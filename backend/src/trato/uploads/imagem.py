"""Remove metadados (EXIF, GPS, miniatura, texto embutido) de JPEG, PNG e WebP, sem dependências.

A localização do check-in vem do campo `localizacao` do pedido, validado e guardado pelo
servidor; nunca do EXIF do arquivo.
"""

from __future__ import annotations

import struct


class ImagemInvalida(ValueError):
    pass


def limpar_jpeg(dados: bytes) -> bytes:
    if not dados.startswith(b"\xff\xd8"):
        raise ImagemInvalida("JPEG inválido.")
    saida = bytearray(b"\xff\xd8")
    i = 2
    while i < len(dados):
        if dados[i] != 0xFF:
            raise ImagemInvalida("JPEG corrompido.")
        while i < len(dados) and dados[i] == 0xFF:  # preenchimento
            i += 1
        if i >= len(dados):
            raise ImagemInvalida("JPEG corrompido.")
        marca = dados[i]
        i += 1
        if marca == 0xDA:  # início da imagem: o resto (dados + EOI) fica como está
            saida += b"\xff\xda" + dados[i:]
            return bytes(saida)
        if marca == 0xD9:
            saida += b"\xff\xd9"
            return bytes(saida)
        if marca == 0x01 or 0xD0 <= marca <= 0xD7:  # marcadores sem tamanho
            saida += bytes([0xFF, marca])
            continue
        if i + 2 > len(dados):
            raise ImagemInvalida("JPEG corrompido.")
        (tamanho,) = struct.unpack(">H", dados[i : i + 2])
        if tamanho < 2 or i + tamanho > len(dados):
            raise ImagemInvalida("JPEG corrompido.")
        # APP1..APP15 (EXIF, XMP, ...) e comentário saem; APP0 (JFIF) e APP14 (Adobe, cor) ficam.
        if (0xE1 <= marca <= 0xEF and marca != 0xEE) or marca == 0xFE:
            i += tamanho
            continue
        saida += bytes([0xFF, marca]) + dados[i : i + tamanho]
        i += tamanho
    raise ImagemInvalida("JPEG sem dados de imagem.")


_PNG_FIXOS = {b"IHDR", b"PLTE", b"IDAT", b"IEND", b"tRNS", b"gAMA", b"cHRM", b"sRGB", b"sBIT"}


def limpar_png(dados: bytes) -> bytes:
    assinatura = b"\x89PNG\r\n\x1a\n"
    if not dados.startswith(assinatura):
        raise ImagemInvalida("PNG inválido.")
    saida = bytearray(assinatura)
    i = len(assinatura)
    fim = False
    while i + 8 <= len(dados):
        (tamanho,) = struct.unpack(">I", dados[i : i + 4])
        tipo = dados[i + 4 : i + 8]
        bloco = dados[i : i + 12 + tamanho]
        if len(bloco) != 12 + tamanho:
            raise ImagemInvalida("PNG corrompido.")
        if tipo in _PNG_FIXOS:  # o resto (eXIf, tEXt, iTXt, zTXt, tIME, ...) sai
            saida += bloco
        i += 12 + tamanho
        if tipo == b"IEND":
            fim = True
            break
    if not fim:
        raise ImagemInvalida("PNG sem fim.")
    return bytes(saida)


def limpar_webp(dados: bytes) -> bytes:
    if dados[:4] != b"RIFF" or dados[8:12] != b"WEBP":
        raise ImagemInvalida("WebP inválido.")
    corpo = bytearray(b"WEBP")
    i = 12
    while i + 8 <= len(dados):
        tipo = dados[i : i + 4]
        (tamanho,) = struct.unpack("<I", dados[i + 4 : i + 8])
        fim = i + 8 + tamanho + (tamanho & 1)
        if fim > len(dados) + 1:
            raise ImagemInvalida("WebP corrompido.")
        if tipo not in (b"EXIF", b"XMP ", b"ICCP"):
            corpo += dados[i:fim]
        i = fim
    return b"RIFF" + struct.pack("<I", len(corpo)) + bytes(corpo)


def limpar_metadados(tipo: str, dados: bytes) -> bytes:
    if tipo == "image/jpeg":
        return limpar_jpeg(dados)
    if tipo == "image/png":
        return limpar_png(dados)
    if tipo == "image/webp":
        return limpar_webp(dados)
    return dados
