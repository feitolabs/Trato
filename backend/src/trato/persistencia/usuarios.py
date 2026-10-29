"""Usuários e perfis (somente leitura). O cadastro é feito pelo Supabase Auth + fluxo próprio."""

from __future__ import annotations

from dataclasses import dataclass

from trato.api.auth import PapelUsuario
from trato.persistencia.comum import como_uuid
from trato.persistencia.conexao import Banco

STATUS_QUE_ENTRAM = ("ativo", "restrito")


@dataclass(frozen=True)
class PerfilUsuario:
    id: str
    nome: str
    status: str
    papel: PapelUsuario


class UsuariosPostgres:
    def __init__(self, banco: Banco) -> None:
        self._banco = banco

    def perfil(self, usuario_id: str) -> PerfilUsuario | None:
        """Quem é e o que pode ser: equipe ativa > profissional aprovado > cliente.

        Só lê `usuarios`, `equipe` e `perfis_profissional`; dados pessoais
        (`usuarios_privados`) nunca passam por aqui.
        """
        achado = como_uuid(usuario_id)
        if achado is None:
            return None
        with self._banco.transacao() as con:
            linha = con.execute(
                "select u.id, u.nome, u.status, "
                "exists (select 1 from public.equipe e where e.usuario_id = u.id "
                "        and e.ativo and e.revogado_em is null) as eh_equipe, "
                "exists (select 1 from public.perfis_profissional p where p.usuario_id = u.id "
                "        and p.status = 'aprovado') as eh_profissional "
                "from public.usuarios u where u.id = %s",
                (achado,),
            ).fetchone()
        if linha is None:
            return None
        if linha["eh_equipe"]:
            papel = PapelUsuario.EQUIPE
        elif linha["eh_profissional"]:
            papel = PapelUsuario.PROFISSIONAL
        else:
            papel = PapelUsuario.CLIENTE
        return PerfilUsuario(str(linha["id"]), linha["nome"], linha["status"], papel)
