"""Termos 5.7: no Check-out sem o Código Final, o Trato avisa o cliente, abre o caso e conta o
prazo de resposta. Confirmar ou relatar problema registra a resposta. O silêncio nunca libera nem
estorna sozinho; na fase 2, um analista com permissão e alçada pode decidir (`liberar` ou
`estornar`) de forma auditada e idempotente."""

from __future__ import annotations

import logging
import threading
from contextlib import nullcontext
from datetime import datetime, time
from functools import partial
from typing import Any

from fastapi import HTTPException

from trato.api.admin.papeis import PapelEquipe
from trato.api.indisponibilidade import APP, prazo_vigente
from trato.api.regra_contratada import dias_de_garantia
from trato.disputas.prazos import adicionar_dias_uteis
from trato.financeiro import periodo
from trato.financeiro.ledger import reembolso_total_com_custo
from trato.garantias import abrir_garantia
from trato.notificacoes.eventos import Evento
from trato.pedidos import estados
from trato.pedidos.estados import (
    Acao,
    Ator,
    DecisaoDisputa,
    Estado,
    Papel,
    Pedido,
    ResultadoDisputa,
)
from trato.persistencia.checkout_sem_codigo import Caso

log = logging.getLogger("trato.checkout_sem_codigo")
CHAVE_DIAS = "checkout_sem_codigo_resposta_dias_uteis"
DIAS_PADRAO = 5  # Termos 5.7; a configuração só pode aumentar
CONFIRMOU = "confirmou"
RELATOU = "relatou_problema"
DECISAO_LIBERAR = "liberar"
DECISAO_ESTORNAR = "estornar"
_TRAVA_EM_MEMORIA = threading.RLock()


def dias_para_responder(contexto: Any) -> int:
    try:
        publicado = contexto.config.parametro_inteiro(CHAVE_DIAS)
    except Exception:  # noqa: BLE001 - sem a configuração, vale o texto dos Termos
        publicado = None
    return max(DIAS_PADRAO, publicado or 0)


def prazo_original(contexto: Any, contatado_em: datetime) -> datetime:
    """Fim do último dia útil do prazo, em Brasília (o dia do contato não conta)."""
    local = contatado_em.astimezone(periodo.BRASILIA)
    ultimo = adicionar_dias_uteis(
        local, dias_para_responder(contexto), contexto.config.carregar().disputas.feriados
    )
    return datetime.combine(ultimo.date(), time(23, 59, 59), periodo.BRASILIA)


def responder_ate(contexto: Any, caso: Caso) -> datetime | None:
    """Com a prorrogação por falha do app (22.3), calculada na leitura."""
    return prazo_vigente(contexto, APP, caso.contatado_em, caso.responder_ate)


def registrar_contato(contexto: Any, caso: Caso, canal: str) -> Caso | None:
    agora = contexto.agora()
    return contexto.checkout_sem_codigo.registrar_contato(
        caso.id, agora, canal, prazo_original(contexto, agora)
    )


def _alcada_do_operador(operador: Any) -> int:
    alcada = operador.membro.alcada_centavos
    if operador.membro.papel == PapelEquipe.ADMINISTRADOR:
        return alcada or 100_000_000_00
    return alcada or 0


