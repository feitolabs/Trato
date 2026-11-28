"""Desistir do pedido (Termos 7.1 a 7.4 e 7.9; CDC art. 49).

Antes do check-in usa o cancelamento de sempre (reembolso integral, com o parcelamento). Com o
serviço iniciado dentro dos 7 dias: sem o pedido expresso de execução (7.3), cancela e devolve
tudo na hora; com ele, abre um caso para o analista, que é uma disputa (valor congelado, decisão
por `api/decisao_disputa.py`, permissão `disputas_decidir`).

Prazo: 7 dias corridos contados da CONTRATAÇÃO (pagamento confirmado, 5.3), valendo até o fim do
sétimo dia no horário de Brasília. Sem saber a data, vale a leitura favorável: dentro do prazo.
"""

from __future__ import annotations

import threading
from collections.abc import Iterator
from contextlib import contextmanager, nullcontext
from datetime import datetime, time, timedelta

from fastapi import APIRouter, Depends, HTTPException, Request
from pydantic import BaseModel, ConfigDict, Field

from trato.api import ausencia, rotas_pedidos
from trato.api.auth import PapelUsuario, Usuario
from trato.api.avisos import avisar_partes
from trato.api.contexto import Contexto, exigir_papel, obter_contexto
from trato.api.modelos import AbrirDisputaIn, AcaoPedidoIn
from trato.api.regra_contratada import regra_do_contrato
from trato.api.servicos import carregar_pedido
from trato.financeiro import periodo
from trato.notificacoes.eventos import Evento
from trato.pedidos import estados
from trato.pedidos.estados import Acao, Estado, Pedido
from trato.persistencia.cancelamentos import EM_ANALISE, Cancelamento
from trato.rotinas.regras import SISTEMA

router = APIRouter(prefix="/v1/pedidos", tags=["desistência"])

_SEM_CHECK_IN = frozenset(
    {Estado.ABERTO, Estado.RESERVADO, Estado.ORCAMENTO_ACEITO, Estado.PAGO_E_RETIDO,
     Estado.AGENDADO}
)  # fmt: skip
_TRAVA_EM_MEMORIA = threading.RLock()
_TIPOS_DO_CLIENTE = ("desistencia_arrependimento", "cancelamento_cliente")
MOTIVO_PADRAO = "Desistência do cliente."


class DesistirIn(BaseModel):
    model_config = ConfigDict(extra="forbid")

    motivo: str | None = Field(None, max_length=1000, description="Opcional (Termos 7.2).")


class DesistenciaOut(BaseModel):
    pedido_id: str
    tipo: str = Field(description="desistencia_arrependimento | cancelamento_cliente")
    situacao: str = Field(description="reembolso_integral | em_analise | analisado")
    protocolo: str | None = Field(None, description="Id do registro (null sem a tabela).")
    recebido_em: datetime
    dentro_do_arrependimento: bool
    reembolso_centavos: int | None = Field(None, description="null enquanto o analista não decide.")
    estado_pedido: str
    mensagem: str


class SituacaoDesistenciaOut(BaseModel):
    pode_desistir: bool
    efeito: str = Field(description="reembolso_integral | analise | indisponivel")
    motivo_indisponivel: str | None = None
    contratado_em: datetime | None = None
    arrependimento_ate: datetime | None = None
    dentro_do_arrependimento: bool
    consentimento_execucao_imediata: bool
    consentimento_em: datetime | None = None
    registro: DesistenciaOut | None = None


def contratado_em(contexto: Contexto, pedido: Pedido) -> datetime | None:
    """Quando o parceiro confirmou o pagamento (5.3). Sem a data, quem chama trata como dentro
    do prazo."""
    confirmacoes = [
        e.em for e in contexto.pedidos.eventos(pedido.id) if e.acao is Acao.CONFIRMAR_PAGAMENTO
    ]
    return confirmacoes[-1] if confirmacoes else None


def arrependimento_ate(contratado: datetime, dias: int) -> datetime:
    """Fim do último dia do prazo, em Brasília (dias corridos)."""
    ultimo = contratado.astimezone(periodo.BRASILIA).date() + timedelta(days=dias)
    return datetime.combine(ultimo, time.max, periodo.BRASILIA)


def prazo(contexto: Contexto, pedido: Pedido) -> tuple[datetime | None, datetime | None, bool]:
    try:
        dias = contexto.config.carregar().arrependimento_dias
    except Exception:  # noqa: BLE001 - o direito não depende de a configuração estar publicada
        dias = 7
    contrato = contexto.contratos.obter_do_pedido(pedido.id)
    dias = regra_do_contrato(contrato, "arrependimento_dias", "maior", dias)  # 23.6
    inicio = contratado_em(contexto, pedido)
    ate = arrependimento_ate(inicio, max(dias, 7)) if inicio else None
    return inicio, ate, ate is None or contexto.agora() <= ate


