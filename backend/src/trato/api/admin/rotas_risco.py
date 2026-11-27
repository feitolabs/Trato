"""Rotas de Risco e antifraude (RF-RIS-01 a RF-RIS-05).

Alertas com severidade, tipo, usuário, pedido, status (em aberto, em análise, resolvido) e
responsável. Resolver exige motivo e resultado. Travar saques e Bloqueio preventivo exigem motivo e
têm ação contrária (destravar, desbloquear), também com motivo. Atenção: só a trava POR FRAUDE
(com limite e data final) adia a liberação no livro; pagamento manual ou no Stripe não é bloqueado.
Os limites de detecção
vêm de Configurações: sem limite aprovado, nada é detectado (nenhum número fica escrito no código).
"""

from __future__ import annotations

from typing import Any

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel, Field, StrictBool, StrictInt

from trato.api import medidas
from trato.api.admin.contexto import (
    AdminContexto,
    Operador,
    exigir,
    obter_admin,
    proteger_conta_da_equipe,
)
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
    trava_fraude_vigente: bool = Field(
        False, description="Há trava de saque por fraude em vigor para este usuário (20.6)."
    )
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
    motivo_usuario: str | None = Field(None, max_length=2000, description="O usuário lê (20.4).")
    clausulas: list[str] = Field(default_factory=list, max_length=20)


# ação antiga -> (tipo da medida criada, tipos que ela encerra)
_MEDIDA_DA_ACAO = {
    "risco.bloqueio_preventivo": ("bloqueio_preventivo", ()),
    "risco.desbloqueio": ("", ("bloqueio_preventivo", "suspensao", "encerramento")),
    "risco.saque_travado": ("trava_saque", ()),
    "risco.saque_destravado": ("", ("trava_saque",)),
}


