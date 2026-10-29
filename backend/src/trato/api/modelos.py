"""Corpos de entrada e saída da API. Dinheiro sempre em centavos inteiros."""

from __future__ import annotations

from datetime import date, datetime
from typing import Any

from pydantic import AwareDatetime, BaseModel, ConfigDict, Field

from trato.api.repositorios import DadosPedido, EnderecoPedido, RespostaPedido
from trato.pedidos.estados import (
    Foto,
    Janela,
    Localizacao,
    MotivoDisputa,
    ProvaAceite,
    ProvaAgenda,
    ProvaCancelamento,
    ProvaCheckIn,
    ProvaCheckOut,
)


class _Entrada(BaseModel):
    model_config = ConfigDict(extra="forbid")


# --- Provas (entrada) -----------------------------------------------------------------


class FotoIn(_Entrada):
    arquivo_id: str
    tirada_em: AwareDatetime

    def para_regra(self) -> Foto:
        return Foto(self.arquivo_id, self.tirada_em)


class LocalizacaoIn(_Entrada):
    latitude: float
    longitude: float


class JanelaIn(_Entrada):
    inicio: AwareDatetime
    fim: AwareDatetime


class RespostaIn(_Entrada):
    pergunta_id: str
    resposta: Any


class EnderecoIn(_Entrada):
    logradouro: str = Field(min_length=1)
    numero: str | None = None
    complemento: str | None = None
    bairro: str | None = None
    cep: str | None = None
    referencia: str | None = None
    lat: float | None = Field(default=None, ge=-90, le=90)
    lng: float | None = Field(default=None, ge=-180, le=180)


class AbrirPedidoIn(_Entrada):
    """O que o cliente descreve. Com repositório em memória o corpo é opcional."""

    categoria_id: str
    cidade_id: str
    titulo: str = Field(min_length=1)
    descricao: str = Field(min_length=1)
    bairro: str | None = None
    local_aprox_lat: float | None = Field(default=None, ge=-90, le=90)
    local_aprox_lng: float | None = Field(default=None, ge=-180, le=180)
    prazo_desejado: date | None = None
    faixa_preco_min_centavos: int | None = Field(default=None, ge=0)
    faixa_preco_max_centavos: int | None = Field(default=None, ge=0)
    urgente: bool = False
    respostas: list[RespostaIn] = Field(default_factory=list)
    endereco: EnderecoIn | None = None

    def para_dados(self) -> DadosPedido:
        return DadosPedido(
            categoria_id=self.categoria_id,
            cidade_id=self.cidade_id,
            titulo=self.titulo,
            descricao=self.descricao,
            bairro=self.bairro,
            local_aprox_lat=self.local_aprox_lat,
            local_aprox_lng=self.local_aprox_lng,
            prazo_desejado=self.prazo_desejado,
            faixa_preco_min_centavos=self.faixa_preco_min_centavos,
            faixa_preco_max_centavos=self.faixa_preco_max_centavos,
            urgente=self.urgente,
            respostas=tuple(RespostaPedido(r.pergunta_id, r.resposta) for r in self.respostas),
            endereco=EnderecoPedido(**self.endereco.model_dump()) if self.endereco else None,
        )


class AceitarOrcamentoIn(_Entrada):
    orcamento_id: str

    def para_regra(self, profissional_id: str) -> ProvaAceite:
        return ProvaAceite(self.orcamento_id, profissional_id)


class ConfirmarAgendaIn(_Entrada):
    janela: JanelaIn

    def para_regra(self) -> ProvaAgenda:
        return ProvaAgenda(Janela(self.janela.inicio, self.janela.fim))


class CheckInIn(_Entrada):
    foto: FotoIn
    localizacao: LocalizacaoIn
    codigo_inicio: str

    def para_regra(self) -> ProvaCheckIn:
        return ProvaCheckIn(
            self.foto.para_regra(),
            Localizacao(self.localizacao.latitude, self.localizacao.longitude),
            self.codigo_inicio,
        )


class CheckOutIn(_Entrada):
    foto_final: FotoIn
    codigo_conclusao: str

    def para_regra(self) -> ProvaCheckOut:
        return ProvaCheckOut(self.foto_final.para_regra(), self.codigo_conclusao)


class CancelarIn(_Entrada):
    motivo: str

    def para_regra(self) -> ProvaCancelamento:
        return ProvaCancelamento(self.motivo)


class AcaoPedidoIn(_Entrada):
    """Corpo de `POST /v1/pedidos/{id}/acoes/{acao}`. O formato de `prova` depende da ação."""

    prova: dict[str, Any] | None = Field(
        default=None,
        description=(
            "aceitar_orcamento: {orcamento_id}. confirmar_agenda: {janela:{inicio,fim}}. "
            "fazer_check_in: {foto:{arquivo_id,tirada_em}, localizacao:{latitude,longitude}, "
            "codigo_inicio}. fazer_check_out: {foto_final, codigo_conclusao}. "
            "cancelar: {motivo}. confirmar_conclusao e encerrar_disputa_por_acordo: sem prova."
        ),
    )


class AbrirDisputaIn(_Entrada):
    motivo: MotivoDisputa
    descricao: str
    fotos: list[FotoIn] = []


class PedirRetrabalhoIn(_Entrada):
    descricao: str
    fotos: list[FotoIn] = []


# --- Saídas ---------------------------------------------------------------------------


class JanelaOut(BaseModel):
    inicio: datetime
    fim: datetime


class PedidoOut(BaseModel):
    id: str
    estado: str
    estado_nome: str
    cliente_id: str
    profissional_id: str | None
    aberto_em: datetime
    janela: JanelaOut | None
    concluido_em: datetime | None
    acoes_permitidas: list[str]
    codigo_inicio: str | None = Field(
        None, description="Só o cliente vê; ele informa ao profissional."
    )
    codigo_conclusao: str | None = Field(None, description="Só o cliente vê.")


class EventoOut(BaseModel):
    acao: str
    de: str
    para: str
    ator_papel: str
    ator_id: str
    em: datetime


class ContaOut(BaseModel):
    tipo: str
    titular: str | None


class LancamentoOut(BaseModel):
    id: str
    pedido_id: str
    tipo: str
    valor_centavos: int
    data: datetime
    debito: ContaOut
    credito: ContaOut
    estorno_de: str | None


class ExtratoOut(BaseModel):
    itens: list[LancamentoOut]
    total: int
    limite: int
    deslocamento: int


class SaldoPedidoOut(BaseModel):
    pedido_id: str
    cliente_pagou_centavos: int
    retido_centavos: int
    a_liberar_centavos: int
    liberado_centavos: int
    taxa_trato_centavos: int


class SaldoProfissionalOut(BaseModel):
    a_liberar_centavos: int
    liberado_centavos: int


class DisputaOut(BaseModel):
    pedido_id: str
    estado: str
    motivo: str
    valor_congelado_centavos: int
    aberta_em: datetime
    resposta_ate: datetime
    decisao_ate: datetime
    respondida_em: datetime | None
    sem_resposta: bool


class RetrabalhoOut(BaseModel):
    pedido_id: str
    estado: str
    aberto_em: datetime
    atender_ate: datetime
    descricao: str


class WebhookOut(BaseModel):
    recebido: bool
    duplicado: bool
    tratado: bool
