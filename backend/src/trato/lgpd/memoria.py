"""LGPD em memória: testes e modo `memoria` (desenvolvimento). Perde tudo ao reiniciar."""

from __future__ import annotations

import itertools
import threading
from collections.abc import Callable, Sequence
from contextlib import AbstractContextManager
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

    def ultimos(self, usuario_ids: Sequence[str], finalidade: str) -> dict[str, bool]:
        pedidos = set(usuario_ids)
        achados: dict[str, bool] = {}
        # Ordenação estável: no mesmo instante vale a linha gravada por último (o "id").
        for linha in sorted(self._linhas, key=lambda c: c.registrado_em):
            if linha.finalidade == finalidade and linha.usuario_id in pedidos:
                achados[linha.usuario_id] = linha.aceito
        return achados


class ExclusoesEmMemoria:
    def __init__(self) -> None:
        self._pedidos: dict[str, PedidoExclusao] = {}
        self._ids = itertools.count(1)

    def novo_id(self) -> str:
        return f"excl-{next(self._ids)}"

    def salvar(self, pedido: PedidoExclusao) -> bool:
        atual = self._pedidos.get(pedido.id)
        if atual is not None and atual.status not in STATUS_ATIVOS:
            return False
        self._pedidos[pedido.id] = pedido
        return True

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
        self.a_remover: dict[str, list[tuple[str, str]]] = {}
        self._leitores = leitores or {}
        self._pendencias = pendencias or (lambda _uid: [])
        self._trava = threading.RLock()

    def exportar(self, usuario_id: str) -> dict[str, Any]:
        dados: dict[str, Any] = {
            "perfil": self.perfis.get(usuario_id, {}),
            "documentos_enviados": self.documentos.get(usuario_id, []),
            "mensagens": [m for m in self.mensagens if m.get("autor_id") == usuario_id],
        }
        for nome, leitor in self._leitores.items():
            dados[nome] = leitor(usuario_id)
        return dados

    def exclusivo(self, usuario_id: str) -> AbstractContextManager[None]:
        return self._trava  # um processo só: uma exclusão de cada vez

    def pendencias(self, usuario_id: str) -> list[str]:
        return self._pendencias(usuario_id)

    def arquivos_a_remover(self, usuario_id: str) -> list[tuple[str, str]]:
        return list(self.a_remover.get(usuario_id, []))

    def pastas_temporarias(self, usuario_id: str) -> list[tuple[str, str]]:
        return [("verificacao", f"contestacao-medida/{usuario_id}/")]

    def limpeza_concluida(self, usuario_id: str, removidos: int) -> None:
        self.a_remover.pop(usuario_id, None)

    def limpezas_pendentes(self) -> list[str]:
        return list(self.a_remover)

    def anonimizar(self, usuario_id: str) -> dict[str, list[str]]:
        if usuario_id in self.perfis:
            self.perfis[usuario_id] = {"nome": "Usuário anonimizado", "status": "anonimizado"}
        documentos = self.documentos.pop(usuario_id, None) or []
        self.a_remover.setdefault(usuario_id, []).extend(
            ("verificacao", d) for d in documentos if isinstance(d, str)
        )
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
