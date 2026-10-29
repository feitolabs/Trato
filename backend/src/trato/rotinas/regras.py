"""Rotinas automáticas como regras puras (F4.9).

Cada função recebe o "agora" (injetado: aqui nunca se lê o relógio), o estado dos pedidos e a
configuração, e devolve a LISTA de ações a executar. Nada é executado aqui: sem banco,
sem agendador, sem Stripe. Quem executa grava cada ação pela sua `chave`.

Idempotência: a lista depende só dos argumentos, então rodar duas vezes no mesmo instante dá
a mesma lista; a `chave` de cada ação é estável. Uma ação já feita some sozinha (o estado do
pedido mudou) ou entra em `ja_executadas` (lembretes, que não mudam o estado).

Transições (expirar, concluir por prazo, ausência) NÃO são reescritas aqui: a rotina pergunta à
máquina de estados do F4.1 (`transicionar` como `SISTEMA`) se a ação já vale e só a devolve se vale.

Prazos: todos vêm de `ConfigRotinas`, resolvidos pelo backend a partir da tabela de
configuração (docs/modelo-de-dados.md, 4.3). Campo `None` = prazo ainda não configurado: a
rotina daquele item fica desligada. Nunca há prazo fixo no código.

Dúvidas que mudam o comportamento (ficam como parâmetro até o João decidir):
- P1: `prazo_liberacao` é 48 h ou 7 dias? E `prazo_confirmacao_cliente` (48 h; 72 h acima do
  limite de valor). Basta trocar os valores da configuração.
- N17/D3: a janela de reclamação (`janela_reclamacao`) bloqueia a liberação? Com
  `liberacao_espera_janela=True` o saldo só é liberado depois dela; com `False`, só vale
  `prazo_liberacao`.
- N14: não existe prazo de aprovação de aditivo; só o intervalo do lembrete.
"""

from __future__ import annotations

from dataclasses import dataclass
from datetime import date, datetime, timedelta
from enum import StrEnum

from trato.pedidos.estados import (
    Acao,
    Ator,
    Estado,
    Papel,
    Pedido,
    PrazosPedido,
    TransicaoInvalida,
    transicionar,
)
from trato.rotinas.dias_uteis import somar_dias_uteis

SISTEMA = Ator(Papel.SISTEMA, "sistema")


@dataclass(frozen=True)
class ConfigRotinas:
    # Expiração
    validade_pedido: timedelta | None = None
    validade_pedido_urgente: timedelta | None = None
    prazo_pagamento: timedelta | None = None
    tolerancia_comparecimento: timedelta | None = None
    # Conclusão e liberação
    prazo_confirmacao_cliente: timedelta | None = None
    prazo_confirmacao_cliente_acima_do_limite: timedelta | None = None
    limite_valor_prazo_maior_centavos: int | None = None
    prazo_liberacao: timedelta | None = None
    janela_reclamacao: timedelta | None = None
    liberacao_espera_janela: bool = False
    # Disputa
    prazo_resposta_disputa: timedelta | None = None
    prazo_decisao_disputa_dias_uteis: int | None = None
    # Lembretes (quanto tempo depois do marco, ou quanto antes do prazo)
    lembrete_confirmacao_apos: timedelta | None = None
    lembrete_resposta_disputa_antecedencia: timedelta | None = None
    lembrete_decisao_disputa_antecedencia: timedelta | None = None
    lembrete_aditivo_apos: timedelta | None = None


@dataclass(frozen=True)
class DisputaMonitorada:
    aberta_em: datetime
    respondida: bool = False


@dataclass(frozen=True)
class PedidoMonitorado:
    """Foto do pedido que a rotina precisa. Quem chama monta a partir do banco."""

    pedido: Pedido
    valor_servico_centavos: int = 0
    urgente: bool = False
    orcamentos_recebidos: int = 0
    saldo_a_liberar_centavos: int = 0  # saldo do ledger (conta a liberar do pedido)
    disputa: DisputaMonitorada | None = None
    disputa_aberta: bool = False  # qualquer disputa ainda sem decisão
    aditivo_pendente_desde: datetime | None = None


class TipoAcaoRotina(StrEnum):
    TRANSICIONAR = "transicionar"  # aplicar `acao` (F4.1) como sistema
    LIBERAR_SALDO = "liberar_saldo"  # ledger: a liberar -> liberado
    LEMBRETE = "lembrete"


