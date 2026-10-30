"""Armazenamento de arquivos atrás de uma interface. Nenhum teste fala com o Storage real.

`ArmazenamentoFake` (testes) guarda em memória. `ArmazenamentoSupabase` fala com o Storage do
Supabase (buckets privados) e só é montado quando `SUPABASE_URL` e a chave de serviço existem.
"""

from __future__ import annotations

from typing import Any, Protocol


class ArquivoNaoEncontrado(Exception):
    pass


class ArmazenamentoArquivos(Protocol):
    def url_envio(self, bucket: str, caminho: str, content_type: str, segundos: int) -> str:
        """URL assinada para o app enviar o arquivo direto ao bucket privado."""

    def ler(self, bucket: str, caminho: str) -> bytes:
        """Bytes do arquivo enviado. Levanta `ArquivoNaoEncontrado`."""

    def gravar(self, bucket: str, caminho: str, dados: bytes, content_type: str) -> None:
        """Grava (sobrescreve) o arquivo já revalidado e limpo."""

    def remover(self, bucket: str, caminho: str) -> None: ...


class ArmazenamentoFake:
    def __init__(self) -> None:
        self.arquivos: dict[tuple[str, str], bytes] = {}
        self.urls_emitidas: list[tuple[str, str, int]] = []

    def url_envio(self, bucket: str, caminho: str, content_type: str, segundos: int) -> str:
        self.urls_emitidas.append((bucket, caminho, segundos))
        return f"https://storage.invalid/{bucket}/{caminho}?expira={segundos}"

    def simular_envio(self, bucket: str, caminho: str, dados: bytes) -> None:
        """O que o app faria com a URL assinada."""
        self.arquivos[(bucket, caminho)] = dados

    def ler(self, bucket: str, caminho: str) -> bytes:
        try:
            return self.arquivos[(bucket, caminho)]
        except KeyError:
            raise ArquivoNaoEncontrado(caminho) from None

    def gravar(self, bucket: str, caminho: str, dados: bytes, content_type: str) -> None:
        self.arquivos[(bucket, caminho)] = dados

    def remover(self, bucket: str, caminho: str) -> None:
        self.arquivos.pop((bucket, caminho), None)


class ArmazenamentoSupabase:
    """Adaptador do Storage do Supabase (REST). Usa a chave de serviço, só no backend."""

    def __init__(self, url: str, chave_servico: str, cliente: Any = None) -> None:
        import httpx

        self._base = url.rstrip("/") + "/storage/v1"
        self._http = cliente or httpx.Client(
            headers={"Authorization": f"Bearer {chave_servico}", "apikey": chave_servico},
            timeout=20,
        )

    def url_envio(self, bucket: str, caminho: str, content_type: str, segundos: int) -> str:
        # A URL de envio assinada do Supabase tem validade própria (não configurável por
        # chamada); a validade que vale para o Trato é a da SOLICITAÇÃO, conferida em `concluir`.
        resp = self._http.post(f"{self._base}/object/upload/sign/{bucket}/{caminho}")
        resp.raise_for_status()
        return self._base + resp.json()["url"]

    def ler(self, bucket: str, caminho: str) -> bytes:
        resp = self._http.get(f"{self._base}/object/{bucket}/{caminho}")
        if resp.status_code in (400, 404):
            raise ArquivoNaoEncontrado(caminho)
        resp.raise_for_status()
        return resp.content

    def gravar(self, bucket: str, caminho: str, dados: bytes, content_type: str) -> None:
        resp = self._http.put(
            f"{self._base}/object/{bucket}/{caminho}",
            content=dados,
            headers={"Content-Type": content_type, "x-upsert": "true"},
        )
        resp.raise_for_status()

    def remover(self, bucket: str, caminho: str) -> None:
        self._http.delete(f"{self._base}/object/{bucket}/{caminho}").raise_for_status()


def armazenamento_da_config() -> ArmazenamentoArquivos | None:
    """Supabase Storage se `SUPABASE_URL` e a chave de serviço existirem; senão `None`."""
    from trato.config import obter_config

    cfg = obter_config()
    chave = cfg.supabase_service_role_key.get_secret_value()
    if not cfg.supabase_url or not chave:
        return None
    return ArmazenamentoSupabase(cfg.supabase_url, chave)
