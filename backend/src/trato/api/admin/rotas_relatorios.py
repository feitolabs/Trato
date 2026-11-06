"""Relatórios fiscais e contábeis em CSV (RF-REL-01 a RF-REL-04).

Fluxo: a tela pede o relatório (POST, com motivo e filtros) e recebe um código de uso único, válido
por poucos minutos; o download é por esse código. O token de login NUNCA vai na URL. Toda exportação
grava na auditoria quem exportou, os filtros e a data. Colunas com CPF só saem para papéis que podem
revelar dados pessoais. CSV em UTF-8 com BOM; o formato "excel_br" usa ponto e vírgula e vírgula
decimal (abre direto no Excel em português), o "padrao" usa vírgula e ponto decimal.
"""

from __future__ import annotations

import csv
import io
import secrets
import threading
import time
from dataclasses import dataclass
from datetime import UTC, date, datetime, timedelta
from datetime import time as hora
from typing import Any

from fastapi import APIRouter, Depends, HTTPException, Response
from pydantic import BaseModel, Field

from trato.api.admin.contexto import AdminContexto, Operador, exigir, obter_admin
from trato.api.admin.papeis import Permissao, pode
from trato.api.contexto import Contexto, obter_contexto
from trato.persistencia.comum import como_uuid

router = APIRouter(prefix="/v1/admin/relatorios", tags=["admin: relatorios e exportacao"])

TIPOS = ("financeiro", "pedidos", "repasses", "auditoria")
_SEGUNDOS_DO_CODIGO = 180


class PedirRelatorioIn(BaseModel):
    inicio: date | None = None
    fim: date | None = None
    cidade_id: str | None = None
    formato: str = Field(default="excel_br", pattern="^(excel_br|padrao)$")
    motivo: str = Field(min_length=10, max_length=500)


class RelatorioProntoOut(BaseModel):
    codigo: str
    nome_arquivo: str
    linhas: int
    colunas: int
    com_dados_pessoais: bool
    expira_em_segundos: int = _SEGUNDOS_DO_CODIGO


@dataclass
class _Pronto:
    conteudo: bytes
    nome: str
    operador_id: str
    expira: float


_prontos: dict[str, _Pronto] = {}
_trava = threading.Lock()


def _guardar(conteudo: bytes, nome: str, operador_id: str) -> str:
    agora = time.monotonic()
    codigo = secrets.token_urlsafe(32)
    with _trava:
        for k in [k for k, v in _prontos.items() if v.expira < agora]:
            del _prontos[k]
        _prontos[codigo] = _Pronto(conteudo, nome, operador_id, agora + _SEGUNDOS_DO_CODIGO)
    return codigo


def _banco(contexto: Contexto) -> Any:
    banco = contexto.extras.get("banco") if contexto.extras else None
    if banco is None:
        raise HTTPException(503, "Banco de dados não configurado.")
    return banco


def _numero(valor: float, formato: str) -> str:
    texto = f"{valor:.2f}"
    return texto.replace(".", ",") if formato == "excel_br" else texto


def _reais(centavos: int | None, formato: str) -> str:
    return "" if centavos is None else _numero(centavos / 100, formato)


def _data(valor: Any) -> str:
    return valor.strftime("%d/%m/%Y %H:%M") if hasattr(valor, "strftime") else ""


def _codigo_pedido(numero: Any) -> str:
    return f"PED-{numero}" if numero is not None else ""


