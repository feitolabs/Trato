"""Pagamentos e conciliação, SOMENTE LEITURA (caminho A, D15: o Trato não guarda saldo nem saca).

Tudo sai do ledger-espelho e dos eventos de webhook já gravados. Não há rota de escrita aqui.
"""

from __future__ import annotations

from collections.abc import Sequence
import uuid
from datetime import timedelta

from fastapi import APIRouter, Depends, HTTPException, Query

from trato.api.admin.contexto import AdminContexto, Operador, exigir, obter_admin
from trato.api.admin.modelos import (
    ComMotivo,
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
from trato.api.admin.repositorios import FiltroAuditoria
from trato.api.contexto import Contexto, obter_contexto
from trato.financeiro.ledger import CUSTODIA, TAXA_TRATO, Lancamento, TipoLancamento

router = APIRouter(prefix="/v1/admin", tags=["admin: pagamentos (leitura)"])

# Conciliar só anota na auditoria (nenhum dinheiro se move); por isso mora fora de /pagamentos.
router_divergencias = APIRouter(prefix="/v1/admin/divergencias", tags=["admin: conciliação"])
ACAO_CONCILIADA = "pagamento.divergencia_conciliada"


_PAGINA_AUDITORIA = 500


def _id_normal(valor: str) -> str:
    """O mesmo id em uma forma só: a auditoria do banco devolve uuid com hífens, o ledger sem."""
    try:
        return uuid.UUID(valor).hex
    except ValueError:
        return valor


def _conciliadas(admin: AdminContexto) -> set[str]:
    """Ids (normalizados) dos lançamentos já conciliados. A fonte é a auditoria (imutável).

    Lê TODAS as páginas: antes só as 100 últimas contavam e as mais antigas voltavam a aparecer
    como divergência."""
    ids: set[str] = set()
    lidos = 0
    while True:
        itens, total = admin.auditoria.listar(
            FiltroAuditoria(acao=ACAO_CONCILIADA), _PAGINA_AUDITORIA, lidos
        )
        ids.update(_id_normal(i.entidade_id) for i in itens if i.entidade_id)
        lidos += len(itens)
        if not itens or lidos >= total:
            return ids


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


def _taxas_por_pedido(lancamentos: Sequence[Lancamento]) -> dict[str, int]:
    """Saldo da conta de taxa do Trato por pedido, somado do que já foi lido (sem ir ao banco)."""
    taxa: dict[str, int] = {}
    for item in lancamentos:
        if item.credito == TAXA_TRATO:
            taxa[item.pedido_id] = taxa.get(item.pedido_id, 0) + item.valor
        if item.debito == TAXA_TRATO:
            taxa[item.pedido_id] = taxa.get(item.pedido_id, 0) - item.valor
    return taxa


def _pagamentos(
    contexto: Contexto,
    admin: AdminContexto,
    pedido_id: str | None = None,
    conciliadas: set[str] | None = None,
    dias: int | None = None,
) -> list[PagamentoOut]:
    """As cobranças do espelho com o status de estorno e de conciliação.

    O ledger é lido UMA vez e os pedidos numa consulta só (antes eram várias idas ao banco por
    cobrança: com o banco longe do servidor, algumas centenas já travavam a tela)."""
    todos = contexto.ledger.lancamentos()
    if pedido_id is not None:
        todos = tuple(i for i in todos if i.pedido_id == pedido_id)
    estornos = _estornado(todos)
    taxas = _taxas_por_pedido(todos)
    limite = contexto.agora() - timedelta(days=dias) if dias is not None else None
    cobrancas = [
        i
        for i in todos
        if i.tipo is TipoLancamento.COBRANCA and (limite is None or i.data >= limite)
    ]
    pedidos = admin.pedidos.dados_de_pagamento([i.pedido_id for i in cobrancas])
    ja = conciliadas or set()
    saida = []
    for item in cobrancas:
        referencia, tem_contrato = pedidos.get(item.pedido_id, (None, False))
        estornado = estornos.get(item.id, 0)
        status = "confirmado"
        if estornado:
            status = "estornado" if estornado >= item.valor else "estornado_parcial"
        # Conciliação: cobrança sem pedido, sem contrato ou sem referência do provedor.
        divergente = _id_normal(item.id) not in ja and (
            item.pedido_id not in pedidos or referencia is None or not tem_contrato
        )
        taxa = taxas.get(item.pedido_id, 0) if item.pedido_id in pedidos else None
        saida.append(
            PagamentoOut(
                taxa_trato_centavos=taxa,
                liquido_profissional_centavos=None if taxa is None else max(item.valor - taxa, 0),
                lancamento_id=item.id,
                pedido_id=item.pedido_id,
                valor_centavos=item.valor,
                estornado_centavos=estornado,
                status=status,
                data=item.data,
                referencia_provedor=referencia,
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
    dias: int | None = Query(None, ge=1, le=3650, description="Só os dos últimos N dias."),
    _: Operador = Depends(exigir(Permissao.PAGAMENTOS_VER)),
    contexto: Contexto = Depends(obter_contexto),
    admin: AdminContexto = Depends(obter_admin),
) -> Pagina[PagamentoOut]:
    itens = [
        p
        for p in _pagamentos(contexto, admin, pedido_id, _conciliadas(admin), dias)
        if (status is None or p.status == status) and (not apenas_divergentes or p.divergente)
    ]
    pagina = itens[deslocamento : deslocamento + limite]
    rotulos = admin.pedidos.rotulos([p.pedido_id for p in pagina])
    for p in pagina:
        p.pedido_numero = rotulos.get(p.pedido_id, (None, ""))[0]
    return Pagina(
        itens=pagina,
        total=len(itens),
        limite=limite,
        deslocamento=deslocamento,
    )


@router.get(
    "/pagamentos/resumo", response_model=ResumoConciliacaoOut, summary="Resumo da conciliação"
)
def resumo(
    dias: int | None = Query(None, ge=1, le=3650, description="Só os dos últimos N dias."),
    _: Operador = Depends(exigir(Permissao.PAGAMENTOS_VER)),
    contexto: Contexto = Depends(obter_contexto),
    admin: AdminContexto = Depends(obter_admin),
) -> ResumoConciliacaoOut:
    pagamentos = _pagamentos(contexto, admin, None, _conciliadas(admin), dias)
    return ResumoConciliacaoOut(
        cobrancas=len(pagamentos),
        reembolsos=sum(1 for p in pagamentos if p.estornado_centavos > 0),
        valor_divergente_centavos=sum(p.valor_centavos for p in pagamentos if p.divergente),
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


@router_divergencias.post(
    "/{lancamento_id}/conciliar",
    status_code=204,
    summary="Marcar uma divergência como conciliada (só anota; não mexe em dinheiro)",
)
def conciliar(
    lancamento_id: str,
    corpo: ComMotivo,
    operador: Operador = Depends(exigir(Permissao.PAGAMENTOS_CONCILIAR)),
    contexto: Contexto = Depends(obter_contexto),
    admin: AdminContexto = Depends(obter_admin),
) -> None:
    ja = _conciliadas(admin)
    alvo = next(
        (p for p in _pagamentos(contexto, admin, None, ja) if p.lancamento_id == lancamento_id),
        None,
    )
    if alvo is None:
        if _id_normal(lancamento_id) in ja:
            raise HTTPException(409, "Essa divergência já foi conciliada.")
        raise HTTPException(404, "Lançamento não encontrado.")
    if not alvo.divergente:
        raise HTTPException(409, "Esse lançamento não tem divergência.")
    admin.auditoria.registrar(
        ator_id=operador.id,
        acao=ACAO_CONCILIADA,
        entidade="lancamentos",
        entidade_id=lancamento_id,
        depois={"pedido_id": alvo.pedido_id, "valor_centavos": alvo.valor_centavos},
        motivo=corpo.motivo,
    )
