"""Máquina de estados do pedido (escopo, seção 4).

Cada transição valida QUEM pode (papel e pessoa), QUANDO (estado de origem e prazo)
e COM QUAL PROVA. Não mexe em dinheiro, banco nem HTTP: só decide se a mudança vale
e devolve o pedido novo junto com o evento de auditoria.

Prazos chegam em `PrazosPedido`, vindos da tabela de configuração. Nenhum número fixo aqui.
"""

from __future__ import annotations

import hmac
import secrets
from collections.abc import Callable
from dataclasses import dataclass, replace
from datetime import datetime, timedelta
from enum import StrEnum


class Estado(StrEnum):
    ABERTO = "aberto"
    ORCAMENTO_ACEITO = "orcamento_aceito"
    PAGO_E_RETIDO = "pago_e_retido"
    AGENDADO = "agendado"
    EM_ANDAMENTO = "em_andamento"
    EM_CONFIRMACAO = "em_confirmacao"
    CONCLUIDO = "concluido"
    CANCELADO = "cancelado"
    EM_DISPUTA = "em_disputa"
    RETRABALHO = "retrabalho"

    @property
    def nome(self) -> str:
        return _NOMES_ESTADO[self]


_NOMES_ESTADO = {
    Estado.ABERTO: "Aberto",
    Estado.ORCAMENTO_ACEITO: "Orçamento aceito",
    Estado.PAGO_E_RETIDO: "Pago e retido",
    Estado.AGENDADO: "Agendado",
    Estado.EM_ANDAMENTO: "Em andamento",
    Estado.EM_CONFIRMACAO: "Em confirmação",
    Estado.CONCLUIDO: "Concluído",
    Estado.CANCELADO: "Cancelado",
    Estado.EM_DISPUTA: "Em disputa",
    Estado.RETRABALHO: "Retrabalho",
}


class Papel(StrEnum):
    CLIENTE = "cliente"
    PROFISSIONAL = "profissional"
    SISTEMA = "sistema"  # rotinas e webhooks confirmados
    MEDIADOR = "mediador"  # analista do Trato


_NOMES_PAPEL = {
    Papel.CLIENTE: "Cliente",
    Papel.PROFISSIONAL: "Profissional",
    Papel.SISTEMA: "Sistema",
    Papel.MEDIADOR: "Mediador",
}


class Acao(StrEnum):
    ACEITAR_ORCAMENTO = "aceitar_orcamento"
    EXPIRAR_PEDIDO = "expirar_pedido"
    EXPIRAR_PAGAMENTO = "expirar_pagamento"
    CONFIRMAR_PAGAMENTO = "confirmar_pagamento"
    CONFIRMAR_AGENDA = "confirmar_agenda"
    REMARCAR = "remarcar"
    FAZER_CHECK_IN = "fazer_check_in"
    REGISTRAR_AUSENCIA = "registrar_ausencia"
    FAZER_CHECK_OUT = "fazer_check_out"
    CONFIRMAR_CONCLUSAO = "confirmar_conclusao"
    CONCLUIR_POR_PRAZO = "concluir_por_prazo"
    CANCELAR = "cancelar"
    ABRIR_DISPUTA = "abrir_disputa"
    ENCERRAR_DISPUTA_POR_ACORDO = "encerrar_disputa_por_acordo"
    DECIDIR_DISPUTA = "decidir_disputa"
    PEDIR_RETRABALHO = "pedir_retrabalho"


class MotivoDisputa(StrEnum):
    ABANDONO = "abandono"
    MAL_FEITO = "mal_feito"
    DANO = "dano"
    COBRANCA_EXTRA = "cobranca_extra"
    NAO_COMPARECEU = "nao_compareceu"
    DIFERENTE_DO_COMBINADO = "diferente_do_combinado"


class ResultadoDisputa(StrEnum):
    LIBERAR_TUDO = "liberar_tudo"
    REEMBOLSO_TOTAL = "reembolso_total"
    REEMBOLSO_PARCIAL = "reembolso_parcial"
    NOVA_VISITA = "nova_visita"


# --- Erros ---------------------------------------------------------------------------


class TransicaoInvalida(Exception):
    """Base: a mudança de estado pedida não vale."""


