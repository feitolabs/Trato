"""Moedas do Trato (gamificação, fase 1): bônus por avaliar e consulta de saldo.

Regras ficam aqui, no backend. O app só mostra. Livro separado do ledger de dinheiro:
lançamentos imutáveis, saldo = soma, idempotência por chave (uma avaliação = um bônus).
"""

from __future__ import annotations

import logging
import threading
import uuid
from collections.abc import Callable, Collection, Iterator
from contextlib import AbstractContextManager, contextmanager
from dataclasses import dataclass, replace
from datetime import date, datetime, timedelta
from typing import Any, Protocol

import psycopg

from trato.api.moedas_saldo import parcelas_do_gasto, saldo_disponivel
from trato.financeiro import periodo
from trato.persistencia.comum import como_uuid

MOTIVO_ORCAMENTO_ESGOTADO = "orcamento_esgotado"
MOTIVO_TETO_CLIENTE = "teto_cliente"
MOTIVO_LIMITE_DIARIO = "limite_diario"
MOTIVO_SALDO_INSUFICIENTE = "saldo_insuficiente"
MOTIVO_RESERVAS_ABERTAS = "reservas_abertas"
CARTEIRA_CLIENTE = "cliente"
CARTEIRA_PROFISSIONAL = "profissional"
TIPO_BONUS_CLIENTE = "bonus_avaliacao"
TIPO_BONUS_PROFISSIONAL = "bonus_avaliacao_profissional"
MARGEM_RESERVA_MINUTOS = 2  # a reserva dura um pouco mais que o Pix (que vence em reserva_minutos)
_NS_RESERVA = uuid.UUID("6f1c2a52-7d0e-4f0b-9a57-3c6c1f4d2a10")

log = logging.getLogger("trato.moedas")

# Termos 13.4 e I.5: sem prazo na configuração, o crédito novo vale 90 dias.
VALIDADE_PADRAO_DIAS = 90
# Termos 13.8 e I.9: devolução de Tratinhos já vencidos vira crédito novo com este prazo.
VALIDADE_DEVOLUCAO_VENCIDA_DIAS = 30


def vencimento_de_credito_novo(cfg: ConfigMoedas, agora: datetime) -> datetime:
    return agora + timedelta(days=cfg.validade_dias or VALIDADE_PADRAO_DIAS)


@dataclass(frozen=True)
class ConfigMoedas:
    ativo: bool = False
    bonus_avaliacao_moedas: int = 50
    valor_moeda_centavos: int = 1
    teto_mensal_moedas: int = 500
    min_servico_centavos: int = 5000
    max_bonus_por_profissional_mes: int = 1
    max_desconto_percentual: int = 20
    validade_dias: int | None = None
    # Orçamento mensal de desconto: a empresa paga o desconto, em centavos inteiros.
    orcamento_mensal_desconto_centavos: int = 30_000
    aviso_percentual: int = 80
    teto_desconto_cliente_mes_centavos: int = 500
    teto_diario_desconto_centavos: int = 1_000  # ~R$ 10/dia para distribuir os R$ 300 do mês
    dias_liberacao_bonus: int = 7  # o bônus de avaliação só vira saldo depois disto sem disputa
    max_reservas_abertas: int = 2  # cobranças com moedas ainda sem pagar, por cliente
    reserva_minutos: int = 30  # quanto tempo a reserva de uma cobrança pendente vale
    # Etapa B (Tratinhos do profissional e exclusividade). Só o bônus é usado nesta rodada.
    bonus_avaliacao_profissional_moedas: int = 50
    exclusividade_custo_moedas: int = 100
    exclusividade_duracao_horas: int = 48
    exclusividade_max_simultaneas: int = 3
    exclusividade_prazo_resposta_horas: int = 6
    exclusividade_bloqueio_recusa_dias: int = 30


def chave_reserva(cobranca_id: str) -> str:
    """Chave (uuid) da reserva de uma cobrança. O id da cobrança é o do provedor (texto): o uuid
    sai dele de forma estável, então `moedas_reservas.cobranca_id` nunca depende de coluna nova."""
    return str(uuid.uuid5(_NS_RESERVA, str(cobranca_id)))


@dataclass(frozen=True)
class ReservaMoeda:
    """Desconto de moedas reservado por UMA cobrança (`moedas_reservas`)."""

    cobranca_id: str  # `chave_reserva(...)`
    usuario_id: str
    mes_ref: date
    dia_ref: date
    moedas: int
    desconto_centavos: (
        int  # o valor GRAVADO na reserva: é ele que volta, nunca moedas × valor atual
    )
    expira_em: datetime
    status: str = "reservada"  # reservada | confirmada | devolvida


def mes_ref(instante: datetime) -> date:
    """Primeiro dia do mês no horário de Brasília (America/Sao_Paulo, UTC-3 fixo)."""
    ano, mes = periodo.mes_de(instante)
    return date(ano, mes, 1)


def dia_ref(instante: datetime) -> date:
    """Dia no horário de Brasília (America/Sao_Paulo): o teto diário vira à meia-noite de lá."""
    return instante.astimezone(periodo.BRASILIA).date()


@dataclass(frozen=True)
class PendenteMoeda:
    """Bônus de avaliação aguardando a liberação (`moedas_pendentes`). Ainda NÃO é saldo."""

    usuario_id: str
    pedido_id: str | None
    quantidade: int
    liberar_em: datetime
    chave_idempotencia: str
    criada_em: datetime
    parceiro_id: str | None = None
    status: str = "pendente"  # pendente | liberado | cancelado
    # bonus_avaliacao (cliente) | bonus_avaliacao_profissional (carteira do profissional)
    tipo_lancamento: str = "bonus_avaliacao"


@dataclass(frozen=True)
class LancamentoMoeda:
    usuario_id: str
    tipo: str
    quantidade: int
    chave_idempotencia: str
    criada_em: datetime
    referencia_id: str | None = None
    parceiro_id: str | None = None
    expira_em: datetime | None = None
    carteira: str = "cliente"  # 'cliente' (desconto) | 'profissional' (nunca vira desconto)


class RepositorioMoedas(Protocol):
    def config(self) -> ConfigMoedas: ...

    def salvar_config(self, config: ConfigMoedas) -> None: ...

    def lancar(self, lancamento: LancamentoMoeda) -> bool:
        """Grava o lançamento. False se a chave já existia (nada muda)."""
        ...

    def saldo(self, usuario_id: str, agora: datetime, carteira: str = "cliente") -> int:
        """Saldo da carteira (padrão: cliente, a única que vira desconto)."""
        ...

    def creditado_no_mes(self, usuario_id: str, tipo: str, desde: datetime) -> int: ...

    def existe(self, chave_idempotencia: str) -> bool: ...

    def lancamentos_da_carteira(
        self, usuario_id: str, carteira: str = "cliente"
    ) -> list[LancamentoMoeda]:
        """Todos os lançamentos da carteira (o saldo e o consumo por crédito saem deles)."""
        ...

    def trava(self, nome: str) -> AbstractContextManager[None]:
        """Uma operação por vez para o mesmo `nome` (ler os lançamentos e gravar sem corrida)."""
        ...

    def bonus_do_par(self, usuario_id: str, parceiro_id: str, desde: datetime) -> int: ...

    def extrato(
        self, usuario_id: str, limite: int = 50, carteira: str = "cliente"
    ) -> list[LancamentoMoeda]: ...

    def uso_liquido_no_mes(self, usuario_id: str, inicio: datetime, fim: datetime) -> int:
        """Moedas usadas no período: lançamentos 'uso' menos 'estorno' (valor positivo)."""
        ...

    def orcamento_usado(self, mes: date) -> int:
        """Centavos já reservados do orçamento do mês (0 se o mês não existe)."""
        ...

    def orcamento_usado_dia(self, dia: date) -> int:
        """Centavos já reservados no dia (0 se o dia não existe)."""
        ...

    def reservar_orcamento(
        self,
        mes: date,
        dia: date,
        valor_centavos: int,
        orcamento_mes_centavos: int,
        teto_dia_centavos: int,
    ) -> str:
        """Reserva ATÔMICA de mês E dia. 'ok' | 'orcamento_esgotado' | 'limite_diario'; se não for
        'ok', nada muda."""
        ...

    def devolver_orcamento(self, mes: date, dia: date, valor_centavos: int) -> int:
        """Devolve a reserva do mês e do dia (nunca abaixo de 0). Devolve o usado do mês."""
        ...

    # Reserva por cobrança (moedas_reservas): orçamento, teto do cliente e saldo, atômico.
    def reservar_desconto(
        self,
        cobranca_id: str,
        usuario_id: str,
        mes: date,
        dia: date,
        moedas: int,
        desconto_centavos: int,
        orcamento_mes_centavos: int,
        teto_dia_centavos: int,
        teto_cliente_mes_centavos: int,
        max_reservas_abertas: int,
        expira_em: datetime,
    ) -> str:
        """'ok' | 'ja_reservada' | 'orcamento_esgotado' | 'limite_diario' | 'teto_cliente' |
        'saldo_insuficiente' | 'reservas_abertas'. Se não for 'ok', nada muda."""
        ...

    def confirmar_reserva(self, cobranca_id: str) -> bool:
        """'reservada' -> 'confirmada' (o pagamento foi confirmado)."""
        ...

    def devolver_reserva(self, cobranca_id: str) -> int:
        """Devolve mês, dia e saldo reservado. Idempotente por status: devolve o desconto GRAVADO
        na reserva (0 se nada a devolver)."""
        ...

    def expirar_reservas(self, agora: datetime) -> list[str]:
        """Devolve as reservas 'reservada' vencidas e diz quais cobranças (chaves) expiraram."""
        ...

    def reservas_abertas_do_usuario(self, usuario_id: str) -> list[ReservaMoeda]:
        """Só as 'reservada' (pagamento ainda não confirmado)."""
        ...

    def reserva_status(self, cobranca_id: str) -> str | None:
        """'reservada' | 'confirmada' | 'devolvida', ou None se a cobrança não tem reserva."""
        ...

    # Bônus pendente (liberação depois de `dias_liberacao_bonus`).
    def criar_pendente(self, pendente: PendenteMoeda) -> bool:
        """False se a chave já existia (nada muda)."""
        ...

    def pendentes_do_usuario(
        self, usuario_id: str, tipo: str = "bonus_avaliacao"
    ) -> list[PendenteMoeda]:
        """Só os de status 'pendente' do tipo pedido (padrão: bônus do cliente)."""
        ...

    def pendentes_vencidos(self, agora: datetime) -> list[PendenteMoeda]:
        """Status 'pendente' com `liberar_em <= agora`, os mais antigos primeiro."""
        ...

    def marcar_pendente(self, chave_idempotencia: str, status: str) -> bool:
        """'pendente' -> 'liberado' ou 'cancelado'. False se não estava pendente."""
        ...


