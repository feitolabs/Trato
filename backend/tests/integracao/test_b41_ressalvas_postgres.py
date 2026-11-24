"""B41 no Postgres: visita recorrente fora do feed, limites e antifraude com as constraints reais."""

from __future__ import annotations

import uuid
from datetime import timedelta

import pytest

from trato.agendador.executor import ExecutorContexto

from .test_b32_nota_decimal_postgres import _concluir
from .test_dinheiro_postgres import contratar, pagar_pelo_webhook
from .test_fluxo_postgres import agora
from .test_rotas_app_postgres import get, post

pytestmark = pytest.mark.integracao


def _novo(c, nome: str, email: str | None = None) -> str:
    chave = f"b41-{uuid.uuid4().hex[:8]}"
    uid = str(uuid.uuid4())
    with c.local.admin() as con:
        con.execute("insert into auth.users (id, email) values (%s, %s)", (uid, email))
        con.execute("insert into public.usuarios (id, nome) values (%s, %s)", (uid, nome))
    c.ids[chave] = uid
    return chave


def _atuam(c) -> None:
    with c.local.admin() as con:
        for quem in ("profissional", "profissional2"):
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


def test_pedido_de_visita_so_aparece_para_o_profissional_da_serie(cenario):
    c = cenario
    _atuam(c)
    origem = _concluir(c)
    proposta = post(
        c,
        "/v1/recorrencias",
        "cliente",
        {
            "pedido_origem_id": origem,
            "frequencia": "semanal",
            "proxima_visita_em": (agora() + timedelta(hours=30)).isoformat(),
        },
    )
    assert proposta.status_code == 201, proposta.text
    rid = proposta.json()["id"]
    assert post(c, f"/v1/recorrencias/{rid}/aceitar", "profissional").status_code == 200
    assert ExecutorContexto(c.contexto).gerar_visitas_recorrentes(agora()) == 1
    (visita,) = get(c, f"/v1/recorrencias/{rid}", "cliente").json()["visitas"]
    pedido_visita = visita["pedido_id"]

    do_dono = get(c, "/v1/profissional/pedidos-abertos", "profissional").json()
    de_outro = get(c, "/v1/profissional/pedidos-abertos", "profissional2").json()
    assert pedido_visita in [p["id"] for p in do_dono]
    assert pedido_visita not in [p["id"] for p in de_outro]
    detalhe = get(c, f"/v1/profissional/pedidos-abertos/{pedido_visita}", "profissional2")
    assert detalhe.status_code == 404
    orcamento = {
        "itens": [
            {
                "tipo": "horas",
                "descricao": "Mão de obra",
                "quantidade": 1,
                "valor_unitario_centavos": 5_000,
            }
        ]
    }
    assert (
        post(c, f"/v1/pedidos/{pedido_visita}/orcamentos", "profissional2", orcamento).status_code
        == 404
    )


def test_denuncias_de_perfil_com_limites_e_chat_com_denunciado_e_teto(cenario):
    c = cenario
    denunciante = _novo(c, "Denunciante Teste")
    alvo = c.ids["profissional"]
    corpo = {
        "alvo_tipo": "perfil",
        "denunciado_id": alvo,
        "motivo": "perfil_falso",
        "detalhes": "Fotos de outra pessoa.",
    }
    assert post(c, "/v1/denuncias", denunciante, corpo).status_code == 201
    repetida = post(c, "/v1/denuncias", denunciante, corpo)
    assert repetida.status_code == 409 and "24 horas" in repetida.json()["detail"]
    # 10 por dia: já houve 1; mais 9 alvos novos fecham 10; o 11º leva 429.
    for n in range(9):
        outro = _novo(c, f"Alvo {n} Teste")
        assert (
            post(
                c, "/v1/denuncias", denunciante, dict(corpo, denunciado_id=c.ids[outro])
            ).status_code
            == 201
        )
    ultimo = _novo(c, "Alvo Final Teste")
    r = post(c, "/v1/denuncias", denunciante, dict(corpo, denunciado_id=c.ids[ultimo]))
    assert r.status_code == 429 and "limite de denúncias" in r.json()["detail"]

    # Chat: o denunciado entra no texto e o texto somado nunca passa de 2000 caracteres.
    pedido_id = contratar(c)
    chat = {
        "alvo_tipo": "chat",
        "denunciado_id": c.ids["profissional"],
        "pedido_id": pedido_id,
        "motivo": "outro",
        "detalhes": "y" * 500,
    }
    ids = {post(c, "/v1/denuncias", "cliente", chat).json()["id"] for _ in range(8)}
    assert len(ids) == 1  # mesmo alerta aberto do pedido
    with c.local.admin() as con:
        texto = con.execute(
            "select detalhes from public.alertas_risco where id = %s", (ids.pop(),)
        ).fetchone()[0]
    assert f" por {c.ids['cliente']} contra {c.ids['profissional']}:" in texto
    assert len(texto) <= 2000


