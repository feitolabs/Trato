"""Perfil do profissional e catálogo (categorias e cidades ativas) no Postgres.

Tabelas: `perfis_profissional`, `profissional_categorias`, `profissional_regioes`, `categorias`,
`cidades` (e `usuarios` para o nome). `status` e `nivel_verificacao` só mudam pela equipe: aqui o
`salvar` grava bio, disponibilidade, portfólio, categorias e regiões. A busca devolve só
profissionais APROVADOS (e usuário ativo) e nada de dado pessoal sensível.
"""

from __future__ import annotations

from collections.abc import Callable
from datetime import datetime
from typing import Any

from psycopg.types.json import Jsonb

from trato.persistencia.comum import como_uuid, exigir_uuid, para_json
from trato.persistencia.conexao import Banco
from trato.profissional.repositorio import (
    CategoriaPublica,
    CidadePublica,
    ContaRecebimento,
    FiltroBusca,
    ItemPortfolio,
    JanelaSemanal,
    PerfilProfissional,
    Regiao,
    ResultadoBusca,
    dia_semana_hoje,
    normalizar_busca,
)

_ACENTOS_DE = "áàâãäéèêëíìîïóòôõöúùûüç"
_ACENTOS_PARA = "aaaaaeeeeiiiiooooouuuuc"


def _sem_acento_sql(expr: str) -> str:
    return (
        f"regexp_replace(translate(lower({expr}), '{_ACENTOS_DE}', '{_ACENTOS_PARA}'), "
        "'[^0-9a-z]+', ' ', 'g')"
    )


_NOME_PUBLICO_SQL = (
    "case "
    "when array_length(regexp_split_to_array(btrim(coalesce(u.nome, '')), '\\s+'), 1) > 1 then "
    "(regexp_split_to_array(btrim(u.nome), '\\s+'))[1] || ' ' || "
    "left((regexp_split_to_array(btrim(u.nome), '\\s+'))"
    "[array_length(regexp_split_to_array(btrim(u.nome), '\\s+'), 1)], 1) || '.' "
    "else btrim(coalesce(u.nome, '')) "
    "end"
)


