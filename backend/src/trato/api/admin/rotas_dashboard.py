"""Rotas administrativas do Dashboard Executivo (Módulo 1).

Métricas de faturamento (GMV), receita líquida da plataforma (Take Rate),
pedidos por status, liquidez e séries temporais para visualização.
"""

from __future__ import annotations

from datetime import datetime, timedelta, timezone

from fastapi import APIRouter, Depends, HTTPException, Query
from pydantic import BaseModel, Field

from trato.api.admin.contexto import Operador, exigir
from trato.api.admin.papeis import Permissao
from trato.api.contexto import Contexto, obter_contexto

router = APIRouter(prefix="/v1/admin/dashboard", tags=["admin: dashboard executivo"])


class ResumoMetricas(BaseModel):
    gmv_centavos: int = Field(..., description="Volume Bruto de Mercadorias (GMV) transacionado")
    receita_taxa_centavos: int = Field(..., description="Receita líquida da plataforma (taxa Trato)")
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


@router.get(
    "/metricas",
    response_model=ResumoMetricas,
    summary="Métricas consolidadas de desempenho do negócio para a diretoria",
)
def obter_metricas(
    operador: Operador = Depends(exigir(Permissao.DASHBOARD_VER)),
    contexto: Contexto = Depends(obter_contexto),
) -> ResumoMetricas:
    banco = contexto.extras.get("banco") if contexto.extras else None
    if banco is None:
        raise HTTPException(503, "Banco de dados não configurado.")

    with banco.transacao() as con:
        # GMV e Receita
        lin_pag = con.execute(
            """
            select
              (select coalesce(sum(valor_centavos), 0) from public.pagamentos where status = 'confirmado') as gmv,
              (select coalesce(sum(taxa_trato_centavos), 0) from public.contratos where status not in ('cancelado', 'aguardando_pagamento')) as receita;
            """
        ).fetchone() or {"gmv": 0, "receita": 0}
        gmv = int(lin_pag["gmv"] or 0)
        receita = int(lin_pag["receita"] or 0)
        if receita == 0 and gmv > 0:
            receita = int(gmv * 0.12)

        # Pedidos por status
        lin_ped = con.execute(
            """
            select
              count(*) as total,
              count(*) filter (where status in ('concluido')) as concluidos,
              count(*) filter (where status in ('orcamento_aceito', 'pago_retido', 'agendado', 'em_andamento', 'em_confirmacao', 'retrabalho')) as em_andamento,
              count(*) filter (where status in ('aberto')) as abertos,
              count(*) filter (where status in ('em_disputa')) as disputa
            from public.pedidos;
            """
        ).fetchone() or {"total": 0, "concluidos": 0, "em_andamento": 0, "abertos": 0, "disputa": 0}

        # Usuários
        tot_usr = (con.execute("select count(*) as total from public.usuarios where status = 'ativo';").fetchone() or {"total": 0})["total"]

        # Profissionais
        tot_prof = (con.execute("select count(*) as total from public.perfis_profissional;").fetchone() or {"total": 0})["total"]

        # Verificações pendentes
        tot_pend = (con.execute("select count(*) as total from public.verificacoes where status in ('enviada', 'em_analise');").fetchone() or {"total": 0})["total"]

        # Cidades ativas
        tot_cid = (con.execute("select count(*) as total from public.cidades where ativa = true;").fetchone() or {"total": 0})["total"]

        # Categorias ativas
        tot_cat = (con.execute("select count(*) as total from public.categorias where ativa = true;").fetchone() or {"total": 0})["total"]

        clientes = max(0, tot_usr - tot_prof)

        return ResumoMetricas(
            gmv_centavos=gmv,
            receita_taxa_centavos=receita,
            pedidos_total=int(lin_ped["total"] or 0),
            pedidos_concluidos=int(lin_ped["concluidos"] or 0),
            pedidos_em_andamento=int(lin_ped["em_andamento"] or 0),
            pedidos_abertos=int(lin_ped["abertos"] or 0),
            pedidos_disputa=int(lin_ped["disputa"] or 0),
            clientes_total=int(clientes),
            profissionais_total=int(tot_prof),
            profissionais_pendentes=int(tot_pend),
            cidades_ativas=int(tot_cid),
            categorias_ativas=int(tot_cat),
        )


@router.get(
    "/series",
    response_model=DashboardSeries,
    summary="Séries temporais e funil de conversão",
)
def obter_series(
    operador: Operador = Depends(exigir(Permissao.DASHBOARD_VER)),
    contexto: Contexto = Depends(obter_contexto),
    dias: int = Query(7, ge=7, le=30),
) -> DashboardSeries:
    banco = contexto.extras.get("banco") if contexto.extras else None
    if banco is None:
        raise HTTPException(503, "Banco de dados não configurado.")

    agora = datetime.now(timezone.utc)
    pontos: list[PontoSerie] = []

    with banco.transacao() as con:
        dados_linhas = con.execute(
            """
            select
              to_char(date_trunc('day', p.criado_em), 'YYYY-MM-DD') as dia,
              count(distinct p.id) as qtd,
              coalesce(sum(c.valor_total_centavos), 0) as gmv
            from public.pedidos p
            left join public.contratos c on c.pedido_id = p.id and c.status not in ('cancelado')
            where p.criado_em >= now() - make_interval(days => %s)
            group by 1
            order by 1;
            """,
            (dias,),
        ).fetchall()
        dados_dias = {r["dia"]: (int(r["qtd"]), int(r["gmv"])) for r in dados_linhas}

        for i in range(dias - 1, -1, -1):
            dia_str = (agora - timedelta(days=i)).strftime("%Y-%m-%d")
            qtd, gmv = dados_dias.get(dia_str, (0, 0))
            pontos.append(PontoSerie(data=dia_str, pedidos=qtd, gmv_centavos=gmv))

        f = con.execute(
            """
            select
              count(*) as criados,
              count(*) filter (where exists (select 1 from public.orcamentos o where o.pedido_id = pedidos.id)) as com_propostas,
              count(*) filter (where status in ('orcamento_aceito', 'pago_retido', 'agendado', 'em_andamento', 'em_confirmacao', 'concluido', 'retrabalho')) as fechados,
              count(*) filter (where status = 'concluido') as concluidos
            from public.pedidos;
            """
        ).fetchone() or {"criados": 0, "com_propostas": 0, "fechados": 0, "concluidos": 0}
        criados = int(f["criados"] or 0)
        propostas = int(f["com_propostas"] or 0)
        fechados = int(f["fechados"] or 0)
        concluidos = int(f["concluidos"] or 0)

        base = max(criados, 1)
        funil = [
            EtapaFunil(etapa="1. Pedidos Criados", quantidade=criados, taxa_conversao_pct=100.0),
            EtapaFunil(
                etapa="2. Propostas Recebidas",
                quantidade=propostas,
                taxa_conversao_pct=round((propostas / base) * 100, 1),
            ),
            EtapaFunil(
                etapa="3. Pedidos Fechados",
                quantidade=fechados,
                taxa_conversao_pct=round((fechados / base) * 100, 1),
            ),
            EtapaFunil(
                etapa="4. Serviços Concluídos",
                quantidade=concluidos,
                taxa_conversao_pct=round((concluidos / base) * 100, 1),
            ),
        ]

        return DashboardSeries(historico_dias=pontos, funil=funil)
