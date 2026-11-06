"""Casos de borda da interação cliente <-> profissional contra o Postgres local descartável.

Cada teste afirma o comportamento SEGURO; falhar aqui é bug a corrigir antes de chegar ao usuário.
Nunca toca no Supabase real.
"""

from __future__ import annotations

from datetime import UTC, datetime, timedelta

import pytest

from .test_fluxo_postgres import abrir_pedido, acao, enviar_orcamento
from .test_rotas_app_postgres import atuacao, get, post  # noqa: F401

pytestmark = pytest.mark.integracao


@pytest.fixture(autouse=True)
def _desfaz_vinculo_do_profissional2(cenario):
    """O banco do cenário é compartilhado: não deixa o profissional2 vinculado para outros testes."""
    yield
    with cenario.local.admin() as con:
        for tabela in ("profissional_categorias", "profissional_regioes"):
            con.execute(
                f"delete from public.{tabela} where profissional_id = %s",  # noqa: S608
                (cenario.ids["profissional2"],),
            )


def corpo_orcamento(valor_unitario: int = 10_000, quantidade: str = "8") -> dict:
    return {
        "itens": [
            {
                "tipo": "horas",
                "descricao": "Mão de obra",
                "quantidade": quantidade,
                "valor_unitario_centavos": valor_unitario,
            }
        ],
        "etapas": [{"descricao": "Serviço", "valor_centavos": 10_000}],
        "prazo_execucao_dias": 5,
        "garantia_dias": 90,
    }


def contratos_do_pedido(c, pedido_id: str) -> int:
    with c.local.admin() as con:
        return con.execute(
            "select count(*) from public.contratos where pedido_id = %s", (pedido_id,)
        ).fetchone()[0]


def vincular(c, quem: str) -> None:
    """Faz o profissional atuar na categoria e na cidade do cenário."""
    with c.local.admin() as con:
        con.execute(
            "insert into public.profissional_categorias (profissional_id, categoria_id) "
            "values (%s, %s) on conflict do nothing",
            (c.ids[quem], c.categoria_id),
        )
        if not con.execute(
            "select 1 from public.profissional_regioes where profissional_id = %s",
            (c.ids[quem],),
        ).fetchone():
            con.execute(
                "insert into public.profissional_regioes (profissional_id, cidade_id) "
                "values (%s, %s)",
                (c.ids[quem], c.cidade_id),
            )


# --- aceite -------------------------------------------------------------------------------------


def test_aceitar_o_mesmo_orcamento_duas_vezes_nao_duplica_contrato(atuacao):  # noqa: F811
    c = atuacao
    pedido_id = abrir_pedido(c)
    orc = enviar_orcamento(c, pedido_id)
    corpo = {"orcamento_id": orc}
    primeira = acao(c, "cliente", pedido_id, "aceitar_orcamento", corpo)
    segunda = acao(c, "cliente", pedido_id, "aceitar_orcamento", corpo)
    assert primeira.status_code == 200, primeira.text
    assert segunda.status_code in (200, 409, 422), segunda.text
    assert contratos_do_pedido(c, pedido_id) == 1


def test_aceitar_dois_orcamentos_do_mesmo_pedido_so_vale_o_primeiro(atuacao):  # noqa: F811
    c = atuacao
    vincular(c, "profissional2")
    pedido_id = abrir_pedido(c)
    o1 = enviar_orcamento(c, pedido_id, "profissional")
    o2 = enviar_orcamento(c, pedido_id, "profissional2")
    assert acao(c, "cliente", pedido_id, "aceitar_orcamento", {"orcamento_id": o1}).status_code == 200
    r = acao(c, "cliente", pedido_id, "aceitar_orcamento", {"orcamento_id": o2})
    assert r.status_code in (409, 422), r.text
    assert contratos_do_pedido(c, pedido_id) == 1
    with c.local.admin() as con:
        dono = con.execute(
            "select profissional_id::text from public.contratos where pedido_id = %s", (pedido_id,)
        ).fetchone()[0]
    assert dono == c.ids["profissional"]


