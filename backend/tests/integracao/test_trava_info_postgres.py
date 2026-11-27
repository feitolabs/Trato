"""BE-TRAVA-INFO no Postgres local: fila de risco, busca de usuários e prazo máximo."""

from __future__ import annotations

from .test_ausencia_cliente_postgres import _post
from .test_disputa_painel_postgres import equipe  # noqa: F401 - fixture
from .test_medidas_postgres import limpar
from .test_pagamento_postgres import (  # noqa: F401 - `pg` e `migrations_novas` são fixtures
    migrations_novas,
    pg,
)


def test_fila_busca_e_prazo(pg, equipe):  # noqa: F811
    limpar(pg)
    quem = pg.ids["profissional"]
    with pg.local.admin() as con:
        alerta = con.execute(
            "insert into public.alertas_risco (usuario_id, tipo, severidade, detalhes) "
            "values (%s, 'denuncia_perfil', 'alta', 'Teste da trava.') returning id",
            (quem,),
        ).fetchone()[0]

    def get(url):
        r = pg.pagto[0].get(url, headers=pg.token("adm_a"))
        assert r.status_code == 200, r.text
        return r.json()

    def na_fila():
        (item,) = [a for a in get("/v1/admin/risco/alertas") if a["id"] == str(alerta)]
        return item["trava_fraude_vigente"]

    def no_detalhe():
        return get(f"/v1/admin/usuarios/{quem}")["trava_fraude_vigente"]

    try:
        assert na_fila() is False and no_detalhe() is False
        corpo = {
            "usuario_id": quem,
            "motivo": "Fraude em apuração.",
            "motivo_fraude": True,
            "limite_retencao_centavos": 500,
        }
        r = _post(pg, "adm_a", "/v1/admin/risco/travar-saque", corpo)
        assert r.status_code == 200, r.text
        assert na_fila() is True and no_detalhe() is True
        assert get("/v1/admin/medidas/trava-fraude") == {"prazo_maximo_dias": 30}
        r = _post(pg, "adm_a", "/v1/admin/risco/destravar-saque", corpo)
        assert r.status_code == 200, r.text
        assert na_fila() is False and no_detalhe() is False
    finally:
        limpar(pg)
        with pg.local.admin() as con:
            con.execute("delete from public.alertas_risco where id = %s", (alerta,))
