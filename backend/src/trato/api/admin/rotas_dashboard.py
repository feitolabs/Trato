"""Rotas administrativas do Painel executivo (RF-DAS-01 a RF-DAS-04).

Quatro indicadores com comparação ao período anterior de mesma duração, série diária de
pedidos e funil de conversão. Nenhum percentual é inventado aqui: a receita vem das taxas que o
contrato registrou (`contratos.taxa_trato_centavos`), nunca de uma conta em cima do GMV.
"""

from __future__ import annotations

from datetime import UTC, date, datetime, time, timedelta
from typing import Any

from fastapi import APIRouter, Depends, HTTPException, Query
from pydantic import BaseModel, Field

from trato.api.admin.contexto import Operador, exigir
from trato.api.admin.papeis import Permissao
from trato.api.contexto import Contexto, obter_contexto

router = APIRouter(prefix="/v1/admin/dashboard", tags=["admin: dashboard executivo"])

_ATIVOS = (
    "aberto",
    "orcamento_aceito",
    "pago_retido",
    "agendado",
    "em_andamento",
    "em_confirmacao",
    "retrabalho",
    "em_disputa",
)
_FECHADOS = (
    "orcamento_aceito",
    "pago_retido",
    "agendado",
    "em_andamento",
    "em_confirmacao",
    "concluido",
    "retrabalho",
)


class ResumoMetricas(BaseModel):
    gmv_centavos: int = Field(..., description="Soma dos pedidos pagos no período")
    receita_taxa_centavos: int = Field(
        ..., description="Soma das taxas retidas em serviços concluídos"
    )
    pedidos_total: int
    pedidos_concluidos: int
    pedidos_em_andamento: int
    pedidos_abertos: int
    pedidos_disputa: int
    clientes_total: int
    profissionais_total: int
    profissionais_pendentes: int
    cidades_ativas: int
    categorias_ativas: int
    # Comparação com o período anterior de mesma duração.
    gmv_anterior_centavos: int = 0
    receita_taxa_anterior_centavos: int = 0
    pedidos_ativos: int = 0
    pedidos_ativos_anterior: int = 0
    base_usuarios: int = 0
    base_usuarios_anterior: int = 0
    disputas_abertas: int = 0
    alertas_risco_abertos: int = 0


class PontoSerie(BaseModel):
    data: str
    pedidos: int
    gmv_centavos: int


class EtapaFunil(BaseModel):
    etapa: str
    quantidade: int
    taxa_conversao_pct: float


class DashboardSeries(BaseModel):
    historico_dias: list[PontoSerie]
    funil: list[EtapaFunil]


def _janela(
    dias: int, inicio: date | None, fim: date | None, agora: datetime
) -> tuple[datetime, datetime, datetime]:
    """(começo, fim, começo do período anterior). O período anterior tem a mesma duração."""
    if (inicio is None) != (fim is None):
        raise HTTPException(422, "Informe início e fim juntos.")
    if inicio is not None and fim is not None:
        if fim < inicio:
            raise HTTPException(422, "O fim precisa ser depois do início.")
        comeco = datetime.combine(inicio, time.min, tzinfo=UTC)
        termino = datetime.combine(fim, time.max, tzinfo=UTC)
    else:
        termino = agora
        comeco = agora - timedelta(days=dias)
    return comeco, termino, comeco - (termino - comeco)


def _banco(contexto: Contexto) -> Any:
    banco = contexto.extras.get("banco") if contexto.extras else None
    if banco is None:
        raise HTTPException(503, "Banco de dados não configurado.")
    return banco


def _uma(con: Any, sql: str, params: tuple[Any, ...] = ()) -> int:
    linha = con.execute(sql, params).fetchone()
    return int((linha or {}).get("n") or 0)


def _gmv(con: Any, de: datetime, ate: datetime) -> int:
    return _uma(
        con,
        "select coalesce(sum(valor_centavos), 0) as n from public.pagamentos "
        "where status = 'confirmado' and coalesce(confirmado_em, criado_em) >= %s "
        "and coalesce(confirmado_em, criado_em) < %s",
        (de, ate),
    )


def _receita(con: Any, de: datetime, ate: datetime) -> int:
    """Taxas retidas em serviços concluídos dentro do período (data da conclusão)."""
    return _uma(
        con,
        "select coalesce(sum(c.taxa_trato_centavos), 0) as n from public.contratos c "
        "join public.pedidos p on p.id = c.pedido_id and p.status = 'concluido' "
        "join lateral (select max(h.ocorrida_em) as em from public.pedido_historico h "
        "              where h.pedido_id = p.id and h.para_status = 'concluido') h on true "
        "where h.em >= %s and h.em < %s",
        (de, ate),
    )


def _ativos(con: Any, de: datetime, ate: datetime) -> int:
    return _uma(
        con,
        "select count(*) as n from public.pedidos where status = any(%s) "
        "and criado_em >= %s and criado_em < %s",
        (list(_ATIVOS), de, ate),
    )


def _base(con: Any, ate: datetime) -> int:
    return _uma(
        con,
        "select count(*) as n from public.usuarios where status = 'ativo' and criado_em < %s",
        (ate,),
    )


