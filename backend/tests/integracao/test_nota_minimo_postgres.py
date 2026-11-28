"""BE-TETO75-MINIMO123 no Postgres local: avaliação fora de 'publicada' não conta (12.3) e,
abaixo do mínimo, a nota não sai, não filtra e não ordena."""

# ruff: noqa: F811 - o parâmetro com nome da fixture importada é do pytest

from __future__ import annotations

from trato.persistencia.profissionais import ProfissionaisPostgres
from trato.profissional.repositorio import FiltroBusca

from .test_b32_nota_decimal_postgres import _concluir
from .test_rotas_app_postgres import post


def test_contagem_so_de_publicadas_e_minimo(cenario):
    c = cenario
    pro = c.ids["profissional"]
    repo = ProfissionaisPostgres(c.banco)
    pid = _concluir(c)
    r = post(c, f"/v1/pedidos/{pid}/avaliacao", "cliente", {"nota_geral": 5})
    assert r.status_code in (200, 201), r.text
    total = c.contexto.usuarios.detalhe(pro).avaliacoes_total
    assert total >= 1
    with c.local.admin() as con:
        antes = con.execute(
            "select status, nota_publica from public.perfis_profissional where usuario_id = %s",
            (pro,),
        ).fetchone()
        con.execute(
            "update public.perfis_profissional set status = 'aprovado', nota_publica = 5 "
            "where usuario_id = %s",
            (pro,),
        )

    def buscar(minimo, nota_minima=None):
        filtro = FiltroBusca(nota_minimo_avaliacoes=minimo, nota_minima=nota_minima, limite=100)
        achados, _ = repo.buscar(filtro, c.contexto.usuarios.detalhe)
        return {x.usuario_id: x for x in achados}.get(pro)

    try:
        visto = buscar(1)
        assert (visto.nota_publica, visto.avaliacoes_total) == (5.0, total)
        assert buscar(total, 4.0).nota_publica == 5.0
        oculto = buscar(total + 1)
        assert (oculto.nota_publica, oculto.avaliacoes_total) == (None, total)
        assert buscar(total + 1, 4.0) is None
        with c.local.admin() as con:
            con.execute("set session_replication_role = replica")
            con.execute(
                "update public.avaliacoes set status = 'descartada' where contrato_id in "
                "(select id from public.contratos where pedido_id = %s) and avaliado_id = %s",
                (pid, pro),
            )
        assert c.contexto.usuarios.detalhe(pro).avaliacoes_total == total - 1
        with c.local.admin() as con:  # a nota gravada é do banco; aqui só a contagem
            con.execute("set session_replication_role = replica")
            con.execute(
                "update public.perfis_profissional set nota_publica = 5 where usuario_id = %s",
                (pro,),
            )
        assert buscar(1).avaliacoes_total == total - 1
        # a consulta do aviso de pedido novo roda com e sem o mínimo
        for minimo in (1, 3):
            repo.listar_elegiveis_para_pedido(
                c.categoria_id, c.cidade_id, nota_minimo_avaliacoes=minimo
            )
        assert c.contexto.conta.favoritar(c.ids["cliente"], pro)
        favoritos = c.contexto.conta.favoritos(c.ids["cliente"])
        (favorito,) = [
            f for f in favoritos if f.profissional_id.replace("-", "") == pro.replace("-", "")
        ]
        assert favorito.avaliacoes_total == total - 1
        c.contexto.conta.desfavoritar(c.ids["cliente"], pro)
    finally:
        with c.local.admin() as con:
            con.execute("set session_replication_role = replica")
            con.execute(
                "update public.perfis_profissional set status = %s, nota_publica = %s "
                "where usuario_id = %s",
                (antes[0], antes[1], pro),
            )
