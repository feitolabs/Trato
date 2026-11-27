"""Medidas de conta no painel (Termos 20). Permissão `medidas_aplicar`: mediador, líder de
suporte, segurança e administrador."""

from __future__ import annotations

import logging
from datetime import timedelta
from typing import Literal

from fastapi import APIRouter, Depends, Query, Request
from fastapi.responses import JSONResponse
from pydantic import BaseModel, ConfigDict, Field, StrictBool, StrictInt

from trato.api import medidas as regras
from trato.api import medidas_anexos as provas
from trato.api.admin.contexto import (
    AdminContexto,
    Operador,
    exigir,
    obter_admin,
    proteger_conta_da_equipe,
)
from trato.api.admin.modelos import Pagina
from trato.api.admin.papeis import Permissao
from trato.api.contexto import Contexto, obter_contexto
from trato.persistencia.medidas import ABERTAS, Medida
from trato.persistencia.retorno_conta import hmacs_de_identificadores

router = APIRouter(prefix="/v1/admin/medidas", tags=["admin: medidas de conta"])
URL_SEGUNDOS = 300  # link assinado curto
log = logging.getLogger("trato.medidas")

Tipo = Literal[
    "aviso", "restricao", "suspensao", "encerramento", "bloqueio_preventivo", "trava_saque",
    "remocao_conteudo",
]  # fmt: skip


class AplicarIn(BaseModel):
    model_config = ConfigDict(extra="forbid")

    usuario_id: str = Field(max_length=64)
    tipo: Tipo
    motivo: str = Field(min_length=10, max_length=2000, description="O usuário lê (20.4).")
    clausulas: list[str] = Field(min_length=1, max_length=20)
    dias: int | None = Field(None, ge=1, le=3650, strict=True, description="null: sem data final.")
    efeito_pedidos_valores: str = Field(regras.EFEITO_PADRAO, min_length=10, max_length=2000)
    como_contestar: str = Field(regras.COMO_CONTESTAR, min_length=10, max_length=2000)
    detalhe_adiado: bool = False
    justificativa_adiamento: str | None = Field(None, max_length=1000)
    nota_interna: str | None = Field(None, max_length=2000)
    infracao_grave: bool = False
    impedir_nova_conta: bool = False
    sem_falta: StrictBool | None = Field(
        None,
        description="Só em encerramento (13.10): sem falta do usuário. Sem resposta, os "
        "Tratinhos são guardados.",
    )
    identificadores_impedimento: dict[Literal["cpf", "email", "telefone"], str] | None = None
    motivo_fraude: StrictBool = Field(
        False, description="Só em trava_saque: adia a liberação no livro (20.6)."
    )
    limite_retencao_centavos: StrictInt | None = Field(
        None, gt=0, le=10**12, description="Obrigatório com fraude: o prejuízo apurado."
    )


class ReverterIn(BaseModel):
    model_config = ConfigDict(extra="forbid")

    motivo: str = Field(min_length=10, max_length=1000)


class ApagarProvasIn(BaseModel):
    model_config = ConfigDict(extra="forbid")

    motivo: str = Field(min_length=10, max_length=1000)


class ApagarProvasOut(BaseModel):
    resultado: str = Field(description="ok | ja_anonimizada")
    arquivos: int
    removidos: int
    pendentes: int = Field(description="Acima de zero: chame de novo para repetir a remoção.")


class ContestarPorSacIn(BaseModel):
    model_config = ConfigDict(extra="forbid")

    versao: str = Field(min_length=1, max_length=4000)
    anexos: list[str] = Field(default_factory=list, max_length=provas.MAXIMO_DE_ANEXOS)


class AbrirAnexosIn(BaseModel):
    model_config = ConfigDict(extra="forbid")

    motivo: str = Field(min_length=10, max_length=500, description="Vai para a auditoria.")


class AnexoAbertoOut(regras.AnexoDaContestacaoOut):
    url: str
    expira_em_segundos: int


class DecidirMedidaIn(BaseModel):
    model_config = ConfigDict(extra="forbid")

    resultado: Literal["mantida", "alterada", "revertida"]
    resposta: str = Field(min_length=10, max_length=4000)
    dias_a_partir_de_hoje: int | None = Field(
        None, ge=1, le=3650, strict=True, description="Só em `alterada`: novo fim, mais curto."
    )
    mesmo_analista_justificativa: str | None = Field(None, max_length=1000)


