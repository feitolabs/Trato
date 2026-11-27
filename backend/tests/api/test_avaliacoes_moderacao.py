# ruff: noqa: F811
"""TERMOS-BE-126 (12.6, 12.7 e 20.5): moderação/ocultação de avaliações e pedido de revisão."""

from __future__ import annotations

from datetime import UTC, datetime

import pytest
from admin_ambiente import adm, cab, token_de  # noqa: F401
from conftest import CLIENTE, PROFISSIONAL

from trato.api.admin.repositorios import FiltroAuditoria
from trato.api.repositorios_app import Avaliacao
from trato.persistencia.avaliacoes_moderacao import ModeracaoAvaliacoesEmMemoria

AGORA = datetime(2026, 11, 26, 15, 0, tzinfo=UTC)


def semear_avaliacoes(adm) -> tuple[str, str]:
    av1 = Avaliacao(
        pedido_id="ped-1",
        direcao="cliente_para_profissional",
        avaliador_id=CLIENTE.id,
        avaliado_id=PROFISSIONAL.id,
        nota_geral=5,
        nota_decimal=5.0,
        comentario="Excelente trabalho.",
        etiquetas=(),
        criada_em=AGORA,
    )
    av2 = Avaliacao(
        pedido_id="ped-2",
        direcao="cliente_para_profissional",
        avaliador_id=CLIENTE.id,
        avaliado_id=PROFISSIONAL.id,
        nota_geral=1,
        nota_decimal=1.0,
        comentario="Ofensa grave fora da regra.",
        etiquetas=(),
        criada_em=AGORA,
    )
    adm.contexto.avaliacoes.salvar(av1)
    adm.contexto.avaliacoes.salvar(av2)
    a1 = adm.contexto.avaliacoes.obter("ped-1", "cliente_para_profissional")
    a2 = adm.contexto.avaliacoes.obter("ped-2", "cliente_para_profissional")
    assert a1 is not None and a1.id and a2 is not None and a2.id
    return a1.id, a2.id


def test_ocultar_e_reverter_atualizam_listagem_e_media_e_auditam(adm):
    _, av2_id = semear_avaliacoes(adm)

    assert adm.contexto.avaliacoes.media_recebida(PROFISSIONAL.id) == 3.0
    assert len(adm.contexto.avaliacoes.recebidas(PROFISSIONAL.id)) == 2

    h_med = cab(token_de("mediador"))
    r = adm.cliente.post(
        f"/v1/admin/avaliacoes/{av2_id}/ocultar",
        json={
            "motivo": "ofensa_ou_ilegal",
            "explicacao": "Conteúdo ofensivo comprovado na análise.",
        },
        headers=h_med,
    )
    assert r.status_code == 201, r.text
    corpo = r.json()
    assert corpo["motivo"] == "ofensa_ou_ilegal"
    assert corpo["status_anterior"] == "publicada"
    assert corpo["revertida_em"] is None

    # Avaliação oculta sai da média e da listagem pública
    assert adm.contexto.avaliacoes.media_recebida(PROFISSIONAL.id) == 5.0
    assert len(adm.contexto.avaliacoes.recebidas(PROFISSIONAL.id)) == 1

    # Ocultar novamente = 409
    r_dup = adm.cliente.post(
        f"/v1/admin/avaliacoes/{av2_id}/ocultar",
        json={"motivo": "ofensa_ou_ilegal", "explicacao": "Repetição de ocultação."},
        headers=h_med,
    )
    assert r_dup.status_code == 409

    # Reverter restaura status, média e listagem
    r_rev = adm.cliente.post(
        f"/v1/admin/avaliacoes/{av2_id}/reverter-ocultacao",
        json={"motivo": "Contestação do autor considerada procedente."},
        headers=h_med,
    )
    assert r_rev.status_code == 200, r_rev.text
    assert r_rev.json()["revertida_em"] is not None
    assert adm.contexto.avaliacoes.media_recebida(PROFISSIONAL.id) == 3.0
    assert len(adm.contexto.avaliacoes.recebidas(PROFISSIONAL.id)) == 2

    # Reverter sem ocultação ativa = 409
    assert (
        adm.cliente.post(
            f"/v1/admin/avaliacoes/{av2_id}/reverter-ocultacao",
            json={"motivo": "Tentativa sem ocultação ativa."},
            headers=h_med,
        ).status_code
        == 409
    )

    acoes = [e.acao for e in adm.admin.auditoria.listar(FiltroAuditoria(), 50, 0)[0]]
    assert "avaliacao.ocultada" in acoes and "avaliacao.ocultacao_revertida" in acoes


