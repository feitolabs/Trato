"""Provas da contestação de medida (Termos 20.5).

Sem pedido não há registro em `midias`: o arquivo vai ao bucket privado `verificacao` (sem leitura
direta por ninguém) e a referência fica em `medida_contestacoes.anexos`. A pessoa envia para um
caminho temporário; ao contestar, o servidor confere, limpa os metadados e grava a cópia final
num caminho que a URL de envio não alcança.
"""

from __future__ import annotations

import hashlib
import re
import uuid
from contextlib import suppress
from typing import Any

from pydantic import BaseModel, ConfigDict, Field

from trato.api import medidas as regras
from trato.api.contexto import Contexto
from trato.persistencia.medidas import ContestacaoMedida, Medida
from trato.seguranca.upload import ErroUpload, validar_conteudo, validar_metadados
from trato.uploads.armazenamento import ArquivoNaoEncontrado
from trato.uploads.imagem import ImagemInvalida, limpar_metadados

BUCKET = "verificacao"
CATEGORIA = "anexo_pedido"
TIPOS = {"image/jpeg": "jpg", "image/png": "png", "image/webp": "webp", "application/pdf": "pdf"}
_DO_SUFIXO = {sufixo: tipo for tipo, sufixo in TIPOS.items()}
TAMANHO_MAXIMO = 10 * 1024 * 1024  # limite do bucket
MAXIMO_DE_ANEXOS = 10
_ID = re.compile(r"^[0-9a-f]{32}\.(jpg|png|webp|pdf)$")


class ErroDeContestacao(Exception):
    def __init__(self, status: int, codigo: str, mensagem: str) -> None:
        super().__init__(mensagem)
        self.status, self.codigo, self.mensagem = status, codigo, mensagem


class PedirAnexoIn(BaseModel):
    model_config = ConfigDict(extra="forbid")

    nome_arquivo: str = Field(min_length=1, max_length=200)
    content_type: str = Field(max_length=100, description="image/jpeg, png, webp ou PDF.")
    tamanho_bytes: int = Field(gt=0, le=TAMANHO_MAXIMO, strict=True)


class AnexoParaEnvioOut(BaseModel):
    anexo_id: str = Field(description="Mande em `anexos` ao contestar.")
    url: str = Field(description="Envie o arquivo (PUT) para este link curto.")
    expira_em_segundos: int


def _temporario(medida: Medida, anexo_id: str) -> str:
    return f"contestacao-medida/{medida.usuario_id}/{medida.id}/envio/{anexo_id}"


def _exigir_prazo(contexto: Contexto, medida: Medida) -> None:
    ate = regras.contestavel_ate(contexto, medida)
    if ate is None or contexto.agora() > ate:
        raise ErroDeContestacao(
            409, "prazo_encerrado", "O prazo de 30 dias para contestar terminou."
        )


def _exigir_servico(servico: Any) -> Any:
    if servico is None:
        raise ErroDeContestacao(503, "indisponivel", "O envio de arquivos não está disponível.")
    return servico


def pedir_envio(
    contexto: Contexto, servico: Any, medida: Medida, corpo: PedirAnexoIn
) -> AnexoParaEnvioOut:
    _exigir_servico(servico)
    if contexto.medidas.contestacao(medida.id or "") is not None:
        raise ErroDeContestacao(409, "ja_contestada", "Esta medida já foi contestada.")
    _exigir_prazo(contexto, medida)
    tipo = corpo.content_type.split(";")[0].strip().lower()
    if tipo not in TIPOS:
        raise ErroDeContestacao(422, "arquivo_invalido", "Envie foto (JPG, PNG, WebP) ou PDF.")
    try:
        validar_metadados(
            servico.seguranca, CATEGORIA, tipo, corpo.tamanho_bytes, corpo.nome_arquivo
        )
    except ErroUpload as erro:
        raise ErroDeContestacao(422, "arquivo_invalido", str(erro)) from None
    anexo_id = f"{uuid.uuid4().hex}.{TIPOS[tipo]}"
    segundos = servico.config.url_envio_segundos
    url = servico.armazenamento.url_envio(BUCKET, _temporario(medida, anexo_id), tipo, segundos)
    return AnexoParaEnvioOut(anexo_id=anexo_id, url=url, expira_em_segundos=segundos)


def _guardar(servico: Any, medida: Medida, anexo_id: str) -> dict[str, Any]:
    """Confere o arquivo enviado e grava a cópia final (o caminho só o servidor conhece)."""
    if not _ID.match(anexo_id):
        raise ErroDeContestacao(422, "anexo_invalido", "Anexo desconhecido.")
    tipo = _DO_SUFIXO[anexo_id.rsplit(".", 1)[1]]
    try:
        dados = servico.armazenamento.ler(BUCKET, _temporario(medida, anexo_id))
    except ArquivoNaoEncontrado:
        raise ErroDeContestacao(
            409, "anexo_nao_enviado", "Um dos arquivos ainda não foi enviado."
        ) from None
    try:
        if len(dados) > TAMANHO_MAXIMO:
            raise ErroUpload("Arquivo grande demais.")
        validar_conteudo(servico.seguranca, CATEGORIA, tipo, dados)
        if tipo.startswith("image/"):
            dados = limpar_metadados(tipo, dados)
    except (ErroUpload, ImagemInvalida) as erro:
        raise ErroDeContestacao(422, "arquivo_invalido", str(erro)) from None
    sha = hashlib.sha256(dados).hexdigest()
    caminho = f"contestacao-medida/{medida.id}/{sha}.{TIPOS[tipo]}"
    servico.armazenamento.gravar(BUCKET, caminho, dados, tipo)
    return {
        "anexo_id": anexo_id,
        "bucket": BUCKET,
        "caminho": caminho,
        "content_type": tipo,
        "tamanho_bytes": len(dados),
        "sha256": sha,
    }


def contestar(
    contexto: Contexto,
    servico: Any,
    medida: Medida,
    versao: str,
    canal: str,
    anexos: list[str],
) -> tuple[ContestacaoMedida, bool]:
    """Uma contestação por medida; repetir a mesma devolve a que já existe."""
    ids = tuple(anexos)
    if len(set(ids)) != len(ids):
        raise ErroDeContestacao(422, "anexo_invalido", "Há arquivo repetido.")

    def conferir(item: ContestacaoMedida) -> tuple[ContestacaoMedida, bool]:
        if item.versao == versao and tuple(a["anexo_id"] for a in item.anexos) == ids:
            return item, False
        raise ErroDeContestacao(409, "ja_contestada", "Esta medida já foi contestada.")

    atual = contexto.medidas.contestacao(medida.id or "")
    if atual is not None:
        return conferir(atual)
    _exigir_prazo(contexto, medida)
    if ids:
        _exigir_servico(servico)
    try:
        guardados = tuple(_guardar(servico, medida, i) for i in ids)
    except ErroDeContestacao:
        atual = contexto.medidas.contestacao(medida.id or "")
        if atual is not None:  # outro toque gravou e já limpou o temporário
            return conferir(atual)
        raise
    item, nova = regras.contestar(contexto, medida, versao, canal, guardados)
    if not nova:
        return conferir(item)
    for anexo_id in ids:
        with suppress(Exception):  # sobra de temporário não desfaz a contestação
            servico.armazenamento.remover(BUCKET, _temporario(medida, anexo_id))
    return item, True
