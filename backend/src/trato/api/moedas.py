"""Moedas do Trato (gamificação, fase 1): bônus por avaliar e consulta de saldo.

Regras ficam aqui, no backend. O app só mostra. Livro separado do ledger de dinheiro:
lançamentos imutáveis, saldo = soma, idempotência por chave (uma avaliação = um bônus).
"""

from __future__ import annotations

import logging
import threading
import uuid
from collections.abc import Callable, Collection
from dataclasses import dataclass, replace
from datetime import date, datetime, timedelta
from typing import Any, Protocol

from trato.financeiro import periodo
from trato.persistencia.comum import como_uuid

MOTIVO_ORCAMENTO_ESGOTADO = "orcamento_esgotado"
MOTIVO_TETO_CLIENTE = "teto_cliente"
MOTIVO_LIMITE_DIARIO = "limite_diario"
MOTIVO_SALDO_INSUFICIENTE = "saldo_insuficiente"
MOTIVO_RESERVAS_ABERTAS = "reservas_abertas"
MARGEM_RESERVA_MINUTOS = 2  # a reserva dura um pouco mais que o Pix (que vence em reserva_minutos)
_NS_RESERVA = uuid.UUID("6f1c2a52-7d0e-4f0b-9a57-3c6c1f4d2a10")

log = logging.getLogger("trato.moedas")


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


