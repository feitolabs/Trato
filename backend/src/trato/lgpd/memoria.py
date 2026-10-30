"""LGPD em memória: testes e modo `memoria` (desenvolvimento). Perde tudo ao reiniciar."""

from __future__ import annotations

import itertools
from collections.abc import Callable, Sequence
from datetime import datetime
from typing import Any

from trato.lgpd.repositorios import Consentimento, PedidoExclusao, RepositoriosLgpd

STATUS_ATIVOS = ("aguardando_confirmacao", "agendada")


class ConsentimentosEmMemoria:
    def __init__(self) -> None:
        self._linhas: list[Consentimento] = []

    def registrar(self, consentimento: Consentimento) -> None:
        self._linhas.append(consentimento)

    def historico(self, usuario_id: str) -> Sequence[Consentimento]:
        return tuple(c for c in self._linhas if c.usuario_id == usuario_id)


class ExclusoesEmMemoria:
    def __init__(self) -> None:
        self._pedidos: dict[str, PedidoExclusao] = {}
        self._ids = itertools.count(1)

    def novo_id(self) -> str:
        return f"excl-{next(self._ids)}"

    def salvar(self, pedido: PedidoExclusao) -> None:
        self._pedidos[pedido.id] = pedido

    def ativo_do_usuario(self, usuario_id: str) -> PedidoExclusao | None:
        return next(
            (
                p
                for p in self._pedidos.values()
                if p.usuario_id == usuario_id and p.status in STATUS_ATIVOS
            ),
            None,
        )

    def agendadas_ate(self, agora: datetime) -> Sequence[PedidoExclusao]:
        return tuple(
            p
            for p in self._pedidos.values()
            if p.status == "agendada" and p.executar_apos is not None and p.executar_apos <= agora
        )


class FonteDadosEmMemoria:
    """Dados do titular em dicionários. `leitores` permite acoplar fontes já existentes (perfil,
    pedidos do contexto); `anonimizar` só mexe no que é do perfil e mantém o resto."""

    def __init__(
        self,
        leitores: dict[str, Callable[[str], Any]] | None = None,
        pendencias: Callable[[str], list[str]] | None = None,
    ) -> None:
        self.perfis: dict[str, dict[str, Any]] = {}
        self.documentos: dict[str, list[str]] = {}
        # Imutáveis: só existem aqui para os testes provarem que não são tocados.
        self.ledger: list[dict[str, Any]] = []
        self.auditoria: list[dict[str, Any]] = []
        self.mensagens: list[dict[str, Any]] = []
        self.anonimizados: set[str] = set()
        self._leitores = leitores or {}
        self._pendencias = pendencias or (lambda _uid: [])

    def exportar(self, usuario_id: str) -> dict[str, Any]:
        dados: dict[str, Any] = {
            "perfil": self.perfis.get(usuario_id, {}),
            "documentos_enviados": self.documentos.get(usuario_id, []),
            "mensagens": [m for m in self.mensagens if m.get("autor_id") == usuario_id],
        }
        for nome, leitor in self._leitores.items():
            dados[nome] = leitor(usuario_id)
        return dados

    def pendencias(self, usuario_id: str) -> list[str]:
        return self._pendencias(usuario_id)

    def anonimizar(self, usuario_id: str) -> dict[str, list[str]]:
        if usuario_id in self.perfis:
            self.perfis[usuario_id] = {"nome": "Usuário anonimizado", "status": "anonimizado"}
        self.documentos.pop(usuario_id, None)
        self.anonimizados.add(usuario_id)
        return {
            "anonimizado": ["perfil", "contato", "documentos_verificacao"],
            "mantido": [
                "ledger_financeiro",
                "auditoria",
                "contratos_e_pedidos",
                "mensagens_e_disputas",
            ],
        }


def criar_repositorios_memoria(fonte: FonteDadosEmMemoria | None = None) -> RepositoriosLgpd:
    return RepositoriosLgpd(
        fonte=fonte or FonteDadosEmMemoria(),
        consentimentos=ConsentimentosEmMemoria(),
        exclusoes=ExclusoesEmMemoria(),
    )
