"""Conciliação do ledger espelho com o extrato do provedor (V2.5, caminho A).

Pergunta, para um intervalo (normalmente um dia): o que o provedor diz que entrou e saiu bate com o
que o Trato registrou? Compara três coisas:

- cobrança: por cobrança do provedor (PaymentIntent). Do lado do Trato, a cobrança do ledger cuja
  chave traz esse id (`cob/<id>` ou `cobranca:<pedido>:<id>`).
- estorno: por pedido. Do lado do Trato, o estorno devolvido ao cliente menos o que foi lançado de
  novo como "mantido" (o estorno parcial estorna o lançamento inteiro e relança o resto).
- contestação: por pedido. O provedor tira o valor quando a contestação abre; o Trato só lança
  quando ela é perdida. Diferença aqui com contestação aberta é esperada e a tela diz isso.

Folga: o aviso do provedor chega segundos ou minutos depois do movimento. Para casar, o Trato
é lido com uma folga antes e depois do intervalo; só o que está DENTRO do intervalo e não casou com
nada aparece como "só no Trato".

Nada aqui grava: é só leitura e comparação. Centavos inteiros.
"""

from __future__ import annotations

from collections.abc import Iterable, Sequence
from dataclasses import dataclass, field
from datetime import datetime, timedelta

from trato.financeiro.ledger import CLIENTE, Lancamento, TipoLancamento
from trato.pagamentos.provedor.base import MovimentoProvedor, TipoMovimento

FOLGA_PADRAO = timedelta(hours=2)

CONFERE = "confere"
SO_NO_PROVEDOR = "so_no_provedor"
SO_NO_TRATO = "so_no_trato"
VALOR_DIFERENTE = "valor_diferente"


@dataclass(frozen=True)
class LinhaConciliacao:
    tipo: str  # cobranca | estorno | contestacao
    referencia: str  # id da cobrança no provedor (cobrança) ou o pedido (estorno, contestação)
    valor_provedor_centavos: int
    valor_trato_centavos: int
    situacao: str
    pedido_id: str | None = None

    @property
    def diferenca_centavos(self) -> int:
        return self.valor_provedor_centavos - self.valor_trato_centavos


@dataclass(frozen=True)
class ResultadoConciliacao:
    desde: datetime
    ate: datetime
    linhas: tuple[LinhaConciliacao, ...]
    cobrado_provedor_centavos: int
    cobrado_trato_centavos: int
    taxas_provedor_centavos: int  # o custo real do provedor no período
    movimentos_ignorados: int  # repasses, saques e outros que não entram na comparação
    divergencias: tuple[LinhaConciliacao, ...] = field(default=())

    @property
    def confere(self) -> bool:
        return not self.divergencias


def referencia_da_cobranca(chave: str) -> str | None:
    """O id do provedor dentro da chave de idempotência da cobrança no ledger."""
    if "/mantida/" in chave:
        return None
    if chave.startswith("cob/"):
        resto = chave.removeprefix("cob/")
        return resto.split("/", 1)[0] or None
    if chave.startswith("cobranca:"):
        partes = chave.split(":", 2)
        return partes[2] if len(partes) == 3 and partes[2] else None
    return None


def _entre(item: Lancamento, desde: datetime, ate: datetime) -> bool:
    return desde <= item.data < ate


def _somas_do_trato(
    lancamentos: Iterable[Lancamento], desde: datetime, ate: datetime
) -> tuple[dict[str, int], dict[str, int], dict[str, int]]:
    """(cobrado por referência, estornado por pedido, contestado por pedido) no intervalo."""
    cobrado: dict[str, int] = {}
    estornado: dict[str, int] = {}
    contestado: dict[str, int] = {}
    for item in lancamentos:
        if not _entre(item, desde, ate):
            continue
        destino = contestado if item.chave.startswith("contest/") else estornado
        if item.tipo is TipoLancamento.COBRANCA:
            ref = referencia_da_cobranca(item.chave)
            if ref is not None:
                cobrado[ref] = cobrado.get(ref, 0) + item.valor
            elif "/mantida/" in item.chave and item.debito == CLIENTE:
                destino[item.pedido_id] = destino.get(item.pedido_id, 0) - item.valor
        elif item.tipo is TipoLancamento.ESTORNO and item.credito == CLIENTE:
            destino[item.pedido_id] = destino.get(item.pedido_id, 0) + item.valor
    return cobrado, estornado, contestado


