"""Moderação de avaliações e pedidos de revisão no painel (Termos 12.6, 12.7 e 20.5).

Permissão: `avaliacoes_moderar` (mediador, lider_suporte, seguranca, administrador — espelho da
migration 20261125225600). Toda escrita é auditada. Sem as tabelas, responde 503 limpo.
"""

from __future__ import annotations

import logging
from datetime import datetime
from typing import Literal

from fastapi import APIRouter, Depends, HTTPException, Query, Request, Response
from pydantic import BaseModel, ConfigDict, Field, model_validator

from trato.api.admin.contexto import AdminContexto, Operador, exigir, obter_admin
from trato.api.admin.modelos import Pagina
from trato.api.admin.papeis import Permissao
from trato.api.avisos import servicos_de_notificacao
from trato.api.contexto import Contexto, obter_contexto
from trato.notificacoes.eventos import Evento
from trato.persistencia.avaliacoes_moderacao import OcultacaoAvaliacao, RevisaoAvaliacao

router = APIRouter(prefix="/v1/admin/avaliacoes", tags=["admin: moderação de avaliações"])

MotivoOcultacao = Literal[
    "ofensa_ou_ilegal",
    "dados_pessoais",
    "sem_pedido_real_ou_falsa",
    "nao_participou",
    "ordem_judicial",
]
StatusRevisao = Literal["aberta", "em_analise", "aceita", "recusada"]

log = logging.getLogger("trato.moderacao")

# Motivos da cláusula 12.6, como o autor os lê. A explicação do analista é interna e não vai.
TEXTO_DO_MOTIVO: dict[str, str] = {
    "ofensa_ou_ilegal": "conteúdo ofensivo ou ilegal",
    "dados_pessoais": "exposição de dados pessoais",
    "sem_pedido_real_ou_falsa": "avaliação sem pedido real ou falsa",
    "nao_participou": "quem avaliou não participou do serviço",
    "ordem_judicial": "ordem judicial",
}


class _Adiamento(BaseModel):
    adiar_aviso: bool = Field(
        False,
        description="11.8: só quando avisar o autor atrapalha investigação de crime ou põe "
        "alguém em risco. Exige a justificativa, que fica na auditoria.",
    )
    justificativa_adiamento: str | None = Field(None, min_length=10, max_length=1000)

    @model_validator(mode="after")
    def _exigir_justificativa(self) -> _Adiamento:
        if self.adiar_aviso and not (self.justificativa_adiamento or "").strip():
            raise ValueError("Para adiar o aviso ao autor, informe `justificativa_adiamento`.")
        return self


class OcultarAvaliacaoIn(_Adiamento):
    model_config = ConfigDict(extra="forbid", str_strip_whitespace=True)

    motivo: MotivoOcultacao
    explicacao: str = Field(min_length=10, max_length=2000)


class ReverterOcultacaoIn(BaseModel):
    model_config = ConfigDict(extra="forbid", str_strip_whitespace=True)

    motivo: str = Field(min_length=10, max_length=2000)


class DecidirRevisaoIn(_Adiamento):
    model_config = ConfigDict(extra="forbid", str_strip_whitespace=True)

    status: Literal["aceita", "recusada"]
    resposta: str = Field(min_length=10, max_length=2000)
    ocultar_motivo: MotivoOcultacao | None = None
    mesmo_analista_justificativa: str | None = Field(None, min_length=10, max_length=1000)


class OcultacaoOut(BaseModel):
    id: str
    avaliacao_id: str
    motivo: MotivoOcultacao
    explicacao: str
    analista_id: str
    ocultada_em: datetime
    status_anterior: str
    autor_avisado_em: datetime | None = None
    revertida_em: datetime | None = None
    revertida_por: str | None = None


class RevisaoAvaliacaoAdminOut(BaseModel):
    id: str
    protocolo: str
    avaliacao_id: str
    tipo: str
    ocultacao_id: str | None = None
    solicitante_id: str
    justificativa: str
    anexos: list[str]
    canal: str
    aberta_em: datetime
    responder_ate: datetime
    status: StatusRevisao
    analista_id: str | None = None
    resposta: str | None = None
    mesmo_analista_justificativa: str | None = None
    decidida_em: datetime | None = None
    ocultacao_aplicada_id: str | None = None


def _ocu_out(o: OcultacaoAvaliacao) -> OcultacaoOut:
    return OcultacaoOut(
        id=o.id,
        avaliacao_id=o.avaliacao_id,
        motivo=o.motivo,  # type: ignore[arg-type]
        explicacao=o.explicacao,
        analista_id=o.analista_id,
        ocultada_em=o.ocultada_em,
        status_anterior=o.status_anterior,
        autor_avisado_em=o.autor_avisado_em,
        revertida_em=o.revertida_em,
        revertida_por=o.revertida_por,
    )