class Lembrete(StrEnum):
    CONFIRMACAO_PENDENTE = "confirmacao_pendente"  # para o cliente
    RESPOSTA_DISPUTA = "resposta_disputa"  # para o profissional
    DECISAO_DISPUTA = "decisao_disputa"  # para o mediador
    ADITIVO_AGUARDANDO = "aditivo_aguardando"  # para o cliente


@dataclass(frozen=True)
class AcaoRotina:
    tipo: TipoAcaoRotina
    pedido_id: str
    chave: str
    acao: Acao | None = None
    lembrete: Lembrete | None = None
    destinatario: Papel | None = None
    valor_centavos: int | None = None
    profissional_id: str | None = None


def prazo_confirmacao(valor_centavos: int, config: ConfigRotinas) -> timedelta | None:
    """Prazo do cliente para confirmar: o maior só vale acima do limite de valor (escopo 4, P1)."""
    limite = config.limite_valor_prazo_maior_centavos
    if (
        limite is not None
        and valor_centavos > limite
        and config.prazo_confirmacao_cliente_acima_do_limite is not None
    ):
        return config.prazo_confirmacao_cliente_acima_do_limite
    return config.prazo_confirmacao_cliente


def _prazos_do_pedido(item: PedidoMonitorado, config: ConfigRotinas) -> PrazosPedido:
    validade = config.validade_pedido
    if item.urgente and config.validade_pedido_urgente is not None:
        validade = config.validade_pedido_urgente
    return PrazosPedido(
        receber_orcamentos=validade,
        pagamento=config.prazo_pagamento,
        tolerancia_comparecimento=config.tolerancia_comparecimento,
        confirmacao_cliente=prazo_confirmacao(item.valor_servico_centavos, config),
    )


_TRANSICOES_AUTOMATICAS = {
    Estado.ABERTO: Acao.EXPIRAR_PEDIDO,
    Estado.ORCAMENTO_ACEITO: Acao.EXPIRAR_PAGAMENTO,
    Estado.AGENDADO: Acao.REGISTRAR_AUSENCIA,
    Estado.EM_CONFIRMACAO: Acao.CONCLUIR_POR_PRAZO,
}


def transicoes_por_prazo(
    agora: datetime, itens: list[PedidoMonitorado], config: ConfigRotinas
) -> list[AcaoRotina]:
    """Expirações e conclusão por prazo, só as que a máquina de estados já aceita agora."""
    saida = []
    for item in itens:
        pedido = item.pedido
        acao = _TRANSICOES_AUTOMATICAS.get(pedido.estado)
        if acao is None:
            continue
        if pedido.estado is Estado.ABERTO and item.orcamentos_recebidos > 0:
            continue  # recebeu orçamento: o cliente decide, o pedido não expira
        if pedido.estado is Estado.EM_CONFIRMACAO and item.disputa_aberta:
            continue
        try:
            transicionar(pedido, acao, SISTEMA, agora, prazos=_prazos_do_pedido(item, config))
        except TransicaoInvalida:
            continue  # prazo não venceu ou não configurado
        marco = _marco_da_transicao(pedido, acao)
        saida.append(
            AcaoRotina(
                TipoAcaoRotina.TRANSICIONAR,
                pedido.id,
                f"transicao:{acao.value}:{pedido.id}:{marco.isoformat()}",
                acao=acao,
            )
        )
    return saida


def _marco_da_transicao(pedido: Pedido, acao: Acao) -> datetime:
    marcos = {
        Acao.EXPIRAR_PEDIDO: pedido.aberto_em,
        Acao.EXPIRAR_PAGAMENTO: pedido.aceito_em,
        Acao.REGISTRAR_AUSENCIA: pedido.janela.fim if pedido.janela else None,
        Acao.CONCLUIR_POR_PRAZO: pedido.check_out_em,
    }
    return marcos[acao] or pedido.aberto_em


def liberacoes_por_prazo(
    agora: datetime, itens: list[PedidoMonitorado], config: ConfigRotinas
) -> list[AcaoRotina]:
    """Libera o saldo do profissional depois do prazo, se o pedido está concluído e sem disputa.

    Instante da liberação = `concluido_em + prazo_liberacao`; com `liberacao_espera_janela`,
    o maior entre isso e `concluido_em + janela_reclamacao`. No limite exato já libera.
    """
    if config.prazo_liberacao is None:
        return []
    saida = []
    for item in itens:
        pedido = item.pedido
        if pedido.estado is not Estado.CONCLUIDO or pedido.concluido_em is None:
            continue
        if item.disputa_aberta or item.saldo_a_liberar_centavos <= 0:
            continue
        espera = config.prazo_liberacao
        if config.liberacao_espera_janela and config.janela_reclamacao is not None:
            espera = max(espera, config.janela_reclamacao)
        if agora < pedido.concluido_em + espera:
            continue
        saida.append(
            AcaoRotina(
                TipoAcaoRotina.LIBERAR_SALDO,
                pedido.id,
                f"liberacao:{pedido.id}:{item.saldo_a_liberar_centavos}:"
                f"{pedido.concluido_em.isoformat()}",
                valor_centavos=item.saldo_a_liberar_centavos,
                profissional_id=pedido.profissional_id,
            )
        )
    return saida