class EstadoInvalido(TransicaoInvalida):
    """A ação não vale no estado atual do pedido."""


class AtorNaoAutorizado(TransicaoInvalida):
    """Quem pediu não pode fazer esta ação neste pedido."""


class ProvaInvalida(TransicaoInvalida):
    """Faltou prova ou a prova não confere."""


class ForaDoPrazo(TransicaoInvalida):
    """O prazo ainda não venceu (rotina) ou já venceu (pedido do usuário)."""


class PrazoNaoConfigurado(TransicaoInvalida):
    """A transição precisa de um prazo que não veio da configuração."""


# --- Dados ---------------------------------------------------------------------------


@dataclass(frozen=True)
class Ator:
    papel: Papel
    id: str


@dataclass(frozen=True)
class Localizacao:
    latitude: float
    longitude: float


@dataclass(frozen=True)
class Foto:
    arquivo_id: str
    tirada_em: datetime


@dataclass(frozen=True)
class Janela:
    inicio: datetime
    fim: datetime


@dataclass(frozen=True)
class ProvaAceite:
    orcamento_id: str
    profissional_id: str


@dataclass(frozen=True)
class ProvaPagamento:
    referencia_pagamento: str  # id do pagamento confirmado pelo parceiro (webhook assinado)


@dataclass(frozen=True)
class ProvaAgenda:
    janela: Janela


@dataclass(frozen=True)
class ProvaRemarcacao:
    janela: Janela
    aceito_por: str  # id da outra parte, que aceitou a nova data


@dataclass(frozen=True)
class ProvaCheckIn:
    foto: Foto
    localizacao: Localizacao
    codigo_inicio: str


@dataclass(frozen=True)
class ProvaCheckOut:
    foto_final: Foto
    codigo_conclusao: str


@dataclass(frozen=True)
class ProvaCancelamento:
    motivo: str


@dataclass(frozen=True)
class ProvaDisputa:
    motivo: MotivoDisputa
    descricao: str
    fotos: tuple[Foto, ...] = ()


@dataclass(frozen=True)
class DecisaoDisputa:
    resultado: ResultadoDisputa
    justificativa: str


@dataclass(frozen=True)
class ProvaRetrabalho:
    descricao: str
    fotos: tuple[Foto, ...] = ()


Prova = (
    ProvaAceite
    | ProvaPagamento
    | ProvaAgenda
    | ProvaRemarcacao
    | ProvaCheckIn
    | ProvaCheckOut
    | ProvaCancelamento
    | ProvaDisputa
    | DecisaoDisputa
    | ProvaRetrabalho
)


@dataclass(frozen=True)
class PrazosPedido:
    """Prazos vindos da tabela de configuração. Só a transição que usa o prazo o exige."""

    receber_orcamentos: timedelta | None = None
    pagamento: timedelta | None = None
    tolerancia_comparecimento: timedelta | None = None
    confirmacao_cliente: timedelta | None = None
    garantia: timedelta | None = None  # por categoria


@dataclass(frozen=True)
class Pedido:
    id: str
    cliente_id: str
    aberto_em: datetime
    estado: Estado = Estado.ABERTO
    profissional_id: str | None = None
    orcamento_id: str | None = None
    aceito_em: datetime | None = None
    referencia_pagamento: str | None = None
    janela: Janela | None = None
    codigo_inicio: str | None = None
    codigo_conclusao: str | None = None
    check_in_em: datetime | None = None
    check_out_em: datetime | None = None
    concluido_em: datetime | None = None
    estado_antes_da_disputa: Estado | None = None


@dataclass(frozen=True)
class Evento:
    """Registro imutável de auditoria de cada transição."""

    pedido_id: str
    acao: Acao
    de: Estado
    para: Estado
    ator: Ator
    em: datetime
    prova: Prova | None


@dataclass(frozen=True)
class Transicao:
    pedido: Pedido
    evento: Evento


@dataclass(frozen=True)
class _Regra:
    rotulo: str
    quem: dict[Papel, frozenset[Estado]]  # papel -> estados de origem em que pode agir
    prova: type | None


def _de(*estados: Estado) -> frozenset[Estado]:
    return frozenset(estados)


