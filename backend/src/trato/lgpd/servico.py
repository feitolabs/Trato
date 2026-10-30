"""Regras de LGPD: exportar, pedir/confirmar/cancelar exclusão, registrar consentimento.

Toda ação grava na auditoria com motivo (as ações `dado_pessoal.*` exigem motivo no banco). O
ledger e a auditoria são imutáveis: este serviço nunca os altera, só anonimiza o que a lei deixa.
"""

from __future__ import annotations

import hashlib
import hmac
import secrets
from dataclasses import replace
from datetime import datetime, timedelta
from typing import Any

from trato.api.auth import Usuario
from trato.lgpd.config import ConfigLgpd
from trato.lgpd.repositorios import Consentimento, PedidoExclusao, RepositoriosLgpd
from trato.seguranca.estado import Seguranca

FORMATO_EXPORTACAO = "trato-lgpd-1"
# Texto de cada categoria mantida por obrigação legal; o PRAZO vem da configuração.
CATEGORIAS_MANTIDAS = {
    "ledger_financeiro": "Registros financeiros (obrigação fiscal e contábil).",
    "auditoria": "Trilha de auditoria (segurança e prevenção a fraude).",
    "contratos_e_pedidos": "Contratos e pedidos concluídos (defesa em disputa ou processo).",
    "mensagens_e_disputas": "Mensagens e disputas dos serviços (evidência), sem seu nome.",
    "logs_acesso": "Registros de acesso (Marco Civil da Internet).",
}


class ErroLgpd(Exception):
    def __init__(self, status: int, mensagem: str) -> None:
        super().__init__(mensagem)
        self.status = status


def _hash_token(token: str) -> str:
    return hashlib.sha256(token.encode()).hexdigest()


