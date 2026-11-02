"""Rotas de Gestão de Cupons de Desconto e Promoções (Módulo 5).

Permite aos administradores e financeiros cadastrarem e controlarem cupons
para incentivo de novos pedidos e expansão do Trato.
"""

from __future__ import annotations

from datetime import datetime
from typing import Annotated

from fastapi import APIRouter, Depends, HTTPException, Query
from pydantic import BaseModel, Field

from trato.api.admin.contexto import AdminContexto, Operador, exigir, obter_admin
from trato.api.admin.papeis import Permissao
from trato.api.contexto import Contexto, obter_contexto
from trato.persistencia.comum import como_uuid

router = APIRouter(prefix="/v1/admin/cupons", tags=["admin: cupons e promocoes"])


class CupomOut(BaseModel):
    id: str
    codigo: str
    tipo: str
    valor: int
    valor_minimo_centavos: int
    limite_usos: int | None = None
    usos_atuais: int
    valido_ate: str | None = None
    ativo: bool
    criado_em: str


class CriarCupomIn(BaseModel):
    codigo: str = Field(min_length=3, max_length=30)
    tipo: str = Field(..., pattern="^(percentual|fixo)$")
    valor: int = Field(..., gt=0)
    valor_minimo_centavos: int = Field(default=0, ge=0)
    limite_usos: int | None = Field(default=None, gt=0)
    valido_ate: str | None = None
    motivo: str = Field(min_length=3, max_length=500)


class AlterarStatusCupomIn(BaseModel):
    ativo: bool
    motivo: str = Field(min_length=3, max_length=500)


@router.get("", response_model=list[CupomOut], summary="Listar cupons de desconto")
def listar_cupons(
    operador: Operador = Depends(exigir(Permissao.CUPONS_GERENCIAR)),
    contexto: Contexto = Depends(obter_contexto),
) -> list[CupomOut]:
    banco = contexto.extras.get("banco") if contexto.extras else None
    if banco is None:
        raise HTTPException(503, "Banco de dados não configurado.")

    with banco.transacao() as con:
        linhas = con.execute(
            """
            SELECT id, codigo, tipo, valor, valor_minimo_centavos, limite_usos, usos_atuais, valido_ate, ativo, criado_em
            FROM public.cupons
            ORDER BY criado_em DESC
            """
        ).fetchall()

        return [
            CupomOut(
                id=str(r["id"]),
                codigo=r["codigo"],
                tipo=r["tipo"],
                valor=int(r["valor"]),
                valor_minimo_centavos=int(r["valor_minimo_centavos"] or 0),
                limite_usos=int(r["limite_usos"]) if r["limite_usos"] is not None else None,
                usos_atuais=int(r["usos_atuais"] or 0),
                valido_ate=r["valido_ate"].isoformat() if r["valido_ate"] and hasattr(r["valido_ate"], "isoformat") else (str(r["valido_ate"]) if r["valido_ate"] else None),
                ativo=bool(r["ativo"]),
                criado_em=r["criado_em"].isoformat() if hasattr(r["criado_em"], "isoformat") else str(r["criado_em"]),
            )
            for r in linhas
        ]


@router.post("", response_model=CupomOut, status_code=201, summary="Cadastrar novo cupom")
def criar_cupom(
    corpo: CriarCupomIn,
    operador: Operador = Depends(exigir(Permissao.CUPONS_GERENCIAR)),
    admin: AdminContexto = Depends(obter_admin),
    contexto: Contexto = Depends(obter_contexto),
) -> CupomOut:
    banco = contexto.extras.get("banco") if contexto.extras else None
    if banco is None:
        raise HTTPException(503, "Banco de dados não configurado.")

    codigo_norm = corpo.codigo.strip().upper()
    val_ate = None
    if corpo.valido_ate:
        try:
            val_ate = datetime.fromisoformat(corpo.valido_ate.replace("Z", "+00:00"))
        except Exception:
            raise HTTPException(422, "Data de validade inválida. Formato ISO esperado.")

    with banco.transacao() as con:
        existente = con.execute("SELECT id FROM public.cupons WHERE codigo = %s", (codigo_norm,)).fetchone()
        if existente:
            raise HTTPException(409, f"O cupom '{codigo_norm}' já está cadastrado.")

        cup = con.execute(
            """
            INSERT INTO public.cupons (codigo, tipo, valor, valor_minimo_centavos, limite_usos, usos_atuais, valido_ate, ativo)
            VALUES (%s, %s, %s, %s, %s, 0, %s, true)
            RETURNING id, codigo, tipo, valor, valor_minimo_centavos, limite_usos, usos_atuais, valido_ate, ativo, criado_em
            """,
            (codigo_norm, corpo.tipo, corpo.valor, corpo.valor_minimo_centavos, corpo.limite_usos, val_ate),
        ).fetchone()

        admin.auditoria.registrar(
            ator_id=operador.id,
            acao="cupom.criado",
            entidade="cupons",
            entidade_id=str(cup["id"]),
            depois={"codigo": codigo_norm, "tipo": corpo.tipo, "valor": corpo.valor},
            motivo=corpo.motivo,
        )

        return CupomOut(
            id=str(cup["id"]),
            codigo=cup["codigo"],
            tipo=cup["tipo"],
            valor=int(cup["valor"]),
            valor_minimo_centavos=int(cup["valor_minimo_centavos"]),
            limite_usos=int(cup["limite_usos"]) if cup["limite_usos"] is not None else None,
            usos_atuais=0,
            valido_ate=cup["valido_ate"].isoformat() if cup["valido_ate"] and hasattr(cup["valido_ate"], "isoformat") else None,
            ativo=True,
            criado_em=cup["criado_em"].isoformat() if hasattr(cup["criado_em"], "isoformat") else str(cup["criado_em"]),
        )


