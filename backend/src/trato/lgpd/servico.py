"""Regras de LGPD: exportar, pedir/confirmar/cancelar exclusão, registrar consentimento.

Toda ação grava na auditoria com motivo (as ações `dado_pessoal.*` exigem motivo no banco). O
ledger e a auditoria são imutáveis: este serviço nunca os altera, só anonimiza o que a lei deixa.
"""

from __future__ import annotations

import hashlib
import hmac
import logging
import secrets
from collections.abc import Callable
from dataclasses import replace
from datetime import UTC, datetime, timedelta
from typing import Any

from trato import legal
from trato.api.auth import Usuario
from trato.api.cautela import PRESERVACAO
from trato.api.moedas import (
    saldo_total_disponivel,
    zerar_tratinhos_encerramento_voluntario,
)
from trato.financeiro import periodo
from trato.lgpd.config import ConfigLgpd
from trato.lgpd.repositorios import Consentimento, PedidoExclusao, RepositoriosLgpd
from trato.persistencia.erros import ErroPersistencia, RegistrosPreservados
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


class PedidoEncerrado(ErroLgpd):
    def __init__(self) -> None:
        super().__init__(
            409, "Este pedido de exclusão já foi encerrado e não muda mais. Confira a situação."
        )


log = logging.getLogger("trato.lgpd")


def _hash_token(token: str) -> str:
    return hashlib.sha256(token.encode()).hexdigest()


