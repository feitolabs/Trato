"""Disputas: fila, detalhe (evidências e linha do tempo) e decisão com alçada e segunda pessoa.

Nenhuma regra nova de dinheiro mora aqui. Quem decide é `disputas/` (alçada, segunda pessoa,
divisão do valor), quem muda o pedido é `pedidos/estados.py` e quem move o espelho é o ledger
(`financeiro/ledger.py`). Caminho A (D15): o Trato só ESPELHA; a devolução real ao cliente é
feita no parceiro de pagamento, fora desta API.
"""

from __future__ import annotations

from collections.abc import Sequence
from typing import Any

from fastapi import APIRouter, Depends, HTTPException, Query

from trato import disputas
from trato.api.admin.contexto import AdminContexto, Operador, exigir, obter_admin
from trato.api.admin.modelos import (
    AprovarDisputaIn,
    DecidirDisputaIn,
    DisputaDetalheOut,
    DisputaResumoOut,
    DivisaoOut,
    EventoLinhaDoTempoOut,
    EvidenciaOut,
    Pagina,
    PessoaOut,
)
from trato.api.admin.papeis import PapelEquipe, Permissao
from trato.api.admin.rotas_pagamentos import lancamento_admin_out
from trato.api.contexto import Contexto, obter_contexto
from trato.disputas import Ator, Decisao, Disputa, Estado, Resultado
from trato.financeiro.ledger import CUSTODIA, Lancamento, Livro, estornar_pedido, repartir_custodia
from trato.garantias import abrir_garantia
from trato.pedidos import estados
from trato.pedidos.estados import Acao, Pedido
from trato.pedidos.estados import Ator as AtorPedido
from trato.pedidos.estados import Papel as PapelPedido
from trato.persistencia.comum import para_json

router = APIRouter(prefix="/v1/admin/disputas", tags=["admin: disputas"])


def _todas(contexto: Contexto) -> list[tuple[str, Disputa]]:
    """Todas as disputas. O repositório de disputas ainda não tem listagem: a memória expõe o
    dicionário (em modo postgres elas também estão em memória até a F3.6 ser aplicada)."""
    repo = contexto.disputas
    if hasattr(repo, "listar"):
        return list(repo.listar())  # type: ignore[attr-defined]
    return list(getattr(repo, "_itens", {}).items())


def _resumo(pedido_id: str, d: Disputa, contexto: Contexto) -> DisputaResumoOut:
    return DisputaResumoOut(
        pedido_id=pedido_id,
        estado=d.estado.value,
        motivo=d.motivo.value,
        valor_congelado_centavos=d.valor_congelado,
        aberta_em=d.aberta_em,
        resposta_ate=d.prazos.resposta_ate,
        decisao_ate=d.prazos.decisao_ate,
        atrasada=d.atrasada(contexto.agora()),
        sem_resposta=d.sem_resposta,
    )


def _sem_codigos(valor: Any) -> Any:
    """Tira da prova qualquer campo `codigo*` (os códigos de check-in/out nunca saem)."""
    if isinstance(valor, dict):
        return {k: _sem_codigos(v) for k, v in valor.items() if "codigo" not in k}
    if isinstance(valor, list):
        return [_sem_codigos(v) for v in valor]
    return valor


def _detalhe(
    contexto: Contexto,
    admin: AdminContexto,
    pedido_id: str,
    d: Disputa,
    novos: Sequence[Lancamento] = (),
) -> DisputaDetalheOut:
    pedido = contexto.pedidos.obter(pedido_id)
    eventos = contexto.pedidos.eventos(pedido_id)
    ids = [i for i in ((pedido.cliente_id, pedido.profissional_id) if pedido else ()) if i]
    nomes = admin.usuarios.nomes(ids)
    linha = [
        EventoLinhaDoTempoOut(
            em=e.em,
            tipo="pedido",
            acao=e.acao.value,
            de=e.de.value,
            para=e.para.value,
            ator_papel=e.ator.papel.value,
            ator_id=e.ator.id,
        )
        for e in eventos
    ]
    marcos = [
        (d.aberta_em, "disputa_aberta", None),
        (d.respondida_em, "disputa_respondida", None),
        (d.decidido_em, "decisao_registrada", d.decidido_por),
        (d.aprovado_em, "decisao_aprovada", d.aprovado_por),
    ]
    linha += [
        EventoLinhaDoTempoOut(em=em, tipo="disputa", acao=acao, ator_id=ator)
        for em, acao, ator in marcos
        if em is not None
    ]
    linha.sort(key=lambda e: e.em)
    evidencias = [
        EvidenciaOut(
            origem=e.acao.value,
            em=e.em,
            ator_papel=e.ator.papel.value,
            ator_id=e.ator.id,
            dados=_sem_codigos(para_json(e.prova)),
        )
        for e in eventos
        if e.prova is not None
    ]
    resumo = _resumo(pedido_id, d, contexto)
    return DisputaDetalheOut(
        **resumo.model_dump(),
        estado_pedido=pedido.estado.value if pedido else None,
        cliente=PessoaOut(
            id=pedido.cliente_id if pedido else None,
            nome=nomes.get(pedido.cliente_id) if pedido else None,
        ),
        profissional=PessoaOut(
            id=pedido.profissional_id if pedido else None,
            nome=nomes.get(pedido.profissional_id or "") if pedido else None,
        ),
        respondida_em=d.respondida_em,
        decisao=d.decisao.resultado.value if d.decisao else None,
        percentual_cliente_bps=d.decisao.percentual_cliente_bps if d.decisao else None,
        decidido_por=d.decidido_por,
        decidido_em=d.decidido_em,
        aprovado_por=d.aprovado_por,
        aprovado_em=d.aprovado_em,
        aguardando_segunda_pessoa=d.estado is Estado.AGUARDANDO_APROVACAO,
        divisao=DivisaoOut(
            para_profissional_centavos=d.divisao.para_profissional,
            para_cliente_centavos=d.divisao.para_cliente,
            retido_centavos=d.divisao.retido,
        )
        if d.divisao
        else None,
        evidencias=evidencias,
        linha_do_tempo=linha,
        lancamentos_da_decisao=[lancamento_admin_out(n) for n in novos],
    )


