"""Rotas de Gestão de Equipe e Acessos Internos (Módulo 6).

Regras do painel v2: um e-mail só tem um acesso (RF-EQP-02); a alçada de cada pessoa fica abaixo
do teto do papel (RP-02); quem concede não dá papel nem alçada maiores que os próprios (RP-04);
o último Administrador ativo não pode ser revogado nem rebaixado (RF-EQP-04).
"""

from __future__ import annotations

from typing import Any

from fastapi import APIRouter, Depends, HTTPException, Query
from pydantic import BaseModel, Field

from trato.api.admin.contexto import AdminContexto, Operador, exigir, obter_admin
from trato.api.admin.papeis import PapelEquipe, Permissao
from trato.api.contexto import Contexto, obter_contexto
from trato.persistencia.comum import como_uuid

router = APIRouter(prefix="/v1/admin/equipe", tags=["admin: equipe interna"])

_PAPEIS = "^(atendente_n1|atendente_n2|mediador|financeiro|seguranca|cadastro|moderador|juridico|dpo|lider_suporte|administrador)$"  # noqa: E501


class MembroEquipeOut(BaseModel):
    usuario_id: str
    nome: str
    email: str
    papel: str
    ativo: bool
    alcada_centavos: int
    criado_em: str
    # "ativo", "convite_enviado" (nunca entrou) ou "revogado".
    status: str = "ativo"
    ultimo_acesso: str | None = None
    teto_papel_centavos: int = 0


class AdicionarMembroIn(BaseModel):
    nome: str = Field(min_length=2, max_length=150)
    email: str = Field(min_length=5, max_length=150)
    papel: str = Field(..., pattern=_PAPEIS)
    alcada_centavos: int = Field(default=0, ge=0)
    motivo: str = Field(min_length=10, max_length=500)


class EditarMembroIn(BaseModel):
    papel: str | None = Field(default=None, pattern=_PAPEIS)
    alcada_centavos: int | None = Field(default=None, ge=0)
    ativo: bool | None = None
    motivo: str = Field(min_length=10, max_length=500)


class TetoPapelOut(BaseModel):
    papel: str
    teto_centavos: int


def _banco(contexto: Contexto) -> Any:
    banco = contexto.extras.get("banco") if contexto.extras else None
    if banco is None:
        raise HTTPException(503, "Banco de dados não configurado.")
    return banco


def _tetos(con: Any) -> dict[str, int]:
    linhas = con.execute("select papel, teto_centavos from public.papeis_alcada").fetchall()
    return {l["papel"]: int(l["teto_centavos"]) for l in linhas}  # noqa: E741


def _status(ativo: bool, ultimo_acesso: Any) -> str:
    if not ativo:
        return "revogado"
    return "ativo" if ultimo_acesso is not None else "convite_enviado"


def _iso(valor: Any) -> str | None:
    if valor is None:
        return None
    return valor.isoformat() if hasattr(valor, "isoformat") else str(valor)


_SELECT = """
    SELECT e.usuario_id, coalesce(u.nome, 'Membro da equipe') AS nome,
           coalesce(au.email, '') AS email, e.papel, e.ativo,
           coalesce(e.alcada_centavos, 0) AS alcada_centavos, e.criado_em,
           au.ultimo_acesso
    FROM public.equipe e
    LEFT JOIN public.usuarios u ON u.id = e.usuario_id
    LEFT JOIN privado.contas_auth(array(SELECT usuario_id FROM public.equipe)) au
           ON au.id = e.usuario_id
"""


def _saida(r: Any, tetos: dict[str, int]) -> MembroEquipeOut:
    teto = tetos.get(r["papel"], 0)
    return MembroEquipeOut(
        usuario_id=str(r["usuario_id"]),
        nome=r["nome"],
        email=r["email"],
        papel=r["papel"],
        ativo=bool(r["ativo"]),
        # O que vale de fato: nunca passa do teto do papel (RP-02).
        alcada_centavos=min(int(r["alcada_centavos"] or 0), teto),
        criado_em=_iso(r["criado_em"]) or "",
        status=_status(bool(r["ativo"]), r["ultimo_acesso"]),
        ultimo_acesso=_iso(r["ultimo_acesso"]),
        teto_papel_centavos=teto,
    )


