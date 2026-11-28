"""Registros de acesso à conta (Termos 14.3 e 16.1; migrations 061200 e 190000).

Gravar e expurgar são só pelas funções do banco. Sem elas, nada acontece e nada quebra.
"""

from __future__ import annotations

from dataclasses import dataclass

from trato.persistencia.comum import como_uuid
from trato.persistencia.conexao import Banco


@dataclass(frozen=True)
class Acesso:
    usuario_id: str
    evento: str  # login | sessao_renovada | acesso | logout
    ip: str
    aparelho_tipo: str | None = None
    sistema_operacional: str | None = None
    dispositivo_id: str | None = None
    user_agent: str | None = None
    app_versao: str | None = None


class AcessosPostgres:
    def __init__(self, banco: Banco) -> None:
        self._banco = banco

    def registrar(self, acesso: Acesso, janela_minutos: int) -> str:
        """registrado | repetido | ip_invalido | usuario_nao_encontrado | indisponivel"""
        usuario = como_uuid(acesso.usuario_id)
        if usuario is None:
            return "usuario_nao_encontrado"
        with self._banco.transacao() as con:
            if not con.execute(
                "select to_regprocedure('public.registrar_acesso_conta("
                "uuid,text,text,text,text,text,text,text,integer)') is not null as tem"
            ).fetchone()["tem"]:
                return "indisponivel"
            linha = con.execute(
                "select public.registrar_acesso_conta(%s, %s, %s, %s, %s, %s, %s, %s, %s) as r",
                (
                    usuario, acesso.evento, acesso.ip, acesso.aparelho_tipo,
                    acesso.sistema_operacional, acesso.dispositivo_id, acesso.user_agent,
                    acesso.app_versao, janela_minutos,
                ),
            ).fetchone()  # fmt: skip
        return str(linha["r"])

    def expurgar(self, limite: int) -> int:
        """Uma transação curta e própria, em READ COMMITTED (a trava da 190000 só vale nele).
        Sem a 190000 (expurgo sem corrida e que protege incidente) não apaga nada."""
        with self._banco.transacao() as con:
            con.execute("set transaction isolation level read committed")
            if not con.execute(
                "select to_regprocedure('public.expurgo_acessos_enfileirar()') is not null as tem"
            ).fetchone()["tem"]:
                return 0
            linha = con.execute(
                "select public.expurgar_acessos_conta(%s) as n", (limite,)
            ).fetchone()
        return int(linha["n"])
