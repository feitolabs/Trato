"""Financeiro do painel: contestações, alertas, consulta ao provedor (só leitura de dinheiro).

Nada aqui move dinheiro nem marca "pago": o espelho só muda pelo webhook assinado (D13). As rotas
mostram o que o provedor avisou e o que travou, para o financeiro agir.
"""

from __future__ import annotations

import csv
import io
from dataclasses import asdict
from datetime import date, datetime, timedelta
from typing import Any

from fastapi import APIRouter, Depends, HTTPException, Query, Request
from pydantic import BaseModel, Field

from trato.api.admin.contexto import AdminContexto, Operador, exigir, obter_admin
from trato.api.admin.modelos import ComMotivo
from trato.api.admin.papeis import Permissao
from trato.api.admin.rotas_relatorios import guardar_para_baixar
from trato.api.contexto import Contexto, obter_contexto
from trato.financeiro import extrato_profissional, fechamento, periodo
from trato.financeiro.conciliacao import conciliar
from trato.financeiro.contestacoes import Contestacao, StatusContestacao
from trato.pedidos.estados import Estado

router = APIRouter(prefix="/v1/admin/financeiro", tags=["admin: financeiro"])

CHAVE_MINUTOS_PARADO = "alerta_pagamento_parado_minutos"
MINUTOS_PARADO_PADRAO = 30  # vale até a definição ser aprovada em Configurações
TIPOS_FALHA_REPASSE = ("transfer.reversed", "payout.failed")


# --- Modelos ------------------------------------------------------------------------------------


class ContestacaoOut(BaseModel):
    id: str
    pedido_id: str | None
    pedido_numero: int | None = None
    pedido_titulo: str | None = None
    cobranca_id: str | None
    valor_centavos: int
    motivo: str | None
    motivo_legivel: str
    status: str
    prazo_provas: datetime | None
    horas_para_prazo: int | None
    aberta_em: datetime
    encerrada_em: datetime | None
    repasse_liberado: bool


class PagamentoParadoOut(BaseModel):
    cobranca_id: str
    pedido_id: str
    pedido_numero: int | None = None
    valor_centavos: int
    meio: str
    criada_em: datetime
    minutos_parado: int
    cliente_avisou: bool  # o cliente disse no app que pagou e o webhook não veio


class EventoRevisaoOut(BaseModel):
    evento_id: str
    tipo: str
    recebido_em: datetime
    motivo: str
    pedido_id: str | None = None


class EstornoPendenteOut(BaseModel):
    chave: str
    pedido_id: str
    cobranca_id: str
    valor_centavos: int
    criada_em: datetime


class AlertasFinanceirosOut(BaseModel):
    minutos_pagamento_parado: int
    provedor_ligado: bool
    pagamentos_parados: list[PagamentoParadoOut]
    repasses_com_falha: list[EventoRevisaoOut]
    estornos_pendentes: list[EstornoPendenteOut]
    eventos_em_revisao: list[EventoRevisaoOut]
    contestacoes_em_aberto: int


class LinhaConciliacaoOut(BaseModel):
    tipo: str
    referencia: str
    pedido_id: str | None
    pedido_numero: int | None = None
    valor_provedor_centavos: int
    valor_trato_centavos: int
    diferenca_centavos: int
    situacao: str


class ConciliacaoOut(BaseModel):
    dia: date
    confere: bool
    cobrado_provedor_centavos: int
    cobrado_trato_centavos: int
    taxas_provedor_centavos: int
    movimentos_ignorados: int
    divergencias: list[LinhaConciliacaoOut]
    linhas: list[LinhaConciliacaoOut]


class FechamentoOut(BaseModel):
    mes: str
    fechado: bool
    pode_fechar: bool  # o mês já terminou e ainda não foi fechado
    totais: dict[str, Any]  # recalculados agora, do ledger
    gravado: dict[str, Any] | None = None  # o retrato do dia do fechamento
    confere: bool | None = None  # recalculado == gravado (só para mês fechado)
    hash: str | None = None
    fechado_por: str | None = None
    fechado_por_nome: str | None = None
    fechado_em: datetime | None = None
    motivo: str | None = None


