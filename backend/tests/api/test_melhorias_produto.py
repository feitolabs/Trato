"""Testes das melhorias de API: CEP, ordenação alfabética, busca textual e negociação em dias."""

from __future__ import annotations

import uuid

from conftest import AGORA, cab

from trato.api.auth import PapelUsuario
from trato.api.repositorios_app import PerfilDetalhe
from trato.api.rotas_profissional_cadastro import modulo_em_memoria
from trato.cep import ConsultaCep
from trato.pedidos.estados import Estado
from trato.persistencia.conversas import mascarar_contatos
from trato.profissional.repositorio import ItemPortfolio, PerfilProfissional, Regiao


def test_consulta_cep_viacep_fallback_brasilapi_e_erros(amb):
    chamadas: list[str] = []

    def buscador(url: str):
        chamadas.append(url)
        if "35500001" in url and "viacep" in url:
            return 200, {
                "cep": "35500-001",
                "logradouro": "Av. Primeiro de Junho",
                "complemento": "",
                "bairro": "Centro",
                "localidade": "Divinópolis",
                "uf": "MG",
            }
        if "35500002" in url and "viacep" in url:
            return 503, None
        if "35500002" in url and "brasilapi" in url:
            return 200, {
                "cep": "35500002",
                "street": "Rua Goiás",
                "neighborhood": "Centro",
                "city": "Divinópolis",
                "state": "MG",
            }
        if "99999999" in url:
            return 200, {"erro": True}
        return 500, None

    amb.cliente.app.state.consulta_cep = ConsultaCep(buscador)
    assert amb.cliente.get("/v1/cep/35500001").status_code == 401

    r1 = amb.cliente.get("/v1/cep/35500-001", headers=cab("t-cliente"))
    assert r1.status_code == 200
    assert r1.json() == {
        "cep": "35500001",
        "logradouro": "Av. Primeiro de Junho",
        "complemento": "",
        "bairro": "Centro",
        "cidade": "Divinópolis",
        "uf": "MG",
    }

    # Segunda chamada vem do cache sem nova consulta HTTP
    antes = len(chamadas)
    assert amb.cliente.get("/v1/cep/35500001", headers=cab("t-cliente")).status_code == 200
    assert len(chamadas) == antes

    # Fallback para BrasilAPI quando ViaCEP falha
    r2 = amb.cliente.get("/v1/cep/35500002", headers=cab("t-prof"))
    assert r2.status_code == 200 and r2.json()["logradouro"] == "Rua Goiás"

    assert amb.cliente.get("/v1/cep/123", headers=cab("t-cliente")).status_code == 422
    assert amb.cliente.get("/v1/cep/99999999", headers=cab("t-cliente")).status_code == 404
    assert amb.cliente.get("/v1/cep/88888888", headers=cab("t-cliente")).status_code == 503


def test_busca_melhorada_hifen_nome_publico_bio_portfolio_e_privacidade(amb):
    modulo = modulo_em_memoria(amb.cliente.app)
    modulo.catalogo.categorias.update(
        {
            "c-zeta": "z-servico",
            "c-ar": "ar-condicionado",
            "c-pint": "pintura-interna",
        }
    )
    modulo.catalogo.nomes.update(
        {
            "c-zeta": "Zeladoria",
            "c-ar": "Ar-condicionado",
            "c-pint": "Pintura interna",
        }
    )
    modulo.catalogo.cidades.update({"div"})
    modulo.catalogo.nomes.update({"div": "Divinópolis"})
    modulo.catalogo.ufs.update({"div": "MG"})

    modulo.repo.salvar(
        PerfilProfissional(
            "pro-ar",
            "aprovado",
            "Instalação e limpeza de split inverter.",
            ("c-ar",),
            (Regiao("div", "Centro"),),
            (),
            (ItemPortfolio("Higienização de condensadora"),),
            AGORA,
            nivel_verificacao="verificado_plus",
            atende_remoto=False,
        )
    )
    amb.contexto.usuarios.adicionar(
        PerfilDetalhe(
            "pro-ar",
            "Roberto Secreto Silva",
            PapelUsuario.PROFISSIONAL,
            "ativo",
            "verificado_plus",
            4.9,
            15,
        )
    )

    cats = amb.cliente.get("/v1/catalogo/categorias", headers=cab("t-cliente")).json()
    assert [c["nome"] for c in cats] == ["Ar-condicionado", "Pintura interna", "Zeladoria"]

    # Sem hífen encontra "Ar-condicionado"
    assert [
        i["id"]
        for i in amb.cliente.get(
            "/v1/profissionais?servico=ar%20condicionado", headers=cab("t-cliente")
        ).json()["itens"]
    ] == ["pro-ar"]

    # Busca ampla `q=` encontra nome público, bio, portfólio e cidade sem vazar sobrenome privado
    for termo in ("Roberto", "inverter", "condensadora", "Divinopolis", "ar condicionado"):
        res = amb.cliente.get(f"/v1/profissionais?q={termo}", headers=cab("t-cliente"))
        assert res.status_code == 200
        itens = res.json()["itens"]
        assert [i["id"] for i in itens] == ["pro-ar"], f"falhou em {termo!r}"
        assert itens[0]["cidades"] == ["Divinópolis/MG"]
        assert itens[0]["bairros"] == ["Centro"]

    # Sobrenome privado nunca casa nem vaza na busca
    assert (
        amb.cliente.get("/v1/profissionais?q=Secreto", headers=cab("t-cliente")).json()["itens"]
        == []
    )