def _obter(contexto: Contexto, pedido_id: str) -> Disputa:
    disputa = contexto.disputas.obter(pedido_id)
    if disputa is None:
        raise HTTPException(404, "Este pedido não tem disputa.")
    return disputa


@router.get("", response_model=Pagina[DisputaResumoOut], summary="Fila de disputas")
def fila(
    estado: Estado | None = Query(None, description="Padrão: tudo que não está decidido."),
    limite: int = Query(20, ge=1, le=100),
    deslocamento: int = Query(0, ge=0),
    _: Operador = Depends(exigir(Permissao.DISPUTAS_VER)),
    contexto: Contexto = Depends(obter_contexto),
) -> Pagina[DisputaResumoOut]:
    achadas = [
        (pid, d)
        for pid, d in _todas(contexto)
        if (d.estado is estado if estado else d.estado is not Estado.DECIDIDA)
    ]
    achadas.sort(key=lambda par: par[1].prazos.decisao_ate)  # o prazo mais curto primeiro
    pagina = achadas[deslocamento : deslocamento + limite]
    return Pagina(
        itens=[_resumo(pid, d, contexto) for pid, d in pagina],
        total=len(achadas),
        limite=limite,
        deslocamento=deslocamento,
    )


@router.get("/{pedido_id}", response_model=DisputaDetalheOut, summary="Detalhe da disputa")
def detalhe(
    pedido_id: str,
    _: Operador = Depends(exigir(Permissao.DISPUTAS_VER)),
    admin: AdminContexto = Depends(obter_admin),
    contexto: Contexto = Depends(obter_contexto),
) -> DisputaDetalheOut:
    return _detalhe(contexto, admin, pedido_id, _obter(contexto, pedido_id))


def _planejar_dinheiro(contexto: Contexto, pedido: Pedido, d: Disputa) -> list[Lancamento]:
    """Lançamentos do espelho para a decisão, com as funções que o ledger já tem.

    Chaves determinísticas (`disputa/<pedido>/...`): refazer a chamada depois de uma falha no
    meio não duplica nada (se já estão no ledger, não planeja de novo).
    """
    prefixo = f"disputa/{pedido.id}/"
    existentes = contexto.ledger.lancamentos(pedido.id)
    if any(i.id.startswith(prefixo) for i in existentes) or d.divisao is None:
        return []
    livro = Livro()
    if existentes:
        livro.lancar_varios(existentes)
    antes = len(livro.lancamentos)
    agora = contexto.agora()
    if d.divisao.para_cliente > 0:
        estornar_pedido(livro, pedido.id, d.divisao.para_cliente, f"{prefixo}est", agora)
    restante = livro.saldo(CUSTODIA, pedido.id)
    if d.divisao.para_profissional > 0 and restante > 0:
        if contexto.taxa is None:
            raise HTTPException(503, "A taxa do Trato ainda não está ligada à configuração.")
        taxa = contexto.taxa.calcular(restante)
        repartir_custodia(
            livro, pedido.id, pedido.profissional_id or "", taxa, f"{prefixo}rep", agora
        )
    return list(livro.lancamentos[antes:])


