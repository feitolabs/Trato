"""Interfaces dos repositórios das rotas do app (mensagens, notificações, perfil, verificação,
avaliação, pedidos abertos e taxa). A versão em memória está em `memoria_app.py` e a do
Postgres em `persistencia/app_extras.py` e `persistencia/conversas.py`.
"""

from __future__ import annotations

from collections.abc import Sequence
from dataclasses import dataclass
from datetime import date, datetime
from typing import Protocol

from trato.api.auth import PapelUsuario
from trato.persistencia.conversas import Mensagem, Notificacao

# Tipos de documento que o profissional pode enviar (mesmos da tabela `verificacao_documentos`).
TIPOS_DOCUMENTO = (
    "documento_frente",
    "documento_verso",
    "selfie",
    "antecedentes",
    "comprovante_endereco",
    "registro_profissional",
    "curso_nr10",
    "seguro",
    "outro",
)
NIVEIS_VERIFICACAO = ("verificado", "verificado_plus")


@dataclass(frozen=True)
class OrcamentoDoPedido:
    id: str
    profissional_id: str
    profissional_nome: str | None
    versao: int
    valor_centavos: int
    prazo_execucao_dias: int | None
    garantia_dias: int | None
    observacoes: str | None
    enviado_em: datetime | None


@dataclass(frozen=True)
class PedidoAberto:
    """O que o profissional vê de um pedido que ainda recebe orçamentos (sem endereço exato)."""

    id: str
    titulo: str
    descricao: str
    bairro: str | None
    categoria_id: str | None
    faixa_preco_min_centavos: int | None
    faixa_preco_max_centavos: int | None
    urgente: bool
    prazo_desejado: date | None
    aberto_em: datetime


@dataclass(frozen=True)
class PerfilDetalhe:
    id: str
    nome: str | None
    papel: PapelUsuario
    status: str = "ativo"
    nivel_verificacao: str | None = None
    nota_publica: float | None = None
    servicos_concluidos: int | None = None


@dataclass(frozen=True)
class DocumentoVerificacao:
    tipo: str
    storage_path: str


@dataclass(frozen=True)
class Verificacao:
    id: str
    profissional_id: str
    nivel_solicitado: str
    status: str
    enviada_em: datetime
    documentos: tuple[DocumentoVerificacao, ...] = ()


@dataclass(frozen=True)
class Avaliacao:
    pedido_id: str  # o contrato é um por pedido
    direcao: str  # cliente_para_profissional | profissional_para_cliente
    avaliador_id: str
    avaliado_id: str
    nota_geral: int
    comentario: str | None
    etiquetas: tuple[str, ...]
    criada_em: datetime


class RepositorioConversas(Protocol):
    def abrir(self, pedido_id: str, profissional_id: str) -> str: ...

    def enviar(self, conversa_id: str, autor_id: str, corpo: str) -> int: ...

    def listar(self, conversa_id: str) -> Sequence[Mensagem]: ...


class RepositorioNotificacoes(Protocol):
    def listar(self, usuario_id: str, apenas_nao_lidas: bool = False) -> Sequence[Notificacao]: ...


class RepositorioUsuarios(Protocol):
    def detalhe(self, usuario_id: str) -> PerfilDetalhe | None: ...


class RepositorioVerificacoes(Protocol):
    def enviar(
        self,
        profissional_id: str,
        nivel: str,
        documentos: Sequence[DocumentoVerificacao],
        agora: datetime,
    ) -> Verificacao:
        """Grava a verificação com o consentimento LGPD (só guarda as referências)."""

    def da_pessoa(self, profissional_id: str) -> Sequence[Verificacao]: ...


class RepositorioAvaliacoes(Protocol):
    def obter(self, pedido_id: str, direcao: str) -> Avaliacao | None: ...

    def salvar(self, avaliacao: Avaliacao) -> None: ...


class ProvedorTaxa(Protocol):
    def calcular(self, valor_centavos: int) -> int:
        """Taxa do Trato, em centavos, para o valor. Vem da configuração, nunca do app."""
