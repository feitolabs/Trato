"""Rotas da Central Antifraude e Gestão de Risco (Módulo 3).

Permite monitorar comportamentos anômalos, travar saques de forma preventiva
e auditar bloqueios de segurança.
"""

from __future__ import annotations

from datetime import datetime, timezone
from typing import Annotated

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel, Field

from trato.api.admin.contexto import AdminContexto, Operador, exigir, obter_admin
from trato.api.admin.papeis import Permissao
from trato.api.contexto import Contexto, obter_contexto
from trato.persistencia.comum import como_uuid

router = APIRouter(prefix="/v1/admin/risco", tags=["admin: risco e antifraude"])


class AlertaRiscoOut(BaseModel):
    id: str
    usuario_id: str | None = None
    usuario_nome: str | None = None
    tipo: str
    severidade: str
    detalhes: str
    resolvido: bool = False
    criado_em: str


class AcaoRiscoIn(BaseModel):
    usuario_id: str
    motivo: str = Field(min_length=3, max_length=500)


class ResolverAlertaIn(BaseModel):
    motivo: str = Field(min_length=3, max_length=500)


@router.get("/alertas", response_model=list[AlertaRiscoOut], summary="Listar alertas de risco e antifraude")
def listar_alertas(
    operador: Operador = Depends(exigir(Permissao.RISCO_VER)),
    contexto: Contexto = Depends(obter_contexto),
) -> list[AlertaRiscoOut]:
    banco = contexto.extras.get("banco") if contexto.extras else None
    if banco is None:
        raise HTTPException(503, "Banco de dados não configurado.")

    alertas: list[AlertaRiscoOut] = []
    with banco.transacao() as con:
        # 1. Alertas persistidos na tabela
        linhas = con.execute(
            """
            SELECT a.id, a.usuario_id, u.nome as usuario_nome, a.tipo, a.severidade, a.detalhes, a.resolvido, a.criado_em
            FROM public.alertas_risco a
            LEFT JOIN public.usuarios u ON u.id = a.usuario_id
            ORDER BY a.resolvido ASC, a.criado_em DESC
            LIMIT 50
            """
        ).fetchall()

        for r in linhas:
            alertas.append(
                AlertaRiscoOut(
                    id=str(r["id"]),
                    usuario_id=str(r["usuario_id"]) if r["usuario_id"] else None,
                    usuario_nome=r["usuario_nome"] or "Usuário do sistema",
                    tipo=r["tipo"],
                    severidade=r["severidade"],
                    detalhes=r["detalhes"],
                    resolvido=r["resolvido"],
                    criado_em=r["criado_em"].isoformat() if hasattr(r["criado_em"], "isoformat") else str(r["criado_em"]),
                )
            )

        # 2. Se a tabela tiver poucos registros, adiciona detecções automáticas baseadas no estado atual do banco
        if len(alertas) < 3:
            # Detecta disputas ativas
            disputas = con.execute(
                """
                SELECT d.id, d.pedido_id, p.titulo, p.cliente_id, u.nome as cliente_nome, p.valor_centavos
                FROM public.disputas d
                JOIN public.pedidos p ON p.id = d.pedido_id
                JOIN public.usuarios u ON u.id = p.cliente_id
                WHERE d.status in ('aberta', 'em_analise', 'aguardando_segunda_pessoa')
                LIMIT 5
                """
            ).fetchall()

            for d in disputas:
                alertas.append(
                    AlertaRiscoOut(
                        id=f"disp-{d['id']}",
                        usuario_id=str(d["cliente_id"]),
                        usuario_nome=d["cliente_nome"],
                        tipo="disputa_financeira",
                        severidade="alta",
                        detalhes=f"Disputa em aberto no pedido '{d['titulo']}' (R$ {d['valor_centavos'] / 100:.2f}). Reter liquidação.",
                        resolvido=False,
                        criado_em=datetime.now(timezone.utc).isoformat(),
                    )
                )

            # Detecta pedidos de alto valor (anomalia)
            altos = con.execute(
                """
                SELECT p.id, p.titulo, p.cliente_id, u.nome as cliente_nome, p.valor_centavos
                FROM public.pedidos p
                JOIN public.usuarios u ON u.id = p.cliente_id
                WHERE p.valor_centavos >= 500000 and p.status in ('criado', 'aberto', 'em_execucao')
                LIMIT 5
                """
            ).fetchall()

            for p in altos:
                alertas.append(
                    AlertaRiscoOut(
                        id=f"val-{p['id']}",
                        usuario_id=str(p["cliente_id"]),
                        usuario_nome=p["cliente_nome"],
                        tipo="valor_atípico",
                        severidade="media",
                        detalhes=f"Pedido com valor elevado: R$ {p['valor_centavos'] / 100:.2f} ('{p['titulo']}'). Verificar consistência.",
                        resolvido=False,
                        criado_em=datetime.now(timezone.utc).isoformat(),
                    )
                )

    return alertas