class MedidaAdminOut(regras.MedidaOut):
    usuario_id: str
    usuario_nome: str | None = None
    motivo_completo: str
    origem: str
    aplicada_por: str | None = None
    nota_interna: str | None = None
    justificativa_adiamento: str | None = None
    revertida_por: str | None = None
    contestacao_analista_id: str | None = None
    # Nomes só no painel.
    aplicada_por_nome: str | None = None
    contestacao_analista_nome: str | None = None
    infracao_grave: bool = False
    impedir_nova_conta: bool = False
    sem_falta: bool | None = None
    motivo_fraude: bool = False
    limite_retencao_centavos: int | None = None


def _chave(valor: str | None) -> str:
    return str(valor or "").replace("-", "")


def nomes_de(admin: AdminContexto, ids: list[str | None]) -> dict[str, str]:
    """Nomes por id (com ou sem hífen)."""
    procurados = list({i for i in ids if i})
    if admin.usuarios is None or not procurados:
        return {}
    return {_chave(k): v for k, v in admin.usuarios.nomes(procurados).items()}


def _erro(status: int, codigo: str, mensagem: str) -> JSONResponse:
    return JSONResponse(status_code=status, content={"detail": mensagem, "codigo": codigo})


def _indisponivel() -> JSONResponse:
    return _erro(503, "indisponivel", "A tabela de medidas ainda não está disponível.")


def _out(
    contexto: Contexto, admin: AdminContexto, m: Medida, nomes: dict[str, str] | None = None
) -> MedidaAdminOut:
    c = contexto.medidas.contestacao(m.id or "")
    if nomes is None:
        nomes = nomes_de(admin, [m.usuario_id, m.aplicada_por, c.analista_id if c else None])
    return MedidaAdminOut(
        **regras.saida(contexto, m).model_dump(),
        usuario_id=m.usuario_id,
        usuario_nome=nomes.get(_chave(m.usuario_id)),
        aplicada_por_nome=nomes.get(_chave(m.aplicada_por)),
        contestacao_analista_nome=nomes.get(_chave(c.analista_id)) if c else None,
        motivo_completo=m.motivo,
        origem=m.origem,
        aplicada_por=m.aplicada_por,
        nota_interna=m.nota_interna,
        justificativa_adiamento=m.justificativa_adiamento,
        revertida_por=m.revertida_por,
        contestacao_analista_id=c.analista_id if c else None,
        infracao_grave=m.infracao_grave,
        impedir_nova_conta=m.impedir_nova_conta,
        sem_falta=m.sem_falta,
        motivo_fraude=m.motivo_fraude,
        limite_retencao_centavos=m.limite_retencao_centavos,
    )


def _auditar(
    admin: AdminContexto, operador: Operador, acao: str, m: Medida, motivo: str, **depois
) -> None:
    admin.auditoria.registrar(
        ator_id=operador.id,
        acao=f"bloqueio.medida_{acao}",
        entidade="usuarios",
        entidade_id=m.usuario_id,
        antes={},
        depois={"medida": m.protocolo, "tipo": m.tipo} | depois,
        motivo=motivo,
    )


