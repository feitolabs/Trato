"""Perfil do profissional e catálogo (categorias e cidades ativas) no Postgres.

Tabelas: `perfis_profissional`, `profissional_categorias`, `profissional_regioes`, `categorias`,
`cidades` (e `usuarios` para o nome). `status` e `nivel_verificacao` só mudam pela equipe: aqui o
`salvar` grava bio, disponibilidade, portfólio, categorias e regiões. A busca devolve só
profissionais APROVADOS (e usuário ativo) e nada de dado pessoal sensível.
"""

from __future__ import annotations

from collections.abc import Callable
from typing import Any

from psycopg.types.json import Jsonb

from trato.persistencia.comum import como_uuid, exigir_uuid, para_json
from trato.persistencia.conexao import Banco
from trato.profissional.repositorio import (
    CategoriaPublica,
    CidadePublica,
    FiltroBusca,
    ItemPortfolio,
    JanelaSemanal,
    PerfilProfissional,
    Regiao,
    ResultadoBusca,
)


class CatalogoPostgres:
    def __init__(self, banco: Banco) -> None:
        self._banco = banco

    def categorias_publicas(self) -> list[CategoriaPublica]:
        with self._banco.transacao() as con:
            linhas = con.execute(
                "select id, nome, slug, icone, pai_id from public.categorias "
                "where ativa order by ordem, nome, id"
            ).fetchall()
        return [
            CategoriaPublica(
                str(l["id"]),
                l["nome"],
                l["slug"],
                l["icone"],
                str(l["pai_id"]) if l["pai_id"] else None,
            )  # fmt: skip
            for l in linhas  # noqa: E741
        ]

    def categorias_ativas(self) -> dict[str, str]:
        return {c.id: c.slug for c in self.categorias_publicas()}

    def cidades_publicas(self) -> list[CidadePublica]:
        with self._banco.transacao() as con:
            linhas = con.execute(
                "select id, nome, uf from public.cidades where ativa order by nome, uf, id"
            ).fetchall()
        return [CidadePublica(str(l["id"]), l["nome"], l["uf"]) for l in linhas]  # noqa: E741

    def cidades_ativas(self) -> set[str]:
        return {c.id for c in self.cidades_publicas()}


