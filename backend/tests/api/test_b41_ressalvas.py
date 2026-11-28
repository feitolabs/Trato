"""B41: visita recorrente fora do feed, limites de denúncia/reagendamento/consulta e antifraude."""

from __future__ import annotations

from datetime import timedelta

import pytest
from conftest import AGORA, cab

from trato.agendador.executor import ExecutorContexto
from trato.api.auth import PapelUsuario
from trato.api.conta import DadosPessoais
from trato.api.repositorios_app import PerfilDetalhe
from trato.pedidos.estados import Estado, Janela

H = timedelta(hours=1)
D = timedelta(days=1)


def _perfis(amb, extras=()):
    for uid, nome, papel in (
        ("cli-1", "João Pedro Silva", PapelUsuario.CLIENTE),
        ("cli-2", "Maria Oliveira Lima", PapelUsuario.CLIENTE),
        ("pro-1", "Carlos Eduardo Souza", PapelUsuario.PROFISSIONAL),
        ("pro-2", "Ana Beatriz Costa", PapelUsuario.PROFISSIONAL),
        *extras,
    ):
        amb.contexto.usuarios.adicionar(PerfilDetalhe(uid, nome, papel))


def _ids(resposta):
    corpo = resposta.json()
    itens = corpo["itens"] if isinstance(corpo, dict) else corpo
    return [i["id"] for i in itens]


# --- 1. visita recorrente fora do feed --------------------------------------------------------


def test_pedido_de_visita_recorrente_so_aparece_para_o_profissional_da_serie(amb):
    _perfis(amb)
    amb.semear_pedido(Estado.CONCLUIDO, concluido_em=AGORA)
    proposta = amb.cliente.post(
        "/v1/recorrencias",
        json={
            "pedido_origem_id": "ped-1",
            "frequencia": "semanal",
            "proxima_visita_em": (AGORA + 30 * H).isoformat(),
        },
        headers=cab("t-cliente"),
    )
    rid = proposta.json()["id"]
    amb.cliente.post(f"/v1/recorrencias/{rid}/aceitar", headers=cab("t-prof"))
    assert ExecutorContexto(amb.contexto).gerar_visitas_recorrentes(AGORA) == 1
    (visita,) = amb.contexto.recorrencias.visitas(rid)
    pedido_visita = visita.pedido_id

    # O profissional da série vê; outro profissional não vê em lugar nenhum.
    assert pedido_visita in {p.id for p in amb.contexto.pedidos.listar_abertos("pro-1")}
    assert pedido_visita not in {p.id for p in amb.contexto.pedidos.listar_abertos("pro-2")}
    feed = amb.cliente.get("/v1/profissional/pedidos-abertos", headers=cab("t-outro-prof"))
    assert feed.status_code == 200 and pedido_visita not in _ids(feed)
    do_dono = amb.cliente.get("/v1/profissional/pedidos-abertos", headers=cab("t-prof"))
    assert pedido_visita in _ids(do_dono)
    detalhe = amb.cliente.get(
        f"/v1/profissional/pedidos-abertos/{pedido_visita}", headers=cab("t-outro-prof")
    )
    assert detalhe.status_code == 404
    orcar = amb.cliente.post(
        f"/v1/pedidos/{pedido_visita}/orcamentos",
        json={
            "prazo_execucao_dias": 3,
            "validade_ate": "2099-01-01T00:00:00Z",
            "fora_do_escopo": "Materiais não incluídos.",
            "garantia_dias": 90,
            "itens": [
                {
                    "tipo": "horas",
                    "descricao": "Mão de obra",
                    "quantidade": 1,
                    "valor_unitario_centavos": 5_000,
                }
            ],
        },
        headers=cab("t-outro-prof"),
    )
    assert orcar.status_code == 404
    # Um pedido comum (fora de série) continua visível para os dois.
    comum = amb.contexto.pedidos.listar_abertos("pro-2")
    assert pedido_visita not in {p.id for p in comum}


# --- 2a/2b. denúncias ---------------------------------------------------------------------------


