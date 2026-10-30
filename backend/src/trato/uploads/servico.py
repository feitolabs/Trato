"""Serviço de upload: pede a URL de envio, REVALIDA o arquivo e só então registra.

Fluxo: `pedir` valida os metadados (bucket, tipo, tamanho) e emite uma URL assinada curta para um
caminho com o id do dono; o app envia o arquivo direto ao Storage; `concluir` lê o arquivo,
confere o tipo REAL pelo conteúdo, o tamanho, remove EXIF/GPS (imagem), calcula o SHA-256 e
registra em `midias` ou `verificacao_documentos`. O app nunca registra nada por conta própria.
"""

from __future__ import annotations

import hashlib
import math
import uuid
from collections.abc import Callable
from dataclasses import dataclass, replace
from datetime import datetime, timedelta

from trato.seguranca.config import ConfigSeguranca
from trato.seguranca.upload import ErroUpload, validar_conteudo, validar_metadados
from trato.uploads.armazenamento import ArmazenamentoArquivos, ArquivoNaoEncontrado
from trato.uploads.config import ConfigUploads
from trato.uploads.imagem import ImagemInvalida, limpar_metadados


class UploadNegado(Exception):
    """O usuário não pode enviar isto (vira 403/404 na rota)."""


class SolicitacaoInvalida(Exception):
    """Estado da solicitação não permite concluir (vira 409/410/422)."""

    def __init__(self, mensagem: str, status: int = 409) -> None:
        super().__init__(mensagem)
        self.status = status


@dataclass(frozen=True)
class Destino:
    bucket: str
    categoria: str  # chave de `ConfigSeguranca.uploads` (tipos e tamanho)
    registro: str  # "midia" | "documento" | "avatar"


# O destino decide bucket, regra de tipo/tamanho e onde registrar (docs/seguranca-banco.md).
DESTINOS: dict[str, Destino] = {
    "pedido": Destino("pedido-midias", "anexo_pedido", "midia"),
    "antes": Destino("pedido-midias", "anexo_pedido", "midia"),
    "durante": Destino("pedido-midias", "anexo_pedido", "midia"),
    "depois": Destino("pedido-midias", "anexo_pedido", "midia"),
    "checkin": Destino("pedido-midias", "foto", "midia"),
    "checkout": Destino("pedido-midias", "foto", "midia"),
    "nota_material": Destino("pedido-midias", "anexo_pedido", "midia"),
    "disputa": Destino("pedido-midias", "anexo_pedido", "midia"),
    "retrabalho": Destino("pedido-midias", "anexo_pedido", "midia"),
    "chat": Destino("chat-anexos", "anexo_pedido", "midia"),
    "avatar": Destino("avatar", "foto", "avatar"),
    "verificacao": Destino("verificacao", "documento", "documento"),
}
# Quem pode enviar para cada finalidade de mídia do pedido (papel no pedido).
SO_PROFISSIONAL = frozenset({"checkin", "checkout", "nota_material", "durante", "depois"})
SO_CLIENTE = frozenset({"pedido"})


@dataclass(frozen=True)
class Solicitacao:
    id: str
    dono_id: str
    destino: str
    bucket: str
    caminho: str
    content_type: str
    tamanho_bytes: int
    criada_em: datetime
    pedido_id: str | None = None
    tipo_documento: str | None = None
    status: str = "pendente"
    registro_id: str | None = None


@dataclass(frozen=True)
class Midia:
    id: str
    pedido_id: str
    enviada_por: str
    finalidade: str
    bucket: str
    storage_path: str
    mime: str
    tamanho_bytes: int
    sha256: str
    criada_em: datetime
    # Posição que o app informou na conclusão (o check-in compara com o local do pedido).
    lat: float | None = None
    lng: float | None = None


@dataclass(frozen=True)
class DocumentoGuardado:
    id: str
    dono_id: str
    tipo: str
    bucket: str
    storage_path: str
    sha256: str
    criado_em: datetime


class UploadsEmMemoria:
    """Solicitações, mídias e documentos de verificação. Não é o armazenamento real."""

    def __init__(self) -> None:
        self.solicitacoes: dict[str, Solicitacao] = {}
        self.midias: dict[str, Midia] = {}
        self.documentos: dict[str, DocumentoGuardado] = {}

    def salvar_solicitacao(self, s: Solicitacao) -> None:
        self.solicitacoes[s.id] = s

    def solicitacao(self, solicitacao_id: str) -> Solicitacao | None:
        return self.solicitacoes.get(solicitacao_id)

    def salvar_midia(self, m: Midia) -> None:
        self.midias[m.id] = m

    def midia(self, midia_id: str) -> Midia | None:
        return self.midias.get(midia_id)

    def salvar_documento(self, d: DocumentoGuardado) -> None:
        self.documentos[d.id] = d

    def documento_por_caminho(self, caminho: str) -> DocumentoGuardado | None:
        return next((d for d in self.documentos.values() if d.storage_path == caminho), None)


