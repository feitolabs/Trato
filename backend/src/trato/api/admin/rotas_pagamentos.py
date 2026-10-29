"""Pagamentos e conciliação, SOMENTE LEITURA (caminho A, D15: o Trato não guarda saldo nem saca).

Tudo sai do ledger-espelho e dos eventos de webhook já gravados. Não há rota de escrita aqui.
"""

from __future__ import annotations

from collections.abc import Sequence

from fastapi import APIRouter, Depends, HTTPException, Query

from trato.api.admin.contexto import Operador, exigir
from trato.api.admin.modelos import (
    ContaAdminOut,
    EventoWebhookOut,
    ExtratoContratoOut,
    LancamentoAdminOut,
    PagamentoOut,
    Pagina,
    ResumoConciliacaoOut,
    SaldoContratoOut,
)
from trato.api.admin.papeis import Permissao
from trato.api.contexto import Contexto, obter_contexto
from trato.financeiro.ledger import CUSTODIA, TAXA_TRATO, Lancamento, TipoLancamento

router = APIRouter(prefix="/v1/admin", tags=["admin: pagamentos (leitura)"])


def lancamento_admin_out(item: Lancamento) -> LancamentoAdminOut:
    return LancamentoAdminOut(
        id=item.id,
        pedido_id=item.pedido_id,
        tipo=item.tipo.value,
        valor_centavos=item.valor,
        data=item.data,
        debito=ContaAdminOut(tipo=item.debito.tipo.value, titular=item.debito.titular),
        credito=ContaAdminOut(tipo=item.credito.tipo.value, titular=item.credito.titular),
        estorno_de=item.estorno_de,
    )


def _estornado(lancamentos: Sequence[Lancamento]) -> dict[str, int]:
    soma: dict[str, int] = {}
    for item in lancamentos:
        if item.tipo is TipoLancamento.ESTORNO and item.estorno_de:
            soma[item.estorno_de] = soma.get(item.estorno_de, 0) + item.valor
    return soma


def _pagamentos(contexto: Contexto, pedido_id: str | None = None) -> list[PagamentoOut]:
    todos = contexto.ledger.lancamentos(pedido_id)
    estornos = _estornado(contexto.ledger.lancamentos())
    saida = []
    for item in todos:
        if item.tipo is not TipoLancamento.COBRANCA:
            continue
        pedido = contexto.pedidos.obter(item.pedido_id)
        estornado = estornos.get(item.id, 0)
        status = "confirmado"
        if estornado:
            status = "estornado" if estornado >= item.valor else "estornado_parcial"
        # Conciliação: cobrança sem pedido, sem contrato ou sem referência do provedor.
        divergente = (
            pedido is None
            or pedido.referencia_pagamento is None
            or contexto.contratos.obter_do_pedido(item.pedido_id) is None
        )
        saida.append(
            PagamentoOut(
                lancamento_id=item.id,
                pedido_id=item.pedido_id,
                valor_centavos=item.valor,
                estornado_centavos=estornado,
                status=status,
                data=item.data,
                referencia_provedor=pedido.referencia_pagamento if pedido else None,
                divergente=divergente,
            )
        )
    saida.sort(key=lambda p: p.data, reverse=True)
    return saida


@router.get("/pagamentos", response_model=Pagina[PagamentoOut], summary="Pagamentos (espelho)")
def listar_pagamentos(
    pedido_id: str | None = None,
    status: str | None = Query(None, pattern="^(confirmado|estornado_parcial|estornado)$"),
    apenas_divergentes: bool = False,
    limite: int = Query(20, ge=1, le=100),
    deslocamento: int = Query(0, ge=0),
    _: Operador = Depends(exigir(Permissao.PAGAMENTOS_VER)),
    contexto: Contexto = Depends(obter_contexto),
) -> Pagina[PagamentoOut]:
    itens = [
        p
        for p in _pagamentos(contexto, pedido_id)
        if (status is None or p.status == status) and (not apenas_divergentes or p.divergente)
    ]
    return Pagina(
        itens=itens[deslocamento : deslocamento + limite],
        total=len(itens),
        limite=limite,
        deslocamento=deslocamento,
    )