def _denunciar_perfil(amb, denunciado, quem="t-cliente"):
    return amb.cliente.post(
        "/v1/denuncias",
        json={
            "alvo_tipo": "perfil",
            "denunciado_id": denunciado,
            "motivo": "perfil_falso",
            "detalhes": "Fotos de outra pessoa.",
        },
        headers=cab(quem),
    )


def test_perfil_so_pode_ser_denunciado_uma_vez_a_cada_24h(amb):
    _perfis(amb)
    assert _denunciar_perfil(amb, "pro-1").status_code == 201
    de_novo = _denunciar_perfil(amb, "pro-1")
    assert de_novo.status_code == 409
    assert "últimas 24 horas" in de_novo.json()["detail"]
    assert _denunciar_perfil(amb, "pro-2").status_code == 201  # outro alvo vale
    assert (
        _denunciar_perfil(amb, "pro-1", quem="t-outro-cliente").status_code == 201
    )  # outra pessoa
    amb.relogio.avancar(hours=25)
    assert _denunciar_perfil(amb, "pro-1").status_code == 201  # passou a janela


def test_no_maximo_10_denuncias_de_perfil_por_dia(amb):
    extras = [(f"alvo-{n}", f"Alvo {n} Teste", PapelUsuario.PROFISSIONAL) for n in range(11)]
    _perfis(amb, extras)
    for n in range(10):
        assert _denunciar_perfil(amb, f"alvo-{n}").status_code == 201, n
    r = _denunciar_perfil(amb, "alvo-10")
    assert r.status_code == 429
    assert "limite de denúncias" in r.json()["detail"]
    amb.relogio.avancar(hours=25)
    assert _denunciar_perfil(amb, "alvo-10").status_code == 201


def test_alerta_de_chat_traz_o_denunciado_e_o_texto_somado_tem_teto(amb):
    amb.semear_pedido(Estado.PAGO_E_RETIDO)
    corpo = {
        "alvo_tipo": "chat",
        "denunciado_id": "pro-1",
        "pedido_id": "ped-1",
        "motivo": "outro",
        "detalhes": "x" * 500,
    }
    for _ in range(8):
        assert (
            amb.cliente.post("/v1/denuncias", json=corpo, headers=cab("t-cliente")).status_code
            == 201
        )
    (alerta,) = amb.contexto.denuncias.alertas.values()
    assert " por cli-1 contra pro-1:" in alerta.detalhes
    assert len(alerta.detalhes) <= 2000


# --- 2c/2d. reagendamento --------------------------------------------------------------------------


def _propor(amb, token, dias, **extra):
    inicio = AGORA + dias * D
    return amb.cliente.post(
        "/v1/pedidos/ped-1/reagendamentos",
        json={
            "nova_janela_inicio": inicio.isoformat(),
            "nova_janela_fim": (inicio + 2 * H).isoformat(),
            **extra,
        },
        headers=cab(token),
    )


def test_reagendamento_no_maximo_60_dias_a_frente(amb):
    amb.semear_pedido(Estado.AGENDADO, janela=Janela(AGORA + 24 * H, AGORA + 26 * H))
    longe = _propor(amb, "t-cliente", 61)
    assert longe.status_code == 422 and "60 dias" in longe.json()["detail"]
    assert _propor(amb, "t-cliente", 59).status_code == 201


def test_reagendamento_no_maximo_5_propostas_por_pedido_por_dia(amb):
    amb.semear_pedido(Estado.AGENDADO, janela=Janela(AGORA + 24 * H, AGORA + 26 * H))
    for n in range(5):
        r = _propor(amb, "t-cliente", 3 + n)
        assert r.status_code == 201, r.text
        recusa = amb.cliente.post(
            f"/v1/pedidos/ped-1/reagendamentos/{r.json()['id']}/recusar", headers=cab("t-prof")
        )
        assert recusa.status_code == 200
    sexta = _propor(amb, "t-cliente", 10)
    assert sexta.status_code == 429
    assert "reagendamento" in sexta.json()["detail"]
    amb.relogio.avancar(hours=25)
    assert _propor(amb, "t-cliente", 10).status_code == 201


