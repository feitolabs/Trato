"""Moderação/ocultação de avaliações e pedidos de revisão (Termos 12.6, 12.7 e 20.5).

Tabelas: `public.avaliacao_ocultacoes` e `public.avaliacao_revisoes`
(migration 20261125225600_avaliacoes_moderacao.sql).
Sem as tabelas no banco, `disponivel()` devolve False e as rotas respondem 503 limpo.
"""

# ruff: noqa: S608 - só trechos fixos de SQL são concatenados; valores vão por parâmetro

from __future__ import annotations

import threading
import uuid
from dataclasses import dataclass, replace
from datetime import datetime
from typing import Any, Protocol

from psycopg.types.json import Jsonb

from trato.persistencia.comum import como_uuid, exigir_uuid
from trato.persistencia.conexao import Banco
from trato.persistencia.erros import Duplicado, ErroPersistencia

MOTIVOS_OCULTACAO = (
    "ofensa_ou_ilegal",
    "dados_pessoais",
    "sem_pedido_real_ou_falsa",
    "nao_participou",
    "ordem_judicial",
)
PRAZO_REVISAO_PADRAO_DIAS_UTEIS = 5


@dataclass(frozen=True)
class OcultacaoAvaliacao:
    id: str
    avaliacao_id: str
    motivo: str
    explicacao: str
    analista_id: str
    ocultada_em: datetime
    status_anterior: str = "publicada"
    autor_avisado_em: datetime | None = None
    revertida_em: datetime | None = None
    revertida_por: str | None = None


@dataclass(frozen=True)
class RevisaoAvaliacao:
    id: str
    protocolo: str
    avaliacao_id: str
    tipo: str  # revisao | contestacao_ocultacao
    ocultacao_id: str | None
    solicitante_id: str
    justificativa: str
    anexos: tuple[str, ...]
    canal: str  # app | sac
    aberta_em: datetime
    responder_ate: datetime
    status: str = "aberta"  # aberta | em_analise | aceita | recusada
    analista_id: str | None = None
    resposta: str | None = None
    mesmo_analista_justificativa: str | None = None
    decidida_em: datetime | None = None


class RepositorioModeracaoAvaliacoes(Protocol):
    def disponivel(self) -> bool: ...

    def ocultacao_ativa(self, avaliacao_id: str) -> OcultacaoAvaliacao | None: ...

    def obter_ocultacao(self, ocultacao_id: str) -> OcultacaoAvaliacao | None: ...

    def ocultar(
        self,
        avaliacao_id: str,
        motivo: str,
        explicacao: str,
        analista_id: str,
        agora: datetime,
    ) -> tuple[OcultacaoAvaliacao | None, str]:
        """(ocultacao, status): ok | ja_ocultada | nao_encontrada"""

    def reverter_ocultacao(
        self, avaliacao_id: str, operador_id: str, agora: datetime
    ) -> tuple[OcultacaoAvaliacao | None, str]:
        """(ocultacao, status): ok | sem_ocultacao_ativa | nao_encontrada"""

    def abrir_revisao(
        self,
        *,
        avaliacao_id: str,
        tipo: str,
        ocultacao_id: str | None,
        solicitante_id: str,
        justificativa: str,
        anexos: tuple[str, ...],
        canal: str,
        agora: datetime,
        responder_ate: datetime,
    ) -> tuple[RevisaoAvaliacao | None, bool, str]:
        """(revisao, eh_nova, codigo): ok | ja_aberta"""

    def obter_revisao(self, revisao_id: str) -> RevisaoAvaliacao | None: ...

    def listar_revisoes_do_usuario(
        self, solicitante_id: str, limite: int, deslocamento: int
    ) -> tuple[list[RevisaoAvaliacao], int]: ...

    def listar_revisoes_admin(
        self,
        status: str | None,
        avaliacao_id: str | None,
        limite: int,
        deslocamento: int,
    ) -> tuple[list[RevisaoAvaliacao], int]: ...

    def iniciar_analise(
        self, revisao_id: str, analista_id: str
    ) -> tuple[RevisaoAvaliacao | None, str]:
        """(revisao, codigo): ok | repetido | ja_decidida | nao_encontrada"""

    def decidir_revisao(
        self,
        revisao_id: str,
        status_final: str,
        analista_id: str,
        resposta: str,
        agora: datetime,
        mesmo_analista_justificativa: str | None = None,
    ) -> tuple[RevisaoAvaliacao | None, str]:
        """(revisao, codigo): ok | repetido | ja_decidida | mesmo_analista_sem_justificativa."""


