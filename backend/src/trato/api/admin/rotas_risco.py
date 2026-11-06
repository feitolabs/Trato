"""Rotas de Risco e antifraude (RF-RIS-01 a RF-RIS-05).

Alertas com severidade, tipo, usuário, pedido, status (em aberto, em análise, resolvido) e
responsável. Resolver exige motivo e resultado. Travar saques e Bloqueio preventivo exigem motivo e
têm ação contrária (destravar, desbloquear), também com motivo. Os limites de detecção vêm de
Configurações: sem limite aprovado, nada é detectado (nenhum número fica escrito no código).
"""

from __future__ import annotations

from typing import Any

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
    usuario_tipo: str | None = None
    usuario_status: str | None = None
    pedido_id: str | None = None
    pedido_numero: int | None = None
    tipo: str
    severidade: str
    detalhes: str
    status: str = "em_aberto"
    resultado: str | None = None
    responsavel: str | None = None
    resolvido: bool = False
    criado_em: str


class AcaoRiscoIn(BaseModel):
    usuario_id: str
    motivo: str = Field(min_length=10, max_length=500)


class ResolverAlertaIn(BaseModel):
    motivo: str = Field(min_length=10, max_length=500)
    resultado: str = Field(default="procedente", pattern="^(procedente|improcedente)$")


class AssumirAlertaIn(BaseModel):
    motivo: str = Field(min_length=10, max_length=500)


def _banco(contexto: Contexto) -> Any:
    banco = contexto.extras.get("banco") if contexto.extras else None
    if banco is None:
        raise HTTPException(503, "Banco de dados não configurado.")
    return banco


def _iso(valor: Any) -> str:
    return valor.isoformat() if hasattr(valor, "isoformat") else str(valor)


def _limites(con: Any) -> tuple[int | None, int | None]:
    """(limite de valor atípico, teto do pedido) da configuração vigente, se já aprovados."""
    linhas = con.execute(
        "select p.chave, p.valor from public.config_parametros p "
        "join public.config_versoes v on v.id = p.versao_id and v.status = 'vigente' "
        "where p.chave in ('limite_valor_atipico_centavos', 'valor_maximo_servico_centavos') "
        "and p.escopo_tipo = 'global'"
    ).fetchall()
    por_chave = {l["chave"]: int(l["valor"]) for l in linhas}  # noqa: E741
    return por_chave.get("limite_valor_atipico_centavos"), por_chave.get(
        "valor_maximo_servico_centavos"
    )


def _reais(centavos: int) -> str:
    """12345678 -> "R$ 123.456,78"."""
    inteiro, cents = divmod(abs(centavos), 100)
    return f"R$ {inteiro:,}".replace(",", ".") + f",{cents:02d}"


def _detectar_valores_atipicos(con: Any) -> None:
    """Cria o alerta de valor atípico dos pedidos acima do limite configurado (um por pedido)."""
    limite, teto = _limites(con)
    if limite is None:
        return
    candidatos = con.execute(
        """
        select p.id, p.cliente_id,
               coalesce(c.valor_total_centavos, p.faixa_preco_max_centavos, 0) as valor
        from public.pedidos p
        left join public.contratos c on c.pedido_id = p.id
        where coalesce(c.valor_total_centavos, p.faixa_preco_max_centavos, 0) > %s
          and not exists (select 1 from public.alertas_risco a
                          where a.pedido_id = p.id and a.tipo = 'valor_atipico')
        """,
        (limite,),
    ).fetchall()
    for c in candidatos:
        valor = int(c["valor"])
        acima_do_teto = teto is not None and valor > teto
        detalhes = (
            f"Pedido criado com valor de {_reais(valor)}. "
            f"O limite de atipicidade é {_reais(limite)}"
        )
        if acima_do_teto:
            detalhes += (
                f" e o teto do pedido é {_reais(teto)}, então a criação deveria ter sido barrada."
            )
        else:
            detalhes += "."
        con.execute(
            "insert into public.alertas_risco (usuario_id, pedido_id, tipo, severidade, detalhes) "
            "values (%s, %s, 'valor_atipico', %s, %s) "
            "on conflict (pedido_id, tipo) where pedido_id is not null do nothing",
            (c["cliente_id"], c["id"], "critica" if acima_do_teto else "alta", detalhes),
        )