class MoedasEmMemoria:
    def __init__(self, config: ConfigMoedas | None = None) -> None:
        self._config = config or ConfigMoedas()
        self._itens: dict[str, LancamentoMoeda] = {}
        self._orcamento: dict[date, int] = {}
        self._orcamento_dia: dict[date, int] = {}
        self._pendentes: dict[str, PendenteMoeda] = {}
        self._reservas: dict[str, ReservaMoeda] = {}
        self._trava = threading.Lock()  # a reserva em memória é atômica como a do banco
        self._travas_nomeadas: dict[str, Any] = {}

    def config(self) -> ConfigMoedas:
        return self._config

    def salvar_config(self, config: ConfigMoedas) -> None:
        self._config = config

    def lancar(self, lancamento: LancamentoMoeda) -> bool:
        if lancamento.chave_idempotencia in self._itens:
            return False
        self._itens[lancamento.chave_idempotencia] = lancamento
        return True

    def saldo(self, usuario_id: str, agora: datetime, carteira: str = "cliente") -> int:
        return saldo_disponivel(self.lancamentos_da_carteira(usuario_id, carteira), agora)

    def lancamentos_da_carteira(
        self, usuario_id: str, carteira: str = "cliente"
    ) -> list[LancamentoMoeda]:
        return [
            i
            for i in list(self._itens.values())
            if i.usuario_id == usuario_id and i.carteira == carteira
        ]

    @contextmanager
    def trava(self, nome: str) -> Iterator[None]:
        with self._trava:
            lock = self._travas_nomeadas.setdefault(nome, threading.RLock())
        with lock:
            yield

    def creditado_no_mes(self, usuario_id: str, tipo: str, desde: datetime) -> int:
        return sum(
            i.quantidade
            for i in self._itens.values()
            if i.usuario_id == usuario_id and i.tipo == tipo and i.criada_em >= desde
        )

    def existe(self, chave_idempotencia: str) -> bool:
        return chave_idempotencia in self._itens

    def restauracao_disponivel(self) -> bool:
        return True

    def restauracao_devida(
        self, medida_id: str, usuario_id: str, carteira: str, inicio: datetime, agora: datetime
    ) -> int:
        """Saldo válido no início do encerramento menos o válido agora (como no banco)."""
        todos = self.lancamentos_da_carteira(usuario_id, carteira)
        antes = saldo_disponivel([x for x in todos if x.criada_em <= inicio], inicio)
        return max(0, antes - saldo_disponivel(todos, max(agora, inicio)))

    def restaurar(self, lancamento: LancamentoMoeda) -> bool:
        return self.lancar(lancamento)

    def bonus_do_par(self, usuario_id: str, parceiro_id: str, desde: datetime) -> int:
        return sum(
            1
            for i in self._itens.values()
            if i.usuario_id == usuario_id
            and i.parceiro_id == parceiro_id
            and i.tipo == "bonus_avaliacao"
            and i.criada_em >= desde
        )

    def extrato(
        self, usuario_id: str, limite: int = 50, carteira: str = "cliente"
    ) -> list[LancamentoMoeda]:
        meus = [
            i for i in self._itens.values() if i.usuario_id == usuario_id and i.carteira == carteira
        ]
        return sorted(meus, key=lambda i: i.criada_em, reverse=True)[:limite]

    def uso_liquido_no_mes(self, usuario_id: str, inicio: datetime, fim: datetime) -> int:
        return -sum(
            i.quantidade
            for i in self._itens.values()
            if i.usuario_id == usuario_id
            and i.tipo in ("uso", "estorno")
            and inicio <= i.criada_em < fim
        )

    def orcamento_usado(self, mes: date) -> int:
        return self._orcamento.get(mes.replace(day=1), 0)

    def orcamento_usado_dia(self, dia: date) -> int:
        return self._orcamento_dia.get(dia, 0)

    def reservar_orcamento(
        self,
        mes: date,
        dia: date,
        valor_centavos: int,
        orcamento_mes_centavos: int,
        teto_dia_centavos: int,
    ) -> str:
        if valor_centavos <= 0:
            raise ValueError("valor da reserva deve ser positivo")
        chave_mes = mes.replace(day=1)
        with self._trava:  # mês e dia na mesma trava: ou reserva os dois ou nenhum
            usado_dia = self._orcamento_dia.get(dia, 0)
            if usado_dia + valor_centavos > teto_dia_centavos:
                return MOTIVO_LIMITE_DIARIO
            usado_mes = self._orcamento.get(chave_mes, 0)
            if usado_mes + valor_centavos > orcamento_mes_centavos:
                return MOTIVO_ORCAMENTO_ESGOTADO
            self._orcamento_dia[dia] = usado_dia + valor_centavos
            self._orcamento[chave_mes] = usado_mes + valor_centavos
            return "ok"

    def devolver_orcamento(self, mes: date, dia: date, valor_centavos: int) -> int:
        chave_mes = mes.replace(day=1)
        valor = max(valor_centavos, 0)
        with self._trava:
            if dia in self._orcamento_dia:
                self._orcamento_dia[dia] = max(self._orcamento_dia[dia] - valor, 0)
            usado = max(self._orcamento.get(chave_mes, 0) - valor, 0)
            if chave_mes in self._orcamento:
                self._orcamento[chave_mes] = usado
            return usado

    def reservar_desconto(
        self,
        cobranca_id: str,
        usuario_id: str,
        mes: date,
        dia: date,
        moedas: int,
        desconto_centavos: int,
        orcamento_mes_centavos: int,
        teto_dia_centavos: int,
        teto_cliente_mes_centavos: int,
        max_reservas_abertas: int,
        expira_em: datetime,
    ) -> str:
        if moedas <= 0 or desconto_centavos <= 0:
            raise ValueError("reserva precisa de moedas e desconto positivos")
        chave_mes = mes.replace(day=1)
        with self._trava:  # tudo na mesma trava: ou reserva tudo ou nada (como a função do banco)
            if cobranca_id in self._reservas:
                return "ja_reservada"
            do_usuario = [r for r in self._reservas.values() if r.usuario_id == usuario_id]
            abertas = [r for r in do_usuario if r.status == "reservada"]
            # Mesma ordem da função SQL: saldo, reservas abertas, teto do cliente, dia, mês.
            # `saldo` ignora expiração aqui de propósito: usa o relógio da própria reserva.
            if self._saldo_bruto(usuario_id, expira_em) - sum(r.moedas for r in abertas) < moedas:
                return MOTIVO_SALDO_INSUFICIENTE
            if len(abertas) >= max_reservas_abertas:
                return MOTIVO_RESERVAS_ABERTAS
            do_mes = sum(
                r.desconto_centavos
                for r in do_usuario
                if r.mes_ref == chave_mes and r.status in ("reservada", "confirmada")
            )
            if do_mes + desconto_centavos > teto_cliente_mes_centavos:
                return MOTIVO_TETO_CLIENTE
            usado_dia = self._orcamento_dia.get(dia, 0)
            if usado_dia + desconto_centavos > teto_dia_centavos:
                return MOTIVO_LIMITE_DIARIO
            usado_mes = self._orcamento.get(chave_mes, 0)
            if usado_mes + desconto_centavos > orcamento_mes_centavos:
                return MOTIVO_ORCAMENTO_ESGOTADO
            self._orcamento[chave_mes] = usado_mes + desconto_centavos
            self._orcamento_dia[dia] = usado_dia + desconto_centavos
            self._reservas[cobranca_id] = ReservaMoeda(
                cobranca_id, usuario_id, chave_mes, dia, moedas, desconto_centavos, expira_em
            )
            return "ok"

    def _saldo_bruto(self, usuario_id: str, agora: datetime) -> int:
        return self.saldo(usuario_id, agora)

    def confirmar_reserva(self, cobranca_id: str) -> bool:
        with self._trava:
            r = self._reservas.get(cobranca_id)
            if r is None or r.status != "reservada":
                return False
            self._reservas[cobranca_id] = replace(r, status="confirmada")
            return True

    def _devolver_locked(self, r: ReservaMoeda) -> int:
        self._reservas[r.cobranca_id] = replace(r, status="devolvida")
        self._orcamento[r.mes_ref] = max(self._orcamento.get(r.mes_ref, 0) - r.desconto_centavos, 0)
        self._orcamento_dia[r.dia_ref] = max(
            self._orcamento_dia.get(r.dia_ref, 0) - r.desconto_centavos, 0
        )
        return r.desconto_centavos

    def devolver_reserva(self, cobranca_id: str) -> int:
        with self._trava:
            r = self._reservas.get(cobranca_id)
            if r is None or r.status == "devolvida":
                return 0
            return self._devolver_locked(r)

    def expirar_reservas(self, agora: datetime) -> list[str]:
        with self._trava:
            vencidas = [
                r
                for r in self._reservas.values()
                if r.status == "reservada" and r.expira_em <= agora
            ]
            for r in vencidas:
                self._devolver_locked(r)
            return [r.cobranca_id for r in vencidas]

    def reserva_status(self, cobranca_id: str) -> str | None:
        r = self._reservas.get(cobranca_id)
        return r.status if r is not None else None

    def reservas_abertas_do_usuario(self, usuario_id: str) -> list[ReservaMoeda]:
        return [
            r
            for r in self._reservas.values()
            if r.usuario_id == usuario_id and r.status == "reservada"
        ]

    def criar_pendente(self, pendente: PendenteMoeda) -> bool:
        with self._trava:  # duas avaliações ao mesmo tempo: só uma cria
            if pendente.chave_idempotencia in self._pendentes:
                return False
            self._pendentes[pendente.chave_idempotencia] = pendente
            return True

    def pendentes_do_usuario(
        self, usuario_id: str, tipo: str = "bonus_avaliacao"
    ) -> list[PendenteMoeda]:
        return [
            p
            for p in self._pendentes.values()
            if p.usuario_id == usuario_id and p.status == "pendente" and p.tipo_lancamento == tipo
        ]

    def pendentes_vencidos(self, agora: datetime) -> list[PendenteMoeda]:
        vencidos = [
            p for p in self._pendentes.values() if p.status == "pendente" and p.liberar_em <= agora
        ]
        return sorted(vencidos, key=lambda p: p.liberar_em)

    def marcar_pendente(self, chave_idempotencia: str, status: str) -> bool:
        atual = self._pendentes.get(chave_idempotencia)
        if atual is None or atual.status != "pendente":
            return False
        self._pendentes[chave_idempotencia] = replace(atual, status=status)
        return True


