"""Rotas de Cupons e promoções (RF-CUP-01 a RF-CUP-03).

Código único e sem espaços, percentual entre 1 e 100, fim depois do início. Desativar preserva o
histórico; excluir só vale para cupom nunca usado.
"""

from __future__ import annotations

from datetime import datetime
from typing import Any

from fastapi import APIRouter, Depends, HTTPException, Query
from pydantic import BaseModel, Field

from trato.api.admin.contexto import AdminContexto, Operador, exigir, obter_admin
from trato.api.admin.papeis import Permissao
from trato.api.contexto import Contexto, obter_contexto
from trato.persistencia.comum import como_uuid

router = APIRouter(prefix="/v1/admin/cupons", tags=["admin: cupons e promocoes"])

_COLUNAS = (
    "id, codigo, tipo, valor, valor_minimo_centavos, limite_usos, usos_atuais, valido_ate, "
    "valido_desde, campanha, limite_por_usuario, ativo, criado_em"
)


class CupomOut(BaseModel):
    id: str
    codigo: str
    tipo: str
    valor: int
    valor_minimo_centavos: int
    limite_usos: int | None = None
    usos_atuais: int
    valido_ate: str | None = None
    valido_desde: str | None = None
    campanha: str | None = None
    limite_por_usuario: int | None = None
    ativo: bool
    criado_em: str


class CriarCupomIn(BaseModel):
    codigo: str = Field(min_length=3, max_length=30)
    tipo: str = Field(..., pattern="^(percentual|fixo)$")
    valor: int = Field(..., gt=0)
    valor_minimo_centavos: int = Field(default=0, ge=0)
    limite_usos: int | None = Field(default=None, gt=0)
    limite_por_usuario: int | None = Field(default=None, gt=0)
    valido_desde: str | None = None
    valido_ate: str | None = None
    campanha: str | None = Field(default=None, max_length=80)
    motivo: str = Field(min_length=10, max_length=500)


class AlterarStatusCupomIn(BaseModel):
    ativo: bool
    motivo: str = Field(min_length=10, max_length=500)


def _banco(contexto: Contexto) -> Any:
    banco = contexto.extras.get("banco") if contexto.extras else None
    if banco is None:
        raise HTTPException(503, "Banco de dados não configurado.")
    return banco


def _iso(valor: Any) -> str | None:
    if valor is None:
        return None
    return valor.isoformat() if hasattr(valor, "isoformat") else str(valor)


def _data(texto: str | None, campo: str) -> datetime | None:
    if not texto:
        return None
    try:
        return datetime.fromisoformat(texto.replace("Z", "+00:00"))
    except ValueError:
        raise HTTPException(422, f"{campo} inválido. Use o formato AAAA-MM-DD.") from None


def _saida(r: Any, *, ativo: bool | None = None) -> CupomOut:
    return CupomOut(
        id=str(r["id"]),
        codigo=r["codigo"],
        tipo=r["tipo"],
        valor=int(r["valor"]),
        valor_minimo_centavos=int(r["valor_minimo_centavos"] or 0),
        limite_usos=int(r["limite_usos"]) if r["limite_usos"] is not None else None,
        usos_atuais=int(r["usos_atuais"] or 0),
        valido_ate=_iso(r["valido_ate"]),
        valido_desde=_iso(r.get("valido_desde")),
        campanha=r.get("campanha"),
        limite_por_usuario=r.get("limite_por_usuario"),
        ativo=bool(r["ativo"]) if ativo is None else ativo,
        criado_em=_iso(r["criado_em"]) or "",
    )


@router.get("", response_model=list[CupomOut], summary="Listar cupons de desconto")
def listar_cupons(
    operador: Operador = Depends(exigir(Permissao.CUPONS_GERENCIAR)),
    contexto: Contexto = Depends(obter_contexto),
) -> list[CupomOut]:
    with _banco(contexto).transacao() as con:
        linhas = con.execute(
            f"SELECT {_COLUNAS} FROM public.cupons ORDER BY criado_em DESC"  # noqa: S608
        ).fetchall()
        return [_saida(r) for r in linhas]


