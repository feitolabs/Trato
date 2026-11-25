"""PUT /v1/profissional/mei: 5 por hora por usuário (regra padrão do limitador HTTP)."""

from __future__ import annotations

from ambiente_seg import cab, montar

from trato.profissional.mei import ConfigMei, ConsultaCnpj, ServicoMei


def test_sexta_tentativa_de_informar_cnpj_em_uma_hora_leva_429():
    amb = montar()
    cfg = ConfigMei()
    # nunca chama a BrasilAPI real: se chamasse, a resposta simulada é esta
    amb.app.state.servico_mei = ServicoMei(
        consulta=ConsultaCnpj(lambda _url: (404, None), cfg), config=cfg
    )
    cabecalho = cab("t-cli")  # mesmo token = mesmo usuário
    codigos = [
        amb.cliente.put("/v1/profissional/mei", json={"cnpj": "1"}, headers=cabecalho).status_code
        for _ in range(6)
    ]
    assert 429 not in codigos[:5]
    assert codigos[5] == 429
    # leitura não entra na regra do PUT
    assert amb.cliente.get("/v1/profissional/mei", headers=cabecalho).status_code != 429
    # outro usuário tem o próprio limite
    assert (
        amb.cliente.put(
            "/v1/profissional/mei", json={"cnpj": "1"}, headers=cab("t-outro")
        ).status_code
        != 429
    )
