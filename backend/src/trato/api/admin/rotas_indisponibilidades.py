"""Janelas de indisponibilidade no painel (Termos 22.3). Permissão
`indisponibilidades_gerenciar`: líder de suporte e administrador. Tudo auditado; nada se apaga."""

from __future__ import annotations

from typing import Literal

from fastapi import APIRouter, Depends, HTTPException, Query, Response
from pydantic import AwareDatetime, BaseModel, ConfigDict, Field

from trato.api.admin.contexto import AdminContexto, Operador, exigir, obter_admin
from trato.api.admin.modelos import Pagina
from trato.api.admin.papeis import Permissao
from trato.api.contexto import Contexto, obter_contexto
from trato.persistencia.indisponibilidades import Janela, JanelaSobreposta

router = APIRouter(prefix="/v1/admin/indisponibilidades", tags=["admin: indisponibilidades"])
Origem = Literal["app", "pagamento"]


class _Entrada(BaseModel):
    model_config = ConfigDict(extra="forbid", str_strip_whitespace=True)

    motivo: str = Field(min_length=10, max_length=1000)


class AbrirJanelaIn(_Entrada):
    origem: Origem
    inicio_em: AwareDatetime
    fim_em: AwareDatetime | None = Field(None, description="null: a falha continua.")


class EncerrarJanelaIn(_Entrada):
    fim_em: AwareDatetime | None = Field(None, description="null: agora.")


class JanelaOut(BaseModel):
    id: str
    origem: str
    inicio_em: AwareDatetime
    fim_em: AwareDatetime | None
    ativa: bool
    motivo: str
    criada_por: str
    encerrada_por: str | None
    criada_em: AwareDatetime | None


def _saida(j: Janela) -> JanelaOut:
    campos = {n: getattr(j, n) for n in JanelaOut.model_fields if n != "ativa"}
    return JanelaOut(**campos, ativa=j.fim_em is None)


def _exigir_tabela(contexto: Contexto) -> None:
    if not contexto.indisponibilidades.disponivel():
        raise HTTPException(503, "A tabela de indisponibilidades ainda não está disponível.")


def _auditar(admin: AdminContexto, operador: Operador, acao: str, j: Janela, motivo: str) -> None:
    admin.auditoria.registrar(
        ator_id=operador.id,
        acao=f"indisponibilidade.{acao}",
        entidade="janelas_indisponibilidade",
        entidade_id=j.id,
        antes={},
        depois={
            "origem": j.origem,
            "inicio_em": j.inicio_em.isoformat(),
            "fim_em": j.fim_em.isoformat() if j.fim_em else None,
        },
        motivo=motivo,
    )


@router.post("", response_model=JanelaOut, status_code=201, summary="Registrar uma falha")
def abrir(
    corpo: AbrirJanelaIn,
    response: Response,
    operador: Operador = Depends(exigir(Permissao.INDISPONIBILIDADES_GERENCIAR)),
    admin: AdminContexto = Depends(obter_admin),
    contexto: Contexto = Depends(obter_contexto),
) -> JanelaOut:
    _exigir_tabela(contexto)
    agora = contexto.agora()
    if corpo.inicio_em > agora or (corpo.fim_em is not None and corpo.fim_em > agora):
        raise HTTPException(422, "Início e fim não podem estar no futuro.")
    if corpo.fim_em is not None and corpo.fim_em <= corpo.inicio_em:
        raise HTTPException(422, "O fim precisa ser depois do início.")
    try:
        with contexto.transacao():
            janela, criada = contexto.indisponibilidades.criar(
                Janela(
                    origem=corpo.origem,
                    inicio_em=corpo.inicio_em,
                    fim_em=corpo.fim_em,
                    motivo=corpo.motivo,
                    criada_por=operador.id,
                    encerrada_por=operador.id if corpo.fim_em else None,
                    criada_em=agora,
                )
            )
            if criada:
                _auditar(admin, operador, "registrada", janela, corpo.motivo)
    except JanelaSobreposta:
        raise HTTPException(
            409, "Já existe uma janela desta origem nesse período (confira as abertas)."
        ) from None
    if not criada:
        response.status_code = 200
    return _saida(janela)


@router.get("", response_model=Pagina[JanelaOut], summary="Falhas registradas")
def listar(
    origem: Origem | None = None,
    abertas: bool = False,
    limite: int = Query(20, ge=1, le=100),
    deslocamento: int = Query(0, ge=0),
    _: Operador = Depends(exigir(Permissao.INDISPONIBILIDADES_GERENCIAR)),
    contexto: Contexto = Depends(obter_contexto),
) -> Pagina[JanelaOut]:
    achadas = contexto.indisponibilidades.listar(origem=origem, abertas=abertas)
    return Pagina(
        itens=[_saida(j) for j in achadas[deslocamento : deslocamento + limite]],
        total=len(achadas),
        limite=limite,
        deslocamento=deslocamento,
    )


@router.post("/{janela_id}/encerrar", response_model=JanelaOut, summary="Encerrar a falha")
def encerrar(
    janela_id: str,
    corpo: EncerrarJanelaIn,
    operador: Operador = Depends(exigir(Permissao.INDISPONIBILIDADES_GERENCIAR)),
    admin: AdminContexto = Depends(obter_admin),
    contexto: Contexto = Depends(obter_contexto),
) -> JanelaOut:
    _exigir_tabela(contexto)
    agora = contexto.agora()
    fim = corpo.fim_em or agora
    with contexto.transacao():
        atual = contexto.indisponibilidades.obter(janela_id)
        if atual is None:
            raise HTTPException(404, "Janela não encontrada.")
        if fim > agora or fim <= atual.inicio_em:
            raise HTTPException(422, "O fim precisa ser depois do início e não pode ser futuro.")
        janela = contexto.indisponibilidades.encerrar(janela_id, fim, operador.id)
        if janela is None:
            raise HTTPException(409, "Esta janela já foi encerrada.")
        _auditar(admin, operador, "encerrada", janela, corpo.motivo)
    return _saida(janela)