def test_usuario_pede_revisao_idempotente_lista_e_equipe_decide_com_ocultacao(adm):
    _, av2_id = semear_avaliacoes(adm)

    # Cliente (quem escreveu) não pode pedir tipo=revisao (só quem foi avaliado)
    r_proib = adm.cliente.post(
        f"/v1/avaliacoes/{av2_id}/revisoes",
        json={"justificativa": "Não sou o avaliado mas quero pedir revisão."},
        headers=cab("t-cliente"),
    )
    assert r_proib.status_code == 403

    # Profissional (avaliado) pede revisão -> 201
    r1 = adm.cliente.post(
        f"/v1/avaliacoes/{av2_id}/revisoes",
        json={"justificativa": "O comentário contém ofensas pessoais previstas na 12.6."},
        headers=cab("t-prof"),
    )
    assert r1.status_code == 201, r1.text
    rev = r1.json()
    assert rev["status"] == "aberta" and rev["protocolo"].startswith("REV-")
    assert "analista_id" not in rev and "solicitante_id" not in rev

    # Repetir pedido aberto = 200 devolvendo o mesmo pedido (sem duplicar)
    r2 = adm.cliente.post(
        f"/v1/avaliacoes/{av2_id}/revisoes",
        json={"justificativa": "Reenvio do mesmo pedido enquanto aberto."},
        headers=cab("t-prof"),
    )
    assert r2.status_code == 200 and r2.json()["id"] == rev["id"]

    # Listagem do próprio usuário só mostra os dele
    minhas = adm.cliente.get("/v1/me/avaliacoes/revisoes", headers=cab("t-prof"))
    assert minhas.status_code == 200 and minhas.json()["total"] == 1
    outras = adm.cliente.get("/v1/me/avaliacoes/revisoes", headers=cab("t-cliente"))
    assert outras.status_code == 200 and outras.json()["total"] == 0

    # Admin lista, coloca em análise e decide aceitando (exige ocultar_motivo)
    h_lider = cab(token_de("lider_suporte"))
    lista = adm.cliente.get(
        "/v1/admin/avaliacoes/revisoes", params={"status": "aberta"}, headers=h_lider
    )
    assert lista.status_code == 200 and lista.json()["total"] == 1

    r_ana = adm.cliente.post(f"/v1/admin/avaliacoes/revisoes/{rev['id']}/analisar", headers=h_lider)
    assert r_ana.status_code == 200 and r_ana.json()["status"] == "em_analise"

    # Aceitar revisão sem ocultar_motivo = 422
    assert (
        adm.cliente.post(
            f"/v1/admin/avaliacoes/revisoes/{rev['id']}/decidir",
            json={"status": "aceita", "resposta": "Confirmada ofensa na avaliação."},
            headers=h_lider,
        ).status_code
        == 422
    )

    # Aceitar revisão com ocultar_motivo oculta automaticamente a avaliação
    r_dec = adm.cliente.post(
        f"/v1/admin/avaliacoes/revisoes/{rev['id']}/decidir",
        json={
            "status": "aceita",
            "resposta": "Confirmada ofensa pessoal prevista na cláusula 12.6.",
            "ocultar_motivo": "ofensa_ou_ilegal",
        },
        headers=h_lider,
    )
    assert r_dec.status_code == 200, r_dec.text
    dec = r_dec.json()
    assert dec["status"] == "aceita" and dec["ocultacao_aplicada_id"] is not None
    assert adm.contexto.avaliacoes.media_recebida(PROFISSIONAL.id) == 5.0

    # Repetir exatamente a mesma decisão = 200 idempotente; mudar decisão = 409
    assert (
        adm.cliente.post(
            f"/v1/admin/avaliacoes/revisoes/{rev['id']}/decidir",
            json={
                "status": "aceita",
                "resposta": "Confirmada ofensa pessoal prevista na cláusula 12.6.",
                "ocultar_motivo": "ofensa_ou_ilegal",
            },
            headers=h_lider,
        ).status_code
        == 200
    )
    assert (
        adm.cliente.post(
            f"/v1/admin/avaliacoes/revisoes/{rev['id']}/decidir",
            json={"status": "recusada", "resposta": "Tentativa de alterar decisão já tomada."},
            headers=h_lider,
        ).status_code
        == 409
    )