def test_negociacao_de_dias_no_orcamento_contraproposta_e_proposta_do_profissional(amb):
    amb.semear_pedido(Estado.ABERTO, orcamento_id=None, profissional_id=None)
    criado = amb.cliente.post(
        "/v1/pedidos/ped-1/orcamentos",
        json={
            "itens": [
                {
                    "tipo": "horas",
                    "descricao": "Mão de obra",
                    "quantidade": 2,
                    "valor_unitario_centavos": 15_000,
                }
            ],
            "prazo_execucao_dias": 5,
            "garantia_dias": 90,
        },
        headers=cab("t-prof"),
    )
    assert criado.status_code == 201
    orc = criado.json()["id"]

    # Cliente contrapropõe mantendo valor ou reduzindo valor junto com 2 dias de execução
    contra = amb.cliente.post(
        f"/v1/pedidos/ped-1/orcamentos/{orc}/contraproposta",
        json={
            "valor_centavos": 28_000,
            "prazo_execucao_dias": 2,
            "mensagem": "Consegue entregar antes?",
        },
        headers=cab("t-cliente"),
    )
    assert contra.status_code == 201
    assert contra.json()["prazo_execucao_dias"] == 2

    msgs = amb.cliente.get("/v1/pedidos/ped-1/mensagens", headers=cab("t-prof")).json()
    assert msgs[-1]["texto"].startswith(f"[contraproposta:{orc}:28000:2]")

    # Profissional aceita com os 2 dias combinados
    aceite = amb.cliente.post(
        f"/v1/pedidos/ped-1/orcamentos/{orc}/contraproposta/aceitar",
        json={"valor_centavos": 28_000, "prazo_execucao_dias": 2},
        headers=cab("t-prof"),
    )
    assert aceite.status_code == 201
    novo_orc = aceite.json()["orcamento_id"]
    assert aceite.json()["prazo_execucao_dias"] == 2

    det = amb.cliente.get(f"/v1/orcamentos/{novo_orc}", headers=cab("t-cliente")).json()
    assert det["valor_centavos"] == 28_000 and det["prazo_execucao_dias"] == 2

    # Mensagem gerada traz cartão [proposta:...] para o cliente aceitar e pagar
    msgs_cli = amb.cliente.get("/v1/pedidos/ped-1/mensagens", headers=cab("t-cliente")).json()
    assert msgs_cli[-1]["texto"].startswith(f"[proposta:{novo_orc}:28000:2]")

    # Profissional também pode enviar contraproposta/nova condição direto pelo chat
    contra_pro = amb.cliente.post(
        f"/v1/pedidos/ped-1/orcamentos/{novo_orc}/propor",
        json={
            "valor_centavos": 26_000,
            "prazo_execucao_dias": 3,
            "mensagem": "Consigo em 3 dias por 260.",
        },
        headers=cab("t-prof"),
    )
    assert contra_pro.status_code == 201
    terceiro_orc = contra_pro.json()["orcamento_id"]
    assert contra_pro.json()["prazo_execucao_dias"] == 3
    msgs_cli2 = amb.cliente.get("/v1/pedidos/ped-1/mensagens", headers=cab("t-cliente")).json()
    assert msgs_cli2[-1]["texto"].startswith(f"[proposta:{terceiro_orc}:26000:3]")


def test_mascaramento_preserva_marcas_com_dias():
    for _ in range(200):
        uid = str(uuid.uuid4())
        t1 = f"[contraproposta:{uid}:25000:4] Fala no 31 99999-8888"
        t2 = f"[proposta:{uid}:25000:4] Fala no 31 99999-8888"
        assert mascarar_contatos(t1).startswith(f"[contraproposta:{uid}:25000:4] ")
        assert mascarar_contatos(t2).startswith(f"[proposta:{uid}:25000:4] ")
        assert "99999" not in mascarar_contatos(t1)
        assert "99999" not in mascarar_contatos(t2)