class CatalogoPostgres:
    def __init__(self, banco: Banco) -> None:
        self._banco = banco

    def categorias_publicas(self) -> list[CategoriaPublica]:
        sql = (
            "select id, nome, slug, icone, pai_id, aceita_remoto from public.categorias "  # noqa: S608
            "where ativa order by " + _sem_acento_sql("nome") + ", lower(nome), id"
        )
        with self._banco.transacao() as con:
            linhas = con.execute(sql).fetchall()
        return [
            CategoriaPublica(
                str(l["id"]),
                l["nome"],
                l["slug"],
                l["icone"],
                str(l["pai_id"]) if l["pai_id"] else None,
                bool(l["aceita_remoto"]),
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


def _conta_do_json(bruto: Any) -> ContaRecebimento | None:
    if not isinstance(bruto, dict) or not bruto.get("tipo_pix") or not bruto.get("chave_pix"):
        return None
    atualizada_raw = bruto.get("atualizada_em")
    atualizada = (
        datetime.fromisoformat(atualizada_raw.replace("Z", "+00:00"))
        if isinstance(atualizada_raw, str) and atualizada_raw
        else None
    )
    return ContaRecebimento(
        tipo_pix=str(bruto["tipo_pix"]),
        chave_pix=str(bruto["chave_pix"]),
        banco_codigo=bruto.get("banco_codigo"),
        banco_nome=bruto.get("banco_nome"),
        agencia=bruto.get("agencia"),
        conta=bruto.get("conta"),
        tipo_conta=bruto.get("tipo_conta"),
        atualizada_em=atualizada,
    )


def _conta_para_json(conta: ContaRecebimento | None) -> Jsonb | None:
    if conta is None:
        return None
    return Jsonb(
        para_json(
            {
                "tipo_pix": conta.tipo_pix,
                "chave_pix": conta.chave_pix,
                "banco_codigo": conta.banco_codigo,
                "banco_nome": conta.banco_nome,
                "agencia": conta.agencia,
                "conta": conta.conta,
                "tipo_conta": conta.tipo_conta,
                "atualizada_em": conta.atualizada_em,
            }
        )
    )


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
                "criado_em, atende_presencial, atende_remoto, disponivel_agora, conta_recebimento "
                "from public.perfis_profissional where usuario_id = %s",
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
            atende_presencial=bool(p["atende_presencial"]),
            atende_remoto=bool(p["atende_remoto"]),
            disponivel_agora=bool(p["disponivel_agora"]),
            conta_recebimento=_conta_do_json(p["conta_recebimento"]),
        )

    def listar_disponiveis_agora(self) -> list[PerfilProfissional]:
        with self._banco.transacao() as con:
            linhas = con.execute(
                "select usuario_id from public.perfis_profissional "
                "where status = 'aprovado' and disponivel_agora = true"
            ).fetchall()
        saida: list[PerfilProfissional] = []
        for l in linhas:  # noqa: E741
            perfil = self.obter(str(l["usuario_id"]))
            if perfil is not None:
                saida.append(perfil)
        return saida

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
                "bio, disponibilidade, portfolio, atende_presencial, atende_remoto, "
                "disponivel_agora, conta_recebimento) "
                "values (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s) "
                "on conflict (usuario_id) do update set bio = excluded.bio, "
                "disponibilidade = excluded.disponibilidade, portfolio = excluded.portfolio, "
                "atende_presencial = excluded.atende_presencial, "
                "atende_remoto = excluded.atende_remoto, "
                "disponivel_agora = excluded.disponivel_agora, "
                "conta_recebimento = excluded.conta_recebimento",
                (usuario, perfil.status, perfil.nivel_verificacao, perfil.bio,
                 Jsonb(para_json(disponibilidade)), Jsonb(para_json(portfolio)),
                 perfil.atende_presencial, perfil.atende_remoto,
                 perfil.disponivel_agora, _conta_para_json(perfil.conta_recebimento)),
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
        if filtro.excluir_usuario_id:
            excluir_uuid = como_uuid(filtro.excluir_usuario_id)
            if excluir_uuid is not None:
                onde.append("p.usuario_id <> %s")
                params.append(excluir_uuid)
        if filtro.categoria_ids is not None:
            ids = [i for i in map(como_uuid, filtro.categoria_ids) if i]
            onde.append(
                "exists (select 1 from public.profissional_categorias pc "
                "where pc.profissional_id = p.usuario_id and pc.suspensa_em is null "
                "and pc.categoria_id = any(%s::uuid[]))"
            )
            params.append(ids)
        if filtro.atende_remoto is not None:
            onde.append("p.atende_remoto = %s")
            params.append(filtro.atende_remoto)
        tokens = [t for t in normalizar_busca(filtro.texto or "").split() if t]
        sem_bio = _sem_acento_sql("coalesce(p.bio, '')")
        sem_cat_nome = _sem_acento_sql("cat.nome")
        sem_cat_slug = _sem_acento_sql("cat.slug")
        sem_item_titulo = _sem_acento_sql("coalesce(item->>'titulo', '')")
        sem_item_desc = _sem_acento_sql("coalesce(item->>'descricao', '')")
        sem_bairro_co = _sem_acento_sql("coalesce(r.bairro, '')")
        sem_nome_pub = _sem_acento_sql(_NOME_PUBLICO_SQL)
        sem_bairro = _sem_acento_sql("r.bairro")
        if filtro.cidade_id is not None or filtro.bairro is not None:
            cidade = como_uuid(filtro.cidade_id) if filtro.cidade_id else None
            if filtro.cidade_id is not None and cidade is None:
                return [], 0
            bairro_norm = normalizar_busca(filtro.bairro or "") or None
            clausula_regiao = (
                "exists (select 1 from public.profissional_regioes r "  # noqa: S608
                "where r.profissional_id = p.usuario_id "
                "and (%s::uuid is null or r.cidade_id = %s::uuid) "
                "and (%s::text is null or r.bairro is null or btrim("
                + sem_bairro
                + ") = %s::text))"
            )
            onde.append(clausula_regiao)
            params += [cidade, cidade, bairro_norm, bairro_norm]
        sem_cid_nome = _sem_acento_sql("cid.nome")
        for tok in tokens:
            like = f"%{tok}%"
            clausula_tok = (
                "("  # noqa: S608
                + sem_nome_pub
                + " like %s or "
                + sem_bio
                + " like %s "
                + "or exists (select 1 from public.profissional_categorias pc "
                "join public.categorias cat on cat.id = pc.categoria_id and cat.ativa "
                "where pc.profissional_id = p.usuario_id and pc.suspensa_em is null "
                "and (" + sem_cat_nome + " like %s or " + sem_cat_slug + " like %s)) "
                "or exists (select 1 from jsonb_array_elements("
                "coalesce(p.portfolio, '[]'::jsonb)) item "
                "where " + sem_item_titulo + " like %s or " + sem_item_desc + " like %s) "
                "or exists (select 1 from public.profissional_regioes r "
                "join public.cidades cid on cid.id = r.cidade_id and cid.ativa "
                "where r.profissional_id = p.usuario_id "
                "and (" + sem_cid_nome + " like %s or " + sem_bairro_co + " like %s))"
                ")"
            )
            onde.append(clausula_tok)
            params += [like] * 8
        if filtro.nota_minima is not None:
            onde.append("p.nota_publica is not null and p.nota_publica >= %s")
            params.append(filtro.nota_minima)
        if filtro.atende_hoje:
            onde.append(
                "exists (select 1 from jsonb_array_elements(coalesce(p.disponibilidade, "
                "'[]'::jsonb)) j where (j->>'dia_semana')::int = %s)"
            )
            params.append(dia_semana_hoje())
        base = (
            "from public.perfis_profissional p join public.usuarios u on u.id = p.usuario_id "
            "where " + " and ".join(onde)
        )
        ordem_topo: list[str] = []
        ordem_params: list[Any] = []
        if tokens:
            like_primeiro = f"%{tokens[0]}%"
            sql_ordem_tok = (
                "case when "  # noqa: S608
                + sem_nome_pub
                + " like %s then 0 "
                "when exists (select 1 from public.profissional_categorias pc "
                "join public.categorias cat on cat.id = pc.categoria_id "
                "where pc.profissional_id = p.usuario_id and pc.suspensa_em is null "
                "and " + sem_cat_nome + " like %s) then 1 else 2 end"
            )
            ordem_topo.append(sql_ordem_tok)
            ordem_params += [like_primeiro, like_primeiro]
        ordem_desempate: list[str] = []
        bairro_ord = normalizar_busca(filtro.bairro or "")
        if bairro_ord:
            sql_ordem_bairro = (
                "case when exists (select 1 from public.profissional_regioes r "  # noqa: S608
                "where r.profissional_id = p.usuario_id "
                "and r.bairro is not null and btrim(" + sem_bairro + ") = %s) "
                "then 0 else 1 end"
            )
            ordem_desempate.append(sql_ordem_bairro)
            ordem_params.append(bairro_ord)
        ordem_sql = ", ".join(
            [
                *ordem_topo,
                "p.nota_publica desc nulls last",
                "p.servicos_concluidos desc",
                *ordem_desempate,
                "case p.nivel_verificacao when 'verificado_plus' then 0 "
                "when 'verificado' then 1 else 2 end",
                "case when btrim(coalesce(p.bio, '')) <> '' then 0 else 1 end",
                "p.usuario_id",
            ]
        )
        cidade_label = "case when c.uf <> '' then c.nome || '/' || c.uf else c.nome end"
        with self._banco.transacao() as con:
            total = con.execute(f"select count(*) as n {base}", params).fetchone()["n"]  # noqa: S608
            linhas = con.execute(
                "select p.usuario_id, u.nome, p.bio, p.nivel_verificacao, p.nota_publica, "  # noqa: S608
                "p.servicos_concluidos, p.atende_remoto, "
                "coalesce((select array_agg(pc.categoria_id::text "
                "order by pc.categoria_id) from public.profissional_categorias pc "
                "where pc.profissional_id = p.usuario_id and pc.suspensa_em is null), '{}') "
                "as categorias, "
                f"coalesce((select array_agg(distinct {cidade_label} order by {cidade_label}) "
                "from public.profissional_regioes r "
                "join public.cidades c on c.id = r.cidade_id and c.ativa "
                "where r.profissional_id = p.usuario_id), '{}') as cidades, "
                "coalesce((select array_agg(distinct btrim(r.bairro) order by btrim(r.bairro)) "
                "from public.profissional_regioes r "
                "where r.profissional_id = p.usuario_id and r.bairro is not null "
                "and btrim(r.bairro) <> ''), '{}') as bairros "
                f"{base} "
                f"order by {ordem_sql} limit %s offset %s",
                [*params, *ordem_params, filtro.limite, filtro.deslocamento],
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
                cidades=tuple(l["cidades"]),
                bairros=tuple(l["bairros"]),
                atende_remoto=bool(l["atende_remoto"]),
            )  # fmt: skip
            for l in linhas  # noqa: E741
        ], int(total)
