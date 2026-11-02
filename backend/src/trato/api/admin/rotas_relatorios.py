"""Rotas de Exportação de Relatórios Fiscais e Contábeis em CSV (Módulo 7).

Gera extratos e relatórios consolidados para fechamento contábil e auditoria financeira.
"""

from __future__ import annotations

import csv
import io
from datetime import datetime, timezone
from typing import Annotated

from fastapi import APIRouter, Depends, HTTPException, Query, Response

from trato.api.admin.contexto import Operador, exigir
from trato.api.admin.papeis import Permissao
from trato.api.contexto import Contexto, obter_contexto

router = APIRouter(prefix="/v1/admin/relatorios", tags=["admin: relatorios e exportacao"])


@router.get("/financeiro", summary="Exportar relatório financeiro e fiscal em CSV")
def exportar_financeiro(
    operador: Operador = Depends(exigir(Permissao.RELATORIOS_EXPORTAR)),
    contexto: Contexto = Depends(obter_contexto),
) -> Response:
    banco = contexto.extras.get("banco") if contexto.extras else None
    if banco is None:
        raise HTTPException(503, "Banco de dados não configurado.")

    output = io.StringIO()
    writer = csv.writer(output, delimiter=";")
    writer.writerow([
        "ID_Pagamento",
        "Data_Criacao",
        "Pedido_ID",
        "Metodo",
        "Valor_Bruto_BRL",
        "Taxa_Plataforma_Trato_BRL",
        "Valor_Liquido_Prestador_BRL",
        "Status",
    ])

    with banco.transacao() as con:
        linhas = con.execute(
            """
            SELECT
              id,
              criado_em,
              pedido_id,
              metodo,
              valor_centavos,
              coalesce(taxa_plataforma_centavos, 0) as taxa,
              status
            FROM public.pagamentos
            ORDER BY criado_em DESC
            """
        ).fetchall()

        for r in linhas:
            bruto = (r["valor_centavos"] or 0) / 100
            taxa = (r["taxa"] or 0) / 100
            if taxa == 0 and bruto > 0:
                taxa = round(bruto * 0.12, 2)
            liquido = round(bruto - taxa, 2)
            dt = r["criado_em"].strftime("%d/%m/%Y %H:%M") if hasattr(r["criado_em"], "strftime") else str(r["criado_em"])
            writer.writerow([
                str(r["id"]),
                dt,
                str(r["pedido_id"]),
                r["metodo"] or "PIX",
                f"{bruto:.2f}".replace(".", ","),
                f"{taxa:.2f}".replace(".", ","),
                f"{liquido:.2f}".replace(".", ","),
                r["status"],
            ])

    conteudo = "\ufeff" + output.getvalue()  # BOM para abrir correto no Excel Windows
    nome_arquivo = f"trato_relatorio_financeiro_{datetime.now(timezone.utc).strftime('%Y%m%d_%H%M')}.csv"

    return Response(
        content=conteudo,
        media_type="text/csv; charset=utf-8",
        headers={"Content-Disposition": f'attachment; filename="{nome_arquivo}"'},
    )


@router.get("/pedidos", summary="Exportar relatório de pedidos e atendimentos em CSV")
def exportar_pedidos(
    operador: Operador = Depends(exigir(Permissao.RELATORIOS_EXPORTAR)),
    contexto: Contexto = Depends(obter_contexto),
) -> Response:
    banco = contexto.extras.get("banco") if contexto.extras else None
    if banco is None:
        raise HTTPException(503, "Banco de dados não configurado.")

    output = io.StringIO()
    writer = csv.writer(output, delimiter=";")
    writer.writerow([
        "ID_Pedido",
        "Data_Criacao",
        "Titulo",
        "Categoria",
        "Cliente",
        "Cidade",
        "Valor_BRL",
        "Status",
    ])

    with banco.transacao() as con:
        linhas = con.execute(
            """
            SELECT
              p.id,
              p.criado_em,
              p.titulo,
              c.nome as categoria,
              u.nome as cliente,
              cid.nome as cidade,
              coalesce(p.valor_centavos, 0) as valor_centavos,
              p.status
            FROM public.pedidos p
            LEFT JOIN public.categorias c ON c.id = p.categoria_id
            LEFT JOIN public.usuarios u ON u.id = p.cliente_id
            LEFT JOIN public.cidades cid ON cid.id = p.cidade_id
            ORDER BY p.criado_em DESC
            """
        ).fetchall()

        for r in linhas:
            val = (r["valor_centavos"] or 0) / 100
            dt = r["criado_em"].strftime("%d/%m/%Y %H:%M") if hasattr(r["criado_em"], "strftime") else str(r["criado_em"])
            writer.writerow([
                str(r["id"]),
                dt,
                r["titulo"],
                r["categoria"] or "Geral",
                r["cliente"] or "Cliente",
                r["cidade"] or "Campinas",
                f"{val:.2f}".replace(".", ","),
                r["status"],
            ])

    conteudo = "\ufeff" + output.getvalue()
    nome_arquivo = f"trato_relatorio_pedidos_{datetime.now(timezone.utc).strftime('%Y%m%d_%H%M')}.csv"

    return Response(
        content=conteudo,
        media_type="text/csv; charset=utf-8",
        headers={"Content-Disposition": f'attachment; filename="{nome_arquivo}"'},
    )


@router.get("/repasses", summary="Exportar relatório de repasses a prestadores em CSV")
def exportar_repasses(
    operador: Operador = Depends(exigir(Permissao.RELATORIOS_EXPORTAR)),
    contexto: Contexto = Depends(obter_contexto),
) -> Response:
    banco = contexto.extras.get("banco") if contexto.extras else None
    if banco is None:
        raise HTTPException(503, "Banco de dados não configurado.")

    output = io.StringIO()
    writer = csv.writer(output, delimiter=";")
    writer.writerow([
        "ID_Repasse",
        "Data",
        "Profissional",
        "Valor_BRL",
        "Status",
    ])

    with banco.transacao() as con:
        linhas = con.execute(
            """
            SELECT
              r.id,
              r.criado_em,
              u.nome as profissional,
              coalesce(r.valor_centavos, 0) as valor_centavos,
              r.status
            FROM public.repasses r
            LEFT JOIN public.usuarios u ON u.id = r.profissional_id
            ORDER BY r.criado_em DESC
            """
        ).fetchall()

        for r in linhas:
            val = (r["valor_centavos"] or 0) / 100
            dt = r["criado_em"].strftime("%d/%m/%Y %H:%M") if hasattr(r["criado_em"], "strftime") else str(r["criado_em"])
            writer.writerow([
                str(r["id"]),
                dt,
                r["profissional"] or "Profissional",
                f"{val:.2f}".replace(".", ","),
                r["status"],
            ])

    conteudo = "\ufeff" + output.getvalue()
    nome_arquivo = f"trato_relatorio_repasses_{datetime.now(timezone.utc).strftime('%Y%m%d_%H%M')}.csv"

    return Response(
        content=conteudo,
        media_type="text/csv; charset=utf-8",
        headers={"Content-Disposition": f'attachment; filename="{nome_arquivo}"'},
    )
