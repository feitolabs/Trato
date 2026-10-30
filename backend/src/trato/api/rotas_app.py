"""Rotas que o app pede: orçamentos do pedido, valores do pagamento, mensagens, notificações,
perfil, pedidos abertos, resumo de orçamento, verificação do profissional e avaliação.

Nenhuma regra de dinheiro mora aqui: a taxa vem do `ProvedorTaxa` (configuração) e o app só
pede e mostra. Dados pessoais (documento, telefone, e-mail, endereço exato) nunca saem daqui.
"""

from __future__ import annotations

from datetime import date, datetime, timedelta
from typing import Annotated

from fastapi import APIRouter, Depends, HTTPException, Query, Request
from pydantic import BaseModel, ConfigDict, Field, StrictBool, StrictInt

from trato.api.admin.papeis import Permissao
from trato.api.auth import PapelUsuario, Usuario
from trato.api.contexto import Contexto, exigir_papel, obter_contexto, usuario_atual
from trato.api.repositorios_app import (
    NIVEIS_VERIFICACAO,
    TIPOS_DOCUMENTO,
    Avaliacao,
    DocumentoVerificacao,
)
from trato.api.servicos import carregar_pedido, eh_participante
from trato.pagamentos.custo import ConfigCustoPagamento, MeioPagamento, calcular_custo_stripe
from trato.pedidos.estados import Estado, Pedido
from trato.profissional.config import ORDEM_NIVEIS, obter_config_profissional
from trato.profissional.repositorio import slugs
from trato.seguranca.config import obter_config_seguranca
from trato.seguranca.texto_livre import limpar_etiquetas, limpar_texto

router = APIRouter(prefix="/v1", tags=["app"])


class _Entrada(BaseModel):
    model_config = ConfigDict(extra="forbid")


# --- Saídas -----------------------------------------------------------------------------


class OrcamentoOut(BaseModel):
    id: str
    profissional_id: str
    profissional_nome: str | None
    versao: int
    valor_centavos: int
    prazo_execucao_dias: int | None
    garantia_dias: int | None
    observacoes: str | None
    enviado_em: datetime | None
    aceito: bool


class PagamentoValoresOut(BaseModel):
    pedido_id: str
    estado: str
    valor_centavos: int | None = Field(None, description="Valor do contrato, em centavos.")
    pago_centavos: int = Field(description="O que o ledger mostra como pago (webhook assinado).")
    pagamento_confirmado: bool
    meios_disponiveis: list[str]
    cobranca_pendente_id: str | None = None


class MensagemOut(BaseModel):
    id: int
    autor_id: str
    minha: bool
    texto: str
    mascarada: bool
    enviada_em: datetime
    lida_em: datetime | None


class NotificacaoOut(BaseModel):
    id: str
    tipo: str
    titulo: str
    corpo: str | None
    dados: dict
    criada_em: datetime
    lida: bool


class PerfilOut(BaseModel):
    id: str
    nome: str | None
    papel: str
    status: str
    nivel_verificacao: str | None
    nota_publica: float | None
    servicos_concluidos: int | None
    papeis: list[str] = Field(default_factory=list)
    tem_perfil_profissional: bool = False
    status_verificacao: str | None = Field(
        None, description="Verificação mais recente: enviada, em_analise, aprovada ou recusada."
    )


class PedidoAbertoOut(BaseModel):
    id: str
    titulo: str
    descricao: str
    bairro: str | None
    categoria_id: str | None
    faixa_preco_min_centavos: int | None
    faixa_preco_max_centavos: int | None
    urgente: bool
    prazo_desejado: date | None
    aberto_em: datetime


class ResumoOrcamentoOut(BaseModel):
    valor_centavos: int = Field(description="Bruto: o total do orçamento.")
    taxa_centavos: int = Field(description="Taxa do Trato pela configuração vigente.")
    liquido_centavos: int = Field(description="O que o profissional recebe: bruto menos a taxa.")
    custo_provedor_estimado_centavos: int = Field(
        description="ESTIMATIVA do custo do meio de pagamento (o maior entre Pix e cartão). "
        "Sai da taxa do Trato; não reduz o líquido do profissional."
    )
    custo_provedor_estimativa: bool = True


