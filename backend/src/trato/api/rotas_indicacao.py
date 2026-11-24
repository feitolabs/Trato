"""Indique e Ganhe Tratinhos: código pessoal, aplicar código e conferir um código.

Quem decide tipo e valores é o backend (`api/indicacoes.py`). Nunca sai e-mail, telefone, CPF ou
sobrenome completo: só primeiro nome e a inicial do sobrenome.
"""

from __future__ import annotations

import re
from datetime import datetime

from fastapi import APIRouter, Depends, HTTPException, Request
from pydantic import BaseModel, ConfigDict, Field

from trato.api.auth import PapelUsuario, Usuario
from trato.api.contexto import Contexto, exigir_papel, obter_contexto
from trato.api.indicacoes import (
    STATUS_AGUARDANDO,
    STATUS_BLOQUEADO_FRAUDE,
    STATUS_CADASTRADO,
    STATUS_LIBERADO,
    Indicacao,
    JaIndicado,
    candidatos_de_codigo,
    contato_repetido,
    resolver_tipo,
)
from trato.financeiro import periodo
from trato.pedidos.estados import Estado
from trato.seguranca.cliente import ip_do_cliente
from trato.seguranca.contadores import Contadores

router = APIRouter(prefix="/v1/indicacoes", tags=["indicacoes"])

_FORMATO_CODIGO = re.compile(r"^[A-Z0-9]{6,12}$")
_JA_USOU = "Você já utilizou um código de indicação."
# Consulta pública de código: no máximo 20 por minuto por IP (impede varrer códigos).
CONSULTAS_POR_MINUTO = 20
JANELA_CONSULTA_S = 60


class IndicadoOut(BaseModel):
    id: str
    indicado_nome: str | None = Field(description="Primeiro nome e inicial do sobrenome.")
    status: str
    tipo: str
    bonus_indicador_tratinhos: int
    liberacao_prevista_em: datetime | None = None
    liberado_em: datetime | None = None


class ResumoIndicacoesOut(BaseModel):
    cadastradas: int
    aguardando_liberacao: int
    liberadas: int
    limite_mensal: int
    limite_mensal_restante: int


class MeuCodigoOut(BaseModel):
    codigo: str
    resumo: ResumoIndicacoesOut
    indicacoes: list[IndicadoOut]


class AplicarCodigoIn(BaseModel):
    model_config = ConfigDict(extra="forbid")

    codigo: str = Field(min_length=1, max_length=32)


class AplicarCodigoOut(BaseModel):
    id: str
    tipo: str
    status: str
    bonus_indicado_tratinhos: int
    mensagem: str


class CodigoOut(BaseModel):
    valido: bool = True
    indicador_nome_curto: str | None = None
    indicador_papel: str
    profissional_id: str | None = Field(
        default=None, description="Só quando o indicador é profissional (abre o perfil público)."
    )


def _normalizar(codigo: str) -> str:
    return codigo.strip().upper()


def _nome_curto(contexto: Contexto, usuario_id: str) -> str | None:
    from trato.api.rotas_profissional_cadastro import _nome_abreviado

    detalhe = contexto.usuarios.detalhe(usuario_id)
    return _nome_abreviado(detalhe.nome) if detalhe is not None else None


def _eh_profissional(contexto: Contexto, usuario_id: str) -> bool | None:
    """True/False pelo papel da conta; None se a conta não existe."""
    detalhe = contexto.usuarios.detalhe(usuario_id)
    if detalhe is None:
        return None
    return detalhe.papel is PapelUsuario.PROFISSIONAL


def _ja_tem_atividade(contexto: Contexto, usuario_id: str) -> bool:
    """Já pediu um serviço como cliente ou concluiu um como profissional (acabou a 'conta nova')."""
    if contexto.pedidos.listar_do_usuario(usuario_id, True, 1):
        return True
    feitos = contexto.pedidos.listar_do_usuario(usuario_id, False, 200)
    return any(p.estado is Estado.CONCLUIDO for p in feitos)


def _item(contexto: Contexto, i: Indicacao) -> IndicadoOut:
    return IndicadoOut(
        id=i.id,
        indicado_nome=_nome_curto(contexto, i.indicado_id),
        status=i.status,
        tipo=i.tipo,
        bonus_indicador_tratinhos=i.bonus_indicador_tratinhos,
        liberacao_prevista_em=i.liberacao_prevista_em,
        liberado_em=i.liberado_em,
    )


@router.get(
    "/meu-codigo",
    response_model=MeuCodigoOut,
    summary="Meu código de indicação, o resumo e a lista de quem eu indiquei",
)
def meu_codigo(
    usuario: Usuario = Depends(exigir_papel(PapelUsuario.CLIENTE, PapelUsuario.PROFISSIONAL)),
    contexto: Contexto = Depends(obter_contexto),
) -> MeuCodigoOut:
    repo = contexto.indicacoes
    cfg = repo.config()
    codigo = repo.garantir_codigo(usuario.id, candidatos_de_codigo(usuario.id))
    lista = repo.do_indicador(usuario.id)
    profissional = (
        _eh_profissional(contexto, usuario.id) or usuario.papel is PapelUsuario.PROFISSIONAL
    )
    limite = cfg.limite_mensal_profissional if profissional else cfg.limite_mensal_cliente
    inicio, fim = periodo.mes(*periodo.mes_de(contexto.agora()))
    usadas = repo.recompensadas_no_mes(usuario.id, inicio, fim, cfg.dias_liberacao)
    return MeuCodigoOut(
        codigo=codigo,
        resumo=ResumoIndicacoesOut(
            cadastradas=sum(1 for i in lista if i.status == STATUS_CADASTRADO),
            aguardando_liberacao=sum(1 for i in lista if i.status == STATUS_AGUARDANDO),
            liberadas=sum(1 for i in lista if i.status == STATUS_LIBERADO),
            limite_mensal=limite,
            limite_mensal_restante=max(limite - usadas, 0),
        ),
        indicacoes=[_item(contexto, i) for i in lista],
    )


