"""B42 no Postgres: gatilho de indicação mais firme, reajuste com valor e visitas só com partes aptas."""

from __future__ import annotations

import threading
import time
import uuid
from dataclasses import replace
from datetime import timedelta

import pytest

from trato.agendador.executor import ExecutorContexto
from trato.api.indicacoes import acionar_gatilho
from trato.financeiro.ledger import Livro, registrar_cobranca

from .test_b32_nota_decimal_postgres import _concluir
from .test_dinheiro_postgres import contratar, pagar_pelo_webhook
from .test_fluxo_postgres import agora
from .test_rotas_app_postgres import get, post

pytestmark = pytest.mark.integracao


def _novo(c, nome: str, email: str | None = None) -> str:
    chave = f"b42-{uuid.uuid4().hex[:8]}"
    uid = str(uuid.uuid4())
    with c.local.admin() as con:
        con.execute("insert into auth.users (id, email) values (%s, %s)", (uid, email))
        con.execute("insert into public.usuarios (id, nome) values (%s, %s)", (uid, nome))
    c.ids[chave] = uid
    return uid


def _vinculo(c, indicador: str, indicado: str, tipo: str = "cliente_cliente"):
    codigo = "B42" + uuid.uuid4().hex[:6].upper()
    bonus = {
        "cliente_cliente": (300, 300),
        "profissional_cliente": (150, 300),
        "profissional_profissional": (150, 100),
    }[tipo]
    return c.contexto.indicacoes.criar(indicador, indicado, codigo, tipo, *bonus, agora())


def _linha(c, indicado: str):
    with c.local.admin() as con:
        return con.execute(
            "select status, motivo_bloqueio, pedido_gatilho_id::text, bonus_indicador_tratinhos "
            "from public.indicacoes where indicado_id = %s",
            (indicado,),
        ).fetchone()


def test_gatilho_bloqueia_contraparte_igual_ao_indicador_ou_com_mesmo_contato(cenario):
    c = cenario
    pedido_id = contratar(c)
    assert pagar_pelo_webhook(c, pedido_id).status_code == 200  # R$ 900,00 pagos
    pedido = c.contexto.pedidos.obter(pedido_id)

    # a1) profissional_cliente: o indicador É o profissional do pedido = fluxo planejado, arma
    indicado_a = _novo(c, "Indicado A Teste")
    vinculo_a = _vinculo(c, c.ids["profissional"], indicado_a, "profissional_cliente")
    armadas_a = acionar_gatilho(c.contexto, replace(pedido, cliente_id=indicado_a), agora())
    assert [a.id for a in armadas_a] == [vinculo_a.id]
    assert tuple(_linha(c, indicado_a))[:3] == ("aguardando_liberacao", "", pedido_id)

    # a2) cliente_cliente: o indicador é o profissional do pedido = bloqueia
    indicado_a2 = _novo(c, "Indicado A2 Teste")
    _vinculo(c, c.ids["profissional"], indicado_a2, "cliente_cliente")
    assert acionar_gatilho(c.contexto, replace(pedido, cliente_id=indicado_a2), agora()) == []
    assert tuple(_linha(c, indicado_a2))[:3] == (
        "bloqueado_fraude",
        "contraparte_e_o_indicador",
        None,
    )
    assert _linha(c, indicado_a2)[3] == 0

    # a3) profissional_profissional: o indicador é o cliente do pedido = bloqueia
    indicado_a3 = c.ids["profissional2"]
    _vinculo(c, c.ids["cliente"], indicado_a3, "profissional_profissional")
    assert acionar_gatilho(c.contexto, replace(pedido, profissional_id=indicado_a3), agora()) == []
    assert tuple(_linha(c, indicado_a3))[:2] == ("bloqueado_fraude", "contraparte_e_o_indicador")

    # b) a outra ponta é outra conta com o mesmo e-mail normalizado do indicador
    indicador_b = _novo(c, "Indicador B Teste", email="a.b+trato@gmail.com")
    contraparte_b = _novo(c, "Contraparte B Teste", email="ab@GMAIL.com")
    indicado_b = _novo(c, "Indicado B Teste")
    _vinculo(c, indicador_b, indicado_b)
    por_email = replace(pedido, cliente_id=indicado_b, profissional_id=contraparte_b)
    assert acionar_gatilho(c.contexto, por_email, agora()) == []
    assert tuple(_linha(c, indicado_b))[:2] == ("bloqueado_fraude", "contraparte_mesmo_email")

    # c) contraparte sem relação com o indicador: arma normalmente (e conta o limite sob trava)
    indicador_c = _novo(c, "Indicador C Teste", email="c@exemplo.com")
    indicado_c = _novo(c, "Indicado C Teste")
    vinculo_c = _vinculo(c, indicador_c, indicado_c)
    armadas = acionar_gatilho(c.contexto, replace(pedido, cliente_id=indicado_c), agora())
    assert [a.id for a in armadas] == [vinculo_c.id]
    linha = _linha(c, indicado_c)
    assert linha[0] == "aguardando_liberacao" and linha[2] == pedido_id and linha[3] == 300