class ModeracaoAvaliacoesEmMemoria:
    def __init__(self, *, disponivel: bool = True) -> None:
        self._disponivel = disponivel
        self._avaliacoes: Any = None
        self._ocultacoes: dict[str, OcultacaoAvaliacao] = {}
        self._revisoes: dict[str, RevisaoAvaliacao] = {}
        self._seq_ocu = 0
        self._seq_rev = 0
        self._trava = threading.Lock()

    def vincular(self, avaliacoes: Any) -> None:
        self._avaliacoes = avaliacoes

    def disponivel(self) -> bool:
        return self._disponivel

    def ocultacao_ativa(self, avaliacao_id: str) -> OcultacaoAvaliacao | None:
        with self._trava:
            return self._ocultacao_ativa_sem_trava(avaliacao_id)

    def _ocultacao_ativa_sem_trava(self, avaliacao_id: str) -> OcultacaoAvaliacao | None:
        return next(
            (
                o
                for o in self._ocultacoes.values()
                if o.avaliacao_id == avaliacao_id and o.revertida_em is None
            ),
            None,
        )

    def obter_ocultacao(self, ocultacao_id: str) -> OcultacaoAvaliacao | None:
        with self._trava:
            return self._ocultacoes.get(ocultacao_id)

    def ocultar(
        self,
        avaliacao_id: str,
        motivo: str,
        explicacao: str,
        analista_id: str,
        agora: datetime,
    ) -> tuple[OcultacaoAvaliacao | None, str]:
        with self._trava:
            av = self._avaliacoes.obter_por_id(avaliacao_id) if self._avaliacoes else None
            if av is None:
                return None, "nao_encontrada"
            ativa = self._ocultacao_ativa_sem_trava(avaliacao_id)
            if ativa is not None:
                return ativa, "ja_ocultada"
            self._seq_ocu += 1
            ocu = OcultacaoAvaliacao(
                id=f"ocu-{self._seq_ocu}",
                avaliacao_id=avaliacao_id,
                motivo=motivo,
                explicacao=explicacao,
                analista_id=analista_id,
                ocultada_em=agora,
                status_anterior=av.status,
            )
            self._ocultacoes[ocu.id] = ocu
            self._avaliacoes.definir_status(avaliacao_id, "descartada")
            return ocu, "ok"

    def reverter_ocultacao(
        self, avaliacao_id: str, operador_id: str, agora: datetime
    ) -> tuple[OcultacaoAvaliacao | None, str]:
        with self._trava:
            av = self._avaliacoes.obter_por_id(avaliacao_id) if self._avaliacoes else None
            if av is None:
                return None, "nao_encontrada"
            ativa = self._ocultacao_ativa_sem_trava(avaliacao_id)
            if ativa is None:
                return None, "sem_ocultacao_ativa"
            revertida = replace(ativa, revertida_em=agora, revertida_por=operador_id)
            self._ocultacoes[ativa.id] = revertida
            self._avaliacoes.definir_status(avaliacao_id, ativa.status_anterior)
            return revertida, "ok"

    def abrir_revisao(
        self,
        *,
        avaliacao_id: str,
        tipo: str,
        ocultacao_id: str | None,
        solicitante_id: str,
        justificativa: str,
        anexos: tuple[str, ...],
        canal: str,
        agora: datetime,
        responder_ate: datetime,
    ) -> tuple[RevisaoAvaliacao | None, bool, str]:
        with self._trava:
            existente = next(
                (
                    r
                    for r in self._revisoes.values()
                    if r.avaliacao_id == avaliacao_id
                    and r.solicitante_id == solicitante_id
                    and r.status in ("aberta", "em_analise")
                ),
                None,
            )
            if existente is not None:
                return existente, False, "ja_aberta"
            self._seq_rev += 1
            rev = RevisaoAvaliacao(
                id=f"rev-{self._seq_rev}",
                protocolo=f"REV-{agora.year}-{self._seq_rev:06d}",
                avaliacao_id=avaliacao_id,
                tipo=tipo,
                ocultacao_id=ocultacao_id,
                solicitante_id=solicitante_id,
                justificativa=justificativa,
                anexos=tuple(anexos),
                canal=canal,
                aberta_em=agora,
                responder_ate=responder_ate,
            )
            self._revisoes[rev.id] = rev
            return rev, True, "ok"

    def obter_revisao(self, revisao_id: str) -> RevisaoAvaliacao | None:
        with self._trava:
            return self._revisoes.get(revisao_id)

    def listar_revisoes_do_usuario(
        self, solicitante_id: str, limite: int, deslocamento: int
    ) -> tuple[list[RevisaoAvaliacao], int]:
        with self._trava:
            itens = sorted(
                (r for r in self._revisoes.values() if r.solicitante_id == solicitante_id),
                key=lambda r: r.aberta_em,
                reverse=True,
            )
            return itens[deslocamento : deslocamento + limite], len(itens)

    def listar_revisoes_admin(
        self,
        status: str | None,
        avaliacao_id: str | None,
        limite: int,
        deslocamento: int,
    ) -> tuple[list[RevisaoAvaliacao], int]:
        with self._trava:
            itens = [
                r
                for r in self._revisoes.values()
                if (status is None or r.status == status)
                and (avaliacao_id is None or r.avaliacao_id == avaliacao_id)
            ]
            itens.sort(key=lambda r: (r.responder_ate, r.id))
            return itens[deslocamento : deslocamento + limite], len(itens)

    def iniciar_analise(
        self, revisao_id: str, analista_id: str
    ) -> tuple[RevisaoAvaliacao | None, str]:
        with self._trava:
            atual = self._revisoes.get(revisao_id)
            if atual is None:
                return None, "nao_encontrada"
            if atual.status in ("aceita", "recusada"):
                return atual, "ja_decidida"
            if atual.status == "em_analise":
                return atual, "repetido"
            nova = replace(atual, status="em_analise", analista_id=analista_id)
            self._revisoes[revisao_id] = nova
            return nova, "ok"

    def decidir_revisao(
        self,
        revisao_id: str,
        status_final: str,
        analista_id: str,
        resposta: str,
        agora: datetime,
        mesmo_analista_justificativa: str | None = None,
    ) -> tuple[RevisaoAvaliacao | None, str]:
        with self._trava:
            atual = self._revisoes.get(revisao_id)
            if atual is None:
                return None, "nao_encontrada"
            if atual.status in ("aceita", "recusada"):
                if atual.status == status_final and atual.resposta == resposta:
                    return atual, "repetido"
                return atual, "ja_decidida"
            if atual.tipo == "contestacao_ocultacao" and atual.ocultacao_id:
                ocu = self._ocultacoes.get(atual.ocultacao_id)
                if (
                    ocu is not None
                    and ocu.analista_id == analista_id
                    and not (mesmo_analista_justificativa or "").strip()
                ):
                    return atual, "mesmo_analista_sem_justificativa"
            nova = replace(
                atual,
                status=status_final,
                analista_id=analista_id,
                resposta=resposta,
                mesmo_analista_justificativa=mesmo_analista_justificativa,
                decidida_em=agora,
            )
            self._revisoes[revisao_id] = nova
            return nova, "ok"


