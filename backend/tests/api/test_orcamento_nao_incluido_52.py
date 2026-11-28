"""BE-TERMOS-96-52 (5.2): o orçamento sempre diz o que não está incluído. A API exige; o antigo
sem o campo ganha um texto que só avisa que não foi informado."""

from __future__ import annotations

from dataclasses import replace

import pytest
from test_orcamentos_do_profissional_e_papel import ORC, _aberto, _post

from trato.api.validade import FORA_DO_ESCOPO_NAO_INFORMADO

URL = "/v1/pedidos/ped-1/orcamentos"


@pytest.mark.parametrize("valor", [None, "", "   ", "x"])
def test_envio_sem_o_que_nao_esta_incluido_e_recusado(amb, valor):
    _aberto(amb)
    assert _post(amb, URL, "t-prof", ORC | {"fora_do_escopo": valor}).status_code == 422
    sem = {k: v for k, v in ORC.items() if k != "fora_do_escopo"}
    assert _post(amb, URL, "t-prof", sem).status_code == 422
    assert not amb.contexto.orcamentos.do_pedido("ped-1")


def test_nova_versao_de_orcamento_antigo_usa_o_texto_de_nao_informado(amb):
    _aberto(amb)
    novo = _post(amb, URL, "t-prof", ORC).json()["id"]
    detalhes = amb.contexto.orcamentos._detalhes
    detalhes[novo] = replace(detalhes[novo], fora_do_escopo=None)  # como um orçamento antigo
    base = f"{URL}/{novo}/contraproposta"
    r = _post(amb, base, "t-cliente", {"valor_centavos": 8_000})
    assert r.status_code < 300, r.text
    r = _post(amb, f"{base}/aceitar", "t-prof", {"valor_centavos": 8_000})
    assert r.status_code < 300, r.text
    (atual,) = [o for o in amb.contexto.orcamentos.do_pedido("ped-1")]
    assert amb.contexto.orcamentos.detalhe(atual.id).fora_do_escopo == FORA_DO_ESCOPO_NAO_INFORMADO
