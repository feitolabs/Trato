# ruff: noqa: F811  (fixture `e2` importada de test_profissional_upload)
"""Divergências do app: reenvio offline, nota de material com `midia_id` e destino `portfolio`."""

from __future__ import annotations

from datetime import timedelta

from conftest import AGORA
from test_profissional_upload import JPEG_COM_EXIF, e2, prova_checkin  # noqa: F401

from trato.pedidos.estados import Estado

URL_IN = "/v1/pedidos/ped-1/acoes/fazer_check_in"


def _foto(e2, destino="checkin"):
    _, concluir = e2.enviar("t-prof", destino, JPEG_COM_EXIF, pedido_id="ped-1")
    return concluir.json()["midia_id"]


def _com_offline(corpo, quando):
    corpo["prova"]["offline_capturada_em"] = quando
    return corpo


# --- offline_capturada_em -----------------------------------------------------------------


def test_checkin_offline_aceita_registra_e_nao_decide(e2, amb):
    amb.semear_pedido(Estado.AGENDADO, codigo_inicio="1234")
    capturada = (AGORA - timedelta(hours=5)).isoformat()
    corpo = _com_offline(prova_checkin(_foto(e2)), capturada)
    r = e2.post(URL_IN, "t-prof", corpo)
    assert r.status_code == 200 and r.json()["estado"] == "em_andamento"
    [ev] = amb.contexto.extras["evidencias_offline"]
    assert ev["pedido_id"] == "ped-1" and ev["ator_id"] == "pro-1"
    assert ev["capturada_em_informada"].startswith("2026-10-29T07:00") and ev["acao"] == (
        "fazer_check_in"
    )
    # a hora oficial é a do servidor: o evento do pedido leva o relógio do servidor
    assert amb.contexto.pedidos.eventos("ped-1")[-1].em == AGORA


def test_checkin_offline_fora_da_janela_ou_no_futuro_e_recusado(e2, amb):
    amb.semear_pedido(Estado.AGENDADO, codigo_inicio="1234")
    mid = _foto(e2)
    velha = (AGORA - timedelta(hours=73)).isoformat()
    r = e2.post(URL_IN, "t-prof", _com_offline(prova_checkin(mid), velha))
    assert r.status_code == 422 and "janela" in r.json()["detail"]
    futuro = (AGORA + timedelta(hours=1)).isoformat()
    r = e2.post(URL_IN, "t-prof", _com_offline(prova_checkin(mid), futuro))
    assert r.status_code == 422 and "futuro" in r.json()["detail"]
    for ruim in ("ontem", "2026-10-29T10:00:00", 123):  # sem fuso também é recusado
        r = e2.post(URL_IN, "t-prof", _com_offline(prova_checkin(mid), ruim))
        assert r.status_code == 422
    assert "evidencias_offline" not in amb.contexto.extras
    assert amb.contexto.pedidos.obter("ped-1").estado is Estado.AGENDADO


def test_offline_nao_vale_fora_de_checkin_e_checkout(e2, amb):
    amb.semear_pedido(Estado.AGENDADO)
    r = e2.post(
        "/v1/pedidos/ped-1/acoes/cancelar",
        "t-cliente",
        {"prova": {"motivo": "desisti", "offline_capturada_em": AGORA.isoformat()}},
    )
    assert r.status_code == 422  # campo desconhecido continua recusado


def test_checkout_offline(e2, amb):
    amb.semear_pedido(Estado.EM_ANDAMENTO, codigo_conclusao="4321")
    mid = _foto(e2, "checkout")
    corpo = {
        "prova": {
            "foto_final": {"arquivo_id": mid, "tirada_em": AGORA.isoformat()},
            "codigo_conclusao": "4321",
            "offline_capturada_em": (AGORA - timedelta(minutes=30)).isoformat(),
        }
    }
    r = e2.post("/v1/pedidos/ped-1/acoes/fazer_check_out", "t-prof", corpo)
    assert r.status_code == 200 and r.json()["estado"] == "em_confirmacao"
    assert amb.contexto.extras["evidencias_offline"][0]["acao"] == "fazer_check_out"


