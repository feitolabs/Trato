"""Contestação da retenção por cliente ausente (8.7) e vínculos que autorizam ler conversas (11.3).

A contestação vira um CHAMADO (`chamados` + `chamado_mensagens`, categoria `contestacao`):
`disputa_contestacoes` exige uma disputa decidida, e a ausência não é disputa. O resultado fica
na mensagem da equipe que encerra o chamado. Sem as tabelas, `disponivel()` é falso.
"""

# ruff: noqa: S608 - só trechos fixos de SQL são concatenados; valores vão por parâmetro

from __future__ import annotations

import threading
import uuid
from collections.abc import Sequence
from dataclasses import dataclass, replace
from datetime import datetime
from typing import Any, Protocol

from psycopg.types.json import Jsonb

from trato.persistencia.comum import como_uuid
from trato.persistencia.conexao import Banco

ASSUNTO = "Contestação da retenção por cliente ausente"
ABERTA = "aberta"


@dataclass(frozen=True)
class Revisao:
    pedido_id: str
    cliente_id: str
    texto: str
    anexos: tuple[str, ...]
    aberta_em: datetime
    responder_ate: datetime
    status: str = ABERTA  # aberta | mantida | alterada | revertida
    analista_id: str | None = None
    resposta: str | None = None
    decidida_em: datetime | None = None
    protocolo: str | None = None
    id: str | None = None


class RepositorioChamados(Protocol):
    def disponivel(self) -> bool: ...

    def revisao(self, pedido_id: str, desde: datetime) -> Revisao | None:
        """A contestação aberta a partir de `desde` (quando a retenção foi mostrada)."""

    def abrir_revisao(self, item: Revisao) -> Revisao: ...

    def decidir_revisao(
        self, item: Revisao, status: str, analista_id: str, resposta: str, agora: datetime
    ) -> bool:
        """Fecha só se ainda estiver aberta."""

    def incidente_aberto(self, pedido_id: str) -> bool:
        """Há incidente de segurança (9.4) deste pedido ainda não encerrado?"""

    def vinculo(
        self,
        base: str,
        pedido_id: str,
        participantes: Sequence[str],
        referencia: str | None,
    ) -> bool:
        """Existe no pedido o fato que permite ler as mensagens (denúncia, incidente...)?"""

    def partes_do_vinculo(
        self, base: str, pedido_id: str, referencia: str | None, candidatos: Sequence[str]
    ) -> set[str]:
        """Quais dos `candidatos` (profissionais com conversa) fazem parte do fato."""


class ChamadosEmMemoria:
    def __init__(self) -> None:
        self._revisoes: list[Revisao] = []
        self.vinculos: set[tuple[str, str]] = set()  # (base, pedido_id), para os testes
        self.partes: dict[tuple[str, str], set[str]] = {}  # idem: quem o fato envolve
        self.incidentes: set[str] = set()  # pedidos com incidente aberto, para os testes
        self._registrados: Any = None  # `IncidentesEmMemoria` do contexto
        self._trava = threading.Lock()

    def disponivel(self) -> bool:
        return True

    def ligar_incidentes(self, repositorio: Any) -> None:
        self._registrados = repositorio

    def incidente_aberto(self, pedido_id: str) -> bool:
        if pedido_id in self.incidentes:
            return True
        consultar = getattr(self._registrados, "aberto_do_pedido", None)
        return consultar is not None and consultar(pedido_id)

    def revisao(self, pedido_id: str, desde: datetime) -> Revisao | None:
        achadas = [r for r in self._revisoes if r.pedido_id == pedido_id and r.aberta_em >= desde]
        return achadas[-1] if achadas else None

    def abrir_revisao(self, item: Revisao) -> Revisao:
        with self._trava:
            numero = len(self._revisoes) + 1
            novo = replace(item, id=uuid.uuid4().hex, protocolo=f"SAC-MEM-{numero:06d}")
            self._revisoes.append(novo)
            return novo

    def decidir_revisao(
        self, item: Revisao, status: str, analista_id: str, resposta: str, agora: datetime
    ) -> bool:
        with self._trava:
            for i, r in enumerate(self._revisoes):
                if r.id == item.id and r.status == ABERTA:
                    self._revisoes[i] = replace(
                        r,
                        status=status,
                        analista_id=analista_id,
                        resposta=resposta,
                        decidida_em=agora,
                    )
                    return True
        return False

    def vinculo(
        self,
        base: str,
        pedido_id: str,
        participantes: Sequence[str],
        referencia: str | None,
    ) -> bool:
        return (base, pedido_id) in self.vinculos

    def partes_do_vinculo(
        self, base: str, pedido_id: str, referencia: str | None, candidatos: Sequence[str]
    ) -> set[str]:
        return self.partes.get((base, pedido_id), set()) & set(candidatos)


