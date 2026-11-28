"""Avisos com antecedência mínima: mudança dos Termos (23.2), mudança ou fim dos Tratinhos
(13.11 e I.12) e conta inativa (4.9). Aqui só sai o aviso: nada é publicado, mudado ou
inativado. O texto do que muda é de quem envia; o prazo mínimo é do sistema."""

from __future__ import annotations

import json
import logging
import zlib
from datetime import date, timedelta
from typing import Literal

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel, ConfigDict, Field, StrictBool, StrictInt

from trato.api.admin.contexto import AdminContexto, Operador, exigir, obter_admin
from trato.api.admin.mudanca_moedas import ACAO_AVISO, CAMPOS
from trato.api.admin.papeis import Permissao
from trato.api.contexto import Contexto, obter_contexto
from trato.financeiro import periodo
from trato.notificacoes.eventos import Evento

log = logging.getLogger("trato.avisos_previos")
router = APIRouter(prefix="/v1/admin/avisos-previos", tags=["admin: avisos prévios"])
MINIMO_DIAS = 30  # os Termos: "pelo menos 30 dias"; a configuração só pode aumentar
_LOTE = 500
_EVENTOS = {
    "termos": Evento.AVISO_MUDANCA_TERMOS,
    "tratinhos": Evento.AVISO_MUDANCA_TRATINHOS,
    "inatividade": Evento.AVISO_INATIVACAO,
}


class AvisoPrevioIn(BaseModel):
    model_config = ConfigDict(extra="forbid", str_strip_whitespace=True)

    tipo: Literal["termos", "tratinhos", "inatividade"]
    referencia: str = Field(
        min_length=1,
        max_length=60,
        pattern=r"^[A-Za-z0-9._-]+$",
        description="Identifica a mudança (ex.: versão). Repetir não avisa duas vezes.",
    )
    vigencia: date = Field(description="Dia (Brasília) em que passa a valer.")
    resumo: str | None = Field(None, min_length=10, max_length=2000)
    motivo: str | None = Field(None, min_length=10, max_length=1000)
    link: str | None = Field(None, max_length=500, pattern=r"^https://\S+$")
    usuario_id: str | None = Field(None, max_length=64, description="Só em `inatividade`.")
    mudancas: dict[str, StrictBool | StrictInt] | None = Field(
        None,
        description="Só em `tratinhos`: campo da configuração e o novo valor. Sem isto, o aviso "
        "não libera mudança desfavorável.",
    )


class AvisoPrevioOut(BaseModel):
    tipo: str
    referencia: str
    vigencia: date
    antecedencia_minima_dias: int
    destinatarios: int
    avisos_novos: int = Field(description="Registros criados agora (app, push e e-mail).")
    falhas: int = Field(description="Pessoas não avisadas agora: repita o envio.")


def antecedencia_dias(contexto: Contexto, tipo: str) -> int:
    publicado = contexto.config.parametro_inteiro(f"aviso_previo_{tipo}_dias")
    return max(MINIMO_DIAS, publicado or MINIMO_DIAS)


def _conferir(corpo: AvisoPrevioIn) -> None:
    exigidos = {
        "termos": ("resumo", "motivo", "link"),  # 23.2: resumo, link e motivo
        "tratinhos": ("resumo",),
        "inatividade": ("usuario_id",),
    }[corpo.tipo]
    faltam = [campo for campo in exigidos if not getattr(corpo, campo)]
    if faltam:
        raise HTTPException(422, "Informe: " + ", ".join(faltam) + ".")
    if corpo.tipo != "inatividade" and corpo.usuario_id:
        raise HTTPException(422, "`usuario_id` só vale no aviso de conta inativa.")
    if corpo.mudancas is not None:
        if corpo.tipo != "tratinhos":
            raise HTTPException(422, "`mudancas` só vale no aviso dos Tratinhos.")
        estranhos = sorted(set(corpo.mudancas) - set(CAMPOS))
        if estranhos or not corpo.mudancas:
            raise HTTPException(422, "Campos inválidos em `mudancas`: " + ", ".join(estranhos))


