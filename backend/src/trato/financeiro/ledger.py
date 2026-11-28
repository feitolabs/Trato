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
    COBRANCA    cliente (externo) -> custódia          cliente pagou o serviço (+ parcelamento)
    TAXA        custódia -> taxa do Trato              na conclusão: a taxa é descontada do
                                                       profissional antes de creditar a carteira
                                                       (decisão do João de 10/11/2026). Na
                                                       confirmação do pagamento, só o custo de
                                                       parcelamento sai (chave `.../parcelamento`)
    COBRANCA    cliente (externo) -> liberado          gorjeta: 100% do profissional, sem taxa
    RETENCAO    custódia -> a liberar (profissional)   serviço menos a taxa, ao concluir
    REPASSE     a liberar -> liberado (profissional)   liberação: passou o prazo / cliente confirmou
    REPASSE     liberado -> profissional (externo)     o provedor pagou o profissional
    ESTORNO     inverte EXATAMENTE as partidas de um lançamento (o banco confere isso)

O reembolso devolve o serviço inteiro, inclusive a taxa já descontada, proporcionalmente ao valor
devolvido. Só o custo de parcelamento NÃO volta (o provedor não devolve).

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
    # Dívida do profissional por reembolso decidido depois do repasse (Termos 8.6 e 17.4).
    A_COMPENSAR = "a_compensar"


SUFIXO_PARCELAMENTO = "/parcelamento"  # chave do lançamento TAXA que é custo de parcelamento
# chave do lançamento REEMBOLSO que devolve parte do custo de parcelamento (6.9, já liberado)
SUFIXO_CUSTO_DEVOLVIDO = "/custo-devolvido"

_EXTERNAS = frozenset({TipoConta.CLIENTE_EXTERNO, TipoConta.PROFISSIONAL_EXTERNO})
_COM_TITULAR = frozenset({TipoConta.A_LIBERAR, TipoConta.LIBERADO, TipoConta.A_COMPENSAR})
# Podem ficar com saldo negativo: a dívida nasce devedora e o Trato pode assumir uma.
_SEM_EXIGIR_SALDO = frozenset({TipoConta.A_COMPENSAR, TipoConta.TAXA_TRATO})


class TipoLancamento(StrEnum):
    COBRANCA = "cobranca"
    RETENCAO = "retencao"
    TAXA = "taxa"
    REPASSE = "repasse"
    ESTORNO = "estorno"
    REEMBOLSO = "reembolso"  # lançado pelas funções de compensação do banco


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
        (TipoConta.LIBERADO, TipoConta.A_COMPENSAR),  # compensação no repasse
    ),
    TipoLancamento.REEMBOLSO: (
        (TipoConta.A_COMPENSAR, TipoConta.CLIENTE_EXTERNO),  # dívida: o cliente recebe de volta
        (TipoConta.TAXA_TRATO, TipoConta.A_COMPENSAR),  # contestação aceita: o Trato assume
    ),
}


# Com parte já liberada, o livro não permite estornar a cobrança inteira: o saldo ainda retido
# e o custo do parcelamento saem em REEMBOLSO direto para o cliente. Cada par só vale no
# lançamento cuja chave termina no sufixo da própria conta.
SUFIXO_RETIDO_CUSTODIA = "/retido/custodia"
SUFIXO_RETIDO_A_LIBERAR = "/retido/a-liberar"


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


def a_compensar(profissional_id: str) -> Conta:
    return Conta(TipoConta.A_COMPENSAR, profissional_id)


def a_liberar(profissional_id: str) -> Conta:
    return Conta(TipoConta.A_LIBERAR, profissional_id)


def liberado(profissional_id: str) -> Conta:
    return Conta(TipoConta.LIBERADO, profissional_id)