class VerificacaoOut(BaseModel):
    id: str
    nivel_solicitado: str
    status: str
    enviada_em: datetime
    documentos: list[str] = Field(description="Só os tipos enviados; os arquivos ficam privados.")
    status_app: str = Field(
        description="O que o app mostra: em_analise, aprovado ou pendente (com `motivo`)."
    )
    motivo: str | None = Field(None, description="Por que ficou pendente, quando recusada.")
    finalidade: str = Field(description="Para que os documentos são usados (consentimento LGPD).")
    retencao_dias: int = Field(description="Quanto tempo os documentos ficam guardados.")


class AvaliacaoOut(BaseModel):
    pedido_id: str
    direcao: str
    nota_geral: int
    comentario: str | None
    etiquetas: list[str]
    criada_em: datetime


# --- Entradas ---------------------------------------------------------------------------


class EnviarMensagemIn(_Entrada):
    texto: str = Field(min_length=1, max_length=2000)


class ResumoOrcamentoIn(_Entrada):
    valor_centavos: StrictInt = Field(
        gt=0, le=10**10, description="Total do orçamento, em centavos."
    )


class DocumentoIn(_Entrada):
    tipo: str
    upload_id: str | None = Field(
        None,
        max_length=64,
        description="Id de um envio CONCLUÍDO em `/v1/uploads` (destino `verificacao`).",
    )
    storage_path: str | None = Field(
        None,
        min_length=3,
        max_length=300,
        description="Só sem o serviço de upload ligado: caminho no bucket privado, não uma URL.",
    )


class VerificacaoIn(_Entrada):
    nivel_solicitado: str = "verificado"
    consentimento_lgpd: StrictBool
    documentos: list[DocumentoIn] = Field(min_length=1, max_length=12)


class AvaliarIn(_Entrada):
    nota_geral: StrictInt = Field(ge=1, le=5)
    # Tamanhos finais vêm da configuração (`TRATO_SEG_COMENTARIO_MAX_CHARS` etc.); estes tetos
    # só protegem a validação contra corpo absurdo.
    comentario: str | None = Field(None, max_length=20_000)
    etiquetas: list[str] = Field(default_factory=list, max_length=200)


# --- Acesso -----------------------------------------------------------------------------


def _pedido_visivel(
    contexto: Contexto,
    pedido_id: str,
    usuario: Usuario,
    request: Request | None = None,
    *,
    equipe: tuple[Permissao, ...] = (),
    consulta: str = "pedido",
    com_disputa: bool = False,
) -> Pedido:
    """Como `carregar_pedido`, mas o profissional também vê pedido ABERTO (para orçar/conversar).

    A equipe só passa pela matriz de permissões (`equipe=`); `com_disputa` ainda exige que o
    pedido tenha disputa (o chat só é do mediador que está julgando)."""
    if usuario.papel is PapelUsuario.EQUIPE:
        pedido = carregar_pedido(
            contexto, pedido_id, usuario, request=request, equipe=equipe, consulta=consulta
        )
        if com_disputa and contexto.disputas.obter(pedido.id) is None:
            raise HTTPException(403, "Seu papel na equipe não permite isso.")
        return pedido
    pedido = contexto.pedidos.obter(pedido_id)
    if pedido is None:
        raise HTTPException(404, "Pedido não encontrado.")
    if eh_participante(pedido, usuario):
        return pedido
    if usuario.papel is PapelUsuario.PROFISSIONAL and pedido.estado is Estado.ABERTO:
        return pedido
    raise HTTPException(404, "Pedido não encontrado.")


def _custo_provedor_estimado() -> ConfigCustoPagamento:
    """Custos do provedor ainda são ESTIMATIVAS até haver proposta comercial (P7)."""
    from trato.margem.relatorio import CUSTO_PROVEDOR

    return CUSTO_PROVEDOR


# --- Orçamentos e pagamento -------------------------------------------------------------