def _rev_out(
    r: RevisaoAvaliacao, *, ocultacao_aplicada_id: str | None = None
) -> RevisaoAvaliacaoAdminOut:
    return RevisaoAvaliacaoAdminOut(
        id=r.id,
        protocolo=r.protocolo,
        avaliacao_id=r.avaliacao_id,
        tipo=r.tipo,
        ocultacao_id=r.ocultacao_id,
        solicitante_id=r.solicitante_id,
        justificativa=r.justificativa,
        anexos=list(r.anexos),
        canal=r.canal,
        aberta_em=r.aberta_em,
        responder_ate=r.responder_ate,
        status=r.status,  # type: ignore[arg-type]
        analista_id=r.analista_id,
        resposta=r.resposta,
        mesmo_analista_justificativa=r.mesmo_analista_justificativa,
        decidida_em=r.decidida_em,
        ocultacao_aplicada_id=ocultacao_aplicada_id,
    )


def _exigir_tabelas(contexto: Contexto) -> None:
    if not contexto.avaliacoes_moderacao.disponivel():
        raise HTTPException(
            503,
            "Moderação de avaliações indisponível: as tabelas ainda não existem no banco de dados.",
        )


def _avisar_autor(
    request: Request, contexto: Contexto, ocu: OcultacaoAvaliacao
) -> OcultacaoAvaliacao:
    """11.8: informa o autor, com o motivo e como contestar (20.5). Idempotente pela ocultação.
    Falha no aviso não desfaz a ocultação: `autor_avisado_em` fica vazio e a rota
    `/avisar-autor` reenvia."""
    try:
        avaliacao = contexto.avaliacoes.obter_por_id(ocu.avaliacao_id)
        if avaliacao is None:
            return ocu
        servico, _ = servicos_de_notificacao(request, contexto)
        servico.notificar(
            Evento.AVALIACAO_OCULTADA,
            avaliacao.avaliador_id,
            chave=f"ocultacao:{ocu.id}",
            pedido_id=avaliacao.pedido_id,
            corpo=f"Sua avaliação foi ocultada. Motivo: {TEXTO_DO_MOTIVO[ocu.motivo]}. "
            "Você pode contestar pelo aplicativo ou pelo SAC em até 30 dias deste aviso.",
            dados={"avaliacao_id": ocu.avaliacao_id, "motivo": ocu.motivo},
        )
        return contexto.avaliacoes_moderacao.marcar_autor_avisado(ocu.id, contexto.agora()) or ocu
    except Exception:  # noqa: BLE001 - aviso não desfaz a moderação
        log.exception("Aviso de avaliação ocultada falhou (%s)", ocu.id)
        return ocu


@router.post(
    "/{avaliacao_id}/avisar-autor",
    response_model=OcultacaoOut,
    summary="Enviar o aviso adiado (ou que falhou) ao autor da avaliação oculta (11.8)",
)
def avisar_autor_da_ocultacao(
    avaliacao_id: str,
    request: Request,
    operador: Operador = Depends(exigir(Permissao.AVALIACOES_MODERAR)),
    contexto: Contexto = Depends(obter_contexto),
    admin: AdminContexto = Depends(obter_admin),
) -> OcultacaoOut:
    _exigir_tabelas(contexto)
    ativa = contexto.avaliacoes_moderacao.ocultacao_ativa(avaliacao_id)
    if ativa is None:
        raise HTTPException(409, "Esta avaliação não tem ocultação ativa.")
    if ativa.autor_avisado_em is not None:
        return _ocu_out(ativa)
    avisada = _avisar_autor(request, contexto, ativa)
    if avisada.autor_avisado_em is None:
        raise HTTPException(503, "Não foi possível avisar o autor agora. Tente de novo.")
    admin.auditoria.registrar(
        ator_id=operador.id,
        acao="avaliacao.autor_avisado",
        entidade="avaliacoes",
        entidade_id=avaliacao_id,
        depois={"ocultacao_id": ativa.id},
        motivo="Aviso ao autor (Termos 11.8)",
    )
    return _ocu_out(avisada)


