"""Extrato do profissional em PDF: o que ele recebeu num período (comprovante de renda).

Os números saem só do ledger espelho, nas contas do próprio profissional:
- recebido = o que passou de "a liberar" para "liberado" (o parceiro de pagamento confirmou);
- estorno = o que saiu do que ele JÁ tinha recebido (raro: o ledger recusa estornar o liberado);
- a liberar no fim = serviço concluído que ainda espera o prazo de liberação, já líquido de
  reembolsos. Um estorno parcial desfaz a parte "a liberar" inteira e relança o resto: contar o
  estorno bruto ali mostraria uma perda que o profissional não teve.

Datas no horário de Brasília. Centavos inteiros; o PDF mostra reais.
"""

from __future__ import annotations

from collections.abc import Mapping, Sequence
from dataclasses import dataclass
from datetime import datetime, timedelta

from trato.financeiro import periodo
from trato.financeiro.ledger import Lancamento, TipoConta, TipoLancamento
from trato.financeiro.pdf import LARGURA, PdfSimples


@dataclass(frozen=True)
class LinhaExtrato:
    data: datetime
    pedido_id: str
    descricao: str
    valor_centavos: int  # positivo = recebido; negativo = saiu


@dataclass(frozen=True)
class ExtratoProfissional:
    profissional_id: str
    desde: datetime
    ate: datetime
    linhas: tuple[LinhaExtrato, ...]
    recebido_centavos: int
    estornado_centavos: int
    a_liberar_fim_centavos: int

    @property
    def liquido_centavos(self) -> int:
        return self.recebido_centavos - self.estornado_centavos


def montar(
    lancamentos: Sequence[Lancamento], profissional_id: str, desde: datetime, ate: datetime
) -> ExtratoProfissional:
    def dele(tipo: TipoConta, conta) -> bool:
        return conta.tipo is tipo and conta.titular == profissional_id

    linhas: list[LinhaExtrato] = []
    a_liberar_fim = 0
    for item in lancamentos:
        if item.data < ate:
            if dele(TipoConta.A_LIBERAR, item.credito):
                a_liberar_fim += item.valor
            if dele(TipoConta.A_LIBERAR, item.debito):
                a_liberar_fim -= item.valor
        if not desde <= item.data < ate:
            continue
        if item.tipo is TipoLancamento.REPASSE and dele(TipoConta.LIBERADO, item.credito):
            linhas.append(LinhaExtrato(item.data, item.pedido_id, "Recebido", item.valor))
        elif item.tipo is TipoLancamento.ESTORNO and dele(TipoConta.LIBERADO, item.debito):
            linhas.append(LinhaExtrato(item.data, item.pedido_id, "Estorno", -item.valor))
        elif item.tipo is TipoLancamento.COBRANCA and dele(TipoConta.LIBERADO, item.credito):
            linhas.append(LinhaExtrato(item.data, item.pedido_id, "Gorjeta", item.valor))
    linhas.sort(key=lambda lin: lin.data)
    return ExtratoProfissional(
        profissional_id=profissional_id,
        desde=desde,
        ate=ate,
        linhas=tuple(linhas),
        recebido_centavos=sum(lin.valor_centavos for lin in linhas if lin.valor_centavos > 0),
        estornado_centavos=-sum(lin.valor_centavos for lin in linhas if lin.valor_centavos < 0),
        a_liberar_fim_centavos=a_liberar_fim,
    )


def reais(centavos: int) -> str:
    sinal = "-" if centavos < 0 else ""
    inteiro, resto = divmod(abs(centavos), 100)
    milhares = f"{inteiro:,}".replace(",", ".")
    return f"{sinal}R$ {milhares},{resto:02d}"


def _data(instante: datetime) -> str:
    return instante.astimezone(periodo.BRASILIA).strftime("%d/%m/%Y")


def pdf(
    extrato: ExtratoProfissional,
    nome: str,
    rotulos: Mapping[str, tuple[int | None, str]],
    emitido_em: datetime,
) -> bytes:
    """O extrato em PDF A4. `rotulos` = pedido -> (número curto, título)."""
    doc = PdfSimples()
    margem, direita = 50, LARGURA - 50
    fim_inclusivo = _data(extrato.ate - timedelta(days=1))  # o fim do intervalo é exclusivo

    def cabecalho() -> float:
        doc.texto(margem, 60, "Trato", 20, negrito=True)
        doc.texto(margem, 80, "Extrato de recebimentos do profissional", 11, cinza=True)
        doc.texto(margem, 112, nome, 13, negrito=True)
        doc.texto(margem, 130, f"Período: {_data(extrato.desde)} a {fim_inclusivo}", 10, cinza=True)
        return 160

    y = cabecalho()
    resumo = (
        ("Recebido no período", extrato.recebido_centavos),
        ("Estornos no período", -extrato.estornado_centavos),
        ("Líquido no período", extrato.liquido_centavos),
        ("A liberar ao fim do período", extrato.a_liberar_fim_centavos),
    )
    for rotulo, valor in resumo:
        negrito = rotulo.startswith("Líquido")
        doc.texto(margem, y, rotulo, 10.5, negrito=negrito)
        doc.texto(direita, y, reais(valor), 10.5, negrito=negrito, direita=True)
        y += 18
    y += 14

    def cabecalho_tabela(y: float) -> float:
        doc.faixa(margem, y - 12, direita - margem, 18)
        doc.texto(margem + 6, y, "Data", 9, negrito=True)
        doc.texto(margem + 90, y, "Pedido", 9, negrito=True)
        doc.texto(margem + 330, y, "Movimento", 9, negrito=True)
        doc.texto(direita - 6, y, "Valor", 9, negrito=True, direita=True)
        return y + 20

    y = cabecalho_tabela(y)
    if not extrato.linhas:
        doc.texto(margem + 6, y, "Nenhum movimento no período.", 10, cinza=True)
        y += 16
    for linha in extrato.linhas:
        if y > 780:
            doc.nova_pagina()
            y = cabecalho_tabela(cabecalho())
        numero, titulo = rotulos.get(linha.pedido_id, (None, ""))
        pedido = f"PED-{numero}" if numero is not None else linha.pedido_id[:8]
        if titulo:
            pedido = f"{pedido} · {titulo}"[:48]
        doc.texto(margem + 6, y, _data(linha.data), 9.5)
        doc.texto(margem + 90, y, pedido, 9.5)
        doc.texto(margem + 330, y, linha.descricao, 9.5)
        doc.texto(direita - 6, y, reais(linha.valor_centavos), 9.5, direita=True)
        doc.linha(margem, y + 6, direita, y + 6, 0.3)
        y += 18
    rodape = (
        f"Emitido em {emitido_em.astimezone(periodo.BRASILIA):%d/%m/%Y %H:%M} (horário de "
        "Brasília). Valores confirmados pelo parceiro de pagamento."
    )
    doc.texto(margem, 815, rodape, 8, cinza=True)
    return doc.bytes()
