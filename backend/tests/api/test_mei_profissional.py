"""MEI do profissional: validação do CNPJ (BrasilAPI simulada) e bloqueio do orçamento."""

from __future__ import annotations

from datetime import UTC, datetime, timedelta

import pytest
from conftest import cab

from trato.pedidos.estados import Estado
from trato.profissional.mei import (
    ConfigMei,
    ConsultaCnpj,
    ServicoMei,
    StatusMei,
    cnpj_valido,
)

CNPJ_OK = "11222333000181"  # dígitos verificadores corretos (exemplo de teste)
CNPJ_DV_ERRADO = "11222333000182"
ORCAMENTO = {
    "itens": [
        {
            "tipo": "horas",
            "descricao": "Pintura",
            "quantidade": "1",
            "valor_unitario_centavos": 5000,
        }
    ],
    "garantia_dias": 90,
}


class Relogio:
    def __init__(self) -> None:
        self.t = datetime(2026, 11, 24, 12, 0, tzinfo=UTC)

    def __call__(self) -> datetime:
        return self.t


class BrasilApiFalsa:
    def __init__(self, resposta=None) -> None:
        self.resposta = resposta
        self.urls: list[str] = []

    def __call__(self, url):
        self.urls.append(url)
        if isinstance(self.resposta, Exception):
            raise self.resposta
        return self.resposta


def _corpo(ativa=True, mei=True):
    return {
        "razao_social": "JOAO DA SILVA 12345678900",
        "descricao_situacao_cadastral": "ATIVA" if ativa else "BAIXADA",
        "situacao_cadastral": 2 if ativa else 8,
        "opcao_pelo_mei": mei,
    }


def _servico(resposta, obrigatorio=True, relogio=None):
    relogio = relogio or Relogio()
    busca = BrasilApiFalsa(resposta)
    cfg = ConfigMei(obrigatorio=obrigatorio)
    return ServicoMei(consulta=ConsultaCnpj(busca, cfg, relogio), config=cfg, agora=relogio), busca


def test_digito_verificador():
    assert cnpj_valido("11.222.333/0001-81")
    assert not cnpj_valido(CNPJ_DV_ERRADO)
    assert not cnpj_valido("11111111111111")
    assert not cnpj_valido("123")
    assert not cnpj_valido(None)


def test_cnpj_invalido_nao_chama_a_api():
    svc, busca = _servico((200, _corpo()))
    r = svc.informar("pro-1", CNPJ_DV_ERRADO)
    assert r.mei_status is StatusMei.INVALIDO
    assert "não é válido" in r.mei_motivo
    assert busca.urls == []


def test_mei_ativo_valido_e_so_o_cnpj_sai_na_requisicao():
    svc, busca = _servico((200, _corpo()))
    r = svc.informar("pro-1", "11.222.333/0001-81")
    assert r.mei_status is StatusMei.VALIDO
    assert r.razao_social == "JOAO DA SILVA 12345678900"
    assert r.mei_validado_em is not None
    assert busca.urls == [f"https://brasilapi.com.br/api/cnpj/v1/{CNPJ_OK}"]
    assert svc.liberado("pro-1")


def test_cnpj_inativo_e_invalido():
    svc, _ = _servico((200, _corpo(ativa=False)))
    r = svc.informar("pro-1", CNPJ_OK)
    assert r.mei_status is StatusMei.INVALIDO
    assert "ativa" in r.mei_motivo
    assert not svc.liberado("pro-1")


def test_nao_mei_e_invalido():
    svc, _ = _servico((200, _corpo(mei=False)))
    r = svc.informar("pro-1", CNPJ_OK)
    assert r.mei_status is StatusMei.INVALIDO
    assert "não é de um MEI" in r.mei_motivo


def test_cnpj_inexistente_404_e_invalido():
    svc, _ = _servico((404, {"message": "nao encontrado"}))
    assert svc.informar("pro-1", CNPJ_OK).mei_status is StatusMei.INVALIDO


@pytest.mark.parametrize("resposta", [TimeoutError("lento"), (503, None), (429, None), (200, None)])
def test_api_fora_do_ar_fica_pendente_e_nunca_reprova(resposta):
    svc, busca = _servico(resposta)
    r = svc.informar("pro-1", CNPJ_OK)
    assert r.mei_status is StatusMei.PENDENTE
    assert len(busca.urls) == 2  # tentativa + 1 retry
    assert not svc.liberado("pro-1")


