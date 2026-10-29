"""Repositórios em memória, para testes e desenvolvimento. Não são o armazenamento real."""

from __future__ import annotations

import threading
from collections.abc import Sequence

from trato.api.repositorios import (
    ConfigApi,
    Contrato,
    EventoWebhook,
    Orcamento,
)
from trato.disputas import Disputa
from trato.financeiro.ledger import Conta, Lancamento, Livro, SaldoPedido
from trato.garantias import Garantia, Retrabalho
from trato.pagamentos.idempotencia import RegistroEventosEmMemoria
from trato.pedidos.estados import Evento, Pedido


class PedidosEmMemoria:
    def __init__(self) -> None:
        self._pedidos: dict[str, Pedido] = {}
        self._eventos: dict[str, list[Evento]] = {}

    def obter(self, pedido_id: str) -> Pedido | None:
        return self._pedidos.get(pedido_id)

    def salvar(self, pedido: Pedido, evento: Evento | None = None) -> None:
        self._pedidos[pedido.id] = pedido
        lista = self._eventos.setdefault(pedido.id, [])
        if evento is not None:
            lista.append(evento)

    def eventos(self, pedido_id: str) -> Sequence[Evento]:
        return tuple(self._eventos.get(pedido_id, ()))

    def listar_do_usuario(self, usuario_id: str, como_cliente: bool) -> Sequence[Pedido]:
        campo = "cliente_id" if como_cliente else "profissional_id"
        achados = [p for p in self._pedidos.values() if getattr(p, campo) == usuario_id]
        return sorted(achados, key=lambda p: p.aberto_em, reverse=True)


class OrcamentosEmMemoria:
    def __init__(self, orcamentos: Sequence[Orcamento] = ()) -> None:
        self._itens = {o.id: o for o in orcamentos}

    def adicionar(self, orcamento: Orcamento) -> None:
        self._itens[orcamento.id] = orcamento

    def obter(self, orcamento_id: str) -> Orcamento | None:
        return self._itens.get(orcamento_id)


class ContratosEmMemoria:
    def __init__(self) -> None:
        self._itens: dict[str, Contrato] = {}

    def obter_do_pedido(self, pedido_id: str) -> Contrato | None:
        return self._itens.get(pedido_id)

    def salvar(self, contrato: Contrato) -> None:
        self._itens[contrato.pedido_id] = contrato


class LedgerEmMemoria:
    """Usa o `Livro` das regras puras (só inclusão, partidas dobradas, idempotente)."""

    def __init__(self, livro: Livro | None = None) -> None:
        self._livro = livro or Livro()
        self._trava = threading.Lock()

    @property
    def livro(self) -> Livro:
        return self._livro

    def lancar_varios(self, lancamentos: Sequence[Lancamento]) -> Sequence[Lancamento]:
        with self._trava:
            return self._livro.lancar_varios(lancamentos)

    def lancamentos(self, pedido_id: str | None = None) -> Sequence[Lancamento]:
        todos = self._livro.lancamentos
        return todos if pedido_id is None else tuple(i for i in todos if i.pedido_id == pedido_id)

    def saldo_da_conta(self, conta: Conta, pedido_id: str | None = None) -> int:
        return self._livro.saldo(conta, pedido_id)

    def saldos_pedido(self, pedido_id: str, profissional_id: str | None) -> SaldoPedido:
        return self._livro.saldos_pedido(pedido_id, profissional_id)


class DisputasEmMemoria:
    def __init__(self) -> None:
        self._itens: dict[str, Disputa] = {}

    def obter(self, pedido_id: str) -> Disputa | None:
        return self._itens.get(pedido_id)

    def salvar(self, pedido_id: str, disputa: Disputa) -> None:
        self._itens[pedido_id] = disputa


class GarantiasEmMemoria:
    def __init__(self) -> None:
        self._garantias: dict[str, Garantia] = {}
        self._retrabalhos: dict[str, list[Retrabalho]] = {}

    def obter_garantia(self, pedido_id: str) -> Garantia | None:
        return self._garantias.get(pedido_id)

    def salvar_garantia(self, pedido_id: str, garantia: Garantia) -> None:
        self._garantias[pedido_id] = garantia

    def retrabalhos(self, pedido_id: str) -> Sequence[Retrabalho]:
        return tuple(self._retrabalhos.get(pedido_id, ()))

    def salvar_retrabalho(self, pedido_id: str, retrabalho: Retrabalho) -> None:
        self._retrabalhos.setdefault(pedido_id, []).append(retrabalho)


class EventosWebhookEmMemoria(RegistroEventosEmMemoria):
    def __init__(self) -> None:
        super().__init__()
        self._eventos: list[EventoWebhook] = []

    def registrar(self, evento: EventoWebhook) -> None:
        self._eventos.append(evento)

    def listar(self) -> Sequence[EventoWebhook]:
        return tuple(self._eventos)


class ConfigEmMemoria:
    def __init__(self, config: ConfigApi) -> None:
        self._config = config

    def carregar(self) -> ConfigApi:
        return self._config
