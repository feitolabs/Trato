"""Conversas e mensagens (imutáveis) e notificações."""

from __future__ import annotations

from collections.abc import Sequence
from dataclasses import dataclass
from datetime import datetime
from typing import Any

from psycopg.types.json import Jsonb

from trato.persistencia.comum import como_uuid, exigir_uuid, para_json
from trato.persistencia.conexao import Banco
from trato.persistencia.erros import NaoEncontrado, RegraDoBanco
from trato.seguranca.mascaramento import AVISO_MASCARA as _AVISO_MASCARA
from trato.seguranca.mascaramento import mascarar as _mascarar

AVISO_MASCARA = _AVISO_MASCARA


def mascarar_contatos(texto: str) -> str:
    """Esconde telefone, e-mail, link, perfil e endereço antes da contratação (o original fica em
    `corpo`, só o `corpo_exibido` é mascarado). A regra mora em `trato.seguranca.mascaramento`."""
    return _mascarar(texto).exibido


@dataclass(frozen=True)
class Mensagem:
    id: int
    autor_id: str
    texto: str  # o texto EXIBIDO. O original (evidência) não sai por esta camada.
    mascarada: bool
    enviada_em: datetime
    lida_em: datetime | None


@dataclass(frozen=True)
class Notificacao:
    id: str
    tipo: str
    canal: str
    titulo: str
    corpo: str | None
    dados: dict[str, Any]
    criada_em: datetime
    lida_em: datetime | None


class ConversasPostgres:
    def __init__(self, banco: Banco) -> None:
        self._banco = banco

    def abrir(self, pedido_id: str, profissional_id: str) -> str:
        """Uma conversa por pedido e profissional (repetir devolve a mesma)."""
        pedido = exigir_uuid(pedido_id, "pedido")
        profissional = exigir_uuid(profissional_id, "profissional")
        with self._banco.transacao() as con:
            ped = con.execute(
                "select cliente_id from public.pedidos where id = %s", (pedido,)
            ).fetchone()
            if ped is None:
                raise NaoEncontrado("Pedido não encontrado.")
            linha = con.execute(
                "insert into public.conversas (pedido_id, cliente_id, profissional_id) "
                "values (%s, %s, %s) on conflict (pedido_id, profissional_id) do nothing "
                "returning id",
                (pedido, ped["cliente_id"], profissional),
            ).fetchone()
            if linha is None:
                linha = con.execute(
                    "select id from public.conversas where pedido_id = %s and profissional_id = %s",
                    (pedido, profissional),
                ).fetchone()
        return str(linha["id"])

    def partes(self, conversa_id: str) -> tuple[str, str] | None:
        """(cliente_id, profissional_id) da conversa, para a rota conferir quem pode ler."""
        achado = como_uuid(conversa_id)
        if achado is None:
            return None
        with self._banco.transacao() as con:
            linha = con.execute(
                "select cliente_id, profissional_id from public.conversas where id = %s", (achado,)
            ).fetchone()
        return (str(linha["cliente_id"]), str(linha["profissional_id"])) if linha else None

    def enviar(self, conversa_id: str, autor_id: str, corpo: str) -> int:
        """Grava a mensagem. Antes da contratação (pedido não contratado) o contato é mascarado."""
        conversa = exigir_uuid(conversa_id, "conversa")
        with self._banco.transacao() as con:
            linha = con.execute(
                "select cv.pedido_id, exists (select 1 from public.contratos c "
                "where c.pedido_id = cv.pedido_id) as contratado "
                "from public.conversas cv where cv.id = %s and cv.encerrada_em is null",
                (conversa,),
            ).fetchone()
            if linha is None:
                raise NaoEncontrado("Conversa não encontrada ou encerrada.")
            exibido = corpo if linha["contratado"] else mascarar_contatos(corpo)
            nova = con.execute(
                "insert into public.mensagens (conversa_id, autor_id, corpo, corpo_exibido, "
                "mascarada) values (%s, %s, %s, %s, %s) returning id",
                (conversa, exigir_uuid(autor_id, "autor"), corpo, exibido, exibido != corpo),
            ).fetchone()
        return int(nova["id"])

    def listar(self, conversa_id: str) -> Sequence[Mensagem]:
        achado = como_uuid(conversa_id)
        if achado is None:
            return ()
        with self._banco.transacao() as con:
            linhas = con.execute(
                "select id, autor_id, corpo_exibido, mascarada, enviada_em, lida_em "
                "from public.mensagens where conversa_id = %s order by id",
                (achado,),
            ).fetchall()
        return tuple(
            Mensagem(
                int(l["id"]),
                str(l["autor_id"]),
                l["corpo_exibido"],
                l["mascarada"],
                l["enviada_em"],
                l["lida_em"],
            )  # fmt: skip
            for l in linhas  # noqa: E741
        )

    def marcar_lida(self, mensagem_id: int, agora: datetime) -> None:
        """Preenche `lida_em` uma única vez (depois disso o banco não deixa mexer)."""
        with self._banco.transacao() as con:
            linha = con.execute(
                "update public.mensagens set lida_em = %s where id = %s and lida_em is null "
                "returning id",
                (agora, mensagem_id),
            ).fetchone()
        if linha is None:
            raise RegraDoBanco("A mensagem não existe ou já foi marcada como lida.")


class NotificacoesPostgres:
    def __init__(self, banco: Banco) -> None:
        self._banco = banco

    def criar(
        self,
        usuario_id: str,
        tipo: str,
        titulo: str,
        *,
        canal: str = "app",
        corpo: str | None = None,
        dados: dict[str, Any] | None = None,
    ) -> str:
        with self._banco.transacao() as con:
            linha = con.execute(
                "insert into public.notificacoes (usuario_id, tipo, canal, titulo, corpo, dados) "
                "values (%s, %s, %s, %s, %s, %s) returning id",
                (exigir_uuid(usuario_id, "usuário"), tipo, canal, titulo, corpo,
                 Jsonb(para_json(dados or {}))),
            ).fetchone()  # fmt: skip
        return str(linha["id"])

    def listar(self, usuario_id: str, apenas_nao_lidas: bool = False) -> Sequence[Notificacao]:
        achado = como_uuid(usuario_id)
        if achado is None:
            return ()
        filtro = " and lida_em is null" if apenas_nao_lidas else ""
        with self._banco.transacao() as con:
            linhas = con.execute(
                "select id, tipo, canal, titulo, corpo, dados, criada_em, lida_em "  # noqa: S608
                f"from public.notificacoes where usuario_id = %s{filtro} "
                "order by criada_em desc, id",
                (achado,),
            ).fetchall()
        return tuple(
            Notificacao(
                str(l["id"]),
                l["tipo"],
                l["canal"],
                l["titulo"],
                l["corpo"],
                l["dados"],
                l["criada_em"],
                l["lida_em"],
            )  # fmt: skip
            for l in linhas  # noqa: E741
        )

    def marcar_lida(self, notificacao_id: str, usuario_id: str, agora: datetime) -> None:
        with self._banco.transacao() as con:
            linha = con.execute(
                "update public.notificacoes set lida_em = %s "
                "where id = %s and usuario_id = %s and lida_em is null returning id",
                (agora, exigir_uuid(notificacao_id, "notificação"), exigir_uuid(usuario_id)),
            ).fetchone()
        if linha is None:
            raise NaoEncontrado("Notificação não encontrada ou já lida.")