@router.get(
    "/pagamentos/resumo", response_model=ResumoConciliacaoOut, summary="Resumo da conciliação"
)
def resumo(
    _: Operador = Depends(exigir(Permissao.PAGAMENTOS_VER)),
    contexto: Contexto = Depends(obter_contexto),
) -> ResumoConciliacaoOut:
    pagamentos = _pagamentos(contexto)
    return ResumoConciliacaoOut(
        confirmado_centavos=sum(p.valor_centavos for p in pagamentos),
        estornado_centavos=sum(p.estornado_centavos for p in pagamentos),
        retido_centavos=contexto.ledger.saldo_da_conta(CUSTODIA),
        taxa_trato_centavos=contexto.ledger.saldo_da_conta(TAXA_TRATO),
        divergencias=sum(1 for p in pagamentos if p.divergente),
        atualizado_em=contexto.agora(),
    )


@router.get(
    "/webhooks/eventos",
    response_model=Pagina[EventoWebhookOut],
    summary="Eventos de webhook recebidos (sem o payload bruto)",
)
def eventos_webhook(
    limite: int = Query(20, ge=1, le=100),
    deslocamento: int = Query(0, ge=0),
    _: Operador = Depends(exigir(Permissao.PAGAMENTOS_VER)),
    contexto: Contexto = Depends(obter_contexto),
) -> Pagina[EventoWebhookOut]:
    todos = sorted(contexto.eventos_webhook.listar(), key=lambda e: e.recebido_em, reverse=True)
    itens = []
    for e in todos[deslocamento : deslocamento + limite]:
        dados = e.payload.get("data")
        objeto = dados.get("object") if isinstance(dados, dict) else None
        objeto = objeto if isinstance(objeto, dict) else {}
        meta = objeto.get("metadata")
        valor = objeto.get("amount_received", objeto.get("amount"))
        itens.append(
            EventoWebhookOut(
                provedor=e.provedor,
                evento_id=e.evento_id,
                tipo=e.tipo,
                recebido_em=e.recebido_em,
                pedido_id=meta.get("pedido_id") if isinstance(meta, dict) else None,
                referencia=objeto.get("id") if isinstance(objeto.get("id"), str) else None,
                valor_centavos=valor
                if isinstance(valor, int) and not isinstance(valor, bool)
                else None,
            )
        )
    return Pagina(itens=itens, total=len(todos), limite=limite, deslocamento=deslocamento)


@router.get(
    "/lancamentos", response_model=Pagina[LancamentoAdminOut], summary="Lançamentos do ledger"
)
def listar_lancamentos(
    pedido_id: str | None = None,
    tipo: TipoLancamento | None = None,
    limite: int = Query(20, ge=1, le=100),
    deslocamento: int = Query(0, ge=0),
    _: Operador = Depends(exigir(Permissao.PAGAMENTOS_VER)),
    contexto: Contexto = Depends(obter_contexto),
) -> Pagina[LancamentoAdminOut]:
    itens = [i for i in contexto.ledger.lancamentos(pedido_id) if tipo is None or i.tipo is tipo]
    itens.sort(key=lambda i: i.data, reverse=True)
    return Pagina(
        itens=[lancamento_admin_out(i) for i in itens[deslocamento : deslocamento + limite]],
        total=len(itens),
        limite=limite,
        deslocamento=deslocamento,
    )


@router.get(
    "/contratos/{pedido_id}/extrato",
    response_model=ExtratoContratoOut,
    summary="Extrato do contrato: lançamentos e saldo do pedido (não há saldo próprio)",
)
def extrato_do_contrato(
    pedido_id: str,
    _: Operador = Depends(exigir(Permissao.PAGAMENTOS_VER)),
    contexto: Contexto = Depends(obter_contexto),
) -> ExtratoContratoOut:
    pedido = contexto.pedidos.obter(pedido_id)
    contrato = contexto.contratos.obter_do_pedido(pedido_id)
    if pedido is None and contrato is None:
        raise HTTPException(404, "Contrato não encontrado.")
    saldo = contexto.ledger.saldos_pedido(pedido_id, pedido.profissional_id if pedido else None)
    itens = sorted(contexto.ledger.lancamentos(pedido_id), key=lambda i: i.data)
    return ExtratoContratoOut(
        pedido_id=pedido_id,
        estado=pedido.estado.value if pedido else None,
        valor_contrato_centavos=contrato.valor_centavos if contrato else None,
        saldo=SaldoContratoOut(
            cliente_pagou_centavos=saldo.cliente_pagou,
            retido_centavos=saldo.retido,
            a_liberar_centavos=saldo.a_liberar,
            liberado_centavos=saldo.liberado,
            taxa_trato_centavos=saldo.taxa_trato,
        ),
        lancamentos=[lancamento_admin_out(i) for i in itens],
    )