def efetivar_decisao(
    contexto: Any,
    admin: Any,
    servico: Any,
    operador: Any,
    caso_id: str,
    decisao: str,
    motivo: str,
    chave_idempotencia: str,
) -> tuple[Caso, Pedido, bool]:
    """Decide o caso (`liberar` ou `estornar`) numa única transação com o pedido e o ledger.
    Devolve `(caso, pedido, idempotente)`."""
    if servico is None:
        raise HTTPException(
            503, "O serviço de pagamento não está ligado: a decisão não pode mover o dinheiro."
        )
    repo = contexto.checkout_sem_codigo
    travar = getattr(contexto.pedidos, "travar", None)
    with _TRAVA_EM_MEMORIA if travar is None else nullcontext():
        with contexto.transacao():
            existente = repo.obter_por_chave(chave_idempotencia)
            if existente is not None:
                if existente.id == caso_id and existente.decisao == decisao:
                    pedido_atual = contexto.pedidos.obter(existente.pedido_id)
                    if pedido_atual is None:
                        raise HTTPException(404, "Pedido do caso não encontrado.")
                    return existente, pedido_atual, True
                raise HTTPException(409, "Chave de idempotência já utilizada em outra decisão.")

            caso = repo.obter(caso_id)
            if caso is None:
                raise HTTPException(404, "Caso não encontrado.")
            if travar is not None:
                travar(caso.pedido_id)
            caso = repo.obter(caso_id)
            if caso is None:
                raise HTTPException(404, "Caso não encontrado.")
            if caso.decidido_em is not None:
                if caso.chave_idempotencia == chave_idempotencia and caso.decisao == decisao:
                    pedido_atual = contexto.pedidos.obter(caso.pedido_id)
                    if pedido_atual is None:
                        raise HTTPException(404, "Pedido do caso não encontrado.")
                    return caso, pedido_atual, True
                raise HTTPException(409, "Este caso já foi decidido.")
            if caso.respondido_em is not None:
                raise HTTPException(409, "O cliente já respondeu a este caso.")
            if caso.contatado_em is None:
                raise HTTPException(
                    409, "O cliente ainda não foi contatado sobre este check-out sem código."
                )
            agora = contexto.agora()
            ate = responder_ate(contexto, caso)
            if ate is None or agora <= ate:
                raise HTTPException(409, "O prazo de resposta do cliente ainda não venceu.")

            pedido = contexto.pedidos.obter(caso.pedido_id)
            if pedido is None:
                raise HTTPException(404, "Pedido do caso não encontrado.")
            disputa = contexto.disputas.obter(pedido.id)
            if disputa is not None and not disputa.encerrada:
                raise HTTPException(409, "Há uma disputa aberta para este pedido.")
            if repo.vigente(caso.pedido_id) != caso.check_out_em:
                raise HTTPException(409, "Este caso não está mais vigente.")

            saldos = contexto.ledger.saldos_pedido(pedido.id, pedido.profissional_id)
            valor_em_jogo = saldos.retido + saldos.a_liberar
            total_estorno: int | None = None
            devolver = 0
            if decisao == DECISAO_ESTORNAR:
                total_estorno = reembolso_total_com_custo(
                    contexto.ledger.lancamentos(pedido.id), pedido.id, pedido.profissional_id
                )
                devolver = total_estorno if total_estorno is not None else valor_em_jogo
            alcada = _alcada_do_operador(operador)
            valor_alcada = max(valor_em_jogo, devolver)
            if valor_alcada > alcada:
                raise HTTPException(
                    403,
                    f"Valor da operação ({valor_alcada} centavos) acima da sua alçada "
                    f"({alcada} centavos).",
                )

            resultado = (
                ResultadoDisputa.LIBERAR_TUDO
                if decisao == DECISAO_LIBERAR
                else ResultadoDisputa.REEMBOLSO_TOTAL
            )
            transicao = estados.transicionar(
                pedido,
                Acao.DECIDIR_CHECKOUT_SEM_CODIGO,
                Ator(Papel.MEDIADOR, operador.id),
                agora,
                DecisaoDisputa(resultado, motivo),
                contexto.config.carregar().prazos_pedido,
            )

            # Dinheiro primeiro: se o ledger ou as cobranças recusarem, nada é gravado.
            if decisao == DECISAO_LIBERAR:
                servico.aplicar_dinheiro(
                    contexto,
                    transicao.pedido,
                    operacao=f"checkout_sem_codigo/{caso.id}",
                    devolver_ao_cliente=0,
                    repartir=True,
                    gatilho="decisao_disputa",
                )
            else:
                servico.aplicar_dinheiro(
                    contexto,
                    transicao.pedido,
                    operacao=f"checkout_sem_codigo/{caso.id}",
                    devolver_ao_cliente=devolver,
                    repartir=False,
                    gatilho="decisao_disputa",
                    incluir_custo=total_estorno is not None,
                )

            gravado = contexto.pedidos.salvar(transicao.pedido, transicao.evento)
            if gravado.estado is Estado.CONCLUIDO and gravado.concluido_em is not None:
                if contexto.garantias.obter_garantia(gravado.id) is None:
                    contrato = contexto.contratos.obter_do_pedido(gravado.id)
                    categoria = contrato.categoria_id if contrato else None
                    contexto.garantias.salvar_garantia(
                        gravado.id,
                        abrir_garantia(
                            gravado.concluido_em,
                            categoria,
                            contexto.config.carregar().garantias,
                            dias_de_garantia(contexto, contrato),
                        ),
                    )
            decidido = repo.decidir(
                caso.id, operador.id, decisao, motivo, agora, chave_idempotencia
            )
            if decidido is None:
                raise HTTPException(409, "Este caso já foi decidido ou respondido.")
            valor_auditado = devolver if decisao == DECISAO_ESTORNAR else valor_em_jogo
            admin.auditoria.registrar(
                ator_id=operador.id,
                acao="financeiro.checkout_sem_codigo_decidido",
                entidade="pedidos",
                entidade_id=pedido.id,
                antes={"estado": pedido.estado.value},
                depois={
                    "caso_id": caso.id,
                    "decisao": decisao,
                    "estado": gravado.estado.value,
                    "valor_centavos": valor_auditado,
                    "alcada_centavos": alcada,
                    "chave_idempotencia": chave_idempotencia,
                },
                motivo=motivo,
            )
    return decidido, gravado, False


