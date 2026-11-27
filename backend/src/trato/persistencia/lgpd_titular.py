"""Pedidos de titular LGPD e revisão de decisão automatizada (Termos 14.9 e 14.10).

Tabela: `public.lgpd_pedidos_titular` (migration 20261125225700_lgpd_pedidos_titular.sql).
Sem a tabela no banco, `disponivel()` devolve False e as rotas respondem 503 limpo.
"""

# ruff: noqa: S608 - só trechos fixos de SQL são concatenados; valores vão por parâmetro

from __future__ import annotations

import threading
import uuid
from dataclasses import dataclass, replace
from datetime import UTC, datetime, timedelta
from typing import Any, Protocol

from trato.financeiro.periodo import BRASILIA
from trato.persistencia.comum import como_uuid, exigir_uuid
from trato.persistencia.conexao import Banco
from trato.persistencia.erros import ErroPersistencia

PRAZO_PADRAO_DIAS = 15
STATUS_ABERTOS = ("aberto", "em_analise", "aguardando_titular")
STATUS_FINAIS = ("atendido", "atendido_parcial", "negado")


def calcular_responder_ate(aberto_em: datetime, dias: int = PRAZO_PADRAO_DIAS) -> datetime:
    """Fim do N-ésimo dia (1..15) no fuso de Brasília (UTC-3), respeitando o trigger do banco."""
    d = max(1, min(int(dias), 15))
    dia_br = aberto_em.astimezone(BRASILIA).date() + timedelta(days=d)
    return datetime(dia_br.year, dia_br.month, dia_br.day, 23, 59, 59, tzinfo=BRASILIA).astimezone(
        UTC
    )


@dataclass(frozen=True)
class PedidoTitularLgpd:
    id: str
    protocolo: str
    usuario_id: str | None
    contato: str | None
    tipo: str
    decisao_automatizada: str | None
    referencia_tipo: str | None
    referencia_id: str | None
    descricao: str
    canal: str
    exclusao_id: str | None
    aberto_em: datetime
    responder_ate: datetime
    status: str = "aberto"
    analista_id: str | None = None
    resposta: str | None = None
    motivo_nao_atendido: str | None = None
    criterios_informados: str | None = None
    respondido_em: datetime | None = None


class RepositorioLgpdTitular(Protocol):
    def disponivel(self) -> bool: ...

    def abrir(
        self,
        *,
        usuario_id: str,
        tipo: str,
        decisao_automatizada: str | None,
        referencia_tipo: str | None,
        referencia_id: str | None,
        descricao: str,
        canal: str,
        exclusao_id: str | None,
        aberto_em: datetime,
        responder_ate: datetime,
    ) -> tuple[PedidoTitularLgpd, bool]:
        """(pedido, eh_novo). Repetição idêntica enquanto aberto devolve o existente."""

    def obter(self, pedido_id: str) -> PedidoTitularLgpd | None: ...

    def listar_do_usuario(
        self, usuario_id: str, limite: int, deslocamento: int
    ) -> tuple[list[PedidoTitularLgpd], int]: ...

    def listar_admin(
        self,
        status: str | None,
        tipo: str | None,
        usuario_id: str | None,
        limite: int,
        deslocamento: int,
    ) -> tuple[list[PedidoTitularLgpd], int]: ...

    def iniciar_analise(
        self, pedido_id: str, analista_id: str
    ) -> tuple[PedidoTitularLgpd | None, str]:
        """(pedido, codigo): ok | repetido | ja_respondido | nao_encontrado"""

    def responder(
        self,
        pedido_id: str,
        status_final: str,
        analista_id: str,
        resposta: str,
        agora: datetime,
        motivo_nao_atendido: str | None = None,
        criterios_informados: str | None = None,
    ) -> tuple[PedidoTitularLgpd | None, str]:
        """(pedido, codigo): ok | repetido | ja_respondido | nao_encontrado"""