def distancia_metros(lat1: float, lng1: float, lat2: float, lng2: float) -> float:
    """Distância entre dois pontos (haversine), em metros. Calculada SEMPRE no servidor."""
    r = 6_371_000.0
    p1, p2 = math.radians(lat1), math.radians(lat2)
    dp, dl = p2 - p1, math.radians(lng2 - lng1)
    a = math.sin(dp / 2) ** 2 + math.cos(p1) * math.cos(p2) * math.sin(dl / 2) ** 2
    return 2 * r * math.asin(math.sqrt(a))


class ServicoUploads:
    def __init__(
        self,
        armazenamento: ArmazenamentoArquivos,
        repo: UploadsEmMemoria,
        seguranca: ConfigSeguranca,
        config: ConfigUploads,
        agora: Callable[[], datetime],
        local_do_pedido: Callable[[str], tuple[float, float] | None] | None = None,
    ) -> None:
        self.armazenamento = armazenamento
        self.repo = repo
        self.seguranca = seguranca
        self.config = config
        self.agora = agora
        self.local_do_pedido = local_do_pedido or (lambda _pedido: None)

    def pedir(
        self,
        dono_id: str,
        destino: str,
        content_type: str,
        tamanho_bytes: int,
        nome: str,
        *,
        pedido_id: str | None = None,
        tipo_documento: str | None = None,
    ) -> tuple[Solicitacao, str]:
        regra = DESTINOS.get(destino)
        if regra is None:
            raise ErroUpload("Destino de arquivo desconhecido.")
        nome_seguro = validar_metadados(
            self.seguranca, regra.categoria, content_type, tamanho_bytes, nome
        )
        if regra.registro == "midia":
            # O caminho começa pelo pedido (convenção do Storage); o dono fica na solicitação.
            caminho = f"{pedido_id}/{nome_seguro}"
        elif regra.registro == "avatar":
            caminho = f"{dono_id}/{nome_seguro}"
        else:
            caminho = f"{dono_id}/pendente/{nome_seguro}"
        tipo = content_type.split(";")[0].strip().lower()
        sol = Solicitacao(
            uuid.uuid4().hex, dono_id, destino, regra.bucket, caminho, tipo, tamanho_bytes,
            self.agora(), pedido_id, tipo_documento,
        )  # fmt: skip
        self.repo.salvar_solicitacao(sol)
        url = self.armazenamento.url_envio(
            regra.bucket, caminho, tipo, self.config.url_envio_segundos
        )
        return sol, url

    def concluir(
        self,
        dono_id: str,
        solicitacao_id: str,
        *,
        lat: float | None = None,
        lng: float | None = None,
    ) -> Solicitacao:
        sol = self.repo.solicitacao(solicitacao_id)
        if sol is None or sol.dono_id != dono_id:  # não revela que existe
            raise UploadNegado("Envio não encontrado.")
        if sol.status == "concluida":
            return sol
        validade = timedelta(seconds=self.config.solicitacao_validade_segundos)
        if self.agora() - sol.criada_em > validade:
            raise SolicitacaoInvalida("O prazo deste envio acabou. Peça um novo.", 410)
        regra = DESTINOS[sol.destino]
        try:
            dados = self.armazenamento.ler(sol.bucket, sol.caminho)
        except ArquivoNaoEncontrado:
            raise SolicitacaoInvalida("O arquivo ainda não foi enviado.", 409) from None
        try:
            # Revalida tudo: o app pode ter declarado um tipo e enviado outra coisa.
            if len(dados) > sol.tamanho_bytes:
                raise ErroUpload("O arquivo é maior do que o informado.")
            validar_conteudo(self.seguranca, regra.categoria, sol.content_type, dados)
            if sol.content_type.startswith("image/"):
                dados = limpar_metadados(sol.content_type, dados)
        except (ErroUpload, ImagemInvalida) as erro:
            self.armazenamento.remover(sol.bucket, sol.caminho)  # arquivo suspeito não fica
            raise SolicitacaoInvalida(str(erro), 422) from None
        self.armazenamento.gravar(sol.bucket, sol.caminho, dados, sol.content_type)
        sha = hashlib.sha256(dados).hexdigest()
        agora = self.agora()
        registro_id = uuid.uuid4().hex
        if regra.registro == "midia":
            if sol.pedido_id is None:
                raise SolicitacaoInvalida("Envio sem pedido.", 422)
            self.repo.salvar_midia(
                Midia(
                    registro_id,
                    sol.pedido_id,
                    dono_id,
                    sol.destino,
                    sol.bucket,
                    sol.caminho,
                    sol.content_type,
                    len(dados),
                    sha,
                    agora,
                    lat,
                    lng,
                )  # fmt: skip
            )
        elif regra.registro == "documento":
            self.repo.salvar_documento(
                DocumentoGuardado(
                    registro_id,
                    dono_id,
                    sol.tipo_documento or "outro",
                    sol.bucket,
                    sol.caminho,
                    sha,
                    agora,
                )  # fmt: skip
            )
        feita = replace(sol, status="concluida", registro_id=registro_id)
        self.repo.salvar_solicitacao(feita)
        return feita