def test_reagendamento_limites_e_historico_com_quem_aceitou(cenario):
    c = cenario
    pedido_id = contratar(c)
    assert pagar_pelo_webhook(c, pedido_id).status_code == 200  # pago_e_retido
    url = f"/v1/pedidos/{pedido_id}/reagendamentos"

    def janela(dias: int) -> dict:
        inicio = agora() + timedelta(days=dias)
        return {
            "nova_janela_inicio": inicio.isoformat(),
            "nova_janela_fim": (inicio + timedelta(hours=2)).isoformat(),
        }

    longe = post(c, url, "profissional", janela(61))
    assert longe.status_code == 422 and "60 dias" in longe.json()["detail"]
    proposta = post(c, url, "profissional", janela(5))
    assert proposta.status_code == 201, proposta.text
    aceite = post(c, f"{url}/{proposta.json()['id']}/aceitar", "cliente")
    assert aceite.status_code == 200, aceite.text
    assert aceite.json()["respondido_por"] == c.ids["cliente"]
    with c.local.admin() as con:
        ator = con.execute(
            "select ator_id::text from public.pedido_historico where pedido_id = %s "
            "and para_status = 'agendado' order by id desc limit 1",
            (pedido_id,),
        ).fetchone()[0]
    assert ator == c.ids["cliente"]  # quem de fato aceitou, não o profissional que propôs
    # 5 propostas por dia: já houve 1 (aceita); mais 4 (cada uma recusada) fecham 5.
    for n in range(4):
        r = post(c, url, "cliente", janela(6 + n))
        assert r.status_code == 201, r.text
        assert post(c, f"{url}/{r.json()['id']}/recusar", "profissional").status_code == 200
    sexta = post(c, url, "cliente", janela(12))
    assert sexta.status_code == 429


def test_indicacao_consulta_com_limite_e_antifraude_por_email(cenario):
    c = cenario
    indicador = _novo(c, "Maria Lima Santos", email="maria.lima+trato@gmail.com")
    indicado = _novo(c, "Maria Outra Conta", email="marialima@GMAIL.com")
    codigo = get(c, "/v1/indicacoes/meu-codigo", indicador).json()["codigo"]
    r = post(c, "/v1/indicacoes/aplicar", indicado, {"codigo": codigo})
    assert r.status_code == 201, r.text
    assert (r.json()["status"], r.json()["bonus_indicado_tratinhos"]) == ("bloqueado_fraude", 0)
    with c.local.admin() as con:
        linha = con.execute(
            "select status, motivo_bloqueio, bonus_indicador_tratinhos, bonus_indicado_tratinhos "
            "from public.indicacoes where indicado_id = %s",
            (c.ids[indicado],),
        ).fetchone()
    assert tuple(linha) == ("bloqueado_fraude", "mesmo_email", 0, 0)
    # e-mails diferentes seguem normais
    limpo = _novo(c, "Pessoa Diferente", email="outra.pessoa@exemplo.com")
    ok = post(c, "/v1/indicacoes/aplicar", limpo, {"codigo": codigo})
    assert ok.status_code == 201 and ok.json()["status"] == "cadastrado"

    # Consulta pública: 20 por minuto por IP, depois 429 com Retry-After.
    for _ in range(20):
        assert c.cliente.get(f"/v1/indicacoes/codigo/{codigo}").status_code == 200
    bloqueada = c.cliente.get(f"/v1/indicacoes/codigo/{codigo}")
    assert bloqueada.status_code == 429 and int(bloqueada.headers["retry-after"]) >= 1