class ModeracaoAvaliacoesPostgres:
    _COLS_OCU = (
        "id, avaliacao_id, motivo, explicacao, analista_id, ocultada_em, "
        "status_anterior, autor_avisado_em, revertida_em, revertida_por"
    )
    _COLS_REV = (
        "id, protocolo, avaliacao_id, tipo, ocultacao_id, solicitante_id, justificativa, "
        "anexos, canal, aberta_em, responder_ate, status, analista_id, resposta, "
        "mesmo_analista_justificativa, decidida_em"
    )

    def __init__(self, banco: Banco) -> None:
        self._banco = banco

    @staticmethod
    def _ocu(l: dict[str, Any]) -> OcultacaoAvaliacao:  # noqa: E741
        return OcultacaoAvaliacao(
            id=str(l["id"]),
            avaliacao_id=str(l["avaliacao_id"]),
            motivo=l["motivo"],
            explicacao=l["explicacao"],
            analista_id=str(l["analista_id"]),
            ocultada_em=l["ocultada_em"],
            status_anterior=l["status_anterior"],
            autor_avisado_em=l["autor_avisado_em"],
            revertida_em=l["revertida_em"],
            revertida_por=str(l["revertida_por"]) if l["revertida_por"] else None,
        )

    @staticmethod
    def _rev(l: dict[str, Any]) -> RevisaoAvaliacao:  # noqa: E741
        bruto = l["anexos"] or []
        anexos = tuple(str(x) for x in bruto) if isinstance(bruto, list) else ()
        return RevisaoAvaliacao(
            id=str(l["id"]),
            protocolo=l["protocolo"],
            avaliacao_id=str(l["avaliacao_id"]),
            tipo=l["tipo"],
            ocultacao_id=str(l["ocultacao_id"]) if l["ocultacao_id"] else None,
            solicitante_id=str(l["solicitante_id"]),
            justificativa=l["justificativa"],
            anexos=anexos,
            canal=l["canal"],
            aberta_em=l["aberta_em"],
            responder_ate=l["responder_ate"],
            status=l["status"],
            analista_id=str(l["analista_id"]) if l["analista_id"] else None,
            resposta=l["resposta"],
            mesmo_analista_justificativa=l["mesmo_analista_justificativa"],
            decidida_em=l["decidida_em"],
        )

    def disponivel(self) -> bool:
        try:
            with self._banco.transacao() as con:
                l = con.execute(  # noqa: E741
                    "select to_regclass('public.avaliacao_ocultacoes') as o, "
                    "to_regclass('public.avaliacao_revisoes') as r"
                ).fetchone()
            return bool(l and l["o"] and l["r"])
        except Exception:  # noqa: BLE001
            return False

    def ocultacao_ativa(self, avaliacao_id: str) -> OcultacaoAvaliacao | None:
        aid = como_uuid(avaliacao_id)
        if aid is None:
            return None
        with self._banco.transacao() as con:
            l = con.execute(  # noqa: E741
                f"select {self._COLS_OCU} from public.avaliacao_ocultacoes "
                "where avaliacao_id = %s and revertida_em is null",
                (aid,),
            ).fetchone()
        return self._ocu(l) if l else None

    def obter_ocultacao(self, ocultacao_id: str) -> OcultacaoAvaliacao | None:
        oid = como_uuid(ocultacao_id)
        if oid is None:
            return None
        with self._banco.transacao() as con:
            l = con.execute(  # noqa: E741
                f"select {self._COLS_OCU} from public.avaliacao_ocultacoes where id = %s",
                (oid,),
            ).fetchone()
        return self._ocu(l) if l else None

    def ocultar(
        self,
        avaliacao_id: str,
        motivo: str,
        explicacao: str,
        analista_id: str,
        agora: datetime,
    ) -> tuple[OcultacaoAvaliacao | None, str]:
        aid = como_uuid(avaliacao_id)
        if aid is None:
            return None, "nao_encontrada"
        op_id = exigir_uuid(analista_id, "analista")
        try:
            with self._banco.transacao() as con:
                av = con.execute(
                    "select status from public.avaliacoes where id = %s for update", (aid,)
                ).fetchone()
                if av is None:
                    return None, "nao_encontrada"
                ativa = con.execute(
                    f"select {self._COLS_OCU} from public.avaliacao_ocultacoes "
                    "where avaliacao_id = %s and revertida_em is null",
                    (aid,),
                ).fetchone()
                if ativa is not None:
                    return self._ocu(ativa), "ja_ocultada"
                nova = con.execute(
                    f"insert into public.avaliacao_ocultacoes "
                    "(avaliacao_id, motivo, explicacao, analista_id, ocultada_em, status_anterior) "
                    f"values (%s, %s, %s, %s, %s, %s) returning {self._COLS_OCU}",
                    (aid, motivo, explicacao, op_id, agora, av["status"]),
                ).fetchone()
            return self._ocu(nova), "ok"
        except Duplicado:
            return self.ocultacao_ativa(avaliacao_id), "ja_ocultada"

    def reverter_ocultacao(
        self, avaliacao_id: str, operador_id: str, agora: datetime
    ) -> tuple[OcultacaoAvaliacao | None, str]:
        aid = como_uuid(avaliacao_id)
        if aid is None:
            return None, "nao_encontrada"
        op_id = exigir_uuid(operador_id, "operador")
        with self._banco.transacao() as con:
            av = con.execute(
                "select id from public.avaliacoes where id = %s for update", (aid,)
            ).fetchone()
            if av is None:
                return None, "nao_encontrada"
            ativa = con.execute(
                f"select {self._COLS_OCU} from public.avaliacao_ocultacoes "
                "where avaliacao_id = %s and revertida_em is null for update",
                (aid,),
            ).fetchone()
            if ativa is None:
                return None, "sem_ocultacao_ativa"
            rev = con.execute(
                f"update public.avaliacao_ocultacoes "
                f"set revertida_em = %s, revertida_por = %s where id = %s "
                f"returning {self._COLS_OCU}",
                (agora, op_id, ativa["id"]),
            ).fetchone()
        return self._ocu(rev), "ok"

    def abrir_revisao(
        self,
        *,
        avaliacao_id: str,
        tipo: str,
        ocultacao_id: str | None,
        solicitante_id: str,
        justificativa: str,
        anexos: tuple[str, ...],
        canal: str,
        agora: datetime,
        responder_ate: datetime,
    ) -> tuple[RevisaoAvaliacao | None, bool, str]:
        aid = exigir_uuid(avaliacao_id, "avaliacao")
        sid = exigir_uuid(solicitante_id, "solicitante")
        oid = como_uuid(ocultacao_id) if ocultacao_id else None
        try:
            with self._banco.transacao() as con:
                existente = con.execute(
                    f"select {self._COLS_REV} from public.avaliacao_revisoes "
                    "where avaliacao_id = %s and solicitante_id = %s "
                    "and status in ('aberta', 'em_analise') limit 1",
                    (aid, sid),
                ).fetchone()
                if existente is not None:
                    return self._rev(existente), False, "ja_aberta"
                nova = con.execute(
                    "insert into public.avaliacao_revisoes "
                    "(id, avaliacao_id, tipo, ocultacao_id, solicitante_id, justificativa, "
                    "anexos, canal, aberta_em, responder_ate) "
                    f"values (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s) returning {self._COLS_REV}",
                    (
                        uuid.uuid4(),
                        aid,
                        tipo,
                        oid,
                        sid,
                        justificativa,
                        Jsonb(list(anexos)),
                        canal,
                        agora,
                        responder_ate,
                    ),
                ).fetchone()
            return self._rev(nova), True, "ok"
        except Duplicado:
            with self._banco.transacao() as con:
                existente = con.execute(
                    f"select {self._COLS_REV} from public.avaliacao_revisoes "
                    "where avaliacao_id = %s and solicitante_id = %s "
                    "and status in ('aberta', 'em_analise') limit 1",
                    (aid, sid),
                ).fetchone()
            return (
                (self._rev(existente), False, "ja_aberta")
                if existente
                else (None, False, "ja_aberta")
            )

    def obter_revisao(self, revisao_id: str) -> RevisaoAvaliacao | None:
        rid = como_uuid(revisao_id)
        if rid is None:
            return None
        with self._banco.transacao() as con:
            l = con.execute(  # noqa: E741
                f"select {self._COLS_REV} from public.avaliacao_revisoes where id = %s",
                (rid,),
            ).fetchone()
        return self._rev(l) if l else None

    def listar_revisoes_do_usuario(
        self, solicitante_id: str, limite: int, deslocamento: int
    ) -> tuple[list[RevisaoAvaliacao], int]:
        sid = como_uuid(solicitante_id)
        if sid is None:
            return [], 0
        with self._banco.transacao() as con:
            tot = con.execute(
                "select count(*) as n from public.avaliacao_revisoes where solicitante_id = %s",
                (sid,),
            ).fetchone()
            linhas = con.execute(
                f"select {self._COLS_REV} from public.avaliacao_revisoes "
                "where solicitante_id = %s order by aberta_em desc, id desc limit %s offset %s",
                (sid, limite, deslocamento),
            ).fetchall()
        return [self._rev(l) for l in linhas], int(tot["n"]) if tot else 0  # noqa: E741

    def listar_revisoes_admin(
        self,
        status: str | None,
        avaliacao_id: str | None,
        limite: int,
        deslocamento: int,
    ) -> tuple[list[RevisaoAvaliacao], int]:
        filtros: list[str] = []
        params: list[Any] = []
        if status is not None:
            filtros.append("status = %s")
            params.append(status)
        if avaliacao_id is not None:
            aid = como_uuid(avaliacao_id)
            if aid is None:
                return [], 0
            filtros.append("avaliacao_id = %s")
            params.append(aid)
        where = f"where {' and '.join(filtros)}" if filtros else ""
        with self._banco.transacao() as con:
            tot = con.execute(
                f"select count(*) as n from public.avaliacao_revisoes {where}",
                tuple(params),
            ).fetchone()
            linhas = con.execute(
                f"select {self._COLS_REV} from public.avaliacao_revisoes {where} "
                "order by responder_ate asc, id asc limit %s offset %s",
                (*params, limite, deslocamento),
            ).fetchall()
        return [self._rev(l) for l in linhas], int(tot["n"]) if tot else 0  # noqa: E741

    def iniciar_analise(
        self, revisao_id: str, analista_id: str
    ) -> tuple[RevisaoAvaliacao | None, str]:
        rid = como_uuid(revisao_id)
        if rid is None:
            return None, "nao_encontrada"
        op_id = exigir_uuid(analista_id, "analista")
        with self._banco.transacao() as con:
            atual = con.execute(
                f"select {self._COLS_REV} from public.avaliacao_revisoes where id = %s for update",
                (rid,),
            ).fetchone()
            if atual is None:
                return None, "nao_encontrada"
            if atual["status"] in ("aceita", "recusada"):
                return self._rev(atual), "ja_decidida"
            if atual["status"] == "em_analise":
                return self._rev(atual), "repetido"
            nova = con.execute(
                f"update public.avaliacao_revisoes set status = 'em_analise', analista_id = %s "
                f"where id = %s returning {self._COLS_REV}",
                (op_id, rid),
            ).fetchone()
        return self._rev(nova), "ok"

    def decidir_revisao(
        self,
        revisao_id: str,
        status_final: str,
        analista_id: str,
        resposta: str,
        agora: datetime,
        mesmo_analista_justificativa: str | None = None,
    ) -> tuple[RevisaoAvaliacao | None, str]:
        rid = como_uuid(revisao_id)
        if rid is None:
            return None, "nao_encontrada"
        op_id = exigir_uuid(analista_id, "analista")
        try:
            with self._banco.transacao() as con:
                atual = con.execute(
                    f"select {self._COLS_REV} from public.avaliacao_revisoes "
                    "where id = %s for update",
                    (rid,),
                ).fetchone()
                if atual is None:
                    return None, "nao_encontrada"
                if atual["status"] in ("aceita", "recusada"):
                    if atual["status"] == status_final and atual["resposta"] == resposta:
                        return self._rev(atual), "repetido"
                    return self._rev(atual), "ja_decidida"
                if atual["tipo"] == "contestacao_ocultacao" and atual["ocultacao_id"]:
                    ocu = con.execute(
                        "select analista_id from public.avaliacao_ocultacoes where id = %s",
                        (atual["ocultacao_id"],),
                    ).fetchone()
                    if (
                        ocu is not None
                        and str(ocu["analista_id"]) == str(op_id)
                        and not (mesmo_analista_justificativa or "").strip()
                    ):
                        return self._rev(atual), "mesmo_analista_sem_justificativa"
                nova = con.execute(
                    "update public.avaliacao_revisoes "
                    "set status = %s, analista_id = %s, resposta = %s, "
                    "mesmo_analista_justificativa = %s, decidida_em = %s "
                    f"where id = %s returning {self._COLS_REV}",
                    (
                        status_final,
                        op_id,
                        resposta,
                        mesmo_analista_justificativa,
                        agora,
                        rid,
                    ),
                ).fetchone()
            return self._rev(nova), "ok"
        except ErroPersistencia:
            return self.obter_revisao(revisao_id), "ja_decidida"