@router.post("", response_model=MedidaAdminOut, status_code=201, summary="Aplicar medida")
def aplicar(
    corpo: AplicarIn,
    operador: Operador = Depends(exigir(Permissao.MEDIDAS_APLICAR)),
    admin: AdminContexto = Depends(obter_admin),
    contexto: Contexto = Depends(obter_contexto),
):
    if not contexto.medidas.disponivel():
        return _indisponivel()
    clausulas = tuple(c.strip() for c in corpo.clausulas if c.strip())
    motivo = corpo.motivo.strip()
    justificativa = (corpo.justificativa_adiamento or "").strip() or None
    if not clausulas or len(motivo) < 10:
        return _erro(422, "dados_incompletos", "Informe o motivo e as cláusulas.")
    if corpo.detalhe_adiado and not justificativa:
        return _erro(422, "falta_justificativa", "Adiar o detalhe exige justificativa (20.4).")
    if corpo.tipo == "encerramento" and corpo.dias is not None:
        return _erro(422, "prazo_invalido", "Encerramento não tem prazo.")
    if corpo.infracao_grave and corpo.tipo != "encerramento":
        return _erro(422, "infracao_grave_invalida", "Infração grave só se aplica a encerramento.")
    if corpo.sem_falta is not None and corpo.tipo != "encerramento":
        return _erro(422, "sem_falta_invalida", "sem_falta só se aplica a encerramento.")
    if corpo.sem_falta and corpo.infracao_grave:
        return _erro(422, "sem_falta_invalida", "Infração grave não é encerramento sem falta.")
    if corpo.impedir_nova_conta and not corpo.infracao_grave:
        return _erro(422, "impedimento_exige_grave", "Impedir nova conta exige infração grave.")
    if corpo.impedir_nova_conta and not contexto.retorno_conta.disponivel():
        return _erro(503, "indisponivel", "Tabela de impedimentos indisponível.")
    if corpo.usuario_id.replace("-", "") == operador.id.replace("-", ""):
        return _erro(403, "propria_conta", "Ninguém aplica medida na própria conta.")
    proteger_conta_da_equipe(admin, operador, corpo.usuario_id)
    if contexto.usuarios.detalhe(corpo.usuario_id) is None:
        return _erro(404, "usuario_nao_encontrado", "Usuário não encontrado.")
    dias, erro = regras.prazo_da_trava(
        contexto, corpo.tipo, corpo.motivo_fraude, corpo.limite_retencao_centavos, corpo.dias
    )
    if erro:
        return _erro(422, "trava_fraude_invalida", erro)
    agora = contexto.agora()
    with contexto.transacao():
        medida, nova = regras.aplicar(
            contexto,
            Medida(
                usuario_id=corpo.usuario_id,
                tipo=corpo.tipo,
                motivo=motivo,
                clausulas=clausulas,
                inicio_em=agora,
                fim_em=agora + timedelta(days=dias) if dias else None,
                motivo_fraude=corpo.motivo_fraude,
                limite_retencao_centavos=corpo.limite_retencao_centavos,
                efeito=corpo.efeito_pedidos_valores.strip(),
                como_contestar=corpo.como_contestar.strip(),
                aplicada_por=operador.id,
                nota_interna=corpo.nota_interna,
                detalhe_adiado=corpo.detalhe_adiado,
                justificativa_adiamento=justificativa,
                infracao_grave=corpo.infracao_grave,
                impedir_nova_conta=corpo.impedir_nova_conta,
                sem_falta=corpo.sem_falta,
            ),
        )
        if nova:
            impedidos = 0
            if corpo.impedir_nova_conta and medida.id:
                det = contexto.usuarios.detalhe(corpo.usuario_id) or {}
                extra = corpo.identificadores_impedimento or {}
                try:
                    pares = hmacs_de_identificadores(
                        cpf=extra.get("cpf") or det.get("cpf"),
                        email=extra.get("email") or det.get("email"),
                        telefone=extra.get("telefone") or det.get("telefone"),
                        exigir_pepper=True,
                    )
                except RuntimeError:
                    return _erro(503, "pepper_ausente", "Segredo de impedimento não configurado.")
                for tipo_id, h in pares:
                    _, criou = contexto.retorno_conta.registrar_impedimento(
                        medida.id, tipo_id, h, operador.id, agora
                    )
                    if criou:
                        impedidos += 1
            _auditar(
                admin,
                operador,
                "aplicada",
                medida,
                motivo[:500],
                infracao_grave=corpo.infracao_grave,
                impedir_nova_conta=corpo.impedir_nova_conta,
                impedimentos_registrados=impedidos,
                sem_falta=corpo.sem_falta,
                motivo_fraude=medida.motivo_fraude,
                limite_retencao_centavos=medida.limite_retencao_centavos,
            )
    saida = _out(contexto, admin, medida)
    return saida if nova else JSONResponse(status_code=200, content=saida.model_dump(mode="json"))


