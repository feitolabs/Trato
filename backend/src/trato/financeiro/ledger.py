"""Ledger de partidas dobradas (escopo, seções 8 e 11.2).

- Valores em centavos inteiros (`int`). Nunca `float`. Valor <= 0 é recusado.
- `Lancamento` é imutável. O `Livro` só aceita inclusão: não há editar nem apagar.
  Correção só por lançamento de ESTORNO que aponta para o original.
- Cada lançamento debita uma conta e credita outra pelo mesmo valor.
- Idempotência: a mesma chave com os mesmos dados devolve o lançamento já gravado;
  a mesma chave com dados diferentes é erro.
- Saldos nunca são guardados: saem sempre da soma dos lançamentos.
  Convenção: saldo = créditos - débitos ("saldo credor").
- Sem banco, sem Stripe, sem HTTP. A taxa chega já calculada (F4.2); o prazo de
  liberação fica na rotina (F4.9). Aqui só se registra.

Os tipos são os do CHECK de `lancamentos.tipo` do banco (F3.5); o banco ainda aceita
`custo_stripe` e `reembolso`, que o Python não lança. O que muda entre dois lançamentos do mesmo
tipo é o par de contas (tipo: débito -> crédito):
    COBRANCA    cliente (externo) -> custódia          cliente pagou, valor retido
    COBRANCA    cliente (externo) -> liberado          gorjeta: 100% do profissional, sem taxa
    RETENCAO    custódia -> a liberar (profissional)   parte do profissional, ao concluir
    TAXA        custódia -> taxa do Trato              parte do Trato, ao concluir
    REPASSE     a liberar -> liberado (profissional)   liberação: passou o prazo / cliente confirmou
    REPASSE     liberado -> profissional (externo)     o provedor pagou o profissional
    ESTORNO     inverte EXATAMENTE as partidas de um lançamento (o banco confere isso)

O banco só aceita estorno do lançamento INTEIRO, e um único estorno por original. Por isso o
estorno parcial do pedido (`estornar_pedido`) estorna os originais por inteiro e lança de novo,
como lançamentos novos, a parte que o cliente NÃO recebeu de volta. O cliente recebe V e o
resto volta a ficar onde estava (custódia, parte do profissional e taxa), em proporção ao que
cada uma tem. O arredondamento é determinístico: cada parte recebe o piso de V*peso/total; os
centavos que sobram vão, um a um, para a parte com maior resto (empate: custódia, depois
profissional, depois taxa). A soma das partes é exatamente V.
"""

from __future__ import annotations

import uuid
from collections.abc import Iterable, Sequence
from dataclasses import dataclass, field
from datetime import datetime
from enum import StrEnum


class TipoConta(StrEnum):
    CLIENTE_EXTERNO = "cliente_externo"  # dinheiro que entra pelo parceiro de pagamento
    PROFISSIONAL_EXTERNO = "profissional_externo"  # dinheiro que sai por saque
    CUSTODIA = "custodia"  # retido
    A_LIBERAR = "a_liberar"  # do profissional, ainda não liberado
    LIBERADO = "liberado"  # do profissional, disponível para saque
    TAXA_TRATO = "taxa_trato"


_EXTERNAS = frozenset({TipoConta.CLIENTE_EXTERNO, TipoConta.PROFISSIONAL_EXTERNO})
_COM_TITULAR = frozenset({TipoConta.A_LIBERAR, TipoConta.LIBERADO})


class TipoLancamento(StrEnum):
    COBRANCA = "cobranca"
    RETENCAO = "retencao"
    TAXA = "taxa"
    REPASSE = "repasse"
    ESTORNO = "estorno"


# tipo -> pares (conta debitada, conta creditada) válidos. ESTORNO é validado contra o original.
_CONTAS_DO_TIPO = {
    TipoLancamento.COBRANCA: (
        (TipoConta.CLIENTE_EXTERNO, TipoConta.CUSTODIA),
        (TipoConta.CLIENTE_EXTERNO, TipoConta.LIBERADO),  # gorjeta
    ),
    TipoLancamento.RETENCAO: ((TipoConta.CUSTODIA, TipoConta.A_LIBERAR),),
    TipoLancamento.TAXA: ((TipoConta.CUSTODIA, TipoConta.TAXA_TRATO),),
    TipoLancamento.REPASSE: (
        (TipoConta.A_LIBERAR, TipoConta.LIBERADO),  # liberação
        (TipoConta.LIBERADO, TipoConta.PROFISSIONAL_EXTERNO),  # pagamento ao profissional
    ),
}


