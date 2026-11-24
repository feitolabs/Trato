"""GET /v1/pedidos/{id}/recibo.pdf: comprovante do pedido concluído."""

from __future__ import annotations

from conftest import AGORA, cab

from trato.pedidos.estados import Estado

URL = "/v1/pedidos/ped-1/recibo.pdf"


def _concluido(amb):
    amb.semear_pedido(Estado.CONCLUIDO, concluido_em=AGORA)
    amb.semear_dinheiro(90_000, taxa=7_500)  # contrato de R$ 1.000,00; cliente pagou R$ 900,00


def test_cliente_e_profissional_baixam_o_pdf(amb):
    _concluido(amb)
    for token in ("t-cliente", "t-prof"):
        r = amb.cliente.get(URL, headers=cab(token))
        assert r.status_code == 200, r.text
        assert r.content.startswith(b"%PDF-")
        assert r.headers["content-type"] == "application/pdf"
        assert r.headers["cache-control"] == "no-store"
        assert r.headers["content-disposition"].startswith('attachment; filename="recibo-trato-')


def test_pdf_so_mostra_o_que_e_de_cada_parte(amb):
    _concluido(amb)
    cli = amb.cliente.get(URL, headers=cab("t-cliente")).content
    pro = amb.cliente.get(URL, headers=cab("t-prof")).content
    assert b"Total pago por voc" in cli and b"Taxa do Trato" not in cli
    assert b"Taxa do Trato" in pro and b"Total pago por voc" not in pro


def test_terceiro_recebe_404_e_sem_login_401(amb):
    _concluido(amb)
    assert amb.cliente.get(URL, headers=cab("t-outro-cliente")).status_code == 404
    assert amb.cliente.get(URL, headers=cab("t-outro-prof")).status_code == 404
    assert amb.cliente.get(URL).status_code == 401


def test_pedido_nao_concluido_da_409(amb):
    amb.semear_pedido(Estado.EM_ANDAMENTO)
    r = amb.cliente.get(URL, headers=cab("t-cliente"))
    assert r.status_code == 409
    assert r.json()["detail"] == "O comprovante fica disponível após a conclusão do serviço."


def test_pedido_inexistente_404(amb):
    assert amb.cliente.get(URL, headers=cab("t-cliente")).status_code == 404
