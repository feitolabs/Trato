"""B30: avisar quem perdeu quando o cliente ACEITA outro orçamento (ORCAMENTO_NAO_ESCOLHIDO)."""

from __future__ import annotations

from dataclasses import replace

import pytest
from conftest import OUTRO_PROFISSIONAL, PROFISSIONAL, cab

from trato.api.repositorios import DadosPedido, Orcamento
from trato.notificacoes import ligar_ao_contexto
from trato.notificacoes.canais import Canais, CanalApp
from trato.notificacoes.config import ConfigNotificacoes
from trato.notificacoes.eventos import MODELOS, Evento
from trato.notificacoes.repositorio import RepositorioEmMemoria
from trato.notificacoes.servico import ServicoNotificacoes
from trato.pedidos.estados import Estado as E

GANHADOR, PERDEDOR_B, PERDEDOR_C = PROFISSIONAL.id, OUTRO_PROFISSIONAL.id, "pro-c"
TITULO = "Cliente escolheu outro orçamento"
CORPO = "Desta vez não foi o seu orçamento. Veja outros pedidos abertos."


def _ligar(amb):
    repo = RepositorioEmMemoria()
    notif = ServicoNotificacoes(repo, Canais(app=CanalApp()), ConfigNotificacoes(ativo=True))
    ligar_ao_contexto(amb.cliente.app, amb.contexto, notif)
    amb.cliente.app.state.notificador = notif
    return repo


def _pedido_com_tres_orcamentos(amb):
    amb.semear_pedido(E.ABERTO)
    amb.contexto.pedidos._dados["ped-1"] = DadosPedido("cat-1", "cid", "Pintar", "Sala")
    for oid, pro, valor in (
        ("orc-a", GANHADOR, 11_100),
        ("orc-b", PERDEDOR_B, 22_200),
        ("orc-c", PERDEDOR_C, 33_300),
    ):
        amb.contexto.orcamentos.adicionar(Orcamento(oid, "ped-1", pro, valor, "cat-1"))


def _aceitar(amb, orcamento_id="orc-a"):
    return amb.cliente.post(
        "/v1/pedidos/ped-1/acoes/aceitar_orcamento",
        json={"prova": {"orcamento_id": orcamento_id}},
        headers=cab("t-cliente"),
    )


def _avisos(repo, usuario, titulo=TITULO):
    return [n for n in repo.listar(usuario, False, 50) if n.titulo == titulo]


def test_modelo_do_evento_texto_categoria_e_destino_do_recusado():
    novo, antigo = MODELOS[Evento.ORCAMENTO_NAO_ESCOLHIDO], MODELOS[Evento.ORCAMENTO_RECUSADO]
    assert (novo.titulo, novo.corpo) == (TITULO, CORPO)
    assert (novo.categoria, novo.tela, novo.essencial) == (
        antigo.categoria,
        antigo.tela,
        antigo.essencial,
    )
    assert novo.categoria.value == "orcamentos" and novo.tela == "pedido_aberto"


def test_aceitar_um_avisa_cada_perdedor_uma_vez_e_o_vencedor_nao(amb):
    repo = _ligar(amb)
    _pedido_com_tres_orcamentos(amb)
    r = _aceitar(amb)
    assert r.status_code == 200, r.text
    assert len(_avisos(repo, PERDEDOR_B)) == 1 and len(_avisos(repo, PERDEDOR_C)) == 1
    assert _avisos(repo, GANHADOR) == []
    assert _avisos(repo, GANHADOR, "Orçamento aceito")  # o vencedor segue com o aviso de aceite
    assert _avisos(repo, PERDEDOR_B, "Orçamento recusado") == []  # não é a recusa individual
    aviso = _avisos(repo, PERDEDOR_B)[0]
    assert aviso.corpo == CORPO
    texto = f"{aviso.titulo} {aviso.corpo}"
    assert not any(c.isdigit() for c in texto) and "R$" not in texto  # sem valores
    for nome in ("Cliente Teste", "Ana", GANHADOR):
        assert nome not in texto


def test_aceitar_de_novo_e_reenvio_nao_duplicam(amb):
    from trato.api.avisos import avisar_orcamentos_nao_escolhidos

    repo = _ligar(amb)
    _pedido_com_tres_orcamentos(amb)
    assert _aceitar(amb).status_code == 200
    assert _aceitar(amb).status_code >= 400  # pedido já aceito: nada novo sai
    avisar_orcamentos_nao_escolhidos(
        SimpleRequest(amb.cliente.app),
        amb.contexto,
        pedido_id="ped-1",
        perdedores=[("orc-b", PERDEDOR_B), ("orc-c", PERDEDOR_C)],
        vencedor_orcamento_id="orc-a",
        vencedor_profissional_id=GANHADOR,
    )  # reenvio da mesma lista
    assert len(_avisos(repo, PERDEDOR_B)) == 1 and len(_avisos(repo, PERDEDOR_C)) == 1


class SimpleRequest:
    def __init__(self, app):
        self.app = app