def test_gatilho_exige_o_minimo_pago_em_dinheiro(cenario):
    c = cenario
    pedido_id = contratar(c)  # contrato de R$ 900,00, mas ainda sem pagamento
    pedido = c.contexto.pedidos.obter(pedido_id)

    def pagar(valor: int) -> None:
        livro = Livro()
        registrar_cobranca(livro, pedido_id, valor, f"cob-{uuid.uuid4().hex}", agora())
        c.contexto.ledger.lancar_varios(livro.lancamentos)

    indicador = _novo(c, "Indicador Pago Teste")
    indicado = _novo(c, "Indicado Pago Teste")
    _vinculo(c, indicador, indicado)
    do_indicado = replace(pedido, cliente_id=indicado)
    pagar(5_999)
    assert acionar_gatilho(c.contexto, do_indicado, agora()) == []  # contrato alto, pago pouco
    assert _linha(c, indicado)[0] == "cadastrado"
    pagar(1)  # completa R$ 60,00 pagos
    assert len(acionar_gatilho(c.contexto, do_indicado, agora())) == 1
    assert _linha(c, indicado)[0] == "aguardando_liberacao"


def test_trava_do_indicador_enfileira_os_gatilhos_no_postgres(cenario):
    c = cenario
    repo = c.contexto.indicacoes
    indicador = str(uuid.uuid4())
    marcas: dict[str, float] = {}
    dentro = threading.Event()

    def primeiro() -> None:
        with repo.trava_do_indicador(indicador):
            dentro.set()
            time.sleep(0.5)
            marcas["primeiro_saiu"] = time.monotonic()

    def segundo() -> None:
        dentro.wait(5)
        with repo.trava_do_indicador(indicador):
            marcas["segundo_entrou"] = time.monotonic()

    fios = [threading.Thread(target=primeiro), threading.Thread(target=segundo)]
    for fio in fios:
        fio.start()
    for fio in fios:
        fio.join(10)
    assert marcas["segundo_entrou"] >= marcas["primeiro_saiu"] - 0.01  # esperou o 1º terminar


def _serie_ativa(c) -> tuple[str, int]:
    origem = _concluir(c)
    primeira = agora() + timedelta(hours=30)
    r = post(
        c,
        "/v1/recorrencias",
        "cliente",
        {
            "pedido_origem_id": origem,
            "frequencia": "semanal",
            "proxima_visita_em": primeira.isoformat(),
        },
    )
    assert r.status_code == 201, r.text
    rid = r.json()["id"]
    ok = post(c, f"/v1/recorrencias/{rid}/aceitar", "profissional")
    assert ok.status_code == 200, ok.text
    return rid, ok.json()["valor_centavos"]


def test_aceite_do_reajuste_exige_o_valor_e_barra_proposta_em_cima_de_proposta(cenario):
    c = cenario
    rid, valor = _serie_ativa(c)
    base = f"/v1/recorrencias/{rid}"
    assert (
        post(c, f"{base}/reajuste", "profissional", {"valor_centavos": valor + 500}).status_code
        == 200
    )
    segunda = post(c, f"{base}/reajuste", "profissional", {"valor_centavos": valor + 900})
    assert segunda.status_code == 409 and "esperando resposta" in segunda.json()["detail"]
    assert post(c, f"{base}/reajuste/aceitar", "cliente").status_code == 422  # sem o valor
    errado = post(c, f"{base}/reajuste/aceitar", "cliente", {"valor_centavos": valor + 900})
    assert errado.status_code == 409
    assert errado.json()["detail"] == "O valor do reajuste mudou. Confira o novo valor."
    assert get(c, base, "cliente").json()["valor_centavos"] == valor  # nada mudou
    ok = post(c, f"{base}/reajuste/aceitar", "cliente", {"valor_centavos": valor + 500})
    assert ok.status_code == 200 and ok.json()["valor_centavos"] == valor + 500
    assert ok.json()["valor_proposto_centavos"] is None
    assert (
        post(c, f"{base}/reajuste/aceitar", "cliente", {"valor_centavos": valor + 500}).status_code
        == 409
    )
    assert post(c, f"{base}/cancelar", "cliente").status_code == 200  # limpa a série


def test_cliente_inativo_pausa_a_serie_e_nao_gera_visita(cenario):
    c = cenario
    rid, _ = _serie_ativa(c)
    with c.local.admin() as con:
        con.execute(
            "update public.usuarios set status = 'restrito' where id = %s", (c.ids["cliente"],)
        )
    try:
        ExecutorContexto(c.contexto).gerar_visitas_recorrentes(agora())
        detalhe = get(c, f"/v1/recorrencias/{rid}", "profissional").json()
        assert detalhe["status"] == "pausada" and detalhe["visitas"] == []
    finally:
        with c.local.admin() as con:
            con.execute(
                "update public.usuarios set status = 'ativo' where id = %s", (c.ids["cliente"],)
            )
    assert post(c, f"/v1/recorrencias/{rid}/cancelar", "profissional").status_code == 200