@router.get(
    "/pedidos/{pedido_id}/orcamentos",
    response_model=list[OrcamentoOut],
    summary="Orçamentos recebidos pelo pedido",
    description="O cliente (dono) e a equipe veem todos; o profissional vê só o próprio.",
)
def listar_orcamentos(
    pedido_id: str,
    request: Request,
    usuario: Usuario = Depends(usuario_atual),
    contexto: Contexto = Depends(obter_contexto),
) -> list[OrcamentoOut]:
    pedido = _pedido_visivel(
        contexto,
        pedido_id,
        usuario,
        request,
        equipe=(Permissao.PEDIDOS_BUSCAR,),
        consulta="orcamentos",
    )
    itens = contexto.orcamentos.do_pedido(pedido.id)
    if usuario.papel is PapelUsuario.PROFISSIONAL:
        itens = [o for o in itens if o.profissional_id == usuario.id]
    return [
        OrcamentoOut(
            id=o.id,
            profissional_id=o.profissional_id,
            profissional_nome=o.profissional_nome,
            versao=o.versao,
            valor_centavos=o.valor_centavos,
            prazo_execucao_dias=o.prazo_execucao_dias,
            garantia_dias=o.garantia_dias,
            observacoes=o.observacoes,
            enviado_em=o.enviado_em,
            aceito=o.id == pedido.orcamento_id,
        )
        for o in itens
    ]


@router.get(
    "/pedidos/{pedido_id}/pagamento",
    response_model=PagamentoValoresOut,
    summary="Valores do pagamento (o que o app mostra antes de pagar)",
)
def valores_do_pagamento(
    pedido_id: str,
    request: Request,
    usuario: Usuario = Depends(exigir_papel(PapelUsuario.CLIENTE, PapelUsuario.EQUIPE)),
    contexto: Contexto = Depends(obter_contexto),
) -> PagamentoValoresOut:
    pedido = carregar_pedido(
        contexto,
        pedido_id,
        usuario,
        request=request,
        equipe=(Permissao.PAGAMENTOS_VER,),
        consulta="pagamento",
    )
    contrato = contexto.contratos.obter_do_pedido(pedido.id)
    saldo = contexto.ledger.saldos_pedido(pedido.id, pedido.profissional_id)
    servico = getattr(request.app.state, "servico_pagamento", None)
    pendente = None
    if servico is not None:
        pendente = next(
            (
                c.id
                for c in servico.cobrancas.do_pedido(pedido.id)
                if c.status.value == "aguardando"
            ),
            None,
        )
    return PagamentoValoresOut(
        pedido_id=pedido.id,
        estado=pedido.estado.value,
        valor_centavos=contrato.valor_centavos if contrato else None,
        pago_centavos=saldo.cliente_pagou,
        pagamento_confirmado=pedido.referencia_pagamento is not None,
        meios_disponiveis=[m.value for m in MeioPagamento],
        cobranca_pendente_id=pendente,
    )


@router.post(
    "/orcamentos/resumo",
    response_model=ResumoOrcamentoOut,
    summary="Taxa e líquido de um valor (calculadora do profissional)",
    description="Só o backend calcula a taxa, pela configuração vigente. Nada é gravado.",
)
def resumo_do_orcamento(
    corpo: ResumoOrcamentoIn,
    usuario: Usuario = Depends(exigir_papel(PapelUsuario.PROFISSIONAL)),
    contexto: Contexto = Depends(obter_contexto),
) -> ResumoOrcamentoOut:
    if contexto.taxa is None:
        raise HTTPException(503, "A taxa ainda não foi configurada.")
    taxa = min(contexto.taxa.calcular(corpo.valor_centavos), corpo.valor_centavos)
    custo = contexto.extras.get("custo_provedor") or _custo_provedor_estimado()
    return ResumoOrcamentoOut(
        valor_centavos=corpo.valor_centavos,
        taxa_centavos=taxa,
        liquido_centavos=corpo.valor_centavos - taxa,
        custo_provedor_estimado_centavos=max(
            calcular_custo_stripe(corpo.valor_centavos, meio, custo) for meio in MeioPagamento
        ),
    )