@router.get(
    "/alertas", response_model=list[AlertaRiscoOut], summary="Listar alertas de risco e antifraude"
)
def listar_alertas(
    operador: Operador = Depends(exigir(Permissao.RISCO_VER)),
    contexto: Contexto = Depends(obter_contexto),
) -> list[AlertaRiscoOut]:
    with _banco(contexto).transacao() as con:
        _detectar_valores_atipicos(con)
        linhas = con.execute(
            """
            SELECT a.id, a.usuario_id, u.nome AS usuario_nome, u.status AS usuario_status,
                   a.pedido_id, p.numero AS pedido_numero, a.tipo, a.severidade, a.detalhes,
                   a.status, a.resultado, r.nome AS responsavel, a.resolvido, a.criado_em,
                   CASE WHEN EXISTS (SELECT 1 FROM public.equipe e
                                    WHERE e.usuario_id = a.usuario_id)
                        THEN 'equipe'
                        WHEN EXISTS (SELECT 1 FROM public.perfis_profissional pp
                                     WHERE pp.usuario_id = a.usuario_id AND pp.status = 'aprovado')
                        THEN 'profissional'
                        ELSE 'cliente' END AS usuario_tipo
            FROM public.alertas_risco a
            LEFT JOIN public.usuarios u ON u.id = a.usuario_id
            LEFT JOIN public.usuarios r ON r.id = a.responsavel_id
            LEFT JOIN public.pedidos p ON p.id = a.pedido_id
            ORDER BY a.resolvido ASC,
                     CASE a.severidade WHEN 'critica' THEN 0 WHEN 'alta' THEN 1
                                       WHEN 'media' THEN 2 ELSE 3 END,
                     a.criado_em DESC
            LIMIT 200
            """
        ).fetchall()
    return [
        AlertaRiscoOut(
            id=str(r["id"]),
            usuario_id=str(r["usuario_id"]) if r["usuario_id"] else None,
            usuario_nome=r["usuario_nome"],
            usuario_tipo=r["usuario_tipo"],
            usuario_status=r["usuario_status"],
            pedido_id=str(r["pedido_id"]) if r["pedido_id"] else None,
            pedido_numero=r["pedido_numero"],
            tipo=r["tipo"],
            severidade=r["severidade"],
            detalhes=r["detalhes"],
            status="resolvido" if r["resolvido"] else r["status"],
            resultado=r["resultado"],
            responsavel=r["responsavel"],
            resolvido=bool(r["resolvido"]),
            criado_em=_iso(r["criado_em"]),
        )
        for r in linhas
    ]


@router.post("/alertas/{alerta_id}/assumir", summary="Assumir o alerta (vai para Em análise)")
def assumir_alerta(
    alerta_id: str,
    corpo: AssumirAlertaIn,
    operador: Operador = Depends(exigir(Permissao.RISCO_DECIDIR)),
    admin: AdminContexto = Depends(obter_admin),
    contexto: Contexto = Depends(obter_contexto),
) -> dict[str, str]:
    uid = como_uuid(alerta_id)
    if uid is None:
        raise HTTPException(404, "Alerta não encontrado.")
    with _banco(contexto).transacao() as con:
        alvo = con.execute(
            "select resolvido from public.alertas_risco where id = %s for update", (uid,)
        ).fetchone()
        if alvo is None:
            raise HTTPException(404, "Alerta não encontrado.")
        if alvo["resolvido"]:
            raise HTTPException(409, "Este alerta já foi resolvido.")
        con.execute(
            "update public.alertas_risco set status = 'em_analise', "
            "responsavel_id = %s where id = %s",
            (operador.id, uid),
        )
        admin.auditoria.registrar(
            ator_id=operador.id,
            acao="risco.alerta_assumido",
            entidade="alertas_risco",
            entidade_id=str(uid),
            depois={"status": "em_analise"},
            motivo=corpo.motivo,
        )
    return {"mensagem": "Alerta em análise."}


@router.post(
    "/alertas/{alerta_id}/resolver", summary="Resolver alerta (procedente ou improcedente)"
)
def resolver_alerta(
    alerta_id: str,
    corpo: ResolverAlertaIn,
    operador: Operador = Depends(exigir(Permissao.RISCO_DECIDIR)),
    admin: AdminContexto = Depends(obter_admin),
    contexto: Contexto = Depends(obter_contexto),
) -> dict[str, str]:
    uid = como_uuid(alerta_id)
    if uid is None:
        raise HTTPException(404, "Alerta não encontrado.")
    with _banco(contexto).transacao() as con:
        alvo = con.execute(
            "select resolvido from public.alertas_risco where id = %s for update", (uid,)
        ).fetchone()
        if alvo is None:
            raise HTTPException(404, "Alerta não encontrado.")
        if alvo["resolvido"]:
            raise HTTPException(409, "Este alerta já foi resolvido.")
        con.execute(
            "update public.alertas_risco set resolvido = true, status = 'resolvido', "
            "resultado = %s, resolvido_em = now(), resolvido_por = %s where id = %s",
            (corpo.resultado, operador.id, uid),
        )
        admin.auditoria.registrar(
            ator_id=operador.id,
            acao="risco.alerta_resolvido",
            entidade="alertas_risco",
            entidade_id=str(uid),
            depois={"resolvido": True, "resultado": corpo.resultado},
            motivo=corpo.motivo,
        )
    return {"mensagem": "Alerta resolvido com sucesso."}


