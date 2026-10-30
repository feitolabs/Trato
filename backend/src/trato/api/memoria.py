"""Repositórios em memória, para testes e desenvolvimento. Não são o armazenamento real."""

from __future__ import annotations

import threading
from collections.abc import Sequence
from dataclasses import replace
from datetime import datetime

from trato.api.repositorios import (
    ConfigApi,
    Contrato,
    DadosPedido,
    EventoWebhook,
    Orcamento,
    Repasse,
)
from trato.api.repositorios_app import OrcamentoDetalhe, OrcamentoDoPedido, PedidoAberto
from trato.disputas import Disputa
from trato.financeiro.ledger import Conta, Lancamento, Livro, SaldoPedido
from trato.garantias import Garantia, Retrabalho
from trato.pagamentos.idempotencia import RegistroEventosEmMemoria
from trato.pedidos.estados import Estado, Evento, Pedido


class PedidosEmMemoria:
    def __init__(self) -> None:
        self._pedidos: dict[str, Pedido] = {}
        self._eventos: dict[str, list[Evento]] = {}
        self._dados: dict[str, DadosPedido] = {}

    def obter(self, pedido_id: str) -> Pedido | None:
        return self._pedidos.get(pedido_id)

    def salvar(
        self, pedido: Pedido, evento: Evento | None = None, dados: DadosPedido | None = None
    ) -> Pedido:
        self._pedidos[pedido.id] = pedido
        if dados is not None:
            self._dados.setdefault(pedido.id, dados)
        lista = self._eventos.setdefault(pedido.id, [])
        if evento is not None:
            lista.append(evento)
        return pedido

    def eventos(self, pedido_id: str) -> Sequence[Evento]:
        return tuple(self._eventos.get(pedido_id, ()))

    def listar_do_usuario(self, usuario_id: str, como_cliente: bool) -> Sequence[Pedido]:
        campo = "cliente_id" if como_cliente else "profissional_id"
        achados = [p for p in self._pedidos.values() if getattr(p, campo) == usuario_id]
        return sorted(achados, key=lambda p: p.aberto_em, reverse=True)

    def listar_abertos(self, profissional_id: str) -> Sequence[PedidoAberto]:
        abertos = [p for p in self._pedidos.values() if p.estado is Estado.ABERTO]
        abertos.sort(key=lambda p: p.aberto_em, reverse=True)
        saida = []
        for p in abertos:
            d = self._dados.get(p.id)
            saida.append(
                PedidoAberto(
                    id=p.id,
                    titulo=d.titulo if d else "Pedido",
                    descricao=d.descricao if d else "",
                    bairro=d.bairro if d else None,
                    categoria_id=d.categoria_id if d else None,
                    faixa_preco_min_centavos=d.faixa_preco_min_centavos if d else None,
                    faixa_preco_max_centavos=d.faixa_preco_max_centavos if d else None,
                    urgente=d.urgente if d else False,
                    prazo_desejado=d.prazo_desejado if d else None,
                    aberto_em=p.aberto_em,
                )
            )
        return tuple(saida)


class OrcamentosEmMemoria:
    def __init__(self, orcamentos: Sequence[Orcamento] = ()) -> None:
        self._itens = {o.id: o for o in orcamentos}

    def adicionar(self, orcamento: Orcamento) -> None:
        self._itens[orcamento.id] = orcamento

    def obter(self, orcamento_id: str) -> Orcamento | None:
        return self._itens.get(orcamento_id)

    def do_pedido(self, pedido_id: str) -> Sequence[OrcamentoDoPedido]:
        achados = [o for o in self._itens.values() if o.pedido_id == pedido_id]
        achados.sort(key=lambda o: (o.valor_centavos, o.id))
        return tuple(
            OrcamentoDoPedido(
                o.id, o.profissional_id, None, 1, o.valor_centavos, None, None, None, None
            )
            for o in achados
        )

    def detalhe(self, orcamento_id: str) -> OrcamentoDetalhe | None:
        o = self._itens.get(orcamento_id)
        if o is None:
            return None
        return OrcamentoDetalhe(
            o.id, o.pedido_id, o.profissional_id, None, 1, "enviado", o.valor_centavos,
            None, None, None, None, None, None, None,
        )  # fmt: skip


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
        self._revisao: list[tuple[EventoWebhook, str]] = []

    def registrar(self, evento: EventoWebhook) -> None:
        self._eventos.append(evento)

    def descartar(self, evento: EventoWebhook) -> None:
        self._eventos = [e for e in self._eventos if e is not evento]

    def marcar_revisao(self, evento: EventoWebhook, motivo: str) -> None:
        self._revisao.append((evento, motivo))

    def em_revisao(self) -> Sequence[tuple[EventoWebhook, str]]:
        return tuple(self._revisao)

    def listar(self) -> Sequence[EventoWebhook]:
        return tuple(self._eventos)


class ConfigEmMemoria:
    def __init__(self, config: ConfigApi) -> None:
        self._config = config

    def carregar(self) -> ConfigApi:
        return self._config


class RepassesEmMemoria:
    def __init__(self) -> None:
        self._itens: dict[str, Repasse] = {}
        self._trava = threading.Lock()

    def criar(self, repasse: Repasse) -> Repasse:
        with self._trava:
            existente = self.por_chave(repasse.chave)
            if existente is not None:
                return existente
            self._itens[repasse.id] = repasse
            return repasse

    def obter(self, repasse_id: str) -> Repasse | None:
        return self._itens.get(repasse_id)

    def por_chave(self, chave: str) -> Repasse | None:
        return next((r for r in self._itens.values() if r.chave == chave), None)

    def por_transferencia(self, provedor_transferencia_id: str) -> Repasse | None:
        return next(
            (
                r
                for r in self._itens.values()
                if r.provedor_transferencia_id == provedor_transferencia_id
            ),
            None,
        )

    def do_pedido(self, pedido_id: str) -> Sequence[Repasse]:
        return tuple(r for r in self._itens.values() if r.pedido_id == pedido_id)

    def vincular_transferencia(self, repasse_id: str, provedor_transferencia_id: str) -> None:
        with self._trava:
            r = self._itens[repasse_id]
            if r.provedor_transferencia_id is None:
                self._itens[repasse_id] = replace(
                    r, provedor_transferencia_id=provedor_transferencia_id
                )

    def marcar_liberado(self, repasse_id: str, lancamento_id: str, em: datetime) -> None:
        from trato.persistencia.erros import ConflitoDeEstado

        with self._trava:
            r = self._itens[repasse_id]
            if r.status != "agendado":
                raise ConflitoDeEstado("Este repasse não está mais agendado.")
            self._itens[repasse_id] = replace(
                r, status="liberado", lancamento_id=lancamento_id, liberado_em=em
            )

    def congelar(self, repasse_id: str, disputa_id: str) -> None:
        with self._trava:
            r = self._itens[repasse_id]
            if r.status == "agendado":
                self._itens[repasse_id] = replace(r, status="congelado")
