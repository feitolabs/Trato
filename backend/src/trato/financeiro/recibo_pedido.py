"""Comprovante de serviço de um pedido concluído, em PDF (A4, mesmo gerador do extrato).

Só usa dados que já existem: o pedido, o contrato e o ledger. Não substitui nota fiscal.
Cada parte vê só o que é seu: o cliente vê o que pagou (e o desconto); o profissional vê a taxa
do Trato e o líquido. Nomes sempre abreviados (primeiro nome e inicial do último).
"""

from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime
from typing import Literal

from trato.financeiro import periodo
from trato.financeiro.extrato_profissional import reais
from trato.financeiro.pdf import LARGURA, PdfSimples


@dataclass(frozen=True)
class DadosRecibo:
    codigo: str  # PED-<número> ou o início do id
    titulo: str
    categoria: str
    concluido_em: datetime | None
    cliente_nome: str
    profissional_nome: str
    valor_servico_centavos: int
    cliente_pagou_centavos: int
    taxa_trato_centavos: int
    liquido_profissional_centavos: int

    @property
    def desconto_centavos(self) -> int:
        """Quanto o cliente deixou de pagar (cupom ou Tratinhos); 0 sem cobrança registrada."""
        if self.cliente_pagou_centavos <= 0:
            return 0
        return max(0, self.valor_servico_centavos - self.cliente_pagou_centavos)


def _data(instante: datetime | None) -> str:
    if instante is None:
        return "—"
    return instante.astimezone(periodo.BRASILIA).strftime("%d/%m/%Y")


def pdf(
    dados: DadosRecibo, quem: Literal["cliente", "profissional"], emitido_em: datetime
) -> bytes:
    doc = PdfSimples()
    margem, direita = 50, LARGURA - 50
    doc.texto(margem, 60, "Comprovante de serviço — Trato", 18, negrito=True)
    doc.texto(margem, 80, f"Pedido {dados.codigo}", 11, cinza=True)

    y = 120.0
    for rotulo, texto in (
        ("Serviço", dados.titulo or "—"),
        ("Categoria", dados.categoria or "—"),
        ("Concluído em", _data(dados.concluido_em)),
        ("Cliente", dados.cliente_nome or "—"),
        ("Profissional", dados.profissional_nome or "—"),
    ):
        doc.texto(margem, y, rotulo, 10.5, cinza=True)
        doc.texto(direita, y, texto[:60], 10.5, direita=True)
        y += 18

    y += 12
    doc.texto(margem, y, "Valores", 11, negrito=True)
    y += 20
    linhas: list[tuple[str, str, bool]] = [
        ("Valor do serviço", reais(dados.valor_servico_centavos), False)
    ]
    if quem == "cliente":
        if dados.desconto_centavos > 0:
            linhas.append(("Desconto (cupom ou Tratinhos)", reais(-dados.desconto_centavos), False))
        linhas.append(("Total pago por você", reais(dados.cliente_pagou_centavos), True))
    else:
        linhas.append(("Taxa do Trato", reais(-dados.taxa_trato_centavos), False))
        linhas.append(
            ("Valor líquido do profissional", reais(dados.liquido_profissional_centavos), True)
        )
    for rotulo, texto, negrito in linhas:
        doc.texto(margem, y, rotulo, 10.5, negrito=negrito)
        doc.texto(direita, y, texto, 10.5, negrito=negrito, direita=True)
        doc.linha(margem, y + 6, direita, y + 6, 0.3)
        y += 20

    doc.texto(
        margem,
        y + 20,
        "Este é um comprovante de serviço da plataforma Trato e não substitui nota fiscal.",
        9,
        cinza=True,
    )
    doc.texto(
        margem,
        815,
        f"Emitido em {emitido_em.astimezone(periodo.BRASILIA):%d/%m/%Y %H:%M} "
        "(horário de Brasília).",
        8,
        cinza=True,
    )
    return doc.bytes()