def abrir_e_avisar(contexto: Any, pedido_id: str) -> None:
    """Depois do check-out gravado. Quem decide se há caso é a função do banco (ou o espelho
    em memória). O contato só conta se o aviso ficou registrado; sem isso o caso aparece na
    fila como "sem contato". Nunca derruba o check-out."""
    try:
        repo = contexto.checkout_sem_codigo
        em = repo.vigente(pedido_id)
        if em is None:
            return
        caso = repo.abrir(pedido_id, em, contexto.agora())
        pedido = contexto.pedidos.obter(pedido_id)
        notificador = contexto.extras.get("notificador")
        if caso.contatado_em or notificador is None or pedido is None:
            return
        ate = prazo_original(contexto, contexto.agora())
        novas = notificador.notificar(
            Evento.CHECKOUT_SEM_CODIGO,
            pedido.cliente_id,
            chave=f"checkout-sem-codigo:{caso.id}",
            pedido_id=pedido_id,
            corpo=(
                "O profissional encerrou o serviço sem o seu Código Final. Confirme a conclusão "
                f"ou relate um problema no pedido até {ate:%d/%m/%Y}. Sem a sua confirmação o "
                "serviço não é considerado confirmado e o valor continua retido (Termos 5.7)."
            ),
        )
        if novas:
            registrar_contato(contexto, caso, "+".join(sorted({r.canal for r in novas})))
    except Exception:  # noqa: BLE001 - o check-out vale; o painel registra o contato à mão
        log.exception("Caso de check-out sem código falhou (%s)", pedido_id)


def gancho_checkout_sem_codigo(antes: Pedido, depois: Pedido, acao: Acao, contexto: Any) -> None:
    if acao is Acao.FAZER_CHECK_OUT:
        contexto.depois_do_commit(partial(abrir_e_avisar, contexto, depois.id))
    elif acao is Acao.CONFIRMAR_CONCLUSAO:  # na mesma transação da confirmação
        contexto.checkout_sem_codigo.responder(depois.id, CONFIRMOU, contexto.agora())