class MoedasPostgres:
    def __init__(self, banco: Any) -> None:
        self._banco = banco

    # Colunas por migration: se a mais nova ainda não existe, a leitura cai nos padrões dela (e só
    # dela), sem quebrar. O primeiro nível é o que vale com as duas migrations aplicadas.
    _BASE = (
        "ativo", "bonus_avaliacao_moedas", "valor_moeda_centavos", "teto_mensal_moedas",
        "min_servico_centavos", "max_bonus_por_profissional_mes", "max_desconto_percentual",
        "validade_dias",
    )  # fmt: skip
    _ORCAMENTO = (
        "orcamento_mensal_desconto_centavos", "aviso_percentual",
        "teto_desconto_cliente_mes_centavos", "teto_diario_desconto_centavos",
        "dias_liberacao_bonus",
    )  # fmt: skip
    _RESERVAS = ("max_reservas_abertas", "reserva_minutos")
    _EXCLUSIVIDADE = (
        "bonus_avaliacao_profissional_moedas", "exclusividade_custo_moedas",
        "exclusividade_duracao_horas", "exclusividade_max_simultaneas",
        "exclusividade_prazo_resposta_horas", "exclusividade_bloqueio_recusa_dias",
    )  # fmt: skip
    _NIVEIS = (
        _BASE + _ORCAMENTO + _RESERVAS + _EXCLUSIVIDADE,
        _BASE + _ORCAMENTO + _RESERVAS,
        _BASE + _ORCAMENTO,
        _BASE,
    )

    def config(self) -> ConfigMoedas:
        linha = None
        ultimo: Exception | None = None
        for colunas in self._NIVEIS:
            try:
                with self._banco.transacao() as con:
                    linha = con.execute(
                        f"select {', '.join(colunas)} from public.moedas_config where id"  # noqa: S608
                    ).fetchone()
            except Exception as erro:  # noqa: BLE001 - coluna ainda não existe: tenta o nível abaixo
                ultimo = erro
                continue
            break
        else:
            raise ultimo  # type: ignore[misc]  # nem as colunas base existem: erro de verdade
        if linha is None:
            return ConfigMoedas()
        extras = {
            c: int(linha[c])
            for c in (*self._ORCAMENTO, *self._RESERVAS, *self._EXCLUSIVIDADE)
            if c in linha
        }
        return ConfigMoedas(
            ativo=bool(linha["ativo"]),
            bonus_avaliacao_moedas=int(linha["bonus_avaliacao_moedas"]),
            valor_moeda_centavos=int(linha["valor_moeda_centavos"]),
            teto_mensal_moedas=int(linha["teto_mensal_moedas"]),
            min_servico_centavos=int(linha["min_servico_centavos"]),
            max_bonus_por_profissional_mes=int(linha["max_bonus_por_profissional_mes"]),
            max_desconto_percentual=int(linha["max_desconto_percentual"]),
            validade_dias=linha["validade_dias"],
            **extras,
        )

    def salvar_config(self, config: ConfigMoedas) -> None:
        valores = {
            c: getattr(config, c)
            for c in (*self._BASE, *self._ORCAMENTO, *self._RESERVAS, *self._EXCLUSIVIDADE)
        }
        for colunas in self._NIVEIS[:3]:
            try:
                with self._banco.transacao() as con:
                    con.execute(
                        "update public.moedas_config set "  # noqa: S608
                        + ", ".join(f"{c} = %s" for c in colunas)
                        + ", atualizado_em = now() where id",
                        tuple(valores[c] for c in colunas),
                    )
                return
            except Exception:  # noqa: BLE001, S112 - migration das reservas ainda não aplicada
                continue
        with self._banco.transacao() as con:
            con.execute(
                "update public.moedas_config set "  # noqa: S608
                + ", ".join(f"{c} = %s" for c in self._BASE)
                + ", atualizado_em = now() where id",
                tuple(valores[c] for c in self._BASE),
            )

    def lancar(self, lancamento: LancamentoMoeda) -> bool:
        uid = como_uuid(lancamento.usuario_id)
        if uid is None:
            return False
        valores = (
            uid,
            lancamento.tipo,
            lancamento.quantidade,
            lancamento.chave_idempotencia,
            como_uuid(lancamento.referencia_id),
            como_uuid(lancamento.parceiro_id),
            lancamento.expira_em,
            lancamento.criada_em,
        )
        with self._banco.transacao() as con:
            if lancamento.carteira == CARTEIRA_CLIENTE:
                # A carteira 'cliente' é o padrão da coluna: o insert não depende dela existir.
                linha = con.execute(
                    "insert into public.moedas_lancamentos (usuario_id, tipo, quantidade, "
                    "chave_idempotencia, referencia_id, parceiro_id, expira_em, criada_em) "
                    "values (%s, %s, %s, %s, %s, %s, %s, %s) "
                    "on conflict (chave_idempotencia) do nothing returning id",
                    valores,
                ).fetchone()
            else:
                # Carteira do profissional: precisa da coluna nova (sem ela o insert falha e
                # quem chamou trata como "não creditou": fail-closed).
                linha = con.execute(
                    "insert into public.moedas_lancamentos (usuario_id, tipo, quantidade, "
                    "chave_idempotencia, referencia_id, parceiro_id, expira_em, criada_em, "
                    "carteira) values (%s, %s, %s, %s, %s, %s, %s, %s, %s) "
                    "on conflict (chave_idempotencia) do nothing returning id",
                    (*valores, lancamento.carteira),
                ).fetchone()
        return linha is not None

    def saldo(self, usuario_id: str, agora: datetime, carteira: str = "cliente") -> int:
        return saldo_disponivel(self.lancamentos_da_carteira(usuario_id, carteira), agora)

    def lancamentos_da_carteira(
        self, usuario_id: str, carteira: str = "cliente"
    ) -> list[LancamentoMoeda]:
        uid = como_uuid(usuario_id)
        if uid is None:
            return []
        colunas = "tipo, quantidade, chave_idempotencia, expira_em, criada_em"
        try:
            with self._banco.transacao() as con:
                linhas = con.execute(
                    f"select {colunas} from public.moedas_lancamentos "  # noqa: S608
                    "where usuario_id = %s and carteira = %s",
                    (uid, carteira),
                ).fetchall()
        except Exception:  # noqa: BLE001 - coluna `carteira` ainda não existe: tudo é do cliente
            if carteira != CARTEIRA_CLIENTE:
                return []
            with self._banco.transacao() as con:
                linhas = con.execute(
                    f"select {colunas} from public.moedas_lancamentos "  # noqa: S608
                    "where usuario_id = %s",
                    (uid,),
                ).fetchall()
        return [
            LancamentoMoeda(
                usuario_id=usuario_id,
                tipo=l["tipo"],
                quantidade=int(l["quantidade"]),
                chave_idempotencia=l["chave_idempotencia"],
                criada_em=l["criada_em"],
                expira_em=l["expira_em"],
                carteira=carteira,
            )
            for l in linhas  # noqa: E741
        ]

    @contextmanager
    def trava(self, nome: str) -> Iterator[None]:
        # Trava só deste nome até o COMMIT: duas máquinas não devolvem a mesma moeda.
        with self._banco.transacao() as con:
            con.execute(
                "select pg_advisory_xact_lock(hashtextextended(%s, 0))", (f"moedas|{nome}",)
            )
            yield

    def creditado_no_mes(self, usuario_id: str, tipo: str, desde: datetime) -> int:
        uid = como_uuid(usuario_id)
        if uid is None:
            return 0
        with self._banco.transacao() as con:
            l = con.execute(  # noqa: E741
                "select coalesce(sum(quantidade), 0) as total from public.moedas_lancamentos "
                "where usuario_id = %s and tipo = %s and criada_em >= %s",
                (uid, tipo, desde),
            ).fetchone()
        return int(l["total"])

    def restauracao_disponivel(self) -> bool:
        with self._banco.transacao() as con:
            return con.execute(
                "select to_regprocedure("
                "'public.moedas_restauracao_devida(uuid,text,timestamptz)') is not null as tem"
            ).fetchone()["tem"]

    def restauracao_devida(
        self, medida_id: str, usuario_id: str, carteira: str, inicio: datetime, agora: datetime
    ) -> int:
        mid = como_uuid(medida_id)
        if mid is None:
            return 0
        with self._banco.transacao() as con:
            linha = con.execute(
                "select public.moedas_restauracao_devida(%s, %s, %s) as q", (mid, carteira, agora)
            ).fetchone()
        return int(linha["q"] or 0)

    def restaurar(self, lancamento: LancamentoMoeda) -> bool:
        """Num ponto de retorno: se o banco recusar a regra, o resto da transação continua."""
        with self._banco.transacao() as con:
            try:
                with con.transaction():
                    linha = con.execute(
                        "insert into public.moedas_lancamentos (usuario_id, tipo, quantidade, "
                        "chave_idempotencia, referencia_id, expira_em, criada_em, carteira) "
                        "values (%s, 'restauracao', %s, %s, %s, %s, %s, %s) "
                        "on conflict (chave_idempotencia) do nothing returning id",
                        (
                            como_uuid(lancamento.usuario_id),
                            lancamento.quantidade,
                            lancamento.chave_idempotencia,
                            como_uuid(lancamento.referencia_id),
                            lancamento.expira_em,
                            lancamento.criada_em,
                            lancamento.carteira,
                        ),
                    ).fetchone()
            except psycopg.errors.CheckViolation:
                log.warning(
                    "o banco recusou a restauração %s",
                    lancamento.chave_idempotencia,
                    exc_info=True,
                )
                return False
        return linha is not None

    def existe(self, chave_idempotencia: str) -> bool:
        with self._banco.transacao() as con:
            l = con.execute(  # noqa: E741
                "select 1 from public.moedas_lancamentos where chave_idempotencia = %s",
                (chave_idempotencia,),
            ).fetchone()
        return l is not None

    def bonus_do_par(self, usuario_id: str, parceiro_id: str, desde: datetime) -> int:
        uid, pid = como_uuid(usuario_id), como_uuid(parceiro_id)
        if uid is None or pid is None:
            return 0
        with self._banco.transacao() as con:
            l = con.execute(  # noqa: E741
                "select count(*) as total from public.moedas_lancamentos "
                "where usuario_id = %s and parceiro_id = %s and tipo = 'bonus_avaliacao' "
                "and criada_em >= %s",
                (uid, pid, desde),
            ).fetchone()
        return int(l["total"])

    def extrato(
        self, usuario_id: str, limite: int = 50, carteira: str = "cliente"
    ) -> list[LancamentoMoeda]:
        uid = como_uuid(usuario_id)
        if uid is None:
            return []
        try:
            with self._banco.transacao() as con:
                linhas = con.execute(
                    "select usuario_id, tipo, quantidade, chave_idempotencia, referencia_id, "
                    "expira_em, criada_em from public.moedas_lancamentos "
                    "where usuario_id = %s and carteira = %s order by criada_em desc limit %s",
                    (uid, carteira, limite),
                ).fetchall()
        except Exception:  # noqa: BLE001 - coluna `carteira` ainda não existe: tudo é do cliente
            if carteira != CARTEIRA_CLIENTE:
                return []
            with self._banco.transacao() as con:
                linhas = con.execute(
                    "select usuario_id, tipo, quantidade, chave_idempotencia, referencia_id, "
                    "expira_em, criada_em from public.moedas_lancamentos "
                    "where usuario_id = %s order by criada_em desc limit %s",
                    (uid, limite),
                ).fetchall()
        return [
            LancamentoMoeda(
                usuario_id=str(l["usuario_id"]),
                tipo=l["tipo"],
                quantidade=int(l["quantidade"]),
                chave_idempotencia=l["chave_idempotencia"],
                criada_em=l["criada_em"],
                referencia_id=str(l["referencia_id"]) if l["referencia_id"] else None,
                expira_em=l["expira_em"],
            )
            for l in linhas  # noqa: E741
        ]

    def uso_liquido_no_mes(self, usuario_id: str, inicio: datetime, fim: datetime) -> int:
        uid = como_uuid(usuario_id)
        if uid is None:
            return 0
        with self._banco.transacao() as con:
            l = con.execute(  # noqa: E741
                "select coalesce(sum(quantidade), 0) as total from public.moedas_lancamentos "
                "where usuario_id = %s and tipo in ('uso', 'estorno') "
                "and criada_em >= %s and criada_em < %s",
                (uid, inicio, fim),
            ).fetchone()
        return -int(l["total"])

    def orcamento_usado(self, mes: date) -> int:
        with self._banco.transacao() as con:
            l = con.execute(  # noqa: E741
                "select usado_centavos from public.moedas_orcamento_mensal where mes_ref = %s",
                (mes.replace(day=1),),
            ).fetchone()
        return int(l["usado_centavos"]) if l is not None else 0

    def orcamento_usado_dia(self, dia: date) -> int:
        with self._banco.transacao() as con:
            l = con.execute(  # noqa: E741
                "select usado_centavos from public.moedas_orcamento_diario where dia_ref = %s",
                (dia,),
            ).fetchone()
        return int(l["usado_centavos"]) if l is not None else 0

    def reservar_orcamento(
        self,
        mes: date,
        dia: date,
        valor_centavos: int,
        orcamento_mes_centavos: int,
        teto_dia_centavos: int,
    ) -> str:
        # A função do banco reserva mês e dia numa só transação (atômica) e diz o motivo se negar.
        with self._banco.transacao() as con:
            l = con.execute(  # noqa: E741
                "select public.moedas_reservar_orcamento(%s, %s, %s, %s, %s) as r",
                (
                    mes.replace(day=1),
                    dia,
                    valor_centavos,
                    orcamento_mes_centavos,
                    teto_dia_centavos,
                ),
            ).fetchone()
        return str(l["r"])

    def devolver_orcamento(self, mes: date, dia: date, valor_centavos: int) -> int:
        with self._banco.transacao() as con:
            l = con.execute(  # noqa: E741
                "select public.moedas_devolver_orcamento(%s, %s, %s) as usado",
                (mes.replace(day=1), dia, max(valor_centavos, 0)),
            ).fetchone()
        return int(l["usado"])

    def reservar_desconto(
        self,
        cobranca_id: str,
        usuario_id: str,
        mes: date,
        dia: date,
        moedas: int,
        desconto_centavos: int,
        orcamento_mes_centavos: int,
        teto_dia_centavos: int,
        teto_cliente_mes_centavos: int,
        max_reservas_abertas: int,
        expira_em: datetime,
    ) -> str:
        uid = como_uuid(usuario_id)
        if uid is None:
            raise ValueError("usuário inválido para a reserva")
        # Orçamento do mês + dia, teto do cliente e saldo: tudo numa função/transação do banco.
        with self._banco.transacao() as con:
            l = con.execute(  # noqa: E741
                "select public.moedas_reservar_desconto("
                "%s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s) "
                "as r",
                (
                    como_uuid(cobranca_id),
                    uid,
                    mes.replace(day=1),
                    dia,
                    moedas,
                    desconto_centavos,
                    orcamento_mes_centavos,
                    teto_dia_centavos,
                    teto_cliente_mes_centavos,
                    max_reservas_abertas,
                    expira_em,
                ),
            ).fetchone()
        return str(l["r"])

    def confirmar_reserva(self, cobranca_id: str) -> bool:
        with self._banco.transacao() as con:
            l = con.execute(  # noqa: E741
                "select public.moedas_confirmar_reserva(%s) as ok", (como_uuid(cobranca_id),)
            ).fetchone()
        return bool(l["ok"])

    def devolver_reserva(self, cobranca_id: str) -> int:
        with self._banco.transacao() as con:
            l = con.execute(  # noqa: E741
                "select public.moedas_devolver_reserva(%s) as valor", (como_uuid(cobranca_id),)
            ).fetchone()
        return int(l["valor"] or 0)

    def expirar_reservas(self, agora: datetime) -> list[str]:
        with self._banco.transacao() as con:
            linhas = con.execute(
                "select public.moedas_expirar_reservas(%s) as id", (agora,)
            ).fetchall()
        return [str(l["id"]) for l in linhas]  # noqa: E741

    def reserva_status(self, cobranca_id: str) -> str | None:
        with self._banco.transacao() as con:
            l = con.execute(  # noqa: E741
                "select status from public.moedas_reservas where cobranca_id = %s",
                (como_uuid(cobranca_id),),
            ).fetchone()
        return str(l["status"]) if l is not None else None

    def reservas_abertas_do_usuario(self, usuario_id: str) -> list[ReservaMoeda]:
        uid = como_uuid(usuario_id)
        if uid is None:
            return []
        with self._banco.transacao() as con:
            linhas = con.execute(
                "select cobranca_id, usuario_id, mes_ref, dia_ref, moedas, desconto_centavos, "
                "expira_em, status from public.moedas_reservas "
                "where usuario_id = %s and status = 'reservada'",
                (uid,),
            ).fetchall()
        return [
            ReservaMoeda(
                cobranca_id=str(l["cobranca_id"]),
                usuario_id=str(l["usuario_id"]),
                mes_ref=l["mes_ref"],
                dia_ref=l["dia_ref"],
                moedas=int(l["moedas"]),
                desconto_centavos=int(l["desconto_centavos"]),
                expira_em=l["expira_em"],
                status=l["status"],
            )
            for l in linhas  # noqa: E741
        ]

    def criar_pendente(self, pendente: PendenteMoeda) -> bool:
        uid = como_uuid(pendente.usuario_id)
        if uid is None:
            return False
        valores = (
            uid,
            como_uuid(pendente.pedido_id),
            pendente.quantidade,
            pendente.liberar_em,
            pendente.chave_idempotencia,
            como_uuid(pendente.parceiro_id),
            pendente.criada_em,
        )
        with self._banco.transacao() as con:
            if pendente.tipo_lancamento == TIPO_BONUS_CLIENTE:
                # O tipo do cliente é o padrão da coluna: o insert não depende dela existir.
                l = con.execute(  # noqa: E741
                    "insert into public.moedas_pendentes (usuario_id, pedido_id, quantidade, "
                    "liberar_em, status, chave_idempotencia, parceiro_id, criada_em) "
                    "values (%s, %s, %s, %s, 'pendente', %s, %s, %s) "
                    "on conflict (chave_idempotencia) do nothing returning id",
                    valores,
                ).fetchone()
            else:
                # Bônus do profissional: precisa da coluna nova (sem ela falha: fail-closed).
                l = con.execute(  # noqa: E741
                    "insert into public.moedas_pendentes (usuario_id, pedido_id, quantidade, "
                    "liberar_em, status, chave_idempotencia, parceiro_id, criada_em, "
                    "tipo_lancamento) values (%s, %s, %s, %s, 'pendente', %s, %s, %s, %s) "
                    "on conflict do nothing returning id",
                    (*valores, pendente.tipo_lancamento),
                ).fetchone()
        return l is not None

    @staticmethod
    def _pendente(l: dict[str, Any]) -> PendenteMoeda:  # noqa: E741
        return PendenteMoeda(
            usuario_id=str(l["usuario_id"]),
            pedido_id=str(l["pedido_id"]) if l["pedido_id"] else None,
            quantidade=int(l["quantidade"]),
            liberar_em=l["liberar_em"],
            chave_idempotencia=l["chave_idempotencia"],
            criada_em=l["criada_em"],
            parceiro_id=str(l["parceiro_id"]) if l["parceiro_id"] else None,
            status=l["status"],
            tipo_lancamento=l.get("tipo_lancamento") or TIPO_BONUS_CLIENTE,
        )

    def pendentes_do_usuario(
        self, usuario_id: str, tipo: str = "bonus_avaliacao"
    ) -> list[PendenteMoeda]:
        uid = como_uuid(usuario_id)
        if uid is None:
            return []
        try:
            with self._banco.transacao() as con:
                linhas = con.execute(
                    "select usuario_id, pedido_id, quantidade, liberar_em, chave_idempotencia, "
                    "criada_em, parceiro_id, status, tipo_lancamento from public.moedas_pendentes "
                    "where usuario_id = %s and status = 'pendente' and tipo_lancamento = %s "
                    "order by liberar_em",
                    (uid, tipo),
                ).fetchall()
        except Exception:  # noqa: BLE001 - coluna `tipo_lancamento` ainda não existe
            if tipo != TIPO_BONUS_CLIENTE:
                return []
            with self._banco.transacao() as con:
                linhas = con.execute(
                    "select usuario_id, pedido_id, quantidade, liberar_em, chave_idempotencia, "
                    "criada_em, parceiro_id, status from public.moedas_pendentes "
                    "where usuario_id = %s and status = 'pendente' order by liberar_em",
                    (uid,),
                ).fetchall()
        return [self._pendente(l) for l in linhas]  # noqa: E741

    def pendentes_vencidos(self, agora: datetime) -> list[PendenteMoeda]:
        try:
            with self._banco.transacao() as con:
                linhas = con.execute(
                    "select usuario_id, pedido_id, quantidade, liberar_em, chave_idempotencia, "
                    "criada_em, parceiro_id, status, tipo_lancamento from public.moedas_pendentes "
                    "where status = 'pendente' and liberar_em <= %s order by liberar_em limit 500",
                    (agora,),
                ).fetchall()
        except Exception:  # noqa: BLE001 - coluna `tipo_lancamento` ainda não existe
            with self._banco.transacao() as con:
                linhas = con.execute(
                    "select usuario_id, pedido_id, quantidade, liberar_em, chave_idempotencia, "
                    "criada_em, parceiro_id, status from public.moedas_pendentes "
                    "where status = 'pendente' and liberar_em <= %s order by liberar_em limit 500",
                    (agora,),
                ).fetchall()
        return [self._pendente(l) for l in linhas]  # noqa: E741

    def marcar_pendente(self, chave_idempotencia: str, status: str) -> bool:
        with self._banco.transacao() as con:
            l = con.execute(  # noqa: E741
                "update public.moedas_pendentes set status = %s "
                "where chave_idempotencia = %s and status = 'pendente' returning id",
                (status, chave_idempotencia),
            ).fetchone()
        return l is not None