# Teto de um lançamento: cabe com folga no bigint do Postgres (9,22e18) mesmo somando saldos.
VALOR_MAXIMO_CENTAVOS = 9_000_000_000_000_000


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
        if self.valor > VALOR_MAXIMO_CENTAVOS:
            raise LancamentoInvalido(
                f"O valor passa do máximo de {VALOR_MAXIMO_CENTAVOS} centavos por lançamento."
            )
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
            pares = _CONTAS_DO_TIPO[self.tipo]
            if self.tipo is TipoLancamento.REEMBOLSO:
                pares += tuple(
                    (conta, TipoConta.CLIENTE_EXTERNO)
                    for sufixo, conta in (
                        (SUFIXO_RETIDO_CUSTODIA, TipoConta.CUSTODIA),
                        (SUFIXO_RETIDO_A_LIBERAR, TipoConta.A_LIBERAR),
                        (SUFIXO_CUSTO_DEVOLVIDO, TipoConta.TAXA_TRATO),
                    )
                    if self.chave.endswith(sufixo)
                )
            if (self.debito.tipo, self.credito.tipo) not in pares:
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


def eh_custo_parcelamento(item: Lancamento) -> bool:
    """Lançamento TAXA que é o custo do parcelado (do cliente), e não a taxa do Trato."""
    return item.tipo is TipoLancamento.TAXA and item.chave.endswith(SUFIXO_PARCELAMENTO)


def taxa_descontada(lancamentos: Sequence[Lancamento], pedido_id: str) -> int:
    """Taxa do Trato já descontada do profissional neste pedido e ainda não devolvida."""
    return sum(
        i.valor
        for i in lancamentos
        if i.pedido_id == pedido_id
        and i.tipo is TipoLancamento.TAXA
        and not eh_custo_parcelamento(i)
        and not _ja_estornado(lancamentos, i.id)
    )


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
    if novo.debito.tipo not in _EXTERNAS and novo.debito.tipo not in _SEM_EXIGIR_SALDO:
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

    def da_chave(self, chave: str) -> Lancamento | None:
        """O lançamento já gravado com esta chave de idempotência, se houver."""
        return self._por_chave.get(chave)

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