def _mudar_status_do_usuario(
    contexto: Contexto,
    admin: AdminContexto,
    operador: Operador,
    corpo: AcaoRiscoIn,
    *,
    de: tuple[str, ...],
    para: str,
    acao: str,
    mensagem: str,
    exige_profissional: bool = False,
) -> dict[str, str]:
    uid = como_uuid(corpo.usuario_id)
    if uid is None:
        raise HTTPException(404, "Usuário não encontrado.")
    with _banco(contexto).transacao() as con:
        usr = con.execute(
            "select id, nome, status from public.usuarios where id = %s for update", (uid,)
        ).fetchone()
        if usr is None:
            raise HTTPException(404, "Usuário não encontrado.")
        if (
            exige_profissional
            and con.execute(
                "select 1 from public.perfis_profissional where usuario_id = %s", (uid,)
            ).fetchone()
            is None
        ):
            raise HTTPException(404, "Perfil profissional não encontrado.")
        if usr["status"] not in de:
            raise HTTPException(409, f"Nada a fazer: a conta está com status '{usr['status']}'.")
        con.execute(
            "update public.usuarios set status = %s, atualizado_em = now() where id = %s",
            (para, uid),
        )
        admin.auditoria.registrar(
            ator_id=operador.id,
            acao=acao,
            entidade="usuarios",
            entidade_id=str(uid),
            antes={"status": usr["status"]},
            depois={"status": para},
            motivo=corpo.motivo,
        )
        return {"mensagem": mensagem.format(nome=usr["nome"])}


@router.post("/bloqueio-preventivo", summary="Bloqueio preventivo da conta (reversível)")
def aplicar_bloqueio_preventivo(
    corpo: AcaoRiscoIn,
    operador: Operador = Depends(exigir(Permissao.RISCO_DECIDIR)),
    admin: AdminContexto = Depends(obter_admin),
    contexto: Contexto = Depends(obter_contexto),
) -> dict[str, str]:
    return _mudar_status_do_usuario(
        contexto, admin, operador, corpo,
        de=("ativo", "restrito"), para="bloqueado", acao="risco.bloqueio_preventivo",
        mensagem="Conta de {nome} bloqueada.",
    )  # fmt: skip


@router.post("/desbloqueio", summary="Desfaz o bloqueio preventivo")
def desbloquear(
    corpo: AcaoRiscoIn,
    operador: Operador = Depends(exigir(Permissao.RISCO_DECIDIR)),
    admin: AdminContexto = Depends(obter_admin),
    contexto: Contexto = Depends(obter_contexto),
) -> dict[str, str]:
    return _mudar_status_do_usuario(
        contexto, admin, operador, corpo,
        de=("bloqueado",), para="ativo", acao="risco.desbloqueio",
        mensagem="Conta de {nome} desbloqueada.",
    )  # fmt: skip


@router.post("/travar-saque", summary="Travar saques e repasses de um profissional (reversível)")
def travar_saque(
    corpo: AcaoRiscoIn,
    operador: Operador = Depends(exigir(Permissao.RISCO_DECIDIR)),
    admin: AdminContexto = Depends(obter_admin),
    contexto: Contexto = Depends(obter_contexto),
) -> dict[str, str]:
    return _mudar_status_do_usuario(
        contexto, admin, operador, corpo,
        de=("ativo",), para="restrito", acao="risco.saque_travado",
        mensagem="Saques de {nome} travados.", exige_profissional=True,
    )  # fmt: skip


@router.post("/destravar-saque", summary="Destrava os saques de um profissional")
def destravar_saque(
    corpo: AcaoRiscoIn,
    operador: Operador = Depends(exigir(Permissao.RISCO_DECIDIR)),
    admin: AdminContexto = Depends(obter_admin),
    contexto: Contexto = Depends(obter_contexto),
) -> dict[str, str]:
    return _mudar_status_do_usuario(
        contexto, admin, operador, corpo,
        de=("restrito",), para="ativo", acao="risco.saque_destravado",
        mensagem="Saques de {nome} liberados.", exige_profissional=True,
    )  # fmt: skip