@router.get("", response_model=Pagina[MedidaAdminOut], summary="Medidas aplicadas")
def listar(
    usuario_id: str | None = None,
    tipo: Tipo | None = None,
    vigentes: bool = False,
    contestacao_aberta: bool = False,
    limite: int = Query(20, ge=1, le=100),
    deslocamento: int = Query(0, ge=0),
    _: Operador = Depends(exigir(Permissao.MEDIDAS_APLICAR)),
    admin: AdminContexto = Depends(obter_admin),
    contexto: Contexto = Depends(obter_contexto),
):
    if not contexto.medidas.disponivel():
        return _indisponivel()
    itens, total = contexto.medidas.listar(
        usuario_id=usuario_id,
        tipo=tipo,
        vigentes_em=contexto.agora() if vigentes else None,
        contestacao_aberta=contestacao_aberta,
        limite=limite,
        deslocamento=deslocamento,
    )
    contestacoes = [contexto.medidas.contestacao(m.id or "") for m in itens]
    nomes = nomes_de(
        admin,
        [m.usuario_id for m in itens]
        + [m.aplicada_por for m in itens]
        + [c.analista_id for c in contestacoes if c],
    )
    return Pagina(
        itens=[_out(contexto, admin, m, nomes) for m in itens],
        total=total,
        limite=limite,
        deslocamento=deslocamento,
    )


class TravaFraudeConfigOut(BaseModel):
    prazo_maximo_dias: int = Field(
        description="Máximo de `dias` da trava por fraude (configuração; sem valor, 30)."
    )


@router.get(
    "/trava-fraude",
    response_model=TravaFraudeConfigOut,
    summary="Prazo máximo configurado da trava de saque por fraude",
)
def configuracao_da_trava_por_fraude(
    _: Operador = Depends(exigir(Permissao.MEDIDAS_APLICAR)),
    contexto: Contexto = Depends(obter_contexto),
) -> TravaFraudeConfigOut:
    return TravaFraudeConfigOut(prazo_maximo_dias=contexto.medidas.prazo_maximo_trava_fraude_dias())


@router.get("/{medida_id}", response_model=MedidaAdminOut, summary="Medida")
def ver(
    medida_id: str,
    _: Operador = Depends(exigir(Permissao.MEDIDAS_APLICAR)),
    admin: AdminContexto = Depends(obter_admin),
    contexto: Contexto = Depends(obter_contexto),
):
    if not contexto.medidas.disponivel():
        return _indisponivel()
    medida = contexto.medidas.obter(medida_id)
    if medida is None:
        return _erro(404, "nao_encontrada", "Medida não encontrada.")
    return _out(contexto, admin, medida)


@router.post("/{medida_id}/reverter", response_model=MedidaAdminOut, summary="Reverter a medida")
def reverter(
    medida_id: str,
    corpo: ReverterIn,
    operador: Operador = Depends(exigir(Permissao.MEDIDAS_APLICAR)),
    admin: AdminContexto = Depends(obter_admin),
    contexto: Contexto = Depends(obter_contexto),
):
    if not contexto.medidas.disponivel():
        return _indisponivel()
    medida = contexto.medidas.obter(medida_id)
    if medida is None:
        return _erro(404, "nao_encontrada", "Medida não encontrada.")
    proteger_conta_da_equipe(admin, operador, medida.usuario_id)
    with contexto.transacao():
        if not regras.reverter(contexto, medida, operador.id):
            return _erro(409, "ja_revertida", "Esta medida já foi revertida.")
        _auditar(admin, operador, "revertida", medida, corpo.motivo)
    return _out(contexto, admin, contexto.medidas.obter(medida_id))


@router.post(
    "/{medida_id}/contestacao",
    response_model=MedidaAdminOut,
    summary="Registrar contestação recebida pelo atendimento",
)
def contestar_por_sac(
    medida_id: str,
    corpo: ContestarPorSacIn,
    request: Request,
    operador: Operador = Depends(exigir(Permissao.MEDIDAS_APLICAR)),
    admin: AdminContexto = Depends(obter_admin),
    contexto: Contexto = Depends(obter_contexto),
):
    if not contexto.medidas.disponivel():
        return _indisponivel()
    medida = contexto.medidas.obter(medida_id)
    if medida is None:
        return _erro(404, "nao_encontrada", "Medida não encontrada.")
    versao = corpo.versao.strip()
    try:
        with contexto.transacao():
            _, nova = provas.contestar(
                contexto,
                getattr(request.app.state, "servico_uploads", None),
                medida,
                versao,
                "sac",
                corpo.anexos,
            )
            if nova:
                _auditar(admin, operador, "contestada", medida, "Contestação recebida no SAC.")
    except provas.ErroDeContestacao as erro:
        return _erro(erro.status, erro.codigo, erro.mensagem)
    return _out(contexto, admin, medida)


