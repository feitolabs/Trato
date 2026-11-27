"""Contestações da decisão de disputa no painel (Termos 8.7)."""

from __future__ import annotations

from collections.abc import Callable
from datetime import datetime
from typing import Literal

from fastapi import APIRouter, Depends, Query, Request, Response
from pydantic import BaseModel, ConfigDict, Field

from trato.api import contestacao_disputa as regras
from trato.api.admin.contexto import AdminContexto, Operador, exigir, obter_admin
from trato.api.admin.modelos import Pagina
from trato.api.admin.papeis import PapelEquipe, Permissao
from trato.api.contexto import Contexto, obter_contexto
from trato.persistencia.contestacoes_decisao import PENDENTES, ContestacaoDecisao

router = APIRouter(prefix="/v1/admin/contestacoes-disputa", tags=["admin: contestação da decisão"])

Status = Literal["aberta", "em_analise", "aguardando_aprovacao", "mantida", "alterada", "revertida"]
Resultado = Literal["mantida", "alterada", "revertida"]
NovaDecisao = Literal["liberar_tudo", "reembolso_total", "reembolso_parcial", "nova_visita"]
Efeito = Literal["nenhum", "pendente_financeiro", "executado"]


class _Corpo(BaseModel):
    model_config = ConfigDict(extra="forbid", str_strip_whitespace=True)


class RegistrarPeloSacIn(_Corpo):
    pedido_id: str = Field(max_length=64)
    contestante_id: str = Field(max_length=64)
    chamado_id: str = Field(
        max_length=64, description="Chamado da parte; a data dele é a data da contestação."
    )
    o_que_faltou: str = Field(min_length=10, max_length=4000)
    anexos: list[str] = Field(default_factory=list, max_length=10)


class DecidirContestacaoIn(_Corpo):
    resultado: Resultado
    resposta: str = Field(min_length=10, max_length=4000, description="As duas partes leem.")
    nova_decisao: NovaDecisao | None = None
    novo_valor_reembolso_centavos: int | None = Field(
        None, ge=1, strict=True, description="Só com reembolso_parcial."
    )


class AprovarContestacaoIn(_Corpo):
    aprovar: bool = Field(description="false: devolve para nova análise.")
    motivo: str = Field(min_length=10, max_length=1000)


class ContestacaoAdminOut(BaseModel):
    id: str
    protocolo: str
    pedido_id: str
    disputa_id: str
    contestante_id: str
    contestante_papel: str | None = Field(None, description="cliente | profissional")
    o_que_faltou: str
    anexos: list[str]
    canal: str
    status: str
    aberta_em: datetime
    contestar_ate: datetime
    responder_ate: datetime
    atrasada: bool
    analista_id: str | None
    resposta: str | None
    nova_decisao: str | None
    novo_valor_reembolso_centavos: int | None
    aprovada_por: str | None
    decidida_em: datetime | None
    efeito_financeiro: str


class DecisaoOut(BaseModel):
    resultado: str
    reembolso_centavos: int


class ContestacaoDetalheOut(ContestacaoAdminOut):
    valor_congelado_centavos: int
    decisao_original: DecisaoOut
    decisao_vigente: DecisaoOut
    decidida_por: str | None = Field(description="Quem decidiu a disputa: não analisa.")
    disputa_aprovada_por: str | None


def _saida(contexto: Contexto, item: ContestacaoDecisao) -> ContestacaoAdminOut:
    pedido = contexto.pedidos.obter(item.pedido_id)
    papel = None
    if pedido is not None:
        papel = "cliente" if item.contestante_id == pedido.cliente_id else "profissional"
    campos = {k: getattr(item, k) for k in ContestacaoAdminOut.model_fields if hasattr(item, k)}
    campos |= {
        "anexos": list(item.anexos),
        "contestante_papel": papel,
        "atrasada": item.status in PENDENTES and contexto.agora() > item.responder_ate,
    }
    return ContestacaoAdminOut(**campos)