def _limite_decisao(
    disputa: DisputaMonitorada, dias_uteis: int, feriados: frozenset[date]
) -> datetime:
    """Mesma hora da abertura, `dias_uteis` dias úteis depois (no fuso da abertura)."""
    dia = somar_dias_uteis(disputa.aberta_em.date(), dias_uteis, feriados)
    return datetime.combine(dia, disputa.aberta_em.timetz())


def lembretes(
    agora: datetime,
    itens: list[PedidoMonitorado],
    config: ConfigRotinas,
    feriados: frozenset[date] = frozenset(),
) -> list[AcaoRotina]:
    """Lembretes devidos agora. Cada marco gera uma chave só; quem já enviou filtra por ela."""
    saida = []

    def lembrar(item, tipo: Lembrete, para: Papel, marco: datetime, devido: datetime):
        if agora >= devido:
            saida.append(
                AcaoRotina(
                    TipoAcaoRotina.LEMBRETE,
                    item.pedido.id,
                    f"lembrete:{tipo.value}:{item.pedido.id}:{marco.isoformat()}",
                    lembrete=tipo,
                    destinatario=para,
                )
            )

    for item in itens:
        pedido = item.pedido
        prazo_conf = prazo_confirmacao(item.valor_servico_centavos, config)
        if (
            pedido.estado is Estado.EM_CONFIRMACAO
            and pedido.check_out_em
            and config.lembrete_confirmacao_apos is not None
            and not item.disputa_aberta
            and (prazo_conf is None or agora < pedido.check_out_em + prazo_conf)
        ):
            lembrar(
                item,
                Lembrete.CONFIRMACAO_PENDENTE,
                Papel.CLIENTE,
                pedido.check_out_em,
                pedido.check_out_em + config.lembrete_confirmacao_apos,
            )
        disputa = item.disputa
        if pedido.estado is Estado.EM_DISPUTA and disputa is not None:
            prazo_resp = config.prazo_resposta_disputa
            antecedencia = config.lembrete_resposta_disputa_antecedencia
            if not disputa.respondida and prazo_resp is not None and antecedencia is not None:
                limite = disputa.aberta_em + prazo_resp
                if agora < limite:
                    lembrar(
                        item,
                        Lembrete.RESPOSTA_DISPUTA,
                        Papel.PROFISSIONAL,
                        disputa.aberta_em,
                        limite - antecedencia,
                    )
            dias = config.prazo_decisao_disputa_dias_uteis
            antecedencia = config.lembrete_decisao_disputa_antecedencia
            if dias is not None and antecedencia is not None:
                lembrar(
                    item,
                    Lembrete.DECISAO_DISPUTA,
                    Papel.MEDIADOR,
                    disputa.aberta_em,
                    _limite_decisao(disputa, dias, feriados) - antecedencia,
                )
        desde = item.aditivo_pendente_desde
        if desde is not None and config.lembrete_aditivo_apos is not None:
            lembrar(
                item,
                Lembrete.ADITIVO_AGUARDANDO,
                Papel.CLIENTE,
                desde,
                desde + config.lembrete_aditivo_apos,
            )
    return saida


def rotinas_do_instante(
    agora: datetime,
    itens: list[PedidoMonitorado],
    config: ConfigRotinas,
    feriados: frozenset[date] = frozenset(),
    ja_executadas: frozenset[str] = frozenset(),
) -> list[AcaoRotina]:
    """Tudo que deve rodar em `agora`, em ordem estável, sem repetir chave."""
    if agora.tzinfo is None:
        raise ValueError("O instante precisa ter fuso horário.")
    todas = (
        transicoes_por_prazo(agora, itens, config)
        + liberacoes_por_prazo(agora, itens, config)
        + lembretes(agora, itens, config, feriados)
    )
    vistas: set[str] = set(ja_executadas)
    saida = []
    for acao in sorted(todas, key=lambda a: (a.pedido_id, a.tipo.value, a.chave)):
        if acao.chave not in vistas:
            vistas.add(acao.chave)
            saida.append(acao)
    return saida