class ServicoLgpd:
    def __init__(
        self,
        config: ConfigLgpd,
        repos: RepositoriosLgpd,
        seg: Seguranca,
        armazenamento: Any = None,
        moedas: Any = None,
        tratinhos_guardados_ate: Callable[[str, datetime], datetime | None] | None = None,
        preservado: Callable[[str], bool] | None = None,
    ) -> None:
        self._cfg = config
        self._r = repos
        self._seg = seg
        self._arquivos = armazenamento  # porta de armazenamento; None = remoção fica pendente
        self._moedas = moedas  # livro de Tratinhos; None = degrada para 0 em testes mínimos
        self._guardados = tratinhos_guardados_ate or (lambda _usuario, _agora: None)
        self._preservado = preservado or (lambda _usuario: False)

    def _pendencias(self, usuario_id: str) -> list[str]:
        """O que impede excluir agora, inclusive a preservação de registros (9.6)."""
        achadas = list(self._r.fonte.pendencias(usuario_id))
        if self._preservado(usuario_id):
            achadas.append(PRESERVACAO)
        return achadas

    def _apagar_arquivos(self, usuario_id: str) -> bool:
        """Apaga documentos anonimizados e envios temporários. Falhou: fica pendente e a próxima
        rodada repete. Prova de contestação NÃO sai aqui (guarda ainda sem prazo decidido)."""
        if self._arquivos is None or self._preservado(usuario_id):
            return False  # preservação (9.6): os arquivos ficam até o incidente encerrar
        try:
            alvos = list(self._r.fonte.arquivos_a_remover(usuario_id))
            for bucket, pasta in self._r.fonte.pastas_temporarias(usuario_id):
                alvos += [(bucket, c) for c in self._arquivos.listar(bucket, pasta)]
            falhas = 0
            for bucket, caminho in alvos:
                try:
                    self._arquivos.remover(bucket, caminho)
                except Exception:  # noqa: BLE001 - um arquivo não impede os outros
                    log.exception("Não consegui apagar um arquivo da conta anonimizada")
                    falhas += 1
            if falhas:
                return False
            self._r.fonte.limpeza_concluida(usuario_id, len(alvos))
        except Exception:  # noqa: BLE001 - a conta já foi anonimizada; repete depois
            log.exception("Limpeza de arquivos da conta anonimizada falhou")
            return False
        return True

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

    def _tratinhos(self, usuario_id: str, agora: datetime) -> dict[str, Any]:
        """O que a pessoa perde ao excluir a conta, ou até quando fica guardado (13.10)."""
        ate = self._guardados(usuario_id, agora)
        if ate is None:
            return {"tratinhos_a_perder": self._tratinhos_a_perder(usuario_id, agora)}
        return {"tratinhos_a_perder": 0, "tratinhos_guardados_ate": ate.isoformat()}

    def _tratinhos_a_perder(self, usuario_id: str, agora: datetime) -> int:
        return saldo_total_disponivel(self._moedas, usuario_id, agora)

    def _zerar_tratinhos(self, usuario_id: str, pedido_id: str, agora: datetime) -> int:
        return zerar_tratinhos_encerramento_voluntario(self._moedas, usuario_id, pedido_id, agora)

    def situacao_exclusao(self, usuario: Usuario, agora: datetime | None = None) -> dict[str, Any]:
        ativo = self._r.exclusoes.ativo_do_usuario(usuario.id)
        instante = agora or datetime.now(UTC)
        return {
            "pedido": self._resumo_pedido(ativo) if ativo else None,
            **self._tratinhos(usuario.id, instante),
        }

    def _gravar(self, pedido: PedidoExclusao) -> None:
        if not self._r.exclusoes.salvar(pedido):
            raise PedidoEncerrado

    def exclusao_agendada_em(self, usuario_id: str) -> datetime | None:
        ativo = self._r.exclusoes.ativo_do_usuario(usuario_id)
        if ativo is not None and ativo.status == "agendada":
            return ativo.executar_apos
        return None

    def pedir_exclusao(self, usuario: Usuario, agora: datetime) -> dict[str, Any]:
        """Passo 1: mostra o que será apagado e mantido e devolve o código de confirmação."""
        pendencias = self._pendencias(usuario.id)
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
        self._gravar(pedido)
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
            **self._tratinhos(usuario.id, agora),
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
        pendencias = self._pendencias(usuario.id)
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
        self._gravar(agendado)
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
        self._gravar(replace(pedido, status="cancelada", token_hash=None))
        self._motivo(
            usuario,
            "dado_pessoal.exclusao_cancelada",
            "Titular desistiu da exclusão durante a carência",
            pedido=pedido.id,
        )

    def _excluir_sem_pendencia(
        self, pedido: PedidoExclusao, agora: datetime
    ) -> tuple[list[str], dict[str, Any]] | None:
        """Checa e anonimiza na mesma transação, com a pessoa travada. Devolve as pendências
        (nada gravado) ou o resumo do que foi feito; `None` se o pedido já não vale."""
        with self._r.fonte.exclusivo(pedido.usuario_id):
            atual = self._r.exclusoes.ativo_do_usuario(pedido.usuario_id)
            if atual is None or atual.id != pedido.id or atual.status != "agendada":
                return None
            pendencias = self._pendencias(pedido.usuario_id)
            if pendencias:
                return pendencias, {}
            guardados = self._guardados(pedido.usuario_id, agora)
            tratinhos_zerados = (
                0 if guardados else self._zerar_tratinhos(pedido.usuario_id, pedido.id, agora)
            )
            resumo = dict(self._r.fonte.anonimizar(pedido.usuario_id))
            resumo["tratinhos_zerados"] = tratinhos_zerados
            if guardados:
                resumo["tratinhos_guardados_ate"] = guardados.isoformat()
            # Se o pedido deixou de valer, o erro desfaz a anonimização desta transação.
            self._gravar(replace(atual, status="concluida", concluido_em=agora, resumo=resumo))
        return [], resumo

    def processar_vencidas(self, agora: datetime) -> dict[str, int]:
        """Rotina (equipe/sistema): anonimiza quem passou da carência e não tem pendência."""
        feitas = adiadas = 0
        for pedido in self._r.exclusoes.agendadas_ate(agora):
            try:
                resultado = self._excluir_sem_pendencia(pedido, agora)
            except RegistrosPreservados:  # 9.6: o banco recusou e tudo voltou atrás
                resultado = [PRESERVACAO], {}
            except (ErroPersistencia, PedidoEncerrado):  # trava ocupada: nada foi gravado
                log.warning("Exclusão %s ficou para a próxima rodada", pedido.id, exc_info=True)
                adiadas += 1
                continue
            if resultado is None:
                continue  # outra rodada concluiu, ou a pessoa cancelou
            pendencias, resumo = resultado
            if pendencias:
                adiadas += 1
                self._seg.auditar(
                    "dado_pessoal.exclusao_adiada",
                    ator_tipo="sistema",
                    motivo="Pendências impedem a anonimização: " + "; ".join(pendencias),
                    depois={"pedido": pedido.id},
                )
                continue
            self._seg.auditar(
                "dado_pessoal.anonimizacao",
                ator_tipo="sistema",
                entidade="usuarios",
                entidade_id=pedido.usuario_id,
                motivo="Exclusão pedida pelo titular, carência cumprida (LGPD, art. 18, VI)",
                depois=resumo,
            )
            feitas += 1
        pendentes = sum(not self._apagar_arquivos(u) for u in self._r.fonte.limpezas_pendentes())
        saida = {"anonimizadas": feitas, "adiadas": adiadas}
        if pendentes:
            saida["arquivos_pendentes"] = pendentes
        return saida

    # --- Consentimentos ---------------------------------------------------------------
    ALIAS_FINALIDADES: dict[str, str] = {
        "avisos": "comunicacoes_marketing",
        "localizacao": "localizacao_no_servico",
        "dados_pedido": "termos_de_uso",
    }

    def registrar_consentimento(
        self,
        usuario: Usuario,
        finalidade: str,
        aceito: bool,
        versao_texto: str,
        agora: datetime,
        ip: str | None,
    ) -> Consentimento:
        finalidade_efetiva = self.ALIAS_FINALIDADES.get(finalidade, finalidade)
        regra = self._cfg.finalidades.get(finalidade_efetiva)
        if regra is None:
            raise ErroLgpd(422, "Finalidade desconhecida.")
        if regra.obrigatoria and not aceito:
            raise ErroLgpd(
                422,
                "Esse aceite é necessário para usar o Trato. Para sair, peça a exclusão da conta.",
            )
        linha = Consentimento(usuario.id, finalidade_efetiva, aceito, versao_texto, agora, ip)
        self._r.consentimentos.registrar(linha)
        self._motivo(
            usuario,
            "consentimento.registrado" if aceito else "consentimento.revogado",
            "Escolha do titular sobre o tratamento de dados",
            finalidade=finalidade_efetiva,
            versao_texto=versao_texto,
        )
        return linha

    # --- Aceite dos Termos (1.4, 1.7 e 23.4) ------------------------------------------
    def aceite_dos_termos(
        self, usuario_id: str, vigente: legal.VersaoDosTermos
    ) -> Consentimento | None:
        """Primeiro aceite da versão vigente. Linha anterior à vigência não vale."""
        return next(
            (c for c in self._aceites(usuario_id) if c.versao_texto == vigente.versao), None
        )

    def ultimo_aceite_dos_termos(self, usuario_id: str) -> Consentimento | None:
        aceites = self._aceites(usuario_id)
        return aceites[-1] if aceites else None

    def _aceites(self, usuario_id: str) -> list[Consentimento]:
        """Aceites de versões publicadas, registrados já com a versão em vigor. A rota genérica
        de consentimentos aceita qualquer texto de versão: o que não confere é ignorado."""
        vigencia = {v.versao: v.vigente_desde for v in legal.VERSOES}
        return [
            c
            for c in self._r.consentimentos.historico(usuario_id)
            if c.finalidade == "termos_de_uso"
            and c.aceito
            and c.versao_texto in vigencia
            and c.registrado_em.astimezone(periodo.BRASILIA).date() >= vigencia[c.versao_texto]
        ]

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
