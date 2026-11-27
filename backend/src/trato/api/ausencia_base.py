"""Peças do caso de cliente ausente usadas pelo app e pelo painel (sem dependências de rota,
para o painel poder importar sem ciclo)."""

from __future__ import annotations

from collections.abc import Iterator
from contextlib import contextmanager, nullcontext
from datetime import datetime, time, timedelta
from threading import RLock
from typing import Any

from pydantic import BaseModel, Field

from trato.api.contexto import Contexto
from trato.financeiro import periodo
from trato.pedidos.estados import Acao, Pedido, ProvaClienteAusente
from trato.persistencia.ausencias import Ausencia
from trato.persistencia.cancelamentos import Cancelamento
from trato.persistencia.chamados import Revisao
from trato.rotinas.dias_uteis import somar_dias_uteis

_TRAVA_EM_MEMORIA = RLock()
URL_SEGUNDOS = 300  # link assinado curto


class ContestacaoOut(BaseModel):
    protocolo: str | None
    status: str = Field(description="aberta | mantida | alterada | revertida")
    texto: str
    anexos: list[str] = []
    aberta_em: datetime
    responder_ate: datetime
    resposta: str | None = None
    decidida_em: datetime | None = None


class AnexoOut(BaseModel):
    tipo: str = Field(
        description="registro_chegada | registro_ausencia | justificativa | "
        "comprovante_retencao | contestacao"
    )
    arquivo_id: str
    enviado_por: str | None = Field(None, description="cliente | profissional | equipe")
    url: str | None = Field(None, description="Link assinado curto; null se não é deste pedido.")
    content_type: str | None = Field(None, description="Tipo do arquivo (ex.: image/jpeg).")
    expira_em_segundos: int | None = None


class AusenciaOut(BaseModel):
    pedido_id: str
    status: str
    chegada_em: datetime
    pode_registrar_em: datetime = Field(description="Antes disso não vale 'Cliente ausente'.")
    registrada_em: datetime | None = None
    justificativa_ate: datetime | None = None
    justificativa_texto: str | None = None
    anexos: list[str] = []
    justificativa_enviada_em: datetime | None = None
    decisao: str | None = None
    # Retenção por custos comprovados (7.4): mostrada ao cliente antes de confirmar.
    retencao_centavos: int | None = None
    retencao_justificativa: str | None = None
    retencao_comprovantes: list[str] = []
    cancelamento_status: str | None = None
    reembolso_centavos: int | None = None
    contestar_ate: datetime | None = Field(
        None, description="Até quando o cliente contesta a retenção (5 dias úteis)."
    )
    contestacao: ContestacaoOut | None = None
    valor_servico_centavos: int | None = None
    # Só no painel:
    pedido_numero: int | None = None
    cliente_nome: str | None = None
    profissional_nome: str | None = None


def pode_registrar_em(item: Ausencia) -> datetime:
    """A espera conta do que vier depois: a chegada ou o horário marcado."""
    return max(item.chegada_em, item.janela_inicio) + timedelta(minutes=item.espera_minutos)


def do_pedido(contexto: Contexto, pedido: Pedido) -> Ausencia | None:
    if pedido.janela is None:
        return None
    return contexto.ausencias.obter(pedido.id, pedido.janela.inicio)


def contestar_ate(contexto: Contexto, mostrada_em: datetime) -> datetime:
    """Fim do último dia útil do prazo de contestação, em Brasília (8.7)."""
    cfg = contexto.config.carregar()
    ultimo = somar_dias_uteis(
        mostrada_em.astimezone(periodo.BRASILIA).date(),
        max(5, cfg.ausencia_contestacao_dias_uteis),
        frozenset(cfg.disputas.feriados),
    )
    return datetime.combine(ultimo, time.max, periodo.BRASILIA)


def caso_de(contexto: Contexto, pedido_id: str) -> Cancelamento | None:
    caso = contexto.cancelamentos.do_pedido(pedido_id)
    return caso if caso is not None and caso.tipo == "cliente_ausente" else None


def revisao_de(contexto: Contexto, caso: Cancelamento | None) -> Revisao | None:
    if caso is None or caso.retencao_mostrada_em is None:
        return None
    return contexto.chamados.revisao(caso.pedido_id, caso.retencao_mostrada_em)


