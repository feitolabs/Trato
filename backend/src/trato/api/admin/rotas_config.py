"""Configuração versionada: ler, propor, aprovar (outra pessoa), publicar e reverter.

Versão publicada nunca é editada: mudar = criar nova versão. As regras do ciclo estão em
`config_regras.py` e o banco repete as que consegue garantir.
"""

from __future__ import annotations

from fastapi import APIRouter, Depends, HTTPException

from trato.api.admin.contexto import AdminContexto, Operador, exigir, obter_admin
from trato.api.admin.modelos import (
    ComMotivo,
    DefinicaoOut,
    FaixaIO,
    ParametroIO,
    RascunhoIn,
    VersaoConfigOut,
)
from trato.api.admin.papeis import Permissao
from trato.api.admin.repositorios import FaixaTaxa, ParametroConfig, VersaoConfig
from trato.api.contexto import Contexto, obter_contexto

router = APIRouter(prefix="/v1/admin/config", tags=["admin: configuração"])


def _saida(v: VersaoConfig) -> VersaoConfigOut:
    return VersaoConfigOut(
        id=v.id,
        numero=v.numero,
        status=v.status,
        motivo=v.motivo,
        criada_por=v.criada_por,
        aprovada_por=v.aprovada_por,
        vigente_desde=v.vigente_desde,
        revertida_de=v.revertida_de,
        criado_em=v.criado_em,
        parametros=[ParametroIO(**vars(p)) for p in v.parametros],
        faixas=[FaixaIO(**vars(f)) for f in v.faixas],
    )


@router.get("/definicoes", response_model=list[DefinicaoOut], summary="Catálogo de parâmetros")
def definicoes(
    _: Operador = Depends(exigir(Permissao.CONFIG_VER)),
    admin: AdminContexto = Depends(obter_admin),
) -> list[DefinicaoOut]:
    return [DefinicaoOut.model_validate(d, from_attributes=True) for d in admin.config.definicoes()]


@router.get(
    "/vigente", response_model=VersaoConfigOut, summary="Versão vigente (parâmetros e faixas)"
)
def vigente(
    _: Operador = Depends(exigir(Permissao.CONFIG_VER)),
    admin: AdminContexto = Depends(obter_admin),
) -> VersaoConfigOut:
    atual = admin.config.vigente()
    if atual is None:
        raise HTTPException(404, "Ainda não há versão de configuração vigente.")
    return _saida(atual)


@router.get("/versoes", response_model=list[VersaoConfigOut], summary="Histórico de versões")
def versoes(
    _: Operador = Depends(exigir(Permissao.CONFIG_VER)),
    admin: AdminContexto = Depends(obter_admin),
) -> list[VersaoConfigOut]:
    return [_saida(v) for v in admin.config.versoes()]


@router.get("/versoes/{versao_id}", response_model=VersaoConfigOut, summary="Uma versão completa")
def versao(
    versao_id: str,
    _: Operador = Depends(exigir(Permissao.CONFIG_VER)),
    admin: AdminContexto = Depends(obter_admin),
) -> VersaoConfigOut:
    achada = admin.config.versao(versao_id)
    if achada is None:
        raise HTTPException(404, "Versão de configuração não encontrada.")
    return _saida(achada)


@router.post(
    "/versoes",
    response_model=VersaoConfigOut,
    status_code=201,
    summary="Criar rascunho de nova versão",
)
def criar_rascunho(
    corpo: RascunhoIn,
    operador: Operador = Depends(exigir(Permissao.CONFIG_PROPOR)),
    admin: AdminContexto = Depends(obter_admin),
) -> VersaoConfigOut:
    criada = admin.config.criar_rascunho(
        operador.id,
        corpo.motivo,
        [ParametroConfig(**p.model_dump()) for p in corpo.parametros],
        [FaixaTaxa(**f.model_dump()) for f in corpo.faixas],
        corpo.vigente_desde,
        corpo.partir_da_vigente,
    )
    return _saida(criada)


@router.post(
    "/versoes/{versao_id}/enviar",
    response_model=VersaoConfigOut,
    summary="Enviar o rascunho para aprovação",
)
def enviar(
    versao_id: str,
    corpo: ComMotivo,
    operador: Operador = Depends(exigir(Permissao.CONFIG_PROPOR)),
    admin: AdminContexto = Depends(obter_admin),
) -> VersaoConfigOut:
    return _saida(admin.config.enviar_para_aprovacao(versao_id, operador.id, corpo.motivo))


@router.post(
    "/versoes/{versao_id}/aprovar",
    response_model=VersaoConfigOut,
    summary="Aprovar (aprovação dupla: quem propôs não aprova)",
)
def aprovar(
    versao_id: str,
    corpo: ComMotivo,
    operador: Operador = Depends(exigir(Permissao.CONFIG_APROVAR)),
    admin: AdminContexto = Depends(obter_admin),
) -> VersaoConfigOut:
    return _saida(admin.config.aprovar(versao_id, operador.id, corpo.motivo))


@router.post(
    "/versoes/{versao_id}/publicar",
    response_model=VersaoConfigOut,
    summary="Publicar uma versão aprovada (vira a vigente)",
)
def publicar(
    versao_id: str,
    corpo: ComMotivo,
    operador: Operador = Depends(exigir(Permissao.CONFIG_APROVAR)),
    admin: AdminContexto = Depends(obter_admin),
    contexto: Contexto = Depends(obter_contexto),
) -> VersaoConfigOut:
    return _saida(admin.config.publicar(versao_id, operador.id, corpo.motivo, contexto.agora()))


@router.post(
    "/versoes/{versao_id}/reverter",
    response_model=VersaoConfigOut,
    status_code=201,
    summary="Reverter PARA esta versão (cria uma nova, que também precisa de aprovação)",
)
def reverter(
    versao_id: str,
    corpo: ComMotivo,
    operador: Operador = Depends(exigir(Permissao.CONFIG_PROPOR)),
    admin: AdminContexto = Depends(obter_admin),
) -> VersaoConfigOut:
    return _saida(admin.config.reverter(versao_id, operador.id, corpo.motivo))


@router.delete("/versoes/{versao_id}", status_code=204, summary="Descartar rascunho")
def descartar(
    versao_id: str,
    corpo: ComMotivo,
    operador: Operador = Depends(exigir(Permissao.CONFIG_PROPOR)),
    admin: AdminContexto = Depends(obter_admin),
) -> None:
    admin.config.descartar_rascunho(versao_id, operador.id, corpo.motivo)
