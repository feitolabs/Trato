"""PDFs entregues na Contratação (Termos 5.3 e 6.13): comprovante de pagamento e cópia dos Termos.

Só leitura: nada aqui calcula, cobra ou lança dinheiro.
"""

from __future__ import annotations

import textwrap
from dataclasses import dataclass
from datetime import datetime

from trato.financeiro import periodo
from trato.financeiro.extrato_profissional import reais
from trato.financeiro.pdf import LARGURA, PdfSimples

_MARGEM = 50


@dataclass(frozen=True)
class DadosComprovante:
    codigo: str
    titulo: str
    cliente_nome: str
    profissional_nome: str
    confirmada_em: datetime
    referencia_pagamento: str
    valor_pago_centavos: int
    desconto_centavos: int = 0
    meio: str | None = None
    parcelas: int = 1
    termos_versao: str | None = None


def _quando(instante: datetime) -> str:
    return f"{instante.astimezone(periodo.BRASILIA):%d/%m/%Y %H:%M} (horário de Brasília)"


def comprovante_pdf(dados: DadosComprovante, emitido_em: datetime) -> bytes:
    doc = PdfSimples()
    direita = LARGURA - _MARGEM
    doc.texto(_MARGEM, 60, "Comprovante de pagamento — Trato", 18, negrito=True)
    doc.texto(_MARGEM, 80, f"Pedido {dados.codigo}", 11, cinza=True)
    linhas = [
        ("Serviço", dados.titulo or "—"),
        ("Cliente", dados.cliente_nome or "—"),
        ("Profissional", dados.profissional_nome or "—"),
        ("Contratação confirmada em", _quando(dados.confirmada_em)),
        ("Referência do pagamento", dados.referencia_pagamento),
    ]
    if dados.meio:
        meio = {"pix": "Pix", "cartao": "Cartão"}.get(dados.meio, dados.meio)
        if dados.parcelas > 1:
            meio = f"{meio} em {dados.parcelas}x"
        linhas.append(("Forma de pagamento", meio))
    if dados.desconto_centavos > 0:
        linhas.append(("Desconto (cupom ou Tratinhos)", reais(-dados.desconto_centavos)))
    linhas.append(("Valor pago na contratação", reais(dados.valor_pago_centavos)))
    if dados.termos_versao:
        linhas.append(("Termos de uso da Contratação", f"versão {dados.termos_versao}"))
    y = 120.0
    for rotulo, texto in linhas:
        doc.texto(_MARGEM, y, rotulo, 10.5, cinza=True)
        doc.texto(direita, y, texto[:60], 10.5, direita=True)
        doc.linha(_MARGEM, y + 6, direita, y + 6, 0.3)
        y += 22
    for i, aviso in enumerate(
        (
            "Pagamento da contratação. Aditivos e estornos posteriores aparecem no pedido.",
            "Este comprovante não substitui a nota fiscal do serviço.",
        )
    ):
        doc.texto(_MARGEM, y + 20 + 14 * i, aviso, 9, cinza=True)
    doc.texto(_MARGEM, 815, f"Emitido em {_quando(emitido_em)}.", 8, cinza=True)
    return doc.bytes()


def _sem_marcas(linha: str) -> str:
    """Tira as marcas de markdown e troca o que a fonte do PDF não desenha."""
    linha = linha.replace("**", "").replace("`", "").replace("→", "->")
    return linha.lstrip("#").strip() if linha.startswith("#") else linha


def termos_pdf(texto: str) -> bytes:
    doc = PdfSimples()
    y = 55.0
    for bruta in texto.splitlines():
        if bruta.strip() == "---":
            continue
        titulo = bruta.startswith("#")
        for linha in textwrap.wrap(_sem_marcas(bruta), 80 if titulo else 90) or [""]:
            if y > 790:
                doc.nova_pagina()
                y = 55.0
            doc.texto(_MARGEM, y, linha, 11.5 if titulo else 9.5, negrito=titulo)
            y += 17 if titulo else 13
    return doc.bytes()