# Chamado aberto pela equipe não cria o vínculo sozinho: precisa de mensagem do próprio usuário.
_DO_USUARIO = (
    "exists (select 1 from public.chamado_mensagens m where m.chamado_id = chamados.id "
    "and m.autor_tipo = 'usuario')"
)

# Fatos do banco que ligam cada base ao pedido (tabela exigida, consulta).
_VINCULOS = {
    "relato": (
        "chamados",
        "select 1 from public.chamados where pedido_id = %(pedido)s "
        "and categoria in ('reclamacao', 'contestacao') and " + _DO_USUARIO,
    ),
    "denuncia": (
        "alertas_risco",
        "select 1 from public.alertas_risco where pedido_id = %(pedido)s "
        "or position(%(marca)s in detalhes) > 0",
    ),
    "incidente": (
        "incidentes_seguranca",
        "select 1 from public.incidentes_seguranca where pedido_id = %(pedido)s",
    ),
    "fraude": (
        "incidentes_seguranca",
        "select 1 from public.incidentes_seguranca where pedido_id = %(pedido)s "
        "and tipo in ('pagamento_por_fora', 'comportamento_suspeito', 'pessoa_diferente') "
        "union all select 1 from public.alertas_risco where pedido_id = %(pedido)s",
    ),
    "autorizacao_usuario": (
        "chamados",
        "select 1 from public.chamados where pedido_id = %(pedido)s "
        "and protocolo = %(referencia)s and usuario_id = any(%(participantes)s) and " + _DO_USUARIO,
    ),
}