def _apurar_bonus_avaliacao(
    repo: RepositorioMoedas,
    *,
    cliente_id: str,
    agora: datetime,
    profissional_id: str | None,
    valor_servico_centavos: int,
) -> tuple[int, bool]:
    """Quanto o bônus de avaliação vale agora (0 se não vale) e se vai para pendentes.

    Só LÊ: a mesma regra serve para conceder e para avisar o app antes de avaliar.
    """
    cfg = repo.config()
    if not cfg.ativo or cfg.bonus_avaliacao_moedas <= 0:
        return 0, False
    if valor_servico_centavos < cfg.min_servico_centavos:
        return 0, False
    inicio_mes, _ = periodo.mes(*periodo.mes_de(agora))
    usa_pendente = cfg.dias_liberacao_bonus > 0
    pendentes: list[PendenteMoeda] = []
    if usa_pendente:
        try:
            pendentes = [
                p for p in repo.pendentes_do_usuario(cliente_id) if p.criada_em >= inicio_mes
            ]
        except Exception:  # noqa: BLE001 - sem a tabela: crédito imediato como antes
            log.warning("moedas_pendentes indisponível: bônus creditado direto", exc_info=True)
            usa_pendente = False
    if profissional_id is not None:
        do_par = repo.bonus_do_par(cliente_id, profissional_id, inicio_mes) + sum(
            1 for p in pendentes if p.parceiro_id == profissional_id
        )
        if do_par >= cfg.max_bonus_por_profissional_mes:
            return 0, False
    ja_no_mes = repo.creditado_no_mes(cliente_id, "bonus_avaliacao", inicio_mes) + sum(
        p.quantidade for p in pendentes
    )
    quantidade = min(cfg.bonus_avaliacao_moedas, max(cfg.teto_mensal_moedas - ja_no_mes, 0))
    return max(quantidade, 0), usa_pendente