# --- Mensagens --------------------------------------------------------------------------


def _conversa_do_pedido(
    contexto: Contexto, pedido: Pedido, usuario: Usuario, profissional_id: str | None
) -> str:
    """Abre (ou acha) a conversa do pedido com UM profissional."""
    if usuario.papel is PapelUsuario.PROFISSIONAL:
        alvo = usuario.id
    else:
        alvo = profissional_id or pedido.profissional_id
        if alvo is None:
            raise HTTPException(422, "Diga com qual profissional você quer conversar.")
        orcou = any(o.profissional_id == alvo for o in contexto.orcamentos.do_pedido(pedido.id))
        if alvo != pedido.profissional_id and not orcou:
            raise HTTPException(404, "Esse profissional não está neste pedido.")
    return contexto.conversas.abrir(pedido.id, alvo)


def _mensagens_out(contexto: Contexto, conversa: str, usuario: Usuario) -> list[MensagemOut]:
    return [
        MensagemOut(
            id=m.id,
            autor_id=m.autor_id,
            minha=m.autor_id == usuario.id,
            texto=m.texto,
            mascarada=m.mascarada,
            enviada_em=m.enviada_em,
            lida_em=m.lida_em,
        )
        for m in contexto.conversas.listar(conversa)
    ]


@router.get(
    "/pedidos/{pedido_id}/mensagens",
    response_model=list[MensagemOut],
    summary="Mensagens do pedido",
    description=(
        "Para o cliente, `profissional_id` escolhe a conversa (sem ele, vale o profissional "
        "contratado). Antes da contratação, e-mail e telefone saem ocultos."
    ),
)
def listar_mensagens(
    pedido_id: str,
    request: Request,
    profissional_id: Annotated[str | None, Query()] = None,
    usuario: Usuario = Depends(usuario_atual),
    contexto: Contexto = Depends(obter_contexto),
) -> list[MensagemOut]:
    pedido = _pedido_visivel(
        contexto,
        pedido_id,
        usuario,
        request,
        equipe=(Permissao.DISPUTAS_DECIDIR,),
        consulta="chat",
        com_disputa=True,
    )
    conversa = _conversa_do_pedido(contexto, pedido, usuario, profissional_id)
    return _mensagens_out(contexto, conversa, usuario)


@router.post(
    "/pedidos/{pedido_id}/mensagens",
    response_model=MensagemOut,
    status_code=201,
    summary="Enviar mensagem no pedido",
)
def enviar_mensagem(
    pedido_id: str,
    corpo: EnviarMensagemIn,
    profissional_id: Annotated[str | None, Query()] = None,
    usuario: Usuario = Depends(exigir_papel(PapelUsuario.CLIENTE, PapelUsuario.PROFISSIONAL)),
    contexto: Contexto = Depends(obter_contexto),
) -> MensagemOut:
    pedido = _pedido_visivel(contexto, pedido_id, usuario)
    if usuario.papel is PapelUsuario.PROFISSIONAL and (
        pedido.profissional_id not in (None, usuario.id)
    ):
        raise HTTPException(404, "Pedido não encontrado.")
    conversa = _conversa_do_pedido(contexto, pedido, usuario, profissional_id)
    nova = contexto.conversas.enviar(conversa, usuario.id, corpo.texto)
    return next(m for m in _mensagens_out(contexto, conversa, usuario) if m.id == nova)


# --- Notificações, perfil, pedidos abertos ----------------------------------------------


@router.get("/notificacoes", response_model=list[NotificacaoOut], summary="Minhas notificações")
def listar_notificacoes(
    nao_lidas: bool = False,
    usuario: Usuario = Depends(exigir_papel(PapelUsuario.CLIENTE, PapelUsuario.PROFISSIONAL)),
    contexto: Contexto = Depends(obter_contexto),
) -> list[NotificacaoOut]:
    return [
        NotificacaoOut(
            id=n.id,
            tipo=n.tipo,
            titulo=n.titulo,
            corpo=n.corpo,
            dados=n.dados,
            criada_em=n.criada_em,
            lida=n.lida_em is not None,
        )
        for n in contexto.notificacoes.listar(usuario.id, nao_lidas)
    ]


