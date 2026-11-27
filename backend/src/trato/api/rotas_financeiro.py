"""Consulta de saldo e extrato. Tudo sai do ledger (nada é guardado); o app só mostra."""

from __future__ import annotations

from collections.abc import Sequence
from datetime import datetime
from typing import Literal

from fastapi import APIRouter, Depends, HTTPException, Query, Request, Response

from trato.api.admin.papeis import Permissao
from trato.api.auth import PapelUsuario, Usuario
from trato.api.contexto import Contexto, exigir_papel, obter_contexto, usuario_atual
from trato.api.liberacao import fatos_da_liberacao
from trato.api.modelos import (
    ContaOut,
    ExtratoOut,
    LancamentoOut,
    LiberacaoPrevistaOut,
    SaldoPedidoOut,
    SaldoProfissionalOut,
)
from trato.api.servicos import carregar_pedido
from trato.financeiro import extrato_profissional, periodo, recibo_pedido
from trato.financeiro.ledger import CUSTODIA, Conta, Lancamento, a_liberar, liberado
from trato.pedidos.estados import Estado, Pedido
from trato.persistencia.comum import como_uuid
from trato.rotinas.regras import ConfigRotinas, instante_liberacao, regra_de_liberacao

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
        liberacao_prevista_em=liberacao_prevista(contexto, pedido),
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
    usuario: Usuario = Depends(exigir_papel(PapelUsuario.CLIENTE, PapelUsuario.PROFISSIONAL)),
    contexto: Contexto = Depends(obter_contexto),
) -> SaldoProfissionalOut:
    previstas = _liberacoes_previstas(contexto, usuario.id)
    datas = [p.liberacao_prevista_em for p in previstas if p.liberacao_prevista_em is not None]
    return SaldoProfissionalOut(
        a_liberar_centavos=contexto.ledger.saldo_da_conta(a_liberar(usuario.id)),
        liberado_centavos=contexto.ledger.saldo_da_conta(liberado(usuario.id)),
        retido_centavos=_retido_do_profissional(contexto, usuario.id),
        proxima_liberacao_em=min(datas) if datas else None,
        liberacoes_previstas=previstas,
    )


def _retido_do_profissional(contexto: Contexto, profissional_id: str) -> int:
    """Dinheiro pago e retido (custódia) dos pedidos deste profissional, até ser liberado.
    Só leitura: nunca falha a carteira."""
    try:
        por_pedido: dict[str, int] = {}
        for item in contexto.ledger.lancamentos():
            if item.credito == CUSTODIA:
                por_pedido[item.pedido_id] = por_pedido.get(item.pedido_id, 0) + item.valor
            if item.debito == CUSTODIA:
                por_pedido[item.pedido_id] = por_pedido.get(item.pedido_id, 0) - item.valor
        total = 0
        for pedido_id, valor in por_pedido.items():
            if valor <= 0:
                continue
            pedido = contexto.pedidos.obter(pedido_id)
            if pedido is not None and pedido.profissional_id == profissional_id:
                total += valor
        return total
    except Exception:  # noqa: BLE001 - campo opcional
        return 0


def _regra_liberacao(contexto: Contexto) -> ConfigRotinas:
    cfg = contexto.config.carregar()
    prazo, congelamento = regra_de_liberacao(
        cfg.prazo_liberacao_dias, cfg.disputas.prazo_congelar_repasse_horas
    )
    return ConfigRotinas(
        prazo_liberacao=prazo,
        janela_congelamento_repasse=congelamento,
        liberacao_espera_congelamento=True,
    )


def _quando_libera(contexto: Contexto, pedido: Pedido, regra: ConfigRotinas) -> datetime | None:
    """Sem data enquanto a decisão está contestada (ou sem prazo conhecido)."""
    cancelado = pedido.estado is Estado.CANCELADO
    if pedido.concluido_em is None and not cancelado:
        return None
    fatos = fatos_da_liberacao(contexto, pedido)
    base = fatos.retencao_em if cancelado else pedido.concluido_em
    if base is None or fatos.relato or fatos.contestacao_pendente or fatos.prazo_desconhecido:
        return None
    return instante_liberacao(base, regra, fatos.confirmado, fatos.contestar_ate)