class LedgerErro(Exception):
    """Base dos erros do ledger."""


class LancamentoInvalido(LedgerErro):
    pass


class ChaveReutilizada(LedgerErro):
    """A mesma chave de idempotência chegou com dados diferentes."""


class SaldoInsuficiente(LedgerErro):
    pass


class EstornoInvalido(LedgerErro):
    pass


class LivroDesbalanceado(LedgerErro):
    pass


@dataclass(frozen=True)
class Conta:
    tipo: TipoConta
    titular: str | None = None  # id do profissional nas contas dele

    def __post_init__(self) -> None:
        if (self.tipo in _COM_TITULAR) != (self.titular is not None):
            raise LancamentoInvalido(f"Conta {self.tipo.value}: titular incorreto.")


CLIENTE = Conta(TipoConta.CLIENTE_EXTERNO)
CUSTODIA = Conta(TipoConta.CUSTODIA)
TAXA_TRATO = Conta(TipoConta.TAXA_TRATO)
PROFISSIONAL_EXTERNO = Conta(TipoConta.PROFISSIONAL_EXTERNO)


def a_liberar(profissional_id: str) -> Conta:
    return Conta(TipoConta.A_LIBERAR, profissional_id)


def liberado(profissional_id: str) -> Conta:
    return Conta(TipoConta.LIBERADO, profissional_id)


@dataclass(frozen=True)
class Lancamento:
    chave: str  # chave de idempotência
    pedido_id: str
    tipo: TipoLancamento
    debito: Conta
    credito: Conta
    valor: int  # centavos
    data: datetime
    estorno_de: str | None = None  # id do lançamento original (só em ESTORNO)
    id: str = field(default_factory=lambda: uuid.uuid4().hex)
    # Evento assinado do provedor que originou o lançamento (espelho). Fora da conferência de
    # reenvio: o mesmo lançamento pode chegar por outro caminho.
    evento_webhook_id: str | None = None

    def __post_init__(self) -> None:
        if isinstance(self.valor, bool) or not isinstance(self.valor, int):
            raise LancamentoInvalido("O valor deve ser inteiro, em centavos.")
        if self.valor <= 0:
            raise LancamentoInvalido("O valor deve ser maior que zero.")
        if not self.chave.strip() or not self.pedido_id.strip():
            raise LancamentoInvalido("Chave e pedido são obrigatórios.")
        if self.data.tzinfo is None:
            raise LancamentoInvalido("A data precisa ter fuso horário.")
        if self.debito == self.credito:
            raise LancamentoInvalido("Débito e crédito não podem ser a mesma conta.")
        if self.tipo is TipoLancamento.ESTORNO:
            if not self.estorno_de:
                raise LancamentoInvalido("Estorno precisa apontar para o lançamento original.")
        else:
            if self.estorno_de is not None:
                raise LancamentoInvalido("Só estorno aponta para um lançamento original.")
            if (self.debito.tipo, self.credito.tipo) not in _CONTAS_DO_TIPO[self.tipo]:
                raise LancamentoInvalido(
                    f"Contas incompatíveis com o tipo {self.tipo.value}: "
                    f"{self.debito.tipo.value} -> {self.credito.tipo.value}."
                )

    def _conteudo(self) -> tuple:
        # Reenvio pode trazer outra data e outro id; o que vale é o conteúdo.
        return (self.pedido_id, self.tipo, self.debito, self.credito, self.valor, self.estorno_de)


@dataclass(frozen=True)
class SaldoPedido:
    cliente_pagou: int  # cobrado menos estornado (inclui gorjeta)
    retido: int
    a_liberar: int
    liberado: int
    taxa_trato: int


def _saldo(itens: Iterable[Lancamento], conta: Conta, pedido_id: str | None = None) -> int:
    total = 0
    for item in itens:
        if pedido_id is not None and item.pedido_id != pedido_id:
            continue
        if item.credito == conta:
            total += item.valor
        if item.debito == conta:
            total -= item.valor
    return total


def _ja_estornado(itens: Iterable[Lancamento], original_id: str) -> int:
    return sum(i.valor for i in itens if i.estorno_de == original_id)