@router.post(
    "/{medida_id}/contestacao/decisao",
    response_model=MedidaAdminOut,
    summary="Responder a contestação (outro analista quando possível)",
)
def decidir(
    medida_id: str,
    corpo: DecidirMedidaIn,
    operador: Operador = Depends(exigir(Permissao.MEDIDAS_APLICAR)),
    admin: AdminContexto = Depends(obter_admin),
    contexto: Contexto = Depends(obter_contexto),
):
    from dataclasses import replace

    if not contexto.medidas.disponivel():
        return _indisponivel()
    medida = contexto.medidas.obter(medida_id)
    contestacao = contexto.medidas.contestacao(medida_id) if medida else None
    if medida is None or contestacao is None:
        return _erro(404, "nao_encontrada", "Não há contestação desta medida.")
    proteger_conta_da_equipe(admin, operador, medida.usuario_id)  # decidir pode reverter
    if contestacao.status not in ABERTAS:
        return _erro(409, "ja_decidida", "A contestação já foi decidida.")
    mesmo = str(medida.aplicada_por).replace("-", "") == operador.id.replace("-", "")
    justificativa = (corpo.mesmo_analista_justificativa or "").strip()
    if mesmo and len(justificativa) < 10:
        return _erro(
            422,
            "mesmo_analista",
            "Você aplicou a medida: passe a outro analista ou justifique por que não é possível.",
        )
    resposta = corpo.resposta.strip()
    if len(resposta) < 10:
        return _erro(422, "resposta_curta", "Escreva a resposta ao usuário.")
    if (corpo.resultado == "alterada") != (corpo.dias_a_partir_de_hoje is not None):
        return _erro(422, "prazo_invalido", "Informe o novo prazo só quando alterar a medida.")
    agora = contexto.agora()
    novo_fim = None
    if corpo.resultado == "alterada":
        novo_fim = agora + timedelta(days=corpo.dias_a_partir_de_hoje or 0)
        if medida.tipo == "encerramento" or (medida.fim_em and novo_fim >= medida.fim_em):
            return _erro(422, "prazo_invalido", "A alteração precisa encurtar a medida.")
    with contexto.transacao():
        decidida = replace(
            contestacao,
            status=corpo.resultado,
            analista_id=operador.id,
            resposta=resposta,
            mesmo_analista_justificativa=justificativa if mesmo else None,
            decidida_em=agora,
        )
        if not contexto.medidas.decidir_contestacao(decidida):
            return _erro(409, "ja_decidida", "A contestação já foi decidida.")
        if corpo.resultado == "revertida":
            regras.reverter(contexto, medida, operador.id)
        elif novo_fim is not None:
            contexto.medidas.mudar(medida_id, {"fim_em": novo_fim})
        _auditar(
            admin, operador, "contestacao_decidida", medida, resposta[:500],
            resultado=corpo.resultado,
        )  # fmt: skip
        regras.avisar_resposta(contexto, medida, corpo.resultado, resposta)
    return _out(contexto, admin, contexto.medidas.obter(medida_id))


@router.post(
    "/{medida_id}/contestacao/anexos",
    response_model=provas.AnexoParaEnvioOut,
    status_code=201,
    summary="Pedir o envio de uma prova recebida pelo atendimento",
)
def pedir_anexo_por_sac(
    medida_id: str,
    corpo: provas.PedirAnexoIn,
    request: Request,
    operador: Operador = Depends(exigir(Permissao.MEDIDAS_APLICAR)),
    admin: AdminContexto = Depends(obter_admin),
    contexto: Contexto = Depends(obter_contexto),
):
    if not contexto.medidas.disponivel():
        return _indisponivel()
    medida = contexto.medidas.obter(medida_id)
    if medida is None:
        return _erro(404, "nao_encontrada", "Medida não encontrada.")
    try:
        envio = provas.pedir_envio(
            contexto, getattr(request.app.state, "servico_uploads", None), medida, corpo
        )
    except provas.ErroDeContestacao as erro:
        return _erro(erro.status, erro.codigo, erro.mensagem)
    _auditar(admin, operador, "prova_pedida", medida, "Envio de prova pelo atendimento.")
    return envio