@router.post(
    "/{avaliacao_id}/ocultar",
    response_model=OcultacaoOut,
    status_code=201,
    summary="Ocultar avaliação por motivo previsto na cláusula 12.6",
)
def ocultar_avaliacao(
    avaliacao_id: str,
    corpo: OcultarAvaliacaoIn,
    request: Request,
    operador: Operador = Depends(exigir(Permissao.AVALIACOES_MODERAR)),
    contexto: Contexto = Depends(obter_contexto),
    admin: AdminContexto = Depends(obter_admin),
) -> OcultacaoOut:
    _exigir_tabelas(contexto)
    ocu, cod = contexto.avaliacoes_moderacao.ocultar(
        avaliacao_id, corpo.motivo, corpo.explicacao, operador.id, contexto.agora()
    )
    if cod == "nao_encontrada" or ocu is None:
        raise HTTPException(404, "Avaliação não encontrada.")
    if cod == "ja_ocultada":
        raise HTTPException(409, "Esta avaliação já possui uma ocultação ativa.")
    admin.auditoria.registrar(
        ator_id=operador.id,
        acao="avaliacao.ocultada",
        entidade="avaliacoes",
        entidade_id=avaliacao_id,
        depois={
            "ocultacao_id": ocu.id,
            "motivo": corpo.motivo,
            "aviso_adiado": corpo.adiar_aviso,
            "justificativa_adiamento": corpo.justificativa_adiamento if corpo.adiar_aviso else None,
        },
        motivo=corpo.explicacao,
    )
    if not corpo.adiar_aviso:
        ocu = _avisar_autor(request, contexto, ocu)
    return _ocu_out(ocu)


@router.post(
    "/{avaliacao_id}/reverter-ocultacao",
    response_model=OcultacaoOut,
    summary="Reverter ocultação ativa de avaliação",
)
def reverter_ocultacao_avaliacao(
    avaliacao_id: str,
    corpo: ReverterOcultacaoIn,
    operador: Operador = Depends(exigir(Permissao.AVALIACOES_MODERAR)),
    contexto: Contexto = Depends(obter_contexto),
    admin: AdminContexto = Depends(obter_admin),
) -> OcultacaoOut:
    _exigir_tabelas(contexto)
    ocu, cod = contexto.avaliacoes_moderacao.reverter_ocultacao(
        avaliacao_id, operador.id, contexto.agora()
    )
    if cod == "nao_encontrada":
        raise HTTPException(404, "Avaliação não encontrada.")
    if cod == "sem_ocultacao_ativa" or ocu is None:
        raise HTTPException(409, "Esta avaliação não tem ocultação ativa para reverter.")
    admin.auditoria.registrar(
        ator_id=operador.id,
        acao="avaliacao.ocultacao_revertida",
        entidade="avaliacoes",
        entidade_id=avaliacao_id,
        depois={"ocultacao_id": ocu.id, "status_restaurado": ocu.status_anterior},
        motivo=corpo.motivo,
    )
    return _ocu_out(ocu)


@router.get(
    "/revisoes",
    response_model=Pagina[RevisaoAvaliacaoAdminOut],
    summary="Listar pedidos de revisão de avaliação",
)
def listar_revisoes(
    status: StatusRevisao | None = Query(None),
    avaliacao_id: str | None = Query(None),
    limite: int = Query(50, ge=1, le=200),
    deslocamento: int = Query(0, ge=0),
    _: Operador = Depends(exigir(Permissao.AVALIACOES_MODERAR)),
    contexto: Contexto = Depends(obter_contexto),
) -> Pagina[RevisaoAvaliacaoAdminOut]:
    _exigir_tabelas(contexto)
    itens, total = contexto.avaliacoes_moderacao.listar_revisoes_admin(
        status, avaliacao_id, limite, deslocamento
    )
    return Pagina(
        itens=[_rev_out(r) for r in itens],
        total=total,
        limite=limite,
        deslocamento=deslocamento,
    )


@router.post(
    "/revisoes/{revisao_id}/analisar",
    response_model=RevisaoAvaliacaoAdminOut,
    summary="Passar pedido de revisão de avaliação para em_analise",
)
def iniciar_analise_revisao(
    revisao_id: str,
    operador: Operador = Depends(exigir(Permissao.AVALIACOES_MODERAR)),
    contexto: Contexto = Depends(obter_contexto),
    admin: AdminContexto = Depends(obter_admin),
) -> RevisaoAvaliacaoAdminOut:
    _exigir_tabelas(contexto)
    rev, cod = contexto.avaliacoes_moderacao.iniciar_analise(revisao_id, operador.id)
    if cod == "nao_encontrada" or rev is None:
        raise HTTPException(404, "Pedido de revisão não encontrado.")
    if cod == "ja_decidida":
        raise HTTPException(409, "Este pedido de revisão já foi decidido.")
    if cod == "ok":
        admin.auditoria.registrar(
            ator_id=operador.id,
            acao="avaliacao.revisao_em_analise",
            entidade="avaliacao_revisoes",
            entidade_id=rev.id,
            depois={"status": "em_analise", "avaliacao_id": rev.avaliacao_id},
            motivo=f"Análise iniciada para revisão {rev.protocolo}",
        )
    return _rev_out(rev)