@router.post("/bloqueio-preventivo", summary="Aplicar bloqueio preventivo a conta suspeita")
def aplicar_bloqueio_preventivo(
    corpo: AcaoRiscoIn,
    operador: Operador = Depends(exigir(Permissao.RISCO_DECIDIR)),
    admin: AdminContexto = Depends(obter_admin),
    contexto: Contexto = Depends(obter_contexto),
) -> dict[str, str]:
    banco = contexto.extras.get("banco") if contexto.extras else None
    if banco is None:
        raise HTTPException(503, "Banco de dados não configurado.")
    uid = como_uuid(corpo.usuario_id)
    if uid is None:
        raise HTTPException(404, "Usuário não encontrado.")

    with banco.transacao() as con:
        usr = con.execute("SELECT id, nome, status FROM public.usuarios WHERE id = %s", (uid,)).fetchone()
        if usr is None:
            raise HTTPException(404, "Usuário não encontrado.")
        con.execute("UPDATE public.usuarios SET status = 'bloqueado', atualizado_em = now() WHERE id = %s", (uid,))
        admin.auditoria.registrar(
            ator_id=operador.id,
            acao="risco.bloqueio_preventivo",
            entidade="usuarios",
            entidade_id=str(uid),
            depois={"status": "bloqueado", "anterior": usr["status"]},
            motivo=corpo.motivo,
        )
        return {"mensagem": f"Usuário {usr['nome']} bloqueado preventivamente com sucesso."}


@router.post("/travar-saque", summary="Travar saques e repasses de profissional sob investigação")
def travar_saque(
    corpo: AcaoRiscoIn,
    operador: Operador = Depends(exigir(Permissao.RISCO_DECIDIR)),
    admin: AdminContexto = Depends(obter_admin),
    contexto: Contexto = Depends(obter_contexto),
) -> dict[str, str]:
    banco = contexto.extras.get("banco") if contexto.extras else None
    if banco is None:
        raise HTTPException(503, "Banco de dados não configurado.")
    uid = como_uuid(corpo.usuario_id)
    if uid is None:
        raise HTTPException(404, "Usuário não encontrado.")

    with banco.transacao() as con:
        prof = con.execute("SELECT usuario_id FROM public.perfis_profissional WHERE usuario_id = %s", (uid,)).fetchone()
        if prof is None:
            raise HTTPException(404, "Perfil profissional não encontrado.")
        # Registra alerta crítico e trava no usuário
        con.execute(
            """
            INSERT INTO public.alertas_risco (usuario_id, tipo, severidade, detalhes, resolvido)
            VALUES (%s, 'saque_travado', 'critica', %s, false)
            """,
            (uid, f"Saque travado preventivamente. Motivo: {corpo.motivo}"),
        )
        con.execute("UPDATE public.usuarios SET status = 'restrito', atualizado_em = now() WHERE id = %s", (uid,))
        admin.auditoria.registrar(
            ator_id=operador.id,
            acao="risco.saque_travado",
            entidade="perfis_profissional",
            entidade_id=str(uid),
            depois={"saque_bloqueado": True},
            motivo=corpo.motivo,
        )
        return {"mensagem": "Saques travados e conta colocada em modo restrito com auditoria."}


@router.post("/alertas/{alerta_id}/resolver", summary="Resolver alerta de risco")
def resolver_alerta(
    alerta_id: str,
    corpo: ResolverAlertaIn,
    operador: Operador = Depends(exigir(Permissao.RISCO_DECIDIR)),
    admin: AdminContexto = Depends(obter_admin),
    contexto: Contexto = Depends(obter_contexto),
) -> dict[str, str]:
    banco = contexto.extras.get("banco") if contexto.extras else None
    if banco is None:
        raise HTTPException(503, "Banco de dados não configurado.")
    uid = como_uuid(alerta_id)
    if uid is not None:
        with banco.transacao() as con:
            con.execute(
                "UPDATE public.alertas_risco SET resolvido = true, resolvido_em = now(), resolvido_por = %s WHERE id = %s",
                (operador.id, uid),
            )
            admin.auditoria.registrar(
                ator_id=operador.id,
                acao="risco.alerta_resolvido",
                entidade="alertas_risco",
                entidade_id=str(uid),
                depois={"resolvido": True},
                motivo=corpo.motivo,
            )
    return {"mensagem": "Alerta resolvido com sucesso."}
