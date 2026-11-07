"""Links assinados do Storage: o Supabase devolve o caminho relativo a /storage/v1."""

from __future__ import annotations

import httpx
import pytest

from trato.uploads.armazenamento import ArmazenamentoSupabase, AssinadorSupabaseStorage

BASE = "https://projeto.supabase.co"


def _cliente(resposta: dict) -> httpx.Client:
    def tratar(req: httpx.Request) -> httpx.Response:
        assert req.url.path.startswith("/storage/v1/object/sign/")
        return httpx.Response(200, json=resposta)

    return httpx.Client(transport=httpx.MockTransport(tratar))


@pytest.mark.parametrize(
    ("devolvido", "esperado"),
    [
        (
            "/object/sign/verificacao/a/b.jpg?token=t",
            f"{BASE}/storage/v1/object/sign/verificacao/a/b.jpg?token=t",
        ),
        (
            "object/sign/verificacao/a/b.jpg?token=t",
            f"{BASE}/storage/v1/object/sign/verificacao/a/b.jpg?token=t",
        ),
        ("https://cdn.exemplo/x.jpg?token=t", "https://cdn.exemplo/x.jpg?token=t"),
    ],
)
def test_assinador_do_painel_inclui_storage_v1(devolvido: str, esperado: str) -> None:
    assinador = AssinadorSupabaseStorage(
        BASE + "/", "chave", cliente=_cliente({"signedURL": devolvido})
    )
    assert assinador.assinar("/a/b.jpg", 60) == esperado


def test_url_leitura_inclui_storage_v1() -> None:
    arm = ArmazenamentoSupabase(
        BASE, "chave", cliente=_cliente({"signedUrl": "/object/sign/b/c.jpg?token=t"})
    )
    assert arm.url_leitura("b", "c.jpg", 60) == f"{BASE}/storage/v1/object/sign/b/c.jpg?token=t"
