"""Termos 13.11 e I.12: o que pode mudar na hora nos Tratinhos e o que depende de aviso.

Melhora vale na hora. Piora (ou fim do programa) só vale com aviso emitido há pelo menos 30 dias.
Piora no USO também não vale enquanto houver saldo válido: a configuração é uma só e atingiria o
que já foi creditado. Onde o texto não decide (tetos e orçamento de desconto), vale a opção mais
favorável ao consumidor: contam como uso."""

from __future__ import annotations

import logging
from datetime import date, datetime, time, timedelta
from typing import Any

from trato.api.admin.repositorios import FiltroAuditoria
from trato.api.moedas import VALIDADE_PADRAO_DIAS, ConfigMoedas
from trato.financeiro import periodo

log = logging.getLogger("trato.mudanca_moedas")

ACAO_AVISO = "notificacao.aviso_previo"
ACAO_CONFIG = "moedas.config_alterada"
_MENOR, _MAIOR = -1, 1  # em que direção o valor piora

PIORA_USO = {
    "valor_moeda_centavos": (_MENOR, "valor de cada Tratinho em centavos"),
    "max_desconto_percentual": (_MENOR, "desconto máximo por serviço em %"),
    "orcamento_mensal_desconto_centavos": (_MENOR, "orçamento mensal de desconto em centavos"),
    "teto_diario_desconto_centavos": (_MENOR, "teto diário de desconto em centavos"),
    "teto_desconto_cliente_mes_centavos": (_MENOR, "teto mensal por cliente em centavos"),
    "max_reservas_abertas": (_MENOR, "cobranças abertas com desconto"),
    "reserva_minutos": (_MENOR, "minutos de reserva do desconto"),
    "exclusividade_custo_moedas": (_MAIOR, "custo da exclusividade em Tratinhos"),
    "exclusividade_duracao_horas": (_MENOR, "duração da exclusividade em horas"),
}
PIORA_REGRA = {
    "ativo": (_MENOR, "programa ativo (0 = encerrado)"),
    "bonus_avaliacao_moedas": (_MENOR, "bônus por avaliação do cliente"),
    "bonus_avaliacao_profissional_moedas": (_MENOR, "bônus por avaliação do profissional"),
    "teto_mensal_moedas": (_MENOR, "teto mensal de Tratinhos ganhos"),
    "max_bonus_por_profissional_mes": (_MENOR, "bônus por profissional no mês"),
    "min_servico_centavos": (_MAIOR, "serviço mínimo para ganhar em centavos"),
    "validade_dias": (_MENOR, "validade dos novos Tratinhos em dias"),
    "dias_liberacao_bonus": (_MAIOR, "dias para liberar o bônus"),
}
CAMPOS = PIORA_USO | PIORA_REGRA


class MudancaRecusada(Exception):
    def __init__(
        self, codigo: str, mensagem: str, campos: list[str], pode_valer_em: date | None = None
    ) -> None:
        super().__init__(mensagem)
        self.corpo: dict[str, Any] = {"codigo": codigo, "detail": mensagem, "campos": campos}
        if pode_valer_em:
            self.corpo["pode_valer_em"] = pode_valer_em.isoformat()


def _numero(campo: str, valor: Any) -> int:
    if campo == "validade_dias" and valor is None:
        return VALIDADE_PADRAO_DIAS
    return int(valor)


def _piora(campo: str, de: Any, para: Any) -> bool:
    return (_numero(campo, para) - _numero(campo, de)) * CAMPOS[campo][0] > 0


def campos_que_pioram(antes: ConfigMoedas, novo: ConfigMoedas) -> list[str]:
    return [c for c in CAMPOS if _piora(c, getattr(antes, c), getattr(novo, c))]


def _ha_saldo(repo: Any, agora: datetime) -> bool:
    try:
        return bool(repo.ha_saldo_vivo(agora))
    except Exception:  # noqa: BLE001 - sem como saber: protege como se houvesse
        log.warning("saldo vivo de moedas indisponível", exc_info=True)
        return True


def _historico(auditoria: Any, acao: str) -> list[dict[str, Any]]:
    itens, _ = auditoria.listar(FiltroAuditoria(acao=acao), 500, 0)
    return [e.depois or {} for e in itens]


def autorizar(
    contexto: Any,
    auditoria: Any,
    antes: ConfigMoedas,
    novo: ConfigMoedas,
    referencia: str | None,
    dias: int,
) -> dict[str, Any] | None:
    """Levanta `MudancaRecusada`, ou devolve o aviso usado (None: não precisava de aviso)."""
    piores = campos_que_pioram(antes, novo)
    if not piores:
        return None
    agora = contexto.agora()
    de_uso = [c for c in piores if c in PIORA_USO]
    if de_uso and _ha_saldo(contexto.moedas, agora):
        raise MudancaRecusada(
            "creditos_vigentes",
            "Há Tratinhos válidos: o uso deles não pode piorar antes de vencerem.",
            de_uso,
        )
    if not antes.ativo:  # programa desligado: não há regra em vigor para quem ganha
        return None

    # cada aviso libera cada campo uma vez só: desligar de novo pede aviso novo
    usados = {
        (a["referencia"], a["vigencia"], campo)
        for a in (d.get("aviso") for d in _historico(auditoria, ACAO_CONFIG))
        if a
        for campo in a["campos"]
    }
    prazos: list[datetime] = []
    for envio in _historico(auditoria, ACAO_AVISO) if referencia else []:
        anunciado = envio.get("mudancas") or {}
        if (
            envio.get("tipo") != "tratinhos"
            or envio.get("referencia") != referencia
            or envio.get("falhas")
            or not envio.get("destinatarios")
            or any(
                c not in anunciado
                or _piora(c, anunciado[c], getattr(novo, c))  # pior que o anunciado
                or (referencia, envio["vigencia"], c) in usados
                for c in piores
            )
        ):
            continue
        emitido = datetime.fromisoformat(envio["emitido_em"])
        # meia-noite de Brasília do dia anunciado
        inicio = datetime.combine(date.fromisoformat(envio["vigencia"]), time(), periodo.BRASILIA)
        libera = max(emitido + timedelta(days=dias), inicio)
        if agora >= libera:
            return {"referencia": referencia, "vigencia": envio["vigencia"], "campos": piores}
        prazos.append(libera)
    if prazos:
        quando = min(prazos).astimezone(periodo.BRASILIA)
        raise MudancaRecusada(
            "aviso_no_prazo",
            f"O aviso ainda está no prazo: a mudança pode valer a partir de "
            f"{quando:%d/%m/%Y %H:%M}.",
            piores,
            quando,
        )
    raise MudancaRecusada(
        "aviso_obrigatorio",
        "Mudança desfavorável: envie antes o aviso dos Tratinhos com estes campos em "
        f"`mudancas` e aplique depois de {dias} dias, com `aviso_referencia`.",
        piores,
    )