def _validar(itens: Sequence[Lancamento], novo: Lancamento) -> None:
    if novo.tipo is TipoLancamento.ESTORNO:
        original = next((i for i in itens if i.id == novo.estorno_de), None)
        if original is None:
            raise EstornoInvalido("O lançamento original do estorno não existe.")
        if original.tipo is TipoLancamento.ESTORNO:
            raise EstornoInvalido("Não se estorna um estorno.")
        if original.pedido_id != novo.pedido_id:
            raise EstornoInvalido("O estorno precisa ser do mesmo pedido do original.")
        if (novo.debito, novo.credito) != (original.credito, original.debito):
            raise EstornoInvalido("O estorno precisa inverter débito e crédito do original.")
        if _ja_estornado(itens, original.id):
            raise EstornoInvalido("Este lançamento já foi estornado.")
        if novo.valor != original.valor:
            raise EstornoInvalido(
                f"O estorno inverte o lançamento inteiro ({original.valor} centavos)."
            )
    if novo.debito.tipo not in _EXTERNAS:
        disponivel = _saldo(itens, novo.debito, novo.pedido_id)
        if disponivel < novo.valor:
            raise SaldoInsuficiente(
                f"Saldo insuficiente em {novo.debito.tipo.value}: "
                f"tem {disponivel} centavos, precisa de {novo.valor}."
            )


class Livro:
    """Livro-razão só de inclusão."""

    def __init__(self) -> None:
        self._itens: list[Lancamento] = []
        self._por_chave: dict[str, Lancamento] = {}

    @property
    def lancamentos(self) -> tuple[Lancamento, ...]:
        return tuple(self._itens)

    def lancar(self, lancamento: Lancamento) -> Lancamento:
        return self.lancar_varios([lancamento])[0]

    def lancar_varios(self, lancamentos: Iterable[Lancamento]) -> tuple[Lancamento, ...]:
        """Grava todos ou nenhum. Reenvio de chave já gravada devolve o lançamento antigo."""
        itens = list(self._itens)
        por_chave = dict(self._por_chave)
        resultado = []
        for novo in lancamentos:
            existente = por_chave.get(novo.chave)
            if existente is not None:
                if existente._conteudo() != novo._conteudo():
                    raise ChaveReutilizada(f"A chave {novo.chave!r} já foi usada com outros dados.")
                resultado.append(existente)
                continue
            _validar(itens, novo)
            itens.append(novo)
            por_chave[novo.chave] = novo
            resultado.append(novo)
        self._itens = itens
        self._por_chave = por_chave
        return tuple(resultado)

    def saldo(self, conta: Conta, pedido_id: str | None = None) -> int:
        return _saldo(self._itens, conta, pedido_id)

    def saldos_pedido(self, pedido_id: str, profissional_id: str | None = None) -> SaldoPedido:
        """Saldos do pedido. As contas do profissional só entram se ele for informado."""
        prof = profissional_id
        return SaldoPedido(
            cliente_pagou=-self.saldo(CLIENTE, pedido_id),
            retido=self.saldo(CUSTODIA, pedido_id),
            a_liberar=self.saldo(a_liberar(prof), pedido_id) if prof else 0,
            liberado=self.saldo(liberado(prof), pedido_id) if prof else 0,
            taxa_trato=self.saldo(TAXA_TRATO, pedido_id),
        )

    def total_debitos(self) -> int:
        return sum(sum(i.valor for i in self._itens if i.debito == c) for c in self._contas())

    def total_creditos(self) -> int:
        return sum(sum(i.valor for i in self._itens if i.credito == c) for c in self._contas())

    def verificar_partidas(self) -> None:
        """Débitos e créditos somados por conta precisam fechar, e os saldos somar zero."""
        soma_saldos = sum(self.saldo(c) for c in self._contas())
        if self.total_debitos() != self.total_creditos() or soma_saldos != 0:
            raise LivroDesbalanceado("Débitos e créditos não fecham.")

    def _contas(self) -> set[Conta]:
        return {c for i in self._itens for c in (i.debito, i.credito)}


# --- Operações do fluxo ---------------------------------------------------------------