class RepositorioMoedas(Protocol):
    def config(self) -> ConfigMoedas: ...

    def salvar_config(self, config: ConfigMoedas) -> None: ...

    def lancar(self, lancamento: LancamentoMoeda) -> bool:
        """Grava o lançamento. False se a chave já existia (nada muda)."""
        ...

    def saldo(self, usuario_id: str, agora: datetime) -> int: ...

    def creditado_no_mes(self, usuario_id: str, tipo: str, desde: datetime) -> int: ...

    def existe(self, chave_idempotencia: str) -> bool: ...

    def bonus_do_par(self, usuario_id: str, parceiro_id: str, desde: datetime) -> int: ...

    def extrato(self, usuario_id: str, limite: int = 50) -> list[LancamentoMoeda]: ...

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

    def pendentes_do_usuario(self, usuario_id: str) -> list[PendenteMoeda]:
        """Só os de status 'pendente'."""
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

    def config(self) -> ConfigMoedas:
        return self._config

    def salvar_config(self, config: ConfigMoedas) -> None:
        self._config = config

    def lancar(self, lancamento: LancamentoMoeda) -> bool:
        if lancamento.chave_idempotencia in self._itens:
            return False
        self._itens[lancamento.chave_idempotencia] = lancamento
        return True

    def saldo(self, usuario_id: str, agora: datetime) -> int:
        return sum(
            i.quantidade
            for i in self._itens.values()
            if i.usuario_id == usuario_id and (i.expira_em is None or i.expira_em > agora)
        )

    def creditado_no_mes(self, usuario_id: str, tipo: str, desde: datetime) -> int:
        return sum(
            i.quantidade
            for i in self._itens.values()
            if i.usuario_id == usuario_id and i.tipo == tipo and i.criada_em >= desde
        )

    def existe(self, chave_idempotencia: str) -> bool:
        return chave_idempotencia in self._itens

    def bonus_do_par(self, usuario_id: str, parceiro_id: str, desde: datetime) -> int:
        return sum(
            1
            for i in self._itens.values()
            if i.usuario_id == usuario_id
            and i.parceiro_id == parceiro_id
            and i.tipo == "bonus_avaliacao"
            and i.criada_em >= desde
        )

    def extrato(self, usuario_id: str, limite: int = 50) -> list[LancamentoMoeda]:
        meus = [i for i in self._itens.values() if i.usuario_id == usuario_id]
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
        if pendente.chave_idempotencia in self._pendentes:
            return False
        self._pendentes[pendente.chave_idempotencia] = pendente
        return True

    def pendentes_do_usuario(self, usuario_id: str) -> list[PendenteMoeda]:
        return [
            p
            for p in self._pendentes.values()
            if p.usuario_id == usuario_id and p.status == "pendente"
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
    _NIVEIS = (_BASE + _ORCAMENTO + _RESERVAS, _BASE + _ORCAMENTO, _BASE)

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
        extras = {c: int(linha[c]) for c in (*self._ORCAMENTO, *self._RESERVAS) if c in linha}
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
        valores = {c: getattr(config, c) for c in (*self._BASE, *self._ORCAMENTO, *self._RESERVAS)}
        for colunas in self._NIVEIS[:2]:
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
        with self._banco.transacao() as con:
            linha = con.execute(
                "insert into public.moedas_lancamentos (usuario_id, tipo, quantidade, "
                "chave_idempotencia, referencia_id, parceiro_id, expira_em, criada_em) "
                "values (%s, %s, %s, %s, %s, %s, %s, %s) "
                "on conflict (chave_idempotencia) do nothing returning id",
                (
                    uid,
                    lancamento.tipo,
                    lancamento.quantidade,
                    lancamento.chave_idempotencia,
                    como_uuid(lancamento.referencia_id),
                    como_uuid(lancamento.parceiro_id),
                    lancamento.expira_em,
                    lancamento.criada_em,
                ),
            ).fetchone()
        return linha is not None

    def saldo(self, usuario_id: str, agora: datetime) -> int:
        uid = como_uuid(usuario_id)
        if uid is None:
            return 0
        with self._banco.transacao() as con:
            l = con.execute(  # noqa: E741
                "select coalesce(sum(quantidade), 0) as total from public.moedas_lancamentos "
                "where usuario_id = %s and (expira_em is null or expira_em > %s)",
                (uid, agora),
            ).fetchone()
        return int(l["total"])

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

    def extrato(self, usuario_id: str, limite: int = 50) -> list[LancamentoMoeda]:
        uid = como_uuid(usuario_id)
        if uid is None:
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
        with self._banco.transacao() as con:
            l = con.execute(  # noqa: E741
                "insert into public.moedas_pendentes (usuario_id, pedido_id, quantidade, "
                "liberar_em, status, chave_idempotencia, parceiro_id, criada_em) "
                "values (%s, %s, %s, %s, 'pendente', %s, %s, %s) "
                "on conflict (chave_idempotencia) do nothing returning id",
                (
                    uid,
                    como_uuid(pendente.pedido_id),
                    pendente.quantidade,
                    pendente.liberar_em,
                    pendente.chave_idempotencia,
                    como_uuid(pendente.parceiro_id),
                    pendente.criada_em,
                ),
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
        )

    def pendentes_do_usuario(self, usuario_id: str) -> list[PendenteMoeda]:
        uid = como_uuid(usuario_id)
        if uid is None:
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
    cfg = repo.config()
    if not cfg.ativo or cfg.bonus_avaliacao_moedas <= 0:
        return 0
    if valor_servico_centavos < cfg.min_servico_centavos:
        return 0
    inicio_mes = agora.replace(day=1, hour=0, minute=0, second=0, microsecond=0)
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
            return 0
    ja_no_mes = repo.creditado_no_mes(cliente_id, "bonus_avaliacao", inicio_mes) + sum(
        p.quantidade for p in pendentes
    )
    quantidade = min(cfg.bonus_avaliacao_moedas, max(cfg.teto_mensal_moedas - ja_no_mes, 0))
    if quantidade <= 0:
        return 0
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
    expira = agora + timedelta(days=cfg.validade_dias) if cfg.validade_dias else None
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
            expira = agora + timedelta(days=cfg.validade_dias) if cfg.validade_dias else None
            repo.lancar(  # idempotente pela chave: se o ciclo caiu no meio, só falta marcar
                LancamentoMoeda(
                    usuario_id=pend.usuario_id,
                    tipo="bonus_avaliacao",
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


def resumo_pendentes(repo: RepositorioMoedas, usuario_id: str) -> tuple[int, date | None]:
    """(soma dos bônus pendentes, data da próxima liberação em Brasília). Sem tabela: (0, None)."""
    try:
        itens = repo.pendentes_do_usuario(usuario_id)
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
    usado_cliente += sum(r.desconto_centavos for r in abertas)  # reservado também conta no teto
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
) -> bool:
    """Devolve as moedas de uma cobrança estornada por inteiro. Idempotente por cobrança.

    Só devolve se o débito (`uso:<cobrança>`) existiu: sem débito não há o que devolver.
    """
    if moedas <= 0 or not repo.existe(f"uso:{cobranca_id}"):
        return False
    return repo.lancar(
        LancamentoMoeda(
            usuario_id=usuario_id,
            tipo="estorno",
            quantidade=moedas,
            chave_idempotencia=f"estorno-uso:{cobranca_id}",
            criada_em=agora,
            referencia_id=pedido_id,
        )
    )
