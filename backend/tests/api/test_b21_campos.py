"""B21: campos opcionais de leitura, filtro de categoria (FIL-1), ponto na grade (MAP-1) e aviso
de aditivo pago."""

from __future__ import annotations

from datetime import timedelta
from types import SimpleNamespace

from conftest import AGORA, CLIENTE, PROFISSIONAL, cab
from test_fluxo_pagamento_e2e import VALOR, Fluxo, fluxo  # noqa: F401

from trato.api.localizacao import na_grade
from trato.api.modelos import AbrirPedidoIn
from trato.api.moedas import ConfigMoedas, MoedasEmMemoria, conceder_bonus_profissional
from trato.api.repositorios import DadosPedido
from trato.notificacoes import ligar_ao_contexto
from trato.notificacoes.canais import Canais, CanalApp
from trato.notificacoes.config import ConfigNotificacoes
from trato.notificacoes.eventos import Evento
from trato.notificacoes.repositorio import RepositorioEmMemoria
from trato.notificacoes.servico import ServicoNotificacoes
from trato.pagamentos.provedor import TipoEvento
from trato.pedidos.estados import Estado, Pedido
from trato.profissional.repositorio import CategoriaPublica


def _get(amb, url, quem="t-cliente"):
    return amb.cliente.get(url, headers=cab(quem))


# --- pix_disponivel ----------------------------------------------------------------------------


def test_pix_disponivel_segue_a_configuracao_e_comeca_desligado(fluxo: Fluxo, monkeypatch):  # noqa: F811
    pid = fluxo.aceitar()
    url = f"/v1/pedidos/{pid}/pagamento"

    assert fluxo.chamar("GET", url, "t-cliente").json()["pix_disponivel"] is False  # padrão

    from trato.api import rotas_app

    monkeypatch.setattr(
        rotas_app, "obter_config", lambda: SimpleNamespace(trato_pix_habilitado=True)
    )
    assert fluxo.chamar("GET", url, "t-cliente").json()["pix_disponivel"] is True


# --- /me/moedas --------------------------------------------------------------------------------


def test_moedas_valor_da_moeda_so_para_cliente_e_proxima_liberacao_do_profissional(amb):
    amb.contexto.moedas = MoedasEmMemoria(
        ConfigMoedas(ativo=True, dias_liberacao_bonus=3, bonus_avaliacao_profissional_moedas=50)
    )
    ganhou = conceder_bonus_profissional(
        amb.contexto.moedas,
        profissional_id=PROFISSIONAL.id,
        cliente_id=CLIENTE.id,
        pedido_id="ped-1",
        agora=AGORA,
    )
    assert ganhou == 50

    cli = _get(amb, "/v1/me/moedas").json()
    assert isinstance(cli["valor_moeda_centavos"], int) and cli["valor_moeda_centavos"] > 0
    pro = _get(amb, "/v1/me/moedas", "t-prof").json()
    assert pro["valor_moeda_centavos"] is None  # a moeda do profissional nunca vira desconto
    assert pro["proxima_liberacao_profissional"] == (AGORA + timedelta(days=3)).date().isoformat()
    assert cli["proxima_liberacao_profissional"] is None


# --- saldos ------------------------------------------------------------------------------------


def test_saldo_do_profissional_traz_o_retido_e_o_pedido_a_data_de_liberacao(fluxo: Fluxo):  # noqa: F811
    pid = fluxo.aceitar()
    fluxo.pagar(pid)

    assert (
        fluxo.chamar("GET", "/v1/profissionais/me/saldo", "t-prof").json()["retido_centavos"]
        == VALOR
    )
    assert fluxo.saldo(pid)["liberacao_prevista_em"] is None  # ainda não concluído

    fluxo.agendar(pid)
    fluxo.iniciar(pid)
    fluxo.encerrar_execucao(pid)
    fluxo.concluir(pid)

    assert (
        fluxo.chamar("GET", "/v1/profissionais/me/saldo", "t-prof").json()["retido_centavos"] == 0
    )
    saldo = fluxo.saldo(pid)
    assert saldo["liberacao_prevista_em"] is not None
    concluido = fluxo.ctx.pedidos.obter(pid).concluido_em
    assert saldo["liberacao_prevista_em"] > concluido.isoformat().replace("+00:00", "Z")[:19]


