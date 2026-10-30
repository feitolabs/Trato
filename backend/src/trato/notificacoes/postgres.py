"""Repositório de notificações no Postgres (tabelas `notificacoes`, `notificacao_preferencias`
e `dispositivos_push`, esta última da migration 20261029040000, ainda não aplicada)."""

from __future__ import annotations

from collections.abc import Sequence
from datetime import datetime
from typing import Any

from psycopg.types.json import Jsonb

from trato.notificacoes.repositorio import Preferencias, Registro
from trato.persistencia.comum import como_uuid, exigir_uuid, para_json
from trato.persistencia.conexao import Banco
from trato.persistencia.erros import NaoEncontrado

_COLUNAS = "id, usuario_id, tipo, canal, titulo, corpo, dados, criada_em, enviada_em, lida_em"


def _registro(l: dict[str, Any]) -> Registro:  # noqa: E741
    return Registro(
        str(l["id"]), str(l["usuario_id"]), l["tipo"], l["canal"], l["titulo"], l["corpo"],
        l["dados"], l["criada_em"], l["enviada_em"], l["lida_em"],
    )  # fmt: skip


class NotificacoesServicoPostgres:
    def __init__(self, banco: Banco) -> None:
        self._banco = banco

    def criar(
        self,
        usuario_id: str,
        tipo: str,
        canal: str,
        titulo: str,
        corpo: str | None,
        dados: dict[str, Any],
        chave: str,
        agora: datetime,
        enviada: bool,
    ) -> tuple[Registro, bool]:
        usuario = exigir_uuid(usuario_id, "usuário")
        with self._banco.transacao() as con:
            # Trava só desta (pessoa, canal, chave) até o COMMIT: duas instâncias não duplicam.
            con.execute(
                "select pg_advisory_xact_lock(hashtextextended(%s, 0))",
                (f"notif|{usuario}|{canal}|{chave}",),
            )
            achada = con.execute(
                f"select {_COLUNAS} from public.notificacoes "  # noqa: S608
                "where usuario_id = %s and canal = %s and dados ->> 'chave' = %s",
                (usuario, canal, chave),
            ).fetchone()
            if achada is not None:
                return _registro(achada), False
            nova = con.execute(
                "insert into public.notificacoes (usuario_id, tipo, canal, titulo, corpo, dados, "  # noqa: S608
                "criada_em, enviada_em) values (%s, %s, %s, %s, %s, %s, %s, %s) "
                f"returning {_COLUNAS}",
                (usuario, tipo, canal, titulo, corpo, Jsonb(para_json({**dados, "chave": chave})),
                 agora, agora if enviada else None),
            ).fetchone()  # fmt: skip
        return _registro(nova), True

    def listar(self, usuario_id: str, apenas_nao_lidas: bool, limite: int) -> Sequence[Registro]:
        usuario = como_uuid(usuario_id)
        if usuario is None:
            return ()
        filtro = " and lida_em is null" if apenas_nao_lidas else ""
        with self._banco.transacao() as con:
            linhas = con.execute(
                f"select {_COLUNAS} from public.notificacoes "  # noqa: S608
                f"where usuario_id = %s and canal = 'app'{filtro} "
                "order by criada_em desc, id limit %s",
                (usuario, limite),
            ).fetchall()
        return tuple(_registro(l) for l in linhas)  # noqa: E741

    def marcar_lida(self, notificacao_id: str, usuario_id: str, agora: datetime) -> Registro:
        nid, usuario = como_uuid(notificacao_id), como_uuid(usuario_id)
        if nid is None or usuario is None:
            raise NaoEncontrado("Notificação não encontrada.")
        with self._banco.transacao() as con:
            linha = con.execute(
                "update public.notificacoes set lida_em = coalesce(lida_em, %s) "  # noqa: S608
                f"where id = %s and usuario_id = %s returning {_COLUNAS}",
                (agora, nid, usuario),
            ).fetchone()
        if linha is None:
            raise NaoEncontrado("Notificação não encontrada.")
        return _registro(linha)

    def pendentes(self, desde: datetime, limite: int) -> Sequence[Registro]:
        with self._banco.transacao() as con:
            linhas = con.execute(
                f"select {_COLUNAS} from public.notificacoes "  # noqa: S608
                "where canal <> 'app' and enviada_em is null and criada_em >= %s "
                "order by criada_em, id limit %s",
                (desde, limite),
            ).fetchall()
        return tuple(_registro(l) for l in linhas)  # noqa: E741

    def marcar_enviada(self, notificacao_id: str, agora: datetime) -> None:
        with self._banco.transacao() as con:
            con.execute(
                "update public.notificacoes set enviada_em = %s "
                "where id = %s and enviada_em is null",
                (agora, exigir_uuid(notificacao_id, "notificação")),
            )

    def preferencias(self, usuario_id: str) -> Preferencias:
        usuario = como_uuid(usuario_id)
        if usuario is None:
            return {}
        with self._banco.transacao() as con:
            linha = con.execute(
                "select preferencias from public.notificacao_preferencias where usuario_id = %s",
                (usuario,),
            ).fetchone()
        return linha["preferencias"] if linha else {}

    def salvar_preferencias(self, usuario_id: str, prefs: Preferencias, agora: datetime) -> None:
        with self._banco.transacao() as con:
            con.execute(
                "insert into public.notificacao_preferencias (usuario_id, preferencias) "
                "values (%s, %s) on conflict (usuario_id) do update "
                "set preferencias = excluded.preferencias",
                (exigir_uuid(usuario_id, "usuário"), Jsonb(prefs)),
            )

    def registrar_dispositivo(
        self, usuario_id: str, token: str, plataforma: str, agora: datetime
    ) -> None:
        with self._banco.transacao() as con:
            con.execute(
                "insert into public.dispositivos_push (usuario_id, token, plataforma) "
                "values (%s, %s, %s) on conflict (token) do update "
                "set usuario_id = excluded.usuario_id, plataforma = excluded.plataforma, "
                "ativo = true",
                (exigir_uuid(usuario_id, "usuário"), token, plataforma),
            )

    def tokens(self, usuario_id: str) -> Sequence[str]:
        usuario = como_uuid(usuario_id)
        if usuario is None:
            return ()
        with self._banco.transacao() as con:
            linhas = con.execute(
                "select token from public.dispositivos_push where usuario_id = %s and ativo "
                "order by criado_em, id",
                (usuario,),
            ).fetchall()
        return tuple(l["token"] for l in linhas)  # noqa: E741

    def desativar_dispositivo(self, token: str) -> None:
        with self._banco.transacao() as con:
            con.execute(
                "update public.dispositivos_push set ativo = false where token = %s", (token,)
            )