@router.post("", response_model=CupomOut, status_code=201, summary="Cadastrar novo cupom")
def criar_cupom(
    corpo: CriarCupomIn,
    operador: Operador = Depends(exigir(Permissao.CUPONS_GERENCIAR)),
    admin: AdminContexto = Depends(obter_admin),
    contexto: Contexto = Depends(obter_contexto),
) -> CupomOut:
    codigo = corpo.codigo.strip().upper()
    if any(c.isspace() for c in codigo):
        raise HTTPException(422, "O código não pode ter espaços.")
    if corpo.tipo == "percentual" and not 1 <= corpo.valor <= 100:
        raise HTTPException(422, "O percentual deve ficar entre 1 e 100.")
    desde = _data(corpo.valido_desde, "Início")
    ate = _data(corpo.valido_ate, "Fim")
    if desde and ate and ate <= desde:
        raise HTTPException(422, "O fim precisa ser depois do início.")
    campanha = (corpo.campanha or "").strip() or None

    with _banco(contexto).transacao() as con:
        if con.execute("SELECT 1 FROM public.cupons WHERE codigo = %s", (codigo,)).fetchone():
            raise HTTPException(409, f"O cupom '{codigo}' já está cadastrado.")
        cup = con.execute(
            f"""
            INSERT INTO public.cupons
              (codigo, tipo, valor, valor_minimo_centavos, limite_usos, usos_atuais,
               valido_desde, valido_ate, campanha, limite_por_usuario, ativo)
            VALUES (%s, %s, %s, %s, %s, 0, %s, %s, %s, %s, true)
            RETURNING {_COLUNAS}
            """,  # noqa: S608
            (
                codigo,
                corpo.tipo,
                corpo.valor,
                corpo.valor_minimo_centavos,
                corpo.limite_usos,
                desde,
                ate,
                campanha,
                corpo.limite_por_usuario,
            ),
        ).fetchone()
        admin.auditoria.registrar(
            ator_id=operador.id,
            acao="cupom.criado",
            entidade="cupons",
            entidade_id=str(cup["id"]),
            depois={"codigo": codigo, "tipo": corpo.tipo, "valor": corpo.valor},
            motivo=corpo.motivo,
        )
        return _saida(cup)


@router.patch("/{cupom_id}/status", response_model=CupomOut, summary="Ativar ou desativar cupom")
def alterar_status_cupom(
    cupom_id: str,
    corpo: AlterarStatusCupomIn,
    operador: Operador = Depends(exigir(Permissao.CUPONS_GERENCIAR)),
    admin: AdminContexto = Depends(obter_admin),
    contexto: Contexto = Depends(obter_contexto),
) -> CupomOut:
    uid = como_uuid(cupom_id)
    if uid is None:
        raise HTTPException(404, "Cupom não encontrado.")
    with _banco(contexto).transacao() as con:
        cup = con.execute(
            f"SELECT {_COLUNAS} FROM public.cupons WHERE id = %s",  # noqa: S608
            (uid,),
        ).fetchone()
        if cup is None:
            raise HTTPException(404, "Cupom não encontrado.")
        con.execute(
            "UPDATE public.cupons SET ativo = %s, atualizado_em = now() WHERE id = %s",
            (corpo.ativo, uid),
        )
        admin.auditoria.registrar(
            ator_id=operador.id,
            acao="cupom.ativado" if corpo.ativo else "cupom.desativado",
            entidade="cupons",
            entidade_id=str(uid),
            depois={"ativo": corpo.ativo, "codigo": cup["codigo"]},
            motivo=corpo.motivo,
        )
        return _saida(cup, ativo=corpo.ativo)


@router.delete("/{cupom_id}", summary="Excluir cupom nunca usado")
def excluir_cupom(
    cupom_id: str,
    motivo: str = Query(..., min_length=10),
    operador: Operador = Depends(exigir(Permissao.CUPONS_GERENCIAR)),
    admin: AdminContexto = Depends(obter_admin),
    contexto: Contexto = Depends(obter_contexto),
) -> dict[str, str]:
    uid = como_uuid(cupom_id)
    if uid is None:
        raise HTTPException(404, "Cupom não encontrado.")
    with _banco(contexto).transacao() as con:
        cup = con.execute(
            "SELECT codigo, usos_atuais FROM public.cupons WHERE id = %s", (uid,)
        ).fetchone()
        if cup is None:
            raise HTTPException(404, "Cupom não encontrado.")
        if (cup["usos_atuais"] or 0) > 0:
            raise HTTPException(
                409,
                "Este cupom já foi usado e não pode ser excluído. Desative-o: o histórico fica.",
            )
        con.execute("DELETE FROM public.cupons WHERE id = %s", (uid,))
        admin.auditoria.registrar(
            ator_id=operador.id,
            acao="cupom.excluido",
            entidade="cupons",
            entidade_id=str(uid),
            depois={"codigo": cup["codigo"]},
            motivo=motivo,
        )
        return {"mensagem": f"Cupom '{cup['codigo']}' excluído."}