def test_recusa_individual_continua_so_com_orcamento_recusado(amb):
    repo = _ligar(amb)
    _pedido_com_tres_orcamentos(amb)
    r = amb.cliente.post("/v1/pedidos/ped-1/orcamentos/orc-b/recusar", headers=cab("t-cliente"))
    assert r.status_code == 200, r.text
    assert len(_avisos(repo, PERDEDOR_B, "Orçamento recusado")) == 1
    assert _avisos(repo, PERDEDOR_B) == []  # nada de "escolheu outro"
    assert _avisos(repo, PERDEDOR_C) == []


def test_falha_ao_notificar_nao_desfaz_o_aceite(amb, monkeypatch):
    _ligar(amb)
    _pedido_com_tres_orcamentos(amb)
    original = ServicoNotificacoes.notificar

    def quebra(self, evento, *a, **k):
        if evento is Evento.ORCAMENTO_NAO_ESCOLHIDO:
            raise RuntimeError("canal fora do ar")
        return original(self, evento, *a, **k)

    monkeypatch.setattr(ServicoNotificacoes, "notificar", quebra)
    r = _aceitar(amb)
    assert r.status_code == 200, r.text
    assert amb.contexto.pedidos.obter("ped-1").estado is E.ORCAMENTO_ACEITO
    assert amb.contexto.contratos.obter_do_pedido("ped-1") is not None


@pytest.mark.parametrize("vencedor,perdem", [("orc-b", {GANHADOR, PERDEDOR_C})])
def test_vale_para_qualquer_vencedor(amb, vencedor, perdem):
    repo = _ligar(amb)
    _pedido_com_tres_orcamentos(amb)
    assert _aceitar(amb, vencedor).status_code == 200
    com_aviso = {u for u in (GANHADOR, PERDEDOR_B, PERDEDOR_C) if _avisos(repo, u)}
    assert com_aviso == perdem


def test_avisa_apenas_orcamentos_realmente_recusados_no_aceite(amb):
    from trato.api.repositorios_app import OrcamentoDetalhe

    repo = _ligar(amb)
    _pedido_com_tres_orcamentos(amb)
    # orc-b já foi recusado individualmente antes; orc-d está em rascunho; só orc-c está enviado.
    assert amb.contexto.orcamentos.recusar("ped-1", "orc-b") is True
    amb.contexto.orcamentos.adicionar(
        Orcamento("orc-d", "ped-1", "pro-d", 44_400, "cat-1"),
        OrcamentoDetalhe(
            id="orc-d",
            pedido_id="ped-1",
            profissional_id="pro-d",
            profissional_nome=None,
            versao=1,
            status="rascunho",
            valor_centavos=44_400,
            prazo_execucao_dias=None,
            validade_ate=None,
            garantia_dias=None,
            fora_do_escopo=None,
            sinal_material_centavos=None,
            observacoes=None,
            enviado_em=None,
            itens=(),
        ),
    )

    r = _aceitar(amb, "orc-a")
    assert r.status_code == 200, r.text
    assert len(_avisos(repo, PERDEDOR_C)) == 1
    assert _avisos(repo, PERDEDOR_B) == []  # já estava recusado antes do aceite
    assert _avisos(repo, "pro-d") == []  # rascunho não foi recusado pelo aceite
    assert _avisos(repo, GANHADOR) == []
    assert amb.contexto.orcamentos.detalhe("orc-a").status == "aceito"
    assert amb.contexto.orcamentos.detalhe("orc-c").status == "recusado"


def test_falha_na_transacao_nao_envia_aviso(amb, monkeypatch):
    from trato.persistencia.erros import ConflitoDeEstado

    repo = _ligar(amb)
    _pedido_com_tres_orcamentos(amb)

    def falha_salvar(*_a, **_k):
        raise ConflitoDeEstado("corrida no aceite")

    monkeypatch.setattr(amb.contexto.pedidos, "salvar", falha_salvar)
    r = _aceitar(amb, "orc-a")
    assert r.status_code == 409, r.text
    assert _avisos(repo, PERDEDOR_B) == []
    assert _avisos(repo, PERDEDOR_C) == []


def test_recusar_outro_orcamento_com_pedido_ja_aceito_da_409_humano(amb):
    _ligar(amb)
    _pedido_com_tres_orcamentos(amb)
    # orc-b segue "enviado", mas o pedido já está com outro orçamento aceito.
    pedido = amb.contexto.pedidos.obter("ped-1")
    amb.contexto.pedidos.salvar(replace(pedido, estado=E.ORCAMENTO_ACEITO))
    r = amb.cliente.post("/v1/pedidos/ped-1/orcamentos/orc-b/recusar", headers=cab("t-cliente"))
    assert r.status_code == 409, r.text
    assert r.json()["detail"] == "Este pedido já tem um orçamento aceito."


def test_aceitar_de_novo_com_pedido_ja_aceito_da_mensagem_humana(amb):
    _ligar(amb)
    _pedido_com_tres_orcamentos(amb)
    assert _aceitar(amb).status_code == 200
    r = _aceitar(amb, "orc-b")
    assert r.status_code == 409, r.text
    assert "Este pedido já tem um orçamento aceito." in r.text