def _detalhe(contexto: Contexto, item: ContestacaoDecisao):
    disputa = contexto.disputas.obter(item.pedido_id)
    if disputa is None or disputa.decisao is None:
        return regras.Recusa("nao_encontrada").resposta()
    original = regras.decisao_vigente(disputa, [])
    vigente = regras.decisao_vigente(
        disputa, contexto.contestacoes_decisao.da_disputa(item.disputa_id)
    )
    return ContestacaoDetalheOut(
        **_saida(contexto, item).model_dump(),
        valor_congelado_centavos=disputa.valor_congelado,
        decisao_original=DecisaoOut(resultado=original[0], reembolso_centavos=original[1]),
        decisao_vigente=DecisaoOut(resultado=vigente[0], reembolso_centavos=vigente[1]),
        decidida_por=disputa.decidido_por,
        disputa_aprovada_por=disputa.aprovado_por,
    )


def _auditoria(
    admin: AdminContexto, operador: Operador, acao: str, motivo: str
) -> Callable[[ContestacaoDecisao, ContestacaoDecisao], None]:
    def registrar(antes: ContestacaoDecisao, depois: ContestacaoDecisao) -> None:
        admin.auditoria.registrar(
            ator_id=operador.id,
            acao=acao,
            entidade="disputa_contestacoes",
            entidade_id=depois.id,
            antes={"status": antes.status, "nova_decisao": antes.nova_decisao},
            depois={
                "status": depois.status,
                "nova_decisao": depois.nova_decisao,
                "novo_valor_reembolso_centavos": depois.novo_valor_reembolso_centavos,
                "efeito_financeiro": depois.efeito_financeiro,
                "pedido_id": depois.pedido_id,
            },
            motivo=motivo,
        )

    return registrar


@router.get("", response_model=Pagina[ContestacaoAdminOut], summary="Listar contestações")
def listar(
    status: Status | None = None,
    efeito_financeiro: Efeito | None = None,
    pedido_id: str | None = Query(None, max_length=64),
    atrasadas: bool = False,
    limite: int = Query(50, ge=1, le=100),
    deslocamento: int = Query(0, ge=0),
    _: Operador = Depends(exigir(Permissao.DISPUTAS_VER)),
    contexto: Contexto = Depends(obter_contexto),
):
    try:
        regras.exigir_tabelas(contexto)
    except regras.Recusa as erro:
        return erro.resposta()
    itens, total = contexto.contestacoes_decisao.listar(
        status=status,
        efeito=efeito_financeiro,
        pedido_id=pedido_id,
        vencidas_em=contexto.agora() if atrasadas else None,
        limite=limite,
        deslocamento=deslocamento,
    )
    return Pagina[ContestacaoAdminOut](
        itens=[_saida(contexto, c) for c in itens],
        total=total,
        limite=limite,
        deslocamento=deslocamento,
    )


@router.get(
    "/{contestacao_id}", response_model=ContestacaoDetalheOut, summary="Ver uma contestação"
)
def ver(
    contestacao_id: str,
    _: Operador = Depends(exigir(Permissao.DISPUTAS_VER)),
    contexto: Contexto = Depends(obter_contexto),
):
    try:
        regras.exigir_tabelas(contexto)
    except regras.Recusa as erro:
        return erro.resposta()
    item = contexto.contestacoes_decisao.obter(contestacao_id)
    if item is None:
        return regras.Recusa("nao_encontrada").resposta()
    return _detalhe(contexto, item)


