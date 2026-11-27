"""Chamados do atendimento (Termos 25.3 a 25.5; `chamados` e `chamado_mensagens`, migration
20261125224500). O protocolo vem do banco. Mensagem não muda nem some. Sem as tabelas,
`disponivel()` é falso e as rotas respondem 503."""

# ruff: noqa: S608 - só nomes fixos de colunas e condições entram na f-string; valores por parâmetro

from __future__ import annotations

import threading
import uuid
from dataclasses import dataclass, field, replace
from datetime import datetime, timedelta
from typing import Any, Protocol

from psycopg.types.json import Jsonb

from trato.persistencia.comum import como_uuid
from trato.persistencia.conexao import Banco

ENCERRADO = "encerrado"
# Toque repetido do mesmo contato dentro desta janela devolve o chamado já aberto.
JANELA_REPETIDO = timedelta(minutes=5)


@dataclass(frozen=True)
class Chamado:
    categoria: str
    assunto: str
    canal: str
    criado_em: datetime
    responder_ate: datetime
    usuario_id: str | None = None
    nome_contato: str | None = None
    contato: str | None = None
    pedido_id: str | None = None
    prioridade: str = "normal"
    status: str = "aberto"
    responsavel_id: str | None = None
    primeira_resposta_em: datetime | None = None
    novo_prazo_ate: datetime | None = None
    motivo_extensao: str | None = None
    encerrado_em: datetime | None = None
    protocolo: str | None = None
    id: str | None = None

    @property
    def prazo(self) -> datetime:
        return self.novo_prazo_ate or self.responder_ate


@dataclass(frozen=True)
class MensagemChamado:
    autor_tipo: str  # usuario | equipe | sistema
    texto: str
    criada_em: datetime
    autor_id: str | None = None
    interna: bool = False
    anexos: tuple[Any, ...] = ()
    id: str | None = None


@dataclass(frozen=True)
class Filtro:
    usuario_id: str | None = None
    status: str | None = None
    categoria: str | None = None
    prioridade: str | None = None
    responsavel_id: str | None = None
    pedido_id: str | None = None
    protocolo: str | None = None
    atrasados_em: datetime | None = None  # prazo vencido sem resposta nesta data
    extras: tuple[str, ...] = field(default_factory=tuple)


class RepositorioSac(Protocol):
    def disponivel(self) -> bool: ...

    def abrir(self, chamado: Chamado, primeira: MensagemChamado) -> tuple[Chamado, bool]:
        """(chamado, é novo). Repetição recente do mesmo contato devolve o existente."""

    def obter(self, chamado_id: str) -> Chamado | None: ...

    def listar(
        self, filtro: Filtro, limite: int, deslocamento: int
    ) -> tuple[list[Chamado], int]: ...

    def mensagens(self, chamado_id: str, com_internas: bool) -> list[MensagemChamado]: ...

    def mudar(
        self,
        chamado_id: str,
        campos: dict[str, Any],
        mensagem: MensagemChamado | None = None,
        so_responsavel: tuple[str | None, ...] | None = None,
    ) -> bool:
        """Grava campos e mensagem juntos, só se o chamado não estiver encerrado (e, quando
        pedido, se o responsável atual estiver em `so_responsavel`)."""


