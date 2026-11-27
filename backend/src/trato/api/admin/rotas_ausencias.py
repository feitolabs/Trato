"""Análise de "Cliente ausente" (Termos 7.6 e 7.4).

Ver: permissão `disputas_ver`; decidir: `disputas_decidir`.

Justificativa aceita: o pedido segue agendado para remarcar sem custo. Recusada ou sem
justificativa no prazo: cancelamento. Sem retenção, reembolso integral na hora. Com retenção
(custos comprovados, até 30% do serviço, fora dos 7 dias), primeiro é MOSTRADA ao cliente
(`/decisao`) e só depois confirmada (`/confirmar`).
"""

from __future__ import annotations

from dataclasses import replace
from datetime import datetime
from typing import Any, Literal

from fastapi import APIRouter, Depends, HTTPException, Request
from pydantic import BaseModel, ConfigDict, Field

from trato.api import ausencia_base as ausencia
from trato.api.admin.contexto import AdminContexto, Operador, exigir, obter_admin
from trato.api.admin.papeis import Permissao
from trato.api.avisos import avisar_partes
from trato.api.contexto import Contexto, obter_contexto
from trato.financeiro.ledger import CUSTODIA, Livro, custo_parcelamento_em_aberto
from trato.notificacoes.eventos import Evento
from trato.pedidos import estados
from trato.pedidos.estados import Acao, Estado, Pedido
from trato.persistencia.ausencias import (
    ACEITA,
    AGUARDANDO_JUSTIFICATIVA,
    EM_ANALISE,
    EXPIRADA,
    PENDENTES,
    RECUSADA,
    Ausencia,
)
from trato.persistencia.cancelamentos import PROPOSTA, Cancelamento
from trato.persistencia.chamados import ABERTA
from trato.rotinas.regras import SISTEMA
from trato.seguranca.upload import ErroUpload
from trato.uploads.servico import SolicitacaoInvalida, UploadNegado

router = APIRouter(prefix="/v1/admin/ausencias", tags=["admin: cliente ausente"])


class DecisaoAusenciaIn(BaseModel):
    model_config = ConfigDict(extra="forbid")

    aceitar_justificativa: bool
    justificativa: str = Field(min_length=10, max_length=1000, description="Motivo da decisão.")
    retencao_centavos: int = Field(0, ge=0, strict=True)
    retencao_justificativa: str | None = Field(None, max_length=1000)
    retencao_comprovantes: list[str] = Field(default_factory=list, max_length=10)


class ConfirmarIn(BaseModel):
    model_config = ConfigDict(extra="forbid")

    motivo: str = Field(min_length=10, max_length=1000, description="Vai para a auditoria.")
    retirar_retencao: bool = Field(False, description="Cancela devolvendo tudo ao cliente.")


class AnexosIn(BaseModel):
    model_config = ConfigDict(extra="forbid")

    motivo: str = Field(min_length=10, max_length=500, description="Vai para a auditoria.")


class RevisaoIn(BaseModel):
    model_config = ConfigDict(extra="forbid")

    resultado: Literal["mantida", "alterada", "revertida"]
    resposta: str = Field(min_length=10, max_length=2000, description="Resposta fundamentada.")
    retencao_centavos: int | None = Field(
        None, gt=0, strict=True, description="Só em `alterada`: menor que a atual."
    )


def _com_nomes(contexto: Contexto, admin: AdminContexto, item: Ausencia) -> ausencia.AusenciaOut:
    """Número do pedido e nomes para o painel (quando os repositórios administrativos existem)."""
    out = ausencia.saida(contexto, item)
    extra: dict = {}
    if admin.pedidos is not None:
        rotulo = admin.pedidos.rotulos([item.pedido_id]).get(item.pedido_id)
        extra["pedido_numero"] = rotulo[0] if rotulo else None
    if admin.usuarios is not None:
        nomes = admin.usuarios.nomes([item.cliente_id, item.profissional_id])
        extra["cliente_nome"] = nomes.get(item.cliente_id)
        extra["profissional_nome"] = nomes.get(item.profissional_id)
    return out.model_copy(update=extra)


