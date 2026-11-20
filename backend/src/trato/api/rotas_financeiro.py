"""Consulta de saldo e extrato. Tudo sai do ledger (nada é guardado); o app só mostra."""

from __future__ import annotations

from collections.abc import Sequence
from datetime import timedelta

from fastapi import APIRouter, Depends, HTTPException, Query, Request, Response

from trato.api.admin.papeis import Permissao
from trato.api.auth import PapelUsuario, Usuario
from trato.api.contexto import Contexto, exigir_papel, obter_contexto, usuario_atual
from trato.api.modelos import (
    ContaOut,
    ExtratoOut,
    LancamentoOut,
    LiberacaoPrevistaOut,
    SaldoPedidoOut,
    SaldoProfissionalOut,
)
from trato.api.servicos import carregar_pedido
from trato.financeiro import extrato_profissional, periodo
from trato.financeiro.ledger import Conta, Lancamento, a_liberar, liberado
from trato.rotinas.regras import ConfigRotinas, instante_liberacao

router = APIRouter(prefix="/v1", tags=["financeiro"])

LIMITE_MAXIMO = 100


def _conta_out(conta: Conta) -> ContaOut:
    return ContaOut(tipo=conta.tipo.value, titular=conta.titular)


def _lancamento_out(item: Lancamento) -> LancamentoOut:
    return LancamentoOut(
        id=item.id,
        pedido_id=item.pedido_id,
        tipo=item.tipo.value,
        valor_centavos=item.valor,
        data=item.data,
        debito=_conta_out(item.debito),
        credito=_conta_out(item.credito),
        estorno_de=item.estorno_de,
    )


def _extrato(itens: Sequence[Lancamento], limite: int, deslocamento: int) -> ExtratoOut:
    """Mais novos primeiro (empate de data: o gravado por último vem antes)."""
    ordem = sorted(enumerate(itens), key=lambda par: (par[1].data, par[0]), reverse=True)
    pagina = [_lancamento_out(i) for _, i in ordem[deslocamento : deslocamento + limite]]
    return ExtratoOut(itens=pagina, total=len(itens), limite=limite, deslocamento=deslocamento)


@router.get(
    "/pedidos/{pedido_id}/saldo",
    response_model=SaldoPedidoOut,
    summary="Saldo do pedido (retido, a liberar, liberado)",
)
def saldo_do_pedido(
    pedido_id: str,
    request: Request,
    usuario: Usuario = Depends(usuario_atual),
    contexto: Contexto = Depends(obter_contexto),
) -> SaldoPedidoOut:
    pedido = carregar_pedido(
        contexto,
        pedido_id,
        usuario,
        request=request,
        equipe=(Permissao.PAGAMENTOS_VER,),
        consulta="saldo",
    )
    saldo = contexto.ledger.saldos_pedido(pedido.id, pedido.profissional_id)
    return SaldoPedidoOut(
        pedido_id=pedido.id,
        cliente_pagou_centavos=saldo.cliente_pagou,
        retido_centavos=saldo.retido,
        a_liberar_centavos=saldo.a_liberar,
        liberado_centavos=saldo.liberado,
    )


@router.get(
    "/pedidos/{pedido_id}/extrato", response_model=ExtratoOut, summary="Lançamentos do pedido"
)
def extrato_do_pedido(
    pedido_id: str,
    request: Request,
    limite: int = Query(20, ge=1, le=LIMITE_MAXIMO),
    deslocamento: int = Query(0, ge=0),
    usuario: Usuario = Depends(usuario_atual),
    contexto: Contexto = Depends(obter_contexto),
) -> ExtratoOut:
    pedido = carregar_pedido(
        contexto,
        pedido_id,
        usuario,
        request=request,
        equipe=(Permissao.PAGAMENTOS_VER,),
        consulta="extrato",
    )
    return _extrato(contexto.ledger.lancamentos(pedido.id), limite, deslocamento)


@router.get(
    "/profissionais/me/saldo",
    response_model=SaldoProfissionalOut,
    summary="Carteira do profissional (a liberar e liberado)",
)
def saldo_do_profissional(
    usuario: Usuario = Depends(exigir_papel(PapelUsuario.PROFISSIONAL)),
    contexto: Contexto = Depends(obter_contexto),
) -> SaldoProfissionalOut:
    previstas = _liberacoes_previstas(contexto, usuario.id)
    datas = [p.liberacao_prevista_em for p in previstas if p.liberacao_prevista_em is not None]
    return SaldoProfissionalOut(
        a_liberar_centavos=contexto.ledger.saldo_da_conta(a_liberar(usuario.id)),
        liberado_centavos=contexto.ledger.saldo_da_conta(liberado(usuario.id)),
        proxima_liberacao_em=min(datas) if datas else None,
        liberacoes_previstas=previstas,
    )