def test_aceitar_orcamento_de_outro_pedido_e_recusado(atuacao):  # noqa: F811
    c = atuacao
    pedido_a = abrir_pedido(c)
    pedido_b = abrir_pedido(c)
    orc_b = enviar_orcamento(c, pedido_b)
    r = acao(c, "cliente", pedido_a, "aceitar_orcamento", {"orcamento_id": orc_b})
    assert r.status_code >= 400, r.text
    assert contratos_do_pedido(c, pedido_a) == 0


def test_profissional_nao_aceita_o_proprio_orcamento(atuacao):  # noqa: F811
    c = atuacao
    pedido_id = abrir_pedido(c)
    orc = enviar_orcamento(c, pedido_id)
    r = acao(c, "profissional", pedido_id, "aceitar_orcamento", {"orcamento_id": orc})
    assert r.status_code in (403, 404), r.text
    assert contratos_do_pedido(c, pedido_id) == 0


def test_outro_cliente_nao_age_no_pedido_alheio(atuacao):  # noqa: F811
    c = atuacao
    pedido_id = abrir_pedido(c)
    orc = enviar_orcamento(c, pedido_id)
    assert get(c, f"/v1/pedidos/{pedido_id}", "cliente2").status_code in (403, 404)
    r = acao(c, "cliente2", pedido_id, "aceitar_orcamento", {"orcamento_id": orc})
    assert r.status_code in (403, 404), r.text
    r = acao(c, "cliente2", pedido_id, "cancelar", {"motivo": "não é meu pedido"})
    assert r.status_code in (403, 404), r.text
    assert contratos_do_pedido(c, pedido_id) == 0


# --- orçamento ----------------------------------------------------------------------------------


def test_orcamento_so_de_quem_atua_na_categoria_e_cidade(atuacao):  # noqa: F811
    c = atuacao
    pedido_id = abrir_pedido(c)
    # profissional2 não atua na categoria/cidade do pedido (outros testes podem tê-lo vinculado)
    with c.local.admin() as con:
        con.execute(
            "delete from public.profissional_categorias where profissional_id = %s",
            (c.ids["profissional2"],),
        )
    r = post(c, f"/v1/pedidos/{pedido_id}/orcamentos", "profissional2", corpo_orcamento())
    assert r.status_code in (403, 404, 409, 422), r.text


def test_cliente_nao_envia_orcamento(atuacao):  # noqa: F811
    c = atuacao
    pedido_id = abrir_pedido(c)
    r = post(c, f"/v1/pedidos/{pedido_id}/orcamentos", "cliente", corpo_orcamento())
    assert r.status_code == 403, r.text


def test_orcamento_em_pedido_ja_contratado_e_recusado(atuacao):  # noqa: F811
    c = atuacao
    vincular(c, "profissional2")
    pedido_id = abrir_pedido(c)
    o1 = enviar_orcamento(c, pedido_id, "profissional")
    assert acao(c, "cliente", pedido_id, "aceitar_orcamento", {"orcamento_id": o1}).status_code == 200
    r = post(c, f"/v1/pedidos/{pedido_id}/orcamentos", "profissional2", corpo_orcamento())
    assert r.status_code in (403, 404, 409, 422), r.text


def test_orcamento_em_pedido_cancelado_e_recusado(atuacao):  # noqa: F811
    c = atuacao
    pedido_id = abrir_pedido(c)
    cancelou = acao(c, "cliente", pedido_id, "cancelar", {"motivo": "mudei de ideia"})
    if cancelou.status_code != 200:
        pytest.skip(f"cancelar não disponível nesse estado: {cancelou.text}")
    r = post(c, f"/v1/pedidos/{pedido_id}/orcamentos", "profissional", corpo_orcamento())
    assert r.status_code in (403, 404, 409, 422), r.text


@pytest.mark.parametrize(
    ("valor", "quantidade"),
    [(0, "8"), (-100, "8"), (10_000, "0"), (10_000, "-1"), (10**12, "8")],
)
def test_orcamento_com_valores_invalidos_e_recusado(atuacao, valor, quantidade):  # noqa: F811
    c = atuacao
    pedido_id = abrir_pedido(c)
    r = post(
        c, f"/v1/pedidos/{pedido_id}/orcamentos", "profissional", corpo_orcamento(valor, quantidade)
    )
    assert r.status_code in (400, 409, 422), r.text