def bonus_avaliacao_disponivel(
    repo: RepositorioMoedas,
    *,
    cliente_id: str,
    agora: datetime,
    profissional_id: str | None,
    valor_servico_centavos: int,
) -> int:
    """Moedas que o bônus de avaliação daria agora, SEM creditar (0 = não há bônus)."""
    try:
        return _apurar_bonus_avaliacao(
            repo,
            cliente_id=cliente_id,
            agora=agora,
            profissional_id=profissional_id,
            valor_servico_centavos=valor_servico_centavos,
        )[0]
    except Exception:  # noqa: BLE001 - sem dados confiáveis, o app não promete bônus
        return 0


def conceder_bonus_avaliacao(
    repo: RepositorioMoedas,
    *,
    cliente_id: str,
    pedido_id: str,
    agora: datetime,
    profissional_id: str | None = None,
    valor_servico_centavos: int = 0,
) -> int:
    """Registra o bônus de avaliação do cliente. Devolve as moedas ganhas (0 se nada foi dado).

    O bônus NÃO entra direto no saldo: fica em `moedas_pendentes` por `dias_liberacao_bonus` e só
    vira lançamento se o pedido seguir sem disputa (`liberar_bonus_pendentes`). Sem a tabela (ou
    com `dias_liberacao_bonus = 0`), cai no crédito imediato de antes.

    Idempotente por pedido e respeita o teto mensal (o que está pendente conta). Nunca levanta
    erro para o chamador: falha de gamificação não pode atrapalhar a avaliação.
    """
    quantidade, usa_pendente = _apurar_bonus_avaliacao(
        repo,
        cliente_id=cliente_id,
        agora=agora,
        profissional_id=profissional_id,
        valor_servico_centavos=valor_servico_centavos,
    )
    if quantidade <= 0:
        return 0
    cfg = repo.config()
    chave = f"avaliacao:{pedido_id}"
    if usa_pendente:
        try:
            gravou = repo.criar_pendente(
                PendenteMoeda(
                    usuario_id=cliente_id,
                    pedido_id=pedido_id,
                    quantidade=quantidade,
                    liberar_em=agora + timedelta(days=cfg.dias_liberacao_bonus),
                    chave_idempotencia=chave,
                    criada_em=agora,
                    parceiro_id=profissional_id,
                )
            )
        except Exception:  # noqa: BLE001 - sem a tabela: crédito imediato como antes
            log.warning("moedas_pendentes indisponível: bônus creditado direto", exc_info=True)
        else:
            # Já creditado antes desta mudança (mesma chave): não pendura de novo.
            return quantidade if gravou and not repo.existe(chave) else 0
    expira = vencimento_de_credito_novo(cfg, agora)
    gravou = repo.lancar(
        LancamentoMoeda(
            usuario_id=cliente_id,
            tipo="bonus_avaliacao",
            quantidade=quantidade,
            chave_idempotencia=chave,
            criada_em=agora,
            referencia_id=pedido_id,
            parceiro_id=profissional_id,
            expira_em=expira,
        )
    )
    return quantidade if gravou else 0


