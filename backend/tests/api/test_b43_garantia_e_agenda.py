"""B43: garantia mínima (CDC) por categoria e primeiro agendamento sem a palavra "reagendamento"."""

from __future__ import annotations

from datetime import timedelta

import pytest
from conftest import AGORA, cab

from trato.api.repositorios import DadosPedido
from trato.api.rotas_profissional_cadastro import modulo_em_memoria
from trato.garantias import ConfigGarantia, abrir_garantia
from trato.garantias.config import SLUGS_DURAVEIS, SLUGS_NAO_DURAVEIS, garantia_minima_do_slug
from trato.notificacoes import ligar_ao_contexto
from trato.notificacoes.canais import Canais, CanalApp
from trato.notificacoes.config import ConfigNotificacoes
from trato.notificacoes.repositorio import RepositorioEmMemoria
from trato.notificacoes.servico import ServicoNotificacoes
from trato.pedidos.estados import Estado, Janela

H = timedelta(hours=1)
D = timedelta(days=1)


# --- garantia mínima ---------------------------------------------------------------------------


@pytest.mark.parametrize(
    ("slug", "dias"),
    [
        ("eletricista", 90),
        ("encanador", 90),
        ("pintura-interna", 90),
        ("reparos-gerais", 90),
        ("montagem-de-moveis", 90),
        ("diarista", 30),
        ("limpeza-residencial", 30),
        ("limpeza-especial", 30),
        ("jardinagem", 30),
        ("mudanca-frete", 30),
        ("categoria-nova", 30),
        (None, 30),
    ],
)
def test_minimo_por_slug(slug, dias):
    assert garantia_minima_do_slug(slug) == dias
    assert not SLUGS_DURAVEIS & SLUGS_NAO_DURAVEIS


def _catalogo(amb):
    modulo = modulo_em_memoria(amb.cliente.app)
    modulo.catalogo.categorias.update({"c-pint": "pintura-interna", "c-limp": "diarista"})
    modulo.catalogo.nomes.update({"c-pint": "Pintura interna", "c-limp": "Diarista"})


def test_catalogo_publica_o_minimo_de_cada_categoria(amb):
    _catalogo(amb)
    itens = amb.cliente.get("/v1/catalogo/categorias", headers=cab("t-cliente")).json()
    assert {i["slug"]: i["garantia_minima_dias"] for i in itens} == {
        "pintura-interna": 90,
        "diarista": 30,
    }


def _pedido_aberto(amb, categoria: str):
    pedido = amb.semear_pedido(Estado.ABERTO, orcamento_id=None, profissional_id=None)
    amb.contexto.pedidos.salvar(
        pedido, None, DadosPedido(categoria, "div", "Serviço", "Descrição do serviço")
    )


def _orcar(amb, garantia):
    corpo = {
        "fora_do_escopo": "Materiais não incluídos.",
        "prazo_execucao_dias": 3, "validade_ate": "2099-01-01T00:00:00Z", "garantia_dias": 90,
        "itens": [
            {"tipo": "horas", "descricao": "Mão de obra", "quantidade": 1,
             "valor_unitario_centavos": 10_000}
        ]
    }  # fmt: skip
    if garantia is not None:
        corpo["garantia_dias"] = garantia
    return amb.cliente.post("/v1/pedidos/ped-1/orcamentos", json=corpo, headers=cab("t-prof"))


@pytest.mark.parametrize(
    ("categoria", "abaixo", "minimo"), [("c-pint", 89, 90), ("c-limp", 29, 30), ("c-pint", 0, 90)]
)
def test_orcamento_com_garantia_abaixo_do_minimo_da_422(amb, categoria, abaixo, minimo):
    _catalogo(amb)
    _pedido_aberto(amb, categoria)
    r = _orcar(amb, abaixo)
    assert r.status_code == 422, r.text
    assert r.json()["detail"] == (
        f"A garantia mínima para este serviço é de {minimo} dias (Código de Defesa do Consumidor)."
    )
    assert _orcar(amb, minimo).status_code == 201


