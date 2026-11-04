"""Repositórios em memória, para testes e desenvolvimento. Não são o armazenamento real."""

from __future__ import annotations

import threading
import uuid
from collections.abc import Sequence
from dataclasses import replace
from datetime import datetime

from trato.api.repositorios import (
    ConfigApi,
    Contrato,
    DadosPedido,
    EtapaProposta,
    EventoWebhook,
    ItemOrcamento,
    Orcamento,
    Repasse,
)
from trato.api.repositorios_app import (
    ItemDoOrcamento,
    OrcamentoDetalhe,
    OrcamentoDoPedido,
    PedidoAberto,
)
from trato.disputas import Disputa
from trato.financeiro.ledger import Conta, Lancamento, Livro, SaldoPedido
from trato.garantias import Garantia, Retrabalho
from trato.pagamentos.idempotencia import RegistroEventosEmMemoria
from trato.pedidos.estados import Estado, Evento, Pedido
from trato.persistencia.erros import DadosInvalidos


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

    def listar_do_usuario(
        self, usuario_id: str, como_cliente: bool, limite: int = 100, offset: int = 0
    ) -> Sequence[Pedido]:
        campo = "cliente_id" if como_cliente else "profissional_id"
        achados = [p for p in self._pedidos.values() if getattr(p, campo) == usuario_id]
        ordenados = sorted(achados, key=lambda p: p.aberto_em, reverse=True)
        return ordenados[offset : offset + limite]

    def listar_abertos(
        self, profissional_id: str, limite: int = 100, offset: int = 0
    ) -> Sequence[PedidoAberto]:
        abertos = [
            p
            for p in self._pedidos.values()
            if p.estado is Estado.ABERTO and p.cliente_id != profissional_id
        ]
        abertos.sort(key=lambda p: p.aberto_em, reverse=True)
        saida = []
        for p in abertos[offset : offset + limite]:
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
        self._detalhes: dict[str, OrcamentoDetalhe] = {}
        for o in orcamentos:
            self._detalhes[o.id] = OrcamentoDetalhe(
                id=o.id,
                pedido_id=o.pedido_id,
                profissional_id=o.profissional_id,
                profissional_nome=None,
                versao=1,
                status="enviado",
                valor_centavos=o.valor_centavos,
                prazo_execucao_dias=None,
                validade_ate=None,
                garantia_dias=None,
                fora_do_escopo=None,
                sinal_material_centavos=None,
                observacoes=None,
                enviado_em=None,
                itens=(),
            )

    def adicionar(self, orcamento: Orcamento, detalhe: OrcamentoDetalhe | None = None) -> None:
        self._itens[orcamento.id] = orcamento
        if detalhe is not None:
            self._detalhes[orcamento.id] = detalhe
        elif orcamento.id not in self._detalhes:
            self._detalhes[orcamento.id] = OrcamentoDetalhe(
                id=orcamento.id,
                pedido_id=orcamento.pedido_id,
                profissional_id=orcamento.profissional_id,
                profissional_nome=None,
                versao=1,
                status="enviado",
                valor_centavos=orcamento.valor_centavos,
                prazo_execucao_dias=None,
                validade_ate=None,
                garantia_dias=None,
                fora_do_escopo=None,
                sinal_material_centavos=None,
                observacoes=None,
                enviado_em=None,
                itens=(),
            )

    def obter(self, orcamento_id: str) -> Orcamento | None:
        return self._itens.get(orcamento_id)

    def do_pedido(self, pedido_id: str) -> Sequence[OrcamentoDoPedido]:
        if self._detalhes:
            achados_det = [
                d
                for d in self._detalhes.values()
                if d.pedido_id == pedido_id and d.status in ("enviado", "aceito")
            ]
            achados_det.sort(key=lambda d: (d.valor_centavos, d.id))
            return tuple(
                OrcamentoDoPedido(
                    d.id,
                    d.profissional_id,
                    d.profissional_nome,
                    d.versao,
                    d.valor_centavos,
                    d.prazo_execucao_dias,
                    d.garantia_dias,
                    d.observacoes,
                    d.enviado_em,
                )
                for d in achados_det
            )
        achados = [o for o in self._itens.values() if o.pedido_id == pedido_id]
        achados.sort(key=lambda o: (o.valor_centavos, o.id))
        return tuple(
            OrcamentoDoPedido(
                o.id, o.profissional_id, None, 1, o.valor_centavos, None, None, None, None
            )
            for o in achados
        )

    def detalhe(self, orcamento_id: str) -> OrcamentoDetalhe | None:
        det = self._detalhes.get(orcamento_id)
        if det is not None:
            if det.status == "rascunho":
                return None
            return det
        o = self._itens.get(orcamento_id)
        if o is None:
            return None
        return OrcamentoDetalhe(
            o.id,
            o.pedido_id,
            o.profissional_id,
            None,
            1,
            "enviado",
            o.valor_centavos,
            None,
            None,
            None,
            None,
            None,
            None,
            None,
        )

    def enviar(
        self,
        *,
        pedido_id: str,
        profissional_id: str,
        itens: Sequence[ItemOrcamento],
        agora: datetime,
        etapas: Sequence[EtapaProposta] = (),
        prazo_execucao_dias: int | None = None,
        validade_ate: datetime | None = None,
        garantia_dias: int | None = None,
        fora_do_escopo: str | None = None,
        sinal_material_centavos: int | None = None,
        observacoes: str | None = None,
    ) -> str:
        if not itens:
            raise DadosInvalidos("O orçamento precisa de ao menos um item.")
        novo_id = str(uuid.uuid4())
        total = sum(i.total_centavos for i in itens)

        versoes_anteriores = [
            d.versao
            for d in self._detalhes.values()
            if d.pedido_id == pedido_id and d.profissional_id == profissional_id
        ]
        versao = max(versoes_anteriores, default=0) + 1

        for o_id, det in list(self._detalhes.items()):
            if (
                det.pedido_id == pedido_id
                and det.profissional_id == profissional_id
                and det.status == "enviado"
            ):
                self._detalhes[o_id] = OrcamentoDetalhe(
                    id=det.id,
                    pedido_id=det.pedido_id,
                    profissional_id=det.profissional_id,
                    profissional_nome=det.profissional_nome,
                    versao=det.versao,
                    status="substituido",
                    valor_centavos=det.valor_centavos,
                    prazo_execucao_dias=det.prazo_execucao_dias,
                    validade_ate=det.validade_ate,
                    garantia_dias=det.garantia_dias,
                    fora_do_escopo=det.fora_do_escopo,
                    sinal_material_centavos=det.sinal_material_centavos,
                    observacoes=det.observacoes,
                    enviado_em=det.enviado_em,
                    itens=det.itens,
                )

        itens_tupla = tuple(
            ItemDoOrcamento(
                tipo=i.tipo,
                descricao=i.descricao,
                quantidade=str(i.quantidade),
                valor_unitario_centavos=i.valor_unitario_centavos,
                total_centavos=i.total_centavos,
            )
            for i in itens
        )

        detalhe = OrcamentoDetalhe(
            id=novo_id,
            pedido_id=pedido_id,
            profissional_id=profissional_id,
            profissional_nome=None,
            versao=versao,
            status="enviado",
            valor_centavos=total,
            prazo_execucao_dias=prazo_execucao_dias,
            validade_ate=validade_ate,
            garantia_dias=garantia_dias,
            fora_do_escopo=fora_do_escopo,
            sinal_material_centavos=sinal_material_centavos,
            observacoes=observacoes,
            enviado_em=agora,
            itens=itens_tupla,
        )
        self._detalhes[novo_id] = detalhe
        self._itens[novo_id] = Orcamento(
            id=novo_id,
            pedido_id=pedido_id,
            profissional_id=profissional_id,
            valor_centavos=total,
            categoria_id="cat_demo",
        )
        return novo_id


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

    def listar(self) -> list[tuple[str, Disputa]]:
        return list(self._itens.items())


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
        """Abre o retrabalho ou, se já existe (mesma hora de abertura), grava a nova situação."""
        lista = self._retrabalhos.setdefault(pedido_id, [])
        for i, atual in enumerate(lista):
            if atual.aberto_em == retrabalho.aberto_em:
                lista[i] = retrabalho
                return
        lista.append(retrabalho)


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