def _validar_concessao(operador: Operador, papel: str, alcada: int, tetos: dict[str, int]) -> None:
    """RP-02 e RP-04: alçada dentro do teto do papel e nunca maior que a de quem concede."""
    teto = tetos.get(papel, 0)
    if alcada > teto:
        raise HTTPException(
            422,
            f"A alçada passa do teto do papel ({teto / 100:.2f}). Ajuste o valor.".replace(
                ".", ","
            ),
        )
    minha = min(operador.membro.alcada_centavos or 0, tetos.get(operador.membro.papel.value, 0))
    if alcada > minha:
        raise HTTPException(403, "Você não pode dar uma alçada maior que a sua.")
    if (
        papel == PapelEquipe.ADMINISTRADOR.value
        and operador.membro.papel != PapelEquipe.ADMINISTRADOR
    ):
        raise HTTPException(403, "Só um Administrador pode conceder o papel de Administrador.")


def _administradores_ativos(con: Any, exceto: Any = None) -> int:
    linha = con.execute(
        "select count(*) as n from public.equipe "
        "where papel = 'administrador' and ativo and revogado_em is null "
        "and (%s::uuid is null or usuario_id <> %s::uuid)",
        (exceto, exceto),
    ).fetchone()
    return int(linha["n"])


@router.get("", response_model=list[MembroEquipeOut], summary="Listar membros da equipe interna")
def listar_equipe(
    operador: Operador = Depends(exigir(Permissao.EQUIPE_GERENCIAR)),
    contexto: Contexto = Depends(obter_contexto),
) -> list[MembroEquipeOut]:
    with _banco(contexto).transacao() as con:
        tetos = _tetos(con)
        linhas = con.execute(f"{_SELECT} ORDER BY e.ativo DESC, e.criado_em ASC").fetchall()
        return [_saida(r, tetos) for r in linhas]


@router.get("/tetos", response_model=list[TetoPapelOut], summary="Teto de alçada de cada papel")
def listar_tetos(
    operador: Operador = Depends(exigir(Permissao.EQUIPE_GERENCIAR)),
    contexto: Contexto = Depends(obter_contexto),
) -> list[TetoPapelOut]:
    with _banco(contexto).transacao() as con:
        return [TetoPapelOut(papel=p, teto_centavos=v) for p, v in sorted(_tetos(con).items())]


@router.post(
    "", response_model=MembroEquipeOut, status_code=201, summary="Adicionar membro à equipe"
)
def adicionar_membro(
    corpo: AdicionarMembroIn,
    operador: Operador = Depends(exigir(Permissao.EQUIPE_GERENCIAR)),
    admin: AdminContexto = Depends(obter_admin),
    contexto: Contexto = Depends(obter_contexto),
) -> MembroEquipeOut:
    email_norm = corpo.email.strip().lower()
    with _banco(contexto).transacao() as con:
        tetos = _tetos(con)
        _validar_concessao(operador, corpo.papel, corpo.alcada_centavos, tetos)
        usr = con.execute(
            "SELECT id, email FROM privado.conta_auth_por_email(%s)", (email_norm,)
        ).fetchone()
        if usr is None:
            raise HTTPException(
                404,
                f"Nenhuma conta encontrada com o e-mail '{email_norm}'. O colaborador precisa se "
                "cadastrar na plataforma antes de ser adicionado à equipe.",
            )
        usuario_id = usr["id"]
        ja = con.execute(
            "select ativo from public.equipe where usuario_id = %s", (usuario_id,)
        ).fetchone()
        if ja is not None and ja["ativo"]:
            raise HTTPException(409, "Este e-mail já tem acesso. Edite o colaborador existente.")

        con.execute(
            """
            INSERT INTO public.usuarios (id, nome, status)
            VALUES (%s, %s, 'ativo')
            ON CONFLICT (id) DO UPDATE
              SET nome = coalesce(nullif(EXCLUDED.nome, ''), public.usuarios.nome)
            """,
            (usuario_id, corpo.nome),
        )
        con.execute(
            """
            INSERT INTO public.equipe (usuario_id, papel, alcada_centavos, ativo)
            VALUES (%s, %s, %s, true)
            ON CONFLICT (usuario_id) DO UPDATE
            SET papel = EXCLUDED.papel,
                alcada_centavos = EXCLUDED.alcada_centavos,
                ativo = true,
                revogado_em = null
            """,
            (usuario_id, corpo.papel, corpo.alcada_centavos),
        )
        admin.auditoria.registrar(
            ator_id=operador.id,
            acao="equipe.membro_adicionado",
            entidade="equipe",
            entidade_id=str(usuario_id),
            depois={
                "nome": corpo.nome,
                "email": email_norm,
                "papel": corpo.papel,
                "alcada_centavos": corpo.alcada_centavos,
            },
            motivo=corpo.motivo,
        )
        linha = con.execute(f"{_SELECT} WHERE e.usuario_id = %s", (usuario_id,)).fetchone()
        return _saida(linha, tetos)