E = Estado
REGRAS: dict[Acao, _Regra] = {
    Acao.ACEITAR_ORCAMENTO: _Regra(
        "aceitar o orçamento", {Papel.CLIENTE: _de(E.ABERTO)}, ProvaAceite
    ),
    Acao.EXPIRAR_PEDIDO: _Regra("expirar o pedido", {Papel.SISTEMA: _de(E.ABERTO)}, None),
    Acao.EXPIRAR_PAGAMENTO: _Regra(
        "expirar o pagamento", {Papel.SISTEMA: _de(E.ORCAMENTO_ACEITO)}, None
    ),
    Acao.CONFIRMAR_PAGAMENTO: _Regra(
        "confirmar o pagamento", {Papel.SISTEMA: _de(E.ORCAMENTO_ACEITO)}, ProvaPagamento
    ),
    Acao.CONFIRMAR_AGENDA: _Regra(
        "confirmar a agenda", {Papel.PROFISSIONAL: _de(E.PAGO_E_RETIDO)}, ProvaAgenda
    ),
    Acao.REMARCAR: _Regra(
        "remarcar",
        {Papel.CLIENTE: _de(E.AGENDADO), Papel.PROFISSIONAL: _de(E.AGENDADO)},
        ProvaRemarcacao,
    ),
    Acao.FAZER_CHECK_IN: _Regra(
        "fazer check-in", {Papel.PROFISSIONAL: _de(E.AGENDADO)}, ProvaCheckIn
    ),
    Acao.REGISTRAR_AUSENCIA: _Regra(
        "registrar ausência do profissional", {Papel.SISTEMA: _de(E.AGENDADO)}, None
    ),
    Acao.FAZER_CHECK_OUT: _Regra(
        "fazer check-out",
        {Papel.PROFISSIONAL: _de(E.EM_ANDAMENTO, E.RETRABALHO)},
        ProvaCheckOut,
    ),
    Acao.CONFIRMAR_CONCLUSAO: _Regra(
        "confirmar a conclusão", {Papel.CLIENTE: _de(E.EM_CONFIRMACAO)}, None
    ),
    Acao.CONCLUIR_POR_PRAZO: _Regra(
        "concluir por prazo", {Papel.SISTEMA: _de(E.EM_CONFIRMACAO)}, None
    ),
    Acao.CANCELAR: _Regra(
        "cancelar",
        {
            Papel.CLIENTE: _de(E.ABERTO, E.ORCAMENTO_ACEITO, E.PAGO_E_RETIDO, E.AGENDADO),
            Papel.PROFISSIONAL: _de(E.PAGO_E_RETIDO, E.AGENDADO),
        },
        ProvaCancelamento,
    ),
    Acao.ABRIR_DISPUTA: _Regra(
        "abrir disputa",
        {Papel.CLIENTE: _de(E.AGENDADO, E.EM_ANDAMENTO, E.EM_CONFIRMACAO, E.RETRABALHO)},
        ProvaDisputa,
    ),
    Acao.ENCERRAR_DISPUTA_POR_ACORDO: _Regra(
        "encerrar a disputa por acordo", {Papel.CLIENTE: _de(E.EM_DISPUTA)}, None
    ),
    Acao.DECIDIR_DISPUTA: _Regra(
        "decidir a disputa", {Papel.MEDIADOR: _de(E.EM_DISPUTA)}, DecisaoDisputa
    ),
    Acao.PEDIR_RETRABALHO: _Regra(
        "pedir retrabalho", {Papel.CLIENTE: _de(E.CONCLUIDO)}, ProvaRetrabalho
    ),
}
del E

_DESTINO_DA_DECISAO = {
    ResultadoDisputa.LIBERAR_TUDO: Estado.CONCLUIDO,
    ResultadoDisputa.REEMBOLSO_PARCIAL: Estado.CONCLUIDO,
    ResultadoDisputa.REEMBOLSO_TOTAL: Estado.CANCELADO,
    ResultadoDisputa.NOVA_VISITA: Estado.RETRABALHO,
}


def gerar_codigo() -> str:
    """Código de 4 dígitos que o cliente informa ao profissional (início e conclusão)."""
    return f"{secrets.randbelow(10_000):04d}"


# --- API -----------------------------------------------------------------------------


