"""Perguntas que o admin configura por categoria: o app as recebe, o cliente responde ao abrir o
pedido (obrigatórias exigidas) e o profissional lê as respostas."""

from __future__ import annotations

from conftest import cab

from trato.api.repositorios import PerguntaCategoria

ENDERECO = {"logradouro": "Rua das Flores", "numero": "10", "bairro": "Centro", "cep": "35500-000"}
TIPO = PerguntaCategoria("q-tipo", "Qual é o tipo de imóvel?", "escolha_unica",
                         ("Apartamento", "Casa"), True)  # fmt: skip
COMODOS = PerguntaCategoria("q-comodos", "Quantos cômodos?", "numero", (), True)
PETS = PerguntaCategoria("q-pets", "Há animais?", "sim_nao", (), False)
EXTRAS = PerguntaCategoria("q-extras", "O que mais?", "multipla", ("Janelas", "Forno"), False)


def _ligar(amb):
    amb.contexto.pedidos.perguntas = {"cat-limpeza": [TIPO, COMODOS, PETS, EXTRAS]}


def _abrir(amb, respostas):
    corpo = {
        "categoria_id": "cat-limpeza",
        "cidade_id": "cid-bh",
        "titulo": "Limpeza residencial",
        "descricao": "Limpeza do apartamento.",
        "endereco": ENDERECO,
        "respostas": respostas,
    }
    return amb.cliente.post("/v1/pedidos", json=corpo, headers=cab("t-cliente"))


def test_o_app_recebe_as_perguntas_da_categoria(amb):
    _ligar(amb)
    r = amb.cliente.get("/v1/catalogo/categorias/cat-limpeza/perguntas")
    assert r.status_code == 200
    assert [q["id"] for q in r.json()] == ["q-tipo", "q-comodos", "q-pets", "q-extras"]
    assert r.json()[0] == {
        "id": "q-tipo",
        "texto": "Qual é o tipo de imóvel?",
        "tipo": "escolha_unica",
        "opcoes": ["Apartamento", "Casa"],
        "obrigatoria": True,
    }
    assert amb.cliente.get("/v1/catalogo/categorias/outra/perguntas").json() == []


def test_obrigatorias_e_opcoes_sao_conferidas(amb):
    _ligar(amb)
    sem = _abrir(amb, [{"pergunta_id": "q-tipo", "resposta": "Casa"}])
    assert sem.status_code == 422 and "Quantos cômodos?" in sem.json()["detail"]
    fora = _abrir(amb, [
        {"pergunta_id": "q-tipo", "resposta": "Mansão"},
        {"pergunta_id": "q-comodos", "resposta": 3},
    ])  # fmt: skip
    assert fora.status_code == 422 and "opções" in fora.json()["detail"]
    multipla = _abrir(amb, [
        {"pergunta_id": "q-tipo", "resposta": "Casa"},
        {"pergunta_id": "q-comodos", "resposta": 3},
        {"pergunta_id": "q-extras", "resposta": ["Piscina"]},
    ])  # fmt: skip
    assert multipla.status_code == 422


def test_respostas_chegam_ao_profissional_pelos_dados_do_pedido(amb):
    _ligar(amb)
    ok = _abrir(amb, [
        {"pergunta_id": "q-tipo", "resposta": "Apartamento"},
        {"pergunta_id": "q-comodos", "resposta": 3},
        {"pergunta_id": "q-pets", "resposta": False},
        {"pergunta_id": "q-extras", "resposta": ["Janelas"]},
    ])  # fmt: skip
    assert ok.status_code == 201, ok.text
    dados = amb.cliente.get(f"/v1/pedidos/{ok.json()['id']}/dados", headers=cab("t-cliente"))
    assert dados.status_code == 200
    assert dados.json()["respostas"] == [
        {"pergunta": "Qual é o tipo de imóvel?", "resposta": "Apartamento"},
        {"pergunta": "Quantos cômodos?", "resposta": 3},
        {"pergunta": "Há animais?", "resposta": False},
        {"pergunta": "O que mais?", "resposta": ["Janelas"]},
    ]


def test_categoria_sem_perguntas_segue_como_antes(amb):
    corpo = {
        "categoria_id": "cat-sem",
        "cidade_id": "cid-bh",
        "titulo": "Pedido",
        "descricao": "Algo.",
        "endereco": ENDERECO,
    }
    assert amb.cliente.post("/v1/pedidos", json=corpo, headers=cab("t-cliente")).status_code == 201