@router.patch(
    "/{usuario_id}",
    response_model=MembroEquipeOut,
    summary="Alterar papel, alçada ou status de um membro da equipe",
)
def editar_membro(
    usuario_id: str,
    corpo: EditarMembroIn,
    operador: Operador = Depends(exigir(Permissao.EQUIPE_GERENCIAR)),
    admin: AdminContexto = Depends(obter_admin),
    contexto: Contexto = Depends(obter_contexto),
) -> MembroEquipeOut:
    uid = como_uuid(usuario_id)
    if uid is None:
        raise HTTPException(404, "Membro da equipe não encontrado.")

    with _banco(contexto).transacao() as con:
        tetos = _tetos(con)
        m = con.execute(f"{_SELECT} WHERE e.usuario_id = %s", (uid,)).fetchone()
        if m is None:
            raise HTTPException(404, "Membro da equipe não encontrado.")

        novo_papel = corpo.papel if corpo.papel is not None else m["papel"]
        nova_alcada = (
            corpo.alcada_centavos if corpo.alcada_centavos is not None else m["alcada_centavos"]
        )
        novo_ativo = corpo.ativo if corpo.ativo is not None else m["ativo"]

        if corpo.papel is not None or corpo.alcada_centavos is not None:
            _validar_concessao(operador, novo_papel, int(nova_alcada or 0), tetos)
        deixa_de_ser_admin = (
            m["papel"] == "administrador"
            and m["ativo"]
            and (novo_papel != "administrador" or not novo_ativo)
        )
        if deixa_de_ser_admin and _administradores_ativos(con, exceto=uid) == 0:
            raise HTTPException(
                409, "Este é o único Administrador ativo: não pode ser revogado nem rebaixado."
            )

        con.execute(
            """
            UPDATE public.equipe
            SET papel = %s, alcada_centavos = %s, ativo = %s,
                revogado_em = (case when %s = false then now() else null end)
            WHERE usuario_id = %s
            """,
            (novo_papel, nova_alcada, novo_ativo, novo_ativo, uid),
        )
        admin.auditoria.registrar(
            ator_id=operador.id,
            acao="equipe.membro_atualizado",
            entidade="equipe",
            entidade_id=str(uid),
            antes={
                "papel": m["papel"],
                "alcada_centavos": m["alcada_centavos"],
                "ativo": m["ativo"],
            },
            depois={"papel": novo_papel, "alcada_centavos": nova_alcada, "ativo": novo_ativo},
            motivo=corpo.motivo,
        )
        linha = con.execute(f"{_SELECT} WHERE e.usuario_id = %s", (uid,)).fetchone()
        return _saida(linha, tetos)


@router.delete("/{usuario_id}", summary="Revogar acesso de membro da equipe")
def revogar_membro(
    usuario_id: str,
    motivo: str = Query(..., min_length=10),
    operador: Operador = Depends(exigir(Permissao.EQUIPE_GERENCIAR)),
    admin: AdminContexto = Depends(obter_admin),
    contexto: Contexto = Depends(obter_contexto),
) -> dict[str, str]:
    uid = como_uuid(usuario_id)
    if uid is None:
        raise HTTPException(404, "Membro da equipe não encontrado.")

    with _banco(contexto).transacao() as con:
        m = con.execute(
            "select papel, ativo from public.equipe where usuario_id = %s", (uid,)
        ).fetchone()
        if m is None:
            raise HTTPException(404, "Membro da equipe não encontrado.")
        if m["papel"] == "administrador" and m["ativo"] and _administradores_ativos(con, uid) == 0:
            raise HTTPException(
                409, "Este é o único Administrador ativo: não pode ser revogado nem rebaixado."
            )
        # A API confere `equipe.ativo` a cada chamada: o acesso acaba na hora, sem esperar o token.
        con.execute(
            "UPDATE public.equipe SET ativo = false, revogado_em = now() WHERE usuario_id = %s",
            (uid,),
        )
        admin.auditoria.registrar(
            ator_id=operador.id,
            acao="equipe.acesso_revogado",
            entidade="equipe",
            entidade_id=str(uid),
            antes={"papel": m["papel"], "ativo": m["ativo"]},
            depois={"ativo": False},
            motivo=motivo,
        )
        return {"mensagem": "Acesso revogado com sucesso."}
