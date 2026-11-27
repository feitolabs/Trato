"""Documentos da Contratação (Termos 5.3 e 6.13), disponíveis assim que o pagamento é confirmado.

São do cliente do pedido. Continuam disponíveis depois da conclusão ou do cancelamento, porque o
pagamento aconteceu. Só leitura: nenhum valor é calculado nem lançado aqui.
"""

from __future__ import annotations

from datetime import date, datetime

from fastapi import APIRouter, Depends, HTTPException, Request, Response
from pydantic import BaseModel, Field

from trato import legal
from trato.api.auth import PapelUsuario, Usuario
from trato.api.contexto import Contexto, exigir_papel, obter_contexto
from trato.api.rotas_financeiro import _numeros_dos_pedidos
from trato.api.rotas_profissional_cadastro import _nome_abreviado
from trato.api.servicos import carregar_pedido
from trato.financeiro import documentos_contratacao as documentos
from trato.pedidos.estados import Acao, Pedido

router = APIRouter(prefix="/v1/pedidos", tags=["contratação"])

_PDF = {200: {"content": {"application/pdf": {}}}}


class ContratacaoOut(BaseModel):
    pedido_id: str
    confirmada_em: datetime
    comprovante_url: str
    termos_disponiveis: bool = Field(
        description="False: o servidor não tem o texto da versão vigente na Contratação."
    )
    termos_versao: str | None = None
    termos_vigentes_desde: date | None = None
    termos_url: str | None = None


def _contratacao(contexto: Contexto, pedido_id: str, usuario: Usuario) -> tuple[Pedido, datetime]:
    pedido = carregar_pedido(contexto, pedido_id, usuario)  # quem não é parte recebe 404
    if pedido.cliente_id != usuario.id:
        raise HTTPException(403, "Os documentos da contratação são do cliente do pedido.")
    confirmada_em = next(
        (e.em for e in contexto.pedidos.eventos(pedido.id) if e.acao is Acao.CONFIRMAR_PAGAMENTO),
        None,
    )
    if confirmada_em is None or pedido.referencia_pagamento is None:
        raise HTTPException(409, "Disponível depois que o pagamento for confirmado.")
    return pedido, confirmada_em


def _arquivo(conteudo: bytes, nome: str) -> Response:
    return Response(
        content=conteudo,
        media_type="application/pdf",
        headers={
            "Content-Disposition": f'attachment; filename="{nome}"',
            "Cache-Control": "no-store",
        },
    )


@router.get(
    "/{pedido_id}/contratacao",
    response_model=ContratacaoOut,
    summary="Confirmação da Contratação e links do comprovante e dos Termos (5.3)",
)
def ver_contratacao(
    pedido_id: str,
    usuario: Usuario = Depends(exigir_papel(PapelUsuario.CLIENTE, PapelUsuario.PROFISSIONAL)),
    contexto: Contexto = Depends(obter_contexto),
) -> ContratacaoOut:
    pedido, confirmada_em = _contratacao(contexto, pedido_id, usuario)
    termos = legal.vigente_em(confirmada_em)
    base = f"/v1/pedidos/{pedido.id}/contratacao"
    return ContratacaoOut(
        pedido_id=pedido.id,
        confirmada_em=confirmada_em,
        comprovante_url=f"{base}/comprovante.pdf",
        termos_disponiveis=termos is not None,
        termos_versao=termos.versao if termos else None,
        termos_vigentes_desde=termos.vigente_desde if termos else None,
        termos_url=f"{base}/termos.pdf" if termos else None,
    )


@router.get(
    "/{pedido_id}/contratacao/comprovante.pdf",
    summary="Comprovante do pagamento da Contratação em PDF (5.3 e 6.13)",
    responses=_PDF,
)
def baixar_comprovante(
    pedido_id: str,
    request: Request,
    usuario: Usuario = Depends(exigir_papel(PapelUsuario.CLIENTE, PapelUsuario.PROFISSIONAL)),
    contexto: Contexto = Depends(obter_contexto),
) -> Response:
    pedido, confirmada_em = _contratacao(contexto, pedido_id, usuario)
    contrato = contexto.contratos.obter_do_pedido(pedido.id)
    servico = getattr(request.app.state, "servico_pagamento", None)
    cobranca = None
    if servico is not None:
        cobranca = next(
            (
                c
                for c in servico.cobrancas.do_pedido(pedido.id)
                if c.id == pedido.referencia_pagamento
            ),
            None,
        )
    if cobranca is None and contrato is None:
        raise HTTPException(503, "Não foi possível montar o comprovante agora.")
    dados_pedido = contexto.pedidos.dados_do_pedido(pedido.id)

    def nome(uid: str | None) -> str:
        detalhe = contexto.usuarios.detalhe(uid) if uid else None
        return (_nome_abreviado(detalhe.nome) if detalhe is not None else None) or ""

    numero = _numeros_dos_pedidos(contexto, [pedido.id]).get(pedido.id)
    codigo = f"PED-{numero}" if numero is not None else pedido.id[:8]
    termos = legal.vigente_em(confirmada_em)
    dados = documentos.DadosComprovante(
        codigo=codigo,
        titulo=dados_pedido.titulo if dados_pedido else "",
        cliente_nome=nome(pedido.cliente_id),
        profissional_nome=nome(pedido.profissional_id),
        confirmada_em=confirmada_em,
        referencia_pagamento=pedido.referencia_pagamento or "",
        # Sem a cobrança local (confirmação direta pelo webhook), o valor pago foi conferido
        # como igual ao do contrato antes de confirmar.
        valor_pago_centavos=cobranca.valor_centavos if cobranca else contrato.valor_centavos,
        desconto_centavos=cobranca.desconto_centavos if cobranca else 0,
        meio=cobranca.meio.value if cobranca else None,
        parcelas=cobranca.parcelas if cobranca else 1,
        termos_versao=termos.versao if termos else None,
    )
    return _arquivo(
        documentos.comprovante_pdf(dados, contexto.agora()), f"comprovante-trato-{codigo}.pdf"
    )


@router.get(
    "/{pedido_id}/contratacao/termos.pdf",
    summary="Cópia dos Termos vigentes na Contratação em PDF (5.3 e 23.6)",
    responses=_PDF,
)
def baixar_termos(
    pedido_id: str,
    usuario: Usuario = Depends(exigir_papel(PapelUsuario.CLIENTE, PapelUsuario.PROFISSIONAL)),
    contexto: Contexto = Depends(obter_contexto),
) -> Response:
    _, confirmada_em = _contratacao(contexto, pedido_id, usuario)
    termos = legal.vigente_em(confirmada_em)
    if termos is None:  # nunca entrega outra versão no lugar
        raise HTTPException(
            404,
            "A cópia dos Termos da época desta contratação não está no aplicativo. "
            "Peça ao atendimento.",
        )
    return _arquivo(documentos.termos_pdf(termos.texto()), f"termos-trato-v{termos.versao}.pdf")