def saldo_profissional(repo: RepositorioMoedas, usuario_id: str, agora: datetime) -> int:
    """Tratinhos da carteira do profissional (nunca viram desconto). Sem a coluna nova: 0."""
    try:
        return int(repo.saldo(usuario_id, agora, CARTEIRA_PROFISSIONAL))
    except Exception:  # noqa: BLE001 - carteira ainda não existe no banco
        return 0


def conceder_bonus_profissional(
    repo: RepositorioMoedas,
    *,
    profissional_id: str,
    cliente_id: str,
    pedido_id: str,
    agora: datetime,
) -> int:
    """Bônus do profissional por avaliar um cliente: pendente de `dias_liberacao_bonus` dias.

    Vale 1 vez por par (profissional, cliente), para sempre: a chave é determinística
    (`avaliacao-prof:<profissional>:<cliente>`), então o 2º contrato do mesmo cliente, ou duas
    chamadas ao mesmo tempo, não criam outro. NÃO consome o orçamento de desconto da empresa
    (moeda de profissional não vira dinheiro). Devolve as moedas dadas (0 se já houve, se a
    gamificação está desligada ou se faltam as colunas novas no banco: fail-closed, nunca credita
    direto). Nunca levanta erro: falha aqui não pode atrapalhar a avaliação.
    """
    try:
        cfg = repo.config()
        quantidade = cfg.bonus_avaliacao_profissional_moedas
        if not cfg.ativo or quantidade <= 0:
            return 0
        chave = f"avaliacao-prof:{profissional_id}:{cliente_id}"
        if repo.existe(chave):  # já liberado antes
            return 0
        gravou = repo.criar_pendente(
            PendenteMoeda(
                usuario_id=profissional_id,
                pedido_id=pedido_id,
                quantidade=quantidade,
                liberar_em=agora + timedelta(days=cfg.dias_liberacao_bonus),
                chave_idempotencia=chave,
                criada_em=agora,
                parceiro_id=cliente_id,
                tipo_lancamento=TIPO_BONUS_PROFISSIONAL,
            )
        )
    except Exception:  # noqa: BLE001 - sem as colunas novas (ou banco fora): não credita
        log.warning("bônus do profissional indisponível: não creditado", exc_info=True)
        return 0
    return quantidade if gravou else 0


@dataclass(frozen=True)
class ResultadoLiberacao:
    liberados: int = 0
    cancelados: int = 0
    aguardando: int = 0  # vencidos, mas com disputa ainda sem decisão: ficam para o próximo ciclo


def liberar_bonus_pendentes(
    repo: RepositorioMoedas,
    *,
    agora: datetime,
    situacao_disputa: Callable[[PendenteMoeda], str],
) -> ResultadoLiberacao:
    """Rotina: libera (ou cancela) os bônus cujo prazo venceu.

    `situacao_disputa` diz como está o pedido do bônus: `nenhuma`, `aberta` ou `perdida` (a
    disputa foi decidida contra quem avaliou). A decisão é da regra pura em `rotinas/regras.py`.
    A liberação cria o lançamento imutável com a MESMA chave de hoje (`avaliacao:<pedido>`):
    rodar de novo nunca credita duas vezes.
    """
    from trato.rotinas.regras import DecisaoBonus, decidir_liberacao_bonus

    cfg = repo.config()
    liberados = cancelados = aguardando = 0
    for pend in repo.pendentes_vencidos(agora):
        decisao = decidir_liberacao_bonus(agora, pend.liberar_em, situacao_disputa(pend))
        if decisao is DecisaoBonus.AGUARDAR:
            aguardando += 1
        elif decisao is DecisaoBonus.CANCELAR:
            cancelados += int(repo.marcar_pendente(pend.chave_idempotencia, "cancelado"))
        else:
            expira = vencimento_de_credito_novo(cfg, agora)
            do_profissional = pend.tipo_lancamento == TIPO_BONUS_PROFISSIONAL
            repo.lancar(  # idempotente pela chave: se o ciclo caiu no meio, só falta marcar
                LancamentoMoeda(
                    usuario_id=pend.usuario_id,
                    tipo=TIPO_BONUS_PROFISSIONAL if do_profissional else TIPO_BONUS_CLIENTE,
                    carteira=CARTEIRA_PROFISSIONAL if do_profissional else CARTEIRA_CLIENTE,
                    quantidade=pend.quantidade,
                    chave_idempotencia=pend.chave_idempotencia,
                    criada_em=agora,
                    referencia_id=pend.pedido_id,
                    parceiro_id=pend.parceiro_id,
                    expira_em=expira,
                )
            )
            liberados += int(repo.marcar_pendente(pend.chave_idempotencia, "liberado"))
    return ResultadoLiberacao(liberados, cancelados, aguardando)


def resumo_pendentes(
    repo: RepositorioMoedas, usuario_id: str, tipo: str = TIPO_BONUS_CLIENTE
) -> tuple[int, date | None]:
    """(soma dos bônus pendentes do tipo, data da próxima liberação em Brasília).

    Sem tabela/coluna: (0, None)."""
    try:
        itens = repo.pendentes_do_usuario(usuario_id, tipo)
    except Exception:  # noqa: BLE001 - tabela ainda não existe: não há pendente
        return 0, None
    if not itens:
        return 0, None
    return sum(p.quantidade for p in itens), dia_ref(min(p.liberar_em for p in itens))


def volta_em(motivo: str | None, agora: datetime) -> date | None:
    """Quando o desconto volta: `limite_diario` amanhã; mês esgotado ou teto do cliente, dia 1º do
    próximo mês (datas em Brasília). Disponível (sem motivo): `None`."""
    if motivo is None:
        return None
    hoje = dia_ref(agora)
    if motivo == MOTIVO_LIMITE_DIARIO:
        return hoje + timedelta(days=1)
    if motivo in (MOTIVO_ORCAMENTO_ESGOTADO, MOTIVO_TETO_CLIENTE):
        return date(hoje.year + (hoje.month == 12), hoje.month % 12 + 1, 1)
    return None  # saldo_insuficiente / reservas_abertas: voltam quando a reserva paga ou expira


@dataclass(frozen=True)
class Disponibilidade:
    """Se o desconto de moedas pode ser dado agora (orçamento do mês e teto do cliente)."""

    disponivel: bool
    motivo: str | None
    restante_centavos: int  # o menor entre o que sobra do mês, do dia e do teto do cliente
    volta_em: date | None = None  # quando o desconto volta (None se já está disponível)
    moedas_reservadas: int = 0  # moedas presas em cobranças pendentes (fora do saldo livre)


@dataclass(frozen=True)
class UsoMoedas:
    moedas: int
    desconto_centavos: int
    disponivel: bool = True
    motivo: str | None = None
    volta_em: date | None = None