def saida(contexto: Contexto, item: Ausencia) -> AusenciaOut:
    caso = caso_de(contexto, item.pedido_id)
    revisao = revisao_de(contexto, caso)
    contrato = contexto.contratos.obter_do_pedido(item.pedido_id)
    return AusenciaOut(
        valor_servico_centavos=contrato.valor_centavos if contrato else None,
        contestar_ate=contestar_ate(contexto, caso.retencao_mostrada_em)
        if caso and caso.retencao_mostrada_em
        else None,
        contestacao=ContestacaoOut(
            protocolo=revisao.protocolo,
            status=revisao.status,
            texto=revisao.texto,
            anexos=list(revisao.anexos),
            aberta_em=revisao.aberta_em,
            responder_ate=revisao.responder_ate,
            resposta=revisao.resposta,
            decidida_em=revisao.decidida_em,
        )
        if revisao
        else None,
        pedido_id=item.pedido_id,
        status=item.status,
        chegada_em=item.chegada_em,
        pode_registrar_em=pode_registrar_em(item),
        registrada_em=item.registrada_em,
        justificativa_ate=item.justificativa_ate,
        justificativa_texto=item.texto,
        anexos=list(item.anexos),
        justificativa_enviada_em=item.justificativa_em,
        decisao=item.decisao,
        retencao_centavos=caso.retencao_centavos if caso else None,
        retencao_justificativa=caso.retencao_justificativa if caso else None,
        retencao_comprovantes=list(caso.retencao_comprovantes) if caso else [],
        cancelamento_status=caso.status if caso else None,
        reembolso_centavos=caso.reembolso_centavos if caso else None,
    )


def sem_dados_do_cliente(out: AusenciaOut) -> AusenciaOut:
    """O que o profissional recebe: o andamento, nunca o que o cliente escreveu ou anexou."""
    contestacao = out.contestacao
    if contestacao is not None:
        contestacao = contestacao.model_copy(update={"texto": "", "anexos": [], "resposta": None})
    return out.model_copy(
        update={"justificativa_texto": None, "anexos": [], "contestacao": contestacao}
    )


@contextmanager
def uma_por_vez(contexto: Contexto, pedido_id: str) -> Iterator[None]:
    travar = getattr(contexto.pedidos, "travar", None)
    with _TRAVA_EM_MEMORIA if travar is None else nullcontext():
        with contexto.transacao():
            if travar is not None:
                travar(pedido_id)
            yield


# --- provas com link assinado curto --------------------------------------------------------------


def _mesmo(a: object, b: object) -> bool:
    return str(a).replace("-", "") == str(b).replace("-", "")


def midia_do_pedido(servico: Any, arquivo_id: str, pedido_id: str) -> Any:
    """A mídia só se for deste pedido (nunca assina arquivo de outro pedido)."""
    try:
        midia = servico.repo.midia(arquivo_id)
    except Exception:  # noqa: BLE001 - identificador que o armazenamento não reconhece
        return None
    return midia if midia is not None and _mesmo(midia.pedido_id, pedido_id) else None


def anexos_do_caso(
    contexto: Contexto, servico: Any, pedido: Pedido, item: Ausencia
) -> list[AnexoOut]:
    caso = caso_de(contexto, pedido.id)
    revisao = revisao_de(contexto, caso)
    pedidos: list[tuple[str, str]] = [
        ("registro_ausencia", e.prova.foto.arquivo_id)
        for e in contexto.pedidos.eventos(pedido.id)
        if e.acao is Acao.REGISTRAR_CLIENTE_AUSENTE
        and isinstance(e.prova, ProvaClienteAusente)
        and e.prova.foto is not None
    ]
    if item.foto_chegada:
        pedidos.insert(0, ("registro_chegada", item.foto_chegada))
    pedidos += [("justificativa", a) for a in item.anexos]
    pedidos += [("comprovante_retencao", a) for a in (caso.retencao_comprovantes if caso else ())]
    pedidos += [("contestacao", a) for a in (revisao.anexos if revisao else ())]
    saida_ = []
    for tipo, arquivo in pedidos:
        midia = midia_do_pedido(servico, arquivo, pedido.id)
        quem = url = tipo_do_arquivo = None
        if midia is not None:
            tipo_do_arquivo = midia.mime
            quem = (
                "cliente"
                if _mesmo(midia.enviada_por, pedido.cliente_id)
                else "profissional"
                if _mesmo(midia.enviada_por, pedido.profissional_id)
                else "equipe"
            )
            url = servico.armazenamento.url_leitura(midia.bucket, midia.storage_path, URL_SEGUNDOS)
        saida_.append(
            AnexoOut(
                tipo=tipo,
                arquivo_id=arquivo,
                enviado_por=quem,
                url=url,
                content_type=tipo_do_arquivo,
                expira_em_segundos=URL_SEGUNDOS if url else None,
            )
        )
    return saida_


# Arquivos do pedido que podem comprovar custos: nunca os do cliente nem os do chat (11.3).
FINALIDADES_DE_COMPROVANTE = (
    "antes", "durante", "depois", "checkin", "checkout", "nota_material", "aditivo", "disputa",
    "retrabalho",
)  # fmt: skip


def comprovantes_possiveis(servico: Any, pedido: Pedido) -> list[Any]:
    return [
        m
        for m in servico.repo.midias_do_pedido(pedido.id, FINALIDADES_DE_COMPROVANTE)
        if not _mesmo(m.enviada_por, pedido.cliente_id)
    ]


def eh_comprovante(servico: Any, pedido: Pedido, arquivo_id: str) -> bool:
    return any(_mesmo(m.id, arquivo_id) for m in comprovantes_possiveis(servico, pedido))