def _gerar(
    con: Any,
    tipo: str,
    de: datetime | None,
    ate: datetime | None,
    cidade: Any,
    formato: str,
    pessoais: bool,
) -> tuple[list[str], list[list[str]]]:
    janela = {"de": de, "ate": ate, "cidade": cidade}
    if tipo == "financeiro":
        cab = [
            "ID_Pagamento", "Data", "Pedido", "Cidade", "Cliente", "Profissional", "Tipo",
            "Meio", "Valor_Bruto_BRL", "Taxa_Trato_BRL", "Liquido_Profissional_BRL",
            "Estornado_BRL", "Status",
        ]  # fmt: skip
        if pessoais:
            cab += ["CPF_Cliente", "CPF_Profissional"]
        linhas = con.execute(
            """
            SELECT p.id, p.criado_em, pe.numero, cid.nome AS cidade, uc.nome AS cliente,
                   upr.nome AS profissional, p.tipo, p.meio, p.valor_centavos,
                   p.estornado_centavos, p.status, c.taxa_trato_centavos AS taxa,
                   c.liquido_profissional_centavos AS liquido,
                   pc.cpf AS cpf_cliente, pp.cpf AS cpf_profissional
            FROM public.pagamentos p
            LEFT JOIN public.contratos c ON c.id = p.contrato_id
            LEFT JOIN public.pedidos pe ON pe.id = c.pedido_id
            LEFT JOIN public.cidades cid ON cid.id = pe.cidade_id
            LEFT JOIN public.usuarios uc ON uc.id = c.cliente_id
            LEFT JOIN public.usuarios upr ON upr.id = c.profissional_id
            LEFT JOIN public.usuarios_privados pc ON pc.usuario_id = c.cliente_id
            LEFT JOIN public.usuarios_privados pp ON pp.usuario_id = c.profissional_id
            WHERE (%(de)s::timestamptz IS NULL OR p.criado_em >= %(de)s)
              AND (%(ate)s::timestamptz IS NULL OR p.criado_em < %(ate)s)
              AND (%(cidade)s::uuid IS NULL OR pe.cidade_id = %(cidade)s)
            ORDER BY p.criado_em DESC
            """,
            janela,
        ).fetchall()
        saida = []
        for r in linhas:
            linha = [
                str(r["id"]), _data(r["criado_em"]), _codigo_pedido(r["numero"]),
                r["cidade"] or "", r["cliente"] or "", r["profissional"] or "", r["tipo"] or "",
                r["meio"] or "", _reais(r["valor_centavos"], formato), _reais(r["taxa"], formato),
                _reais(r["liquido"], formato), _reais(r["estornado_centavos"], formato),
                r["status"] or "",
            ]  # fmt: skip
            if pessoais:
                linha += [r["cpf_cliente"] or "", r["cpf_profissional"] or ""]
            saida.append(linha)
        return cab, saida

    if tipo == "pedidos":
        cab = [
            "Pedido", "Data", "Titulo", "Categoria", "Cidade", "Cliente", "Profissional",
            "Status", "Valor_BRL", "Urgente",
        ]  # fmt: skip
        linhas = con.execute(
            """
            SELECT pe.numero, pe.criado_em, pe.titulo, cat.nome AS categoria, cid.nome AS cidade,
                   uc.nome AS cliente, upr.nome AS profissional, pe.status, pe.urgente,
                   coalesce(ct.valor_total_centavos, pe.faixa_preco_max_centavos) AS valor
            FROM public.pedidos pe
            LEFT JOIN public.categorias cat ON cat.id = pe.categoria_id
            LEFT JOIN public.cidades cid ON cid.id = pe.cidade_id
            LEFT JOIN public.usuarios uc ON uc.id = pe.cliente_id
            LEFT JOIN public.contratos ct ON ct.pedido_id = pe.id
            LEFT JOIN public.usuarios upr ON upr.id = ct.profissional_id
            WHERE (%(de)s::timestamptz IS NULL OR pe.criado_em >= %(de)s)
              AND (%(ate)s::timestamptz IS NULL OR pe.criado_em < %(ate)s)
              AND (%(cidade)s::uuid IS NULL OR pe.cidade_id = %(cidade)s)
            ORDER BY pe.criado_em DESC
            """,
            janela,
        ).fetchall()
        return cab, [
            [
                _codigo_pedido(r["numero"]),
                _data(r["criado_em"]),
                r["titulo"] or "",
                r["categoria"] or "",
                r["cidade"] or "",
                r["cliente"] or "",
                r["profissional"] or "",
                r["status"] or "",
                _reais(r["valor"], formato),
                "sim" if r["urgente"] else "não",
            ]  # fmt: skip
            for r in linhas
        ]

    if tipo == "auditoria":
        cab = ["Numero", "Data", "Quem", "Acao", "Entidade", "Motivo"]
        linhas = con.execute(
            """
            SELECT a.id, a.ocorrida_em, coalesce(u.nome, a.ator_tipo) AS quem, a.acao,
                   coalesce(a.entidade, '') || coalesce(':' || a.entidade_id::text, '') AS entidade,
                   a.motivo
            FROM public.auditoria a LEFT JOIN public.usuarios u ON u.id = a.ator_id
            WHERE (%(de)s::timestamptz IS NULL OR a.ocorrida_em >= %(de)s)
              AND (%(ate)s::timestamptz IS NULL OR a.ocorrida_em < %(ate)s)
            ORDER BY a.id DESC
            """,
            janela,
        ).fetchall()
        return cab, [
            [str(r["id"]), _data(r["ocorrida_em"]), r["quem"] or "", r["acao"], r["entidade"],
             r["motivo"] or ""]
            for r in linhas
        ]  # fmt: skip

    cab = [
        "ID_Repasse", "Data", "Pedido", "Profissional", "Valor_Bruto_BRL", "Taxa_Trato_BRL",
        "Valor_Liquido_BRL", "Gatilho", "Status", "Liberado_em", "ID_Transferencia",
    ]  # fmt: skip
    linhas = con.execute(
        """
        SELECT r.id, r.criado_em, pe.numero, u.nome AS profissional, r.valor_bruto_centavos,
               r.taxa_centavos, r.valor_liquido_centavos, r.gatilho, r.status, r.liberado_em,
               r.provedor_transferencia_id
        FROM public.repasses r
        LEFT JOIN public.contratos c ON c.id = r.contrato_id
        LEFT JOIN public.pedidos pe ON pe.id = c.pedido_id
        LEFT JOIN public.usuarios u ON u.id = r.profissional_id
        WHERE (%(de)s::timestamptz IS NULL OR r.criado_em >= %(de)s)
          AND (%(ate)s::timestamptz IS NULL OR r.criado_em < %(ate)s)
          AND (%(cidade)s::uuid IS NULL OR pe.cidade_id = %(cidade)s)
        ORDER BY r.criado_em DESC
        """,
        janela,
    ).fetchall()
    return cab, [
        [
            str(r["id"]),
            _data(r["criado_em"]),
            _codigo_pedido(r["numero"]),
            r["profissional"] or "",
            _reais(r["valor_bruto_centavos"], formato),
            _reais(r["taxa_centavos"], formato),
            _reais(r["valor_liquido_centavos"], formato),
            r["gatilho"] or "",
            r["status"] or "",
            _data(r["liberado_em"]),
            r["provedor_transferencia_id"] or "",
        ]  # fmt: skip
        for r in linhas
    ]