def test_contestacao_ocultacao_pelo_autor_exige_justificativa_se_mesmo_analista(adm):
    _, av2_id = semear_avaliacoes(adm)
    h_med = cab(token_de("mediador"))
    h_seg = cab(token_de("seguranca"))

    assert (
        adm.cliente.post(
            f"/v1/admin/avaliacoes/{av2_id}/ocultar",
            json={"motivo": "dados_pessoais", "explicacao": "Exposição de telefone no texto."},
            headers=h_med,
        ).status_code
        == 201
    )

    # Autor (cliente) contesta a ocultação
    r_cont = adm.cliente.post(
        f"/v1/avaliacoes/{av2_id}/revisoes",
        json={
            "tipo": "contestacao_ocultacao",
            "justificativa": "Não havia nenhum telefone ou dado pessoal no comentário.",
        },
        headers=cab("t-cliente"),
    )
    assert r_cont.status_code == 201, r_cont.text
    rev_id = r_cont.json()["id"]

    # Mesmo analista da ocultação sem justificativa = 422 (Termos 20.5)
    assert (
        adm.cliente.post(
            f"/v1/admin/avaliacoes/revisoes/{rev_id}/decidir",
            json={"status": "aceita", "resposta": "Reavaliado e sem dados pessoais."},
            headers=h_med,
        ).status_code
        == 422
    )

    # Outro analista (seguranca) aceita contestação -> reverte ocultação
    r_ok = adm.cliente.post(
        f"/v1/admin/avaliacoes/revisoes/{rev_id}/decidir",
        json={
            "status": "aceita",
            "resposta": "Sem exposição de dado pessoal; ocultação revertida.",
        },
        headers=h_seg,
    )
    assert r_ok.status_code == 200 and r_ok.json()["status"] == "aceita"
    assert adm.contexto.avaliacoes.media_recebida(PROFISSIONAL.id) == 3.0


@pytest.mark.parametrize(
    ("metodo", "caminho", "corpo", "token"),
    [
        ("GET", "/v1/me/avaliacoes/revisoes", None, "t-prof"),
        (
            "POST",
            "/v1/avaliacoes/av-1/revisoes",
            {"justificativa": "Pedido com tabela ausente no banco."},
            "t-prof",
        ),
        ("GET", "/v1/admin/avaliacoes/revisoes", None, token_de("mediador")),
        (
            "POST",
            "/v1/admin/avaliacoes/av-1/ocultar",
            {"motivo": "ofensa_ou_ilegal", "explicacao": "Sem tabela no banco."},
            token_de("mediador"),
        ),
    ],
)
def test_tabelas_ausentes_respondem_503_limpo(adm, metodo, caminho, corpo, token):
    adm.contexto.avaliacoes_moderacao = ModeracaoAvaliacoesEmMemoria(disponivel=False)
    r = adm.cliente.request(metodo, caminho, json=corpo, headers=cab(token))
    assert r.status_code == 503