class ChamadosPostgres:
    def __init__(self, banco: Banco) -> None:
        self._banco = banco

    @staticmethod
    def _tem(con: Any, tabela: str) -> bool:
        return con.execute(
            "select to_regclass(%s) is not null as tem", (f"public.{tabela}",)
        ).fetchone()["tem"]

    def disponivel(self) -> bool:
        with self._banco.transacao() as con:
            return self._tem(con, "chamados")

    def incidente_aberto(self, pedido_id: str) -> bool:
        pid = como_uuid(pedido_id)
        if pid is None:
            return False
        with self._banco.transacao() as con:
            if not self._tem(con, "incidentes_seguranca"):
                return False
            return (
                con.execute(
                    "select 1 from public.incidentes_seguranca where pedido_id = %s "
                    "and status <> 'encerrado' limit 1",
                    (pid,),
                ).fetchone()
                is not None
            )

    def revisao(self, pedido_id: str, desde: datetime) -> Revisao | None:
        pid = como_uuid(pedido_id)
        if pid is None:
            return None
        with self._banco.transacao() as con:
            if not self._tem(con, "chamados"):
                return None
            c = con.execute(
                "select id, protocolo, usuario_id, status, criado_em, responder_ate, "
                "responsavel_id, encerrado_em from public.chamados where pedido_id = %s "
                "and categoria = 'contestacao' and assunto = %s and criado_em >= %s "
                "order by criado_em desc limit 1",
                (pid, ASSUNTO, desde),
            ).fetchone()
            if c is None:
                return None
            mensagens = con.execute(
                "select autor_tipo, texto, anexos from public.chamado_mensagens "
                "where chamado_id = %s order by criada_em",
                (c["id"],),
            ).fetchall()
        pedido = next((m for m in mensagens if m["autor_tipo"] == "usuario"), None)
        decisao = next(  # respostas comuns do atendimento não são a decisão
            (
                m
                for m in mensagens
                if m["autor_tipo"] == "equipe"
                and any(isinstance(a, dict) and "resultado" in a for a in m["anexos"])
            ),
            None,
        )
        status = ABERTA
        if c["status"] == "encerrado":  # encerrado por fora, sem decisão: a retenção se mantém
            status = decisao["anexos"][0]["resultado"] if decisao else "mantida"
        return Revisao(
            pedido_id=pedido_id,
            cliente_id=str(c["usuario_id"]),
            texto=pedido["texto"] if pedido else "",
            anexos=tuple(pedido["anexos"]) if pedido else (),
            aberta_em=c["criado_em"],
            responder_ate=c["responder_ate"],
            status=status,
            analista_id=str(c["responsavel_id"]) if c["responsavel_id"] else None,
            resposta=decisao["texto"] if decisao else None,
            decidida_em=c["encerrado_em"],
            protocolo=c["protocolo"],
            id=str(c["id"]),
        )

    def abrir_revisao(self, item: Revisao) -> Revisao:
        pid, uid = como_uuid(item.pedido_id), como_uuid(item.cliente_id)
        with self._banco.transacao() as con:
            c = con.execute(
                "insert into public.chamados (usuario_id, canal, categoria, assunto, "
                "prioridade, pedido_id, criado_em, responder_ate) values "
                "(%s, 'app', 'contestacao', %s, 'alta', %s, %s, %s) returning id",
                (uid, ASSUNTO, pid, item.aberta_em, item.responder_ate),
            ).fetchone()
            con.execute(
                "insert into public.chamado_mensagens (chamado_id, autor_tipo, autor_id, texto, "
                "anexos, criada_em) values (%s, 'usuario', %s, %s, %s, %s)",
                (c["id"], uid, item.texto, Jsonb(list(item.anexos)), item.aberta_em),
            )
        gravado = self.revisao(item.pedido_id, item.aberta_em)
        assert gravado is not None  # noqa: S101 - acabou de ser gravado nesta transação
        return gravado

    def decidir_revisao(
        self, item: Revisao, status: str, analista_id: str, resposta: str, agora: datetime
    ) -> bool:
        analista = como_uuid(analista_id)
        with self._banco.transacao() as con:
            cursor = con.execute(
                "update public.chamados set status = 'encerrado', encerrado_em = %s, "
                "responsavel_id = %s, primeira_resposta_em = coalesce(primeira_resposta_em, %s) "
                "where id = %s and status <> 'encerrado'",
                (agora, analista, agora, como_uuid(item.id or "")),
            )
            if cursor.rowcount != 1:
                return False
            con.execute(
                "insert into public.chamado_mensagens (chamado_id, autor_tipo, autor_id, texto, "
                "anexos, criada_em) values (%s, 'equipe', %s, %s, %s, %s)",
                (como_uuid(item.id or ""), analista, resposta, Jsonb([{"resultado": status}]),
                 agora),
            )  # fmt: skip
        return True

    def vinculo(
        self,
        base: str,
        pedido_id: str,
        participantes: Sequence[str],
        referencia: str | None,
    ) -> bool:
        pid = como_uuid(pedido_id)
        if pid is None or base not in _VINCULOS:
            return False
        tabela, sql = _VINCULOS[base]
        with self._banco.transacao() as con:
            if not self._tem(con, tabela) or not self._tem(con, "alertas_risco"):
                return False
            return (
                con.execute(
                    sql + " limit 1",
                    {
                        "pedido": pid,
                        "marca": f"Pedido {pedido_id}:",
                        "referencia": referencia,
                        "participantes": [u for u in map(como_uuid, participantes) if u],
                    },
                ).fetchone()
                is not None
            )

    def partes_do_vinculo(
        self, base: str, pedido_id: str, referencia: str | None, candidatos: Sequence[str]
    ) -> set[str]:
        from trato.api.denuncias import marcador  # o pacote `api` importa este módulo

        pid = como_uuid(pedido_id)
        por_uuid = {como_uuid(c): c for c in candidatos if como_uuid(c) is not None}
        if pid is None or not por_uuid:
            return set()
        achados: set[str] = set()
        with self._banco.transacao() as con:

            def juntar(tabela: str, sql: str, valores: tuple) -> list[Any]:
                return con.execute(sql, valores).fetchall() if self._tem(con, tabela) else []

            if base in ("denuncia", "fraude"):
                for a in juntar(
                    "alertas_risco",
                    "select usuario_id, detalhes from public.alertas_risco "
                    "where pedido_id = %s or position(%s in detalhes) > 0",
                    (pid, f"Pedido {pedido_id}:"),
                ):
                    alvo = como_uuid(str(a["usuario_id"]))
                    achados |= {c for u, c in por_uuid.items() if u == alvo}
                    # quem denunciou: o marcador " por <quem> contra <alvo>:" no texto
                    achados |= {
                        c for c in candidatos if marcador(c, str(a["usuario_id"])) in a["detalhes"]
                    }
            if base in ("incidente", "fraude"):
                for i in juntar(
                    "incidentes_seguranca",
                    "select relator_id, envolvido_id from public.incidentes_seguranca "
                    "where pedido_id = %s",
                    (pid,),
                ):
                    quem = {como_uuid(str(v)) for v in (i["relator_id"], i["envolvido_id"]) if v}
                    achados |= {c for u, c in por_uuid.items() if u in quem}
            if base in ("relato", "autorizacao_usuario"):
                filtro = " and protocolo = %s" if base == "autorizacao_usuario" else ""
                valores = (pid, referencia) if filtro else (pid,)
                for c in juntar(
                    "chamados",
                    "select usuario_id from public.chamados where pedido_id = %s and "  # noqa: S608
                    + _DO_USUARIO
                    + filtro,
                    valores,
                ):
                    quem = como_uuid(str(c["usuario_id"]))
                    achados |= {x for u, x in por_uuid.items() if u == quem}
        return achados
