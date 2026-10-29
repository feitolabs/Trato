"""Repositórios de pagamento em memória, para teste e desenvolvimento."""

from __future__ import annotations

from collections.abc import Sequence

from trato.pagamentos.modelos import Aditivo, CobrancaLocal, TermosContrato


class CobrancasEmMemoria:
    def __init__(self) -> None:
        self._itens: dict[str, CobrancaLocal] = {}

    def obter(self, cobranca_id: str) -> CobrancaLocal | None:
        return self._itens.get(cobranca_id)

    def salvar(self, cobranca: CobrancaLocal) -> None:
        self._itens[cobranca.id] = cobranca

    def do_pedido(self, pedido_id: str) -> Sequence[CobrancaLocal]:
        achadas = [c for c in self._itens.values() if c.pedido_id == pedido_id]
        return sorted(achadas, key=lambda c: c.criada_em)


class AditivosEmMemoria:
    def __init__(self) -> None:
        self._itens: dict[str, Aditivo] = {}

    def obter(self, aditivo_id: str) -> Aditivo | None:
        return self._itens.get(aditivo_id)

    def salvar(self, aditivo: Aditivo) -> None:
        self._itens[aditivo.id] = aditivo

    def do_pedido(self, pedido_id: str) -> Sequence[Aditivo]:
        achados = [a for a in self._itens.values() if a.pedido_id == pedido_id]
        return sorted(achados, key=lambda a: a.criado_em)


class TermosEmMemoria:
    def __init__(self) -> None:
        self._itens: dict[str, TermosContrato] = {}

    def obter(self, pedido_id: str) -> TermosContrato | None:
        return self._itens.get(pedido_id)

    def salvar(self, termos: TermosContrato) -> None:
        self._itens[termos.pedido_id] = termos