def disponibilidade_desconto(
    repo: RepositorioMoedas,
    *,
    usuario_id: str,
    agora: datetime,
    ignorar: Collection[str] = (),
) -> Disponibilidade:
    """Orçamento do mês, limite do dia, teto do cliente e reservas abertas NÃO são erro: o desconto
    só não se aplica.

    `ignorar`: chaves de reserva (`chave_reserva`) que não contam, as das cobranças pendentes do
    MESMO pedido (serão reaproveitadas ou trocadas), para a simulação não se bloquear sozinha.

    Recurso desligado: indisponível sem motivo. Ordem do motivo: orçamento do mês, limite do dia,
    teto do cliente, reservas abertas. Se o armazenamento falhar (tabela ainda não existe, banco
    fora), a empresa não paga desconto: indisponível como `orcamento_esgotado` (fail-closed).
    """
    cfg = repo.config()
    if not cfg.ativo:
        return Disponibilidade(False, None, 0)
    try:
        sobra_mes = cfg.orcamento_mensal_desconto_centavos - repo.orcamento_usado(mes_ref(agora))
        sobra_dia = cfg.teto_diario_desconto_centavos - repo.orcamento_usado_dia(dia_ref(agora))
        ano, mes = periodo.mes_de(agora)
        inicio, fim = periodo.mes(ano, mes)
        usado_cliente = repo.uso_liquido_no_mes(usuario_id, inicio, fim) * cfg.valor_moeda_centavos
        abertas = [
            r for r in repo.reservas_abertas_do_usuario(usuario_id) if r.cobranca_id not in ignorar
        ]
    except Exception:  # noqa: BLE001 - sem orçamento confiável, não se dá desconto
        log.warning("orçamento de moedas indisponível: sem desconto", exc_info=True)
        return Disponibilidade(
            False, MOTIVO_ORCAMENTO_ESGOTADO, 0, volta_em(MOTIVO_ORCAMENTO_ESGOTADO, agora)
        )
    if sobra_mes <= 0:
        return Disponibilidade(
            False, MOTIVO_ORCAMENTO_ESGOTADO, 0, volta_em(MOTIVO_ORCAMENTO_ESGOTADO, agora)
        )
    if sobra_dia <= 0:
        return Disponibilidade(
            False, MOTIVO_LIMITE_DIARIO, 0, volta_em(MOTIVO_LIMITE_DIARIO, agora)
        )
    usado_cliente += sum(
        r.desconto_centavos for r in abertas if r.mes_ref == mes_ref(agora)
    )  # reservado também conta no teto
    sobra_cliente = cfg.teto_desconto_cliente_mes_centavos - usado_cliente
    if sobra_cliente <= 0:
        return Disponibilidade(False, MOTIVO_TETO_CLIENTE, 0, volta_em(MOTIVO_TETO_CLIENTE, agora))
    if len(abertas) >= cfg.max_reservas_abertas:
        return Disponibilidade(False, MOTIVO_RESERVAS_ABERTAS, 0)
    return Disponibilidade(
        True,
        None,
        min(sobra_mes, sobra_dia, sobra_cliente),
        moedas_reservadas=sum(r.moedas for r in abertas),
    )


def calcular_uso_moedas(
    repo: RepositorioMoedas,
    *,
    usuario_id: str,
    servico_centavos: int,
    agora: datetime,
    ignorar: Collection[str] = (),
) -> UsoMoedas:
    """Quantas moedas o cliente pode usar neste serviço e o desconto que isso dá (sem reservar).

    Usa o que for MENOR entre o saldo livre (saldo menos o preso em cobranças pendentes), o teto por
    serviço (percentual do valor, em tabela) e o que sobra do orçamento do mês, do dia e do teto do
    cliente. O desconto nunca zera o serviço (sobra pelo menos R$ 1,00). Sem moedas ou recurso
    desligado: `UsoMoedas(0, 0)`. Sem orçamento, no teto, sem saldo livre ou com reservas demais:
    `UsoMoedas(0, 0, False, motivo)` (as moedas continuam guardadas).
    """
    nada = UsoMoedas(0, 0)
    cfg = repo.config()
    if not cfg.ativo or cfg.valor_moeda_centavos <= 0:
        return UsoMoedas(0, 0, False if not cfg.ativo else True)
    disp = disponibilidade_desconto(repo, usuario_id=usuario_id, agora=agora, ignorar=ignorar)
    if not disp.disponivel:
        return UsoMoedas(0, 0, False, disp.motivo, disp.volta_em)
    if servico_centavos <= 100:
        return nada
    saldo_total = repo.saldo(usuario_id, agora)
    if saldo_total <= 0:
        return nada
    saldo = saldo_total - disp.moedas_reservadas
    if saldo <= 0:
        return UsoMoedas(0, 0, False, MOTIVO_SALDO_INSUFICIENTE)
    teto_centavos = min(
        servico_centavos * cfg.max_desconto_percentual // 100,
        servico_centavos - 100,
        disp.restante_centavos,
    )
    por_servico = teto_centavos // cfg.valor_moeda_centavos
    moedas = min(saldo, por_servico)
    if moedas <= 0:
        return nada
    return UsoMoedas(moedas, moedas * cfg.valor_moeda_centavos)


class DescontoMoedasIndisponivel(Exception):
    """A reserva no orçamento falhou (corrida entre pagamentos): o desconto não se aplica."""

    def __init__(self, motivo: str = MOTIVO_ORCAMENTO_ESGOTADO) -> None:
        super().__init__(motivo)
        self.motivo = motivo


def reservar_desconto(
    repo: RepositorioMoedas,
    *,
    cobranca_id: str,
    moedas: int,
    usuario_id: str,
    agora: datetime,
) -> int:
    """Reserva, ATOMICAMENTE e com a cobrança como chave, o desconto de `moedas`: orçamento do mês
    e do dia, teto do cliente e saldo livre numa transação só. Nunca estoura nem gasta em dobro.

    Devolve os centavos reservados (moedas × valor da moeda de agora, gravado na reserva). Qualquer
    negativa, ou falha do armazenamento (tabela nova ausente, banco fora), levanta
    `DescontoMoedasIndisponivel` e nada fica reservado: o desconto só não se aplica.
    """
    if moedas <= 0:
        return 0
    cfg = repo.config()
    desconto = moedas * cfg.valor_moeda_centavos
    try:
        resultado = repo.reservar_desconto(
            chave_reserva(cobranca_id),
            usuario_id,
            mes_ref(agora),
            dia_ref(agora),
            moedas,
            desconto,
            cfg.orcamento_mensal_desconto_centavos,
            cfg.teto_diario_desconto_centavos,
            cfg.teto_desconto_cliente_mes_centavos,
            cfg.max_reservas_abertas,
            agora + timedelta(minutes=cfg.reserva_minutos + MARGEM_RESERVA_MINUTOS),
        )
    except Exception:  # noqa: BLE001 - fail-closed: sem como reservar, não se dá desconto
        log.warning("reserva de moedas falhou: sem desconto", exc_info=True)
        raise DescontoMoedasIndisponivel(MOTIVO_ORCAMENTO_ESGOTADO) from None
    if resultado not in ("ok", "ja_reservada"):
        raise DescontoMoedasIndisponivel(resultado)
    return desconto


def confirmar_reserva_desconto(repo: RepositorioMoedas, *, cobranca_id: str) -> bool:
    """Pagamento confirmado: a reserva vira definitiva. Nunca levanta (o débito segue)."""
    try:
        return bool(repo.confirmar_reserva(chave_reserva(cobranca_id)))
    except Exception:  # noqa: BLE001 - o cliente já pagou com desconto: o débito não pode parar
        log.warning("confirmar reserva de moedas falhou", exc_info=True)
        return False


def devolver_reserva_desconto(repo: RepositorioMoedas, *, cobranca_id: str) -> int:
    """Devolve a reserva da cobrança (mês, dia e saldo) pelo valor GRAVADO nela, uma vez só.

    Estorno total, falha, cancelamento e troca de cobrança passam por aqui. Idempotente: a segunda
    chamada devolve 0 e não mexe em nada. Se o armazenamento falhar, registra e devolve 0.
    """
    try:
        return int(repo.devolver_reserva(chave_reserva(cobranca_id)))
    except Exception:  # noqa: BLE001 - a rotina de expiração recolhe o que sobrar
        log.warning("devolver reserva de moedas falhou", exc_info=True)
        return 0


def situacao_reserva(repo: RepositorioMoedas, *, cobranca_id: str) -> str | None:
    """'reservada' | 'confirmada' | 'devolvida', None (sem reserva) ou 'indisponivel' (falha)."""
    try:
        return repo.reserva_status(chave_reserva(cobranca_id))
    except Exception:  # noqa: BLE001 - não dá para saber: quem chama trata como incerto
        log.warning("situação da reserva de moedas indisponível", exc_info=True)
        return "indisponivel"


def reabrir_reserva_desconto(
    repo: RepositorioMoedas, *, cobranca_id: str, moedas: int, usuario_id: str, agora: datetime
) -> bool:
    """Tenta reservar de novo uma cobrança SEM reserva (webhook tardio). True só se couber (`ok`).

    Se já existe uma linha (ex.: 'devolvida'), a função do banco responde `ja_reservada` e a reserva
    não reabre: a cobrança fica sem desconto válido. Nunca levanta.
    """
    cfg = repo.config()
    try:
        resultado = repo.reservar_desconto(
            chave_reserva(cobranca_id),
            usuario_id,
            mes_ref(agora),
            dia_ref(agora),
            moedas,
            moedas * cfg.valor_moeda_centavos,
            cfg.orcamento_mensal_desconto_centavos,
            cfg.teto_diario_desconto_centavos,
            cfg.teto_desconto_cliente_mes_centavos,
            cfg.max_reservas_abertas,
            agora + timedelta(minutes=cfg.reserva_minutos + MARGEM_RESERVA_MINUTOS),
        )
    except Exception:  # noqa: BLE001 - sem como reservar: não reabre
        log.warning("reabrir reserva de moedas falhou", exc_info=True)
        return False
    return resultado == "ok"


