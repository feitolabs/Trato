"""Rotas do usuário para contestação de nota de material (Termos 6.9)."""

from __future__ import annotations

from datetime import datetime
from typing import Literal

from fastapi import APIRouter, Depends, HTTPException, Request, Response
from pydantic import BaseModel, ConfigDict, Field

from trato.api.auth import PapelUsuario, Usuario
from trato.api.contexto import Contexto, exigir_papel, obter_contexto
from trato.api.rotas_contestacao_disputa import anexo_invalido, anexos_da_parte
from trato.api.servicos import carregar_pedido
from trato.disputas.prazos import adicionar_dias_uteis
from trato.financeiro import periodo
from trato.pedidos.estados import Pedido
from trato.persistencia.materiais_contestacao import ContestacaoNotaMaterial

router = APIRouter(prefix="/v1/pedidos", tags=["materiais"])

MotivoContestacaoMaterial = Literal["nao_comprovado", "diferente_do_combinado"]


class ContestarNotaMaterialIn(BaseModel):
    model_config = ConfigDict(extra="forbid", str_strip_whitespace=True)

    motivo: MotivoContestacaoMaterial
    descricao: str = Field(min_length=10, max_length=4000)
    valor_contestado_centavos: int = Field(ge=1, strict=True)
    item_id: str | None = Field(default=None, min_length=1, max_length=64)
    anexos: list[str] = Field(
        default_factory=list,
        max_length=10,
        description="`midia_id` de arquivos que o próprio cliente enviou neste pedido.",
    )


class ContestacaoMaterialUsuarioOut(BaseModel):
    id: str
    protocolo: str
    pedido_id: str
    nota_id: str
    item_id: str | None = None
    motivo: MotivoContestacaoMaterial
    descricao: str
    anexos: list[str]
    valor_contestado_centavos: int
    aberta_em: datetime
    responder_ate: datetime
    status: str
    resposta: str | None = None
    valor_reconhecido_centavos: int | None = None
    decidida_em: datetime | None = None
    efeito_financeiro: str


class ListaContestacoesMaterialUsuarioOut(BaseModel):
    itens: list[ContestacaoMaterialUsuarioOut]
    total: int


def _out(c: ContestacaoNotaMaterial) -> ContestacaoMaterialUsuarioOut:
    return ContestacaoMaterialUsuarioOut(
        id=c.id,
        protocolo=c.protocolo,
        pedido_id=c.pedido_id,
        nota_id=c.nota_id,
        item_id=c.item_id,
        motivo=c.motivo,  # type: ignore[arg-type]
        descricao=c.descricao,
        anexos=list(c.anexos),
        valor_contestado_centavos=c.valor_contestado_centavos,
        aberta_em=c.aberta_em,
        responder_ate=c.responder_ate,
        status=c.status,
        resposta=c.resposta,
        valor_reconhecido_centavos=c.valor_reconhecido_centavos,
        decidida_em=c.decidida_em,
        efeito_financeiro=c.efeito_financeiro,
    )


def _exigir_tabela(contexto: Contexto) -> None:
    if not contexto.materiais_contestacao.disponivel():
        raise HTTPException(
            503,
            "Contestação de nota de material indisponível: tabela ainda não existe no banco.",
        )


def _responder_ate(contexto: Contexto, agora: datetime) -> datetime:
    """Prazo geral do atendimento (25.4): vem da configuração, no máximo 5 dias úteis."""
    cfg = contexto.config.carregar()
    return adicionar_dias_uteis(
        agora.astimezone(periodo.BRASILIA),
        min(5, cfg.sac_resposta_dias_uteis),
        cfg.disputas.feriados,
    )


def _exigir_cliente_do_pedido(
    contexto: Contexto, pedido_id: str, usuario: Usuario, mensagem: str
) -> Pedido:
    pedido = carregar_pedido(contexto, pedido_id, usuario)  # terceiro recebe 404
    if pedido.cliente_id != usuario.id:
        raise HTTPException(403, mensagem)
    return pedido