class TravarSaqueIn(AcaoRiscoIn):
    motivo_fraude: StrictBool = False
    limite_retencao_centavos: StrictInt | None = Field(
        None, gt=0, le=10**12, description="Obrigatório com fraude: o prejuízo apurado."
    )
    dias: StrictInt | None = Field(
        None, ge=1, le=90, description="Com fraude, sem este campo vale o prazo máximo (30)."
    )


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
        left join public.contratos c on c.pedido_id = p.id and c.status <> 'cancelado'
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
    com_trava = contexto.medidas.usuarios_com_trava_fraude(
        [str(r["usuario_id"]) for r in linhas if r["usuario_id"]], contexto.agora()
    )
    return [
        AlertaRiscoOut(
            id=str(r["id"]),
            usuario_id=str(r["usuario_id"]) if r["usuario_id"] else None,
            usuario_nome=r["usuario_nome"],
            usuario_tipo=r["usuario_tipo"],
            usuario_status=r["usuario_status"],
            trava_fraude_vigente=str(r["usuario_id"]).replace("-", "") in com_trava,
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


_SEM_BLOQUEIO = (
    "Atenção: a liberação e os repasses NÃO são bloqueados automaticamente; confira à mão."
)


def _trava_registrada(contexto: Contexto, usuario_id: str) -> bool:
    """Já há trava de analista, sem data final, em vigor (repetir não cria outra)."""
    if not contexto.medidas.disponivel():
        return False
    vigentes, _ = contexto.medidas.listar(
        usuario_id=usuario_id, tipo="trava_saque", vigentes_em=contexto.agora()
    )
    return any(m.origem == "analista" and m.fim_em is None for m in vigentes)


def _resposta(
    acao: str, nome: str, status: str, medida_registrada: bool, retido: int | None = None
) -> str:
    if acao == "risco.saque_travado" and retido is not None:
        return (
            f"A conta de {nome} tem trava de saques por fraude: a liberação no livro fica adiada, "
            f"retendo no máximo {_reais(retido)}, até a trava vencer ou ser revertida. Pagamento "
            "manual ou no Stripe continua sem trava; confira à mão."
        )
    if acao == "risco.saque_travado":
        registro = (
            "a trava de saques foi registrada"
            if medida_registrada
            else "a trava de saques não pôde ser registrada como medida"
        )
        return f"A conta de {nome} está restrita e {registro}. {_SEM_BLOQUEIO}"
    if acao == "risco.saque_destravado":
        if status == "ativo":
            return f"Conta de {nome} reativada, sem trava de saques. Confira os repasses à mão."
        return (
            f"{nome} não tem mais trava de saques, mas a conta continua restrita por outra "
            "medida em vigor."
        )
    verbo = "bloqueada" if acao == "risco.bloqueio_preventivo" else "desbloqueada"
    return f"Conta de {nome} {verbo}."


def _mudar_status_do_usuario(
    contexto: Contexto,
    admin: AdminContexto,
    operador: Operador,
    corpo: AcaoRiscoIn,
    *,
    de: tuple[str, ...],
    para: str,
    acao: str,
    exige_profissional: bool = False,
) -> dict[str, str]:
    uid = como_uuid(corpo.usuario_id)
    if uid is None:
        raise HTTPException(404, "Usuário não encontrado.")
    proteger_conta_da_equipe(admin, operador, str(uid))
    banco = _banco(contexto)
    with contexto.transacao(), banco.transacao() as con:
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
        fraude = bool(getattr(corpo, "motivo_fraude", False))
        limite = getattr(corpo, "limite_retencao_centavos", None)
        dias = getattr(corpo, "dias", None)
        if acao == "risco.saque_travado":
            dias, erro = medidas.prazo_da_trava(contexto, "trava_saque", fraude, limite, dias)
            if erro:
                raise HTTPException(422, erro)
        if (
            acao == "risco.saque_travado"
            and not fraude
            and dias is None
            and usr["status"] == para
            and _trava_registrada(contexto, str(uid))
        ):  # a linha está travada: dois pedidos juntos não criam duas medidas
            retido = contexto.medidas.retencao_por_fraude(str(uid), contexto.agora())
            return {"mensagem": _resposta(acao, usr["nome"], para, True, retido)}
        con.execute(
            "update public.usuarios set status = %s, atualizado_em = now() where id = %s",
            (para, uid),
        )
        tipo, termina = _MEDIDA_DA_ACAO[acao]
        protocolo = medidas.espelhar_status(
            contexto,
            str(uid),
            operador.id,
            para=para,
            tipo=tipo,
            termina=termina,
            motivo=corpo.motivo,
            motivo_usuario=corpo.motivo_usuario,
            clausulas=tuple(corpo.clausulas),
            dias=dias,
            motivo_fraude=fraude,
            limite_retencao_centavos=limite,
        )
        # Outra medida em vigor pode manter a restrição: vale o status que ficou gravado.
        final = con.execute("select status from public.usuarios where id = %s", (uid,)).fetchone()
        admin.auditoria.registrar(
            ator_id=operador.id,
            acao=acao,
            entidade="usuarios",
            entidade_id=str(uid),
            antes={"status": usr["status"]},
            depois={"status": final["status"]},
            motivo=corpo.motivo,
        )
        retido = contexto.medidas.retencao_por_fraude(str(uid), contexto.agora())
        return {
            "mensagem": _resposta(acao, usr["nome"], final["status"], protocolo is not None, retido)
        }


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
    )  # fmt: skip


@router.post(
    "/travar-saque",
    summary="Restringir o profissional e registrar trava de saques (reversível)",
    description="Só com motivo_fraude (e limite) a liberação no livro é adiada; pagamento manual "
    "ou no Stripe não é bloqueado. Aceita conta ativa ou restrita; conta bloqueada responde 409.",
)
def travar_saque(
    corpo: TravarSaqueIn,
    operador: Operador = Depends(exigir(Permissao.RISCO_DECIDIR)),
    admin: AdminContexto = Depends(obter_admin),
    contexto: Contexto = Depends(obter_contexto),
) -> dict[str, str]:
    return _mudar_status_do_usuario(
        contexto, admin, operador, corpo,
        de=("ativo", "restrito"), para="restrito", acao="risco.saque_travado",
        exige_profissional=True,
    )  # fmt: skip


@router.post("/destravar-saque", summary="Remove a trava de saques de um profissional")
def destravar_saque(
    corpo: AcaoRiscoIn,
    operador: Operador = Depends(exigir(Permissao.RISCO_DECIDIR)),
    admin: AdminContexto = Depends(obter_admin),
    contexto: Contexto = Depends(obter_contexto),
) -> dict[str, str]:
    return _mudar_status_do_usuario(
        contexto, admin, operador, corpo,
        de=("restrito",), para="ativo", acao="risco.saque_destravado",
        exige_profissional=True,
    )  # fmt: skip
