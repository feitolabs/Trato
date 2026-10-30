"""Usuários e perfis. O login é do Supabase Auth; a linha em `public.usuarios` nasce aqui, no
primeiro login válido, de forma idempotente (M11). O papel NUNCA vem do token."""

from __future__ import annotations

from dataclasses import dataclass

from trato.api.auth import PapelUsuario
from trato.api.repositorios_app import PerfilDetalhe
from trato.persistencia.comum import como_uuid
from trato.persistencia.conexao import Banco
from trato.persistencia.erros import DadosInvalidos

STATUS_QUE_ENTRAM = ("ativo", "restrito")
NOME_PADRAO = "Novo usuário"
NOME_MAX = 120


def nome_de_exibicao(bruto: object) -> str:
    """Nome para mostrar, vindo do token do provedor de login (só exibição, nunca autorização)."""
    if not isinstance(bruto, str):
        return NOME_PADRAO
    limpo = " ".join(bruto.split())[:NOME_MAX]
    return limpo or NOME_PADRAO


@dataclass(frozen=True)
class PerfilUsuario:
    id: str
    nome: str
    status: str
    papel: PapelUsuario


class UsuariosPostgres:
    def __init__(self, banco: Banco) -> None:
        self._banco = banco

    def garantir(self, usuario_id: str, nome: object = None) -> PerfilUsuario | None:
        """Cria `public.usuarios` (cliente, ativo) se ainda não existe. Idempotente: repetir não
        muda nada e duas chamadas ao mesmo tempo dão no mesmo. Devolve `None` se o id não existe
        em `auth.users` (token de quem não é do projeto)."""
        achado = como_uuid(usuario_id)
        if achado is None:
            return None
        try:
            with self._banco.transacao() as con:
                con.execute(
                    "insert into public.usuarios (id, nome) values (%s, %s) "
                    "on conflict (id) do nothing",
                    (achado, nome_de_exibicao(nome)),
                )
        except DadosInvalidos:  # chave estrangeira: o id não está em auth.users
            return None
        return self.perfil(usuario_id)

    def registrar_dados_privados(
        self, usuario_id: str, cpf: str, telefone: str | None = None
    ) -> bool:
        """Cria `usuarios_privados` (CPF e telefone) uma única vez. Verdadeiro se criou, falso se
        a pessoa já tinha a linha (nada é sobrescrito). CPF de outra pessoa: `Duplicado`."""
        achado = como_uuid(usuario_id)
        if achado is None:
            raise DadosInvalidos("Usuário inválido.")
        with self._banco.transacao() as con:
            criada = con.execute(
                "insert into public.usuarios_privados (usuario_id, cpf, telefone) "
                "values (%s, %s, %s) on conflict (usuario_id) do nothing returning usuario_id",
                (achado, cpf, telefone),
            ).fetchone()
        return criada is not None

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

    def detalhe(self, usuario_id: str) -> PerfilDetalhe | None:
        """O que o app mostra no Perfil. Sem documento, telefone ou e-mail (ficam fora daqui)."""
        base = self.perfil(usuario_id)
        if base is None:
            return None
        nivel = nota = servicos = None
        if base.papel is PapelUsuario.PROFISSIONAL:
            with self._banco.transacao() as con:
                linha = con.execute(
                    "select nivel_verificacao, nota_publica, servicos_concluidos "
                    "from public.perfis_profissional where usuario_id = %s",
                    (base.id,),
                ).fetchone()
            if linha is not None:
                nivel = linha["nivel_verificacao"]
                nota = float(linha["nota_publica"]) if linha["nota_publica"] is not None else None
                servicos = int(linha["servicos_concluidos"])
        return PerfilDetalhe(base.id, base.nome, base.papel, base.status, nivel, nota, servicos)
