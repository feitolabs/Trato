"""Cabeçalhos, CORS, tamanho do corpo, limite de taxa, upload e logs."""

from __future__ import annotations

import logging

import pytest
from ambiente_seg import cab, montar
from pydantic import ValidationError

from trato.seguranca import upload
from trato.seguranca.config import ConfigSeguranca
from trato.seguranca.logs import instalar_filtro_logs, redigir


def test_cabecalhos_de_seguranca_em_toda_resposta():
    r = montar().cliente.get("/v1/me", headers=cab("t-cli"))
    assert r.headers["x-content-type-options"] == "nosniff"
    assert r.headers["x-frame-options"] == "DENY"
    assert r.headers["referrer-policy"] == "no-referrer"
    assert "frame-ancestors 'none'" in r.headers["content-security-policy"]
    assert r.headers["cache-control"] == "no-store"
    assert len(r.headers["x-request-id"]) == 32


def test_documentacao_da_api_continua_carregando_scripts():
    r = montar().cliente.get("/docs")
    assert r.status_code == 200
    assert "content-security-policy" not in r.headers
    assert r.headers["x-content-type-options"] == "nosniff"


# --- CORS ------------------------------------------------------------------------------


def test_cors_desligado_por_padrao():
    r = montar().cliente.get("/v1/me", headers={"Origin": "https://qualquer.com"})
    assert "access-control-allow-origin" not in r.headers


def test_cors_so_para_origens_configuradas():
    amb = montar(cors_origens=["https://painel.exemplo.com.br/"])
    ok = amb.cliente.options(
        "/v1/me",
        headers={"Origin": "https://painel.exemplo.com.br", "Access-Control-Request-Method": "GET"},
    )
    assert ok.headers["access-control-allow-origin"] == "https://painel.exemplo.com.br"
    assert "access-control-allow-credentials" not in ok.headers
    mau = amb.cliente.options(
        "/v1/me",
        headers={"Origin": "https://mal.com", "Access-Control-Request-Method": "GET"},
    )
    assert "access-control-allow-origin" not in mau.headers


@pytest.mark.parametrize("origem", ["*", "null"])
def test_cors_com_curinga_e_recusado_na_configuracao(origem: str):
    with pytest.raises(ValidationError):
        ConfigSeguranca(_env_file=None, cors_origens=[origem])


# --- Tamanho do corpo ------------------------------------------------------------------


def test_corpo_acima_do_limite_e_recusado_pelo_content_length():
    amb = montar(corpo_max_bytes=100)
    r = amb.cliente.post("/v1/me/consentimentos", content=b"x" * 500, headers=cab("t-cli"))
    assert r.status_code == 413
    assert r.json()["detail"] == "Requisição grande demais."
    assert r.headers["x-content-type-options"] == "nosniff"


def test_corpo_em_pedacos_tambem_e_contado():
    amb = montar(corpo_max_bytes=100)

    def pedacos():
        for _ in range(10):
            yield b"y" * 50

    r = amb.cliente.post("/v1/me/consentimentos", content=pedacos(), headers=cab("t-cli"))
    assert r.status_code == 413


def test_limite_por_prefixo_vence_o_geral():
    amb = montar(corpo_max_bytes=10, corpo_max_por_prefixo={"/v1/me/consentimentos": 5000})
    corpo = {"finalidade": "comunicacoes_marketing", "aceito": True, "versao_texto": "v1"}
    assert (
        amb.cliente.post("/v1/me/consentimentos", json=corpo, headers=cab("t-cli")).status_code
        == 201
    )


# --- Limite de taxa --------------------------------------------------------------------

REGRA = {"nome": "teste", "prefixo": "/v1/me", "escopo": "usuario", "maximo": 3, "janela_s": 60}


def test_limite_por_usuario_responde_429_com_retry_after():
    amb = montar(limites=[REGRA])
    for _ in range(3):
        assert amb.cliente.get("/v1/me", headers=cab("t-cli")).status_code != 429
    r = amb.cliente.get("/v1/me", headers=cab("t-cli"))
    assert r.status_code == 429 and int(r.headers["retry-after"]) > 0
    assert "Muitas tentativas" in r.json()["detail"]
    # outro usuário não é afetado, e depois da janela o primeiro volta
    assert amb.cliente.get("/v1/me", headers=cab("t-outro")).status_code != 429
    amb.relogio.avancar(seconds=61)
    assert amb.cliente.get("/v1/me", headers=cab("t-cli")).status_code != 429
    assert "antifraude.limite_taxa_excedido" in amb.auditoria


def test_limite_por_ip_vale_sem_login():
    amb = montar(limites=[{**REGRA, "escopo": "ip", "prefixo": "/v1/seguranca"}])
    codigos = [amb.cliente.get("/v1/seguranca/flags").status_code for _ in range(5)]
    assert codigos[:3] == [401] * 3 and codigos[3:] == [429, 429]


def test_bloqueio_temporario_dura_alem_da_janela():
    amb = montar(limites=[{**REGRA, "bloqueio_s": 600}])
    for _ in range(4):
        amb.cliente.get("/v1/me", headers=cab("t-cli"))
    amb.relogio.avancar(seconds=120)  # a janela de 60 s já passou, o bloqueio (600 s) não
    assert amb.cliente.get("/v1/me", headers=cab("t-cli")).status_code == 429
    amb.relogio.avancar(seconds=600)
    assert amb.cliente.get("/v1/me", headers=cab("t-cli")).status_code != 429