class MesResumoOut(BaseModel):
    mes: str
    fechado: bool
    pode_fechar: bool
    fechado_em: datetime | None = None


class ArquivoProntoOut(BaseModel):
    codigo: str
    nome_arquivo: str
    expira_em_segundos: int = 180


class PedirExtratoIn(BaseModel):
    inicio: date
    fim: date
    motivo: str = Field(min_length=10, max_length=500)


class ConsultaCobrancaOut(BaseModel):
    cobranca_id: str
    status_no_provedor: str
    status_no_trato: str | None
    valor_centavos: int
    orientacao: str


# --- Apoio -------------------------------------------------------------------------------------


def servico_pagamento(request: Request) -> Any | None:
    """O serviço de pagamento ligado ao app (provedor + cobranças), ou `None` sem provedor."""
    return getattr(request.app.state, "servico_pagamento", None)


def _minutos_parado(admin: AdminContexto) -> int:
    vigente = admin.config.vigente()
    for parametro in vigente.parametros if vigente else ():
        if parametro.chave == CHAVE_MINUTOS_PARADO and parametro.valor:
            return int(parametro.valor)
    return MINUTOS_PARADO_PADRAO


def _contestacao_out(
    c: Contestacao, contexto: Contexto, rotulos: dict[str, tuple[int | None, str]]
) -> ContestacaoOut:
    agora = contexto.agora()
    horas = None
    if c.prazo_provas is not None and c.status.em_aberto:
        horas = int((c.prazo_provas - agora).total_seconds() // 3600)
    liberado = bool(c.pedido_id) and any(
        r.status == "liberado" for r in contexto.repasses.do_pedido(c.pedido_id or "")
    )
    numero, titulo = rotulos.get(c.pedido_id or "", (None, None))
    return ContestacaoOut(
        id=c.provedor_contestacao_id,
        pedido_id=c.pedido_id,
        pedido_numero=numero,
        pedido_titulo=titulo,
        cobranca_id=c.cobranca_id,
        valor_centavos=c.valor_centavos,
        motivo=c.motivo,
        motivo_legivel=c.motivo_legivel,
        status=c.status.value,
        prazo_provas=c.prazo_provas,
        horas_para_prazo=horas,
        aberta_em=c.aberta_em,
        encerrada_em=c.encerrada_em,
        repasse_liberado=liberado,
    )


def _pedido_do_evento(payload: dict[str, Any]) -> str | None:
    dados = payload.get("data")
    objeto = dados.get("object") if isinstance(dados, dict) else None
    meta = objeto.get("metadata") if isinstance(objeto, dict) else None
    valor = meta.get("pedido_id") if isinstance(meta, dict) else None
    return valor if isinstance(valor, str) else None


# --- Rotas -------------------------------------------------------------------------------------


@router.get("/contestacoes", response_model=list[ContestacaoOut], summary="Contestações de cartão")
def listar_contestacoes(
    status: str | None = Query(
        None, pattern="^(em_aberto|aberta|em_analise|ganha|perdida|encerrada)$"
    ),
    _: Operador = Depends(exigir(Permissao.PAGAMENTOS_VER)),
    contexto: Contexto = Depends(obter_contexto),
    admin: AdminContexto = Depends(obter_admin),
) -> list[ContestacaoOut]:
    """Da mais urgente (prazo de provas mais perto) para a mais antiga."""
    todas = [
        c
        for c in contexto.contestacoes.listar()
        if status is None
        or (status == "em_aberto" and c.status.em_aberto)
        or c.status.value == status
    ]
    rotulos = admin.pedidos.rotulos([c.pedido_id for c in todas if c.pedido_id])
    saida = [_contestacao_out(c, contexto, rotulos) for c in todas]
    saida.sort(key=lambda c: (c.horas_para_prazo is None, c.horas_para_prazo or 0))
    return saida


@router.get(
    "/alertas", response_model=AlertasFinanceirosOut, summary="O que travou no dinheiro e pede ação"
)
def alertas(
    request: Request,
    _: Operador = Depends(exigir(Permissao.PAGAMENTOS_VER)),
    contexto: Contexto = Depends(obter_contexto),
    admin: AdminContexto = Depends(obter_admin),
) -> AlertasFinanceirosOut:
    agora = contexto.agora()
    minutos = _minutos_parado(admin)
    servico = servico_pagamento(request)
    parados: list[PagamentoParadoOut] = []
    pendentes: list[EstornoPendenteOut] = []
    if servico is not None:
        for c in servico.cobrancas.aguardando_desde_antes(agora - timedelta(minutes=minutos)):
            pedido = contexto.pedidos.obter(c.pedido_id)
            parados.append(
                PagamentoParadoOut(
                    cobranca_id=c.id,
                    pedido_id=c.pedido_id,
                    valor_centavos=c.valor_centavos,
                    meio=c.meio.value,
                    criada_em=c.criada_em,
                    minutos_parado=int((agora - c.criada_em).total_seconds() // 60),
                    cliente_avisou=pedido is not None
                    and pedido.estado is Estado.AGUARDANDO_CONFIRMACAO,
                )
            )
        # Quem o cliente já avisou que pagou vem primeiro; depois o mais antigo.
        parados.sort(key=lambda p: (not p.cliente_avisou, p.criada_em))
        pendentes = [
            EstornoPendenteOut(
                chave=o.chave,
                pedido_id=o.pedido_id,
                cobranca_id=o.cobranca_id,
                valor_centavos=o.valor_centavos,
                criada_em=o.criada_em,
            )
            for o in servico.ordens.pendentes()
        ]
    rotulos = admin.pedidos.rotulos([p.pedido_id for p in parados])
    for p in parados:
        p.pedido_numero = rotulos.get(p.pedido_id, (None, ""))[0]

    revisao = [
        EventoRevisaoOut(
            evento_id=e.evento_id,
            tipo=e.tipo,
            recebido_em=e.recebido_em,
            motivo=motivo.removeprefix("revisar: "),
            pedido_id=_pedido_do_evento(e.payload),
        )
        for e, motivo in contexto.eventos_webhook.em_revisao()
    ]
    revisao.sort(key=lambda e: e.recebido_em, reverse=True)
    em_aberto = sum(1 for c in contexto.contestacoes.listar() if c.status.em_aberto)
    return AlertasFinanceirosOut(
        minutos_pagamento_parado=minutos,
        provedor_ligado=servico is not None,
        pagamentos_parados=parados,
        repasses_com_falha=[e for e in revisao if e.tipo in TIPOS_FALHA_REPASSE],
        estornos_pendentes=pendentes,
        eventos_em_revisao=[e for e in revisao if e.tipo not in TIPOS_FALHA_REPASSE],
        contestacoes_em_aberto=em_aberto,
    )


@router.post(
    "/cobrancas/{cobranca_id}/consultar",
    response_model=ConsultaCobrancaOut,
    summary="Pergunta ao provedor como está a cobrança (não muda nada no Trato)",
)
def consultar_cobranca(
    cobranca_id: str,
    request: Request,
    operador: Operador = Depends(exigir(Permissao.PAGAMENTOS_CONCILIAR)),
    admin: AdminContexto = Depends(obter_admin),
) -> ConsultaCobrancaOut:
    servico = servico_pagamento(request)
    if servico is None:
        raise HTTPException(503, "Provedor de pagamento não configurado.")
    local = servico.cobrancas.obter(cobranca_id)
    if local is None:
        raise HTTPException(404, "Cobrança não encontrada.")
    try:
        remota = servico.provedor.consultar_cobranca(cobranca_id)
    except Exception as erro:  # noqa: BLE001 - qualquer falha do provedor vira 502 sem detalhe
        raise HTTPException(502, "O provedor não respondeu. Tente de novo em instantes.") from erro
    pago_la = remota.status.value == "paga"
    if pago_la and local.status.value != "paga":
        orientacao = (
            "O provedor já confirmou o pagamento, mas o aviso não chegou ao Trato. Reenvie o "
            "evento payment_intent.succeeded pelo painel do provedor: o Trato só marca pago "
            "pelo aviso assinado."
        )
    elif pago_la:
        orientacao = "Pago no provedor e no Trato. Nada a fazer."
    else:
        orientacao = "O provedor ainda não recebeu o pagamento. O cliente precisa concluir."
    admin.auditoria.registrar(
        ator_id=operador.id,
        acao="pagamento.consultado_no_provedor",
        entidade="pagamentos",
        depois={"cobranca_id": cobranca_id, "status_no_provedor": remota.status.value},
    )
    return ConsultaCobrancaOut(
        cobranca_id=cobranca_id,
        status_no_provedor=remota.status.value,
        status_no_trato=local.status.value,
        valor_centavos=remota.valor_centavos,
        orientacao=orientacao,
    )


@router.get(
    "/conciliacao",
    response_model=ConciliacaoOut,
    summary="Compara o extrato do provedor com o ledger espelho em um dia (horário de Brasília)",
)
def conciliacao(
    request: Request,
    dia: date = Query(..., description="AAAA-MM-DD"),
    operador: Operador = Depends(exigir(Permissao.PAGAMENTOS_VER)),
    contexto: Contexto = Depends(obter_contexto),
    admin: AdminContexto = Depends(obter_admin),
) -> ConciliacaoOut:
    servico = servico_pagamento(request)
    if servico is None:
        raise HTTPException(503, "Provedor de pagamento não configurado.")
    desde, ate = periodo.dia(dia)
    if desde > contexto.agora():
        raise HTTPException(422, "Esse dia ainda não começou.")
    try:
        movimentos = servico.provedor.movimentos(desde, ate)
    except Exception as erro:  # noqa: BLE001 - falha do provedor vira 502 sem detalhe
        raise HTTPException(502, "O provedor não respondeu. Tente de novo em instantes.") from erro
    resultado = conciliar(movimentos, contexto.ledger.lancamentos(), desde, ate)
    rotulos = admin.pedidos.rotulos([lin.pedido_id for lin in resultado.linhas if lin.pedido_id])

    def saida(lin) -> LinhaConciliacaoOut:
        return LinhaConciliacaoOut(
            tipo=lin.tipo,
            referencia=lin.referencia,
            pedido_id=lin.pedido_id,
            pedido_numero=rotulos.get(lin.pedido_id or "", (None, ""))[0],
            valor_provedor_centavos=lin.valor_provedor_centavos,
            valor_trato_centavos=lin.valor_trato_centavos,
            diferenca_centavos=lin.diferenca_centavos,
            situacao=lin.situacao,
        )

    admin.auditoria.registrar(
        ator_id=operador.id,
        acao="pagamento.conciliacao_executada",
        entidade="pagamentos",
        depois={"dia": dia.isoformat(), "divergencias": len(resultado.divergencias)},
    )
    return ConciliacaoOut(
        dia=dia,
        confere=resultado.confere,
        cobrado_provedor_centavos=resultado.cobrado_provedor_centavos,
        cobrado_trato_centavos=resultado.cobrado_trato_centavos,
        taxas_provedor_centavos=resultado.taxas_provedor_centavos,
        movimentos_ignorados=resultado.movimentos_ignorados,
        divergencias=[saida(lin) for lin in resultado.divergencias],
        linhas=[saida(lin) for lin in resultado.linhas],
    )


# --- Fechamento mensal e trava (itens 7 e 8) ---------------------------------------------------


def _mes_ou_422(mes: str) -> tuple[int, int]:
    try:
        return periodo.ler_mes(mes)
    except ValueError as erro:
        raise HTTPException(422, str(erro)) from erro


def _fechamento_out(mes: str, contexto: Contexto, admin: AdminContexto) -> FechamentoOut:
    ano, numero = _mes_ou_422(mes)
    atuais = asdict(
        fechamento.calcular(
            contexto.ledger.lancamentos(), contexto.contestacoes.listar(), ano, numero
        )
    )
    gravado = contexto.fechamentos.obter(f"{ano:04d}-{numero:02d}")
    if gravado is None:
        return FechamentoOut(
            mes=atuais["mes"],
            fechado=False,
            pode_fechar=fechamento.pode_fechar(ano, numero, contexto.agora()),
            totais=atuais,
        )
    nome = None
    if admin.usuarios is not None:
        nome = admin.usuarios.nomes([gravado.fechado_por]).get(gravado.fechado_por)
    return FechamentoOut(
        mes=gravado.mes,
        fechado=True,
        pode_fechar=False,
        totais=atuais,
        gravado=gravado.totais,
        confere=fechamento.hash_dos_totais(atuais) == gravado.hash,
        hash=gravado.hash,
        fechado_por=gravado.fechado_por,
        fechado_por_nome=nome,
        fechado_em=gravado.fechado_em,
        motivo=gravado.motivo,
    )


@router.get("/fechamentos", response_model=list[MesResumoOut], summary="Meses e se estão fechados")
def listar_fechamentos(
    ultimos: int = Query(12, ge=1, le=36),
    _: Operador = Depends(exigir(Permissao.PAGAMENTOS_VER)),
    contexto: Contexto = Depends(obter_contexto),
) -> list[MesResumoOut]:
    agora = contexto.agora()
    ano, numero = periodo.mes_de(agora)
    gravados = {f.mes: f for f in contexto.fechamentos.listar()}
    saida = []
    for _passo in range(ultimos):
        chave = f"{ano:04d}-{numero:02d}"
        f = gravados.get(chave)
        saida.append(
            MesResumoOut(
                mes=chave,
                fechado=f is not None,
                pode_fechar=f is None and fechamento.pode_fechar(ano, numero, agora),
                fechado_em=f.fechado_em if f else None,
            )
        )
        ano, numero = (ano - 1, 12) if numero == 1 else (ano, numero - 1)
    return saida


@router.get("/fechamentos/{mes}", response_model=FechamentoOut, summary="Totais do mês")
def ver_fechamento(
    mes: str,
    _: Operador = Depends(exigir(Permissao.PAGAMENTOS_VER)),
    contexto: Contexto = Depends(obter_contexto),
    admin: AdminContexto = Depends(obter_admin),
) -> FechamentoOut:
    return _fechamento_out(mes, contexto, admin)


@router.post(
    "/fechamentos/{mes}/fechar",
    response_model=FechamentoOut,
    summary="Fecha o mês: grava o retrato (imutável) e trava novos lançamentos nele",
)
def fechar_mes(
    mes: str,
    corpo: ComMotivo,
    operador: Operador = Depends(exigir(Permissao.PAGAMENTOS_CONCILIAR)),
    contexto: Contexto = Depends(obter_contexto),
    admin: AdminContexto = Depends(obter_admin),
) -> FechamentoOut:
    ano, numero = _mes_ou_422(mes)
    if not fechamento.pode_fechar(ano, numero, contexto.agora()):
        raise HTTPException(422, "Só dá para fechar um mês que já terminou.")
    totais = fechamento.calcular(
        contexto.ledger.lancamentos(), contexto.contestacoes.listar(), ano, numero
    )
    novo = fechamento.montar(totais, operador.id, contexto.agora(), corpo.motivo)
    try:
        contexto.fechamentos.gravar(novo)
    except fechamento.MesJaFechado as erro:
        raise HTTPException(409, "Esse mês já foi fechado.") from erro
    admin.auditoria.registrar(
        ator_id=operador.id,
        acao="financeiro.mes_fechado",
        entidade="fechamentos_mensais",
        depois={"mes": novo.mes, "hash": novo.hash, **novo.totais},
        motivo=corpo.motivo,
    )
    return _fechamento_out(novo.mes, contexto, admin)


_ROTULOS_FECHAMENTO = (
    ("cobrancas", "Cobranças recebidas (quantidade)", False),
    ("cobrado_centavos", "Recebido de clientes (bruto)", True),
    ("devolvido_centavos", "Devolvido a clientes (estornos e contestações)", True),
    ("entrada_liquida_centavos", "Entrada líquida de clientes", True),
    ("receita_taxas_centavos", "Receita do Trato (taxas)", True),
    ("liberado_profissionais_centavos", "Liberado aos profissionais", True),
    ("pago_profissionais_centavos", "Pago aos profissionais", True),
    ("retido_fim_centavos", "Retido ao fim do mês", True),
    ("a_liberar_fim_centavos", "A liberar ao fim do mês", True),
    ("liberado_fim_centavos", "Liberado e não pago ao fim do mês", True),
    ("contestacoes_perdidas", "Contestações perdidas (quantidade)", False),
    ("contestacoes_perdidas_centavos", "Contestações perdidas (valor)", True),
    ("lancamentos", "Lançamentos no ledger (quantidade)", False),
)


@router.post(
    "/fechamentos/{mes}/exportar",
    response_model=ArquivoProntoOut,
    status_code=201,
    summary="CSV do mês para o contador (código de uso único para baixar)",
)
def exportar_fechamento(
    mes: str,
    operador: Operador = Depends(exigir(Permissao.RELATORIOS_EXPORTAR)),
    contexto: Contexto = Depends(obter_contexto),
    admin: AdminContexto = Depends(obter_admin),
) -> ArquivoProntoOut:
    dados = _fechamento_out(mes, contexto, admin)
    totais = dados.gravado or dados.totais
    saida = io.StringIO()
    escritor = csv.writer(saida, delimiter=";")
    situacao = "Fechado" if dados.fechado else "Prévia (mês ainda não fechado)"
    escritor.writerow(["Trato - fechamento do mês", dados.mes, situacao])
    if dados.hash:
        escritor.writerow(["Hash do fechamento", dados.hash, ""])
    escritor.writerow(["Indicador", "Valor", ""])
    for chave, rotulo, dinheiro in _ROTULOS_FECHAMENTO:
        valor = int(totais.get(chave, 0))
        texto = f"{valor / 100:.2f}".replace(".", ",") if dinheiro else str(valor)
        escritor.writerow([rotulo, texto, ""])
    conteudo = ("﻿" + saida.getvalue()).encode("utf-8")
    nome = f"trato_fechamento_{dados.mes}.csv"
    admin.auditoria.registrar(
        ator_id=operador.id,
        acao="relatorio.exportado",
        entidade="relatorios",
        depois={"relatorio": "fechamento", "mes": dados.mes, "fechado": dados.fechado},
    )
    codigo = guardar_para_baixar(conteudo, nome, operador.id, "text/csv; charset=utf-8")
    return ArquivoProntoOut(codigo=codigo, nome_arquivo=nome)


# --- Extrato do profissional em PDF (item 9) ---------------------------------------------------


@router.post(
    "/profissionais/{usuario_id}/extrato",
    response_model=ArquivoProntoOut,
    status_code=201,
    summary="Extrato de recebimentos do profissional em PDF (código de uso único)",
)
def extrato_do_profissional(
    usuario_id: str,
    corpo: PedirExtratoIn,
    operador: Operador = Depends(exigir(Permissao.RELATORIOS_EXPORTAR)),
    contexto: Contexto = Depends(obter_contexto),
    admin: AdminContexto = Depends(obter_admin),
) -> ArquivoProntoOut:
    if corpo.fim < corpo.inicio:
        raise HTTPException(422, "O fim precisa ser depois do início.")
    if (corpo.fim - corpo.inicio).days > 366:
        raise HTTPException(422, "Use um período de até um ano.")
    usuario = admin.usuarios.obter(usuario_id) if admin.usuarios is not None else None
    if usuario is None or usuario.tipo != "profissional":
        raise HTTPException(404, "Profissional não encontrado.")
    desde = periodo.dia(corpo.inicio)[0]
    ate = periodo.dia(corpo.fim)[1]
    extrato = extrato_profissional.montar(contexto.ledger.lancamentos(), usuario_id, desde, ate)
    rotulos = admin.pedidos.rotulos(list({lin.pedido_id for lin in extrato.linhas}))
    conteudo = extrato_profissional.pdf(extrato, usuario.nome, rotulos, contexto.agora())
    nome = f"trato_extrato_{corpo.inicio:%Y%m%d}_{corpo.fim:%Y%m%d}.pdf"
    admin.auditoria.registrar(
        ator_id=operador.id,
        acao="relatorio.exportado",
        entidade="usuarios",
        entidade_id=usuario_id,
        depois={
            "relatorio": "extrato_profissional",
            "inicio": corpo.inicio.isoformat(),
            "fim": corpo.fim.isoformat(),
            "recebido_centavos": extrato.recebido_centavos,
        },
        motivo=corpo.motivo,
    )
    codigo = guardar_para_baixar(conteudo, nome, operador.id, "application/pdf")
    return ArquivoProntoOut(codigo=codigo, nome_arquivo=nome)


__all__ = ["StatusContestacao", "router", "servico_pagamento"]
