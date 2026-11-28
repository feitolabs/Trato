"""Implementação dos repositórios de LGPD no PostgreSQL."""

from __future__ import annotations

import uuid
from collections.abc import Iterator, Sequence
from contextlib import contextmanager
from datetime import datetime
from typing import Any

from psycopg.types.json import Jsonb

from trato.lgpd.repositorios import (
    Consentimento,
    FonteDadosPessoais,
    PedidoExclusao,
    RepositorioConsentimentos,
    RepositorioExclusoes,
    RepositoriosLgpd,
)
from trato.persistencia.comum import como_uuid, exigir_uuid
from trato.persistencia.conexao import Banco

_A_REMOVER = "dado_pessoal.arquivos_a_remover"
_REMOVIDOS = "dado_pessoal.arquivos_removidos"


class FonteLgpdPostgres(FonteDadosPessoais):
    def __init__(self, banco: Banco) -> None:
        self._banco = banco

    @contextmanager
    def exclusivo(self, usuario_id: str) -> Iterator[None]:
        """Checar e anonimizar numa transação só (Termos 4.8). Travados até o fim: os pedidos
        e contratos da pessoa (pagamento, livro e ordem de estorno passam por eles) e a conta e
        o perfil (pedido ou contrato novo aponta para eles). Mesma ordem do resto do sistema:
        pedido, contrato, conta. Espera demais ou impasse vira erro e a exclusão fica para a
        próxima rodada."""
        uid = como_uuid(usuario_id)
        with self._banco.transacao() as con:
            if uid is not None:
                con.execute("set local lock_timeout = '10s'")
                for consulta in (
                    # o pedido de exclusão primeiro: cancelar espera, e o que já foi cancelado
                    # é visto pela releitura
                    "select 1 from public.lgpd_pedidos_exclusao where usuario_id = %(u)s "
                    "and status in ('aguardando_confirmacao', 'agendada') for update",
                    "select 1 from public.pedidos where cliente_id = %(u)s or id in "
                    "(select pedido_id from public.contratos where profissional_id = %(u)s) "
                    "order by id for update",
                    "select 1 from public.contratos where cliente_id = %(u)s "
                    "or profissional_id = %(u)s order by id for update",
                    "select 1 from public.usuarios where id = %(u)s for update",
                    "select 1 from public.perfis_profissional where usuario_id = %(u)s for update",
                ):
                    con.execute(consulta, {"u": uid})
            yield

    def pendencias(self, usuario_id: str) -> list[str]:
        uid = como_uuid(usuario_id)
        if uid is None:
            return []
        pendencias: list[str] = []
        with self._banco.transacao() as con:
            # Pedidos em andamento onde a pessoa é cliente
            em_andamento_cliente = con.execute(
                """
                select count(*) as total
                  from public.pedidos
                 where cliente_id = %s
                   and status not in ('cancelado', 'concluido')
                """,
                (uid,),
            ).fetchone()
            if em_andamento_cliente and em_andamento_cliente["total"] > 0:
                pendencias.append(
                    f"{em_andamento_cliente['total']} pedido(s) em andamento como cliente"
                )

            # Pedidos em andamento onde a pessoa é o profissional contratado
            em_andamento_prof = con.execute(
                """
                select count(*) as total
                  from public.contratos c
                  join public.pedidos p on p.id = c.pedido_id
                 where c.profissional_id = %s
                   -- contrato caído por pagamento expirado não obriga o profissional
                   and c.status <> 'cancelado'
                   and p.status not in ('cancelado', 'concluido')
                """,
                (uid,),
            ).fetchone()
            if em_andamento_prof and em_andamento_prof["total"] > 0:
                pendencias.append(
                    f"{em_andamento_prof['total']} contrato(s) em execução como profissional"
                )

            # Disputas abertas
            disputas = con.execute(
                """
                select count(*) as total
                  from public.disputas d
                  join public.pedidos p on p.id = d.pedido_id
                 where (p.cliente_id = %s or exists (
                     select 1 from public.contratos c
                      where c.pedido_id = p.id and c.profissional_id = %s
                        and c.status <> 'cancelado'
                 ))
                   and d.status in ('aberta', 'em_analise', 'aguardando_partes')
                """,
                (uid, uid),
            ).fetchone()
            if disputas and disputas["total"] > 0:
                pendencias.append("Disputa aberta em mediação")

            pendencias += self._valores_pendentes(con, uid)

        return pendencias

    @staticmethod
    def _valores_pendentes(con: Any, uid: Any) -> list[str]:
        """Termos 4.8 e 20.7: a conta só sai depois que o valor retido ou a liberar for
        liberado ou reembolsado, mesmo em pedido já concluído ou cancelado."""
        achados: list[str] = []
        parados = con.execute(
            """
            select count(distinct x.contrato_id) as total from (
                select l.contrato_id
                  from public.partidas p
                  join public.contas_ledger a on a.id = p.conta_id
                  join public.lancamentos l on l.id = p.lancamento_id
                  join public.contratos c on c.id = l.contrato_id
                 where (c.cliente_id = %s or c.profissional_id = %s)
                   and a.codigo in ('custodia', 'a_liberar')
                 group by l.contrato_id, a.codigo
                having sum(case p.sentido when 'credito' then p.valor_centavos
                                          else -p.valor_centavos end) > 0
            ) x
            """,
            (uid, uid),
        ).fetchone()["total"]
        if parados:
            achados.append(f"Valor retido ou a liberar em {parados} pedido(s)")
        tem_ordens = con.execute(
            "select to_regclass('public.ordens_estorno') is not null as tem"
        ).fetchone()["tem"]
        if tem_ordens:
            devolver = con.execute(
                "select count(*) as total from public.ordens_estorno o "
                "join public.contratos c on c.id = o.contrato_id "
                "where c.cliente_id = %s and o.estado = 'pendente'",
                (uid,),
            ).fetchone()["total"]
            if devolver:
                achados.append(f"{devolver} reembolso(s) ainda não enviado(s)")
        return achados

    def exportar(self, usuario_id: str) -> dict[str, Any]:
        uid = como_uuid(usuario_id)
        if uid is None:
            return {}
        with self._banco.transacao() as con:
            usuario = con.execute(
                "select id, nome, status, aceite_termos_versao, aceite_termos_em, criado_em "
                "from public.usuarios where id = %s",
                (uid,),
            ).fetchone()
            privado = con.execute(
                "select cpf, telefone, data_nascimento, criado_em from public.usuarios_privados "
                "where usuario_id = %s",
                (uid,),
            ).fetchone()
            perfil_prof = con.execute(
                "select bio, disponibilidade, portfolio, nivel_verificacao, status "
                "from public.perfis_profissional where usuario_id = %s",
                (uid,),
            ).fetchone()

        return {
            "usuario": dict(usuario) if usuario else None,
            "privado": dict(privado) if privado else None,
            "perfil_profissional": dict(perfil_prof) if perfil_prof else None,
        }

    @staticmethod
    def _auditar(con: Any, uid: Any, acao: str, depois: dict[str, Any], motivo: str) -> None:
        con.execute(
            "select public.registrar_auditoria(null, 'sistema', %s, 'usuarios', %s, null, %s, %s)",
            (acao, uid, Jsonb(depois), motivo),
        )

    def arquivos_a_remover(self, usuario_id: str) -> list[tuple[str, str]]:
        uid = como_uuid(usuario_id)
        if uid is None:
            return []
        with self._banco.transacao() as con:
            linhas = con.execute(
                "select a.depois from public.auditoria a where a.acao = %s and a.entidade_id = %s "
                "and not exists (select 1 from public.auditoria r where r.acao = %s "
                "and r.entidade_id = a.entidade_id and r.id > a.id) order by a.id",
                (_A_REMOVER, uid, _REMOVIDOS),
            ).fetchall()
        return [
            (a["bucket"], a["caminho"])
            for x in linhas
            for a in (x["depois"] or {}).get("arquivos", [])
        ]

    def pastas_temporarias(self, usuario_id: str) -> list[tuple[str, str]]:
        uid = como_uuid(usuario_id)
        if uid is None:
            return []
        with self._banco.transacao() as con:
            if not con.execute(
                "select to_regprocedure('public.lgpd_arquivos_contestacao_medida(uuid)') "
                "is not null as tem"
            ).fetchone()["tem"]:
                return [("verificacao", f"contestacao-medida/{uid}/")]
            linhas = con.execute(
                "select bucket, caminho from public.lgpd_arquivos_contestacao_medida(%s) "
                "where origem = 'temporario'",
                (uid,),
            ).fetchall()
        return [(x["bucket"], x["caminho"]) for x in linhas]

    def limpeza_concluida(self, usuario_id: str, removidos: int) -> None:
        uid = como_uuid(usuario_id)
        if uid is not None:
            with self._banco.transacao() as con:
                self._auditar(
                    con, uid, _REMOVIDOS, {"removidos": removidos}, "Arquivos da conta apagados"
                )

    def limpezas_pendentes(self) -> list[str]:
        with self._banco.transacao() as con:
            linhas = con.execute(
                "select distinct a.entidade_id from public.auditoria a where a.acao = %s "
                "and not exists (select 1 from public.auditoria r where r.acao = %s "
                "and r.entidade_id = a.entidade_id and r.id > a.id)",
                (_A_REMOVER, _REMOVIDOS),
            ).fetchall()
        return [str(x["entidade_id"]) for x in linhas]

    def anonimizar(self, usuario_id: str) -> dict[str, list[str]]:
        uid = como_uuid(usuario_id)
        if uid is not None:
            # Os caminhos ficam na auditoria na mesma transação: sem eles não há como repetir.
            with self._banco.transacao() as con:
                linha = con.execute(
                    "select privado.anonimizar_usuario(%s) as caminhos", (uid,)
                ).fetchone()
                arquivos = [
                    {"bucket": "verificacao", "caminho": c.removeprefix("verificacao/")}
                    for c in linha["caminhos"] or []
                    if c
                ]
                self._auditar(
                    con,
                    uid,
                    _A_REMOVER,
                    {"arquivos": arquivos},
                    "Arquivos a apagar na exclusão da conta",
                )

        return {
            "anonimizado": [
                "perfil_nome",
                "dados_contato",
                "documentos_verificacao",
                "preferencias_notificacao",
            ],
            "mantido": [
                "historico_pedidos",
                "contratos_executados",
                "lancamentos_financeiros",
                "auditoria_seguranca",
            ],
        }