@router.patch("/{cupom_id}/status", response_model=CupomOut, summary="Ativar ou desativar cupom")
def alterar_status_cupom(
    cupom_id: str,
    corpo: AlterarStatusCupomIn,
    operador: Operador = Depends(exigir(Permissao.CUPONS_GERENCIAR)),
    admin: AdminContexto = Depends(obter_admin),
    contexto: Contexto = Depends(obter_contexto),
) -> CupomOut:
    banco = contexto.extras.get("banco") if contexto.extras else None
    if banco is None:
        raise HTTPException(503, "Banco de dados não configurado.")
    uid = como_uuid(cupom_id)
    if uid is None:
        raise HTTPException(404, "Cupom não encontrado.")

    with banco.transacao() as con:
        cup = con.execute("SELECT * FROM public.cupons WHERE id = %s", (uid,)).fetchone()
        if cup is None:
            raise HTTPException(404, "Cupom não encontrado.")

        con.execute("UPDATE public.cupons SET ativo = %s, atualizado_em = now() WHERE id = %s", (corpo.ativo, uid))

        admin.auditoria.registrar(
            ator_id=operador.id,
            acao="cupom.ativado" if corpo.ativo else "cupom.desativado",
            entidade="cupons",
            entidade_id=str(uid),
            depois={"ativo": corpo.ativo, "codigo": cup["codigo"]},
            motivo=corpo.motivo,
        )

        return CupomOut(
            id=str(uid),
            codigo=cup["codigo"],
            tipo=cup["tipo"],
            valor=int(cup["valor"]),
            valor_minimo_centavos=int(cup["valor_minimo_centavos"] or 0),
            limite_usos=int(cup["limite_usos"]) if cup["limite_usos"] is not None else None,
            usos_atuais=int(cup["usos_atuais"] or 0),
            valido_ate=cup["valido_ate"].isoformat() if cup["valido_ate"] and hasattr(cup["valido_ate"], "isoformat") else None,
            ativo=corpo.ativo,
            criado_em=cup["criado_em"].isoformat() if hasattr(cup["criado_em"], "isoformat") else str(cup["criado_em"]),
        )


@router.delete("/{cupom_id}", summary="Excluir cupom sem histórico")
def excluir_cupom(
    cupom_id: str,
    motivo: str = Query(..., min_length=3),
    operador: Operador = Depends(exigir(Permissao.CUPONS_GERENCIAR)),
    admin: AdminContexto = Depends(obter_admin),
    contexto: Contexto = Depends(obter_contexto),
) -> dict[str, str]:
    banco = contexto.extras.get("banco") if contexto.extras else None
    if banco is None:
        raise HTTPException(503, "Banco de dados não configurado.")
    uid = como_uuid(cupom_id)
    if uid is None:
        raise HTTPException(404, "Cupom não encontrado.")

    with banco.transacao() as con:
        cup = con.execute("SELECT codigo, usos_atuais FROM public.cupons WHERE id = %s", (uid,)).fetchone()
        if cup is None:
            raise HTTPException(404, "Cupom não encontrado.")

        if (cup["usos_atuais"] or 0) > 0:
            # Desativa para preservar integridade
            con.execute("UPDATE public.cupons SET ativo = false, atualizado_em = now() WHERE id = %s", (uid,))
        else:
            con.execute("DELETE FROM public.cupons WHERE id = %s", (uid,))

        admin.auditoria.registrar(
            ator_id=operador.id,
            acao="cupom.excluido",
            entidade="cupons",
            entidade_id=str(uid),
            depois={"codigo": cup["codigo"]},
            motivo=motivo,
        )

        return {"mensagem": f"Cupom '{cup['codigo']}' removido/desativado com sucesso."}