def _comparar(
    tipo: str,
    provedor: dict[str, int],
    trato_largo: dict[str, int],
    trato_estrito: dict[str, int],
    pedido_de: dict[str, str],
) -> list[LinhaConciliacao]:
    linhas = []
    for ref in sorted(set(provedor) | {r for r, v in trato_estrito.items() if v}):
        no_provedor = provedor.get(ref)
        no_trato = (trato_largo if no_provedor is not None else trato_estrito).get(ref, 0)
        if no_provedor is None:
            situacao = SO_NO_TRATO
        elif no_trato == 0 and no_provedor != 0:
            situacao = SO_NO_PROVEDOR
        elif no_trato != no_provedor:
            situacao = VALOR_DIFERENTE
        else:
            situacao = CONFERE
        pedido = ref if tipo != "cobranca" else pedido_de.get(ref)
        linhas.append(
            LinhaConciliacao(tipo, ref, no_provedor or 0, no_trato, situacao, pedido or None)
        )
    return linhas


def conciliar(
    movimentos: Sequence[MovimentoProvedor],
    lancamentos: Sequence[Lancamento],
    desde: datetime,
    ate: datetime,
    folga: timedelta = FOLGA_PADRAO,
) -> ResultadoConciliacao:
    # Qual pedido é de cada cobrança do provedor: das cobranças do ledger de qualquer data.
    pedido_de: dict[str, str] = {}
    for item in lancamentos:
        if item.tipo is TipoLancamento.COBRANCA:
            ref = referencia_da_cobranca(item.chave)
            if ref is not None:
                pedido_de.setdefault(ref, item.pedido_id)

    cobrado_p: dict[str, int] = {}
    estornado_p: dict[str, int] = {}
    contestado_p: dict[str, int] = {}
    taxas = 0
    ignorados = 0
    for m in movimentos:
        taxas += m.taxa_provedor_centavos
        if m.tipo is TipoMovimento.TAXA_PROVEDOR:
            taxas += -m.valor_centavos
            continue
        ref = m.cobranca_id or m.id
        if m.tipo is TipoMovimento.COBRANCA:
            cobrado_p[ref] = cobrado_p.get(ref, 0) + m.valor_centavos
        elif m.tipo in (TipoMovimento.ESTORNO, TipoMovimento.CONTESTACAO):
            destino = estornado_p if m.tipo is TipoMovimento.ESTORNO else contestado_p
            chave = pedido_de.get(ref, ref)  # sem pedido conhecido, fica a cobrança do provedor
            destino[chave] = destino.get(chave, 0) - m.valor_centavos  # saída vira positivo
        else:
            ignorados += 1

    largo = _somas_do_trato(lancamentos, desde - folga, ate + folga)
    estrito = _somas_do_trato(lancamentos, desde, ate)
    linhas = (
        _comparar("cobranca", cobrado_p, largo[0], estrito[0], pedido_de)
        + _comparar("estorno", estornado_p, largo[1], estrito[1], pedido_de)
        + _comparar("contestacao", contestado_p, largo[2], estrito[2], pedido_de)
    )
    return ResultadoConciliacao(
        desde=desde,
        ate=ate,
        linhas=tuple(linhas),
        cobrado_provedor_centavos=sum(cobrado_p.values()),
        cobrado_trato_centavos=sum(estrito[0].values()),
        taxas_provedor_centavos=taxas,
        movimentos_ignorados=ignorados,
        divergencias=tuple(linha for linha in linhas if linha.situacao != CONFERE),
    )