@router.post(
    "/{pedido_id}/materiais/{nota_id}/contestar",
    response_model=ContestacaoMaterialUsuarioOut,
    status_code=201,
    description="Reenviar o mesmo conteúdo responde 200 com a aberta. Não move dinheiro.",
    summary="Contestar nota de material do pedido (Termos 6.9)",
)
def contestar_nota_material(
    pedido_id: str,
    nota_id: str,
    corpo: ContestarNotaMaterialIn,
    request: Request,
    resposta: Response,
    usuario: Usuario = Depends(exigir_papel(PapelUsuario.CLIENTE, PapelUsuario.PROFISSIONAL)),
    contexto: Contexto = Depends(obter_contexto),
):
    _exigir_tabela(contexto)
    pedido = _exigir_cliente_do_pedido(
        contexto, pedido_id, usuario, "Só o cliente do pedido pode contestar a nota de material."
    )
    nota = next((n for n in contexto.notas_material.do_pedido(pedido.id) if n.id == nota_id), None)
    if nota is None:
        raise HTTPException(404, "Nota de material não encontrada neste pedido.")

    item_total: int | None = None
    if corpo.item_id is not None:
        totais = {i: linha[3] for i, linha in zip(nota.item_ids, nota.itens, strict=False)}
        if corpo.item_id not in totais:
            raise HTTPException(404, "Item não encontrado nesta nota.")
        item_total = totais[corpo.item_id]
        if corpo.valor_contestado_centavos > item_total:
            raise HTTPException(422, "O valor contestado ultrapassa o valor do item.")
    anexos = anexos_da_parte(request, pedido.id, usuario.id, corpo.anexos)
    if anexos is None:
        return anexo_invalido()

    agora = contexto.agora()
    cont, eh_nova, cod = contexto.materiais_contestacao.abrir(
        pedido_id=pedido.id,
        nota_id=nota.id,
        nota_total_centavos=nota.total_centavos,
        item_id=corpo.item_id,
        item_total_centavos=item_total,
        cliente_id=usuario.id,
        motivo=corpo.motivo,
        descricao=corpo.descricao,
        anexos=anexos,
        valor_contestado_centavos=corpo.valor_contestado_centavos,
        aberta_em=agora,
        responder_ate=_responder_ate(contexto, agora),
    )
    if cod == "excede_valor":
        raise HTTPException(422, "O valor contestado ultrapassa o valor disponível da nota.")
    if cod == "sobreposicao":
        raise HTTPException(409, "Contestação da nota inteira e de item não podem se sobrepor.")
    if cont is None:
        raise HTTPException(409, "Não foi possível abrir a contestação da nota.")
    if not eh_nova:
        pedido_agora = (corpo.motivo, corpo.valor_contestado_centavos, corpo.descricao, anexos)
        if pedido_agora != (
            cont.motivo,
            cont.valor_contestado_centavos,
            cont.descricao,
            cont.anexos,
        ):
            raise HTTPException(
                409,
                f"Já há uma contestação em aberto ({cont.protocolo}). Aguarde a resposta.",
            )
        resposta.status_code = 200
    return _out(cont)


@router.get(
    "/{pedido_id}/materiais/contestacoes",
    response_model=ListaContestacoesMaterialUsuarioOut,
    summary="Listar contestações de notas de material do pedido",
)
def listar_contestacoes_material(
    pedido_id: str,
    usuario: Usuario = Depends(exigir_papel(PapelUsuario.CLIENTE, PapelUsuario.PROFISSIONAL)),
    contexto: Contexto = Depends(obter_contexto),
) -> ListaContestacoesMaterialUsuarioOut:
    _exigir_tabela(contexto)
    pedido = _exigir_cliente_do_pedido(
        contexto, pedido_id, usuario, "Só o cliente do pedido vê as contestações."
    )
    itens = contexto.materiais_contestacao.listar_do_pedido(pedido.id)
    return ListaContestacoesMaterialUsuarioOut(itens=[_out(c) for c in itens], total=len(itens))