def separar_custo_parcelamento(
    livro: Livro,
    pedido_id: str,
    valor: int,
    chave: str,
    data: datetime,
    evento_webhook_id: str | None = None,
) -> Lancamento:
    """Tira da custódia o custo de parcelamento repassado ao provedor.

    Roda logo depois do `registrar_cobranca`: o que fica retido é só o valor do serviço. `chave` é
    a base da operação; o sufixo marca o lançamento como custo, que não volta no reembolso.
    """
    return livro.lancar(
        Lancamento(
            f"{chave}{SUFIXO_PARCELAMENTO}",
            pedido_id,
            TipoLancamento.TAXA,
            CUSTODIA,
            TAXA_TRATO,
            valor,
            data,
            evento_webhook_id=evento_webhook_id,
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

    `taxa` é sempre 0 nos pedidos novos (o app é gratuito desde 18/11/2026); o parâmetro existe
    para o histórico e para os testes do estorno de pedidos antigos. `valor` é a parte da custódia
    a repartir (uma etapa, por exemplo); sem ele, reparte toda a custódia do pedido.
    """
    if valor is None:
        # Reenvio da mesma operação (a custódia já zerou): a base é o que ela repartiu da
        # primeira vez. Confere a chave ANTES de olhar o saldo; parâmetros diferentes seguem
        # sendo erro (`ChaveReutilizada`, na hora de lançar).
        antes = [livro.da_chave(f"{chave}/retencao"), livro.da_chave(f"{chave}/taxa")]
        gravados = [i for i in antes if i is not None]
        base = sum(i.valor for i in gravados) if gravados else livro.saldo(CUSTODIA, pedido_id)
    else:
        base = valor
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
    if valor is not None:
        montante = valor
    elif (anterior := livro.da_chave(chave)) is not None:
        montante = anterior.valor  # reenvio: o saldo já zerou, vale o que foi liberado antes
    else:
        montante = livro.saldo(conta, pedido_id)
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


# --- Estorno de material (Termos 6.9) -------------------------------------------------

PREFIXO_ESTORNO_MATERIAL = "nota-material/"


def ha_liberacao(livro: Livro, pedido_id: str) -> bool:
    """Alguma parte do serviço já passou de 'a liberar' para 'liberado' (e segue assim)."""
    return any(
        i.debito.tipo is TipoConta.A_LIBERAR
        for i in _em_aberto(livro, pedido_id, TipoLancamento.REPASSE, TipoConta.LIBERADO)
    )


def estornar_material(
    livro: Livro,
    pedido_id: str,
    profissional_id: str,
    retido: int,
    custo: int,
    chave: str,
    data: datetime,
) -> None:
    """Lança a devolução da parte ainda RETIDA (`retido`) e do custo do parcelamento
    proporcional ao total reconhecido (`custo`). A parte já liberada não passa por aqui: quem
    lança é a função de compensação do banco.

    Sem nada liberado, usa o estorno de sempre (os próximos cancelamentos, disputas e
    liberações continuam valendo). Com parte liberada, lança reembolsos diretos."""
    if not ha_liberacao(livro, pedido_id):
        if retido > 0:
            estornar_pedido(livro, pedido_id, retido, chave, data, custo_devolvido=custo)
        elif custo > 0:
            raise EstornoInvalido("Custo sem parte retida nem liberada para devolver.")
        return
    _reembolsar_direto(livro, pedido_id, profissional_id, retido, custo, chave, data)


def _reembolsar_direto(
    livro: Livro,
    pedido_id: str,
    profissional_id: str,
    retido: int,
    custo: int,
    chave: str,
    data: datetime,
    evento_webhook_id: str | None = None,
) -> tuple[Lancamento, ...]:
    """Devolve `retido` (da custódia, depois do 'a liberar') e `custo` do parcelamento. O que já
    foi liberado ao profissional não é tocado. Grava tudo ou nada."""
    conta_do_prof = a_liberar(profissional_id)
    na_custodia = min(retido, max(livro.saldo(CUSTODIA, pedido_id), 0))
    if retido - na_custodia > max(livro.saldo(conta_do_prof, pedido_id), 0):
        raise EstornoInvalido("O valor passa do que ainda está retido (sem o que já foi liberado).")
    if custo > max(custo_parcelamento_em_aberto(livro, pedido_id), 0):
        raise EstornoInvalido("O custo a devolver passa do custo ainda não devolvido.")
    saidas = (
        (SUFIXO_RETIDO_CUSTODIA, CUSTODIA, na_custodia),
        (SUFIXO_RETIDO_A_LIBERAR, conta_do_prof, retido - na_custodia),
        (SUFIXO_CUSTO_DEVOLVIDO, TAXA_TRATO, custo),
    )
    return livro.lancar_varios(
        [
            Lancamento(
                f"{chave}{sufixo}",
                pedido_id,
                TipoLancamento.REEMBOLSO,
                conta,
                CLIENTE,
                valor,
                data,
                evento_webhook_id=evento_webhook_id,
            )
            for sufixo, conta, valor in saidas
            if valor > 0
        ]
    )


def reembolso_retido_direto(
    lancamentos: Sequence[Lancamento], pedido_id: str, desde: datetime
) -> int:
    """Saldo retido devolvido por REEMBOLSO direto desde `desde`, fora o estorno de material.
    As funções de compensação do banco ainda não contam esses lançamentos como devolvidos."""
    return sum(
        i.valor
        for i in lancamentos
        if i.pedido_id == pedido_id
        and i.tipo is TipoLancamento.REEMBOLSO
        and i.chave.endswith((SUFIXO_RETIDO_CUSTODIA, SUFIXO_RETIDO_A_LIBERAR))
        and not i.chave.startswith(PREFIXO_ESTORNO_MATERIAL)
        and i.data >= desde
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


def custo_parcelamento_em_aberto(livro: Livro, pedido_id: str) -> int:
    """Custo de parcelamento do pedido que ainda não voltou ao cliente."""
    taxas = _em_aberto(livro, pedido_id, TipoLancamento.TAXA, None)
    devolvido = sum(
        i.valor
        for i in _em_aberto(livro, pedido_id, TipoLancamento.REEMBOLSO, None)
        if i.chave.endswith(SUFIXO_CUSTO_DEVOLVIDO)
    )
    return sum(i.valor for i in taxas if eh_custo_parcelamento(i)) - devolvido


def reembolso_total_com_custo(
    lancamentos: Sequence[Lancamento], pedido_id: str, profissional_id: str | None
) -> int | None:
    """Num reembolso TOTAL, tudo o que o cliente pagou e ainda não voltou, com o custo do
    parcelamento (Termos 6.10: devolve o valor pago). `None` quando não há custo a devolver ou
    quando algo já foi liberado ao profissional: aí vale a divisão decidida, como antes."""
    livro = Livro()
    if lancamentos:
        livro.lancar_varios(list(lancamentos))
    if custo_parcelamento_em_aberto(livro, pedido_id) <= 0:
        return None
    if profissional_id and (
        livro.saldo(liberado(profissional_id), pedido_id) != 0
        or ha_liberacao(livro, pedido_id)  # inclusive o liberado que já foi pago
    ):
        return None
    abertas = _em_aberto(livro, pedido_id, TipoLancamento.COBRANCA, TipoConta.CUSTODIA)
    return sum(i.valor for i in abertas)


def estornar_pedido(
    livro: Livro,
    pedido_id: str,
    valor: int,
    chave: str,
    data: datetime,
    evento_webhook_id: str | None = None,
    incluir_custo: bool = False,
    custo_devolvido: int | None = None,
) -> tuple[Lancamento, ...]:
    """Devolve `valor` ao cliente (parcial ou total) a partir do valor do SERVIÇO.

    `incluir_custo` (cancelamentos, ausência e reembolso total por disputa; Termos 6.10, 7.2,
    7.4, 7.6 e 7.7): o custo do parcelamento também volta. `valor` pode ir até tudo o que foi
    cobrado; num valor parcial (retenção do 7.4) o que fica é só a retenção.

    `valor` pode ir até o que foi cobrado menos o custo de parcelamento, que não volta. A divisão é
    proporcional entre custódia, parte do profissional e taxa já descontada: se o cliente recebe
    tudo de volta, o Trato não fica com taxa.

    Estorna por INTEIRO os lançamentos em aberto de TAXA, RETENCAO e COBRANCA (a que foi para a
    custódia; a gorjeta não entra) e, se o valor for parcial, lança de novo (COBRANCA, RETENCAO e
    TAXA novas, chaves `<chave>/mantida/...`) a parte que o cliente NÃO recebeu. Grava tudo ou
    nada e devolve só os estornos.

    Se parte já foi liberada ao profissional (paga ou não), nada é estornado por inteiro: sai
    REEMBOLSO direto, limitado à custódia mais o 'a liberar' (mais o custo, quando devolvido),
    e devolve os lançamentos feitos. O liberado não é tocado.

    `custo_devolvido` (6.9): devolve exatamente essa parte do custo do parcelamento, além de
    `valor` do serviço, e mantém o resto do custo no livro.
    """
    ja_feitos = [i for i in livro.lancamentos if i.chave.startswith(f"{chave}/")]
    if ja_feitos:  # reenvio da mesma operação: devolve o que já foi gravado
        return tuple(
            i for i in ja_feitos if i.tipo in (TipoLancamento.ESTORNO, TipoLancamento.REEMBOLSO)
        )
    if ha_liberacao(livro, pedido_id):
        profissional = next(
            i.debito.titular
            for i in livro.lancamentos
            if i.pedido_id == pedido_id
            and i.tipo is TipoLancamento.REPASSE
            and i.debito.tipo is TipoConta.A_LIBERAR
        )
        retido = max(livro.saldo(CUSTODIA, pedido_id), 0) + max(
            livro.saldo(a_liberar(profissional), pedido_id), 0
        )
        custo = max(custo_parcelamento_em_aberto(livro, pedido_id), 0)
        if custo_devolvido is not None:
            if incluir_custo or not 0 <= custo_devolvido <= custo:
                raise EstornoInvalido("Custo do parcelamento a devolver fora do que foi cobrado.")
        maximo = retido + (custo if incluir_custo else 0)
        if isinstance(valor, bool) or not isinstance(valor, int) or valor <= 0:
            raise EstornoInvalido("O valor do estorno deve ser inteiro e maior que zero.")
        if valor > maximo:
            raise SaldoInsuficiente(
                f"Saldo retido insuficiente: dá para estornar até {maximo} centavos "
                "(o que já foi liberado ao profissional não é estornado)."
            )
        do_servico = min(valor, retido)
        return _reembolsar_direto(
            livro,
            pedido_id,
            profissional,
            do_servico,
            custo_devolvido if custo_devolvido is not None else valor - do_servico,
            chave,
            data,
            evento_webhook_id,
        )
    cobrancas = _em_aberto(livro, pedido_id, TipoLancamento.COBRANCA, TipoConta.CUSTODIA)
    retencoes = _em_aberto(livro, pedido_id, TipoLancamento.RETENCAO, None)
    taxas = _em_aberto(livro, pedido_id, TipoLancamento.TAXA, None)
    cobrado = sum(i.valor for i in cobrancas)
    custo_parcelamento = sum(i.valor for i in taxas if eh_custo_parcelamento(i))
    taxa_servico = sum(i.valor for i in taxas) - custo_parcelamento
    maximo = cobrado if incluir_custo else cobrado - custo_parcelamento
    if custo_devolvido is not None:
        if incluir_custo or not 0 <= custo_devolvido <= custo_parcelamento:
            raise EstornoInvalido("Custo do parcelamento a devolver fora do que foi cobrado.")
        maximo = cobrado - custo_parcelamento
    if isinstance(valor, bool) or not isinstance(valor, int) or not 0 < valor <= maximo:
        raise EstornoInvalido(
            f"O valor do estorno deve ficar entre 1 e {maximo} centavos "
            "(o custo do parcelamento não volta)."
        )
    pesos = [
        livro.saldo(CUSTODIA, pedido_id),
        sum(i.valor for i in retencoes),
        taxa_servico,
    ]
    mantido = cobrado - valor - (custo_devolvido or 0)
    custo_mantido = 0 if incluir_custo else custo_parcelamento - (custo_devolvido or 0)
    # Só a parte do serviço é repartida entre as contas; o que passar dela é custo do parcelado
    # (só possível com `incluir_custo`), que não pesa em nenhuma.
    devolvidos = repartir_proporcional(min(valor, sum(pesos)), pesos) if mantido else []

    estornos = [
        _estorno_de(i, f"{chave}/{i.tipo.value}/{i.id}", data, evento_webhook_id)
        for i in (*taxas, *retencoes, *cobrancas)
    ]
    novos = list(estornos)
    if mantido:
        profissional = retencoes[0].credito.titular if retencoes else None
        mantidos = (
            ("cobranca", TipoLancamento.COBRANCA, CLIENTE, CUSTODIA, mantido),
            (
                "retencao",
                TipoLancamento.RETENCAO,
                CUSTODIA,
                a_liberar(profissional) if profissional else None,
                pesos[1] - devolvidos[1],
            ),
            ("taxa", TipoLancamento.TAXA, CUSTODIA, TAXA_TRATO, taxa_servico - devolvidos[2]),
            (
                SUFIXO_PARCELAMENTO.removeprefix("/"),
                TipoLancamento.TAXA,
                CUSTODIA,
                TAXA_TRATO,
                # Devolvendo o custo, o que fica é só a retenção, inteira para o profissional.
                custo_mantido,
            ),
        )
        for nome, tipo, conta_debito, conta_credito, quanto in mantidos:
            if quanto > 0 and conta_credito is not None:
                novos.append(
                    Lancamento(
                        f"{chave}/mantida/{nome}",
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
