"""Compensação em repasses (Termos 8.6 e 17.4).

Ordem: (1) registrar a dívida (o banco lança no livro) e, na mesma transação, a ordem de estorno
ao cliente; o provedor só é chamado depois do commit; (2) avisar o profissional com o motivo e
só então marcar a dívida como avisada; (3) cada liberação desconta, na transação dela; (4)
contestação aceita cancela a dívida e devolve o que foi descontado.
"""

from __future__ import annotations

import logging
from typing import Any

from fastapi import APIRouter, Depends
from pydantic import BaseModel, Field

from trato.api.auth import PapelUsuario, Usuario
from trato.api.contexto import Contexto, exigir_papel, obter_contexto
from trato.financeiro.extrato_profissional import reais
from trato.notificacoes.eventos import Evento
from trato.persistencia.compensacoes import Divida

router = APIRouter(prefix="/v1/me/compensacoes", tags=["compensações"])
log = logging.getLogger("trato.compensacoes")


class DividaOut(BaseModel):
    id: str
    pedido_id: str
    origem: str
    valor_centavos: int = Field(description="O que vale hoje (já com as reduções).")
    valor_original_centavos: int
    reduzido_centavos: int = 0
    devolvido_reducao_centavos: int = Field(
        0, description="Quanto voltou ao profissional por causa de reduções."
    )
    compensado_centavos: int
    restante_centavos: int
    motivo: str
    status: str
    criada_em: Any
    avisado_em: Any = None
    cancelada_em: Any = None
    motivo_cancelamento: str | None = None
    suspensa: bool = Field(
        False,
        description="Dívida aberta cuja decisão foi depois revertida ou reduzida (8.7): nada é "
        "descontado. Cancelar faz o Trato assumir o valor INTEIRO.",
    )


class DividaAdminOut(DividaOut):
    """Só no painel. O profissional recebe `DividaOut`, sem nada disto."""

    revisao: str | None = Field(
        None,
        description="Decisão posterior mais baixa ainda sem tratamento, inclusive em quitada: "
        "reducao (usar Reduzir) | reversao (usar Cancelar) | analisar (a dívida ainda cabe na "
        "nova decisão; não há redução obrigatória). null: nada pendente.",
    )
    revisao_contestacao_id: str | None = None
    pode_reduzir: bool = Field(False, description="Há redução aplicável E este operador pode.")
    reducao_maxima_centavos: int | None = Field(
        None, description="Maior novo valor aceito; só vem com `pode_reduzir`."
    )
    pode_cancelar: bool = Field(False, description="Não cancelada E este operador pode.")


def saida_admin(d: Divida, pode_mexer: bool) -> DividaAdminOut:
    maximo = d.reducao_maxima_centavos if pode_mexer else None
    return DividaAdminOut(
        **saida(d).model_dump(),
        revisao=d.revisao,
        revisao_contestacao_id=d.revisao_contestacao_id,
        pode_reduzir=maximo is not None,
        reducao_maxima_centavos=maximo,
        pode_cancelar=pode_mexer and d.status != "cancelada",
    )


def saida(d: Divida) -> DividaOut:
    restante = 0 if d.status == "cancelada" else d.valor_centavos - d.compensado_centavos
    return DividaOut(
        id=d.id,
        pedido_id=d.pedido_id,
        origem=d.origem_tipo,
        valor_centavos=d.valor_centavos,
        valor_original_centavos=d.valor_centavos + d.reduzido_centavos,
        reduzido_centavos=d.reduzido_centavos,
        devolvido_reducao_centavos=d.devolvido_reducao_centavos,
        compensado_centavos=d.compensado_centavos,
        restante_centavos=restante,
        motivo=d.motivo,
        status=d.status,
        criada_em=d.criada_em,
        avisado_em=d.avisado_em,
        cancelada_em=d.cancelada_em,
        motivo_cancelamento=d.motivo_cancelamento,
        suspensa=d.suspensa,
    )


def avisar_divida(contexto: Contexto, divida_id: str, operador_id: str) -> bool:
    """Avisa o profissional e SÓ ENTÃO marca a dívida: sem aviso registrado, nada é compensado.
    Devolve se a dívida está avisada. Pode repetir."""
    divida = contexto.compensacoes.obter(divida_id)
    if divida is None:
        return False
    if divida.avisado_em is not None:
        return True
    notificador = contexto.extras.get("notificador")
    if notificador is None:
        return False
    try:
        notificador.notificar(
            Evento.COMPENSACAO_REGISTRADA,
            divida.profissional_id,
            chave=f"compensacao:{divida.id}:registrada",
            pedido_id=divida.pedido_id,
            corpo=f"{reais(divida.valor_centavos)} serão descontados dos próximos repasses "
            f"deste serviço. Motivo: {divida.motivo} Você pode contestar pelo atendimento.",
            dados={"compensacao_id": divida.id},
        )
    except Exception:  # noqa: BLE001 - sem aviso, a dívida fica sem compensar
        log.exception("Aviso da compensação %s falhou", divida.id)
        return False
    marcado = contexto.compensacoes.avisar(divida.id, operador_id)
    return marcado in ("ok", "ja_avisada")


def compensar_na_liberacao(contexto: Contexto, pedido_id: str, lancamento_id: str) -> None:
    """Chamar DENTRO da transação que passou o valor de 'a liberar' para 'liberado'."""
    contexto.compensacoes.aplicar(pedido_id, f"repasse:{lancamento_id}")


@router.get("", response_model=list[DividaOut], summary="Profissional: minhas compensações")
def minhas(
    usuario: Usuario = Depends(exigir_papel(PapelUsuario.PROFISSIONAL)),
    contexto: Contexto = Depends(obter_contexto),
) -> list[DividaOut]:
    # Sem a dívida avisada o profissional ainda não foi notificado: aparece depois do aviso.
    itens, _ = contexto.compensacoes.listar(profissional_id=usuario.id)
    return [saida(d) for d in itens if d.avisado_em is not None or d.status == "cancelada"]