class LgpdTitularEmMemoria:
    def __init__(self, *, disponivel: bool = True) -> None:
        self._disponivel = disponivel
        self._itens: dict[str, PedidoTitularLgpd] = {}
        self._seq = 0
        self._trava = threading.Lock()

    def disponivel(self) -> bool:
        return self._disponivel

    def abrir(
        self,
        *,
        usuario_id: str,
        tipo: str,
        decisao_automatizada: str | None,
        referencia_tipo: str | None,
        referencia_id: str | None,
        descricao: str,
        canal: str,
        exclusao_id: str | None,
        aberto_em: datetime,
        responder_ate: datetime,
    ) -> tuple[PedidoTitularLgpd, bool]:
        with self._trava:
            existente = next(
                (
                    p
                    for p in self._itens.values()
                    if p.usuario_id == usuario_id
                    and p.tipo == tipo
                    and p.decisao_automatizada == decisao_automatizada
                    and p.referencia_tipo == referencia_tipo
                    and p.referencia_id == referencia_id
                    and p.descricao == descricao
                    and p.status in STATUS_ABERTOS
                ),
                None,
            )
            if existente is not None:
                return existente, False
            self._seq += 1
            novo = PedidoTitularLgpd(
                id=f"lgpd-{self._seq}",
                protocolo=f"LGPD-{aberto_em.year}-{self._seq:06d}",
                usuario_id=usuario_id,
                contato=None,
                tipo=tipo,
                decisao_automatizada=decisao_automatizada,
                referencia_tipo=referencia_tipo,
                referencia_id=referencia_id,
                descricao=descricao,
                canal=canal,
                exclusao_id=exclusao_id,
                aberto_em=aberto_em,
                responder_ate=responder_ate,
            )
            self._itens[novo.id] = novo
            return novo, True

    def obter(self, pedido_id: str) -> PedidoTitularLgpd | None:
        with self._trava:
            return self._itens.get(pedido_id)

    def listar_do_usuario(
        self, usuario_id: str, limite: int, deslocamento: int
    ) -> tuple[list[PedidoTitularLgpd], int]:
        with self._trava:
            itens = sorted(
                (p for p in self._itens.values() if p.usuario_id == usuario_id),
                key=lambda p: (p.aberto_em, p.id),
                reverse=True,
            )
            return itens[deslocamento : deslocamento + limite], len(itens)

    def listar_admin(
        self,
        status: str | None,
        tipo: str | None,
        usuario_id: str | None,
        limite: int,
        deslocamento: int,
    ) -> tuple[list[PedidoTitularLgpd], int]:
        with self._trava:
            itens = [
                p
                for p in self._itens.values()
                if (status is None or p.status == status)
                and (tipo is None or p.tipo == tipo)
                and (usuario_id is None or p.usuario_id == usuario_id)
            ]
            itens.sort(key=lambda p: (p.responder_ate, p.id))
            return itens[deslocamento : deslocamento + limite], len(itens)

    def iniciar_analise(
        self, pedido_id: str, analista_id: str
    ) -> tuple[PedidoTitularLgpd | None, str]:
        with self._trava:
            atual = self._itens.get(pedido_id)
            if atual is None:
                return None, "nao_encontrado"
            if atual.status in STATUS_FINAIS:
                return atual, "ja_respondido"
            if atual.status == "em_analise":
                return atual, "repetido"
            nova = replace(atual, status="em_analise", analista_id=analista_id)
            self._itens[pedido_id] = nova
            return nova, "ok"

    def responder(
        self,
        pedido_id: str,
        status_final: str,
        analista_id: str,
        resposta: str,
        agora: datetime,
        motivo_nao_atendido: str | None = None,
        criterios_informados: str | None = None,
    ) -> tuple[PedidoTitularLgpd | None, str]:
        with self._trava:
            atual = self._itens.get(pedido_id)
            if atual is None:
                return None, "nao_encontrado"
            if atual.status in STATUS_FINAIS:
                if (
                    atual.status == status_final
                    and atual.resposta == resposta
                    and atual.motivo_nao_atendido == motivo_nao_atendido
                    and atual.criterios_informados == criterios_informados
                ):
                    return atual, "repetido"
                return atual, "ja_respondido"
            nova = replace(
                atual,
                status=status_final,
                analista_id=analista_id,
                resposta=resposta,
                motivo_nao_atendido=motivo_nao_atendido,
                criterios_informados=criterios_informados,
                respondido_em=agora,
            )
            self._itens[pedido_id] = nova
            return nova, "ok"