def abrir_pedido(pedido_id: str, ator: Ator, agora: datetime) -> Pedido:
    """Aberto: só o cliente cria o pedido."""
    _exigir_fuso(agora)
    if ator.papel is not Papel.CLIENTE:
        raise AtorNaoAutorizado(f"{_NOMES_PAPEL[ator.papel]} não pode abrir pedido.")
    return Pedido(id=pedido_id, cliente_id=ator.id, aberto_em=agora)


def acoes_permitidas(pedido: Pedido, papel: Papel) -> frozenset[Acao]:
    """Ações que o papel pode tentar no estado atual (sem checar prova nem prazo)."""
    return frozenset(
        acao for acao, regra in REGRAS.items() if pedido.estado in regra.quem.get(papel, ())
    )


def transicionar(
    pedido: Pedido,
    acao: Acao,
    ator: Ator,
    agora: datetime,
    prova: Prova | None = None,
    prazos: PrazosPedido | None = None,
    gerar_codigo: Callable[[], str] = gerar_codigo,
) -> Transicao:
    """Aplica a ação ao pedido. Levanta `TransicaoInvalida` (ou filha) se não vale."""
    _exigir_fuso(agora)
    prazos = prazos or PrazosPedido()
    regra = REGRAS[acao]
    papel = _NOMES_PAPEL[ator.papel]

    if ator.papel not in regra.quem:
        raise AtorNaoAutorizado(f"{papel} não pode {regra.rotulo}.")
    if pedido.estado not in regra.quem[ator.papel]:
        raise EstadoInvalido(
            f"{papel} não pode {regra.rotulo} com o pedido em {pedido.estado.nome}."
        )
    _exigir_pessoa_do_pedido(pedido, ator)
    if regra.prova is None and prova is not None:
        raise ProvaInvalida(f"Para {regra.rotulo} não se envia prova.")
    if regra.prova is not None and not isinstance(prova, regra.prova):
        raise ProvaInvalida(f"Para {regra.rotulo} é preciso enviar {regra.prova.__name__}.")

    novo = _APLICAR[acao](pedido, ator, agora, prova, prazos, gerar_codigo)
    evento = Evento(
        pedido_id=pedido.id,
        acao=acao,
        de=pedido.estado,
        para=novo.estado,
        ator=ator,
        em=agora,
        prova=prova,
    )
    return Transicao(pedido=novo, evento=evento)


# --- Validações ----------------------------------------------------------------------


def _exigir_fuso(momento: datetime) -> None:
    if momento.tzinfo is None:
        raise ValueError("Data e hora precisam ter fuso horário.")


def _exigir_pessoa_do_pedido(pedido: Pedido, ator: Ator) -> None:
    if ator.papel is Papel.CLIENTE and ator.id != pedido.cliente_id:
        raise AtorNaoAutorizado("Só o cliente deste pedido pode fazer isso.")
    if ator.papel is Papel.PROFISSIONAL and ator.id != pedido.profissional_id:
        raise AtorNaoAutorizado("Só o profissional contratado neste pedido pode fazer isso.")
    if ator.papel is Papel.MEDIADOR and ator.id in (pedido.cliente_id, pedido.profissional_id):
        raise AtorNaoAutorizado("Mediador não pode decidir pedido em que é parte.")


def _exigir_texto(texto: str, campo: str) -> None:
    if not texto.strip():
        raise ProvaInvalida(f"Informe {campo}.")


def _exigir_foto(foto: Foto, agora: datetime, campo: str) -> None:
    if not foto.arquivo_id.strip():
        raise ProvaInvalida(f"Falta a {campo}.")
    _exigir_fuso(foto.tirada_em)
    if foto.tirada_em > agora:
        raise ProvaInvalida(f"A {campo} tem data no futuro.")


def _exigir_localizacao(local: Localizacao) -> None:
    if not (-90 <= local.latitude <= 90 and -180 <= local.longitude <= 180):
        raise ProvaInvalida("Localização inválida.")


def _exigir_janela(janela: Janela, agora: datetime) -> None:
    _exigir_fuso(janela.inicio)
    _exigir_fuso(janela.fim)
    if janela.fim <= janela.inicio:
        raise ProvaInvalida("A janela de atendimento precisa terminar depois de começar.")
    if janela.inicio < agora:
        raise ProvaInvalida("A janela de atendimento não pode começar no passado.")