@router.post(
    "/{medida_id}/contestacao/anexos/abrir",
    response_model=list[AnexoAbertoOut],
    summary="Abrir as provas da contestação com link curto (acesso auditado)",
)
def abrir_anexos(
    medida_id: str,
    corpo: AbrirAnexosIn,
    request: Request,
    operador: Operador = Depends(exigir(Permissao.MEDIDAS_APLICAR)),
    admin: AdminContexto = Depends(obter_admin),
    contexto: Contexto = Depends(obter_contexto),
):
    motivo = corpo.motivo.strip()
    if len(motivo) < 10:
        return _erro(422, "motivo_invalido", "Explique o motivo do acesso.")
    if not contexto.medidas.disponivel():
        return _indisponivel()
    medida = contexto.medidas.obter(medida_id)
    contestacao = contexto.medidas.contestacao(medida_id) if medida else None
    if medida is None or contestacao is None:
        return _erro(404, "nao_encontrada", "Não há contestação desta medida.")
    servico = getattr(request.app.state, "servico_uploads", None)
    if servico is None:
        return _erro(503, "indisponivel", "O envio de arquivos não está disponível.")
    with contexto.transacao():  # a auditoria vem antes dos links
        admin.auditoria.registrar(
            ator_id=operador.id,
            acao="dado_pessoal.medida_anexos_vistos",
            entidade="usuarios",
            entidade_id=medida.usuario_id,
            antes={},
            depois={"medida": medida.protocolo},
            motivo=motivo,
        )
    return [
        AnexoAbertoOut(
            anexo_id=a["anexo_id"],
            content_type=a["content_type"],
            tamanho_bytes=a["tamanho_bytes"],
            url=servico.armazenamento.url_leitura(a["bucket"], a["caminho"], URL_SEGUNDOS),
            expira_em_segundos=URL_SEGUNDOS,
        )
        for a in contestacao.anexos
    ]


_ANONIMIZAR_ERROS = {
    "nao_encontrada": (404, "Contestação não encontrada."),
    "nao_decidida": (409, "A contestação ainda não foi respondida."),
    "analista_invalido": (403, "Só o encarregado de dados ou o administrador."),
    "indisponivel": (503, "A anonimização ainda não está disponível."),
}


@router.post(
    "/contestacoes/{contestacao_id}/anonimizacao",
    response_model=ApagarProvasOut,
    summary="LGPD: apagar texto e arquivos de uma contestação decidida",
    description=(
        "Nada sai por prazo: é um pedido expresso do encarregado ou do administrador. Se o "
        "armazenamento falhar, repetir a chamada apaga o que faltou (caminhos na auditoria)."
    ),
)
def apagar_provas(
    contestacao_id: str,
    corpo: ApagarProvasIn,
    request: Request,
    operador: Operador = Depends(exigir(Permissao.LGPD_APAGAR_PROVAS)),
    admin: AdminContexto = Depends(obter_admin),
    contexto: Contexto = Depends(obter_contexto),
):
    motivo = corpo.motivo.strip()
    if len(motivo) < 10:
        return _erro(422, "motivo_invalido", "Explique o motivo.")
    if not contexto.medidas.disponivel():
        return _indisponivel()
    servico = getattr(request.app.state, "servico_uploads", None)
    if servico is None:  # sem armazenamento não apaga nem o texto: faz tudo junto
        return _erro(503, "indisponivel", "O armazenamento de arquivos não está disponível.")
    with contexto.transacao():  # o banco audita junto, com os caminhos
        resultado, devolvidos = contexto.medidas.anonimizar_contestacao(
            contestacao_id, operador.id, motivo
        )
        if resultado in _ANONIMIZAR_ERROS:
            status, mensagem = _ANONIMIZAR_ERROS[resultado]
            return _erro(status, resultado, mensagem)
    guardados = contexto.medidas.arquivos_anonimizados(contestacao_id)
    arquivos = list(dict.fromkeys([*devolvidos, *guardados]))
    removidos = 0
    for bucket, caminho in arquivos:
        try:
            servico.armazenamento.remover(bucket, caminho)
            removidos += 1
        except Exception:  # noqa: BLE001 - fica pendente; a repetição tenta de novo
            log.exception("Não consegui apagar uma prova anonimizada")
    admin.auditoria.registrar(
        ator_id=operador.id,
        acao="dado_pessoal.provas_contestacao_removidas",
        entidade="medida_contestacao",
        entidade_id=contestacao_id,
        depois={"arquivos": len(arquivos), "removidos": removidos},
        motivo=motivo,
    )
    return ApagarProvasOut(
        resultado=resultado,
        arquivos=len(arquivos),
        removidos=removidos,
        pendentes=len(arquivos) - removidos,
    )