def test_orcamento_duplicado_do_mesmo_profissional_nao_vira_dois(atuacao):  # noqa: F811
    c = atuacao
    pedido_id = abrir_pedido(c)
    r1 = post(c, f"/v1/pedidos/{pedido_id}/orcamentos", "profissional", corpo_orcamento())
    r2 = post(c, f"/v1/pedidos/{pedido_id}/orcamentos", "profissional", corpo_orcamento(11_000))
    assert r1.status_code == 201, r1.text
    lista = get(c, f"/v1/pedidos/{pedido_id}/orcamentos", "cliente").json()
    assert len([o for o in lista if o["profissional_nome"] == "profissional"]) <= 1 or (
        r2.status_code in (409, 422)
    )


# --- privacidade e conversa ---------------------------------------------------------------------


def test_endereco_so_aparece_depois_da_contratacao(atuacao):  # noqa: F811
    c = atuacao
    pedido_id = abrir_pedido(c)
    antes = get(c, f"/v1/profissional/pedidos-abertos/{pedido_id}", "profissional")
    assert "Rua A" not in antes.text
    outro = get(c, f"/v1/pedidos/{pedido_id}", "profissional")
    assert "Rua A" not in outro.text


def test_terceiros_nao_leem_nem_escrevem_na_conversa(atuacao):  # noqa: F811
    c = atuacao
    pedido_id = abrir_pedido(c)
    orc = enviar_orcamento(c, pedido_id)
    assert acao(c, "cliente", pedido_id, "aceitar_orcamento", {"orcamento_id": orc}).status_code == 200
    url = f"/v1/pedidos/{pedido_id}/mensagens"
    post(c, url, "profissional", {"texto": "Olá"})
    for quem in ("cliente2", "profissional2"):
        lendo = get(c, url, quem)
        escrevendo = post(c, url, quem, {"texto": "intruso"})
        assert lendo.status_code in (403, 404) or lendo.json() == [], (quem, lendo.text)
        assert escrevendo.status_code in (403, 404), (quem, escrevendo.text)


def test_mensagem_vazia_ou_gigante_e_recusada(atuacao):  # noqa: F811
    c = atuacao
    pedido_id = abrir_pedido(c)
    url = f"/v1/pedidos/{pedido_id}/mensagens"
    for texto in ("", "   ", "x" * 100_000):
        r = post(c, url, "profissional", {"texto": texto})
        assert r.status_code in (400, 413, 422), (len(texto), r.status_code, r.text[:200])


# --- avaliação e pagamento ----------------------------------------------------------------------


def test_avaliar_antes_de_concluir_e_recusado(atuacao):  # noqa: F811
    c = atuacao
    pedido_id = abrir_pedido(c)
    orc = enviar_orcamento(c, pedido_id)
    assert acao(c, "cliente", pedido_id, "aceitar_orcamento", {"orcamento_id": orc}).status_code == 200
    r = post(
        c,
        f"/v1/pedidos/{pedido_id}/avaliacao",
        "cliente",
        {"notas": {"qualidade": 5}, "comentario": "ótimo"},
    )
    assert r.status_code >= 400, r.text


def test_cliente_nem_profissional_confirmam_pagamento(atuacao):  # noqa: F811
    c = atuacao
    pedido_id = abrir_pedido(c)
    orc = enviar_orcamento(c, pedido_id)
    assert acao(c, "cliente", pedido_id, "aceitar_orcamento", {"orcamento_id": orc}).status_code == 200
    for quem in ("cliente", "profissional", "cliente2", "profissional2"):
        r = acao(c, quem, pedido_id, "confirmar_pagamento")
        assert r.status_code in (403, 404), (quem, r.text)


def test_profissional_nao_confirma_conclusao_nem_check_in_sem_pagamento(atuacao):  # noqa: F811
    c = atuacao
    pedido_id = abrir_pedido(c)
    orc = enviar_orcamento(c, pedido_id)
    assert acao(c, "cliente", pedido_id, "aceitar_orcamento", {"orcamento_id": orc}).status_code == 200
    for nome in ("fazer_check_in", "fazer_check_out", "confirmar_conclusao"):
        r = acao(c, "profissional", pedido_id, nome)
        assert r.status_code >= 400, (nome, r.text)
    r = acao(c, "cliente", pedido_id, "confirmar_conclusao")
    assert r.status_code >= 400, r.text


