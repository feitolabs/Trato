"""TERMOS-BE-PROVAS (06h) no Postgres local: comprovante enviado pela equipe (`midias`), provas
na contestação de medida (`medida_contestacoes.anexos`) e campos do chamado."""

from __future__ import annotations

import struct
from datetime import UTC, datetime

import pytest

from trato.persistencia.uploads import UploadsPostgres
from trato.seguranca.config import obter_config_seguranca
from trato.uploads import ArmazenamentoFake
from trato.uploads.config import ConfigUploads
from trato.uploads.servico import ServicoUploads

from .test_ausencia_cliente_postgres import _post, justificar, painel, registrado
from .test_disputa_painel_postgres import equipe  # noqa: F401 - fixture
from .test_medidas_postgres import aplicar, limpar
from .test_pagamento_postgres import (  # noqa: F401 - `pg` e `migrations_novas` são fixtures
    VALOR_ORCAMENTO,
    linhas,
    migrations_novas,
    pg,
)
from .test_provas_ausencia_postgres import com_retencao, contestar

MOTIVO = {"motivo": "Conferir os custos do caso."}


def _bloco(tipo: bytes, dados: bytes) -> bytes:
    return struct.pack(">I", len(dados)) + tipo + dados + b"\x00\x00\x00\x00"


def _segmento(marca: int, corpo: bytes) -> bytes:
    return bytes([0xFF, marca]) + struct.pack(">H", len(corpo) + 2) + corpo


PNG = (
    b"\x89PNG\r\n\x1a\n"
    + _bloco(b"IHDR", b"\x00" * 13)
    + _bloco(b"IDAT", b"\x00\x01")
    + _bloco(b"IEND", b"")
)
JPEG = (
    b"\xff\xd8"
    + _segmento(0xE0, b"JFIF\x00\x01\x01\x00\x00\x01\x00\x01\x00\x00")
    + _segmento(0xC0, b"\x08\x00\x10\x00\x10\x01\x01\x11\x00")
    + b"\xff\xda\x00\x08\x01\x01\x00\x00\x3f\x00DADOS-DA-IMAGEM"
    + b"\xff\xd9"
)


@pytest.fixture
def arquivos(pg, monkeypatch):  # noqa: F811
    """Liga o envio de arquivos só neste teste (o app do cenário é compartilhado)."""
    servico = ServicoUploads(
        ArmazenamentoFake(),
        UploadsPostgres(pg.banco),
        obter_config_seguranca(),
        ConfigUploads(),
        lambda: datetime.now(UTC),
    )

    def ligar() -> ServicoUploads:
        monkeypatch.setattr(pg.pagto[0].app.state, "servico_uploads", servico, raising=False)
        return servico

    return ligar


def test_equipe_envia_comprovante_e_usa_na_retencao(pg, equipe, arquivos):  # noqa: F811
    pid, _ = registrado(pg, fora_dos_7_dias=True)
    justificar(pg, pid)
    servico = arquivos()
    base = f"/v1/admin/ausencias/{pid}/arquivos"
    r = _post(pg, "med_a", base, MOTIVO)
    assert r.status_code == 200, r.text
    antes = {a["arquivo_id"] for a in r.json()}  # a foto do registro da ausência já conta
    pedido = MOTIVO | {
        "nome_arquivo": "nota.jpg",
        "content_type": "image/jpeg",
        "tamanho_bytes": len(JPEG),
    }
    r = _post(pg, "med_a", f"{base}/envio", pedido)
    assert r.status_code == 201, r.text
    envio = r.json()["envio_id"]
    sol = servico.repo.solicitacao(envio)
    servico.armazenamento.simular_envio(sol.bucket, sol.caminho, JPEG)
    concluir = f"{base}/envio/{envio}/concluir"
    assert _post(pg, "med_b", concluir, MOTIVO).status_code == 404  # só quem pediu
    r = _post(pg, "med_a", concluir, MOTIVO)
    assert r.status_code == 200, r.text
    arquivo = r.json()["arquivo_id"]
    depois = {a["arquivo_id"] for a in _post(pg, "med_a", base, MOTIVO).json()}
    assert depois == antes | {arquivo}
    ((quem, finalidade),) = linhas(
        pg,
        "select enviada_por::text, finalidade from public.midias where pedido_id = %s "
        "and finalidade = 'disputa'",
        (pid,),
    )
    assert quem == pg.ids["med_a"] and finalidade == "disputa"
    r = painel(
        pg,
        pid,
        retencao_centavos=VALOR_ORCAMENTO // 10,
        retencao_justificativa="Deslocamento comprovado pela nota.",
        retencao_comprovantes=[arquivo],
    )
    assert r.status_code == 200, r.text


def test_contestacao_de_medida_guarda_os_anexos(pg, equipe, arquivos):  # noqa: F811
    limpar(pg)
    try:
        servico = arquivos()
        mid = aplicar(pg).json()["id"]
        url = f"/v1/me/medidas/{mid}/contestacao"
        corpo = {"nome_arquivo": "a.png", "content_type": "image/png", "tamanho_bytes": 200}
        r = _post(pg, "profissional", f"{url}/anexos", corpo)
        assert r.status_code == 201, r.text
        anexo = r.json()["anexo_id"]
        ((bucket, caminho, _),) = [servico.armazenamento.urls_emitidas[-1]]
        servico.armazenamento.simular_envio(bucket, caminho, PNG)
        envio = {"versao": "Foi um erro do app.", "anexos": [anexo]}
        for _ in range(2):
            r = _post(pg, "profissional", url, envio)
            assert r.status_code == 200, r.text
        assert r.json()["contestacao"]["anexos"][0]["anexo_id"] == anexo
        ((guardados,),) = linhas(
            pg, "select anexos from public.medida_contestacoes where medida_id = %s", (mid,)
        )
        assert guardados[0]["caminho"].startswith("contestacao-medida/")
        assert guardados[0]["caminho"] != caminho
        abrir = f"/v1/admin/medidas/{mid}/contestacao/anexos/abrir"
        r = _post(pg, "adm_b", abrir, MOTIVO)
        assert r.status_code == 200 and r.json()[0]["url"], r.text
        visto = pg.pagto[0].get(f"/v1/admin/medidas/{mid}", headers=pg.token("adm_b")).json()
        assert visto["aplicada_por_nome"] == "adm_a"
    finally:
        limpar(pg)


def test_chamado_da_retencao_marcado_e_com_responsavel(pg, equipe):  # noqa: F811
    pid = com_retencao(pg)
    assert contestar(pg, pid).status_code == 200
    url = f"/v1/admin/chamados?pedido_id={pid}"
    (item,) = pg.pagto[0].get(url, headers=pg.token("adm_a")).json()["itens"]
    assert item["contestacao_retencao"] is True and item["responsavel_nome"] is None
    r = _post(pg, "adm_a", f"/v1/admin/chamados/{item['id']}/assumir", {})
    assert r.status_code == 200 and r.json()["responsavel_nome"] == "adm_a", r.text
    meus = pg.pagto[0].get("/v1/sac/chamados", headers=pg.token("cliente")).json()
    achado = next(c for c in meus["itens"] if c["id"] == item["id"])
    assert achado["contestacao_retencao"] is True and "responsavel" not in str(achado)