def registrar_cobranca(
    livro: Livro,
    pedido_id: str,
    valor: int,
    chave: str,
    data: datetime,
    evento_webhook_id: str | None = None,
) -> Lancamento:
    """Cliente pagou (confirmação do parceiro): o valor entra retido."""
    return livro.lancar(
        Lancamento(
            chave,
            pedido_id,
            TipoLancamento.COBRANCA,
            CLIENTE,
            CUSTODIA,
            valor,
            data,
            evento_webhook_id=evento_webhook_id,
        )
    )


def registrar_gorjeta(
    livro: Livro, pedido_id: str, profissional_id: str, valor: int, chave: str, data: datetime
) -> Lancamento:
    """Gorjeta: 100% do profissional, sem taxa."""
    return livro.lancar(
        Lancamento(
            chave,
            pedido_id,
            TipoLancamento.COBRANCA,
            CLIENTE,
            liberado(profissional_id),
            valor,
            data,
        )
    )


def repartir_custodia(
    livro: Livro,
    pedido_id: str,
    profissional_id: str,
    taxa: int,
    chave: str,
    data: datetime,
    valor: int | None = None,
) -> tuple[Lancamento, ...]:
    """Ao concluir: divide a custódia entre taxa do Trato e parte do profissional.

    `taxa` já vem calculada (F4.2). `valor` é a parte da custódia a repartir (uma etapa,
    por exemplo); sem ele, reparte toda a custódia do pedido.
    """
    base = livro.saldo(CUSTODIA, pedido_id) if valor is None else valor
    if base <= 0:
        raise LancamentoInvalido("Não há valor retido para repartir.")
    if isinstance(taxa, bool) or not isinstance(taxa, int) or not 0 <= taxa <= base:
        raise LancamentoInvalido("A taxa deve ser inteira, de zero até o valor repartido.")
    novos = []
    if base - taxa > 0:
        novos.append(
            Lancamento(
                f"{chave}/retencao",
                pedido_id,
                TipoLancamento.RETENCAO,
                CUSTODIA,
                a_liberar(profissional_id),
                base - taxa,
                data,
            )
        )
    if taxa > 0:
        novos.append(
            Lancamento(
                f"{chave}/taxa", pedido_id, TipoLancamento.TAXA, CUSTODIA, TAXA_TRATO, taxa, data
            )
        )
    return livro.lancar_varios(novos)


def liberar(
    livro: Livro,
    pedido_id: str,
    profissional_id: str,
    chave: str,
    data: datetime,
    valor: int | None = None,
    evento_webhook_id: str | None = None,
) -> Lancamento:
    """Passa o valor de 'a liberar' para 'liberado'. Quando liberar é decisão da rotina."""
    conta = a_liberar(profissional_id)
    montante = livro.saldo(conta, pedido_id) if valor is None else valor
    return livro.lancar(
        Lancamento(
            chave, pedido_id, TipoLancamento.REPASSE, conta, liberado(profissional_id),
            montante, data, evento_webhook_id=evento_webhook_id,
        )
    )  # fmt: skip


def registrar_repasse(
    livro: Livro, pedido_id: str, profissional_id: str, valor: int, chave: str, data: datetime
) -> Lancamento:
    """Saque do valor liberado (a saída real do dinheiro é da integração com o parceiro)."""
    return livro.lancar(
        Lancamento(
            chave,
            pedido_id,
            TipoLancamento.REPASSE,
            liberado(profissional_id),
            PROFISSIONAL_EXTERNO,
            valor,
            data,
        )
    )


# --- Estorno --------------------------------------------------------------------------


def estornar(
    livro: Livro,
    original_id: str,
    chave: str,
    data: datetime,
    evento_webhook_id: str | None = None,
) -> Lancamento:
    """Estorna um lançamento por inteiro: inverte exatamente as partidas dele (uma só vez)."""
    original = next((i for i in livro.lancamentos if i.id == original_id), None)
    if original is None:
        raise EstornoInvalido("O lançamento original do estorno não existe.")
    return livro.lancar(_estorno_de(original, chave, data, evento_webhook_id))


def _estorno_de(
    original: Lancamento, chave: str, data: datetime, evento_webhook_id: str | None = None
) -> Lancamento:
    return Lancamento(
        chave,
        original.pedido_id,
        TipoLancamento.ESTORNO,
        original.credito,
        original.debito,
        original.valor,
        data,
        estorno_de=original.id,
        evento_webhook_id=evento_webhook_id,
    )