def test_profissional_fora_da_categoria_nao_conversa_em_pedido_aberto(atuacao):  # noqa: F811
    c = atuacao
    pedido_id = abrir_pedido(c)
    with c.local.admin() as con:
        con.execute(
            "delete from public.profissional_categorias where profissional_id = %s",
            (c.ids["profissional2"],),
        )
    url = f"/v1/pedidos/{pedido_id}/mensagens"
    r = post(c, url, "profissional2", {"texto": "Posso fazer por menos, me chama no zap"})
    assert r.status_code in (403, 404), r.text
    assert get(c, url, "profissional2").status_code in (403, 404)


def test_aceites_simultaneos_geram_um_unico_contrato(atuacao):  # noqa: F811
    """Duplo toque ou duas abas: dois aceites ao mesmo tempo não podem criar dois contratos."""
    from concurrent.futures import ThreadPoolExecutor

    c = atuacao
    vincular(c, "profissional2")
    pedido_id = abrir_pedido(c)
    o1 = enviar_orcamento(c, pedido_id, "profissional")
    o2 = enviar_orcamento(c, pedido_id, "profissional2")

    def aceitar(orc):
        return acao(c, "cliente", pedido_id, "aceitar_orcamento", {"orcamento_id": orc}).status_code

    with ThreadPoolExecutor(max_workers=4) as pool:
        codigos = list(pool.map(aceitar, [o1, o2, o1, o2]))
    assert codigos.count(200) >= 1, codigos
    assert contratos_do_pedido(c, pedido_id) == 1, codigos
    assert all(codigo in (200, 409, 422) for codigo in codigos), codigos


def test_orcamento_no_formato_do_app_e_aceito(atuacao):  # noqa: F811
    """Contrato app <-> backend: o app monta o orçamento assim (ver ServicoOrcamentoApi.enviar)."""
    c = atuacao
    pedido_id = abrir_pedido(c)
    corpo = {
        "itens": [
            {
                "tipo": "horas",
                "descricao": "Mão de obra",
                "quantidade": 1,
                "valor_unitario_centavos": 12_000,
            },
            {
                "tipo": "deslocamento",
                "descricao": "Deslocamento",
                "quantidade": 1,
                "valor_unitario_centavos": 3_000,
            },
        ],
        "prazo_execucao_dias": 3,
        "validade_ate": (datetime.now(UTC) + timedelta(days=3)).isoformat(),
        "sinal_material_centavos": 0,
        "garantia_dias": 30,
    }
    r = post(c, f"/v1/pedidos/{pedido_id}/orcamentos", "profissional", corpo)
    assert r.status_code == 201, r.text
    assert r.json()["valor_total_centavos"] == 15_000


def test_orcamento_no_formato_antigo_do_app_e_recusado_com_motivo(atuacao):  # noqa: F811
    """O formato que o app mandava antes (sem `tipo`, preço com outro nome) é 422."""
    c = atuacao
    pedido_id = abrir_pedido(c)
    antigo = {
        "itens": [{"descricao": "Serviço", "quantidade": 1, "preco_unitario_centavos": 10_000}],
        "prazo_dias": 3,
        "validade_dias": 3,
    }
    r = post(c, f"/v1/pedidos/{pedido_id}/orcamentos", "profissional", antigo)
    assert r.status_code == 422, r.text


def test_cadastro_em_analise_nao_envia_orcamento_e_recebe_motivo_claro(atuacao):  # noqa: F811
    c = atuacao
    pedido_id = abrir_pedido(c)
    with c.local.admin() as con:
        antes = con.execute(
            "select status::text from public.perfis_profissional where usuario_id = %s",
            (c.ids["profissional"],),
        ).fetchone()[0]
        con.execute(
            "update public.perfis_profissional set status = 'em_analise' where usuario_id = %s",
            (c.ids["profissional"],),
        )
    try:
        r = post(c, f"/v1/pedidos/{pedido_id}/orcamentos", "profissional", corpo_orcamento())
    finally:
        with c.local.admin() as con:
            con.execute(
                "update public.perfis_profissional set status = %s where usuario_id = %s",
                (antes, c.ids["profissional"]),
            )
    assert r.status_code == 403, r.text
    assert "em análise" in r.json()["detail"]