# --- nota de material com midia_id --------------------------------------------------------

ITENS = [{"descricao": "Cano", "quantidade": "2", "valor_unitario_centavos": 1500}]


def test_nota_material_com_midia_id_do_upload(e2, amb):
    amb.semear_pedido(Estado.EM_ANDAMENTO)
    mid = _foto(e2, "nota_material")
    url = "/v1/contratos/ped-1/notas-material"
    r = e2.post(url, "t-prof", {"midia_id": mid, "itens": ITENS})
    assert r.status_code == 201, r.text
    assert r.json()["total_centavos"] == 3000
    guardada = amb.contexto.notas_material.do_pedido("ped-1")[0]
    assert guardada.foto_storage_path == e2.repo.midia(mid).storage_path  # caminho real da foto


def test_nota_material_recusa_midia_alheia_errada_ou_inventada(e2, amb):
    amb.semear_pedido(Estado.EM_ANDAMENTO)
    url = "/v1/contratos/ped-1/notas-material"
    outra_finalidade = _foto(e2, "durante")
    for mid in ("inventado", outra_finalidade):
        r = e2.post(url, "t-prof", {"midia_id": mid, "itens": ITENS})
        assert r.status_code == 422, mid
    # mídia de outro pedido
    amb.semear_pedido(Estado.EM_ANDAMENTO, id="ped-2")
    _, c = e2.enviar("t-prof", "nota_material", JPEG_COM_EXIF, pedido_id="ped-2")
    r = e2.post(url, "t-prof", {"midia_id": c.json()["midia_id"], "itens": ITENS})
    assert r.status_code == 422
    # mídia de outra pessoa: o cliente nem consegue gerar mídia de nota (403 no upload)
    assert amb.contexto.notas_material.do_pedido("ped-1") == ()


def test_nota_material_exige_um_dos_dois_e_mantem_o_caminho(e2, amb):
    amb.semear_pedido(Estado.EM_ANDAMENTO)
    url = "/v1/contratos/ped-1/notas-material"
    assert e2.post(url, "t-prof", {"itens": ITENS}).status_code == 422
    ambos = {"midia_id": "x", "foto_storage_path": "ped-1/a.jpg", "itens": ITENS}
    assert e2.post(url, "t-prof", ambos).status_code == 422
    r = e2.post(url, "t-prof", {"foto_storage_path": "ped-1/a.jpg", "itens": ITENS})
    assert r.status_code == 201


# --- destino portfolio --------------------------------------------------------------------


def test_upload_de_portfolio_so_imagem_sem_exif_e_so_profissional(e2, amb):
    pedir, concluir = e2.enviar("t-prof", "portfolio", JPEG_COM_EXIF)
    assert pedir.status_code == 201 and concluir.status_code == 200
    sol = e2.repo.solicitacao(pedir.json()["upload_id"])
    assert sol.caminho.startswith("pro-1/portfolio/") and sol.status == "concluida"
    gravado = e2.armazenamento.ler(sol.bucket, sol.caminho)
    assert b"GPS" not in gravado and b"DADOS-DA-IMAGEM" in gravado
    # cliente não envia portfólio; PDF não é imagem; pedido_id não se aplica
    assert e2.enviar("t-cliente", "portfolio", JPEG_COM_EXIF)[0].status_code == 403
    pdf = e2.enviar("t-prof", "portfolio", b"%PDF-1.4\n", nome="a.pdf", tipo="application/pdf")[0]
    assert pdf.status_code == 422
    com_pedido = e2.enviar("t-prof", "portfolio", JPEG_COM_EXIF, pedido_id="ped-1")[0]
    assert com_pedido.status_code == 422


def test_upload_de_portfolio_respeita_o_limite_da_configuracao(e2, amb):
    limite = e2.servico.seguranca.uploads["portfolio"].tamanho_max_bytes
    corpo = {
        "destino": "portfolio",
        "nome_arquivo": "a.jpg",
        "content_type": "image/jpeg",
        "tamanho_bytes": limite + 1,
    }
    assert e2.post("/v1/uploads", "t-prof", corpo).status_code == 422
