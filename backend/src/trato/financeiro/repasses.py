"""Ordem de repasse a partir dos lançamentos da divisão da custódia (D15).

Ao repartir a custódia (`repartir_custodia`) nasce a ordem de liberar ao profissional: valor
bruto (retenção + taxa), taxa e líquido. Quem libera o dinheiro de fato é o parceiro; o Trato
só registra a ordem e, quando o parceiro avisa (webhook assinado), espelha no ledger (M5).
"""

from __future__ import annotations

from collections.abc import Iterable

from trato.api.repositorios import Repasse
from trato.financeiro.ledger import Lancamento, TipoLancamento


def repasse_dos_lancamentos(
    pedido_id: str,
    profissional_id: str,
    lancamentos: Iterable[Lancamento],
    gatilho: str,
    chave: str,
) -> Repasse | None:
    """`None` se a divisão não deixou nada para o profissional (tudo voltou ao cliente)."""
    itens = list(lancamentos)
    liquido = sum(i.valor for i in itens if i.tipo is TipoLancamento.RETENCAO)
    taxa = sum(i.valor for i in itens if i.tipo is TipoLancamento.TAXA)
    if liquido <= 0 or not profissional_id:
        return None
    return Repasse(
        pedido_id=pedido_id,
        profissional_id=profissional_id,
        valor_bruto_centavos=liquido + taxa,
        taxa_centavos=taxa,
        valor_liquido_centavos=liquido,
        gatilho=gatilho,
        chave=chave,
    )
