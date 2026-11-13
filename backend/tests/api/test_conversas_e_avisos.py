"""Conversas e avisos: mensagem nova, orçamento recebido, leitura ao abrir e conversa sem id."""

from __future__ import annotations

from conftest import PROFISSIONAL, cab
from test_notificacoes_api import servico_do

from trato.pedidos.estados import Estado

ORCAMENTO = {
    "itens": [
        {
            "tipo": "horas",
            "descricao": "Mão de obra",
            "quantidade": 3,
            "valor_unitario_centavos": 10_000,
        }
    ],
}


def _get(amb, url, quem="t-cliente", **kw):
    return amb.cliente.get(url, headers=cab(quem), **kw)


def _post(amb, url, quem, corpo, **kw):
    return amb.cliente.post(url, json=corpo, headers=cab(quem), **kw)


def _pedido_aberto(amb):
    amb.semear_pedido(Estado.ABERTO, orcamento_id=None, profissional_id=None)
    amb.contexto.contratos._itens.clear()


def test_orcamento_enviado_avisa_o_cliente(amb):
    servico_do(amb)
    _pedido_aberto(amb)
    assert _get(amb, "/v1/notificacoes").json() == []
    r = _post(amb, "/v1/pedidos/ped-1/orcamentos", "t-prof", ORCAMENTO)
    assert r.status_code == 201, r.text
    [aviso] = _get(amb, "/v1/notificacoes").json()
    assert aviso["tipo"] == "orcamento.recebido"
    assert aviso["dados"]["pedido_id"] == "ped-1"
    assert _get(amb, "/v1/notificacoes", "t-prof").json() == []  # só o cliente é avisado


def test_mensagem_avisa_quem_recebeu_sem_vazar_o_texto(amb):
    servico_do(amb)
    _pedido_aberto(amb)
    _post(amb, "/v1/pedidos/ped-1/orcamentos", "t-prof", ORCAMENTO)
    _post(amb, "/v1/pedidos/ped-1/mensagens", "t-prof", {"texto": "Posso ir amanhã"})
    # duas seguidas, sem leitura no meio: um aviso só
    _post(amb, "/v1/pedidos/ped-1/mensagens", "t-prof", {"texto": "Levo o material"})
    avisos = [n for n in _get(amb, "/v1/notificacoes").json() if n["tipo"] == "mensagem.nova"]
    assert len(avisos) == 1
    assert "amanhã" not in str(avisos[0]) and "material" not in str(avisos[0])
    assert avisos[0]["dados"]["profissional_id"] == PROFISSIONAL.id
    # quem escreveu não é avisado
    assert [
        n for n in _get(amb, "/v1/notificacoes", "t-prof").json() if n["tipo"] == "mensagem.nova"
    ] == []
    # o cliente responde: o profissional é avisado
    _post(
        amb,
        "/v1/pedidos/ped-1/mensagens",
        "t-cliente",
        {"texto": "Pode"},
        params={"profissional_id": PROFISSIONAL.id},
    )
    do_prof = [
        n for n in _get(amb, "/v1/notificacoes", "t-prof").json() if n["tipo"] == "mensagem.nova"
    ]
    assert len(do_prof) == 1


def test_abrir_a_conversa_marca_como_lida_e_lista_traz_nome_e_titulo(amb):
    servico_do(amb)
    _pedido_aberto(amb)
    _post(amb, "/v1/pedidos/ped-1/orcamentos", "t-prof", ORCAMENTO)
    _post(amb, "/v1/pedidos/ped-1/mensagens", "t-prof", {"texto": "Oi"})
    [antes] = _get(amb, "/v1/conversas").json()
    assert antes["nao_lidas"] == 1 and antes["pedido_id"] == "ped-1"
    assert antes["outra_parte_id"] == PROFISSIONAL.id
    assert "outra_parte_nome" in antes and "titulo_pedido" in antes
    # o cliente abre a conversa sem dizer o profissional (como ao tocar na notificação)
    r = _get(amb, "/v1/pedidos/ped-1/mensagens")
    assert r.status_code == 200 and len(r.json()) == 1
    [depois] = _get(amb, "/v1/conversas").json()
    assert depois["nao_lidas"] == 0


def test_cliente_com_dois_profissionais_precisa_dizer_qual(amb):
    servico_do(amb)
    _pedido_aberto(amb)
    assert _post(amb, "/v1/pedidos/ped-1/orcamentos", "t-prof", ORCAMENTO).status_code == 201
    assert _post(amb, "/v1/pedidos/ped-1/orcamentos", "t-outro-prof", ORCAMENTO).status_code == 201
    # sem conversa e com dois orçamentos, o app tem de dizer com quem quer falar
    assert _get(amb, "/v1/pedidos/ped-1/mensagens").status_code == 422
    # depois que um profissional escreve, essa conversa vale (a mais recente)
    _post(amb, "/v1/pedidos/ped-1/mensagens", "t-outro-prof", {"texto": "Oi"})
    r = _get(amb, "/v1/pedidos/ped-1/mensagens")
    assert r.status_code == 200 and [m["texto"] for m in r.json()] == ["Oi"]


def test_recebido_quando_o_aparelho_busca_a_lista_e_lido_quando_abre_a_conversa(amb):
    servico_do(amb)
    _pedido_aberto(amb)
    _post(amb, "/v1/pedidos/ped-1/orcamentos", "t-prof", ORCAMENTO)
    _post(amb, "/v1/pedidos/ped-1/mensagens", "t-prof", {"texto": "Oi"})
    # quem mandou vê: enviada (nem recebida nem lida)
    [m] = _get(amb, "/v1/pedidos/ped-1/mensagens", "t-prof").json()
    assert m["entregue_em"] is None and m["lida_em"] is None
    # o aparelho do cliente busca a lista de conversas: a mensagem "chegou"
    _get(amb, "/v1/conversas")
    [m] = _get(amb, "/v1/pedidos/ped-1/mensagens", "t-prof").json()
    assert m["entregue_em"] is not None and m["lida_em"] is None
    # o cliente abre a conversa: lida (e continua recebida)
    _get(amb, "/v1/pedidos/ped-1/mensagens")
    [m] = _get(amb, "/v1/pedidos/ped-1/mensagens", "t-prof").json()
    assert m["lida_em"] is not None and m["entregue_em"] is not None
    # quem escreve não "recebe" a própria mensagem só por listar as conversas
    _post(amb, "/v1/pedidos/ped-1/mensagens", "t-prof", {"texto": "Mais uma"})
    _get(amb, "/v1/conversas", "t-prof")
    novo = _get(amb, "/v1/pedidos/ped-1/mensagens", "t-prof").json()[-1]
    assert novo["entregue_em"] is None