class ProfissionaisPostgres:
    def __init__(self, banco: Banco) -> None:
        self._banco = banco

    def obter(self, usuario_id: str) -> PerfilProfissional | None:
        achado = como_uuid(usuario_id)
        if achado is None:
            return None
        with self._banco.transacao() as con:
            p = con.execute(
                "select usuario_id, status, nivel_verificacao, bio, disponibilidade, portfolio, "
                "criado_em from public.perfis_profissional where usuario_id = %s",
                (achado,),
            ).fetchone()
            if p is None:
                return None
            categorias = con.execute(
                "select categoria_id from public.profissional_categorias "
                "where profissional_id = %s order by criado_em, categoria_id",
                (achado,),
            ).fetchall()
            regioes = con.execute(
                "select cidade_id, bairro from public.profissional_regioes "
                "where profissional_id = %s order by criado_em, id",
                (achado,),
            ).fetchall()
        return PerfilProfissional(
            usuario_id=str(p["usuario_id"]),
            status=p["status"],
            bio=p["bio"],
            categorias=tuple(str(c["categoria_id"]) for c in categorias),
            regioes=tuple(Regiao(str(r["cidade_id"]), r["bairro"]) for r in regioes),
            disponibilidade=tuple(
                JanelaSemanal(int(j["dia_semana"]), j["inicio"], j["fim"])
                for j in p["disponibilidade"] or []
            ),
            portfolio=tuple(
                ItemPortfolio(i.get("titulo", ""), i.get("descricao")) for i in p["portfolio"] or []
            ),
            criado_em=p["criado_em"],
            nivel_verificacao=p["nivel_verificacao"],
        )

    def salvar(self, perfil: PerfilProfissional) -> None:
        usuario = exigir_uuid(perfil.usuario_id, "profissional")
        disponibilidade = [
            {"dia_semana": j.dia_semana, "inicio": j.inicio, "fim": j.fim}
            for j in perfil.disponibilidade
        ]
        portfolio = [{"titulo": i.titulo, "descricao": i.descricao} for i in perfil.portfolio]
        with self._banco.transacao() as con:
            # Resolve categorias: se não for UUID, busca por slug/nome
            categorias: list[str] = []
            for c in dict.fromkeys(perfil.categorias):
                c_uuid = como_uuid(c)
                if c_uuid:
                    categorias.append(c_uuid)
                else:
                    c_slug = str(c or "").strip().lower()
                    row = con.execute(
                        "select id from public.categorias where lower(slug) = %s "
                        "or lower(replace(nome, ' ', '-')) = %s or lower(nome) = %s limit 1",
                        (c_slug, c_slug, c_slug),
                    ).fetchone()
                    if row:
                        categorias.append(str(row["id"]))
            if not categorias:
                padrao_cat = con.execute(
                    "select id from public.categorias where ativa order by ordem, nome limit 1"
                ).fetchone()
                if padrao_cat:
                    categorias.append(str(padrao_cat["id"]))

            # Status e nível só a equipe muda: o conflito não os toca.
            con.execute(
                "insert into public.perfis_profissional (usuario_id, status, nivel_verificacao, "
                "bio, disponibilidade, portfolio) values (%s, %s, %s, %s, %s, %s) "
                "on conflict (usuario_id) do update set bio = excluded.bio, "
                "disponibilidade = excluded.disponibilidade, portfolio = excluded.portfolio",
                (usuario, perfil.status, perfil.nivel_verificacao, perfil.bio,
                 Jsonb(para_json(disponibilidade)), Jsonb(para_json(portfolio))),
            )  # fmt: skip
            con.execute(
                "delete from public.profissional_categorias "
                "where profissional_id = %s and not (categoria_id = any(%s::uuid[]))",
                (usuario, categorias),
            )
            for categoria in categorias:
                con.execute(
                    "insert into public.profissional_categorias (profissional_id, categoria_id) "
                    "values (%s, %s) on conflict do nothing",
                    (usuario, categoria),
                )
            con.execute(
                "delete from public.profissional_regioes where profissional_id = %s", (usuario,)
            )
            for r in dict.fromkeys(perfil.regioes):
                r_cidade_uuid = como_uuid(r.cidade_id)
                if not r_cidade_uuid:
                    r_slug = str(r.cidade_id or "").strip().lower()
                    cid_row = con.execute(
                        "select id from public.cidades where lower(replace(nome, ' ', '-')) = %s "
                        "or lower(nome) = %s limit 1",
                        (r_slug, r_slug),
                    ).fetchone()
                    if cid_row:
                        r_cidade_uuid = str(cid_row["id"])
                    else:
                        cid_padrao = con.execute(
                            "select id from public.cidades where ativa order by nome limit 1"
                        ).fetchone()
                        r_cidade_uuid = (
                            str(cid_padrao["id"])
                            if cid_padrao
                            else exigir_uuid(r.cidade_id, "cidade")
                        )
                con.execute(
                    "insert into public.profissional_regioes (profissional_id, cidade_id, bairro) "
                    "values (%s, %s, %s) on conflict do nothing",
                    (usuario, r_cidade_uuid, r.bairro),
                )

    def buscar(
        self, filtro: FiltroBusca, detalhe: Callable[[str], Any] | None = None
    ) -> tuple[list[ResultadoBusca], int]:
        onde = ["p.status = 'aprovado'", "u.status = 'ativo'"]
        params: list[Any] = []
        if filtro.categoria_ids is not None:
            ids = [i for i in map(como_uuid, filtro.categoria_ids) if i]
            onde.append(
                "exists (select 1 from public.profissional_categorias pc "
                "where pc.profissional_id = p.usuario_id and pc.suspensa_em is null "
                "and pc.categoria_id = any(%s::uuid[]))"
            )
            params.append(ids)
        if filtro.cidade_id is not None or filtro.bairro is not None:
            cidade = como_uuid(filtro.cidade_id) if filtro.cidade_id else None
            if filtro.cidade_id is not None and cidade is None:
                return [], 0
            bairro = (filtro.bairro or "").strip().casefold() or None
            onde.append(
                "exists (select 1 from public.profissional_regioes r "
                "where r.profissional_id = p.usuario_id "
                "and (%s::uuid is null or r.cidade_id = %s::uuid) "
                "and (%s::text is null or r.bairro is null or lower(btrim(r.bairro)) = %s::text))"
            )
            params += [cidade, cidade, bairro, bairro]
        base = (
            "from public.perfis_profissional p join public.usuarios u on u.id = p.usuario_id "
            "where " + " and ".join(onde)
        )
        with self._banco.transacao() as con:
            total = con.execute(f"select count(*) as n {base}", params).fetchone()["n"]  # noqa: S608
            linhas = con.execute(
                "select p.usuario_id, u.nome, p.bio, p.nivel_verificacao, p.nota_publica, "  # noqa: S608
                "p.servicos_concluidos, coalesce((select array_agg(pc.categoria_id::text "
                "order by pc.categoria_id) from public.profissional_categorias pc "
                "where pc.profissional_id = p.usuario_id and pc.suspensa_em is null), '{}') "
                f"as categorias {base} "
                "order by p.nota_publica desc nulls last, p.servicos_concluidos desc, "
                "p.usuario_id limit %s offset %s",
                [*params, filtro.limite, filtro.deslocamento],
            ).fetchall()
        return [
            ResultadoBusca(
                str(l["usuario_id"]),
                l["nome"],
                l["bio"],
                l["nivel_verificacao"],
                float(l["nota_publica"]) if l["nota_publica"] is not None else None,
                int(l["servicos_concluidos"]),
                tuple(l["categorias"]),
            )  # fmt: skip
            for l in linhas  # noqa: E741
        ], int(total)