# `GET /v1/me`, `PATCH /v1/me` e `GET /v1/profissional/pedidos-abertos`: `rotas_pedido_contrato.py`.


# --- Verificação do profissional --------------------------------------------------------


def _nivel_exigido(request: Request, usuario: Usuario, cfg) -> str:  # type: ignore[no-untyped-def]
    """Nível mínimo pelas categorias do profissional (risco da categoria, em configuração)."""
    modulo = getattr(request.app.state, "modulo_profissional", None)
    perfil = modulo.repo.obter(usuario.id) if modulo else None
    if perfil is None:
        return cfg.verificacao_nivel_padrao
    return cfg.nivel_exigido(slugs(modulo.catalogo, perfil.categorias))


def _documentos_da_verificacao(
    request: Request, corpo: VerificacaoIn, usuario: Usuario, excluir_em: datetime
) -> list[DocumentoVerificacao]:
    servico = getattr(request.app.state, "servico_uploads", None)
    docs: list[DocumentoVerificacao] = []
    usados: set[str] = set()
    for d in corpo.documentos:
        if servico is None:  # sem o serviço de upload: só a referência, como antes
            if d.storage_path is None or not _caminho_valido(d.storage_path, usuario):
                raise HTTPException(422, "O caminho de um arquivo não é válido.")
            docs.append(DocumentoVerificacao(d.tipo, d.storage_path, None, excluir_em))
            continue
        sol = servico.repo.solicitacao(d.upload_id or "")
        guardado = servico.repo.documentos.get(sol.registro_id or "") if sol else None
        if (
            sol is None
            or guardado is None
            or sol.dono_id != usuario.id
            or sol.destino != "verificacao"
            or sol.tipo_documento != d.tipo
            or sol.id in usados
        ):
            raise HTTPException(422, "Um dos arquivos não foi enviado ou não confere com o tipo.")
        usados.add(sol.id)
        docs.append(DocumentoVerificacao(d.tipo, sol.caminho, guardado.sha256, excluir_em))
    return docs


def _caminho_valido(caminho: str, usuario: Usuario) -> bool:
    partes = caminho.split("/")
    if "://" in caminho or ".." in partes or caminho.startswith("/") or "" in partes:
        return False
    if partes[0] == "verificacao":
        partes = partes[1:]
    return len(partes) >= 2 and partes[0] == usuario.id


_STATUS_APP = {"enviada": "em_analise", "em_analise": "em_analise", "aprovada": "aprovado"}


def _verificacao_out(v) -> VerificacaoOut:
    cfg = obter_config_profissional()
    return VerificacaoOut(
        status_app=_STATUS_APP.get(v.status, "pendente"),
        motivo=v.motivo_recusa if v.status == "recusada" else None,
        finalidade=cfg.verificacao_finalidade,
        retencao_dias=cfg.verificacao_retencao_dias,
        id=v.id,
        nivel_solicitado=v.nivel_solicitado,
        status=v.status,
        enviada_em=v.enviada_em,
        documentos=[d.tipo for d in v.documentos],
    )