def liberacao_prevista(contexto: Contexto, pedido: Pedido) -> datetime | None:
    """Quando o valor do pedido concluído é liberado (mesma regra da rotina). Nunca levanta."""
    try:
        return _quando_libera(contexto, pedido, _regra_liberacao(contexto))
    except Exception:  # noqa: BLE001 - texto de aviso: sem data, o aviso sai sem ela
        return None


def _liberacoes_previstas(contexto: Contexto, profissional_id: str) -> list[LiberacaoPrevistaOut]:
    """Um item por pedido com valor 'a liberar'. Só leitura: nunca falha a carteira.

    Data = `instante_liberacao` (a mesma regra da rotina de liberação). Pedido ainda não
    concluído, decisão contestada ou prazo não publicado: data `None`.
    """
    try:
        regra = _regra_liberacao(contexto)
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
            quando = None if pedido is None else _quando_libera(contexto, pedido, regra)
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
    como: Literal["cliente", "profissional"] | None = Query(
        None, description="Papel do extrato (cliente ou profissional)."
    ),
    usuario: Usuario = Depends(exigir_papel(PapelUsuario.CLIENTE, PapelUsuario.PROFISSIONAL)),
    contexto: Contexto = Depends(obter_contexto),
) -> ExtratoOut:
    modo_profissional = como == "profissional" or (
        como is None and usuario.papel is PapelUsuario.PROFISSIONAL
    )
    if modo_profissional:
        minhas = {a_liberar(usuario.id), liberado(usuario.id)}
        itens = [
            i for i in contexto.ledger.lancamentos() if i.debito in minhas or i.credito in minhas
        ]
    else:
        pedidos = {p.id for p in contexto.pedidos.listar_do_usuario(usuario.id, True)}
        itens = [i for i in contexto.ledger.lancamentos() if i.pedido_id in pedidos]
    return _extrato(itens, limite, deslocamento)


def _numeros_dos_pedidos(contexto: Contexto, ids: Sequence[str]) -> dict[str, int]:
    """Número curto do pedido (o mesmo `PED-<número>` do painel). Só leitura; sem banco, vazio."""
    banco = contexto.extras.get("banco")
    if banco is None or not ids:
        return {}
    try:
        validos = [u for u in (como_uuid(i) for i in ids) if u is not None]
        with banco.transacao() as con:
            linhas = con.execute(
                "select id, numero from public.pedidos where id = any(%s)", (validos,)
            ).fetchall()
        return {str(linha["id"]): int(linha["numero"]) for linha in linhas if linha["numero"]}
    except Exception:  # noqa: BLE001 - sem o número, o PDF usa o início do id
        return {}


def _nomes_das_categorias(request: Request) -> dict[str, str]:
    modulo = getattr(request.app.state, "modulo_profissional", None)
    if modulo is None:
        return {}
    try:
        return {c.id: c.nome for c in modulo.catalogo.categorias_publicas()}
    except Exception:  # noqa: BLE001 - sem catálogo, a coluna fica vazia
        return {}


