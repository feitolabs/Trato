"""Validação de upload: tipo declarado, tamanho, nome e conteúdo real (bytes iniciais).

O app envia o arquivo direto ao Storage do Supabase. Antes de emitir o envio, o backend valida os
metadados com `validar_metadados`; quando o backend recebe os bytes, `validar_conteudo` confere
que o arquivo é mesmo do tipo declarado (um .exe renomeado para .jpg não passa).
"""

from __future__ import annotations

import re
import uuid

from trato.seguranca.config import ConfigSeguranca

EXTENSOES = {
    "image/jpeg": (".jpg", ".jpeg"),
    "image/png": (".png",),
    "image/webp": (".webp",),
    "application/pdf": (".pdf",),
    "video/mp4": (".mp4",),
}


class ErroUpload(ValueError):
    """Upload recusado; a mensagem é para o usuário."""


def tipo_pelo_conteudo(inicio: bytes) -> str | None:
    if inicio.startswith(b"\xff\xd8\xff"):
        return "image/jpeg"
    if inicio.startswith(b"\x89PNG\r\n\x1a\n"):
        return "image/png"
    if inicio[:4] == b"RIFF" and inicio[8:12] == b"WEBP":
        return "image/webp"
    if inicio.startswith(b"%PDF-"):
        return "application/pdf"
    if inicio[4:8] == b"ftyp":
        return "video/mp4"
    return None


def _regra(config: ConfigSeguranca, categoria: str):  # type: ignore[no-untyped-def]
    regra = config.uploads.get(categoria)
    if regra is None:
        raise ErroUpload("Categoria de arquivo desconhecida.")
    return regra


def validar_metadados(
    config: ConfigSeguranca, categoria: str, content_type: str, tamanho_bytes: int, nome: str
) -> str:
    """Valida e devolve um nome seguro para guardar (o nome original nunca vira caminho)."""
    regra = _regra(config, categoria)
    tipo = (content_type or "").split(";")[0].strip().lower()
    if tipo not in regra.tipos:
        raise ErroUpload("Tipo de arquivo não permitido para este envio.")
    if tamanho_bytes <= 0:
        raise ErroUpload("Arquivo vazio.")
    if tamanho_bytes > regra.tamanho_max_bytes:
        limite_mb = regra.tamanho_max_bytes / (1024 * 1024)
        raise ErroUpload(f"Arquivo grande demais (máximo {limite_mb:g} MB).")
    if not nome or len(nome) > 255 or re.search(r"[\x00-\x1f/\\]|\.\.", nome):
        raise ErroUpload("Nome de arquivo inválido.")
    extensao = "." + nome.rsplit(".", 1)[-1].lower() if "." in nome else ""
    if extensao not in EXTENSOES[tipo]:
        raise ErroUpload("A extensão não bate com o tipo do arquivo.")
    return f"{uuid.uuid4().hex}{EXTENSOES[tipo][0]}"


def validar_conteudo(
    config: ConfigSeguranca, categoria: str, content_type: str, dados: bytes
) -> None:
    regra = _regra(config, categoria)
    tipo = (content_type or "").split(";")[0].strip().lower()
    if len(dados) > regra.tamanho_max_bytes:
        raise ErroUpload("Arquivo grande demais.")
    real = tipo_pelo_conteudo(dados[:16])
    if real is None or real != tipo or real not in regra.tipos:
        raise ErroUpload("O conteúdo do arquivo não confere com o tipo informado.")