def _efeito(contexto: Contexto, pedido: Pedido, dentro: bool) -> tuple[str, str | None]:
    if pedido.estado in _SEM_CHECK_IN:
        return "reembolso_integral", None
    if pedido.estado is Estado.AGUARDANDO_CONFIRMACAO:
        return "indisponivel", "O pagamento está sendo confirmado. Tente de novo em instantes."
    if pedido.estado in (Estado.EM_ANDAMENTO, Estado.EM_CONFIRMACAO):
        guarda = contexto.cancelamentos
        consentiu = guarda.consentimento_em(pedido.id) is not None
        if consentiu and pedido.estado is Estado.EM_CONFIRMACAO:
            return "indisponivel", (
                "O serviço já foi executado por inteiro. Se algo saiu errado, use Relatar problema."
            )
        if not dentro:
            return "indisponivel", (
                "O prazo de arrependimento terminou e o serviço já começou. Use Relatar problema."
            )
        # Sem o pedido expresso, devolve tudo (7.2, art. 49). Se não há como saber, analisa.
        if consentiu or not guarda.consentimento_disponivel():
            return "analise", None
        return "reembolso_integral", None
    if pedido.estado is Estado.EM_DISPUTA:
        return "indisponivel", "Este pedido já está em análise."
    if pedido.estado is Estado.CANCELADO:
        return "indisponivel", "Este pedido já foi cancelado."
    return "indisponivel", "O serviço já foi concluído. Use a garantia ou Relatar problema."


_MENSAGENS = {
    "reembolso_integral": "Recebemos a sua desistência. O pedido foi cancelado e o valor pago "
    "volta por inteiro, pela mesma forma de pagamento.",
    "em_analise": "Recebemos a sua desistência. Como o serviço já começou, um analista vai "
    "calcular o reembolso. O valor fica retido até a decisão.",
    "analisado": "A sua desistência foi analisada.",
}


def _saida(pedido: Pedido, item: Cancelamento) -> DesistenciaOut:
    situacao = {
        EM_ANALISE: "em_analise",
        "cancelado_sem_retencao": "reembolso_integral",
    }.get(item.status, "analisado")
    return DesistenciaOut(
        pedido_id=pedido.id,
        tipo=item.tipo,
        situacao=situacao,
        protocolo=item.id,
        recebido_em=item.recebido_em,
        dentro_do_arrependimento=item.dentro_do_arrependimento,
        reembolso_centavos=item.reembolso_centavos,
        estado_pedido=pedido.estado.value,
        mensagem=_MENSAGENS[situacao],
    )


def _do_cliente(contexto: Contexto, pedido_id: str, usuario: Usuario) -> Pedido:
    pedido = carregar_pedido(contexto, pedido_id, usuario)
    if pedido.cliente_id != usuario.id:
        raise HTTPException(403, "Só o cliente do pedido pode desistir dele.")
    return pedido


@contextmanager
def _uma_por_vez(contexto: Contexto, pedido_id: str) -> Iterator[None]:
    travar = getattr(contexto.pedidos, "travar", None)
    with _TRAVA_EM_MEMORIA if travar is None else nullcontext():
        with contexto.transacao():
            if travar is not None:
                travar(pedido_id)
            yield


@router.get(
    "/{pedido_id}/desistencia",
    response_model=SituacaoDesistenciaOut,
    summary="Posso desistir? O que acontece e até quando vale o arrependimento",
)
def situacao_da_desistencia(
    pedido_id: str,
    usuario: Usuario = Depends(exigir_papel(PapelUsuario.CLIENTE, PapelUsuario.PROFISSIONAL)),
    contexto: Contexto = Depends(obter_contexto),
) -> SituacaoDesistenciaOut:
    pedido = _do_cliente(contexto, pedido_id, usuario)
    inicio, ate, dentro = prazo(contexto, pedido)
    efeito, motivo = _efeito(contexto, pedido, dentro)
    registro = contexto.cancelamentos.do_pedido(pedido.id)
    if registro is not None and registro.tipo not in _TIPOS_DO_CLIENTE:
        registro = None  # cliente ausente tem rota própria
    consentiu = contexto.cancelamentos.consentimento_em(pedido.id)
    return SituacaoDesistenciaOut(
        pode_desistir=efeito != "indisponivel",
        efeito=efeito,
        motivo_indisponivel=motivo,
        contratado_em=inicio,
        arrependimento_ate=ate,
        dentro_do_arrependimento=dentro,
        consentimento_execucao_imediata=consentiu is not None,
        consentimento_em=consentiu,
        registro=_saida(pedido, registro) if registro else None,
    )