def expirar_reservas_moedas(
    repo: RepositorioMoedas, cobrancas: Any, agora: datetime, provedor: Any = None
) -> int:
    """Rotina de expiração, em 2 passos, idempotente a cada ciclo.

    1) `moedas_expirar_reservas` devolve (mês, dia, saldo) das reservas vencidas, de uma vez.
    2) Toda cobrança AGUARDANDO com moedas cuja reserva esteja 'devolvida' é cancelada, tenha vindo
       ou não na lista do passo 1 (se o processo caiu no meio, o ciclo seguinte acaba o serviço).

    Cada cobrança cancelada também é cancelada no provedor (`cancelar_cobranca`; melhor esforço: o
    Pix já vence sozinho junto com a reserva). Devolve quantas cobranças foram canceladas. Sem a
    tabela/banco: 0, sem erro.
    """
    from trato.pagamentos.modelos import EstadoCobranca

    try:
        repo.expirar_reservas(agora)  # passo 1 (a lista não importa: o passo 2 olha o estado)
    except Exception:  # noqa: BLE001 - tabela ainda não existe ou banco fora: tenta no próximo ciclo
        log.warning("expirar reservas de moedas falhou", exc_info=True)
        return 0
    canceladas = 0
    for c in cobrancas.aguardando_desde_antes(agora):
        if c.moedas_usadas <= 0:
            continue
        if situacao_reserva(repo, cobranca_id=c.id) != "devolvida":
            continue
        if provedor is not None:
            try:
                provedor.cancelar_cobranca(c.id)
            except Exception:  # noqa: BLE001 - o Pix vence sozinho; o cancelamento local segue
                log.warning("cancelar cobrança %s no provedor falhou", c.id, exc_info=True)
        cobrancas.salvar(replace(c, status=EstadoCobranca.CANCELADA))
        canceladas += 1
    return canceladas


def debitar_uso_moedas(
    repo: RepositorioMoedas,
    *,
    usuario_id: str,
    cobranca_id: str,
    pedido_id: str,
    moedas: int,
    agora: datetime,
) -> bool:
    """Debita as moedas de uma cobrança paga. Idempotente por cobrança (`uso:<cobrança>`)."""
    if moedas <= 0:
        return False
    return repo.lancar(
        LancamentoMoeda(
            usuario_id=usuario_id,
            tipo="uso",
            quantidade=-moedas,
            chave_idempotencia=f"uso:{cobranca_id}",
            criada_em=agora,
            referencia_id=pedido_id,
        )
    )


def devolver_uso_moedas(
    repo: RepositorioMoedas,
    *,
    usuario_id: str,
    cobranca_id: str,
    pedido_id: str,
    moedas: int,
    agora: datetime,
    devolvido_centavos: int | None = None,
    base_centavos: int | None = None,
) -> bool:
    """Devolve as moedas de uma cobrança estornada (Termos 13.8 e I.9).

    Sem `devolvido_centavos`/`base_centavos`, devolve tudo. Com eles, a proporção do total já
    devolvido ao cliente (arredondada para baixo; tudo quando chega à base). Cada parte volta com a
    validade do crédito de onde saiu; se ele já venceu, vira crédito novo de 30 dias. Idempotente:
    só lança a diferença entre o que é devido e o que já voltou, uma operação por vez por cobrança.

    Só devolve se o débito (`uso:<cobrança>`) existiu: sem débito não há o que devolver.
    """
    if moedas <= 0:
        return False
    devidas = moedas
    if devolvido_centavos is not None and base_centavos is not None and base_centavos > 0:
        devidas = moedas * max(0, min(devolvido_centavos, base_centavos)) // base_centavos
    if devidas <= 0:
        return False
    uso, antiga = f"uso:{cobranca_id}", f"estorno-uso:{cobranca_id}"
    with repo.trava(antiga):
        if not repo.existe(uso):
            return False
        lancamentos = repo.lancamentos_da_carteira(usuario_id, CARTEIRA_CLIENTE)
        ja = sum(
            i.quantidade
            for i in lancamentos
            if i.chave_idempotencia == antiga or i.chave_idempotencia.startswith(f"{antiga}:")
        )
        falta = devidas - ja
        if falta <= 0:
            return False
        vencidas_ate = agora + timedelta(days=VALIDADE_DEVOLUCAO_VENCIDA_DIAS)
        partes: dict[datetime | None, int] = {}
        pular = ja  # o que já voltou saiu das primeiras parcelas do gasto
        resta = falta
        for parcela in parcelas_do_gasto(lancamentos, uso):
            salto = min(pular, parcela.quantidade)
            pular -= salto
            tirar = min(parcela.quantidade - salto, resta)
            if not tirar:
                continue
            valida = parcela.expira_em is None or parcela.expira_em > agora
            validade = parcela.expira_em if valida else vencidas_ate
            partes[validade] = partes.get(validade, 0) + tirar
            resta -= tirar
        if resta:  # gasto sem crédito de origem (dado antigo): trata como vencido
            partes[vencidas_ate] = partes.get(vencidas_ate, 0) + resta
        gravou = False
        for n, (validade, quantidade) in enumerate(partes.items()):
            gravou |= repo.lancar(
                LancamentoMoeda(
                    usuario_id=usuario_id,
                    tipo="estorno",
                    quantidade=quantidade,
                    chave_idempotencia=f"{antiga}:{devidas}:{n}",
                    criada_em=agora,
                    referencia_id=pedido_id,
                    expira_em=validade,
                )
            )
        return gravou


def saldo_total_disponivel(repo: RepositorioMoedas | None, usuario_id: str, agora: datetime) -> int:
    """Soma dos Tratinhos disponíveis (carteiras cliente e profissional) que o usuário tem agora.

    Degrada para 0 se o repositório/tabela ainda não estiver disponível no ambiente.
    """
    if repo is None:
        return 0
    try:
        cliente = max(0, int(repo.saldo(usuario_id, agora, CARTEIRA_CLIENTE)))
    except Exception:  # noqa: BLE001 - tabela/serviço indisponível em ambiente mínimo
        log.warning("Leitura de saldo de Tratinhos (cliente) indisponível; tratando como 0.")
        cliente = 0
    profissional = max(0, saldo_profissional(repo, usuario_id, agora))
    return cliente + profissional


VALIDADE_MINIMA_RESTAURACAO_DIAS = 30  # igual à devolução da 13.8; o banco exige


def restaurar_tratinhos(
    repo: RepositorioMoedas | None,
    medida_id: str,
    usuario_id: str,
    inicio: datetime,
    agora: datetime,
) -> int:
    """Termos 13.10 e I.11: conta restabelecida recebe, por carteira, o que venceu desde o
    encerramento. Chave única por medida e carteira: repetir não credita de novo. Banco sem a
    migration: nada acontece."""
    if repo is None or not repo.restauracao_disponivel():
        return 0
    dias = max(VALIDADE_MINIMA_RESTAURACAO_DIAS, repo.config().validade_dias or 0)
    total = 0
    for carteira in (CARTEIRA_CLIENTE, CARTEIRA_PROFISSIONAL):
        chave = f"restauracao:{_com_hifens(medida_id)}:{carteira}"
        with repo.trava(f"restauracao:{usuario_id}:{carteira}"):
            if repo.existe(chave):
                continue
            devida = repo.restauracao_devida(medida_id, usuario_id, carteira, inicio, agora)
            if devida <= 0:
                continue
            if repo.restaurar(
                LancamentoMoeda(
                    usuario_id=usuario_id,
                    tipo="restauracao",
                    quantidade=devida,
                    chave_idempotencia=chave,
                    criada_em=agora,
                    referencia_id=medida_id,
                    expira_em=agora + timedelta(days=dias),
                    carteira=carteira,
                )
            ):
                total += devida
    return total


def _com_hifens(valor: str) -> str:
    """O banco confere a chave contra o uuid no formato com hífens."""
    try:
        return str(uuid.UUID(valor))
    except ValueError:
        return valor


def zerar_tratinhos_encerramento_voluntario(
    repo: RepositorioMoedas | None,
    usuario_id: str,
    pedido_exclusao_id: str,
    agora: datetime,
) -> int:
    """Zera os Tratinhos válidos restantes no encerramento voluntário da conta (Termos 13.10).

    Lança débito `ajuste` no livro imutável de moedas (nunca UPDATE/DELETE). Idempotente por
    `(pedido_exclusao_id, carteira)` e atômico via `repo.trava` para impedir saldo negativo ou
    lançamento duplicado em corrida. Se saldo for 0, não grava lançamento vazio.
    """
    if repo is None:
        return 0
    total_zerado = 0
    for carteira in (CARTEIRA_CLIENTE, CARTEIRA_PROFISSIONAL):
        chave = f"encerramento-voluntario:{pedido_exclusao_id}:{carteira}"
        try:
            with repo.trava(f"encerramento:{usuario_id}:{carteira}"):
                if repo.existe(chave):
                    continue
                disponivel = max(0, int(repo.saldo(usuario_id, agora, carteira)))
                if disponivel <= 0:
                    continue
                gravou = repo.lancar(
                    LancamentoMoeda(
                        usuario_id=usuario_id,
                        tipo="ajuste",
                        quantidade=-disponivel,
                        chave_idempotencia=chave,
                        criada_em=agora,
                        referencia_id=pedido_exclusao_id,
                        carteira=carteira,
                    )
                )
                if gravou:
                    total_zerado += disponivel
        except Exception:  # noqa: BLE001 - tabela/coluna ausente em ambiente mínimo
            log.warning(
                "Não foi possível zerar Tratinhos (%s) no encerramento voluntário; seguindo.",
                carteira,
            )
    return total_zerado