class SacEmMemoria:
    def __init__(self) -> None:
        self._itens: dict[str, Chamado] = {}
        self._mensagens: dict[str, list[MensagemChamado]] = {}
        self._trava = threading.Lock()

    def disponivel(self) -> bool:
        return True

    def abrir(self, chamado: Chamado, primeira: MensagemChamado) -> tuple[Chamado, bool]:
        with self._trava:
            for c in self._itens.values():
                if (
                    chamado.usuario_id is not None
                    and c.status != ENCERRADO
                    and (c.usuario_id, c.categoria, c.assunto, c.pedido_id)
                    == (
                        chamado.usuario_id,
                        chamado.categoria,
                        chamado.assunto,
                        chamado.pedido_id,
                    )
                    and chamado.criado_em - c.criado_em <= JANELA_REPETIDO
                    and self._mensagens[c.id or ""][0].texto == primeira.texto
                ):
                    return c, False
            numero = len(self._itens) + 1
            novo = replace(
                chamado,
                id=uuid.uuid4().hex,
                protocolo=f"SAC-{chamado.criado_em.year}-{numero:06d}",
            )
            self._itens[novo.id] = novo
            self._mensagens[novo.id] = [replace(primeira, id=uuid.uuid4().hex)]
            return novo, True

    def obter(self, chamado_id: str) -> Chamado | None:
        return self._itens.get(chamado_id)

    def listar(self, filtro: Filtro, limite: int, deslocamento: int) -> tuple[list[Chamado], int]:
        def serve(c: Chamado) -> bool:
            for nome in (
                "usuario_id",
                "status",
                "categoria",
                "prioridade",
                "responsavel_id",
                "pedido_id",
                "protocolo",
            ):
                valor = getattr(filtro, nome)
                if valor is not None and getattr(c, nome) != valor:
                    return False
            return filtro.atrasados_em is None or (
                c.status not in (ENCERRADO, "respondido") and c.prazo < filtro.atrasados_em
            )

        achados = [c for c in self._itens.values() if serve(c)]
        if filtro.usuario_id:  # a pessoa vê os mais novos primeiro
            achados.sort(key=lambda c: c.criado_em, reverse=True)
        else:  # a equipe, o prazo mais curto primeiro
            achados.sort(key=lambda c: (c.status == ENCERRADO, c.prazo, c.protocolo))
        return achados[deslocamento : deslocamento + limite], len(achados)

    def mensagens(self, chamado_id: str, com_internas: bool) -> list[MensagemChamado]:
        todas = self._mensagens.get(chamado_id, [])
        return [m for m in todas if com_internas or not m.interna]

    def mudar(
        self,
        chamado_id: str,
        campos: dict[str, Any],
        mensagem: MensagemChamado | None = None,
        so_responsavel: tuple[str | None, ...] | None = None,
    ) -> bool:
        with self._trava:
            atual = self._itens.get(chamado_id)
            if atual is None or atual.status == ENCERRADO:
                return False
            if so_responsavel is not None and atual.responsavel_id not in so_responsavel:
                return False
            self._itens[chamado_id] = replace(atual, **campos)
            if mensagem is not None:
                self._mensagens[chamado_id].append(replace(mensagem, id=uuid.uuid4().hex))
            return True


_COLUNAS = (
    "id, protocolo, usuario_id, nome_contato, contato, canal, categoria, assunto, status, "
    "prioridade, responsavel_id, pedido_id, criado_em, responder_ate, primeira_resposta_em, "
    "novo_prazo_ate, motivo_extensao, encerrado_em"
)
_MUTAVEIS = frozenset(
    {"status", "responsavel_id", "primeira_resposta_em", "novo_prazo_ate", "motivo_extensao",
     "encerrado_em"}
)  # fmt: skip


def _texto(valor: Any) -> str | None:
    return None if valor is None else str(valor)


def _montar(linha: dict[str, Any]) -> Chamado:
    dados = dict(linha)
    for nome in ("id", "usuario_id", "responsavel_id", "pedido_id"):
        dados[nome] = _texto(dados[nome])
    return Chamado(**dados)