class ConsentimentosPostgres(RepositorioConsentimentos):
    def __init__(self, banco: Banco) -> None:
        self._banco = banco

    def registrar(self, c: Consentimento) -> None:
        uid = exigir_uuid(c.usuario_id, "usuario")
        with self._banco.transacao() as con:
            con.execute(
                """
                insert into public.lgpd_consentimentos (
                    usuario_id, finalidade, aceito, versao_texto, registrado_em, ip
                ) values (%s, %s, %s, %s, %s, %s)
                """,
                (uid, c.finalidade, c.aceito, c.versao_texto, c.registrado_em, c.ip),
            )

    def historico(self, usuario_id: str) -> Sequence[Consentimento]:
        uid = como_uuid(usuario_id)
        if uid is None:
            return ()
        with self._banco.transacao() as con:
            linhas = con.execute(
                """
                select usuario_id, finalidade, aceito, versao_texto, registrado_em, ip
                  from public.lgpd_consentimentos
                 where usuario_id = %s
                 order by registrado_em asc
                """,
                (uid,),
            ).fetchall()
        return tuple(
            Consentimento(
                usuario_id=str(r["usuario_id"]),
                finalidade=r["finalidade"],
                aceito=r["aceito"],
                versao_texto=r["versao_texto"],
                registrado_em=r["registrado_em"],
                ip=r["ip"],
            )
            for r in linhas
        )

    def ultimos(self, usuario_ids: Sequence[str], finalidade: str) -> dict[str, bool]:
        pedidos = {como_uuid(i): i for i in usuario_ids if como_uuid(i) is not None}
        if not pedidos:
            return {}
        with self._banco.transacao() as con:
            linhas = con.execute(
                """
                select distinct on (usuario_id) usuario_id, aceito
                  from public.lgpd_consentimentos
                 where usuario_id = any(%s) and finalidade = %s
                 order by usuario_id, registrado_em desc, id desc
                """,
                (list(pedidos), finalidade),
            ).fetchall()
        return {pedidos[como_uuid(str(r["usuario_id"]))]: r["aceito"] for r in linhas}


