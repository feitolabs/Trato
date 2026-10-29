"""Entradas e saídas da API administrativa (pydantic). Dinheiro sempre em centavos inteiros."""

from __future__ import annotations

from datetime import datetime
from enum import StrEnum
from typing import Annotated, Any, Generic, TypeVar

from pydantic import BaseModel, ConfigDict, Field, StringConstraints

# Toda ação sensível pede um motivo escrito (vai para a auditoria).
Motivo = Annotated[str, StringConstraints(strip_whitespace=True, min_length=5, max_length=1000)]


class Entrada(BaseModel):
    model_config = ConfigDict(extra="forbid")


class Saida(BaseModel):
    model_config = ConfigDict(from_attributes=True)


class ComMotivo(Entrada):
    motivo: Motivo


T = TypeVar("T")


class Pagina(BaseModel, Generic[T]):  # noqa: UP046
    itens: list[T]
    total: int
    limite: int
    deslocamento: int


# --- Verificação -----------------------------------------------------------------------------


class DocumentoOut(Saida):
    id: str
    tipo: str
    validade_em: str | None = None
    mascarado: bool = True  # o arquivo só abre pela URL assinada, com motivo, e só para o cadastro


class VerificacaoOut(Saida):
    id: str
    profissional_id: str
    profissional_nome: str
    nivel_solicitado: str
    status: str
    enviada_em: datetime
    decidida_em: datetime | None = None
    motivo_recusa: str | None = None
    cpf_mascarado: str | None = None
    documentos: list[DocumentoOut] = []


class DecisaoVerificacaoIn(Entrada):
    aprovar: bool
    motivo: Motivo


class UrlDocumentoOut(BaseModel):
    url: str
    expira_em_segundos: int


# --- Disputas --------------------------------------------------------------------------------


class ResultadoDisputaIn(StrEnum):
    LIBERAR_TUDO = "liberar_tudo"
    REEMBOLSO_TOTAL = "reembolso_total"
    REEMBOLSO_PARCIAL = "reembolso_parcial"
    NOVA_VISITA = "nova_visita"


class DecidirDisputaIn(Entrada):
    resultado: ResultadoDisputaIn
    justificativa: Motivo
    # Só em reembolso parcial: exatamente um dos dois.
    percentual_cliente_bps: int | None = Field(default=None, ge=1, le=9999)
    valor_cliente_centavos: int | None = Field(default=None, ge=1)


class AprovarDisputaIn(Entrada):
    justificativa: Motivo


class DisputaResumoOut(BaseModel):
    pedido_id: str
    estado: str
    motivo: str
    valor_congelado_centavos: int
    aberta_em: datetime
    resposta_ate: datetime
    decisao_ate: datetime
    atrasada: bool
    sem_resposta: bool


class PessoaOut(BaseModel):
    id: str | None
    nome: str | None = None


class EventoLinhaDoTempoOut(BaseModel):
    em: datetime
    tipo: str  # pedido | disputa
    acao: str
    de: str | None = None
    para: str | None = None
    ator_papel: str | None = None
    ator_id: str | None = None


class EvidenciaOut(BaseModel):
    origem: str  # ação do pedido que gerou a prova
    em: datetime
    ator_papel: str
    ator_id: str | None
    dados: Any  # a prova, sem códigos de check-in/out


class DivisaoOut(BaseModel):
    para_profissional_centavos: int
    para_cliente_centavos: int
    retido_centavos: int


class DisputaDetalheOut(DisputaResumoOut):
    estado_pedido: str | None = None
    cliente: PessoaOut
    profissional: PessoaOut
    respondida_em: datetime | None = None
    decisao: str | None = None
    percentual_cliente_bps: int | None = None
    decidido_por: str | None = None
    decidido_em: datetime | None = None
    aprovado_por: str | None = None
    aprovado_em: datetime | None = None
    aguardando_segunda_pessoa: bool = False
    divisao: DivisaoOut | None = None
    evidencias: list[EvidenciaOut] = []
    linha_do_tempo: list[EventoLinhaDoTempoOut] = []
    lancamentos_da_decisao: list[LancamentoAdminOut] = []


# --- Pagamentos (somente leitura) ------------------------------------------------------------


class ContaAdminOut(BaseModel):
    tipo: str
    titular: str | None = None


