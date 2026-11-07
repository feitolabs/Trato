"""Fechamento mensal: o retrato do mês para o contador, e a trava do mês fechado.

Os totais saem só do ledger (partidas dobradas) e das contestações, no horário de Brasília. O
fechamento grava esse retrato com um hash; depois dele:
- o registro não muda nem some (gatilho no banco; aqui, o repositório recusa gravar de novo);
- o ledger recusa lançamento com data dentro do mês fechado (gatilho no banco). Correção entra
  como estorno no mês corrente, que é como o ledger já funciona;
- a tela recalcula o mês e compara com o retrato: se algo diferente aparecer, ela avisa.

O custo de cupom ainda não entra: o pedido não guarda desconto (decisão "quem paga o cupom" foi
tomada, falta a coluna). Centavos inteiros.
"""

from __future__ import annotations

import hashlib
import json
from collections.abc import Iterable, Sequence
from dataclasses import asdict, dataclass
from datetime import datetime
from typing import Protocol

from trato.financeiro import periodo
from trato.financeiro.contestacoes import Contestacao, StatusContestacao
from trato.financeiro.ledger import Lancamento, TipoConta, TipoLancamento


@dataclass(frozen=True)
class TotaisMes:
    mes: str  # AAAA-MM
    cobrancas: int  # quantas cobranças entraram
    cobrado_centavos: int  # o que entrou de clientes (bruto)
    devolvido_centavos: int  # estornos e contestações perdidas, líquidos do que foi relançado
    entrada_liquida_centavos: int  # cobrado menos devolvido
    receita_taxas_centavos: int  # movimento da conta de taxa do Trato no mês
    liberado_profissionais_centavos: int  # o que passou de "a liberar" para "liberado"
    pago_profissionais_centavos: int  # o que saiu para a conta do profissional
    retido_fim_centavos: int  # saldos acumulados no último instante do mês
    a_liberar_fim_centavos: int
    liberado_fim_centavos: int
    contestacoes_perdidas: int
    contestacoes_perdidas_centavos: int
    lancamentos: int


@dataclass(frozen=True)
class Fechamento:
    mes: str
    totais: dict
    hash: str
    fechado_por: str
    fechado_em: datetime
    motivo: str


class MesJaFechado(Exception):
    pass


def _movimento(itens: Iterable[Lancamento], tipo: TipoConta) -> int:
    """Créditos menos débitos das contas desse tipo (de todos os titulares)."""
    total = 0
    for item in itens:
        if item.credito.tipo is tipo:
            total += item.valor
        if item.debito.tipo is tipo:
            total -= item.valor
    return total


def calcular(
    lancamentos: Sequence[Lancamento], contestacoes: Sequence[Contestacao], ano: int, mes: int
) -> TotaisMes:
    inicio, fim = periodo.mes(ano, mes)
    do_mes = [i for i in lancamentos if inicio <= i.data < fim]
    ate_o_fim = [i for i in lancamentos if i.data < fim]
    cobrancas = [
        i
        for i in do_mes
        if i.tipo is TipoLancamento.COBRANCA
        and i.debito.tipo is TipoConta.CLIENTE_EXTERNO
        and "/mantida/" not in i.chave
    ]
    cobrado = sum(i.valor for i in cobrancas)
    entrada = -_movimento(do_mes, TipoConta.CLIENTE_EXTERNO)
    liberacoes = sum(
        i.valor
        for i in do_mes
        if i.tipo is TipoLancamento.REPASSE and i.credito.tipo is TipoConta.LIBERADO
    )
    perdidas = [
        c
        for c in contestacoes
        if c.status is StatusContestacao.PERDIDA
        and c.encerrada_em is not None
        and inicio <= c.encerrada_em < fim
    ]
    return TotaisMes(
        mes=f"{ano:04d}-{mes:02d}",
        cobrancas=len(cobrancas),
        cobrado_centavos=cobrado,
        devolvido_centavos=cobrado - entrada,
        entrada_liquida_centavos=entrada,
        receita_taxas_centavos=_movimento(do_mes, TipoConta.TAXA_TRATO),
        liberado_profissionais_centavos=liberacoes,
        pago_profissionais_centavos=_movimento(do_mes, TipoConta.PROFISSIONAL_EXTERNO),
        retido_fim_centavos=_movimento(ate_o_fim, TipoConta.CUSTODIA),
        a_liberar_fim_centavos=_movimento(ate_o_fim, TipoConta.A_LIBERAR),
        liberado_fim_centavos=_movimento(ate_o_fim, TipoConta.LIBERADO),
        contestacoes_perdidas=len(perdidas),
        contestacoes_perdidas_centavos=sum(c.valor_centavos for c in perdidas),
        lancamentos=len(do_mes),
    )


def hash_dos_totais(totais: dict) -> str:
    texto = json.dumps(totais, sort_keys=True, separators=(",", ":"), ensure_ascii=False)
    return hashlib.sha256(texto.encode("utf-8")).hexdigest()


def montar(totais: TotaisMes, operador_id: str, agora: datetime, motivo: str) -> Fechamento:
    dados = asdict(totais)
    return Fechamento(totais.mes, dados, hash_dos_totais(dados), operador_id, agora, motivo)


def pode_fechar(ano: int, mes: int, agora: datetime) -> bool:
    """Só mês que já terminou (no horário de Brasília)."""
    return periodo.mes(ano, mes)[1] <= agora


class RepositorioFechamentos(Protocol):
    def obter(self, mes: str) -> Fechamento | None: ...

    def gravar(self, fechamento: Fechamento) -> None:
        """Grava uma vez só. Mês já fechado: `MesJaFechado`."""

    def listar(self) -> Sequence[Fechamento]:
        """Do mais recente para o mais antigo."""


class FechamentosEmMemoria:
    def __init__(self) -> None:
        self._itens: dict[str, Fechamento] = {}

    def obter(self, mes: str) -> Fechamento | None:
        return self._itens.get(mes)

    def gravar(self, fechamento: Fechamento) -> None:
        if fechamento.mes in self._itens:
            raise MesJaFechado(fechamento.mes)
        self._itens[fechamento.mes] = fechamento

    def listar(self) -> Sequence[Fechamento]:
        return tuple(sorted(self._itens.values(), key=lambda f: f.mes, reverse=True))
