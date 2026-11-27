# ruff: noqa: F811
"""TERMOS-BE-53 (5.3): comprovante e cópia dos Termos assim que o pagamento é confirmado."""

from __future__ import annotations

from datetime import UTC, datetime, timedelta
from pathlib import Path

import pytest
from admin_ambiente import adm, cab  # noqa: F401
from conftest import CLIENTE, PROFISSIONAL

from trato import legal
from trato.api.repositorios import Contrato
from trato.pedidos.estados import Acao, Ator, Estado, Evento, Papel, Pedido, ProvaPagamento

PAGO_EM = datetime(2026, 11, 26, 15, 0, tzinfo=UTC)
ROTAS = ("", "/comprovante.pdf", "/termos.pdf")


def _semear(adm, *, estado=Estado.AGENDADO, pago_em=PAGO_EM, pid="ped-53") -> str:
    pedido = Pedido(
        id=pid,
        cliente_id=CLIENTE.id,
        profissional_id=PROFISSIONAL.id,
        estado=estado,
        aberto_em=pago_em or PAGO_EM,
        referencia_pagamento="pi_teste_53" if pago_em else None,
    )
    evento = None
    if pago_em:
        evento = Evento(
            pid,
            Acao.CONFIRMAR_PAGAMENTO,
            Estado.ORCAMENTO_ACEITO,
            estado,
            Ator(Papel.SISTEMA, "webhook"),
            pago_em,
            ProvaPagamento("pi_teste_53"),
        )
    adm.contexto.pedidos.salvar(pedido, evento)
    return pid


def _contrato(adm, pid: str) -> None:
    adm.contexto.contratos.salvar(Contrato(pid, CLIENTE.id, PROFISSIONAL.id, 12_345))


def _get(adm, pid, sufixo="", quem="t-cliente"):
    return adm.cliente.get(f"/v1/pedidos/{pid}/contratacao{sufixo}", headers=cab(quem))


@pytest.mark.parametrize("estado", [Estado.AGENDADO, Estado.CONCLUIDO, Estado.CANCELADO])
def test_cliente_recebe_comprovante_e_termos_desde_a_contratacao(adm, estado):
    pid = _semear(adm, estado=estado)
    _contrato(adm, pid)
    r = _get(adm, pid)
    assert r.status_code == 200, r.text
    corpo = r.json()
    assert corpo["termos_disponiveis"] is True and corpo["termos_versao"] == "1.1"
    for chave in ("comprovante_url", "termos_url"):
        pdf = adm.cliente.get(corpo[chave], headers=cab("t-cliente"))
        assert pdf.status_code == 200, pdf.text
        assert (
            pdf.content.startswith(b"%PDF") and "attachment" in pdf.headers["content-disposition"]
        )
        assert pdf.headers["cache-control"] == "no-store"
    comprovante = _get(adm, pid, "/comprovante.pdf").content
    assert b"123,45" in comprovante and b"pi_teste_53" in comprovante
    assert _get(adm, pid, "/comprovante.pdf").status_code == 200  # repetir não muda nada


@pytest.mark.parametrize("sufixo", ROTAS)
def test_antes_do_pagamento_409(adm, sufixo):
    pid = _semear(adm, estado=Estado.ORCAMENTO_ACEITO, pago_em=None)
    assert _get(adm, pid, sufixo).status_code == 409


@pytest.mark.parametrize("sufixo", ROTAS)
def test_so_o_cliente_do_pedido(adm, sufixo):
    pid = _semear(adm)
    _contrato(adm, pid)
    assert _get(adm, pid, sufixo, quem="t-prof").status_code == 403
    assert _get(adm, "nao-existe", sufixo).status_code == 404
    assert adm.cliente.get(f"/v1/pedidos/{pid}/contratacao{sufixo}").status_code == 401


def test_contratacao_anterior_ao_texto_guardado_nao_entrega_outra_versao(adm):
    pid = _semear(adm, pago_em=datetime(2026, 11, 10, 12, 0, tzinfo=UTC))
    _contrato(adm, pid)
    corpo = _get(adm, pid).json()
    assert corpo["termos_disponiveis"] is False
    assert corpo["termos_versao"] is None and corpo["termos_url"] is None
    assert _get(adm, pid, "/termos.pdf").status_code == 404
    assert _get(adm, pid, "/comprovante.pdf").status_code == 200


def test_vigencia_vira_no_dia_de_sao_paulo():
    virada = datetime(2026, 11, 22, 3, 0, tzinfo=UTC)  # 00:00 em Brasília
    assert legal.vigente_em(virada).versao == "1.1"
    assert legal.vigente_em(virada - timedelta(seconds=1)) is None


def test_pdf_dos_termos_nao_perde_caracteres_nem_texto():
    for versao in legal.VERSOES:
        texto = versao.texto()
        assert f"Versão {versao.versao}" in texto
        limpo = texto.replace("→", "->")
        limpo.encode("cp1252")  # a fonte do PDF desenha tudo
    pdf = documentos_termos(legal.VERSOES[-1].texto())
    assert pdf.count(b"/Type /Page ") >= 2 and b"Central de ajuda" in pdf


def documentos_termos(texto: str) -> bytes:
    from trato.financeiro.documentos_contratacao import termos_pdf

    return termos_pdf(texto)


def test_copia_do_backend_igual_a_do_app_na_mesma_versao():
    do_app = Path(__file__).parents[3] / "app" / "assets" / "legal" / "termos-de-uso.md"
    if not do_app.exists():
        pytest.skip("app não está nesta cópia do repositório")
    texto = do_app.read_text(encoding="utf-8")
    atual = legal.VERSOES[-1]
    if f"**Versão {atual.versao} " in texto:
        assert atual.texto() == texto
