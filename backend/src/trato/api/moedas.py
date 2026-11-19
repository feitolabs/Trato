"""Moedas do Trato (gamificação, fase 1): bônus por avaliar e consulta de saldo.

Regras ficam aqui, no backend. O app só mostra. Livro separado do ledger de dinheiro:
lançamentos imutáveis, saldo = soma, idempotência por chave (uma avaliação = um bônus).
"""

from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime, timedelta
from typing import Any, Protocol

from trato.persistencia.comum import como_uuid


@dataclass(frozen=True)
class ConfigMoedas:
    ativo: bool = False
    bonus_avaliacao_moedas: int = 50
    valor_moeda_centavos: int = 1
    teto_mensal_moedas: int = 500
    min_servico_centavos: int = 5000
    max_bonus_por_profissional_mes: int = 1
    validade_dias: int | None = None


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

    def bonus_do_par(self, usuario_id: str, parceiro_id: str, desde: datetime) -> int: ...

    def extrato(self, usuario_id: str, limite: int = 50) -> list[LancamentoMoeda]: ...


class MoedasEmMemoria:
    def __init__(self, config: ConfigMoedas | None = None) -> None:
        self._config = config or ConfigMoedas()
        self._itens: dict[str, LancamentoMoeda] = {}

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


class MoedasPostgres:
    def __init__(self, banco: Any) -> None:
        self._banco = banco

    def config(self) -> ConfigMoedas:
        with self._banco.transacao() as con:
            l = con.execute(  # noqa: E741
                "select ativo, bonus_avaliacao_moedas, valor_moeda_centavos, "
                "teto_mensal_moedas, min_servico_centavos, max_bonus_por_profissional_mes, "
                "validade_dias from public.moedas_config where id"
            ).fetchone()
        if l is None:
            return ConfigMoedas()
        return ConfigMoedas(
            ativo=bool(l["ativo"]),
            bonus_avaliacao_moedas=int(l["bonus_avaliacao_moedas"]),
            valor_moeda_centavos=int(l["valor_moeda_centavos"]),
            teto_mensal_moedas=int(l["teto_mensal_moedas"]),
            min_servico_centavos=int(l["min_servico_centavos"]),
            max_bonus_por_profissional_mes=int(l["max_bonus_por_profissional_mes"]),
            validade_dias=l["validade_dias"],
        )

    def salvar_config(self, config: ConfigMoedas) -> None:
        with self._banco.transacao() as con:
            con.execute(
                "update public.moedas_config set ativo = %s, bonus_avaliacao_moedas = %s, "
                "valor_moeda_centavos = %s, teto_mensal_moedas = %s, min_servico_centavos = %s, "
                "max_bonus_por_profissional_mes = %s, validade_dias = %s, atualizado_em = now() "
                "where id",
                (
                    config.ativo,
                    config.bonus_avaliacao_moedas,
                    config.valor_moeda_centavos,
                    config.teto_mensal_moedas,
                    config.min_servico_centavos,
                    config.max_bonus_por_profissional_mes,
                    config.validade_dias,
                ),
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


def conceder_bonus_avaliacao(
    repo: RepositorioMoedas,
    *,
    cliente_id: str,
    pedido_id: str,
    agora: datetime,
    profissional_id: str | None = None,
    valor_servico_centavos: int = 0,
) -> int:
    """Credita o bônus de avaliação ao cliente. Devolve as moedas ganhas (0 se nada foi dado).

    Idempotente por pedido e respeita o teto mensal. Nunca levanta erro para o chamador:
    falha de gamificação não pode atrapalhar a avaliação.
    """
    cfg = repo.config()
    if not cfg.ativo or cfg.bonus_avaliacao_moedas <= 0:
        return 0
    if valor_servico_centavos < cfg.min_servico_centavos:
        return 0
    inicio_mes = agora.replace(day=1, hour=0, minute=0, second=0, microsecond=0)
    if profissional_id is not None and (
        repo.bonus_do_par(cliente_id, profissional_id, inicio_mes)
        >= cfg.max_bonus_por_profissional_mes
    ):
        return 0
    ja_no_mes = repo.creditado_no_mes(cliente_id, "bonus_avaliacao", inicio_mes)
    quantidade = min(cfg.bonus_avaliacao_moedas, max(cfg.teto_mensal_moedas - ja_no_mes, 0))
    if quantidade <= 0:
        return 0
    expira = agora + timedelta(days=cfg.validade_dias) if cfg.validade_dias else None
    gravou = repo.lancar(
        LancamentoMoeda(
            usuario_id=cliente_id,
            tipo="bonus_avaliacao",
            quantidade=quantidade,
            chave_idempotencia=f"avaliacao:{pedido_id}",
            criada_em=agora,
            referencia_id=pedido_id,
            parceiro_id=profissional_id,
            expira_em=expira,
        )
    )
    return quantidade if gravou else 0
