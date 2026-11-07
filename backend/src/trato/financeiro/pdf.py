"""PDF simples (texto, linhas e retângulos), sem dependência externa.

Só o necessário para um extrato: páginas A4, fonte Helvetica (normal e negrito) com acentos do
português (WinAnsiEncoding / cp1252). Nada de imagem, fonte embutida ou formulário.
"""

from __future__ import annotations

from dataclasses import dataclass, field

LARGURA, ALTURA = 595, 842  # A4 em pontos

_FONTES = {False: "F1", True: "F2"}


def _texto_pdf(texto: str) -> bytes:
    bruto = texto.encode("cp1252", errors="replace")
    return bruto.replace(b"\\", b"\\\\").replace(b"(", b"\\(").replace(b")", b"\\)")


def largura_texto(texto: str, tamanho: float) -> float:
    """Largura aproximada (Helvetica): serve para alinhar valores à direita."""
    estreitas = sum(1 for c in texto if c in "il.,:;'|!I ")
    largas = sum(1 for c in texto if c in "mwMW@")
    return tamanho * (0.556 * len(texto) - 0.28 * estreitas + 0.28 * largas)


@dataclass
class PdfSimples:
    _paginas: list[list[bytes]] = field(default_factory=lambda: [[]])

    def nova_pagina(self) -> None:
        self._paginas.append([])

    def texto(
        self,
        x: float,
        y: float,
        texto: str,
        tamanho: float = 10,
        negrito: bool = False,
        cinza: bool = False,
        direita: bool = False,
    ) -> None:
        """`y` é medido do TOPO da página. `direita=True` alinha o fim do texto em `x`."""
        if direita:
            x -= largura_texto(texto, tamanho)
        cor = b"0.42 g " if cinza else b"0 g "
        self._paginas[-1].append(
            cor
            + b"BT /"
            + _FONTES[negrito].encode()
            + f" {tamanho:g} Tf {x:.1f} {ALTURA - y:.1f} Td (".encode()
            + _texto_pdf(texto)
            + b") Tj ET"
        )

    def linha(self, x1: float, y1: float, x2: float, y2: float, espessura: float = 0.6) -> None:
        de, para = f"{x1:.1f} {ALTURA - y1:.1f}", f"{x2:.1f} {ALTURA - y2:.1f}"
        self._paginas[-1].append(f"0.75 G {espessura:g} w {de} m {para} l S".encode())

    def faixa(self, x: float, y: float, largura: float, altura: float) -> None:
        """Retângulo cinza-claro (fundo de cabeçalho de tabela)."""
        self._paginas[-1].append(
            f"0.95 g {x:.1f} {ALTURA - y - altura:.1f} {largura:.1f} {altura:.1f} re f".encode()
        )

    def bytes(self) -> bytes:
        objetos: list[bytes] = []

        def novo(conteudo: bytes) -> int:
            objetos.append(conteudo)
            return len(objetos)

        catalogo = novo(b"")  # preenchido depois
        paginas_id = novo(b"")
        fonte = novo(
            b"<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica /Encoding /WinAnsiEncoding >>"
        )
        fonte_negrito = novo(
            b"<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica-Bold "
            b"/Encoding /WinAnsiEncoding >>"
        )
        filhos = []
        for comandos in self._paginas:
            fluxo = b"\n".join(comandos)
            conteudo = novo(b"<< /Length %d >>\nstream\n" % len(fluxo) + fluxo + b"\nendstream")
            filhos.append(
                novo(
                    b"<< /Type /Page /Parent %d 0 R /MediaBox [0 0 %d %d] "
                    b"/Resources << /Font << /F1 %d 0 R /F2 %d 0 R >> >> /Contents %d 0 R >>"
                    % (paginas_id, LARGURA, ALTURA, fonte, fonte_negrito, conteudo)
                )
            )
        objetos[catalogo - 1] = b"<< /Type /Catalog /Pages %d 0 R >>" % paginas_id
        objetos[paginas_id - 1] = b"<< /Type /Pages /Kids [%s] /Count %d >>" % (
            b" ".join(b"%d 0 R" % f for f in filhos),
            len(filhos),
        )

        saida = bytearray(b"%PDF-1.4\n%\xe2\xe3\xcf\xd3\n")
        posicoes = []
        for numero, conteudo in enumerate(objetos, start=1):
            posicoes.append(len(saida))
            saida += b"%d 0 obj\n" % numero + conteudo + b"\nendobj\n"
        inicio_xref = len(saida)
        saida += b"xref\n0 %d\n0000000000 65535 f \n" % (len(objetos) + 1)
        for posicao in posicoes:
            saida += b"%010d 00000 n \n" % posicao
        saida += b"trailer\n<< /Size %d /Root %d 0 R >>\nstartxref\n%d\n%%%%EOF\n" % (
            len(objetos) + 1,
            catalogo,
            inicio_xref,
        )
        return bytes(saida)