# --- categoria_nome e ja_avaliou ---------------------------------------------------------------


def test_pedidos_trazem_categoria_nome_e_ja_avaliou_na_lista_e_no_detalhe(amb):
    amb.cliente.app.state.modulo_profissional = SimpleNamespace(
        catalogo=SimpleNamespace(
            categorias_publicas=lambda: [CategoriaPublica("pintura", "Pintura", "pintura")]
        )
    )
    amb.semear_pedido(Estado.CONCLUIDO, concluido_em=AGORA)
    amb.contexto.pedidos.salvar(
        amb.contexto.pedidos.obter("ped-1"),
        None,
        DadosPedido("pintura", "bh", "Orçamento geral", "d"),
    )

    lista = _get(amb, "/v1/pedidos?como=cliente").json()
    assert lista[0]["categoria_nome"] == "Pintura" and lista[0]["ja_avaliou"] is False
    det = _get(amb, "/v1/pedidos/ped-1").json()
    assert det["categoria_nome"] == "Pintura" and det["ja_avaliou"] is False

    r = amb.cliente.post(
        "/v1/pedidos/ped-1/avaliacao", json={"nota_geral": 5}, headers=cab("t-cliente")
    )
    assert r.status_code == 201
    assert _get(amb, "/v1/pedidos?como=cliente").json()[0]["ja_avaliou"] is True
    assert _get(amb, "/v1/pedidos/ped-1").json()["ja_avaliou"] is True
    # o profissional ainda não avaliou o cliente: o campo vale para quem consulta
    assert _get(amb, "/v1/pedidos?como=profissional", "t-prof").json()[0]["ja_avaliou"] is False


def test_categoria_nome_e_opcional_sem_catalogo(amb):
    amb.semear_pedido(Estado.ABERTO, profissional_id=None, orcamento_id=None)
    amb.contexto.pedidos.salvar(
        amb.contexto.pedidos.obter("ped-1"), None, DadosPedido("pintura", "bh", "x", "d")
    )
    assert _get(amb, "/v1/pedidos/ped-1").json()["categoria_nome"] is None


# --- FIL-1: o filtro de categoria é exato -----------------------------------------------------


def _abrir(amb, pid, categoria, titulo, local=(None, None), remoto=False):
    amb.contexto.pedidos.salvar(
        Pedido(
            id=pid,
            cliente_id=CLIENTE.id,
            aberto_em=AGORA - timedelta(days=1),
            estado=Estado.ABERTO,
            remoto=remoto,
        ),  # fmt: skip
        dados=DadosPedido(
            categoria_id=categoria,
            cidade_id="c",
            titulo=titulo,
            descricao="d",
            bairro="Centro",
            local_aprox_lat=local[0],
            local_aprox_lng=local[1],
        ),  # fmt: skip
    )


def test_fil1_filtro_de_categoria_nao_traz_outra_categoria_nem_orcamento_geral(amb):
    # FIL-1: o servidor compara o id da categoria por igualdade. "Orçamento geral" é o NOME DE
    # UMA PERGUNTA/título (REM-3), não uma categoria: não há regra que o inclua no filtro.
    _abrir(amb, "e1", "eletricista", "Trocar tomada")
    _abrir(amb, "c1", "cameras-seguranca", "Instalar câmeras")
    _abrir(amb, "g1", "pintura", "Orçamento geral")

    r = amb.cliente.get(
        "/v1/profissional/pedidos-abertos?categoria_id=eletricista", headers=cab("t-prof")
    )

    assert r.status_code == 200, r.text
    assert [p["id"] for p in r.json()] == ["e1"]


# --- MAP-1: ponto na grade de ~500 m ----------------------------------------------------------


def test_na_grade_e_deterministico_e_fica_a_menos_de_500_m():
    assert na_grade(None) is None
    assert na_grade(-19.9167321) == -19.915 and na_grade(-19.9167321) == na_grade(-19.9167321)
    assert abs(na_grade(-43.9345123) - -43.9345123) <= 0.0025


