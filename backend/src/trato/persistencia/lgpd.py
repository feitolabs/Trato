"""Implementação dos repositórios de LGPD no PostgreSQL."""

from __future__ import annotations

import uuid
from collections.abc import Sequence
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


class FonteLgpdPostgres(FonteDadosPessoais):
    def __init__(self, banco: Banco) -> None:
        self._banco = banco

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
                 ))
                   and d.status in ('aberta', 'em_analise', 'aguardando_partes')
                """,
                (uid, uid),
            ).fetchone()
            if disputas and disputas["total"] > 0:
                pendencias.append("Disputa aberta em mediação")

        return pendencias

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

    def anonimizar(self, usuario_id: str) -> dict[str, list[str]]:
        uid = como_uuid(usuario_id)
        if uid is not None:
            with self._banco.transacao() as con:
                con.execute("select privado.anonimizar_usuario(%s)", (uid,))

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


class ExclusoesPostgres(RepositorioExclusoes):
    def __init__(self, banco: Banco) -> None:
        self._banco = banco

    def salvar(self, p: PedidoExclusao) -> None:
        pid = como_uuid(p.id) or uuid.uuid4()
        uid = exigir_uuid(p.usuario_id, "usuario")
        resumo_json = Jsonb(p.resumo) if p.resumo is not None else None
        with self._banco.transacao() as con:
            con.execute(
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
            )

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
