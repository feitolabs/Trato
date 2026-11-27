"""TERMOS-BE-ACORDO no Postgres local: o acordo com devolução cabe na tabela atual, não repete e
não corre junto com a decisão do analista."""

from __future__ import annotations

import threading
from datetime import UTC, datetime, timedelta

import pytest

from .test_ausencia_cliente_postgres import _post
from .test_ausencia_reembolso_postgres import pago_e_agendado
from .test_compensacao_postgres import avisos  # noqa: F401 - `avisos` é fixture
from .test_disputa_painel_postgres import decidir, devolvido, equipe  # noqa: F401 - fixture
from .test_liberacao_automatica_postgres import (  # noqa: F401 - `publicado` é fixture
    a_liberar_de,
    agendador,
    publicado,
    repasses,
)
from .test_pagamento_postgres import (  # noqa: F401
    VALOR_ORCAMENTO,
    linhas,
    migrations_novas,
    pg,
)

pytestmark = pytest.mark.integracao
PARTE = VALOR_ORCAMENTO // 4
ACEITE = {"solucao": "reembolso_parcial", "reembolso_centavos": PARTE}


def respondida(c) -> tuple[str, str]:
    pid, cobranca, _ = pago_e_agendado(c)
    url = f"/v1/pedidos/{pid}/disputa"
    foto = {"arquivo_id": "a" * 32, "tirada_em": datetime.now(UTC).isoformat()}
    abrir = {"motivo": "nao_compareceu", "descricao": "Combinou e não veio.", "fotos": [foto]}
    r = _post(c, "cliente", url, abrir)
    assert r.status_code == 201, r.text
    resposta = {
        "mensagem": "Proponho devolver uma parte.",
        "solucao": "reembolso_parcial",
        "reembolso_parcial_centavos": PARTE,
    }
    r = _post(c, "profissional", f"{url}/resposta", resposta)
    assert r.status_code == 200, r.text
    assert r.json()["proposta"]["reembolso_centavos"] == PARTE
    return pid, cobranca


def aceitar(c, pid):
    return _post(c, "cliente", f"/v1/pedidos/{pid}/disputa/aceitar-proposta", ACEITE)


def juntos(funcoes):
    respostas = []
    threads = [threading.Thread(target=lambda f=f: respostas.append(f())) for f in funcoes]
    for t in threads:
        t.start()
    for t in threads:
        t.join()
    return respostas


def registro(c, pid):
    sql = (
        "select status, decisao, valor_reembolso_centavos, decidida_por "
        "from public.disputas where pedido_id = %s"
    )
    return [tuple(x) for x in linhas(c, sql, (pid,))]


def test_aceites_simultaneos_devolvem_uma_vez_e_liberam_o_resto(publicado):  # noqa: F811
    c = publicado
    pid, cobranca = respondida(c)
    respostas = juntos([lambda: aceitar(c, pid)] * 4)
    assert [r.status_code for r in respostas] == [200] * 4, [r.text for r in respostas]
    assert respostas[0].json()["acordo"]["reembolso_centavos"] == PARTE
    assert registro(c, pid) == [("acordo", "reembolso_parcial", PARTE, None)]
    assert devolvido(c, cobranca) == [PARTE]
    resto = a_liberar_de(c, pid)
    assert resto == VALOR_ORCAMENTO - PARTE
    assert aceitar(c, pid).status_code == 200 and devolvido(c, cobranca) == [PARTE]
    assert decidir(c, pid).status_code == 409
    for _ in range(2):
        assert agendador(c, pid, timedelta(days=10)).rodar_uma_vez().falhas == 0
    assert repasses(c, pid) == 1 and a_liberar_de(c, pid) == 0


@pytest.mark.parametrize("rodada", range(3))
def test_aceite_junto_com_a_decisao_do_analista(publicado, rodada):  # noqa: F811
    c = publicado
    pid, cobranca = respondida(c)
    pares = [lambda: aceitar(c, pid), lambda: decidir(c, pid)]
    if rodada % 2:
        pares.reverse()
    respostas = juntos(pares)
    codigos = sorted(r.status_code for r in respostas)
    assert codigos == [200, 409], [r.text for r in respostas]
    ((status, *_),) = registro(c, pid)
    assert devolvido(c, cobranca) == [PARTE if status == "acordo" else VALOR_ORCAMENTO]