@router.post(
    "/revisoes/{revisao_id}/decidir",
    response_model=RevisaoAvaliacaoAdminOut,
    summary="Decidir pedido de revisão de avaliação (aceita ou recusada)",
)
def decidir_revisao(
    revisao_id: str,
    corpo: DecidirRevisaoIn,
    request: Request,
    resposta: Response,
    operador: Operador = Depends(exigir(Permissao.AVALIACOES_MODERAR)),
    contexto: Contexto = Depends(obter_contexto),
    admin: AdminContexto = Depends(obter_admin),
) -> RevisaoAvaliacaoAdminOut:
    _exigir_tabelas(contexto)
    atual = contexto.avaliacoes_moderacao.obter_revisao(revisao_id)
    if atual is None:
        raise HTTPException(404, "Pedido de revisão não encontrado.")

    precisa_ocultar = (
        corpo.status == "aceita"
        and atual.tipo == "revisao"
        and atual.status not in ("aceita", "recusada")
        and contexto.avaliacoes_moderacao.ocultacao_ativa(atual.avaliacao_id) is None
    )
    if precisa_ocultar and corpo.ocultar_motivo is None:
        raise HTTPException(
            422, "Informe `ocultar_motivo` (cláusula 12.6) ao aceitar um pedido de revisão."
        )

    agora = contexto.agora()
    ocultacao_aplicada_id: str | None = None
    nova_ocultacao: OcultacaoAvaliacao | None = None
    with contexto.transacao():
        rev, cod = contexto.avaliacoes_moderacao.decidir_revisao(
            revisao_id,
            corpo.status,
            operador.id,
            corpo.resposta,
            agora,
            corpo.mesmo_analista_justificativa,
        )
        if cod == "nao_encontrada" or rev is None:
            raise HTTPException(404, "Pedido de revisão não encontrado.")
        if cod == "ja_decidida":
            raise HTTPException(409, "Este pedido de revisão já foi decidido.")
        if cod == "mesmo_analista_sem_justificativa":
            raise HTTPException(
                422,
                "Contestação analisada pelo mesmo analista da ocultação exige "
                "`mesmo_analista_justificativa` (Termos 20.5).",
            )
        if cod == "ok":
            if corpo.status == "aceita" and rev.tipo == "revisao":
                ativa = contexto.avaliacoes_moderacao.ocultacao_ativa(rev.avaliacao_id)
                if ativa is None and corpo.ocultar_motivo is not None:
                    ocu, cod_ocu = contexto.avaliacoes_moderacao.ocultar(
                        rev.avaliacao_id,
                        corpo.ocultar_motivo,
                        corpo.resposta,
                        operador.id,
                        agora,
                    )
                    if cod_ocu == "ok" and ocu is not None:
                        ocultacao_aplicada_id = ocu.id
                        nova_ocultacao = ocu
                elif ativa is not None:
                    ocultacao_aplicada_id = ativa.id
            elif corpo.status == "aceita" and rev.tipo == "contestacao_ocultacao":
                ocu_rev, cod_rev = contexto.avaliacoes_moderacao.reverter_ocultacao(
                    rev.avaliacao_id, operador.id, agora
                )
                if cod_rev == "ok" and ocu_rev is not None:
                    ocultacao_aplicada_id = ocu_rev.id

            admin.auditoria.registrar(
                ator_id=operador.id,
                acao="avaliacao.revisao_decidida",
                entidade="avaliacao_revisoes",
                entidade_id=rev.id,
                depois={
                    "status": rev.status,
                    "tipo": rev.tipo,
                    "avaliacao_id": rev.avaliacao_id,
                    "ocultacao_aplicada_id": ocultacao_aplicada_id,
                    "aviso_adiado": corpo.adiar_aviso,
                    "justificativa_adiamento": corpo.justificativa_adiamento
                    if corpo.adiar_aviso
                    else None,
                },
                motivo=corpo.resposta,
            )
        else:
            resposta.status_code = 200
            ativa = contexto.avaliacoes_moderacao.ocultacao_ativa(rev.avaliacao_id)
            ocultacao_aplicada_id = ativa.id if ativa else rev.ocultacao_id

    if nova_ocultacao is not None and not corpo.adiar_aviso:
        _avisar_autor(request, contexto, nova_ocultacao)  # depois do commit
    return _rev_out(rev, ocultacao_aplicada_id=ocultacao_aplicada_id)