def test_historico_registra_quem_realmente_aceitou(amb):
    amb.semear_pedido(Estado.PAGO_E_RETIDO)  # a regra da agenda exige o profissional na transição
    proposta = _propor(amb, "t-prof", 5)
    assert proposta.status_code == 201
    aceite = amb.cliente.post(
        f"/v1/pedidos/ped-1/reagendamentos/{proposta.json()['id']}/aceitar",
        headers=cab("t-cliente"),
    )
    assert aceite.status_code == 200, aceite.text
    ultimo = amb.contexto.pedidos.eventos("ped-1")[-1]
    assert ultimo.ator.id == "cli-1"  # quem de fato aceitou, não o profissional que propôs
    assert aceite.json()["respondido_por"] == "cli-1"


# --- 3. indicação: limite de consulta e antifraude ----------------------------------------------


def test_consulta_publica_de_codigo_tem_limite_por_ip(amb):
    _perfis(amb)
    codigo = amb.cliente.get("/v1/indicacoes/meu-codigo", headers=cab("t-prof")).json()["codigo"]
    for _ in range(20):
        assert amb.cliente.get(f"/v1/indicacoes/codigo/{codigo}").status_code == 200
    r = amb.cliente.get(f"/v1/indicacoes/codigo/{codigo}")
    assert r.status_code == 429
    assert int(r.headers["retry-after"]) >= 1
    assert "Muitas consultas" in r.json()["detail"]
    amb.relogio.avancar(seconds=61)
    assert amb.cliente.get(f"/v1/indicacoes/codigo/{codigo}").status_code == 200


def _dados(amb, uid, email=None, telefone=None):
    amb.contexto.conta._dados[uid] = DadosPessoais("Nome", email, None, telefone, None)


def _aplicar(amb, token, codigo):
    return amb.cliente.post("/v1/indicacoes/aplicar", json={"codigo": codigo}, headers=cab(token))


@pytest.mark.parametrize(
    ("indicador", "indicado", "motivo"),
    [
        (("maria.lima+trato@gmail.com", None), ("marialima@GMAIL.com", None), "mesmo_email"),
        ((None, "+55 (11) 91234-5678"), (None, "11 91234-5678"), "mesmo_telefone"),
    ],
)
def test_mesmo_telefone_ou_email_bloqueia_por_fraude(amb, indicador, indicado, motivo):
    _perfis(amb)
    _dados(amb, "cli-2", *indicador)
    _dados(amb, "cli-1", *indicado)
    codigo = amb.cliente.get("/v1/indicacoes/meu-codigo", headers=cab("t-outro-cliente")).json()[
        "codigo"
    ]
    r = _aplicar(amb, "t-cliente", codigo)
    assert r.status_code == 201, r.text
    assert (r.json()["status"], r.json()["bonus_indicado_tratinhos"]) == ("bloqueado_fraude", 0)
    salvo = amb.contexto.indicacoes.do_indicado("cli-1")
    assert salvo.status == "bloqueado_fraude" and salvo.motivo_bloqueio == motivo
    assert (salvo.bonus_indicador_tratinhos, salvo.bonus_indicado_tratinhos) == (0, 0)
    # o uso do código foi consumido e o gatilho nunca arma uma indicação bloqueada
    assert _aplicar(amb, "t-cliente", codigo).status_code == 409
    from trato.api.indicacoes import acionar_gatilho

    amb.semear_pedido(Estado.CONCLUIDO, concluido_em=AGORA)
    amb.semear_dinheiro(100_000, taxa=10_000)
    assert acionar_gatilho(amb.contexto, amb.contexto.pedidos.obter("ped-1"), AGORA) == []


def test_contatos_diferentes_ou_ausentes_nao_bloqueiam(amb):
    _perfis(amb)
    _dados(amb, "cli-2", "maria@exemplo.com", "11 90000-0001")
    _dados(amb, "cli-1", "joao@exemplo.com", "11 90000-0002")
    codigo = amb.cliente.get("/v1/indicacoes/meu-codigo", headers=cab("t-outro-cliente")).json()[
        "codigo"
    ]
    r = _aplicar(amb, "t-cliente", codigo)
    assert r.status_code == 201 and r.json()["status"] == "cadastrado"