@router.get(
    "/metricas",
    response_model=ResumoMetricas,
    summary="Indicadores do período, com comparação ao período anterior",
)
def obter_metricas(
    dias: int = Query(30, ge=1, le=365),
    inicio: date | None = None,
    fim: date | None = None,
    operador: Operador = Depends(exigir(Permissao.DASHBOARD_VER)),
    contexto: Contexto = Depends(obter_contexto),
) -> ResumoMetricas:
    banco = _banco(contexto)
    comeco, termino, anterior = _janela(dias, inicio, fim, datetime.now(UTC))
    fim_aberto = termino + timedelta(microseconds=1)

    with banco.transacao() as con:
        lin_ped = (
            con.execute(
                """
            select
              count(*) as total,
              count(*) filter (where status in ('concluido')) as concluidos,
              count(*) filter (where status in ('orcamento_aceito', 'pago_retido', 'agendado',
                                                'em_andamento', 'em_confirmacao',
                                                'retrabalho')) as em_andamento,
              count(*) filter (where status in ('aberto')) as abertos,
              count(*) filter (where status in ('em_disputa')) as disputa
            from public.pedidos where criado_em >= %s and criado_em < %s
            """,
                (comeco, fim_aberto),
            ).fetchone()
            or {}
        )
        profissionais = _uma(con, "select count(*) as n from public.perfis_profissional")
        base_agora = _base(con, fim_aberto)
        return ResumoMetricas(
            gmv_centavos=_gmv(con, comeco, fim_aberto),
            receita_taxa_centavos=_receita(con, comeco, fim_aberto),
            pedidos_total=int(lin_ped.get("total") or 0),
            pedidos_concluidos=int(lin_ped.get("concluidos") or 0),
            pedidos_em_andamento=int(lin_ped.get("em_andamento") or 0),
            pedidos_abertos=int(lin_ped.get("abertos") or 0),
            pedidos_disputa=int(lin_ped.get("disputa") or 0),
            clientes_total=max(0, base_agora - profissionais),
            profissionais_total=profissionais,
            profissionais_pendentes=_uma(
                con,
                "select count(*) as n from public.verificacoes "
                "where status in ('enviada', 'em_analise')",
            ),
            cidades_ativas=_uma(con, "select count(*) as n from public.cidades where ativa = true"),
            categorias_ativas=_uma(
                con, "select count(*) as n from public.categorias where ativa = true"
            ),
            gmv_anterior_centavos=_gmv(con, anterior, comeco),
            receita_taxa_anterior_centavos=_receita(con, anterior, comeco),
            pedidos_ativos=_ativos(con, comeco, fim_aberto),
            pedidos_ativos_anterior=_ativos(con, anterior, comeco),
            base_usuarios=base_agora,
            base_usuarios_anterior=_base(con, comeco),
            disputas_abertas=_uma(
                con, "select count(*) as n from public.disputas where status <> 'decidida'"
            ),
            alertas_risco_abertos=_uma(
                con, "select count(*) as n from public.alertas_risco where resolvido = false"
            ),
        )


@router.get(
    "/series",
    response_model=DashboardSeries,
    summary="Pedidos por dia e funil de conversão do período",
)
def obter_series(
    operador: Operador = Depends(exigir(Permissao.DASHBOARD_VER)),
    contexto: Contexto = Depends(obter_contexto),
    dias: int = Query(30, ge=1, le=365),
    inicio: date | None = None,
    fim: date | None = None,
) -> DashboardSeries:
    banco = _banco(contexto)
    comeco, termino, _ = _janela(dias, inicio, fim, datetime.now(UTC))
    fim_aberto = termino + timedelta(microseconds=1)
    total_dias = (termino.date() - comeco.date()).days + 1

    with banco.transacao() as con:
        linhas = con.execute(
            """
            select
              to_char(date_trunc('day', p.criado_em), 'YYYY-MM-DD') as dia,
              count(distinct p.id) as qtd,
              coalesce(sum(c.valor_total_centavos), 0) as gmv
            from public.pedidos p
            left join public.contratos c on c.pedido_id = p.id and c.status not in ('cancelado')
            where p.criado_em >= %s and p.criado_em < %s
            group by 1
            order by 1
            """,
            (comeco, fim_aberto),
        ).fetchall()
        por_dia = {r["dia"]: (int(r["qtd"]), int(r["gmv"])) for r in linhas}
        pontos = []
        for i in range(total_dias):
            dia = (comeco.date() + timedelta(days=i)).strftime("%Y-%m-%d")
            qtd, gmv = por_dia.get(dia, (0, 0))
            pontos.append(PontoSerie(data=dia, pedidos=qtd, gmv_centavos=gmv))

        f = (
            con.execute(
                """
            select
              count(*) as criados,
              count(*) filter (where exists (select 1 from public.orcamentos o
                                             where o.pedido_id = pedidos.id)) as com_propostas,
              count(*) filter (where status = any(%s)) as fechados,
              count(*) filter (where status = 'concluido') as concluidos
            from public.pedidos where criado_em >= %s and criado_em < %s
            """,
                (list(_FECHADOS), comeco, fim_aberto),
            ).fetchone()
            or {}
        )

    criados = int(f.get("criados") or 0)
    base = max(criados, 1)

    def etapa(nome: str, qtd: int) -> EtapaFunil:
        pct = 100.0 if nome == "Pedidos criados" else round(qtd / base * 100, 1)
        return EtapaFunil(etapa=nome, quantidade=qtd, taxa_conversao_pct=pct)

    return DashboardSeries(
        historico_dias=pontos,
        funil=[
            etapa("Pedidos criados", criados),
            etapa("Propostas recebidas", int(f.get("com_propostas") or 0)),
            etapa("Pedidos fechados", int(f.get("fechados") or 0)),
            etapa("Serviços concluídos", int(f.get("concluidos") or 0)),
        ],
    )
