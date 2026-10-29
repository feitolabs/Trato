"""Versões em memória dos repositórios das rotas do app. Não são o armazenamento real."""

from __future__ import annotations

import itertools
from collections.abc import Callable, Sequence
from datetime import UTC, datetime
from typing import Any

from trato.api.repositorios_app import (
    Avaliacao,
    DocumentoVerificacao,
    PerfilDetalhe,
    Verificacao,
)
from trato.pagamentos.taxa import ConfigTaxa, calcular_taxa
from trato.persistencia.conversas import Mensagem, Notificacao, mascarar_contatos
from trato.persistencia.erros import NaoEncontrado


class ConversasEmMemoria:
    def __init__(self, contratado: Callable[[str], bool] | None = None) -> None:
        self.contratado = contratado  # pedido_id -> já tem contrato? (o contexto liga)
        self._conversas: dict[tuple[str, str], str] = {}
        self._mensagens: dict[str, list[Mensagem]] = {}
        self._pedido_da_conversa: dict[str, str] = {}
        self._ids = itertools.count(1)

    def abrir(self, pedido_id: str, profissional_id: str) -> str:
        chave = (pedido_id, profissional_id)
        if chave not in self._conversas:
            conversa = f"conv-{len(self._conversas) + 1}"
            self._conversas[chave] = conversa
            self._mensagens[conversa] = []
            self._pedido_da_conversa[conversa] = pedido_id
        return self._conversas[chave]

    def enviar(self, conversa_id: str, autor_id: str, corpo: str) -> int:
        if conversa_id not in self._mensagens:
            raise NaoEncontrado("Conversa não encontrada ou encerrada.")
        pedido = self._pedido_da_conversa[conversa_id]
        contratado = self.contratado(pedido) if self.contratado else False
        exibido = corpo if contratado else mascarar_contatos(corpo)
        nova = Mensagem(
            next(self._ids), autor_id, exibido, exibido != corpo, datetime.now(UTC), None
        )
        self._mensagens[conversa_id].append(nova)
        return nova.id

    def listar(self, conversa_id: str) -> Sequence[Mensagem]:
        return tuple(self._mensagens.get(conversa_id, ()))


class NotificacoesEmMemoria:
    def __init__(self) -> None:
        self._itens: dict[str, list[Notificacao]] = {}

    def criar(
        self,
        usuario_id: str,
        tipo: str,
        titulo: str,
        *,
        corpo: str | None = None,
        dados: dict[str, Any] | None = None,
        agora: datetime | None = None,
    ) -> str:
        lista = self._itens.setdefault(usuario_id, [])
        nova = Notificacao(
            f"not-{len(lista) + 1}-{usuario_id}",
            tipo,
            "app",
            titulo,
            corpo,
            dados or {},
            agora or datetime.now(UTC),
            None,
        )
        lista.append(nova)
        return nova.id

    def listar(self, usuario_id: str, apenas_nao_lidas: bool = False) -> Sequence[Notificacao]:
        itens = reversed(self._itens.get(usuario_id, ()))
        return tuple(n for n in itens if not apenas_nao_lidas or n.lida_em is None)


class UsuariosEmMemoria:
    def __init__(self, perfis: Sequence[PerfilDetalhe] = ()) -> None:
        self._perfis = {p.id: p for p in perfis}

    def adicionar(self, perfil: PerfilDetalhe) -> None:
        self._perfis[perfil.id] = perfil

    def detalhe(self, usuario_id: str) -> PerfilDetalhe | None:
        return self._perfis.get(usuario_id)


class VerificacoesEmMemoria:
    def __init__(self) -> None:
        self._itens: list[Verificacao] = []

    def enviar(
        self,
        profissional_id: str,
        nivel: str,
        documentos: Sequence[DocumentoVerificacao],
        agora: datetime,
    ) -> Verificacao:
        nova = Verificacao(
            f"ver-{len(self._itens) + 1}", profissional_id, nivel, "enviada", agora,
            tuple(documentos),
        )  # fmt: skip
        self._itens.append(nova)
        return nova

    def da_pessoa(self, profissional_id: str) -> Sequence[Verificacao]:
        return tuple(v for v in reversed(self._itens) if v.profissional_id == profissional_id)


class AvaliacoesEmMemoria:
    def __init__(self) -> None:
        self._itens: dict[tuple[str, str], Avaliacao] = {}

    def obter(self, pedido_id: str, direcao: str) -> Avaliacao | None:
        return self._itens.get((pedido_id, direcao))

    def salvar(self, avaliacao: Avaliacao) -> None:
        self._itens[(avaliacao.pedido_id, avaliacao.direcao)] = avaliacao


class TaxaEmMemoria:
    def __init__(self, config: ConfigTaxa) -> None:
        self._config = config

    def calcular(self, valor_centavos: int) -> int:
        return calcular_taxa(valor_centavos, self._config)