def _caso(contexto: Contexto, pedido_id: str) -> tuple[Pedido, Ausencia]:
    pedido = contexto.pedidos.obter(pedido_id)
    item = ausencia.do_pedido(contexto, pedido) if pedido else None
    if pedido is None or item is None:
        raise HTTPException(404, "Este pedido não tem caso de cliente ausente.")
    return pedido, item


@router.get("", response_model=list[ausencia.AusenciaOut], summary="Fila de ausências")
def fila(
    _: Operador = Depends(exigir(Permissao.DISPUTAS_VER)),
    admin: AdminContexto = Depends(obter_admin),
    contexto: Contexto = Depends(obter_contexto),
) -> list[ausencia.AusenciaOut]:
    abertos = []
    for item in contexto.ausencias.fila(PENDENTES):
        pedido = contexto.pedidos.obter(item.pedido_id)
        # Cancelado, remarcado ou já iniciado não é mais caso a decidir.
        if pedido and pedido.estado is Estado.AGENDADO and ausencia.do_pedido(contexto, pedido):
            abertos.append(_com_nomes(contexto, admin, item))
    return abertos


@router.get("/{pedido_id}", response_model=ausencia.AusenciaOut, summary="Detalhe do caso")
def detalhe(
    pedido_id: str,
    _: Operador = Depends(exigir(Permissao.DISPUTAS_VER)),
    admin: AdminContexto = Depends(obter_admin),
    contexto: Contexto = Depends(obter_contexto),
) -> ausencia.AusenciaOut:
    return _com_nomes(contexto, admin, _caso(contexto, pedido_id)[1])


def _barrar_retencao_de_bloqueado(contexto: Contexto, pedido: Pedido, saida: str) -> None:
    """Termos 20.6: cliente com a conta bloqueada não paga custo de cancelamento. Dentro da
    transação do caso, a leitura segura a conta até o fim (bloqueio e decisão não se cruzam)."""
    if contexto.medidas.conta_bloqueada_travada(pedido.cliente_id):
        raise HTTPException(
            409,
            "A conta do cliente está bloqueada: não há retenção por ausência (Termos 20.6). "
            f"{saida}",
        )