@router.post(
    "",
    response_model=ContestacaoAdminOut,
    status_code=201,
    summary="Registrar a contestação que a parte fez pelo atendimento",
)
def registrar(
    corpo: RegistrarPeloSacIn,
    request: Request,
    response: Response,
    operador: Operador = Depends(exigir(Permissao.SAC_RESPONDER)),
    admin: AdminContexto = Depends(obter_admin),
    contexto: Contexto = Depends(obter_contexto),
):
    # import tardio: os módulos do painel não importam as rotas do app (ciclo)
    from trato.api.rotas_contestacao_disputa import anexo_invalido, anexos_da_parte

    try:
        regras.exigir_tabelas(contexto)
        pedido = contexto.pedidos.obter(corpo.pedido_id)
        if pedido is None:
            raise regras.Recusa("pedido_nao_encontrado")
        decidida = regras.decisao_da_disputa(contexto, pedido)
        if decidida is None:
            raise regras.Recusa("sem_decisao")
        if corpo.contestante_id not in (pedido.cliente_id, pedido.profissional_id):
            raise regras.Recusa("nao_e_parte")
        chamado = contexto.sac.obter(corpo.chamado_id) if contexto.sac.disponivel() else None
        if (
            chamado is None
            or chamado.usuario_id != corpo.contestante_id
            or chamado.pedido_id not in (None, pedido.id)
            or chamado.criado_em < decidida.decidida_em
        ):
            raise regras.Recusa("chamado_invalido")
        anexos = anexos_da_parte(request, pedido.id, corpo.contestante_id, corpo.anexos)
        if anexos is None:
            return anexo_invalido()

        def auditar(item: ContestacaoDecisao) -> None:
            admin.auditoria.registrar(
                ator_id=operador.id,
                acao="disputas.contestacao_registrada",
                entidade="disputa_contestacoes",
                entidade_id=item.id,
                depois={
                    "pedido_id": item.pedido_id,
                    "contestante_id": item.contestante_id,
                    "chamado_id": corpo.chamado_id,
                },
                motivo=f"Contestação recebida pelo atendimento ({chamado.protocolo}).",
            )

        item, criada = regras.abrir(
            contexto,
            decidida,
            corpo.contestante_id,
            corpo.o_que_faltou,
            anexos,
            "sac",
            chamado.criado_em,
            auditar,
        )
    except regras.Recusa as erro:
        return erro.resposta()
    if not criada:
        response.status_code = 200
    return _saida(contexto, item)


@router.post(
    "/{contestacao_id}/decisao",
    response_model=ContestacaoDetalheOut,
    summary="Outro analista decide a contestação",
    description="Se o valor do reembolso mudar, fica `aguardando_aprovacao`. Nada move dinheiro.",
)
def decidir(
    contestacao_id: str,
    corpo: DecidirContestacaoIn,
    operador: Operador = Depends(exigir(Permissao.DISPUTAS_DECIDIR)),
    admin: AdminContexto = Depends(obter_admin),
    contexto: Contexto = Depends(obter_contexto),
):
    try:
        regras.exigir_tabelas(contexto)
        item = regras.decidir(
            contexto,
            contestacao_id,
            operador.id,
            corpo.resultado,
            corpo.resposta,
            corpo.nova_decisao,
            corpo.novo_valor_reembolso_centavos,
            _auditoria(admin, operador, "disputas.contestacao_decidida", corpo.resposta),
        )
    except regras.Recusa as erro:
        return erro.resposta()
    return _detalhe(contexto, item)


@router.post(
    "/{contestacao_id}/aprovacao",
    response_model=ContestacaoDetalheOut,
    summary="Segunda pessoa aprova ou devolve",
    description="Se aprovada com mudança de valor, o efeito fica `pendente_financeiro`.",
)
def aprovar(
    contestacao_id: str,
    corpo: AprovarContestacaoIn,
    operador: Operador = Depends(exigir(Permissao.DISPUTAS_SEGUNDA_PESSOA)),
    admin: AdminContexto = Depends(obter_admin),
    contexto: Contexto = Depends(obter_contexto),
):
    alcada = (
        None
        if operador.membro.papel is PapelEquipe.ADMINISTRADOR
        else operador.membro.alcada_centavos or 0
    )
    acao = "disputas.contestacao_aprovada" if corpo.aprovar else "disputas.contestacao_devolvida"
    try:
        regras.exigir_tabelas(contexto)
        item = regras.aprovar(
            contexto,
            contestacao_id,
            operador.id,
            corpo.aprovar,
            alcada,
            _auditoria(admin, operador, acao, corpo.motivo),
        )
    except regras.Recusa as erro:
        return erro.resposta()
    return _detalhe(contexto, item)