class ExclusoesPostgres(RepositorioExclusoes):
    def __init__(self, banco: Banco) -> None:
        self._banco = banco

    def salvar(self, p: PedidoExclusao) -> bool:
        """Grava só enquanto o pedido está em aberto: concluído, cancelado ou expirado não muda.
        `False`: nada foi gravado."""
        pid = como_uuid(p.id) or uuid.uuid4()
        uid = exigir_uuid(p.usuario_id, "usuario")
        resumo_json = Jsonb(p.resumo) if p.resumo is not None else None
        with self._banco.transacao() as con:
            linha = con.execute(
                """
                insert into public.lgpd_pedidos_exclusao (
                    id, usuario_id, status, criado_em, token_hash,
                    token_expira_em, executar_apos, concluido_em, resumo
                ) values (%s, %s, %s, %s, %s, %s, %s, %s, %s)
                on conflict (id) do update set
                    status = excluded.status,
                    token_hash = excluded.token_hash,
                    token_expira_em = excluded.token_expira_em,
                    executar_apos = excluded.executar_apos,
                    concluido_em = excluded.concluido_em,
                    resumo = excluded.resumo
                 where lgpd_pedidos_exclusao.status in ('aguardando_confirmacao', 'agendada')
                returning id
                """,
                (
                    pid,
                    uid,
                    p.status,
                    p.criado_em,
                    p.token_hash,
                    p.token_expira_em,
                    p.executar_apos,
                    p.concluido_em,
                    resumo_json,
                ),
            ).fetchone()
        return linha is not None

    def ativo_do_usuario(self, usuario_id: str) -> PedidoExclusao | None:
        uid = como_uuid(usuario_id)
        if uid is None:
            return None
        with self._banco.transacao() as con:
            linha = con.execute(
                """
                select id, usuario_id, status, criado_em, token_hash,
                       token_expira_em, executar_apos, concluido_em, resumo
                  from public.lgpd_pedidos_exclusao
                 where usuario_id = %s
                   and status in ('aguardando_confirmacao', 'agendada')
                 order by criado_em desc
                 limit 1
                """,
                (uid,),
            ).fetchone()
            if not linha:
                return None
            return PedidoExclusao(
                id=str(linha["id"]),
                usuario_id=str(linha["usuario_id"]),
                status=linha["status"],
                criado_em=linha["criado_em"],
                token_hash=linha["token_hash"],
                token_expira_em=linha["token_expira_em"],
                executar_apos=linha["executar_apos"],
                concluido_em=linha["concluido_em"],
                resumo=linha["resumo"],
            )

    def agendadas_ate(self, agora: datetime) -> Sequence[PedidoExclusao]:
        with self._banco.transacao() as con:
            linhas = con.execute(
                """
                select id, usuario_id, status, criado_em, token_hash,
                       token_expira_em, executar_apos, concluido_em, resumo
                  from public.lgpd_pedidos_exclusao
                 where status = 'agendada'
                   and executar_apos <= %s
                 order by executar_apos asc
                """,
                (agora,),
            ).fetchall()
        return tuple(
            PedidoExclusao(
                id=str(r["id"]),
                usuario_id=str(r["usuario_id"]),
                status=r["status"],
                criado_em=r["criado_em"],
                token_hash=r["token_hash"],
                token_expira_em=r["token_expira_em"],
                executar_apos=r["executar_apos"],
                concluido_em=r["concluido_em"],
                resumo=r["resumo"],
            )
            for r in linhas
        )

    def novo_id(self) -> str:
        return str(uuid.uuid4())


def criar_repositorios_lgpd_postgres(banco: Banco) -> RepositoriosLgpd:
    return RepositoriosLgpd(
        fonte=FonteLgpdPostgres(banco),
        consentimentos=ConsentimentosPostgres(banco),
        exclusoes=ExclusoesPostgres(banco),
    )
