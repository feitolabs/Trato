"""BE-ACESSOS no Postgres LOCAL: registro, repetição, expurgo com preservação e sem a
migration."""

from __future__ import annotations

from concurrent.futures import ThreadPoolExecutor

import pytest

from trato.persistencia.acessos import Acesso, AcessosPostgres

from .test_pagamento_postgres import linhas, migrations_novas, pg  # noqa: F401
from .test_tratinhos_encerramento_postgres import pessoa

pytestmark = pytest.mark.integracao
CONTAR = "select count(*) from public.acessos_conta where usuario_id = %s"


def antigo(c, usuario):
    """Registro com 7 meses: só o dono do banco consegue inserir com data passada."""
    with c.local.admin() as con:
        con.execute(
            "insert into public.acessos_conta (usuario_id, evento, ip, ocorrido_em) "
            "values (%s, 'acesso', '198.51.100.7', now() - interval '7 months')",
            (usuario,),
        )


def contar(c, usuario):
    return linhas(c, CONTAR, (usuario,))[0][0]


def test_registra_e_nao_repete_na_janela_mesmo_em_paralelo(pg):  # noqa: F811
    repo = AcessosPostgres(pg.banco)
    uid = pessoa(pg)
    acesso = Acesso(uid, "acesso", "198.51.100.10", "ios", "iOS 20", "ap-9", "app", "1.0")
    with ThreadPoolExecutor(4) as pool:
        saidas = sorted(pool.map(lambda _: repo.registrar(acesso, 60), range(4)))
    assert saidas == ["registrado", "repetido", "repetido", "repetido"]
    assert contar(pg, uid) == 1
    assert repo.registrar(Acesso(uid, "login", "ip-ruim"), 0) == "ip_invalido"


def test_expurgo_apaga_so_o_antigo_sem_guarda_e_repetir_nao_faz_nada(pg):  # noqa: F811
    repo = AcessosPostgres(pg.banco)
    livre, guardado = pessoa(pg), pessoa(pg)
    for uid in (livre, guardado):
        antigo(pg, uid)
        assert repo.registrar(Acesso(uid, "login", "198.51.100.11"), 0) == "registrado"
    analista = pessoa(pg)
    with pg.local.admin() as con:
        con.execute(
            "insert into public.equipe (usuario_id, papel, ativo) values (%s, 'seguranca', true)",
            (analista,),
        )
        con.execute(
            "insert into public.acessos_conta_guardas (usuario_id, motivo, criada_por) "
            "values (%s, 'Processo em andamento', %s)",
            (guardado, analista),
        )
    assert repo.expurgar(1000) >= 1
    assert (contar(pg, livre), contar(pg, guardado)) == (1, 2)  # o recente e o preservado ficam
    assert repo.expurgar(1000) == 0


def test_sem_a_190000_nao_apaga_e_sem_a_061200_nao_quebra(pg):  # noqa: F811
    repo = AcessosPostgres(pg.banco)
    uid = pessoa(pg)
    antigo(pg, uid)
    renomear = "alter function public.{} rename to {}"
    funcoes = (
        ("expurgo_acessos_enfileirar()", "expurgo_escondido", "expurgo_acessos_enfileirar"),
        (
            "registrar_acesso_conta(uuid,text,text,text,text,text,text,text,integer)",
            "registrar_escondido",
            "registrar_acesso_conta",
        ),
    )
    with pg.local.admin() as con:
        for assinatura, escondida, _ in funcoes:
            con.execute(renomear.format(assinatura, escondida))
    try:
        assert repo.expurgar(1000) == 0 and contar(pg, uid) == 1
        assert repo.registrar(Acesso(uid, "login", "198.51.100.12"), 0) == "indisponivel"
    finally:
        with pg.local.admin() as con:
            for assinatura, escondida, nome in funcoes:
                args = assinatura[assinatura.index("(") :]
                con.execute(renomear.format(escondida + args, nome))