def test_limitador_pode_ser_desligado_e_auditoria_nao_enche():
    amb = montar(limites=[REGRA])
    for _ in range(30):
        amb.cliente.get("/v1/me", headers=cab("t-cli"))
    assert amb.auditoria.count("antifraude.limite_taxa_excedido") == 1
    livre = montar(limites=[REGRA], limite_taxa_ativo=False)
    assert all(
        livre.cliente.get("/v1/me", headers=cab("t-cli")).status_code != 429 for _ in range(10)
    )


def test_x_forwarded_for_so_vale_se_configurado():
    regra = {**REGRA, "escopo": "ip", "maximo": 1}
    sem = montar(limites=[regra])
    sem.cliente.get("/v1/me", headers={"X-Forwarded-For": "1.1.1.1"})
    # ignorado: o IP é o do socket, então o cabeçalho forjado não escapa do limite
    assert sem.cliente.get("/v1/me", headers={"X-Forwarded-For": "2.2.2.2"}).status_code == 429
    com = montar(limites=[regra], confiar_x_forwarded_for=True)
    com.cliente.get("/v1/me", headers={"X-Forwarded-For": "1.1.1.1"})
    assert com.cliente.get("/v1/me", headers={"X-Forwarded-For": "2.2.2.2"}).status_code != 429


# --- Upload ----------------------------------------------------------------------------

CFG = ConfigSeguranca(_env_file=None)
JPEG = b"\xff\xd8\xff\xe0" + b"\x00" * 20


def test_upload_valido_devolve_nome_seguro():
    nome = upload.validar_metadados(CFG, "foto", "image/jpeg", 1000, "minha foto.JPG")
    assert nome.endswith(".jpg") and "minha" not in nome


@pytest.mark.parametrize(
    ("categoria", "tipo", "tamanho", "nome"),
    [
        ("foto", "application/x-msdownload", 10, "a.exe"),
        ("foto", "application/pdf", 10, "a.pdf"),  # pdf não vale para foto
        ("foto", "image/png", 6 * 1024 * 1024, "a.png"),
        ("foto", "image/png", 0, "a.png"),
        ("foto", "image/png", 10, "../a.png"),
        ("foto", "image/png", 10, "a.php"),
        ("foto", "image/png", 10, "a/b.png"),
        ("inexistente", "image/png", 10, "a.png"),
    ],
)
def test_upload_invalido(categoria: str, tipo: str, tamanho: int, nome: str):
    with pytest.raises(upload.ErroUpload):
        upload.validar_metadados(CFG, categoria, tipo, tamanho, nome)


def test_conteudo_precisa_bater_com_o_tipo_declarado():
    upload.validar_conteudo(CFG, "foto", "image/jpeg", JPEG)
    with pytest.raises(upload.ErroUpload):
        upload.validar_conteudo(CFG, "foto", "image/jpeg", b"MZ\x90\x00 programa.exe")
    with pytest.raises(upload.ErroUpload):
        upload.validar_conteudo(CFG, "foto", "image/png", JPEG)
    with pytest.raises(upload.ErroUpload):
        upload.validar_conteudo(CFG, "documento", "application/pdf", b"%PDF-1.7 ok" + b"0" * 20)
        upload.validar_conteudo(CFG, "foto", "application/pdf", b"%PDF-1.7")


def test_limites_de_upload_vem_da_configuracao():
    pequeno = ConfigSeguranca(
        _env_file=None, uploads={"foto": {"tipos": ["image/png"], "tamanho_max_bytes": 10}}
    )
    with pytest.raises(upload.ErroUpload):
        upload.validar_metadados(pequeno, "foto", "image/png", 11, "a.png")


def test_rota_de_validacao_de_upload():
    amb = montar()
    corpo = {
        "categoria": "foto",
        "content_type": "image/png",
        "tamanho_bytes": 100,
        "nome": "a.png",
    }
    ok = amb.cliente.post("/v1/seguranca/uploads/validar", json=corpo, headers=cab("t-cli"))
    assert ok.status_code == 200 and ok.json()["nome_seguro"].endswith(".png")
    ruim = amb.cliente.post(
        "/v1/seguranca/uploads/validar",
        json={**corpo, "content_type": "text/html"},
        headers=cab("t-cli"),
    )
    assert ruim.status_code == 422


# --- Logs sem dado pessoal ---------------------------------------------------------------


@pytest.mark.parametrize(
    "texto",
    [
        "usuario joao@gmail.com entrou",
        "cpf 123.456.789-09 consultado",
        "cpf 12345678909",
        "tel +55 11 98765-4321",
        "tel (11) 98765-4321",
        "Authorization: Bearer abc.def-123_456",
        "token eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxMjM0NTY3ODkwIn0.sig_nature123",
        "GET /v1/x?token=segredo123&cpf=12345678909 200",
    ],
)
def test_redigir_remove_dado_pessoal(texto: str):
    saida = redigir(texto)
    for sensivel in (
        "joao@gmail",
        "123.456.789",
        "12345678909",
        "98765",
        "abc.def",
        "eyJhb",
        "segredo123",
    ):
        assert sensivel not in saida


def test_redigir_preserva_texto_comum():
    assert redigir("pedido ped-1 criado em 2026-10-29") == "pedido ped-1 criado em 2026-10-29"


def test_filtro_global_de_logs(caplog: pytest.LogCaptureFixture):
    instalar_filtro_logs()
    instalar_filtro_logs()  # idempotente
    with caplog.at_level(logging.INFO):
        logging.getLogger("trato.teste").info(
            "login de %s com cpf %s", "ana@x.com", "123.456.789-09"
        )
    assert "ana@x.com" not in caplog.text and "123.456" not in caplog.text
    assert "[email]" in caplog.text
