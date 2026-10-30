"""Serviço de notificações: evento do domínio -> linhas em `notificacoes` -> canais.

Regras:
- Respeita `notificacao_preferencias` (categoria x canal). Evento `essencial` sempre entra na
  caixa de entrada (`app`); push/e-mail continuam obedecendo a preferência.
- Idempotente: a mesma `chave` para a mesma pessoa e canal não gera outra notificação.
- Canal externo desligado ou sem destino (sem token, sem e-mail) nem cria linha.
- Falha de envio deixa a linha sem `enviada_em`; `reenviar_pendentes()` tenta de novo.
- Deep link em `dados` (tela + pedido_id + link). Nunca vai código nem dado pessoal.
"""

from __future__ import annotations

from collections.abc import Callable
from datetime import UTC, datetime
from typing import Any, Protocol

from trato.notificacoes.canais import Canais, FalhaEnvio, Mensagem, TokenInvalido
from trato.notificacoes.config import ConfigNotificacoes
from trato.notificacoes.eventos import MODELOS, Evento, deep_link
from trato.notificacoes.repositorio import (
    Preferencias,
    Registro,
    RepositorioServicoNotificacoes,
)


class ResolvedorEmail(Protocol):
    def email_de(self, usuario_id: str) -> str | None:
        """E-mail da pessoa para notificar, ou None. Dado pessoal: nunca sai pela API."""


class SemEmail:
    def email_de(self, usuario_id: str) -> str | None:
        return None


class ServicoNotificacoes:
    def __init__(
        self,
        repo: RepositorioServicoNotificacoes,
        canais: Canais,
        config: ConfigNotificacoes,
        agora: Callable[[], datetime] = lambda: datetime.now(UTC),
        emails: ResolvedorEmail | None = None,
    ) -> None:
        self.repo = repo
        self.canais = canais
        self.config = config
        self.agora = agora
        self._emails = emails or SemEmail()

    # --- preferências ----------------------------------------------------------------------

    def _padrao(self, canal: str) -> bool:
        return {
            "app": self.config.padrao_app,
            "push": self.config.padrao_push,
            "email": self.config.padrao_email,
        }.get(canal, False)

    def canal_ligado(self, prefs: Preferencias, categoria: str, canal: str) -> bool:
        escolha = prefs.get(categoria, {}).get(canal)
        return self._padrao(canal) if escolha is None else bool(escolha)

    def preferencias_efetivas(self, usuario_id: str) -> Preferencias:
        """O que vale hoje para a pessoa (padrão da configuração + o que ela mudou)."""
        prefs = self.repo.preferencias(usuario_id)
        categorias = {m.categoria.value for m in MODELOS.values()}
        return {
            c: {k: self.canal_ligado(prefs, c, k) for k in ("app", "push", "email")}
            for c in sorted(categorias)
        }

    # --- criar ----------------------------------------------------------------------------

    def notificar(
        self,
        evento: Evento,
        usuario_id: str,
        *,
        chave: str,
        pedido_id: str | None = None,
        dados: dict[str, Any] | None = None,
    ) -> list[Registro]:
        """Cria (uma vez) a notificação do evento nos canais ligados. Devolve as linhas novas."""
        modelo = MODELOS[evento]
        agora = self.agora()
        prefs = self.repo.preferencias(usuario_id)
        conteudo = {
            "evento": evento.value,
            "tela": modelo.tela,
            "pedido_id": pedido_id,
            "link": deep_link(self.config.deep_link_base, modelo.tela, pedido_id),
            **(dados or {}),
        }
        novas: list[Registro] = []
        for nome in ("app", "push", "email"):
            canal = self.canais.por_nome(nome)
            if canal is None or not canal.disponivel:
                continue
            ligado = (nome == "app" and modelo.essencial) or self.canal_ligado(
                prefs, modelo.categoria.value, nome
            )
            if not ligado or (nome != "app" and not self._destinos(nome, usuario_id)):
                continue
            registro, criada = self.repo.criar(
                usuario_id, evento.value, nome, modelo.titulo, modelo.corpo, conteudo,
                f"{evento.value}:{chave}", agora, nome == "app",
            )  # fmt: skip
            if criada:
                novas.append(registro)
                if nome != "app":
                    self._entregar(registro)
        return novas

    # --- entrega e reenvio ----------------------------------------------------------------

    def _destinos(self, canal: str, usuario_id: str) -> tuple[str, ...]:
        if canal == "push":
            return tuple(self.repo.tokens(usuario_id))
        if canal == "email":
            endereco = self._emails.email_de(usuario_id)
            return (endereco,) if endereco else ()
        return ()

    def _entregar(self, registro: Registro) -> bool:
        canal = self.canais.por_nome(registro.canal)
        if canal is None or not canal.disponivel:
            return False
        destinos = self._destinos(registro.canal, registro.usuario_id)
        if not destinos:
            self.repo.marcar_enviada(registro.id, self.agora())  # ninguém para receber
            return True
        mensagem = Mensagem(
            registro.usuario_id, registro.titulo, registro.corpo, registro.dados, destinos
        )
        try:
            canal.enviar(mensagem)
        except TokenInvalido as erro:
            self.repo.desativar_dispositivo(erro.token)
            return False  # os outros aparelhos entram no próximo reenvio
        except FalhaEnvio:
            return False
        self.repo.marcar_enviada(registro.id, self.agora())
        return True

    def reenviar_pendentes(self) -> int:
        """Tenta de novo o que falhou (só as recentes, pela janela da configuração)."""
        desde = self.agora() - self.config.reenvio_janela
        enviadas = 0
        for registro in self.repo.pendentes(desde, self.config.reenvio_lote):
            enviadas += self._entregar(registro)
        return enviadas