class LancamentoAdminOut(BaseModel):
    id: str
    pedido_id: str
    tipo: str
    valor_centavos: int
    data: datetime
    debito: ContaAdminOut
    credito: ContaAdminOut
    estorno_de: str | None = None


class PagamentoOut(BaseModel):
    lancamento_id: str
    pedido_id: str
    valor_centavos: int
    estornado_centavos: int
    status: str  # confirmado | estornado_parcial | estornado
    data: datetime
    referencia_provedor: str | None = None
    divergente: bool = False


class ResumoConciliacaoOut(BaseModel):
    confirmado_centavos: int
    estornado_centavos: int
    retido_centavos: int
    taxa_trato_centavos: int
    divergencias: int
    atualizado_em: datetime


class EventoWebhookOut(BaseModel):
    provedor: str
    evento_id: str
    tipo: str
    recebido_em: datetime
    pedido_id: str | None = None
    referencia: str | None = None
    valor_centavos: int | None = None


class SaldoContratoOut(BaseModel):
    cliente_pagou_centavos: int
    retido_centavos: int
    a_liberar_centavos: int
    liberado_centavos: int
    taxa_trato_centavos: int


class ExtratoContratoOut(BaseModel):
    pedido_id: str
    estado: str | None = None
    valor_contrato_centavos: int | None = None
    saldo: SaldoContratoOut
    lancamentos: list[LancamentoAdminOut]


# --- Usuários e pedidos ----------------------------------------------------------------------


class UsuarioOut(Saida):
    id: str
    nome: str
    status: str
    tipo: str
    criado_em: datetime | None = None
    nivel_verificacao: str | None = None
    status_profissional: str | None = None


class DadosPessoaisOut(Saida):
    cpf: str | None
    telefone: str | None
    data_nascimento: str | None
    telefone_confirmado_em: datetime | None
    email_confirmado_em: datetime | None


class PedidoResumoOut(Saida):
    id: str
    titulo: str
    estado: str
    cliente_id: str
    cliente_nome: str
    profissional_id: str | None
    valor_centavos: int | None
    criado_em: datetime | None


class EventoPedidoOut(BaseModel):
    acao: str
    de: str
    para: str
    ator_papel: str
    ator_id: str | None
    em: datetime


class PedidoDetalheOut(BaseModel):
    id: str
    estado: str
    cliente: PessoaOut
    profissional: PessoaOut
    aberto_em: datetime
    concluido_em: datetime | None = None
    valor_contrato_centavos: int | None = None
    pagamento_confirmado: bool
    tem_disputa: bool
    eventos: list[EventoPedidoOut]


# --- Configuração ----------------------------------------------------------------------------


class DefinicaoOut(Saida):
    chave: str
    descricao: str
    unidade: str
    minimo: int | None = None
    maximo: int | None = None
    escopos_permitidos: list[str]
    exige_dupla_aprovacao: bool


class ParametroIO(Entrada):
    chave: str
    valor: int
    escopo_tipo: str = "global"
    escopo_id: str | None = None
    escopo_texto: str | None = None


class FaixaIO(Entrada):
    de_centavos: int = Field(ge=0)
    ate_centavos: int | None = Field(default=None, ge=1)
    taxa_bps: int = Field(ge=0, le=10_000)
    escopo_tipo: str = "global"
    escopo_id: str | None = None
    escopo_texto: str | None = None


class VersaoConfigOut(BaseModel):
    id: str
    numero: int
    status: str
    motivo: str
    criada_por: str
    aprovada_por: str | None = None
    vigente_desde: datetime | None = None
    revertida_de: str | None = None
    criado_em: datetime | None = None
    parametros: list[ParametroIO] = []
    faixas: list[FaixaIO] = []


class RascunhoIn(Entrada):
    motivo: Motivo
    parametros: list[ParametroIO] = []
    faixas: list[FaixaIO] = []
    # Quando a versão passa a valer (vazio = no momento da aprovação). Agendar é permitido.
    vigente_desde: datetime | None = None
    # True: parte da versão vigente e só troca o que veio no corpo.
    partir_da_vigente: bool = True


# --- Auditoria -------------------------------------------------------------------------------


class EntradaAuditoriaOut(Saida):
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


class CadeiaOut(BaseModel):
    integra: bool
    primeira_falha_id: int | None = None
    verificada_em: datetime


DisputaDetalheOut.model_rebuild()