def test_map1_ponto_exato_entra_e_o_servidor_guarda_so_a_grade():
    entrada = AbrirPedidoIn(
        categoria_id="c", cidade_id="x", titulo="t", descricao="d",
        local_aprox_lat=-19.9167321, local_aprox_lng=-43.9345123,
    )  # fmt: skip
    dados = entrada.para_dados()
    assert (dados.local_aprox_lat, dados.local_aprox_lng) == (-19.915, -43.935)
    remoto = AbrirPedidoIn(
        categoria_id="c", cidade_id="x", titulo="t", descricao="d", modalidade="remoto",
        local_aprox_lat=-19.9167321, local_aprox_lng=-43.9345123,
    )  # fmt: skip
    assert remoto.para_dados().local_aprox_lat is None


def test_map1_pedido_ja_salvo_com_ponto_exato_sai_na_grade_e_remoto_sem_ponto(amb):
    _abrir(amb, "exato", "pintura", "Pintar", local=(-19.9167321, -43.9345123))
    _abrir(amb, "remoto", "pintura", "Aula", local=(-19.9167321, -43.9345123), remoto=True)
    url = "/v1/profissional/pedidos-abertos?lat=-19.9167&lng=-43.9345"

    a = {p["id"]: p for p in amb.cliente.get(url, headers=cab("t-prof")).json()}
    b = {p["id"]: p for p in amb.cliente.get(url, headers=cab("t-prof")).json()}

    assert (a["exato"]["local_aprox_lat"], a["exato"]["local_aprox_lng"]) == (-19.915, -43.935)
    assert a["exato"] == b["exato"]  # mesma resposta para o mesmo pedido
    assert a["exato"]["distancia_km"] is not None
    assert a["remoto"]["local_aprox_lat"] is None and a["remoto"]["local_aprox_lng"] is None
    assert a["remoto"]["distancia_km"] is None
    det = amb.cliente.get("/v1/profissional/pedidos-abertos/exato", headers=cab("t-prof")).json()
    assert (
        det["local_aprox_lat"] == -19.915 and "endereco" not in det and "logradouro" not in str(det)
    )


# --- aditivo pago ------------------------------------------------------------------------------


def test_aditivo_pago_avisa_o_profissional_uma_vez(fluxo: Fluxo):  # noqa: F811
    notif = ServicoNotificacoes(
        RepositorioEmMemoria(),
        Canais(CanalApp()),
        ConfigNotificacoes(_env_file=None),
        fluxo.amb.relogio,
    )
    ligar_ao_contexto(fluxo.http.app, fluxo.ctx, notif)
    pid = fluxo.aceitar()
    fluxo.pagar(pid)
    fluxo.agendar(pid)
    fluxo.iniciar(pid)
    base = f"/v1/contratos/{pid}"
    r = fluxo.chamar(
        "POST",
        f"{base}/aditivos",
        "t-prof",
        {"descricao": "Trocar o registro", "valor_centavos": 5000},
    )
    aditivo_id = r.json()["id"]
    r = fluxo.chamar("POST", f"{base}/aditivos/{aditivo_id}/aprovar", "t-cliente", {"meio": "pix"})
    assert r.status_code == 200, r.text
    cobranca_id = r.json()["cobranca"]["cobranca_id"]
    saldo_antes = fluxo.saldo(pid)

    fluxo.fake.marcar_paga(cobranca_id)
    assert fluxo.webhook(TipoEvento.PAGAMENTO_CONFIRMADO, cobranca_id).status_code == 200
    assert fluxo.webhook(TipoEvento.PAGAMENTO_CONFIRMADO, cobranca_id).status_code == 200

    avisos = [
        n
        for n in notif.repo.listar(PROFISSIONAL.id, False, 100)
        if n.tipo == Evento.ADITIVO_PAGO.value
    ]
    assert len(avisos) == 1
    assert avisos[0].titulo == "Aditivo pago"
    assert avisos[0].corpo == (
        "O cliente pagou o aditivo. O valor fica retido até o cliente confirmar o serviço."
    )
    assert avisos[0].dados["pedido_id"] == pid
    assert fluxo.saldo(pid)["cliente_pagou_centavos"] > saldo_antes["cliente_pagou_centavos"]