def repartir_proporcional(total: int, pesos: Sequence[int]) -> list[int]:
    """Divide `total` na proporção dos `pesos`, sem perder nem criar centavo.

    Piso de total*peso/soma para cada um; os centavos que faltam vão, um a um, para o
    maior resto (empate: o primeiro da lista).
    """
    soma = sum(pesos)
    if soma <= 0 or not 0 <= total <= soma:
        raise ValueError("Total fora do que os pesos comportam.")
    partes = [total * p // soma for p in pesos]
    restos = [total * p % soma for p in pesos]
    ordem = sorted(range(len(pesos)), key=lambda i: (-restos[i], i))
    for i in ordem[: total - sum(partes)]:
        partes[i] += 1
    return partes


def _em_aberto(
    livro: Livro, pedido_id: str, tipo: TipoLancamento, credito: TipoConta | None
) -> list[Lancamento]:
    """Originais do tipo ainda sem estorno, do mais antigo ao mais novo."""
    return [
        i
        for i in livro.lancamentos
        if i.pedido_id == pedido_id
        and i.tipo is tipo
        and (credito is None or i.credito.tipo is credito)
        and not _ja_estornado(livro.lancamentos, i.id)
    ]


def estornar_pedido(
    livro: Livro,
    pedido_id: str,
    valor: int,
    chave: str,
    data: datetime,
    evento_webhook_id: str | None = None,
) -> tuple[Lancamento, ...]:
    """Devolve `valor` ao cliente (parcial ou total), proporcional entre taxa e profissional.

    Estorna por INTEIRO os lançamentos em aberto de TAXA, RETENCAO e COBRANCA (a que foi para a
    custódia; a gorjeta não entra) e, se o valor for parcial, lança de novo (COBRANCA, RETENCAO e
    TAXA novas, chaves `<chave>/mantida/...`) a parte que o cliente NÃO recebeu. Grava tudo ou
    nada e devolve só os estornos. Se parte do valor já foi liberada ou paga ao profissional,
    falta saldo e o ledger recusa com `SaldoInsuficiente` (regra pendente, ver F4.8).
    """
    ja_feitos = [i for i in livro.lancamentos if i.chave.startswith(f"{chave}/")]
    if ja_feitos:  # reenvio da mesma operação: devolve o que já foi gravado
        return tuple(i for i in ja_feitos if i.tipo is TipoLancamento.ESTORNO)
    cobrancas = _em_aberto(livro, pedido_id, TipoLancamento.COBRANCA, TipoConta.CUSTODIA)
    retencoes = _em_aberto(livro, pedido_id, TipoLancamento.RETENCAO, None)
    taxas = _em_aberto(livro, pedido_id, TipoLancamento.TAXA, None)
    cobrado = sum(i.valor for i in cobrancas)
    if isinstance(valor, bool) or not isinstance(valor, int) or not 0 < valor <= cobrado:
        raise EstornoInvalido(f"O valor do estorno deve ficar entre 1 e {cobrado} centavos.")
    pesos = [
        livro.saldo(CUSTODIA, pedido_id),
        sum(i.valor for i in retencoes),
        sum(i.valor for i in taxas),
    ]
    devolvidos = repartir_proporcional(valor, pesos)
    mantido = cobrado - valor

    estornos = [
        _estorno_de(i, f"{chave}/{i.tipo.value}/{i.id}", data, evento_webhook_id)
        for i in (*taxas, *retencoes, *cobrancas)
    ]
    novos = list(estornos)
    if mantido:
        profissional = retencoes[0].credito.titular if retencoes else None
        mantidos = (
            (TipoLancamento.COBRANCA, CLIENTE, CUSTODIA, mantido),
            (
                TipoLancamento.RETENCAO,
                CUSTODIA,
                a_liberar(profissional) if profissional else None,
                pesos[1] - devolvidos[1],
            ),
            (TipoLancamento.TAXA, CUSTODIA, TAXA_TRATO, pesos[2] - devolvidos[2]),
        )
        for tipo, conta_debito, conta_credito, quanto in mantidos:
            if quanto > 0 and conta_credito is not None:
                novos.append(
                    Lancamento(
                        f"{chave}/mantida/{tipo.value}",
                        pedido_id,
                        tipo,
                        conta_debito,
                        conta_credito,
                        quanto,
                        data,
                        evento_webhook_id=evento_webhook_id,
                    )
                )
    livro.lancar_varios(novos)
    return tuple(estornos)