def _exigir_codigo(informado: str, esperado: str | None, nome: str) -> None:
    if esperado is None or not hmac.compare_digest(informado.encode(), esperado.encode()):
        raise ProvaInvalida(f"O código de {nome} não confere.")


def _prazo(prazos: PrazosPedido, campo: str, rotulo: str) -> timedelta:
    valor = getattr(prazos, campo)
    if valor is None:
        raise PrazoNaoConfigurado(f"Prazo de {rotulo} não configurado.")
    return valor


def _exigir_vencido(referencia: datetime | None, prazo: timedelta, agora: datetime, rotulo: str):
    if referencia is None or agora < referencia + prazo:
        raise ForaDoPrazo(f"O prazo de {rotulo} ainda não venceu.")


# --- Efeito de cada ação -------------------------------------------------------------


def _aceitar_orcamento(pedido, ator, agora, prova: ProvaAceite, prazos, gerar):
    _exigir_texto(prova.orcamento_id, "o orçamento aceito")
    _exigir_texto(prova.profissional_id, "o profissional do orçamento")
    if prova.profissional_id == pedido.cliente_id:
        raise ProvaInvalida("O cliente não pode contratar a si mesmo.")
    return replace(
        pedido,
        estado=Estado.ORCAMENTO_ACEITO,
        orcamento_id=prova.orcamento_id,
        profissional_id=prova.profissional_id,
        aceito_em=agora,
    )


def _expirar_pedido(pedido, ator, agora, prova, prazos, gerar):
    prazo = _prazo(prazos, "receber_orcamentos", "receber orçamentos")
    _exigir_vencido(pedido.aberto_em, prazo, agora, "receber orçamentos")
    return replace(pedido, estado=Estado.CANCELADO)


def _expirar_pagamento(pedido, ator, agora, prova, prazos, gerar):
    prazo = _prazo(prazos, "pagamento", "pagamento")
    _exigir_vencido(pedido.aceito_em, prazo, agora, "pagamento")
    return replace(
        pedido,
        estado=Estado.ABERTO,
        aberto_em=agora,
        orcamento_id=None,
        profissional_id=None,
        aceito_em=None,
    )


def _confirmar_pagamento(pedido, ator, agora, prova: ProvaPagamento, prazos, gerar):
    _exigir_texto(prova.referencia_pagamento, "a referência do pagamento")
    return replace(
        pedido, estado=Estado.PAGO_E_RETIDO, referencia_pagamento=prova.referencia_pagamento
    )


def _confirmar_agenda(pedido, ator, agora, prova: ProvaAgenda, prazos, gerar):
    _exigir_janela(prova.janela, agora)
    return replace(pedido, estado=Estado.AGENDADO, janela=prova.janela, codigo_inicio=gerar())


def _remarcar(pedido, ator, agora, prova: ProvaRemarcacao, prazos, gerar):
    outra_parte = pedido.profissional_id if ator.papel is Papel.CLIENTE else pedido.cliente_id
    if prova.aceito_por != outra_parte:
        raise ProvaInvalida("Remarcação exige o aceite da outra parte.")
    _exigir_janela(prova.janela, agora)
    return replace(pedido, janela=prova.janela)


def _fazer_check_in(pedido, ator, agora, prova: ProvaCheckIn, prazos, gerar):
    _exigir_foto(prova.foto, agora, "foto do check-in")
    _exigir_localizacao(prova.localizacao)
    _exigir_codigo(prova.codigo_inicio, pedido.codigo_inicio, "início")
    return replace(pedido, estado=Estado.EM_ANDAMENTO, check_in_em=agora, codigo_conclusao=gerar())


def _registrar_ausencia(pedido, ator, agora, prova, prazos, gerar):
    prazo = _prazo(prazos, "tolerancia_comparecimento", "tolerância de comparecimento")
    fim = pedido.janela.fim if pedido.janela else None
    _exigir_vencido(fim, prazo, agora, "tolerância de comparecimento")
    return replace(pedido, estado=Estado.CANCELADO)


def _fazer_check_out(pedido, ator, agora, prova: ProvaCheckOut, prazos, gerar):
    _exigir_foto(prova.foto_final, agora, "foto final")
    _exigir_codigo(prova.codigo_conclusao, pedido.codigo_conclusao, "conclusão")
    return replace(pedido, estado=Estado.EM_CONFIRMACAO, check_out_em=agora)