def _teto_retencao(contexto: Contexto, pedido: Pedido) -> tuple[int, int]:
    """(valor do serviço, retenção máxima): nunca mais que 30% nem que o dinheiro retido."""
    contrato = contexto.contratos.obter_do_pedido(pedido.id)
    base = contrato.valor_centavos if contrato else 0
    bps = min(3000, contexto.config.carregar().ausencia_retencao_max_bps)
    retido = contexto.ledger.saldo_da_conta(CUSTODIA, pedido.id)
    return base, min(base * bps // 10_000, retido)


def _cancelar(
    request: Request, contexto: Contexto, pedido: Pedido, retencao: int
) -> tuple[Pedido, int]:
    """Cancela e move o dinheiro pelo caminho único (ledger, ordens de estorno e repasse)."""
    servico = getattr(request.app.state, "servico_pagamento", None)
    if servico is None:
        raise HTTPException(503, "O serviço de pagamento não está ligado.")
    transicao = estados.transicionar(
        pedido,
        Acao.CANCELAR_CLIENTE_AUSENTE,
        SISTEMA,
        contexto.agora(),
        prazos=contexto.config.carregar().prazos_pedido,
    )
    gravado = contexto.pedidos.salvar(transicao.pedido, transicao.evento)
    for gancho in contexto.apos_transicao:  # cancela cobranças pendentes e avisa
        gancho(pedido, gravado, Acao.CANCELAR_CLIENTE_AUSENTE, contexto)
    livro = Livro()
    antigos = contexto.ledger.lancamentos(pedido.id)
    if antigos:
        livro.lancar_varios(antigos)
    custo = custo_parcelamento_em_aberto(livro, pedido.id)
    devolver = contexto.ledger.saldo_da_conta(CUSTODIA, pedido.id) + custo - retencao
    if devolver > 0:
        servico.aplicar_dinheiro(
            contexto,
            gravado,
            operacao="ausencia_cliente",
            devolver_ao_cliente=devolver,
            repartir=retencao > 0,
            gatilho="decisao_disputa",
            incluir_custo=custo > 0,
        )
    return gravado, max(devolver, 0)


def _auditar(
    admin: AdminContexto, operador: Operador, pedido_id: str, motivo: str, **dados
) -> None:
    admin.auditoria.registrar(
        ator_id=operador.id,
        acao="financeiro.ausencia_cliente_decidida",
        entidade="pedidos",
        entidade_id=pedido_id,
        antes={},
        depois=dados,
        motivo=motivo,
    )


@router.post(
    "/{pedido_id}/decisao",
    response_model=ausencia.AusenciaOut,
    summary="Decidir a ausência do cliente",
)
def decidir(
    pedido_id: str,
    corpo: DecisaoAusenciaIn,
    request: Request,
    operador: Operador = Depends(exigir(Permissao.DISPUTAS_DECIDIR)),
    admin: AdminContexto = Depends(obter_admin),
    contexto: Contexto = Depends(obter_contexto),
) -> ausencia.AusenciaOut:
    r = corpo.retencao_centavos
    motivo_retencao = (corpo.retencao_justificativa or "").strip()
    comprovantes = tuple(c.strip() for c in corpo.retencao_comprovantes if c.strip())
    if r and corpo.aceitar_justificativa:
        raise HTTPException(422, "Justificativa aceita não tem retenção.")
    if r and (len(motivo_retencao) < 10 or not comprovantes):
        raise HTTPException(
            422, "A retenção exige a justificativa e o comprovante dos custos (Termos 7.4)."
        )
    with ausencia.uma_por_vez(contexto, pedido_id):
        pedido, item = _caso(contexto, pedido_id)
        servico_arquivos = getattr(request.app.state, "servico_uploads", None)
        if r and servico_arquivos is not None:
            for arquivo in comprovantes:
                if not ausencia.eh_comprovante(servico_arquivos, pedido, arquivo):
                    raise HTTPException(
                        422,
                        "O comprovante precisa ser um arquivo deste pedido enviado pelo "
                        "profissional ou pela equipe (não vale o do cliente nem o do chat).",
                    )
        agora = contexto.agora()
        if pedido.estado is not Estado.AGENDADO:
            raise HTTPException(409, "O pedido não está mais agendado: nada a decidir.")
        sem_resposta = item.status == AGUARDANDO_JUSTIFICATIVA and agora > item.justificativa_ate
        if item.status != EM_ANALISE and not sem_resposta:
            raise HTTPException(
                409, "Caso já decidido ou ainda dentro do prazo do cliente para justificar."
            )
        if corpo.aceitar_justificativa and sem_resposta:
            raise HTTPException(409, "Não há justificativa para aceitar.")
        if r:
            _barrar_retencao_de_bloqueado(
                contexto, pedido, "Decida sem retenção: o valor pago volta por inteiro."
            )
            from trato.api import desistencia  # importa as rotas do pedido: só na hora

            _, _, dentro = desistencia.prazo(contexto, pedido)
            if dentro:
                raise HTTPException(
                    409, "Dentro dos 7 dias do arrependimento não há retenção (Termos 7.4)."
                )
            base, maximo = _teto_retencao(contexto, pedido)
            if r > maximo:
                raise HTTPException(422, f"A retenção máxima é de {maximo} centavos (30%).")
        status = ACEITA if corpo.aceitar_justificativa else (EXPIRADA if sem_resposta else RECUSADA)
        novo = replace(
            item,
            status=status,
            analista_id=operador.id,
            decisao=corpo.justificativa,
            decidido_em=agora,
        )
        if not contexto.ausencias.mudar(novo, (item.status,)):
            raise HTTPException(409, "O caso mudou. Atualize e confira.")
        reembolso = None
        if status != ACEITA:
            if not r:
                _, reembolso = _cancelar(request, contexto, pedido, 0)
            contexto.cancelamentos.descartar_proposta(pedido.id)  # de um horário anterior
            contexto.cancelamentos.registrar(
                Cancelamento(
                    pedido_id=pedido.id,
                    solicitado_por=operador.id,
                    papel="analista",
                    tipo="cliente_ausente",
                    status=PROPOSTA if r else "cancelado_sem_retencao",
                    recebido_em=agora,
                    motivo=corpo.justificativa,
                    reembolso_centavos=reembolso,
                    retencao_centavos=r,
                    retencao_base_centavos=base if r else None,
                    retencao_justificativa=motivo_retencao if r else None,
                    retencao_comprovantes=comprovantes if r else (),
                    retencao_mostrada_em=agora if r else None,
                )
            )
        if status == ACEITA:
            texto = "Sua justificativa foi aceita. Remarque o serviço sem custo."
        elif r:
            texto = (
                f"O analista propõe cancelar retendo R$ {r / 100:.2f} por custos comprovados. "
                "Veja no pedido; você tem 5 dias úteis para contestar."
            )
        else:
            texto = "O pedido foi cancelado e o valor pago volta por inteiro."
        avisar_partes(
            contexto,
            Evento.AUSENCIA_DECIDIDA,
            (pedido.cliente_id, pedido.profissional_id),
            pedido_id=pedido.id,
            chave=f"{pedido.id}:ausencia_decisao:{int(item.janela_inicio.timestamp())}",
            corpo=texto,
        )
        _auditar(
            admin, operador, pedido.id, corpo.justificativa,
            status=status, retencao_centavos=r, reembolso_centavos=reembolso,
        )  # fmt: skip
    return _com_nomes(contexto, admin, novo)


@router.post(
    "/{pedido_id}/confirmar",
    response_model=ausencia.AusenciaOut,
    summary="Confirmar o cancelamento com a retenção já mostrada ao cliente",
)
def confirmar(
    pedido_id: str,
    request: Request,
    corpo: ConfirmarIn,
    operador: Operador = Depends(exigir(Permissao.DISPUTAS_DECIDIR)),
    admin: AdminContexto = Depends(obter_admin),
    contexto: Contexto = Depends(obter_contexto),
) -> ausencia.AusenciaOut:
    with ausencia.uma_por_vez(contexto, pedido_id):
        pedido = contexto.pedidos.obter(pedido_id)
        caso = contexto.cancelamentos.do_pedido(pedido_id)
        if pedido is None or caso is None or caso.tipo != "cliente_ausente":
            raise HTTPException(404, "Não há retenção proposta para este pedido.")
        item = ausencia.do_pedido(contexto, pedido)
        # A proposta só vale para o horário em que o caso foi decidido.
        if (
            caso.status != PROPOSTA
            or pedido.estado is not Estado.AGENDADO
            or item is None
            or item.status not in (RECUSADA, EXPIRADA)
        ):
            raise HTTPException(409, "Não há retenção esperando confirmação.")
        revisao = ausencia.revisao_de(contexto, caso)
        if revisao is not None and revisao.status == ABERTA:
            raise HTTPException(
                409, "Há uma contestação aberta: nada é cobrado até outro analista responder."
            )
        retirar = corpo.retirar_retencao
        retencao = 0 if retirar else caso.retencao_centavos
        if retencao:
            _barrar_retencao_de_bloqueado(
                contexto,
                pedido,
                "Confirme retirando a retenção (retirar_retencao): o valor pago volta por inteiro.",
            )
        _, maximo = _teto_retencao(contexto, pedido)
        if retencao > maximo:
            raise HTTPException(409, "O valor retido do pedido mudou: confira antes de confirmar.")
        if retencao and revisao is None:
            ate = ausencia.contestar_ate(contexto, caso.retencao_mostrada_em)
            if contexto.agora() <= ate:
                raise HTTPException(
                    409,
                    f"O cliente ainda pode contestar até {ate:%d/%m/%Y}. Antes disso só é "
                    "possível retirar a retenção.",
                )
        _, reembolso = _cancelar(request, contexto, pedido, retencao)
        contexto.cancelamentos.confirmar_retencao(pedido.id, reembolso, retirar)
        avisar_partes(
            contexto,
            Evento.AUSENCIA_DECIDIDA,
            (pedido.cliente_id, pedido.profissional_id),
            pedido_id=pedido.id,
            chave=f"{pedido.id}:ausencia_confirmada:{int(item.janela_inicio.timestamp())}",
            corpo="O pedido foi cancelado. O valor pago volta por inteiro."
            if retirar
            else "O pedido foi cancelado. O valor pago, menos a retenção mostrada, volta a você.",
        )
        _auditar(
            admin, operador, pedido.id, corpo.motivo,
            retencao_centavos=retencao, reembolso_centavos=reembolso,
        )  # fmt: skip
    return _com_nomes(contexto, admin, item)


@router.post(
    "/{pedido_id}/contestacao/decisao",
    response_model=ausencia.AusenciaOut,
    summary="Responder a contestação da retenção (outro analista)",
)
def decidir_contestacao(
    pedido_id: str,
    corpo: RevisaoIn,
    operador: Operador = Depends(exigir(Permissao.DISPUTAS_DECIDIR)),
    admin: AdminContexto = Depends(obter_admin),
    contexto: Contexto = Depends(obter_contexto),
) -> ausencia.AusenciaOut:
    resposta = corpo.resposta.strip()
    if len(resposta) < 10:
        raise HTTPException(422, "Escreva a resposta fundamentada.")
    if (corpo.resultado == "alterada") != (corpo.retencao_centavos is not None):
        raise HTTPException(422, "Informe o novo valor só quando alterar a retenção.")
    with ausencia.uma_por_vez(contexto, pedido_id):
        pedido, item = _caso(contexto, pedido_id)
        caso = ausencia.caso_de(contexto, pedido.id)
        revisao = ausencia.revisao_de(contexto, caso)
        if caso is None or revisao is None or revisao.status != ABERTA:
            raise HTTPException(409, "Não há contestação aberta neste pedido.")
        if str(item.analista_id).replace("-", "") == operador.id.replace("-", ""):
            raise HTTPException(403, "Quem decidiu a ausência não responde a contestação (8.7).")
        novo = caso.retencao_centavos
        if corpo.resultado == "revertida":
            novo = 0
        elif corpo.resultado == "alterada":
            novo = corpo.retencao_centavos or 0
            if novo >= caso.retencao_centavos:
                raise HTTPException(422, "A nova retenção precisa ser menor que a contestada.")
        agora = contexto.agora()
        if not contexto.chamados.decidir_revisao(
            revisao, corpo.resultado, operador.id, resposta, agora
        ):
            raise HTTPException(409, "A contestação mudou. Atualize e confira.")
        contexto.cancelamentos.ajustar_retencao(pedido.id, novo)
        avisar_partes(
            contexto,
            Evento.AUSENCIA_DECIDIDA,
            (pedido.cliente_id, pedido.profissional_id),
            pedido_id=pedido.id,
            chave=f"{pedido.id}:contestacao_decidida:{revisao.id}",
            corpo=f"A contestação foi respondida ({corpo.resultado}). Veja no pedido.",
        )
        _auditar(
            admin, operador, pedido.id, resposta,
            contestacao=corpo.resultado, retencao_antes=caso.retencao_centavos,
            retencao_centavos=novo,
        )  # fmt: skip
    return _com_nomes(contexto, admin, item)


@router.post(
    "/{pedido_id}/anexos",
    response_model=list[ausencia.AnexoOut],
    summary="Provas do caso com link assinado curto (acesso auditado)",
    description="É POST para o motivo ir no corpo (não fica em log de URL).",
)
def anexos(
    pedido_id: str,
    request: Request,
    corpo: AnexosIn,
    operador: Operador = Depends(exigir(Permissao.DISPUTAS_VER)),
    admin: AdminContexto = Depends(obter_admin),
    contexto: Contexto = Depends(obter_contexto),
) -> list[ausencia.AnexoOut]:
    motivo = corpo.motivo.strip()
    if len(motivo) < 10:
        raise HTTPException(422, "Explique o motivo do acesso.")
    pedido, item = _caso(contexto, pedido_id)
    servico = getattr(request.app.state, "servico_uploads", None)
    if servico is None:
        raise HTTPException(503, "O envio de arquivos não está disponível.")
    achados = ausencia.anexos_do_caso(contexto, servico, pedido, item)
    with contexto.transacao():  # os links só saem depois de a auditoria gravar quais foram
        admin.auditoria.registrar(
            ator_id=operador.id,
            acao="dado_pessoal.ausencia_anexos_vistos",
            entidade="pedidos",
            entidade_id=pedido.id,
            antes={},
            depois={"arquivos": [a.arquivo_id for a in achados if a.url]},
            motivo=motivo,
        )
    return achados


# --- comprovante da retenção: listar os arquivos do pedido ou enviar um novo (8.7) ---------------

_TIPOS_DE_ENVIO = ("image/jpeg", "image/png", "image/webp")  # o que o bucket do pedido aceita


class EnviarComprovanteIn(AnexosIn):
    nome_arquivo: str = Field(min_length=1, max_length=200)
    content_type: str = Field(max_length=100, description="image/jpeg, png ou webp.")
    tamanho_bytes: int = Field(gt=0, strict=True)


class ComprovanteOut(BaseModel):
    arquivo_id: str = Field(description="Use em `retencao_comprovantes`.")
    finalidade: str
    enviado_por: str = Field(description="profissional | equipe")
    content_type: str | None = None
    tamanho_bytes: int
    enviado_em: datetime
    url: str
    expira_em_segundos: int


class EnvioDeComprovanteOut(BaseModel):
    envio_id: str
    url: str = Field(description="Envie o arquivo (PUT) para este link e depois conclua.")
    expira_em_segundos: int


def _servico_de_arquivos(request: Request) -> Any:
    servico = getattr(request.app.state, "servico_uploads", None)
    if servico is None:
        raise HTTPException(503, "O envio de arquivos não está disponível.")
    return servico


def _motivo(corpo: AnexosIn) -> str:
    motivo = corpo.motivo.strip()
    if len(motivo) < 10:
        raise HTTPException(422, "Explique o motivo do acesso.")
    return motivo


def _comprovante(servico: Any, pedido: Pedido, m: Any) -> ComprovanteOut:
    do_profissional = str(m.enviada_por).replace("-", "") == str(pedido.profissional_id).replace(
        "-", ""
    )
    return ComprovanteOut(
        arquivo_id=m.id,
        finalidade=m.finalidade,
        enviado_por="profissional" if do_profissional else "equipe",
        content_type=m.mime,
        tamanho_bytes=m.tamanho_bytes,
        enviado_em=m.criada_em,
        url=servico.armazenamento.url_leitura(m.bucket, m.storage_path, ausencia.URL_SEGUNDOS),
        expira_em_segundos=ausencia.URL_SEGUNDOS,
    )


def _registrar_acesso(
    admin: AdminContexto, operador: Operador, pedido_id: str, acao: str, motivo: str, **depois
) -> None:
    admin.auditoria.registrar(
        ator_id=operador.id,
        acao=acao,
        entidade="pedidos",
        entidade_id=pedido_id,
        antes={},
        depois=depois,
        motivo=motivo,
    )


@router.post(
    "/{pedido_id}/arquivos",
    response_model=list[ComprovanteOut],
    summary="Arquivos do pedido que servem de comprovante (acesso auditado)",
)
def listar_comprovantes(
    pedido_id: str,
    corpo: AnexosIn,
    request: Request,
    operador: Operador = Depends(exigir(Permissao.DISPUTAS_DECIDIR)),
    admin: AdminContexto = Depends(obter_admin),
    contexto: Contexto = Depends(obter_contexto),
) -> list[ComprovanteOut]:
    motivo = _motivo(corpo)
    pedido, _ = _caso(contexto, pedido_id)
    servico = _servico_de_arquivos(request)
    achados = ausencia.comprovantes_possiveis(servico, pedido)
    with contexto.transacao():  # a auditoria vem antes dos links
        _registrar_acesso(
            admin, operador, pedido.id, "dado_pessoal.ausencia_arquivos_listados", motivo,
            arquivos=[m.id for m in achados],
        )  # fmt: skip
    return [_comprovante(servico, pedido, m) for m in achados]


@router.post(
    "/{pedido_id}/arquivos/envio",
    response_model=EnvioDeComprovanteOut,
    status_code=201,
    summary="Pedir o envio de um comprovante novo",
)
def pedir_comprovante(
    pedido_id: str,
    corpo: EnviarComprovanteIn,
    request: Request,
    operador: Operador = Depends(exigir(Permissao.DISPUTAS_DECIDIR)),
    admin: AdminContexto = Depends(obter_admin),
    contexto: Contexto = Depends(obter_contexto),
) -> EnvioDeComprovanteOut:
    motivo = _motivo(corpo)
    pedido, _ = _caso(contexto, pedido_id)
    servico = _servico_de_arquivos(request)
    if corpo.content_type.split(";")[0].strip().lower() not in _TIPOS_DE_ENVIO:
        raise HTTPException(422, "Envie o comprovante como foto (JPG, PNG ou WebP).")
    try:
        with contexto.transacao():
            solicitacao, url = servico.pedir(
                operador.id,
                "disputa",
                corpo.content_type,
                corpo.tamanho_bytes,
                corpo.nome_arquivo,
                pedido_id=pedido.id,
            )
            _registrar_acesso(
                admin, operador, pedido.id, "financeiro.ausencia_comprovante_pedido", motivo,
                envio=solicitacao.id,
            )  # fmt: skip
    except ErroUpload as erro:
        raise HTTPException(422, str(erro)) from None
    return EnvioDeComprovanteOut(
        envio_id=solicitacao.id, url=url, expira_em_segundos=servico.config.url_envio_segundos
    )


@router.post(
    "/{pedido_id}/arquivos/envio/{envio_id}/concluir",
    response_model=ComprovanteOut,
    summary="Conferir e registrar o comprovante enviado",
)
def concluir_comprovante(
    pedido_id: str,
    envio_id: str,
    corpo: AnexosIn,
    request: Request,
    operador: Operador = Depends(exigir(Permissao.DISPUTAS_DECIDIR)),
    admin: AdminContexto = Depends(obter_admin),
    contexto: Contexto = Depends(obter_contexto),
) -> ComprovanteOut:
    motivo = _motivo(corpo)
    pedido, _ = _caso(contexto, pedido_id)
    servico = _servico_de_arquivos(request)
    solicitacao = servico.repo.solicitacao(envio_id)
    if solicitacao is None or str(solicitacao.pedido_id).replace("-", "") != pedido.id.replace(
        "-", ""
    ):
        raise HTTPException(404, "Envio não encontrado neste pedido.")
    try:
        feita = servico.concluir(operador.id, envio_id)
    except UploadNegado as erro:  # só quem pediu o envio conclui
        raise HTTPException(404, str(erro)) from None
    except SolicitacaoInvalida as erro:
        raise HTTPException(erro.status, str(erro)) from None
    midia = servico.repo.midia(feita.registro_id or "")
    if midia is None:
        raise HTTPException(409, "O arquivo ainda não foi registrado. Tente de novo.")
    with contexto.transacao():
        _registrar_acesso(
            admin, operador, pedido.id, "financeiro.ausencia_comprovante_enviado", motivo,
            arquivo=midia.id,
        )  # fmt: skip
    return _comprovante(servico, pedido, midia)