def test_pendente_revalida_na_leitura_quando_a_api_volta():
    svc, busca = _servico(TimeoutError("x"))
    assert svc.informar("pro-1", CNPJ_OK).mei_status is StatusMei.PENDENTE
    busca.resposta = (200, _corpo())
    assert svc.status("pro-1").mei_status is StatusMei.VALIDO


def test_cache_de_24h_nao_repete_a_consulta_e_expira():
    relogio = Relogio()
    svc, busca = _servico((200, _corpo()), relogio=relogio)
    svc.informar("pro-1", CNPJ_OK)
    svc.informar("pro-2", CNPJ_OK)
    assert len(busca.urls) == 1
    relogio.t += timedelta(hours=25)
    svc.informar("pro-3", CNPJ_OK)
    assert len(busca.urls) == 2


def test_falha_nao_entra_no_cache():
    svc, busca = _servico((503, None))
    svc.informar("pro-1", CNPJ_OK)
    svc.informar("pro-1", CNPJ_OK)
    assert len(busca.urls) == 4


def test_nao_informado_por_padrao():
    svc, _ = _servico((200, _corpo()))
    assert svc.status("pro-9").mei_status is StatusMei.NAO_INFORMADO
    assert not svc.liberado("pro-9")


# --- API -------------------------------------------------------------------------------------


def _liga(amb, resposta, obrigatorio=True):
    svc, busca = _servico(resposta, obrigatorio=obrigatorio)
    amb.cliente.app.state.servico_mei = svc
    return svc, busca


def test_rota_envia_cnpj_e_le_status(amb):
    _liga(amb, (200, _corpo()))
    r = amb.cliente.get("/v1/profissional/mei", headers=cab("t-prof"))
    assert r.status_code == 200
    assert r.json()["mei_status"] == "nao_informado"
    assert r.json()["pode_orcar_e_receber"] is False
    r = amb.cliente.put("/v1/profissional/mei", json={"cnpj": CNPJ_OK}, headers=cab("t-prof"))
    assert r.status_code == 200, r.text
    assert r.json()["mei_status"] == "valido"
    assert r.json()["pode_orcar_e_receber"] is True
    assert amb.cliente.get("/v1/profissional/mei", headers=cab("t-prof")).json()["cnpj"] == CNPJ_OK


def test_rota_so_para_profissional(amb):
    _liga(amb, (200, _corpo()))
    assert amb.cliente.get("/v1/profissional/mei", headers=cab("t-cliente")).status_code == 403
    assert amb.cliente.get("/v1/profissional/mei").status_code == 401


def test_orcamento_bloqueado_sem_mei_valido_e_liberado_com_mei(amb):
    amb.semear_pedido(Estado.ABERTO, profissional_id=None, orcamento_id=None)
    _liga(amb, (200, _corpo(mei=False)))
    r = amb.cliente.post("/v1/pedidos/ped-1/orcamentos", json=ORCAMENTO, headers=cab("t-prof"))
    assert r.status_code == 422
    assert "MEI" in r.json()["detail"]

    amb.cliente.put("/v1/profissional/mei", json={"cnpj": CNPJ_OK}, headers=cab("t-prof"))
    r = amb.cliente.post("/v1/pedidos/ped-1/orcamentos", json=ORCAMENTO, headers=cab("t-prof"))
    assert r.status_code == 422  # ainda não-MEI

    svc, busca = _liga(amb, (200, _corpo()))
    amb.cliente.put("/v1/profissional/mei", json={"cnpj": CNPJ_OK}, headers=cab("t-prof"))
    r = amb.cliente.post("/v1/pedidos/ped-1/orcamentos", json=ORCAMENTO, headers=cab("t-prof"))
    assert r.status_code == 201, r.text


def test_orcamento_bloqueado_com_api_fora_do_ar(amb):
    amb.semear_pedido(Estado.ABERTO, profissional_id=None, orcamento_id=None)
    _liga(amb, TimeoutError("x"))
    amb.cliente.put("/v1/profissional/mei", json={"cnpj": CNPJ_OK}, headers=cab("t-prof"))
    r = amb.cliente.post("/v1/pedidos/ped-1/orcamentos", json=ORCAMENTO, headers=cab("t-prof"))
    assert r.status_code == 422


def test_bloqueio_desligado_nao_afeta_orcamento(amb):
    amb.semear_pedido(Estado.ABERTO, profissional_id=None, orcamento_id=None)
    _liga(amb, (200, _corpo()), obrigatorio=False)
    r = amb.cliente.post("/v1/pedidos/ped-1/orcamentos", json=ORCAMENTO, headers=cab("t-prof"))
    assert r.status_code == 201, r.text
