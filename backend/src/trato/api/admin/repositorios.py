"""Interfaces (Protocol) e dados da API administrativa. Dinheiro em centavos inteiros."""

from __future__ import annotations

from collections.abc import Sequence
from dataclasses import dataclass, field
from datetime import datetime
from typing import Any, Protocol

from trato.api.admin.papeis import PapelEquipe


@dataclass(frozen=True)
class MembroEquipe:
    usuario_id: str
    papel: PapelEquipe
    ativo: bool = True
    revogado_em: datetime | None = None
    alcada_centavos: int | None = None

    @property
    def vigente(self) -> bool:
        return self.ativo and self.revogado_em is None


class RepositorioEquipe(Protocol):
    def obter(self, usuario_id: str) -> MembroEquipe | None: ...


# --- Auditoria ---------------------------------------------------------------------------


@dataclass(frozen=True)
class FiltroAuditoria:
    acao: str | None = None  # prefixo: "config." pega config.publicada, config.aprovada...
    ator_id: str | None = None
    entidade: str | None = None
    entidade_id: str | None = None
    desde: datetime | None = None
    ate: datetime | None = None
    # Parte do nome de quem agiu (a tela filtra por "Quem" sem pedir o id).
    ator_busca: str | None = None


@dataclass(frozen=True)
class EntradaAuditoria:
    id: int
    ocorrida_em: datetime
    ator_id: str | None
    ator_tipo: str
    acao: str
    entidade: str | None
    entidade_id: str | None
    motivo: str | None
    antes: Any = None
    depois: Any = None
    # Nomes legíveis (RF-AUD-02): a tela mostra "Emanuel Cabral aprovou…", não códigos e UUIDs.
    ator_nome: str | None = None
    entidade_nome: str | None = None


class RepositorioAuditoriaAdmin(Protocol):
    def registrar(
        self,
        *,
        ator_id: str,
        acao: str,
        entidade: str | None = None,
        entidade_id: str | None = None,
        antes: Any = None,
        depois: Any = None,
        motivo: str | None = None,
    ) -> int: ...

    def listar(
        self, filtro: FiltroAuditoria, limite: int, deslocamento: int
    ) -> tuple[Sequence[EntradaAuditoria], int]: ...

    def verificar_cadeia(self) -> int | None:
        """None = íntegra; senão o id da primeira linha adulterada ou removida."""


# --- Verificação de profissionais ----------------------------------------------------------


@dataclass(frozen=True)
class DocumentoAdmin:
    id: str
    tipo: str
    validade_em: str | None = None


@dataclass(frozen=True)
class EnvioAnteriorAdmin:
    """Um envio anterior do mesmo profissional (RF-VER-02: histórico de envios)."""

    enviado_em: datetime
    status: str
    motivo: str | None = None


@dataclass(frozen=True)
class VerificacaoAdmin:
    id: str
    profissional_id: str
    profissional_nome: str
    nivel_solicitado: str
    status: str
    enviada_em: datetime
    decidida_em: datetime | None = None
    motivo_recusa: str | None = None
    cpf_mascarado: str | None = None
    documentos: tuple[DocumentoAdmin, ...] = ()
    # Separa o NÍVEL de verificação das CATEGORIAS de serviço que o profissional pediu (seção 9).
    publico_id: str = ""
    categorias: tuple[str, ...] = ()
    cidade: str | None = None
    envios_anteriores: tuple[EnvioAnteriorAdmin, ...] = ()


class RepositorioVerificacoesAdmin(Protocol):
    def listar(
        self, status: Sequence[str], limite: int, deslocamento: int
    ) -> tuple[Sequence[VerificacaoAdmin], int]: ...

    def obter(self, verificacao_id: str) -> VerificacaoAdmin | None: ...

    def caminho_do_documento(self, verificacao_id: str, documento_id: str) -> str | None:
        """O caminho no storage (nunca sai da API). Só para gerar a URL assinada."""

    def decidir(self, verificacao_id: str, analista_id: str, aprovar: bool, motivo: str) -> None:
        """Aprova ou recusa. Grava a decisão, atualiza o perfil e a auditoria na MESMA operação."""


class AssinadorUrl(Protocol):
    def assinar(self, caminho: str, segundos: int) -> str:
        """URL assinada de curta duração para um arquivo do bucket privado."""


# --- Usuários e pedidos ----------------------------------------------------------------------


@dataclass(frozen=True)
class UsuarioAdmin:
    id: str
    nome: str
    status: str
    tipo: str  # cliente | profissional | equipe
    criado_em: datetime | None = None
    nivel_verificacao: str | None = None
    status_profissional: str | None = None


@dataclass(frozen=True)
class ComplementoUsuarioAdmin:
    """O que a lista de usuários mostra além do nome: contato mascarado, cidade e o ID curto."""

    publico_id: str = ""
    email_mascarado: str | None = None
    telefone_mascarado: str | None = None
    cidade: str | None = None


@dataclass(frozen=True)
class CategoriaDoProfissional:
    categoria_id: str
    nome: str
    ativa_no_perfil: bool
    ativa_na_plataforma: bool


@dataclass(frozen=True)
class EventoUsuarioAdmin:
    em: datetime
    texto: str


@dataclass(frozen=True)
class ItemDiagnostico:
    ok: bool
    titulo: str
    detalhe: str


@dataclass(frozen=True)
class DiagnosticoAdmin:
    """Por que um pedido aparece (ou não) para um profissional (RN-01, RF-BUS-03)."""

    pedido_id: str
    pedido_numero: int | None
    pedido_titulo: str
    categoria: str
    aparece: bool
    itens: tuple[ItemDiagnostico, ...]