def _liberacoes_previstas(contexto: Contexto, profissional_id: str) -> list[LiberacaoPrevistaOut]:
    """Um item por pedido com valor 'a liberar'. Só leitura: nunca falha a carteira.

    Data = `instante_liberacao` (a mesma regra da rotina de liberação): conclusão + o prazo da
    configuração (`prazo_liberacao_dias`; sem ele, a janela de congelamento da disputa), e nunca
    antes da janela de congelamento. Pedido ainda não concluído: data `None`.
    """
    try:
        cfg = contexto.config.carregar()
        congelamento = timedelta(hours=cfg.disputas.prazo_congelar_repasse_horas)
        prazo = (
            timedelta(days=cfg.prazo_liberacao_dias)
            if cfg.prazo_liberacao_dias is not None
            else congelamento
        )
        regra = ConfigRotinas(
            prazo_liberacao=prazo,
            janela_congelamento_repasse=congelamento,
            liberacao_espera_congelamento=True,
        )
        conta = a_liberar(profissional_id)
        por_pedido: dict[str, int] = {}
        for item in contexto.ledger.lancamentos():
            if item.credito == conta:
                por_pedido[item.pedido_id] = por_pedido.get(item.pedido_id, 0) + item.valor
            if item.debito == conta:
                por_pedido[item.pedido_id] = por_pedido.get(item.pedido_id, 0) - item.valor
        saida = []
        for pedido_id, valor in por_pedido.items():
            if valor <= 0:
                continue
            pedido = contexto.pedidos.obter(pedido_id)
            quando = (
                instante_liberacao(pedido.concluido_em, regra)
                if pedido is not None and pedido.concluido_em is not None
                else None
            )
            saida.append(
                LiberacaoPrevistaOut(
                    pedido_id=pedido_id, valor_centavos=valor, liberacao_prevista_em=quando
                )
            )
        com_data = sorted(
            (p for p in saida if p.liberacao_prevista_em is not None),
            key=lambda p: p.liberacao_prevista_em,  # type: ignore[arg-type,return-value]
        )
        return com_data + [p for p in saida if p.liberacao_prevista_em is None]
    except Exception:  # noqa: BLE001 - campo opcional: a carteira não pode quebrar por ele
        return []


@router.get(
    "/extrato",
    response_model=ExtratoOut,
    summary="Meu extrato",
    description=(
        "Profissional: lançamentos nas contas dele. Cliente: lançamentos dos pedidos dele."
    ),
)
def meu_extrato(
    limite: int = Query(20, ge=1, le=LIMITE_MAXIMO),
    deslocamento: int = Query(0, ge=0),
    usuario: Usuario = Depends(exigir_papel(PapelUsuario.CLIENTE, PapelUsuario.PROFISSIONAL)),
    contexto: Contexto = Depends(obter_contexto),
) -> ExtratoOut:
    if usuario.papel is PapelUsuario.PROFISSIONAL:
        minhas = {a_liberar(usuario.id), liberado(usuario.id)}
        itens = [
            i for i in contexto.ledger.lancamentos() if i.debito in minhas or i.credito in minhas
        ]
    else:
        pedidos = {p.id for p in contexto.pedidos.listar_do_usuario(usuario.id, True)}
        itens = [i for i in contexto.ledger.lancamentos() if i.pedido_id in pedidos]
    return _extrato(itens, limite, deslocamento)


@router.get(
    "/profissionais/me/extrato.pdf",
    summary="Baixar extrato mensal do profissional em PDF",
    responses={200: {"content": {"application/pdf": {}}}},
)
def baixar_meu_extrato_pdf(
    mes: str | None = Query(
        None, description="Mês no formato AAAA-MM (horário de Brasília). Padrão: mês atual."
    ),
    usuario: Usuario = Depends(exigir_papel(PapelUsuario.PROFISSIONAL)),
    contexto: Contexto = Depends(obter_contexto),
) -> Response:
    agora = contexto.agora()
    if mes is not None:
        try:
            ano, numero = periodo.ler_mes(mes.strip())
        except ValueError as erro:
            raise HTTPException(422, str(erro)) from None
    else:
        ano, numero = periodo.mes_de(agora)
    desde, ate = periodo.mes(ano, numero)
    extrato = extrato_profissional.montar(contexto.ledger.lancamentos(), usuario.id, desde, ate)
    rotulos: dict[str, tuple[int | None, str]] = {}
    for lin in extrato.linhas:
        if lin.pedido_id in rotulos:
            continue
        dados = contexto.pedidos.dados_do_pedido(lin.pedido_id)
        rotulos[lin.pedido_id] = (None, dados.titulo if dados is not None else "")
    detalhe = contexto.usuarios.detalhe(usuario.id)
    nome = detalhe.nome if detalhe is not None and detalhe.nome else "Profissional"
    conteudo = extrato_profissional.pdf(extrato, nome, rotulos, agora)
    arquivo = f"trato_extrato_{ano:04d}_{numero:02d}.pdf"
    return Response(
        content=conteudo,
        media_type="application/pdf",
        headers={"Content-Disposition": f'attachment; filename="{arquivo}"'},
    )
