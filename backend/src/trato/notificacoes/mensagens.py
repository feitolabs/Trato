"""Conversas: listar as minhas e marcar mensagens como lidas.

Enviar e listar as mensagens de um pedido continuam em `trato/api/rotas_app.py`. Aqui entram a
lista de conversas (com não lidas) e a leitura. O mascaramento de contato é de outra sessão:
`Mascarador` é o gancho; o padrão (`MascaradorSimples`) reaproveita `mascarar_contatos`.
"""

from __future__ import annotations

from collections.abc import Sequence
from dataclasses import dataclass, replace
from datetime import datetime
from typing import Any, Protocol

from trato.persistencia.comum import como_uuid
from trato.persistencia.conexao import Banco
from trato.persistencia.conversas import mascarar_contatos
from trato.persistencia.erros import DadosInvalidos, NaoEncontrado


class Mascarador(Protocol):
    def mascarar(self, texto: str) -> str:
        """Esconde e-mail/telefone do texto. Quem implementa melhor é a sessão de segurança."""


class MascaradorSimples:
    def mascarar(self, texto: str) -> str:
        return mascarar_contatos(texto)


@dataclass(frozen=True)
class ResumoConversa:
    id: str
    pedido_id: str
    outra_parte_id: str
    contratado: bool
    encerrada: bool
    nao_lidas: int
    ultima_texto: str | None
    ultima_em: datetime | None
    ultima_minha: bool | None


class RepositorioConversasApp(Protocol):
    def da_pessoa(self, usuario_id: str) -> Sequence[ResumoConversa]: ...

    def marcar_lida(self, mensagem_id: int, usuario_id: str, agora: datetime) -> datetime:
        """Só quem RECEBEU lê. Idempotente. NaoEncontrado se não é participante."""

    def marcar_conversa_lida(self, conversa_id: str, usuario_id: str, agora: datetime) -> int:
        """Marca tudo que a outra parte mandou. Devolve quantas foram marcadas agora."""


class ServicoMensagens:
    def __init__(self, repo: RepositorioConversasApp, mascarador: Mascarador | None = None) -> None:
        self.repo = repo
        self.mascarador = mascarador or MascaradorSimples()

    def conversas(self, usuario_id: str) -> list[ResumoConversa]:
        # Antes da contratação a prévia passa de novo pelo mascarador (defesa em profundidade).
        return [
            c if c.contratado or c.ultima_texto is None
            else replace(c, ultima_texto=self.mascarador.mascarar(c.ultima_texto))
            for c in self.repo.da_pessoa(usuario_id)
        ]  # fmt: skip


class ConversasAppEmMemoria:
    """Lê as estruturas de `ConversasEmMemoria` (só modo memória / testes)."""

    def __init__(self, contexto: Any) -> None:
        self._contexto = contexto

    @property
    def _base(self) -> Any:
        return self._contexto.conversas

    def _partes(self, conversa: str) -> tuple[str, str, str] | None:
        pedido_id = self._base._pedido_da_conversa.get(conversa)
        if pedido_id is None:
            return None
        pedido = self._contexto.pedidos.obter(pedido_id)
        profissional = next(p for (pid, p), c in self._base._conversas.items() if c == conversa)
        return (pedido.cliente_id, profissional, pedido_id) if pedido else None

    def da_pessoa(self, usuario_id: str) -> Sequence[ResumoConversa]:
        saida = []
        for conversa, mensagens in self._base._mensagens.items():
            partes = self._partes(conversa)
            if partes is None or usuario_id not in partes[:2]:
                continue
            cliente, profissional, pedido_id = partes
            ultima = mensagens[-1] if mensagens else None
            saida.append(
                ResumoConversa(
                    conversa,
                    pedido_id,
                    profissional if usuario_id == cliente else cliente,
                    self._contexto.contratos.obter_do_pedido(pedido_id) is not None,
                    False,
                    sum(1 for m in mensagens if m.autor_id != usuario_id and m.lida_em is None),
                    ultima.texto if ultima else None,
                    ultima.enviada_em if ultima else None,
                    ultima.autor_id == usuario_id if ultima else None,
                )  # fmt: skip
            )
        return sorted(
            saida, key=lambda c: c.ultima_em.timestamp() if c.ultima_em else 0, reverse=True
        )

    def _achar(self, mensagem_id: int, usuario_id: str) -> tuple[str, int] | None:
        for conversa, mensagens in self._base._mensagens.items():
            partes = self._partes(conversa)
            for i, m in enumerate(mensagens):
                if m.id == mensagem_id and partes and usuario_id in partes[:2]:
                    return conversa, i
        return None

    def marcar_lida(self, mensagem_id: int, usuario_id: str, agora: datetime) -> datetime:
        achada = self._achar(mensagem_id, usuario_id)
        if achada is None:
            raise NaoEncontrado("Mensagem não encontrada.")
        conversa, i = achada
        m = self._base._mensagens[conversa][i]
        if m.autor_id == usuario_id:
            raise DadosInvalidos("Você não precisa marcar a sua própria mensagem como lida.")
        if m.lida_em is None:
            m = replace(m, lida_em=agora)
            self._base._mensagens[conversa][i] = m
        return m.lida_em

    def marcar_conversa_lida(self, conversa_id: str, usuario_id: str, agora: datetime) -> int:
        partes = self._partes(conversa_id)
        if partes is None or usuario_id not in partes[:2]:
            raise NaoEncontrado("Conversa não encontrada.")
        marcadas = 0
        lista = self._base._mensagens[conversa_id]
        for i, m in enumerate(lista):
            if m.autor_id != usuario_id and m.lida_em is None:
                lista[i] = replace(m, lida_em=agora)
                marcadas += 1
        return marcadas