def _texto(corpo: AvisoPrevioIn) -> str:
    dia = f"{corpo.vigencia:%d/%m/%Y}"
    if corpo.tipo == "termos":
        return (
            f"Os Termos de uso mudam em {dia}. O que muda: {corpo.resumo} "
            f"Motivo: {corpo.motivo} Versão completa: {corpo.link}"
        )
    if corpo.tipo == "tratinhos":
        novos = "; ".join(f"{CAMPOS[c][1]}: {int(v)}" for c, v in (corpo.mudancas or {}).items())
        return (
            f"O programa de Tratinhos muda em {dia}. {corpo.resumo} "
            + (f"Novos valores: {novos}. " if novos else "")
            + "Os Tratinhos já creditados "
            "valem até o fim da validade que tinham quando foram creditados."
        )
    return (
        f"A sua conta está sem uso e pode ser inativada a partir de {dia}. A reativação é "
        "gratuita, pelo atendimento ou pelo aplicativo."
    )


@router.post("", response_model=AvisoPrevioOut, summary="Enviar aviso com antecedência mínima")
def avisar(
    corpo: AvisoPrevioIn,
    operador: Operador = Depends(exigir(Permissao.NOTIFICACOES_ENVIAR)),
    admin: AdminContexto = Depends(obter_admin),
    contexto: Contexto = Depends(obter_contexto),
) -> AvisoPrevioOut:
    _conferir(corpo)
    dias = antecedencia_dias(contexto, corpo.tipo)
    hoje = contexto.agora().astimezone(periodo.BRASILIA).date()
    if corpo.vigencia < hoje + timedelta(days=dias):
        raise HTTPException(
            422,
            f"A vigência precisa ficar a pelo menos {dias} dias: a partir de "
            f"{hoje + timedelta(days=dias):%d/%m/%Y}.",
        )
    notificador = contexto.extras.get("notificador")
    if notificador is None:
        raise HTTPException(503, "O envio de avisos não está ligado.")
    if corpo.usuario_id and contexto.usuarios.detalhe(corpo.usuario_id) is None:
        raise HTTPException(404, "Usuário não encontrado.")

    destinatarios = novos = falhas = 0
    chave = f"previo:{corpo.referencia}:{corpo.vigencia.isoformat()}"
    if corpo.mudancas:  # outros valores são outro aviso: todos precisam receber de novo
        chave += f":{zlib.crc32(json.dumps(corpo.mudancas, sort_keys=True).encode()):08x}"
    ultimo: str | None = None
    while True:
        lote = (
            [corpo.usuario_id]
            if corpo.usuario_id
            else list(contexto.usuarios.ids_para_aviso(ultimo, _LOTE))
        )
        for pessoa in lote:
            destinatarios += 1
            try:
                novos += len(
                    notificador.notificar(
                        _EVENTOS[corpo.tipo],
                        pessoa,
                        # a data faz parte da chave: mudar a vigência gera aviso novo
                        chave=chave,
                        corpo=_texto(corpo),
                    )
                )
            except Exception:  # noqa: BLE001 - uma pessoa não impede as outras
                log.exception("Aviso prévio falhou")
                falhas += 1
        if corpo.usuario_id or len(lote) < _LOTE:
            break
        ultimo = lote[-1]
    depois_auditoria = {
        "tipo": corpo.tipo,
        "referencia": corpo.referencia,
        "vigencia": corpo.vigencia.isoformat(),
        "destinatarios": destinatarios,
        "falhas": falhas,
        "mudancas": corpo.mudancas,
        "emitido_em": contexto.agora().isoformat(),
    }
    if corpo.tipo == "inatividade" and corpo.usuario_id:
        depois_auditoria["usuario_id"] = corpo.usuario_id
    admin.auditoria.registrar(
        ator_id=operador.id,
        acao=ACAO_AVISO,
        entidade="aviso_previo",
        entidade_id=corpo.usuario_id if corpo.tipo == "inatividade" else None,
        depois=depois_auditoria,
        motivo=corpo.motivo or f"Aviso prévio: {corpo.tipo}",
    )
    return AvisoPrevioOut(
        tipo=corpo.tipo,
        referencia=corpo.referencia,
        vigencia=corpo.vigencia,
        antecedencia_minima_dias=dias,
        destinatarios=destinatarios,
        avisos_novos=novos,
        falhas=falhas,
    )