class LgpdTitularPostgres:
    _COLS = (
        "id, protocolo, usuario_id, contato, tipo, decisao_automatizada, referencia_tipo, "
        "referencia_id, descricao, canal, exclusao_id, aberto_em, responder_ate, status, "
        "analista_id, resposta, motivo_nao_atendido, criterios_informados, respondido_em"
    )

    def __init__(self, banco: Banco) -> None:
        self._banco = banco

    @staticmethod
    def _de_linha(l: dict[str, Any]) -> PedidoTitularLgpd:  # noqa: E741
        return PedidoTitularLgpd(
            id=str(l["id"]),
            protocolo=l["protocolo"],
            usuario_id=str(l["usuario_id"]) if l["usuario_id"] else None,
            contato=l["contato"],
            tipo=l["tipo"],
            decisao_automatizada=l["decisao_automatizada"],
            referencia_tipo=l["referencia_tipo"],
            referencia_id=str(l["referencia_id"]) if l["referencia_id"] else None,
            descricao=l["descricao"],
            canal=l["canal"],
            exclusao_id=str(l["exclusao_id"]) if l["exclusao_id"] else None,
            aberto_em=l["aberto_em"],
            responder_ate=l["responder_ate"],
            status=l["status"],
            analista_id=str(l["analista_id"]) if l["analista_id"] else None,
            resposta=l["resposta"],
            motivo_nao_atendido=l["motivo_nao_atendido"],
            criterios_informados=l["criterios_informados"],
            respondido_em=l["respondido_em"],
        )

    def disponivel(self) -> bool:
        try:
            with self._banco.transacao() as con:
                l = con.execute(  # noqa: E741
                    "select to_regclass('public.lgpd_pedidos_titular') as t"
                ).fetchone()
            return bool(l and l["t"])
        except Exception:  # noqa: BLE001
            return False

    def abrir(
        self,
        *,
        usuario_id: str,
        tipo: str,
        decisao_automatizada: str | None,
        referencia_tipo: str | None,
        referencia_id: str | None,
        descricao: str,
        canal: str,
        exclusao_id: str | None,
        aberto_em: datetime,
        responder_ate: datetime,
    ) -> tuple[PedidoTitularLgpd, bool]:
        uid = exigir_uuid(usuario_id, "usuario")
        ref_id = como_uuid(referencia_id) if referencia_id else None
        exc_id = como_uuid(exclusao_id) if exclusao_id else None
        with self._banco.transacao() as con:
            con.execute(
                "select pg_advisory_xact_lock(hashtextextended(%s, 0))",
                (f"lgpd_titular|{uid}|{tipo}",),
            )
            existente = con.execute(
                f"select {self._COLS} from public.lgpd_pedidos_titular "
                "where usuario_id = %s and tipo = %s "
                "and decisao_automatizada is not distinct from %s "
                "and referencia_tipo is not distinct from %s "
                "and referencia_id is not distinct from %s "
                "and descricao = %s "
                "and status in ('aberto', 'em_analise', 'aguardando_titular') limit 1",
                (uid, tipo, decisao_automatizada, referencia_tipo, ref_id, descricao),
            ).fetchone()
            if existente is not None:
                return self._de_linha(existente), False
            nova = con.execute(
                "insert into public.lgpd_pedidos_titular "
                "(id, usuario_id, tipo, decisao_automatizada, referencia_tipo, referencia_id, "
                "descricao, canal, exclusao_id, aberto_em, responder_ate) "
                f"values (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s) returning {self._COLS}",
                (
                    uuid.uuid4(),
                    uid,
                    tipo,
                    decisao_automatizada,
                    referencia_tipo,
                    ref_id,
                    descricao,
                    canal,
                    exc_id,
                    aberto_em,
                    responder_ate,
                ),
            ).fetchone()
        return self._de_linha(nova), True

    def obter(self, pedido_id: str) -> PedidoTitularLgpd | None:
        pid = como_uuid(pedido_id)
        if pid is None:
            return None
        with self._banco.transacao() as con:
            l = con.execute(  # noqa: E741
                f"select {self._COLS} from public.lgpd_pedidos_titular where id = %s",
                (pid,),
            ).fetchone()
        return self._de_linha(l) if l else None

    def listar_do_usuario(
        self, usuario_id: str, limite: int, deslocamento: int
    ) -> tuple[list[PedidoTitularLgpd], int]:
        uid = como_uuid(usuario_id)
        if uid is None:
            return [], 0
        with self._banco.transacao() as con:
            tot = con.execute(
                "select count(*) as n from public.lgpd_pedidos_titular where usuario_id = %s",
                (uid,),
            ).fetchone()
            linhas = con.execute(
                f"select {self._COLS} from public.lgpd_pedidos_titular "
                "where usuario_id = %s order by aberto_em desc, id desc limit %s offset %s",
                (uid, limite, deslocamento),
            ).fetchall()
        return [self._de_linha(l) for l in linhas], int(tot["n"]) if tot else 0  # noqa: E741

    def listar_admin(
        self,
        status: str | None,
        tipo: str | None,
        usuario_id: str | None,
        limite: int,
        deslocamento: int,
    ) -> tuple[list[PedidoTitularLgpd], int]:
        filtros: list[str] = []
        params: list[Any] = []
        if status is not None:
            filtros.append("status = %s")
            params.append(status)
        if tipo is not None:
            filtros.append("tipo = %s")
            params.append(tipo)
        if usuario_id is not None:
            uid = como_uuid(usuario_id)
            if uid is None:
                return [], 0
            filtros.append("usuario_id = %s")
            params.append(uid)
        where = f"where {' and '.join(filtros)}" if filtros else ""
        with self._banco.transacao() as con:
            tot = con.execute(
                f"select count(*) as n from public.lgpd_pedidos_titular {where}",
                tuple(params),
            ).fetchone()
            linhas = con.execute(
                f"select {self._COLS} from public.lgpd_pedidos_titular {where} "
                "order by responder_ate asc, id asc limit %s offset %s",
                (*params, limite, deslocamento),
            ).fetchall()
        return [self._de_linha(l) for l in linhas], int(tot["n"]) if tot else 0  # noqa: E741

    def iniciar_analise(
        self, pedido_id: str, analista_id: str
    ) -> tuple[PedidoTitularLgpd | None, str]:
        pid = como_uuid(pedido_id)
        if pid is None:
            return None, "nao_encontrado"
        op_id = exigir_uuid(analista_id, "analista")
        with self._banco.transacao() as con:
            atual = con.execute(
                f"select {self._COLS} from public.lgpd_pedidos_titular where id = %s for update",
                (pid,),
            ).fetchone()
            if atual is None:
                return None, "nao_encontrado"
            if atual["status"] in STATUS_FINAIS:
                return self._de_linha(atual), "ja_respondido"
            if atual["status"] == "em_analise":
                return self._de_linha(atual), "repetido"
            nova = con.execute(
                f"update public.lgpd_pedidos_titular set status = 'em_analise', analista_id = %s "
                f"where id = %s returning {self._COLS}",
                (op_id, pid),
            ).fetchone()
        return self._de_linha(nova), "ok"

    def responder(
        self,
        pedido_id: str,
        status_final: str,
        analista_id: str,
        resposta: str,
        agora: datetime,
        motivo_nao_atendido: str | None = None,
        criterios_informados: str | None = None,
    ) -> tuple[PedidoTitularLgpd | None, str]:
        pid = como_uuid(pedido_id)
        if pid is None:
            return None, "nao_encontrado"
        op_id = exigir_uuid(analista_id, "analista")
        try:
            with self._banco.transacao() as con:
                atual = con.execute(
                    f"select {self._COLS} from public.lgpd_pedidos_titular "
                    "where id = %s for update",
                    (pid,),
                ).fetchone()
                if atual is None:
                    return None, "nao_encontrado"
                if atual["status"] in STATUS_FINAIS:
                    if (
                        atual["status"] == status_final
                        and atual["resposta"] == resposta
                        and atual["motivo_nao_atendido"] == motivo_nao_atendido
                        and atual["criterios_informados"] == criterios_informados
                    ):
                        return self._de_linha(atual), "repetido"
                    return self._de_linha(atual), "ja_respondido"
                nova = con.execute(
                    "update public.lgpd_pedidos_titular "
                    "set status = %s, analista_id = %s, resposta = %s, "
                    "motivo_nao_atendido = %s, criterios_informados = %s, respondido_em = %s "
                    f"where id = %s returning {self._COLS}",
                    (
                        status_final,
                        op_id,
                        resposta,
                        motivo_nao_atendido,
                        criterios_informados,
                        agora,
                        pid,
                    ),
                ).fetchone()
            return self._de_linha(nova), "ok"
        except ErroPersistencia:
            return self.obter(pedido_id), "ja_respondido"