def _efetivar(
    contexto: Contexto,
    admin: AdminContexto,
    operador: Operador,
    pedido_id: str,
    decidida: Disputa,
    justificativa: str,
) -> DisputaDetalheOut:
    """Disputa já DECIDIDA: muda o pedido, move o espelho, grava a disputa e a auditoria.

    Tudo que pode recusar (estado do pedido, saldo do ledger) roda ANTES de gravar qualquer coisa.
    """
    assert decidida.decisao is not None  # noqa: S101 - DECIDIDA sempre tem decisão
    pedido = contexto.pedidos.obter(pedido_id)
    if pedido is None:
        raise HTTPException(404, "Pedido da disputa não encontrado.")
    transicao = estados.transicionar(
        pedido,
        Acao.DECIDIR_DISPUTA,
        AtorPedido(PapelPedido.MEDIADOR, decidida.decidido_por or operador.id),
        contexto.agora(),
        estados.DecisaoDisputa(
            estados.ResultadoDisputa(decidida.decisao.resultado.value), justificativa
        ),
        contexto.config.carregar().prazos_pedido,
    )
    novos = _planejar_dinheiro(contexto, pedido, decidida)
    if novos:
        contexto.ledger.lancar_varios(novos)
    gravado = contexto.pedidos.salvar(transicao.pedido, transicao.evento)
    if gravado.estado is estados.Estado.CONCLUIDO and gravado.concluido_em is not None:
        if contexto.garantias.obter_garantia(gravado.id) is None:
            contrato = contexto.contratos.obter_do_pedido(gravado.id)
            categoria = contrato.categoria_id if contrato else None
            contexto.garantias.salvar_garantia(
                gravado.id,
                abrir_garantia(
                    gravado.concluido_em, categoria, contexto.config.carregar().garantias
                ),
            )
    contexto.disputas.salvar(pedido_id, decidida)
    div = decidida.divisao
    admin.auditoria.registrar(
        ator_id=operador.id,
        acao="financeiro.disputa_decidida",
        entidade="pedidos",
        entidade_id=pedido_id,
        antes={"estado_pedido": pedido.estado.value},
        depois={
            "resultado": decidida.decisao.resultado.value,
            "estado_pedido": gravado.estado.value,
            "decidido_por": decidida.decidido_por,
            "aprovado_por": decidida.aprovado_por,
            "para_profissional_centavos": div.para_profissional if div else None,
            "para_cliente_centavos": div.para_cliente if div else None,
            "retido_centavos": div.retido if div else None,
            "lancamentos": [n.id for n in novos],
        },
        motivo=justificativa,
    )
    return _detalhe(contexto, admin, pedido_id, decidida, novos)


@router.post(
    "/{pedido_id}/decisao",
    response_model=DisputaDetalheOut,
    summary="Decidir a disputa",
    description=(
        "Acima da alçada do decisor (`equipe.alcada_centavos`; vazia = 0) a decisão fica "
        "`aguardando_aprovacao` e outra pessoa precisa aprová-la em `/aprovacao`. Dentro da "
        "alçada, vale na hora: muda o pedido e move o espelho do ledger. Refazer a chamada "
        "depois de decidida responde 409 e não duplica lançamentos."
    ),
)
def decidir(
    pedido_id: str,
    corpo: DecidirDisputaIn,
    operador: Operador = Depends(exigir(Permissao.DISPUTAS_DECIDIR)),
    admin: AdminContexto = Depends(obter_admin),
    contexto: Contexto = Depends(obter_contexto),
) -> DisputaDetalheOut:
    disputa = _obter(contexto, pedido_id)
    agora = contexto.agora()
    if disputa.estado is Estado.ABERTA and agora > disputa.prazos.resposta_ate:
        disputa = disputa.encerrar_sem_resposta(Ator.SISTEMA, agora)  # profissional não respondeu
    decisao = Decisao(
        Resultado(corpo.resultado.value), corpo.percentual_cliente_bps, corpo.valor_cliente_centavos
    )
    alcada = operador.membro.alcada_centavos or 0
    nova = disputa.decidir(Ator.ANALISTA, operador.id, decisao, agora, alcada)
    if nova.estado is Estado.DECIDIDA:
        return _efetivar(contexto, admin, operador, pedido_id, nova, corpo.justificativa)
    contexto.disputas.salvar(pedido_id, nova)
    admin.auditoria.registrar(
        ator_id=operador.id,
        acao="financeiro.disputa_decisao_proposta",
        entidade="pedidos",
        entidade_id=pedido_id,
        depois={
            "resultado": decisao.resultado.value,
            "valor_congelado_centavos": nova.valor_congelado,
            "alcada_centavos": alcada,
        },
        motivo=corpo.justificativa,
    )
    return _detalhe(contexto, admin, pedido_id, nova)


@router.post(
    "/{pedido_id}/aprovacao",
    response_model=DisputaDetalheOut,
    summary="Segunda pessoa aprova a decisão acima da alçada",
    description=(
        "Precisa ser outra pessoa, com papel de segunda pessoa (líder de suporte ou "
        "administrador). Só o administrador aprova acima da própria alçada."
    ),
)
def aprovar(
    pedido_id: str,
    corpo: AprovarDisputaIn,
    operador: Operador = Depends(exigir(Permissao.DISPUTAS_SEGUNDA_PESSOA)),
    admin: AdminContexto = Depends(obter_admin),
    contexto: Contexto = Depends(obter_contexto),
) -> DisputaDetalheOut:
    disputa = _obter(contexto, pedido_id)
    aprovada = disputa.aprovar(Ator.ANALISTA, operador.id, contexto.agora())
    alcada = operador.membro.alcada_centavos or 0
    if operador.membro.papel is not PapelEquipe.ADMINISTRADOR and alcada < aprovada.valor_congelado:
        raise disputas.AlcadaInvalida("O valor da disputa está acima da alçada de quem aprova.")
    return _efetivar(contexto, admin, operador, pedido_id, aprovada, corpo.justificativa)