def test_orcamento_sem_garantia_informada_e_recusado(amb):
    _catalogo(amb)
    _pedido_aberto(amb, "c-pint")
    corpo = {
        "prazo_execucao_dias": 3,
        "validade_ate": "2099-01-01T00:00:00Z",
        "itens": [
            {"tipo": "horas", "descricao": "Mão de obra", "quantidade": 1,
             "valor_unitario_centavos": 10_000}
        ],
    }  # fmt: skip
    r = amb.cliente.post("/v1/pedidos/ped-1/orcamentos", json=corpo, headers=cab("t-prof"))
    assert r.status_code == 422 and "garantia_dias" in r.text  # Termos 5.2


def test_garantia_aberta_nunca_fica_abaixo_do_piso():
    cfg = ConfigGarantia(
        garantia_dias_por_categoria={"c": 15}, minimo_dias_por_categoria={"c": 30, "d": 90}
    )
    assert abrir_garantia(AGORA, "c", cfg).dias == 30  # padrão da categoria abaixo do piso
    assert abrir_garantia(AGORA, "d", cfg, dias_contrato=30).dias == 90  # contrato antigo
    assert abrir_garantia(AGORA, "d", cfg, dias_contrato=180).dias == 180  # promessa maior vale
    assert abrir_garantia(AGORA, "x", cfg).dias == cfg.garantia_dias_padrao  # sem piso: igual


# --- primeiro agendamento x reagendamento -----------------------------------------------------


def _avisos(amb):
    repo = RepositorioEmMemoria()
    notif = ServicoNotificacoes(repo, Canais(app=CanalApp()), ConfigNotificacoes(ativo=True))
    ligar_ao_contexto(amb.cliente.app, amb.contexto, notif)
    amb.cliente.app.state.notificador = notif
    return repo


def _propor(amb, quem="t-prof"):
    r = amb.cliente.post(
        "/v1/pedidos/ped-1/reagendamentos",
        json={
            "nova_janela_inicio": (AGORA + 3 * D).isoformat(),
            "nova_janela_fim": (AGORA + 3 * D + 2 * H).isoformat(),
        },
        headers=cab(quem),
    )
    assert r.status_code == 201, r.text
    return r.json()["id"]


def test_primeiro_agendamento_fala_em_agendado_e_o_pedido_fica_agendado(amb):
    repo = _avisos(amb)
    amb.semear_pedido(Estado.PAGO_E_RETIDO)  # pago e ainda sem horário
    rid = _propor(amb)
    amb.cliente.post(f"/v1/pedidos/ped-1/reagendamentos/{rid}/aceitar", headers=cab("t-cliente"))
    assert amb.contexto.pedidos.obter("ped-1").estado is Estado.AGENDADO
    textos = [
        f"{n.titulo} {n.corpo}" for u in ("cli-1", "pro-1") for n in repo.listar(u, False, 10)
    ]
    assert any("Serviço agendado" in t for t in textos)
    assert any("Horário proposto para o serviço" in t for t in textos)
    assert not any("eagendamento" in t for t in textos), textos


def test_recusa_do_primeiro_horario_nao_diz_que_havia_horario_combinado(amb):
    repo = _avisos(amb)
    amb.semear_pedido(Estado.PAGO_E_RETIDO)
    rid = _propor(amb)
    amb.cliente.post(f"/v1/pedidos/ped-1/reagendamentos/{rid}/recusar", headers=cab("t-cliente"))
    textos = [f"{n.titulo} {n.corpo}" for n in repo.listar("pro-1", False, 10)]
    assert any("ainda não há horário marcado" in t for t in textos)
    assert not any("continua o mesmo" in t for t in textos)


def test_remarcar_um_pedido_ja_agendado_continua_como_reagendamento(amb):
    repo = _avisos(amb)
    amb.semear_pedido(Estado.AGENDADO, janela=Janela(AGORA + D, AGORA + D + 2 * H))
    rid = _propor(amb)
    amb.cliente.post(f"/v1/pedidos/ped-1/reagendamentos/{rid}/aceitar", headers=cab("t-cliente"))
    textos = [
        f"{n.titulo} {n.corpo}" for u in ("cli-1", "pro-1") for n in repo.listar(u, False, 10)
    ]
    assert any("Reagendamento aceito" in t for t in textos)
    assert any("Pedido de reagendamento" in t for t in textos)