@router.post(
    "/aplicar",
    response_model=AplicarCodigoOut,
    status_code=201,
    summary="Aplicar o código de quem me indicou (uma vez só, antes do 1º pedido)",
)
def aplicar_codigo(
    corpo: AplicarCodigoIn,
    usuario: Usuario = Depends(exigir_papel(PapelUsuario.CLIENTE, PapelUsuario.PROFISSIONAL)),
    contexto: Contexto = Depends(obter_contexto),
) -> AplicarCodigoOut:
    repo = contexto.indicacoes
    cfg = repo.config()
    codigo = _normalizar(corpo.codigo)
    indicador_id = repo.usuario_do_codigo(codigo) if _FORMATO_CODIGO.match(codigo) else None
    indicador_prof = _eh_profissional(contexto, indicador_id) if indicador_id else None
    if indicador_id is None or indicador_prof is None:
        raise HTTPException(404, "Código de indicação não encontrado.")
    if indicador_id == usuario.id:
        raise HTTPException(422, "Você não pode usar o próprio código de indicação.")
    if repo.do_indicado(usuario.id) is not None:
        raise HTTPException(409, _JA_USOU)
    if _ja_tem_atividade(contexto, usuario.id):
        raise HTTPException(
            409, "O código de indicação só vale antes do seu primeiro serviço no Trato."
        )
    cruzada = repo.do_indicado(indicador_id)
    if cruzada is not None and cruzada.indicador_id == usuario.id:
        raise HTTPException(409, "Vocês já se indicaram: a indicação cruzada não vale.")
    indicado_prof = _eh_profissional(contexto, usuario.id)
    if indicado_prof is None:
        indicado_prof = usuario.papel is PapelUsuario.PROFISSIONAL
    tipo = resolver_tipo(indicador_prof, indicado_prof)
    if tipo is None:
        raise HTTPException(
            422,
            "A indicação de novos profissionais está disponível apenas por códigos de "
            "profissionais.",
        )
    bonus_indicador, bonus_indicado = cfg.bonus_do_tipo(tipo)
    # Antifraude leve: mesma pessoa em duas contas (telefone ou e-mail repetidos) não ganha.
    repetido = contato_repetido(contexto, indicador_id, usuario.id)
    if repetido is not None:
        bonus_indicador = bonus_indicado = 0
    try:
        nova = repo.criar(
            indicador_id,
            usuario.id,
            codigo,
            tipo,
            bonus_indicador,
            bonus_indicado,
            contexto.agora(),
            status=STATUS_BLOQUEADO_FRAUDE if repetido else STATUS_CADASTRADO,
            motivo_bloqueio=repetido or "",
        )
    except JaIndicado:
        raise HTTPException(409, _JA_USOU) from None
    if repetido is not None:
        return AplicarCodigoOut(
            id=nova.id,
            tipo=nova.tipo,
            status=nova.status,
            bonus_indicado_tratinhos=0,
            mensagem="Código registrado, mas esta indicação não é elegível a Tratinhos.",
        )
    reais = f"{cfg.valor_minimo_servico_centavos // 100}"
    return AplicarCodigoOut(
        id=nova.id,
        tipo=nova.tipo,
        status=nova.status,
        bonus_indicado_tratinhos=nova.bonus_indicado_tratinhos,
        mensagem=(
            f"Código aplicado! Você ganha {nova.bonus_indicado_tratinhos} Tratinhos depois do "
            f"seu primeiro serviço concluído (a partir de R$ {reais}) e {cfg.dias_liberacao} "
            "dias sem disputa."
        ),
    )


@router.get(
    "/codigo/{codigo}",
    response_model=CodigoOut,
    summary="Conferir um código de indicação (sem dados privados)",
)
def conferir_codigo(
    codigo: str, request: Request, contexto: Contexto = Depends(obter_contexto)
) -> CodigoOut:
    contadores = contexto.extras.setdefault(
        "contadores_consulta_indicacao",
        Contadores(relogio=lambda: contexto.agora().timestamp()),
    )
    chave = f"indicacao:codigo:{ip_do_cliente(request)}"
    if contadores.quantos(chave, JANELA_CONSULTA_S) >= CONSULTAS_POR_MINUTO:
        espera = contadores.segundos_ate_liberar(chave, JANELA_CONSULTA_S, CONSULTAS_POR_MINUTO)
        raise HTTPException(
            429,
            "Muitas consultas de código. Aguarde um minuto e tente de novo.",
            headers={"Retry-After": str(max(espera, 1))},
        )
    contadores.adicionar(chave)
    normal = _normalizar(codigo)
    indicador_id = (
        contexto.indicacoes.usuario_do_codigo(normal) if _FORMATO_CODIGO.match(normal) else None
    )
    profissional = _eh_profissional(contexto, indicador_id) if indicador_id else None
    if indicador_id is None or profissional is None:
        raise HTTPException(404, "Código de indicação não encontrado.")
    return CodigoOut(
        indicador_nome_curto=_nome_curto(contexto, indicador_id),
        indicador_papel="profissional" if profissional else "cliente",
        profissional_id=indicador_id if profissional else None,
    )