@router.post(
    "/{tipo}",
    response_model=RelatorioProntoOut,
    status_code=201,
    summary="Gera o relatório e devolve um código de uso único para baixar",
)
def pedir_relatorio(
    tipo: str,
    corpo: PedirRelatorioIn,
    operador: Operador = Depends(exigir(Permissao.RELATORIOS_EXPORTAR, Permissao.AUDITORIA_VER)),
    admin: AdminContexto = Depends(obter_admin),
    contexto: Contexto = Depends(obter_contexto),
) -> RelatorioProntoOut:
    if tipo not in TIPOS:
        raise HTTPException(404, "Relatório não encontrado.")
    exigida = Permissao.AUDITORIA_VER if tipo == "auditoria" else Permissao.RELATORIOS_EXPORTAR
    if not pode(operador.membro.papel, exigida):
        raise HTTPException(403, "Seu papel na equipe não permite isso.")
    if corpo.inicio and corpo.fim and corpo.fim < corpo.inicio:
        raise HTTPException(422, "O fim precisa ser depois do início.")
    cidade = como_uuid(corpo.cidade_id) if corpo.cidade_id else None
    de = datetime.combine(corpo.inicio, hora.min, tzinfo=UTC) if corpo.inicio else None
    ate = (
        datetime.combine(corpo.fim, hora.min, tzinfo=UTC) + timedelta(days=1) if corpo.fim else None
    )
    pessoais = pode(operador.membro.papel, Permissao.DADOS_PESSOAIS_REVELAR)

    with _banco(contexto).transacao() as con:
        cab, linhas = _gerar(con, tipo, de, ate, cidade, corpo.formato, pessoais)
        saida = io.StringIO()
        escritor = csv.writer(saida, delimiter=";" if corpo.formato == "excel_br" else ",")
        escritor.writerow(cab)
        escritor.writerows(linhas)
        conteudo = ("﻿" + saida.getvalue()).encode("utf-8")
        nome = f"trato_{tipo}_{datetime.now(UTC):%Y%m%d_%H%M}.csv"
        admin.auditoria.registrar(
            ator_id=operador.id,
            acao="relatorio.exportado",
            entidade="relatorios",
            depois={
                "relatorio": tipo,
                "inicio": corpo.inicio.isoformat() if corpo.inicio else None,
                "fim": corpo.fim.isoformat() if corpo.fim else None,
                "cidade_id": str(cidade) if cidade else None,
                "formato": corpo.formato,
                "linhas": len(linhas),
                "com_dados_pessoais": pessoais and tipo == "financeiro",
            },
            motivo=corpo.motivo,
        )
    codigo = _guardar(conteudo, nome, operador.id)
    return RelatorioProntoOut(
        codigo=codigo,
        nome_arquivo=nome,
        linhas=len(linhas),
        colunas=len(cab),
        com_dados_pessoais=pessoais and tipo == "financeiro",
    )


@router.get(
    "/baixar/{codigo}",
    summary="Baixa o arquivo pelo código de uso único (vale poucos minutos)",
)
def baixar(codigo: str) -> Response:
    with _trava:
        pronto = _prontos.pop(codigo, None)
    if pronto is None or pronto.expira < time.monotonic():
        raise HTTPException(404, "Este link já foi usado ou expirou. Gere o relatório de novo.")
    return Response(
        content=pronto.conteudo,
        media_type="text/csv; charset=utf-8",
        headers={
            "Content-Disposition": f'attachment; filename="{pronto.nome}"',
            "Cache-Control": "no-store",
        },
    )
