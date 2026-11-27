"""BE-1A no Postgres local: a trava de saques não promete bloquear dinheiro, aceita conta já
restrita, não rebaixa conta bloqueada e o destravar respeita outra medida em vigor."""

from __future__ import annotations

import threading

from .test_ausencia_cliente_postgres import _post
from .test_disputa_painel_postgres import equipe  # noqa: F401 - fixture
from .test_medidas_postgres import aplicar, limpar, status
from .test_pagamento_postgres import (  # noqa: F401 - `pg` e `migrations_novas` são fixtures
    linhas,
    migrations_novas,
    pg,
)

RISCO = "/v1/admin/risco"
AVISO = "NÃO são bloqueados automaticamente"
TRAVAS = (
    "select count(*) from public.medidas_conta where usuario_id = %s "
    "and tipo = 'trava_saque' and revertida_em is null"
)


def _corpo(c, motivo="Análise de repasses suspeitos."):
    return {"usuario_id": c.ids["profissional"], "motivo": motivo}


def _travas(c) -> int:
    return linhas(c, TRAVAS, (c.ids["profissional"],))[0][0]


def test_trava_avisa_e_repetir_ao_mesmo_tempo_cria_uma_so(pg, equipe):  # noqa: F811
    limpar(pg)
    try:
        respostas = []

        def travar(n):
            corpo = _corpo(pg, f"Análise de repasses número {n}.")
            respostas.append(_post(pg, "adm_a", f"{RISCO}/travar-saque", corpo))

        threads = [threading.Thread(target=travar, args=(n,)) for n in range(4)]
        for t in threads:
            t.start()
        for t in threads:
            t.join()
        assert [r.status_code for r in respostas] == [200] * 4, [r.text for r in respostas]
        for r in respostas:
            texto = r.json()["mensagem"]
            assert AVISO in texto and "restrita" in texto and "travados" not in texto
        assert status(pg) == "restrito" and _travas(pg) == 1

        r = _post(pg, "adm_a", f"{RISCO}/destravar-saque", _corpo(pg))
        assert r.status_code == 200, r.text
        assert "reativada" in r.json()["mensagem"] and "liberados" not in r.json()["mensagem"]
        assert status(pg) == "ativo" and _travas(pg) == 0
    finally:
        limpar(pg)


def test_conta_restrita_aceita_trava_e_destravar_mantem_a_restricao(pg, equipe):  # noqa: F811
    limpar(pg)
    try:
        assert aplicar(pg).status_code == 201
        assert status(pg) == "restrito"
        r = _post(pg, "adm_a", f"{RISCO}/travar-saque", _corpo(pg))
        assert r.status_code == 200, r.text
        assert status(pg) == "restrito" and _travas(pg) == 1

        r = _post(pg, "adm_a", f"{RISCO}/destravar-saque", _corpo(pg))
        assert r.status_code == 200, r.text
        assert "continua restrita" in r.json()["mensagem"]
        assert status(pg) == "restrito" and _travas(pg) == 0
    finally:
        limpar(pg)


def test_conta_bloqueada_nao_e_rebaixada(pg, equipe):  # noqa: F811
    limpar(pg)
    try:
        assert _post(pg, "adm_a", f"{RISCO}/travar-saque", _corpo(pg)).status_code == 200
        r = _post(pg, "adm_a", f"{RISCO}/bloqueio-preventivo", _corpo(pg))
        assert r.status_code == 200, r.text
        for rota in ("travar-saque", "destravar-saque"):
            r = _post(pg, "adm_a", f"{RISCO}/{rota}", _corpo(pg))
            assert r.status_code == 409, (rota, r.text)
            assert status(pg) == "bloqueado" and _travas(pg) == 1
        # Desbloquear devolve ao que a trava (ainda em vigor) pede.
        assert _post(pg, "adm_a", f"{RISCO}/desbloqueio", _corpo(pg)).status_code == 200
        assert status(pg) == "restrito" and _travas(pg) == 1
    finally:
        limpar(pg)
