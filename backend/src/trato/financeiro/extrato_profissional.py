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
from trato.financeiro.ledger import Lancamento, TipoConta, TipoLancamento, taxa_descontada
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
    # Resumo do mês (recibo de ganhos). Opcionais: quem monta sem eles vê zeros.
    servicos_concluidos: int = 0
    taxa_trato_centavos: int = 0

    @property
    def bruto_centavos(self) -> int:
        """O que os serviços pagos no período valeram antes da taxa (líquido recebido + taxa)."""
        return self.recebido_centavos + self.taxa_trato_centavos

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
    pedidos_pagos = {lin.pedido_id for lin in linhas if lin.descricao == "Recebido"}
    taxa = sum(taxa_descontada(lancamentos, pid) for pid in pedidos_pagos)
    return ExtratoProfissional(
        profissional_id=profissional_id,
        desde=desde,
        ate=ate,
        linhas=tuple(linhas),
        recebido_centavos=sum(lin.valor_centavos for lin in linhas if lin.valor_centavos > 0),
        estornado_centavos=-sum(lin.valor_centavos for lin in linhas if lin.valor_centavos < 0),
        a_liberar_fim_centavos=a_liberar_fim,
        servicos_concluidos=len(pedidos_pagos),
        taxa_trato_centavos=taxa,
    )


def reais(centavos: int) -> str:
    sinal = "-" if centavos < 0 else ""
    inteiro, resto = divmod(abs(centavos), 100)
    milhares = f"{inteiro:,}".replace(",", ".")
    return f"{sinal}R$ {milhares},{resto:02d}"


def formatar_documento(documento: str | None) -> str | None:
    """CPF (11 dígitos) ou CNPJ (14) formatado; outro tamanho = sem linha no PDF."""
    digitos = "".join(c for c in (documento or "") if c.isdigit())
    if len(digitos) == 11:
        return f"CPF {digitos[:3]}.{digitos[3:6]}.{digitos[6:9]}-{digitos[9:]}"
    if len(digitos) == 14:
        return f"CNPJ {digitos[:2]}.{digitos[2:5]}.{digitos[5:8]}/{digitos[8:12]}-{digitos[12:]}"
    return None


def _data(instante: datetime) -> str:
    return instante.astimezone(periodo.BRASILIA).strftime("%d/%m/%Y")


def pdf(
    extrato: ExtratoProfissional,
    nome: str,
    rotulos: Mapping[str, tuple[int | None, str]],
    emitido_em: datetime,
    documento: str | None = None,
    categorias: Mapping[str, str] | None = None,
) -> bytes:
    """O extrato em PDF A4. `rotulos` = pedido -> (número curto, título).

    Opcionais (só do PRÓPRIO profissional): `documento` (CPF/CNPJ, aparece ao lado do nome) e
    `categorias` (pedido -> nome da categoria, para a tabela "Serviços do período"). Nenhum
    dado do cliente entra no documento."""
    doc = PdfSimples()
    margem, direita = 50, LARGURA - 50
    fim_inclusivo = _data(extrato.ate - timedelta(days=1))  # o fim do intervalo é exclusivo

    def cabecalho() -> float:
        doc.texto(margem, 60, "Trato", 20, negrito=True)
        doc.texto(margem, 80, "Extrato de recebimentos do profissional", 11, cinza=True)
        doc.texto(margem, 112, nome, 13, negrito=True)
        texto_doc = formatar_documento(documento)
        if texto_doc:
            doc.texto(direita, 112, texto_doc, 10.5, direita=True)
        doc.texto(margem, 130, f"Período: {_data(extrato.desde)} a {fim_inclusivo}", 10, cinza=True)
        return 160

    y = cabecalho()
    doc.texto(margem, y, "Resumo do mês", 11, negrito=True)
    y += 20
    ganhos = (
        ("Serviços concluídos", str(extrato.servicos_concluidos)),
        ("Total bruto", reais(extrato.bruto_centavos)),
        (
            "Taxa do Trato",
            reais(extrato.taxa_trato_centavos) if extrato.taxa_trato_centavos > 0 else "Sem taxa",
        ),
        ("Total líquido recebido", reais(extrato.recebido_centavos)),
    )
    for rotulo, texto in ganhos:
        negrito = rotulo.startswith("Total líquido")
        doc.texto(margem, y, rotulo, 10.5, negrito=negrito)
        doc.texto(direita, y, texto, 10.5, negrito=negrito, direita=True)
        y += 18
    y += 10
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

    def pedido_curto(pedido_id: str) -> str:
        numero, _ = rotulos.get(pedido_id, (None, ""))
        return f"PED-{numero}" if numero is not None else pedido_id[:8]

    servicos = [lin for lin in extrato.linhas if lin.descricao == "Recebido"]
    if servicos:
        doc.texto(margem, y, "Serviços do período", 11, negrito=True)
        y += 18

        def cabecalho_servicos(y: float) -> float:
            doc.faixa(margem, y - 12, direita - margem, 18)
            doc.texto(margem + 6, y, "Data", 9, negrito=True)
            doc.texto(margem + 90, y, "Pedido", 9, negrito=True)
            doc.texto(margem + 190, y, "Categoria", 9, negrito=True)
            doc.texto(direita - 6, y, "Valor líquido", 9, negrito=True, direita=True)
            return y + 20

        y = cabecalho_servicos(y)
        for lin in servicos:
            if y > 780:
                doc.nova_pagina()
                y = cabecalho_servicos(cabecalho())
            categoria = (categorias or {}).get(lin.pedido_id, "")
            doc.texto(margem + 6, y, _data(lin.data), 9.5)
            doc.texto(margem + 90, y, pedido_curto(lin.pedido_id), 9.5)
            doc.texto(margem + 190, y, categoria[:40], 9.5)
            doc.texto(direita - 6, y, reais(lin.valor_centavos), 9.5, direita=True)
            doc.linha(margem, y + 6, direita, y + 6, 0.3)
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