@router.get(
    "/profissionais/me/extrato.pdf",
    summary="Baixar extrato mensal do profissional em PDF",
    responses={200: {"content": {"application/pdf": {}}}},
)
def baixar_meu_extrato_pdf(
    request: Request,
    mes: str | None = Query(
        None, description="Mês no formato AAAA-MM (horário de Brasília). Padrão: mês atual."
    ),
    usuario: Usuario = Depends(exigir_papel(PapelUsuario.CLIENTE, PapelUsuario.PROFISSIONAL)),
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
    ids = list(dict.fromkeys(lin.pedido_id for lin in extrato.linhas))
    numeros = _numeros_dos_pedidos(contexto, ids)
    nomes_categorias = _nomes_das_categorias(request)
    rotulos: dict[str, tuple[int | None, str]] = {}
    categorias: dict[str, str] = {}
    for pedido_id in ids:
        dados = contexto.pedidos.dados_do_pedido(pedido_id)
        rotulos[pedido_id] = (numeros.get(pedido_id), dados.titulo if dados is not None else "")
        if dados is not None and dados.categoria_id in nomes_categorias:
            categorias[pedido_id] = nomes_categorias[dados.categoria_id]
    detalhe = contexto.usuarios.detalhe(usuario.id)
    nome = detalhe.nome if detalhe is not None and detalhe.nome else "Profissional"
    # Documento do PRÓPRIO profissional (comprovante de ganhos); sem cadastro, sem a linha.
    buscar_cpf = getattr(contexto.usuarios, "cpf_do_usuario", None)
    conteudo = extrato_profissional.pdf(
        extrato,
        nome,
        rotulos,
        agora,
        documento=buscar_cpf(usuario.id) if buscar_cpf else None,
        categorias=categorias,
    )
    arquivo = f"trato_extrato_{ano:04d}_{numero:02d}.pdf"
    return Response(
        content=conteudo,
        media_type="application/pdf",
        headers={"Content-Disposition": f'attachment; filename="{arquivo}"'},
    )


@router.get(
    "/pedidos/{pedido_id}/recibo.pdf",
    summary="Baixar o comprovante de serviço do pedido concluído em PDF",
    responses={200: {"content": {"application/pdf": {}}}},
)
def baixar_recibo_do_pedido(
    pedido_id: str,
    request: Request,
    usuario: Usuario = Depends(exigir_papel(PapelUsuario.CLIENTE, PapelUsuario.PROFISSIONAL)),
    contexto: Contexto = Depends(obter_contexto),
) -> Response:
    from trato.api.rotas_profissional_cadastro import _nome_abreviado

    pedido = carregar_pedido(contexto, pedido_id, usuario)  # quem não é parte recebe 404
    if pedido.estado is not Estado.CONCLUIDO:
        raise HTTPException(409, "O comprovante fica disponível após a conclusão do serviço.")
    contrato = contexto.contratos.obter_do_pedido(pedido.id)
    dados_pedido = contexto.pedidos.dados_do_pedido(pedido.id)

    def nome(uid: str | None) -> str:
        detalhe = contexto.usuarios.detalhe(uid) if uid else None
        return (_nome_abreviado(detalhe.nome) if detalhe is not None else None) or ""

    categoria_id = (dados_pedido.categoria_id if dados_pedido else None) or (
        contrato.categoria_id if contrato else None
    )
    categoria = _nomes_das_categorias(request).get(str(categoria_id), "") if categoria_id else ""
    saldo = contexto.ledger.saldos_pedido(pedido.id, pedido.profissional_id)
    numero = _numeros_dos_pedidos(contexto, [pedido.id]).get(pedido.id)
    codigo = f"PED-{numero}" if numero is not None else pedido.id[:8]
    dados = recibo_pedido.DadosRecibo(
        codigo=codigo,
        titulo=dados_pedido.titulo if dados_pedido else "",
        categoria=categoria,
        concluido_em=pedido.concluido_em,
        cliente_nome=nome(pedido.cliente_id),
        profissional_nome=nome(pedido.profissional_id),
        valor_servico_centavos=contrato.valor_centavos if contrato else 0,
        cliente_pagou_centavos=saldo.cliente_pagou,
        taxa_trato_centavos=saldo.taxa_trato,
        liquido_profissional_centavos=saldo.a_liberar + saldo.liberado,
    )
    quem = "cliente" if usuario.id == pedido.cliente_id else "profissional"
    conteudo = recibo_pedido.pdf(dados, quem, contexto.agora())
    return Response(
        content=conteudo,
        media_type="application/pdf",
        headers={
            "Content-Disposition": f'attachment; filename="recibo-trato-{codigo}.pdf"',
            "Cache-Control": "no-store",
        },
    )
