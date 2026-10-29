"""Verificação de profissionais: fila, detalhe (documentos mascarados), URL assinada e decisão."""

from __future__ import annotations

from fastapi import APIRouter, Depends, HTTPException, Query

from trato.api.admin.contexto import AdminContexto, Operador, exigir, obter_admin
from trato.api.admin.modelos import (
    ComMotivo,
    DecisaoVerificacaoIn,
    DocumentoOut,
    Pagina,
    UrlDocumentoOut,
    VerificacaoOut,
)
from trato.api.admin.papeis import Permissao
from trato.api.admin.repositorios import VerificacaoAdmin

router = APIRouter(prefix="/v1/admin/verificacoes", tags=["admin: verificação"])

STATUS_DA_FILA = ("enviada", "em_analise")
STATUS_VALIDOS = ("enviada", "em_analise", "aprovada", "recusada")


def _saida(v: VerificacaoAdmin) -> VerificacaoOut:
    return VerificacaoOut(
        id=v.id,
        profissional_id=v.profissional_id,
        profissional_nome=v.profissional_nome,
        nivel_solicitado=v.nivel_solicitado,
        status=v.status,
        enviada_em=v.enviada_em,
        decidida_em=v.decidida_em,
        motivo_recusa=v.motivo_recusa,
        cpf_mascarado=v.cpf_mascarado,
        documentos=[
            DocumentoOut(id=d.id, tipo=d.tipo, validade_em=d.validade_em) for d in v.documentos
        ],
    )


@router.get("", response_model=Pagina[VerificacaoOut], summary="Fila de verificações")
def listar(
    status: list[str] | None = Query(None, description="Padrão: enviada e em_analise."),
    limite: int = Query(20, ge=1, le=100),
    deslocamento: int = Query(0, ge=0),
    _: Operador = Depends(exigir(Permissao.VERIFICACOES_VER)),
    admin: AdminContexto = Depends(obter_admin),
) -> Pagina[VerificacaoOut]:
    escolhidos = tuple(status) if status else STATUS_DA_FILA
    if any(s not in STATUS_VALIDOS for s in escolhidos):
        raise HTTPException(422, f"status deve ser um de: {', '.join(STATUS_VALIDOS)}.")
    itens, total = admin.verificacoes.listar(escolhidos, limite, deslocamento)
    return Pagina(
        itens=[_saida(v) for v in itens], total=total, limite=limite, deslocamento=deslocamento
    )


@router.get("/{verificacao_id}", response_model=VerificacaoOut, summary="Detalhe (sem arquivos)")
def detalhe(
    verificacao_id: str,
    _: Operador = Depends(exigir(Permissao.VERIFICACOES_VER)),
    admin: AdminContexto = Depends(obter_admin),
) -> VerificacaoOut:
    achada = admin.verificacoes.obter(verificacao_id)
    if achada is None:
        raise HTTPException(404, "Verificação não encontrada.")
    return _saida(achada)


@router.post(
    "/{verificacao_id}/documentos/{documento_id}/url",
    response_model=UrlDocumentoOut,
    summary="URL assinada curta de um documento (só o papel cadastro)",
    description=(
        "Revelar documento é acesso a dado pessoal: exige motivo e grava `dado_pessoal."
        "documento_revelado` na auditoria ANTES de gerar a URL. O caminho no storage nunca sai."
    ),
)
def url_do_documento(
    verificacao_id: str,
    documento_id: str,
    corpo: ComMotivo,
    operador: Operador = Depends(exigir(Permissao.DOCUMENTOS_REVELAR)),
    admin: AdminContexto = Depends(obter_admin),
) -> UrlDocumentoOut:
    caminho = admin.verificacoes.caminho_do_documento(verificacao_id, documento_id)
    if caminho is None:
        raise HTTPException(404, "Documento não encontrado.")
    if admin.assinador is None:
        raise HTTPException(503, "A assinatura de URL do storage ainda não está configurada.")
    admin.auditoria.registrar(
        ator_id=operador.id,
        acao="dado_pessoal.documento_revelado",
        entidade="verificacoes",
        entidade_id=verificacao_id,
        depois={"documento_id": documento_id, "expira_em_segundos": admin.segundos_url},
        motivo=corpo.motivo,
    )
    url = admin.assinador.assinar(caminho, admin.segundos_url)
    return UrlDocumentoOut(url=url, expira_em_segundos=admin.segundos_url)


@router.post(
    "/{verificacao_id}/decisao",
    response_model=VerificacaoOut,
    summary="Aprovar ou recusar, sempre com motivo",
)
def decidir(
    verificacao_id: str,
    corpo: DecisaoVerificacaoIn,
    operador: Operador = Depends(exigir(Permissao.VERIFICACOES_DECIDIR)),
    admin: AdminContexto = Depends(obter_admin),
) -> VerificacaoOut:
    if admin.verificacoes.obter(verificacao_id) is None:
        raise HTTPException(404, "Verificação não encontrada.")
    admin.verificacoes.decidir(verificacao_id, operador.id, corpo.aprovar, corpo.motivo)
    return _saida(admin.verificacoes.obter(verificacao_id))  # type: ignore[arg-type]
