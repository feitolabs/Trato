"""Termos 22.3 aplicado aos prazos e encargos do pedido. O cálculo está em
`disputas/indisponibilidade.py`; as janelas, em `persistencia/indisponibilidades.py`."""

from __future__ import annotations

from dataclasses import replace
from datetime import datetime, timedelta

from trato.api.contexto import Contexto
from trato.disputas.indisponibilidade import (
    Intervalo,
    cobre,
    estender,
    prorrogar,
    ultimo_inicio_vencido,
)
from trato.pedidos.estados import Acao, Pedido

# 22.3, parte 2. Atos feitos só no aplicativo dependem de 'app'; os que envolvem pagar,
# também do Parceiro de Pagamento.
APP = ("app",)
APP_E_PAGAMENTO = ("app", "pagamento")
ORIGENS_ORCAMENTO = APP_E_PAGAMENTO  # aceitar, renegociar, cobrar e confirmar o pagamento
ORIGENS_RESERVA_PIX = APP_E_PAGAMENTO
ORIGENS_VISITA = APP_E_PAGAMENTO  # orçar, aceitar e pagar a visita recorrente
# Só app: resposta e janela de congelamento da disputa, avaliação, contestação de medida e
# justificativa de ausência.

# Quais falhas afetam cada ato: confirmar o serviço e fazer check-in dependem do app;
# pagar depende do app e do Parceiro de Pagamento.
ORIGENS_DO_ATO = {
    Acao.CONCLUIR_POR_PRAZO: ("app",),
    Acao.EXPIRAR_PAGAMENTO: ("app", "pagamento"),
    Acao.REGISTRAR_AUSENCIA: ("app",),
    Acao.EXPIRAR_PEDIDO: ("app",),  # o profissional orça pelo app
}


def _falhas(
    contexto: Contexto, origens: tuple[str, ...], desde: datetime | None
) -> list[Intervalo]:
    return intervalos(contexto.indisponibilidades, origens, desde)


def intervalos(repo, origens: tuple[str, ...], desde: datetime | None) -> list[Intervalo]:
    return [(j.inicio_em, j.fim_em) for j in repo.listar(desde=desde) if j.origem in origens]


def prazo_vigente(
    contexto: Contexto,
    origens: tuple[str, ...],
    desde: datetime | None,
    ate: datetime | None,
    agora: datetime | None = None,
) -> datetime | None:
    """`ate` prorrogado pela 22.3. Sem data de início ou de fim, fica como está."""
    if desde is None or ate is None:
        return ate
    falhas = _falhas(contexto, origens, desde)
    return estender(falhas, desde, ate, agora or contexto.agora()) if falhas else ate


def corte_das_reservas(contexto: Contexto, validade: timedelta, agora: datetime) -> datetime:
    """Instante a passar para a expiração das reservas do Pix (que compara com `expira_em`):
    reserva atingida por falha ganha de volta o tempo dela. Sem falha, é o próprio `agora`."""
    falhas = _falhas(contexto, ORIGENS_RESERVA_PIX, None)
    if not falhas:
        return agora
    return ultimo_inicio_vencido(agora, validade, falhas) + validade


def falha_cobre_presenca(contexto: Contexto, pedido: Pedido) -> bool:
    """O app falhou durante o atendimento (do começo da janela ao fim da tolerância)? Então não
    há encargo de não comparecimento nem de cancelamento."""
    if pedido.janela is None:
        return False
    tolerancia = contexto.config.carregar().prazos_pedido.tolerancia_comparecimento
    fim = pedido.janela.fim + (tolerancia or timedelta(0))
    origens = ORIGENS_DO_ATO[Acao.REGISTRAR_AUSENCIA]
    inicio = pedido.janela.inicio
    return cobre(inicio, fim, _falhas(contexto, origens, inicio))


def impedimento_por_falha(
    contexto: Contexto,
    pedido: Pedido,
    acao: Acao,
    agora: datetime,
    desde: datetime | None = None,
    prazos=None,  # type: ignore[no-untyped-def]
) -> str | None:
    """Por que o prazo automático ainda não pode correr. `desde`: início da janela de
    confirmação quando ela recomeçou (desbloqueio)."""
    if acao not in ORIGENS_DO_ATO:
        return None
    prazos = prazos or contexto.config.carregar().prazos_pedido
    if acao is Acao.REGISTRAR_AUSENCIA:
        # 22.3: falha durante o atendimento não vira ausência automática (o cliente segue
        # podendo cancelar com reembolso integral; a equipe confere).
        return "falha_cobre_evento" if falha_cobre_presenca(contexto, pedido) else None
    if acao is Acao.EXPIRAR_PAGAMENTO:
        inicio, prazo = pedido.aceito_em, prazos.pagamento
    elif acao is Acao.EXPIRAR_PEDIDO:  # `pedido.aberto_em`: quem chama passa a (re)abertura
        inicio, prazo = pedido.aberto_em, prazos.receber_orcamentos
    else:
        inicio, prazo = desde or pedido.check_out_em, prazos.confirmacao_cliente
    if inicio is None or prazo is None or agora < inicio + prazo:
        return None  # prazo original ainda correndo: a máquina de estados já recusa
    vence = prorrogar(inicio, prazo, _falhas(contexto, ORIGENS_DO_ATO[acao], inicio))
    return "indisponibilidade" if vence is None or agora < vence else None


def disputa_vigente(contexto: Contexto, d):  # type: ignore[no-untyped-def]
    """A disputa com o prazo de resposta prorrogado. Só para conferir e mostrar: nunca grave
    esta cópia (o prazo gravado é o original, senão a falha contaria duas vezes)."""
    resposta = prazo_vigente(contexto, APP, d.aberta_em, d.prazos.resposta_ate)
    return replace(d, prazos=replace(d.prazos, resposta_ate=resposta))


def fim_do_congelamento(contexto: Contexto, concluido_em: datetime) -> datetime:
    """Fim da janela em que a disputa ainda congela o repasse, já prorrogada."""
    horas = contexto.config.carregar().disputas.prazo_congelar_repasse_horas
    return prazo_vigente(contexto, APP, concluido_em, concluido_em + timedelta(hours=horas))
