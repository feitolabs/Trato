# ruff: noqa: S608  (o único texto interpolado no SQL é a constante _COLS_END, nunca dado de fora)
"""Conta do usuário no Postgres: dados pessoais, endereços, favoritos e contatos de confiança.

Depende da migration `20261105120000_conta_enderecos_favoritos_contatos.sql`.
"""

from __future__ import annotations

from datetime import date

from trato.api.conta import (
    LIMITE_CONTATOS,
    LIMITE_ENDERECOS,
    ContatoConfianca,
    DadosPessoais,
    Endereco,
    Favorito,
    LimiteAtingido,
)
from trato.persistencia.comum import como_uuid, exigir_uuid
from trato.persistencia.conexao import Banco
from trato.persistencia.erros import ErroPersistencia, RegraDoBanco

_COLS_END = "id, apelido, cep, logradouro, numero, complemento, bairro, cidade, uf, principal"


def _endereco(linha) -> Endereco:  # type: ignore[no-untyped-def]
    return Endereco(
        str(linha["id"]),
        linha["apelido"],
        linha["cep"],
        linha["logradouro"],
        linha["numero"],
        linha["complemento"],
        linha["bairro"],
        linha["cidade"],
        linha["uf"],
        linha["principal"],
    )


class ContaPostgres:
    def __init__(self, banco: Banco) -> None:
        self._banco = banco

    # --- dados pessoais ---------------------------------------------------------------
    def dados(self, usuario_id: str) -> DadosPessoais:
        uid = exigir_uuid(usuario_id, "usuário")
        with self._banco.transacao() as con:
            linha = con.execute(
                "select u.nome, p.cpf, p.telefone, p.data_nascimento "
                "from public.usuarios u left join public.usuarios_privados p "
                "on p.usuario_id = u.id where u.id = %s",
                (uid,),
            ).fetchone()
        email = self._email(uid)
        if linha is None:
            return DadosPessoais(None, email, None, None, None)
        cpf = linha["cpf"]
        return DadosPessoais(
            linha["nome"],
            email,
            cpf[-2:] if cpf else None,
            linha["telefone"],
            linha["data_nascimento"],
        )

    def _email(self, uid: str) -> str | None:
        try:  # sem a função no banco (migration não aplicada), a tela esconde a linha do e-mail
            with self._banco.transacao() as con:
                linha = con.execute(
                    "select email from privado.contas_auth(array[%s::uuid])", (uid,)
                ).fetchone()
            return linha["email"] if linha and linha["email"] else None
        except ErroPersistencia:
            return None

    def atualizar_dados(
        self,
        usuario_id: str,
        *,
        telefone: str | None,
        data_nascimento: date | None,
        limpar_telefone: bool,
        limpar_nascimento: bool,
    ) -> DadosPessoais:
        uid = exigir_uuid(usuario_id, "usuário")
        atual = self.dados(uid)
        novo_tel = None if limpar_telefone else (telefone or atual.telefone)
        novo_nasc = None if limpar_nascimento else (data_nascimento or atual.data_nascimento)
        with self._banco.transacao() as con:
            feito = con.execute(
                "update public.usuarios_privados set telefone = %s, data_nascimento = %s "
                "where usuario_id = %s returning usuario_id",
                (novo_tel, novo_nasc, uid),
            ).fetchone()
        if feito is None:  # conta sem CPF vinculado: não há linha privada para atualizar
            raise RegraDoBanco("Complete o cadastro com o CPF antes de salvar estes dados.")
        return self.dados(uid)

    # --- endereços --------------------------------------------------------------------
    def enderecos(self, usuario_id: str) -> list[Endereco]:
        uid = como_uuid(usuario_id)
        if uid is None:
            return []
        with self._banco.transacao() as con:
            linhas = con.execute(
                f"select {_COLS_END} from public.enderecos_salvos where usuario_id = %s "
                "order by principal desc, criado_em",
                (uid,),
            ).fetchall()
        return [_endereco(x) for x in linhas]

    def salvar_endereco(self, usuario_id: str, e: Endereco) -> Endereco:
        uid = exigir_uuid(usuario_id, "usuário")
        valores = (e.apelido, e.cep, e.logradouro, e.numero, e.complemento, e.bairro)
        valores = (*valores, e.cidade, e.uf)
        with self._banco.transacao() as con:
            con.execute("select id from public.usuarios where id = %s for update", (uid,))
            if e.id:
                eid = exigir_uuid(e.id, "endereço")
                if e.principal:
                    con.execute(
                        "update public.enderecos_salvos set principal = false "
                        "where usuario_id = %s and id <> %s",
                        (uid, eid),
                    )
                linha = con.execute(
                    "update public.enderecos_salvos set apelido=%s, cep=%s, logradouro=%s, "
                    "numero=%s, complemento=%s, bairro=%s, cidade=%s, uf=%s, "
                    "principal = (principal or %s) "
                    f"where id = %s and usuario_id = %s returning {_COLS_END}",
                    (*valores, e.principal, eid, uid),
                ).fetchone()
            else:
                total = con.execute(
                    "select count(*) as n from public.enderecos_salvos where usuario_id = %s",
                    (uid,),
                ).fetchone()["n"]
                if total >= LIMITE_ENDERECOS:
                    raise LimiteAtingido(f"Você pode salvar até {LIMITE_ENDERECOS} endereços.")
                principal = e.principal or total == 0
                if principal:
                    con.execute(
                        "update public.enderecos_salvos set principal = false "
                        "where usuario_id = %s",
                        (uid,),
                    )
                linha = con.execute(
                    "insert into public.enderecos_salvos (usuario_id, apelido, cep, logradouro, "
                    "numero, complemento, bairro, cidade, uf, principal) "
                    f"values (%s,%s,%s,%s,%s,%s,%s,%s,%s,%s) returning {_COLS_END}",
                    (uid, *valores, principal),
                ).fetchone()
        return _endereco(linha)

    def remover_endereco(self, usuario_id: str, endereco_id: str) -> bool:
        uid, eid = como_uuid(usuario_id), como_uuid(endereco_id)
        if uid is None or eid is None:
            return False
        with self._banco.transacao() as con:
            apagou = con.execute(
                "delete from public.enderecos_salvos where id = %s and usuario_id = %s "
                "returning principal",
                (eid, uid),
            ).fetchone()
            if apagou is not None and apagou["principal"]:  # outro vira o principal
                con.execute(
                    "update public.enderecos_salvos set principal = true where id = ("
                    "select id from public.enderecos_salvos where usuario_id = %s "
                    "order by criado_em limit 1)",
                    (uid,),
                )
        return apagou is not None

    # --- favoritos --------------------------------------------------------------------
    def favoritos(self, usuario_id: str) -> list[Favorito]:
        uid = como_uuid(usuario_id)
        if uid is None:
            return []
        with self._banco.transacao() as con:
            linhas = con.execute(
                "select f.profissional_id, u.nome, p.nota_publica, p.servicos_concluidos "
                "from public.profissionais_favoritos f "
                "join public.usuarios u on u.id = f.profissional_id "
                "join public.perfis_profissional p on p.usuario_id = f.profissional_id "
                "where f.usuario_id = %s and p.status = 'aprovado' order by f.criado_em desc",
                (uid,),
            ).fetchall()
        return [
            Favorito(
                str(x["profissional_id"]),
                x["nome"],
                float(x["nota_publica"]) if x["nota_publica"] is not None else None,
                int(x["servicos_concluidos"]) if x["servicos_concluidos"] is not None else None,
            )
            for x in linhas
        ]

    def favoritar(self, usuario_id: str, profissional_id: str) -> bool:
        uid, pid = exigir_uuid(usuario_id, "usuário"), como_uuid(profissional_id)
        if pid is None:
            return False
        with self._banco.transacao() as con:
            existe = con.execute(
                "select 1 from public.perfis_profissional where usuario_id = %s "
                "and status = 'aprovado'",
                (pid,),
            ).fetchone()
            if existe is None:
                return False
            con.execute(
                "insert into public.profissionais_favoritos (usuario_id, profissional_id) "
                "values (%s, %s) on conflict do nothing",
                (uid, pid),
            )
        return True

    def desfavoritar(self, usuario_id: str, profissional_id: str) -> None:
        uid, pid = como_uuid(usuario_id), como_uuid(profissional_id)
        if uid is None or pid is None:
            return
        with self._banco.transacao() as con:
            con.execute(
                "delete from public.profissionais_favoritos "
                "where usuario_id = %s and profissional_id = %s",
                (uid, pid),
            )

    # --- contatos de confiança --------------------------------------------------------
    def contatos(self, usuario_id: str) -> list[ContatoConfianca]:
        uid = como_uuid(usuario_id)
        if uid is None:
            return []
        with self._banco.transacao() as con:
            linhas = con.execute(
                "select id, nome, telefone, parentesco from public.contatos_confianca "
                "where usuario_id = %s order by criado_em",
                (uid,),
            ).fetchall()
        return [
            ContatoConfianca(str(x["id"]), x["nome"], x["telefone"], x["parentesco"])
            for x in linhas
        ]

    def salvar_contato(self, usuario_id: str, c: ContatoConfianca) -> ContatoConfianca:
        uid = exigir_uuid(usuario_id, "usuário")
        with self._banco.transacao() as con:
            con.execute("select id from public.usuarios where id = %s for update", (uid,))
            total = con.execute(
                "select count(*) as n from public.contatos_confianca where usuario_id = %s",
                (uid,),
            ).fetchone()["n"]
            if total >= LIMITE_CONTATOS:
                raise LimiteAtingido(f"Você pode ter até {LIMITE_CONTATOS} contatos de confiança.")
            x = con.execute(
                "insert into public.contatos_confianca (usuario_id, nome, telefone, parentesco) "
                "values (%s, %s, %s, %s) returning id, nome, telefone, parentesco",
                (uid, c.nome, c.telefone, c.parentesco),
            ).fetchone()
        return ContatoConfianca(str(x["id"]), x["nome"], x["telefone"], x["parentesco"])

    def remover_contato(self, usuario_id: str, contato_id: str) -> bool:
        uid, cid = como_uuid(usuario_id), como_uuid(contato_id)
        if uid is None or cid is None:
            return False
        with self._banco.transacao() as con:
            apagou = con.execute(
                "delete from public.contatos_confianca where id = %s and usuario_id = %s "
                "returning id",
                (cid, uid),
            ).fetchone()
        return apagou is not None