def _concluir(pedido: Pedido, agora: datetime) -> Pedido:
    # A garantia conta da primeira conclusão; retrabalho não a renova.
    return replace(
        pedido,
        estado=Estado.CONCLUIDO,
        concluido_em=pedido.concluido_em or agora,
        estado_antes_da_disputa=None,
    )


def _confirmar_conclusao(pedido, ator, agora, prova, prazos, gerar):
    return _concluir(pedido, agora)


def _concluir_por_prazo(pedido, ator, agora, prova, prazos, gerar):
    prazo = _prazo(prazos, "confirmacao_cliente", "confirmação do cliente")
    _exigir_vencido(pedido.check_out_em, prazo, agora, "confirmação do cliente")
    return _concluir(pedido, agora)


def _cancelar(pedido, ator, agora, prova: ProvaCancelamento, prazos, gerar):
    _exigir_texto(prova.motivo, "o motivo do cancelamento")
    return replace(pedido, estado=Estado.CANCELADO)


def _abrir_disputa(pedido, ator, agora, prova: ProvaDisputa, prazos, gerar):
    _exigir_texto(prova.descricao, "a descrição do problema")
    for foto in prova.fotos:
        _exigir_foto(foto, agora, "foto da disputa")
    return replace(pedido, estado=Estado.EM_DISPUTA, estado_antes_da_disputa=pedido.estado)


def _encerrar_disputa_por_acordo(pedido, ator, agora, prova, prazos, gerar):
    return _concluir(pedido, agora)


def _decidir_disputa(pedido, ator, agora, prova: DecisaoDisputa, prazos, gerar):
    _exigir_texto(prova.justificativa, "a justificativa da decisão")
    destino = _DESTINO_DA_DECISAO[prova.resultado]
    if destino is Estado.CONCLUIDO:
        return _concluir(pedido, agora)
    if destino is Estado.RETRABALHO:
        return _entrar_em_retrabalho(pedido, gerar)
    return replace(pedido, estado=destino, estado_antes_da_disputa=None)


def _entrar_em_retrabalho(pedido: Pedido, gerar: Callable[[], str]) -> Pedido:
    return replace(
        pedido,
        estado=Estado.RETRABALHO,
        codigo_conclusao=gerar(),
        check_out_em=None,
        estado_antes_da_disputa=None,
    )


def _pedir_retrabalho(pedido, ator, agora, prova: ProvaRetrabalho, prazos, gerar):
    garantia = _prazo(prazos, "garantia", "garantia")
    if pedido.concluido_em is None or agora > pedido.concluido_em + garantia:
        raise ForaDoPrazo("O prazo da garantia já acabou.")
    _exigir_texto(prova.descricao, "a descrição do defeito")
    for foto in prova.fotos:
        _exigir_foto(foto, agora, "foto do defeito")
    return _entrar_em_retrabalho(pedido, gerar)


_APLICAR = {
    Acao.ACEITAR_ORCAMENTO: _aceitar_orcamento,
    Acao.EXPIRAR_PEDIDO: _expirar_pedido,
    Acao.EXPIRAR_PAGAMENTO: _expirar_pagamento,
    Acao.CONFIRMAR_PAGAMENTO: _confirmar_pagamento,
    Acao.CONFIRMAR_AGENDA: _confirmar_agenda,
    Acao.REMARCAR: _remarcar,
    Acao.FAZER_CHECK_IN: _fazer_check_in,
    Acao.REGISTRAR_AUSENCIA: _registrar_ausencia,
    Acao.FAZER_CHECK_OUT: _fazer_check_out,
    Acao.CONFIRMAR_CONCLUSAO: _confirmar_conclusao,
    Acao.CONCLUIR_POR_PRAZO: _concluir_por_prazo,
    Acao.CANCELAR: _cancelar,
    Acao.ABRIR_DISPUTA: _abrir_disputa,
    Acao.ENCERRAR_DISPUTA_POR_ACORDO: _encerrar_disputa_por_acordo,
    Acao.DECIDIR_DISPUTA: _decidir_disputa,
    Acao.PEDIR_RETRABALHO: _pedir_retrabalho,
}