@dataclass(frozen=True)
class DadosPessoaisAdmin:
    cpf: str | None
    telefone: str | None
    data_nascimento: str | None
    telefone_confirmado_em: datetime | None
    email_confirmado_em: datetime | None


@dataclass(frozen=True)
class PedidoResumoAdmin:
    id: str
    titulo: str
    estado: str
    cliente_id: str
    cliente_nome: str
    profissional_id: str | None
    valor_centavos: int | None
    criado_em: datetime | None
    # Para a lista mostrar "PED-10482 · Pintura · Belo Horizonte" em vez de só o UUID (RF-BUS-04).
    numero: int | None = None
    categoria: str | None = None
    cidade: str | None = None
    profissional_nome: str | None = None


class RepositorioUsuariosAdmin(Protocol):
    def buscar(
        self, termo: str | None, status: str | None, limite: int, deslocamento: int
    ) -> tuple[Sequence[UsuarioAdmin], int]: ...

    def obter(self, usuario_id: str) -> UsuarioAdmin | None: ...

    def nomes(self, ids: Sequence[str]) -> dict[str, str]: ...

    def complementos(self, usuarios: Sequence[UsuarioAdmin]) -> dict[str, ComplementoUsuarioAdmin]:
        """Contato MASCARADO, cidade e ID curto de vários usuários de uma vez."""

    def categorias(self, usuario_id: str) -> Sequence[CategoriaDoProfissional]:
        """Categorias cadastradas no perfil do profissional, ativas ou não."""

    def historico(self, usuario_id: str, limite: int) -> Sequence[EventoUsuarioAdmin]: ...

    def diagnosticar(self, usuario_id: str, pedido: str) -> DiagnosticoAdmin | None:
        """Aplica a regra RN-01 e explica cada causa. Nulo = pedido não encontrado."""

    def dados_pessoais(
        self, usuario_id: str, ator_id: str, motivo: str
    ) -> DadosPessoaisAdmin | None:
        """Lê os dados pessoais e grava a auditoria `dado_pessoal.revelado` na MESMA operação."""


class RepositorioPedidosAdmin(Protocol):
    def buscar(
        self,
        termo: str | None,
        estado: str | None,
        cliente_id: str | None,
        profissional_id: str | None,
        limite: int,
        deslocamento: int,
    ) -> tuple[Sequence[PedidoResumoAdmin], int]: ...

    def rotulos(self, pedido_ids: Sequence[str]) -> dict[str, tuple[int | None, str]]:
        """(número curto, título) dos pedidos, para as telas que só têm o id."""

    def dados_de_pagamento(self, pedido_ids: Sequence[str]) -> dict[str, tuple[str | None, bool]]:
        """(referência do pagamento no provedor, tem contrato) de vários pedidos numa ida só.

        Serve à conciliação: a tela de pagamentos não pode fazer uma consulta por pedido.
        Pedido que não existe fica de fora do dicionário."""


# --- Configuração versionada -------------------------------------------------------------------


@dataclass(frozen=True)
class DefinicaoConfig:
    chave: str
    descricao: str
    unidade: str
    minimo: int | None = None
    maximo: int | None = None
    escopos_permitidos: tuple[str, ...] = ("global",)
    exige_dupla_aprovacao: bool = False


@dataclass(frozen=True)
class ParametroConfig:
    chave: str
    valor: int
    escopo_tipo: str = "global"
    escopo_id: str | None = None
    escopo_texto: str | None = None


@dataclass(frozen=True)
class FaixaTaxa:
    de_centavos: int
    ate_centavos: int | None
    taxa_bps: int
    escopo_tipo: str = "global"
    escopo_id: str | None = None
    escopo_texto: str | None = None


@dataclass(frozen=True)
class VersaoConfig:
    id: str
    numero: int
    status: str
    motivo: str
    criada_por: str
    aprovada_por: str | None = None
    vigente_desde: datetime | None = None
    revertida_de: str | None = None
    criado_em: datetime | None = None
    parametros: tuple[ParametroConfig, ...] = field(default=())
    faixas: tuple[FaixaTaxa, ...] = field(default=())


class RepositorioConfigAdmin(Protocol):
    """Todas as mudanças de estado gravam a auditoria na MESMA operação (`config.*`)."""

    def definicoes(self) -> Sequence[DefinicaoConfig]: ...

    def versoes(self) -> Sequence[VersaoConfig]:
        """Sem parâmetros nem faixas (use `versao`). A mais nova primeiro."""

    def versao(self, versao_id: str) -> VersaoConfig | None: ...

    def vigente(self) -> VersaoConfig | None: ...

    def criar_rascunho(
        self,
        autor_id: str,
        motivo: str,
        parametros: Sequence[ParametroConfig],
        faixas: Sequence[FaixaTaxa],
        vigente_desde: datetime | None,
        partir_da_vigente: bool,
    ) -> VersaoConfig: ...

    def enviar_para_aprovacao(self, versao_id: str, autor_id: str, motivo: str) -> VersaoConfig: ...

    def aprovar(self, versao_id: str, aprovador_id: str, motivo: str) -> VersaoConfig: ...

    def publicar(
        self, versao_id: str, autor_id: str, motivo: str, agora: datetime
    ) -> VersaoConfig: ...

    def reverter(self, versao_alvo_id: str, autor_id: str, motivo: str) -> VersaoConfig:
        """Cria NOVA versão (aguardando aprovação) copiando a alvo. Histórico não é editado."""

    def descartar_rascunho(self, versao_id: str, autor_id: str, motivo: str) -> None: ...