class ServicoLgpd:
    def __init__(self, config: ConfigLgpd, repos: RepositoriosLgpd, seg: Seguranca) -> None:
        self._cfg = config
        self._r = repos
        self._seg = seg

    def _motivo(self, usuario: Usuario, acao: str, motivo: str, **depois: Any) -> None:
        self._seg.auditar(
            acao,
            ator_id=usuario.id,
            ator_tipo=usuario.papel.value,
            entidade="usuarios",
            entidade_id=usuario.id,
            motivo=motivo,
            depois=depois or None,
        )

    # --- Exportar -------------------------------------------------------------------
    def exportar(self, usuario: Usuario, agora: datetime) -> dict[str, Any]:
        consentimentos = [
            {
                "finalidade": c.finalidade,
                "aceito": c.aceito,
                "versao_texto": c.versao_texto,
                "registrado_em": c.registrado_em.isoformat(),
            }
            for c in self._r.consentimentos.historico(usuario.id)
        ]
        ativo = self._r.exclusoes.ativo_do_usuario(usuario.id)
        dados = self._r.fonte.exportar(usuario.id)
        self._motivo(
            usuario,
            "dado_pessoal.exportacao",
            "Pedido do titular (LGPD, art. 18, II e V)",
            categorias=sorted(dados),
        )
        return {
            "formato": FORMATO_EXPORTACAO,
            "gerado_em": agora.isoformat(),
            "titular_id": usuario.id,
            "dados": dados,
            "consentimentos": consentimentos,
            "exclusao": self._resumo_pedido(ativo) if ativo else None,
            "retencao_por_lei": self._retencao(),
        }

    # --- Exclusão -------------------------------------------------------------------
    def _retencao(self) -> list[dict[str, Any]]:
        return [
            {"categoria": c, "motivo": texto, "prazo_dias": self._cfg.retencao_dias.get(c)}
            for c, texto in CATEGORIAS_MANTIDAS.items()
        ]

    def _resumo_pedido(self, pedido: PedidoExclusao) -> dict[str, Any]:
        return {
            "id": pedido.id,
            "status": pedido.status,
            "executar_apos": pedido.executar_apos.isoformat() if pedido.executar_apos else None,
            "token_expira_em": (
                pedido.token_expira_em.isoformat() if pedido.token_expira_em else None
            ),
        }

    def situacao_exclusao(self, usuario: Usuario) -> dict[str, Any]:
        ativo = self._r.exclusoes.ativo_do_usuario(usuario.id)
        return {"pedido": self._resumo_pedido(ativo) if ativo else None}

    def pedir_exclusao(self, usuario: Usuario, agora: datetime) -> dict[str, Any]:
        """Passo 1: mostra o que será apagado e mantido e devolve o código de confirmação."""
        pendencias = self._r.fonte.pendencias(usuario.id)
        ativo = self._r.exclusoes.ativo_do_usuario(usuario.id)
        if ativo and ativo.status == "agendada":
            raise ErroLgpd(409, "Sua exclusão já está agendada. Você pode cancelá-la.")
        token = secrets.token_urlsafe(24)
        pedido = PedidoExclusao(
            id=ativo.id if ativo else self._r.exclusoes.novo_id(),
            usuario_id=usuario.id,
            status="aguardando_confirmacao",
            criado_em=agora,
            token_hash=_hash_token(token),
            token_expira_em=agora + timedelta(minutes=self._cfg.confirmacao_validade_min),
        )
        self._r.exclusoes.salvar(pedido)
        self._motivo(
            usuario,
            "dado_pessoal.exclusao_solicitada",
            "Pedido de exclusão do titular (LGPD, art. 18, VI), aguardando confirmação",
            pedido=pedido.id,
        )
        return {
            "status": pedido.status,
            "token_confirmacao": token,
            "token_expira_em": pedido.token_expira_em.isoformat(),  # type: ignore[union-attr]
            "carencia_dias": self._cfg.carencia_exclusao_dias,
            "pendencias": pendencias,
            "sera_anonimizado": ["perfil", "contato", "documentos_verificacao"],
            "sera_mantido": self._retencao(),
        }

    def confirmar_exclusao(self, usuario: Usuario, token: str, agora: datetime) -> dict[str, Any]:
        """Passo 2: com o código do passo 1, agenda a anonimização após a carência."""
        pedido = self._r.exclusoes.ativo_do_usuario(usuario.id)
        if pedido is None or pedido.status != "aguardando_confirmacao":
            raise ErroLgpd(409, "Não há pedido de exclusão aguardando confirmação.")
        if pedido.token_expira_em is None or agora > pedido.token_expira_em:
            self._r.exclusoes.salvar(replace(pedido, status="expirada", token_hash=None))
            raise ErroLgpd(410, "O código de confirmação expirou. Peça a exclusão de novo.")
        if not hmac.compare_digest(_hash_token(token), pedido.token_hash or ""):
            raise ErroLgpd(403, "Código de confirmação inválido.")
        pendencias = self._r.fonte.pendencias(usuario.id)
        if pendencias:
            raise ErroLgpd(
                409, "Há pendências que impedem encerrar agora: " + "; ".join(pendencias)
            )
        agendado = replace(
            pedido,
            status="agendada",
            token_hash=None,
            executar_apos=agora + timedelta(days=self._cfg.carencia_exclusao_dias),
        )
        self._r.exclusoes.salvar(agendado)
        self._motivo(
            usuario,
            "dado_pessoal.exclusao_agendada",
            "Titular confirmou a exclusão (LGPD, art. 18, VI)",
            pedido=agendado.id,
            executar_apos=agendado.executar_apos.isoformat(),  # type: ignore[union-attr]
        )
        return {"status": "agendada", "executar_apos": agendado.executar_apos.isoformat()}  # type: ignore[union-attr]

    def cancelar_exclusao(self, usuario: Usuario) -> None:
        pedido = self._r.exclusoes.ativo_do_usuario(usuario.id)
        if pedido is None:
            raise ErroLgpd(404, "Não há pedido de exclusão para cancelar.")
        self._r.exclusoes.salvar(replace(pedido, status="cancelada", token_hash=None))
        self._motivo(
            usuario,
            "dado_pessoal.exclusao_cancelada",
            "Titular desistiu da exclusão durante a carência",
            pedido=pedido.id,
        )

    def processar_vencidas(self, agora: datetime) -> dict[str, int]:
        """Rotina (equipe/sistema): anonimiza quem passou da carência e não tem pendência."""
        feitas = adiadas = 0
        for pedido in self._r.exclusoes.agendadas_ate(agora):
            pendencias = self._r.fonte.pendencias(pedido.usuario_id)
            if pendencias:
                adiadas += 1
                self._seg.auditar(
                    "dado_pessoal.exclusao_adiada",
                    ator_tipo="sistema",
                    motivo="Pendências impedem a anonimização: " + "; ".join(pendencias),
                    depois={"pedido": pedido.id},
                )
                continue
            resumo = self._r.fonte.anonimizar(pedido.usuario_id)
            self._r.exclusoes.salvar(
                replace(pedido, status="concluida", concluido_em=agora, resumo=resumo)
            )
            self._seg.auditar(
                "dado_pessoal.anonimizacao",
                ator_tipo="sistema",
                entidade="usuarios",
                entidade_id=pedido.usuario_id,
                motivo="Exclusão pedida pelo titular, carência cumprida (LGPD, art. 18, VI)",
                depois=resumo,
            )
            feitas += 1
        return {"anonimizadas": feitas, "adiadas": adiadas}

    # --- Consentimentos ---------------------------------------------------------------
    def registrar_consentimento(
        self,
        usuario: Usuario,
        finalidade: str,
        aceito: bool,
        versao_texto: str,
        agora: datetime,
        ip: str | None,
    ) -> Consentimento:
        regra = self._cfg.finalidades.get(finalidade)
        if regra is None:
            raise ErroLgpd(422, "Finalidade desconhecida.")
        if regra.obrigatoria and not aceito:
            raise ErroLgpd(
                422,
                "Esse aceite é necessário para usar o Trato. Para sair, peça a exclusão da conta.",
            )
        linha = Consentimento(usuario.id, finalidade, aceito, versao_texto, agora, ip)
        self._r.consentimentos.registrar(linha)
        self._motivo(
            usuario,
            "consentimento.registrado" if aceito else "consentimento.revogado",
            "Escolha do titular sobre o tratamento de dados",
            finalidade=finalidade,
            versao_texto=versao_texto,
        )
        return linha

    def consentimentos(self, usuario: Usuario) -> dict[str, Any]:
        historico = list(self._r.consentimentos.historico(usuario.id))
        vigentes: dict[str, Consentimento] = {}
        for linha in historico:  # a última linha de cada finalidade vale
            vigentes[linha.finalidade] = linha
        return {
            "vigentes": {
                f: {"aceito": c.aceito, "versao_texto": c.versao_texto, "em": c.registrado_em}
                for f, c in vigentes.items()
            },
            "historico": [
                {
                    "finalidade": c.finalidade,
                    "aceito": c.aceito,
                    "versao_texto": c.versao_texto,
                    "em": c.registrado_em,
                }
                for c in historico
            ],
        }