class ConversasAppPostgres:
    def __init__(self, banco: Banco) -> None:
        self._banco = banco

    def da_pessoa(self, usuario_id: str) -> Sequence[ResumoConversa]:
        usuario = como_uuid(usuario_id)
        if usuario is None:
            return ()
        with self._banco.transacao() as con:
            linhas = con.execute(
                "select cv.id, cv.pedido_id, cv.cliente_id, cv.profissional_id, "
                "cv.encerrada_em is not null as encerrada, "
                "exists (select 1 from public.contratos c where c.pedido_id = cv.pedido_id) "
                "as contratado, "
                "(select count(*) from public.mensagens m where m.conversa_id = cv.id "
                " and m.autor_id <> %(u)s and m.lida_em is null) as nao_lidas, "
                "u.corpo_exibido as ultima_texto, u.enviada_em as ultima_em, "
                "(u.autor_id = %(u)s) as ultima_minha "
                "from public.conversas cv "
                "left join lateral (select corpo_exibido, enviada_em, autor_id "
                " from public.mensagens m where m.conversa_id = cv.id "
                " order by m.id desc limit 1) u on true "
                "where cv.cliente_id = %(u)s or cv.profissional_id = %(u)s "
                "order by u.enviada_em desc nulls last, cv.id",
                {"u": usuario},
            ).fetchall()
        return tuple(
            ResumoConversa(
                str(l["id"]),
                str(l["pedido_id"]),
                str(l["profissional_id"] if str(l["cliente_id"]) == usuario else l["cliente_id"]),
                l["contratado"],
                l["encerrada"],
                int(l["nao_lidas"]),
                l["ultima_texto"],
                l["ultima_em"],
                l["ultima_minha"],
            )  # fmt: skip
            for l in linhas  # noqa: E741
        )

    def marcar_lida(self, mensagem_id: int, usuario_id: str, agora: datetime) -> datetime:
        usuario = como_uuid(usuario_id)
        if usuario is None:
            raise NaoEncontrado("Mensagem não encontrada.")
        with self._banco.transacao() as con:
            linha = con.execute(
                "select m.id, m.autor_id, m.lida_em from public.mensagens m "
                "join public.conversas cv on cv.id = m.conversa_id "
                "where m.id = %(m)s and (cv.cliente_id = %(u)s or cv.profissional_id = %(u)s)",
                {"m": mensagem_id, "u": usuario},
            ).fetchone()
            if linha is None:
                raise NaoEncontrado("Mensagem não encontrada.")
            if str(linha["autor_id"]) == usuario:
                raise DadosInvalidos("Você não precisa marcar a sua própria mensagem como lida.")
            if linha["lida_em"] is not None:
                return linha["lida_em"]
            con.execute(
                "update public.mensagens set lida_em = %s where id = %s and lida_em is null",
                (agora, mensagem_id),
            )
        return agora

    def marcar_conversa_lida(self, conversa_id: str, usuario_id: str, agora: datetime) -> int:
        conversa, usuario = como_uuid(conversa_id), como_uuid(usuario_id)
        if conversa is None or usuario is None:
            raise NaoEncontrado("Conversa não encontrada.")
        with self._banco.transacao() as con:
            dona = con.execute(
                "select 1 from public.conversas where id = %(c)s "
                "and (cliente_id = %(u)s or profissional_id = %(u)s)",
                {"c": conversa, "u": usuario},
            ).fetchone()
            if dona is None:
                raise NaoEncontrado("Conversa não encontrada.")
            marcadas = con.execute(
                "update public.mensagens set lida_em = %s where conversa_id = %s "
                "and autor_id <> %s and lida_em is null returning id",
                (agora, conversa, usuario),
            ).fetchall()
        return len(marcadas)