@router.post(
    "/{pedido_id}/desistir",
    response_model=DesistenciaOut,
    summary="Desistir do pedido",
    description=(
        "Sem motivo obrigatório. Antes do check-in, ou iniciado sem o pedido expresso de "
        "execução, cancela e devolve tudo. Iniciado com o pedido expresso, abre um caso para o "
        "analista. Repetir devolve o mesmo registro. Fora disso responde 409 com a explicação."
    ),
)
def desistir(
    pedido_id: str,
    request: Request,
    corpo: DesistirIn | None = None,
    usuario: Usuario = Depends(exigir_papel(PapelUsuario.CLIENTE, PapelUsuario.PROFISSIONAL)),
    contexto: Contexto = Depends(obter_contexto),
) -> DesistenciaOut:
    _do_cliente(contexto, pedido_id, usuario)
    motivo = ((corpo.motivo if corpo else None) or "").strip()
    with _uma_por_vez(contexto, pedido_id):
        pedido = _do_cliente(contexto, pedido_id, usuario)  # relido já com a trava
        anterior = contexto.cancelamentos.do_pedido(pedido.id)
        # Recusado não impede um novo pedido, se o estado ainda permitir (abaixo).
        if anterior is not None and anterior.tipo not in _TIPOS_DO_CLIENTE:
            anterior = None  # registro de cliente ausente não é desistência
        if anterior is not None and anterior.status != "recusado":
            return _saida(pedido, anterior)
        agora = contexto.agora()
        _, _, dentro = prazo(contexto, pedido)
        efeito, indisponivel = _efeito(contexto, pedido, dentro)
        if efeito == "indisponivel":
            if anterior is not None:
                return _saida(pedido, anterior)
            raise HTTPException(409, indisponivel)
        iniciado = pedido.estado in (Estado.EM_ANDAMENTO, Estado.EM_CONFIRMACAO)
        reembolso = None
        if efeito == "analise":
            consentiu = contexto.cancelamentos.consentimento_em(pedido.id) is not None
            descricao = (
                "Desistência dentro dos 7 dias (arrependimento) com o serviço iniciado. "
                + (
                    "Cliente PEDIU a execução antes do fim do prazo: reembolso proporcional "
                    "à parte não executada (Termos 7.3)."
                    if consentiu
                    else "Cliente NÃO pediu a execução antes do fim do prazo: avaliar "
                    "reembolso integral (Termos 7.2)."
                )
                + (f" Motivo informado: {motivo}" if motivo else "")
            )
            rotas_pedidos.abrir_disputa(
                pedido.id,
                AbrirDisputaIn(motivo="diferente_do_combinado", descricao=descricao),
                usuario,
                contexto,
            )
        elif iniciado:  # sem consentimento: cancela e devolve tudo, pelo caminho único
            pago = contexto.ledger.saldos_pedido(pedido.id, pedido.profissional_id).cliente_pagou
            transicao = estados.transicionar(
                pedido,
                Acao.CANCELAR_ARREPENDIMENTO,
                SISTEMA,
                agora,
                prazos=contexto.config.carregar().prazos_pedido,
            )
            gravado_pedido = contexto.pedidos.salvar(transicao.pedido, transicao.evento)
            for gancho in contexto.apos_transicao:
                gancho(pedido, gravado_pedido, Acao.CANCELAR_ARREPENDIMENTO, contexto)
            depois_pago = contexto.ledger.saldos_pedido(pedido.id, pedido.profissional_id)
            reembolso = pago - depois_pago.cliente_pagou
        else:
            ausencia.barrar_cancelamento(contexto, pedido, dentro)
            pago = contexto.ledger.saldos_pedido(pedido.id, pedido.profissional_id).cliente_pagou
            rotas_pedidos.mudar_estado(
                pedido.id,
                Acao.CANCELAR,
                request,
                AcaoPedidoIn(prova={"motivo": motivo or MOTIVO_PADRAO}),
                usuario,
                contexto,
            )
            reembolso = (
                pago
                - contexto.ledger.saldos_pedido(pedido.id, pedido.profissional_id).cliente_pagou
            )
        item = Cancelamento(
            pedido_id=pedido.id,
            solicitado_por=usuario.id,
            tipo="desistencia_arrependimento" if dentro else "cancelamento_cliente",
            status=EM_ANALISE if efeito == "analise" else "cancelado_sem_retencao",
            recebido_em=agora,
            motivo=motivo,
            servico_iniciado=iniciado,
            dentro_do_arrependimento=dentro,
            reembolso_centavos=reembolso,
        )
        contexto.cancelamentos.descartar_proposta(pedido.id)
        gravado = contexto.cancelamentos.registrar(item) or item
        depois = contexto.pedidos.obter(pedido.id) or pedido
        # Termos 7.2: o recebimento é confirmado na hora (resposta, app e e-mail).
        avisar_partes(
            contexto,
            Evento.DESISTENCIA_RECEBIDA,
            (depois.cliente_id, depois.profissional_id),
            pedido_id=depois.id,
            chave=f"{depois.id}:desistencia",
        )
    return _saida(depois, gravado)