@router.post(
    "/profissional/verificacao",
    response_model=VerificacaoOut,
    status_code=201,
    summary="Enviar documento e selfie para a verificação",
    description=(
        "Recebe só REFERÊNCIAS dos arquivos (caminho no bucket privado), nunca o arquivo nem "
        "o número do documento. Exige o consentimento LGPD, a frente do documento e a selfie."
    ),
)
def enviar_verificacao(
    corpo: VerificacaoIn,
    request: Request,
    usuario: Usuario = Depends(exigir_papel(PapelUsuario.CLIENTE, PapelUsuario.PROFISSIONAL)),
    contexto: Contexto = Depends(obter_contexto),
) -> VerificacaoOut:
    if not corpo.consentimento_lgpd:
        raise HTTPException(422, "Precisamos do seu consentimento para tratar seus documentos.")
    if corpo.nivel_solicitado not in NIVEIS_VERIFICACAO:
        raise HTTPException(422, "Nível de verificação inválido.")
    cfg = obter_config_profissional()
    exigido = _nivel_exigido(request, usuario, cfg)
    if ORDEM_NIVEIS.index(corpo.nivel_solicitado) < ORDEM_NIVEIS.index(exigido):
        raise HTTPException(422, f"Para as suas categorias é preciso o nível {exigido}.")
    tipos = {d.tipo for d in corpo.documentos}
    if not tipos <= set(TIPOS_DOCUMENTO):
        raise HTTPException(422, "Tipo de documento inválido.")
    faltam = set(cfg.verificacao_documentos_obrigatorios[corpo.nivel_solicitado]) - tipos
    if faltam:
        raise HTTPException(422, f"Faltam documentos: {', '.join(sorted(faltam))}.")
    agora = contexto.agora()
    excluir_em = agora + timedelta(days=cfg.verificacao_retencao_dias)
    docs = _documentos_da_verificacao(request, corpo, usuario, excluir_em)
    nova = contexto.verificacoes.enviar(usuario.id, corpo.nivel_solicitado, docs, agora)
    return _verificacao_out(nova)


@router.get(
    "/profissional/verificacao",
    response_model=list[VerificacaoOut],
    summary="Minhas verificações",
)
def minhas_verificacoes(
    usuario: Usuario = Depends(exigir_papel(PapelUsuario.CLIENTE, PapelUsuario.PROFISSIONAL)),
    contexto: Contexto = Depends(obter_contexto),
) -> list[VerificacaoOut]:
    return [_verificacao_out(v) for v in contexto.verificacoes.da_pessoa(usuario.id)]


# --- Avaliação --------------------------------------------------------------------------


@router.post(
    "/pedidos/{pedido_id}/avaliacao",
    response_model=AvaliacaoOut,
    status_code=201,
    summary="Avaliar o serviço concluído",
    description="Cliente avalia o profissional e o profissional avalia o cliente, uma vez cada.",
)
def avaliar(
    pedido_id: str,
    corpo: AvaliarIn,
    usuario: Usuario = Depends(exigir_papel(PapelUsuario.CLIENTE, PapelUsuario.PROFISSIONAL)),
    contexto: Contexto = Depends(obter_contexto),
) -> AvaliacaoOut:
    pedido = carregar_pedido(contexto, pedido_id, usuario)
    if pedido.estado is not Estado.CONCLUIDO:
        raise HTTPException(409, "Só dá para avaliar depois que o serviço for concluído.")
    if usuario.papel is PapelUsuario.CLIENTE:
        direcao, avaliado = "cliente_para_profissional", pedido.profissional_id
    else:
        direcao, avaliado = "profissional_para_cliente", pedido.cliente_id
    if avaliado is None:
        raise HTTPException(409, "Este pedido não tem profissional contratado.")
    if contexto.avaliacoes.obter(pedido.id, direcao) is not None:
        raise HTTPException(409, "Você já avaliou este serviço.")
    cfg_seg = obter_config_seguranca()
    comentario = (
        limpar_texto(corpo.comentario, "comentário", cfg_seg.comentario_max_chars, cfg_seg) or None
        if corpo.comentario
        else None
    )
    etiquetas = limpar_etiquetas(corpo.etiquetas, cfg_seg)
    nova = Avaliacao(
        pedido_id=pedido.id,
        direcao=direcao,
        avaliador_id=usuario.id,
        avaliado_id=avaliado,
        nota_geral=corpo.nota_geral,
        comentario=comentario,
        etiquetas=etiquetas,
        criada_em=contexto.agora(),
    )
    contexto.avaliacoes.salvar(nova)
    return AvaliacaoOut(
        pedido_id=nova.pedido_id,
        direcao=nova.direcao,
        nota_geral=nova.nota_geral,
        comentario=nova.comentario,
        etiquetas=list(nova.etiquetas),
        criada_em=nova.criada_em,
    )