class SacPostgres:
    def __init__(self, banco: Banco) -> None:
        self._banco = banco

    def disponivel(self) -> bool:
        with self._banco.transacao() as con:
            return con.execute(
                "select to_regclass('public.chamados') is not null "
                "and to_regclass('public.chamado_mensagens') is not null as tem"
            ).fetchone()["tem"]

    @staticmethod
    def _gravar_mensagem(con: Any, chamado_id: Any, m: MensagemChamado) -> None:
        con.execute(
            "insert into public.chamado_mensagens (chamado_id, autor_tipo, autor_id, texto, "
            "anexos, interna, criada_em) values (%s, %s, %s, %s, %s, %s, %s)",
            (chamado_id, m.autor_tipo, como_uuid(m.autor_id) if m.autor_id else None, m.texto,
             Jsonb(list(m.anexos)), m.interna, m.criada_em),
        )  # fmt: skip

    def abrir(self, chamado: Chamado, primeira: MensagemChamado) -> tuple[Chamado, bool]:
        uid = como_uuid(chamado.usuario_id) if chamado.usuario_id else None
        pid = como_uuid(chamado.pedido_id) if chamado.pedido_id else None
        with self._banco.transacao() as con:
            if uid is not None:  # dois toques juntos da mesma pessoa entram em fila
                con.execute("select pg_advisory_xact_lock(hashtextextended(%s, 7))", (str(uid),))
                repetido = con.execute(
                    f"select {_COLUNAS} from public.chamados c where usuario_id = %s "
                    "and categoria = %s and assunto = %s and pedido_id is not distinct from %s "
                    "and status <> 'encerrado' and criado_em >= %s and (select m.texto from "
                    "public.chamado_mensagens m where m.chamado_id = c.id "
                    "order by m.criada_em limit 1) = %s order by criado_em desc limit 1",
                    (uid, chamado.categoria, chamado.assunto, pid,
                     chamado.criado_em - JANELA_REPETIDO, primeira.texto),
                ).fetchone()  # fmt: skip
                if repetido is not None:
                    return _montar(repetido), False
            linha = con.execute(
                "insert into public.chamados (usuario_id, nome_contato, contato, canal, "
                "categoria, assunto, prioridade, pedido_id, criado_em, responder_ate) values "
                f"(%s, %s, %s, %s, %s, %s, %s, %s, %s, %s) returning {_COLUNAS}",
                (uid, chamado.nome_contato, chamado.contato, chamado.canal, chamado.categoria,
                 chamado.assunto, chamado.prioridade, pid, chamado.criado_em,
                 chamado.responder_ate),
            ).fetchone()  # fmt: skip
            self._gravar_mensagem(con, linha["id"], primeira)
        return _montar(linha), True

    def obter(self, chamado_id: str) -> Chamado | None:
        cid = como_uuid(chamado_id)
        if cid is None:
            return None
        with self._banco.transacao() as con:
            linha = con.execute(
                f"select {_COLUNAS} from public.chamados where id = %s", (cid,)
            ).fetchone()
        return _montar(linha) if linha else None

    def listar(self, filtro: Filtro, limite: int, deslocamento: int) -> tuple[list[Chamado], int]:
        condicoes, valores = ["true"], []
        for nome in ("status", "categoria", "prioridade", "protocolo"):
            valor = getattr(filtro, nome)
            if valor is not None:
                condicoes.append(f"{nome} = %s")
                valores.append(valor)
        for nome in ("usuario_id", "responsavel_id", "pedido_id"):
            valor = getattr(filtro, nome)
            if valor is not None:
                if como_uuid(valor) is None:
                    return [], 0
                condicoes.append(f"{nome} = %s")
                valores.append(como_uuid(valor))
        if filtro.atrasados_em is not None:
            condicoes.append(
                "status not in ('encerrado', 'respondido') "
                "and coalesce(novo_prazo_ate, responder_ate) < %s"
            )
            valores.append(filtro.atrasados_em)
        ordem = (
            "criado_em desc"
            if filtro.usuario_id
            else "(status = 'encerrado'), coalesce(novo_prazo_ate, responder_ate), protocolo"
        )
        onde = " and ".join(condicoes)
        with self._banco.transacao() as con:
            total = con.execute(
                f"select count(*) as n from public.chamados where {onde}", valores
            ).fetchone()["n"]
            linhas = con.execute(
                f"select {_COLUNAS} from public.chamados where {onde} order by {ordem} "
                "limit %s offset %s",
                [*valores, limite, deslocamento],
            ).fetchall()
        return [_montar(x) for x in linhas], int(total)

    def mensagens(self, chamado_id: str, com_internas: bool) -> list[MensagemChamado]:
        cid = como_uuid(chamado_id)
        if cid is None:
            return []
        filtro = "" if com_internas else " and not interna"
        with self._banco.transacao() as con:
            linhas = con.execute(
                "select id, autor_tipo, autor_id, texto, anexos, interna, criada_em "
                f"from public.chamado_mensagens where chamado_id = %s{filtro} order by criada_em",
                (cid,),
            ).fetchall()
        return [
            MensagemChamado(
                autor_tipo=x["autor_tipo"],
                texto=x["texto"],
                criada_em=x["criada_em"],
                autor_id=_texto(x["autor_id"]),
                interna=x["interna"],
                anexos=tuple(x["anexos"]),
                id=str(x["id"]),
            )
            for x in linhas
        ]

    def mudar(
        self,
        chamado_id: str,
        campos: dict[str, Any],
        mensagem: MensagemChamado | None = None,
        so_responsavel: tuple[str | None, ...] | None = None,
    ) -> bool:
        cid = como_uuid(chamado_id)
        if cid is None or set(campos) - _MUTAVEIS:
            return False
        if "responsavel_id" in campos:
            campos = campos | {"responsavel_id": como_uuid(campos["responsavel_id"] or "")}
        with self._banco.transacao() as con:
            atual = con.execute(
                "select status, responsavel_id from public.chamados where id = %s for update",
                (cid,),
            ).fetchone()
            if atual is None or atual["status"] == ENCERRADO:
                return False
            if so_responsavel is not None:
                aceitos = {None if u is None else como_uuid(u) for u in so_responsavel}
                dono = atual["responsavel_id"]
                if (None if dono is None else como_uuid(str(dono))) not in aceitos:
                    return False
            if campos:
                trocas = ", ".join(f"{nome} = %s" for nome in campos)
                con.execute(
                    f"update public.chamados set {trocas} where id = %s", [*campos.values(), cid]
                )
            if mensagem is not None:
                self._gravar_mensagem(con, cid, mensagem)
        return True
