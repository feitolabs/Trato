# ruff: noqa: S608
# Só fragmentos estáticos do código entram nas f-strings de SQL; todo valor vem por parâmetro.
"""Repositórios administrativos no Postgres (Supabase). Só o `service_role` do backend chega aqui.

Regras de ouro: nenhum `select *`; dados pessoais só saem por `dados_pessoais` (com motivo e
auditoria na MESMA transação); toda mudança grava a auditoria junto; versão de configuração
aprovada é imutável (o banco também garante).
"""

from __future__ import annotations

from collections.abc import Sequence
from datetime import datetime
from typing import Any

import psycopg

from trato.api.admin import config_regras as regras
from trato.api.admin.contexto import AdminContexto
from trato.api.admin.papeis import PapelEquipe
from trato.api.admin.repositorios import (
    DadosPessoaisAdmin,
    DefinicaoConfig,
    DocumentoAdmin,
    EntradaAuditoria,
    FaixaTaxa,
    FiltroAuditoria,
    MembroEquipe,
    ParametroConfig,
    PedidoResumoAdmin,
    UsuarioAdmin,
    VerificacaoAdmin,
    VersaoConfig,
)
from trato.persistencia.auditoria import registrar_na_transacao
from trato.persistencia.comum import como_uuid, exigir_uuid
from trato.persistencia.conexao import Banco
from trato.persistencia.erros import ErroPersistencia, NaoEncontrado, RegraDoBanco

# Nomes do domínio (API) <-> nomes do banco para o estado do pedido.
_ESTADO_PARA_BANCO = {"pago_e_retido": "pago_retido"}
_ESTADO_DO_BANCO = {v: k for k, v in _ESTADO_PARA_BANCO.items()}


def _txt(valor: object) -> str | None:
    return None if valor is None else str(valor)


def _like(termo: str) -> str:
    escapado = termo.replace("\\", "\\\\").replace("%", "\\%").replace("_", "\\_")
    return f"%{escapado}%"


def _auditar(con: psycopg.Connection[Any], ator_id: str, acao: str, **campos: Any) -> None:
    registrar_na_transacao(con, ator_id=ator_id, ator_tipo="equipe", acao=acao, **campos)


class EquipePostgres:
    def __init__(self, banco: Banco) -> None:
        self._banco = banco

    def obter(self, usuario_id: str) -> MembroEquipe | None:
        achado = como_uuid(usuario_id)
        if achado is None:
            return None
        with self._banco.transacao() as con:
            linha = con.execute(
                "select papel, ativo, revogado_em, alcada_centavos from public.equipe "
                "where usuario_id = %s",
                (achado,),
            ).fetchone()
        if linha is None:
            return None
        return MembroEquipe(
            achado,
            PapelEquipe(linha["papel"]),
            bool(linha["ativo"]),
            linha["revogado_em"],
            None if linha["alcada_centavos"] is None else int(linha["alcada_centavos"]),
        )


class AuditoriaAdminPostgres:
    def __init__(self, banco: Banco) -> None:
        self._banco = banco

    def registrar(
        self,
        *,
        ator_id: str,
        acao: str,
        entidade: str | None = None,
        entidade_id: str | None = None,
        antes: Any = None,
        depois: Any = None,
        motivo: str | None = None,
    ) -> int:
        with self._banco.transacao() as con:
            return registrar_na_transacao(
                con,
                ator_id=ator_id,
                ator_tipo="equipe",
                acao=acao,
                entidade=entidade,
                entidade_id=entidade_id,
                antes=antes,
                depois=depois,
                motivo=motivo,
            )

    def listar(
        self, filtro: FiltroAuditoria, limite: int, deslocamento: int
    ) -> tuple[Sequence[EntradaAuditoria], int]:
        ator = como_uuid(filtro.ator_id) if filtro.ator_id else None
        entidade_id = como_uuid(filtro.entidade_id) if filtro.entidade_id else None
        if (filtro.ator_id and ator is None) or (filtro.entidade_id and entidade_id is None):
            return (), 0  # id que não é uuid não casa com nada
        onde = (
            "(%(acao)s::text is null or acao like %(acao_like)s escape '\\') "
            "and (%(ator)s::uuid is null or ator_id = %(ator)s::uuid) "
            "and (%(entidade)s::text is null or entidade = %(entidade)s) "
            "and (%(entidade_id)s::uuid is null or entidade_id = %(entidade_id)s::uuid) "
            "and (%(desde)s::timestamptz is null or ocorrida_em >= %(desde)s::timestamptz) "
            "and (%(ate)s::timestamptz is null or ocorrida_em <= %(ate)s::timestamptz)"
        )
        params = {
            "acao": filtro.acao,
            "acao_like": (_like(filtro.acao)[1:-1] + "%" if filtro.acao else None),
            "ator": ator,
            "entidade": filtro.entidade,
            "entidade_id": entidade_id,
            "desde": filtro.desde,
            "ate": filtro.ate,
            "limite": limite,
            "deslocamento": deslocamento,
        }
        with self._banco.transacao() as con:
            total = con.execute(
                f"select count(*) as n from public.auditoria where {onde}", params
            ).fetchone()["n"]
            linhas = con.execute(
                "select id, ocorrida_em, ator_id, ator_tipo, acao, entidade, entidade_id, "
                "motivo, antes, depois from public.auditoria "
                f"where {onde} order by id desc limit %(limite)s offset %(deslocamento)s",
                params,
            ).fetchall()
        return (
            tuple(
                EntradaAuditoria(
                    l["id"],
                    l["ocorrida_em"],
                    _txt(l["ator_id"]),
                    l["ator_tipo"],
                    l["acao"],
                    l["entidade"],
                    _txt(l["entidade_id"]),
                    l["motivo"],
                    l["antes"],
                    l["depois"],
                )  # fmt: skip
                for l in linhas  # noqa: E741
            ),
            int(total),
        )

    def verificar_cadeia(self) -> int | None:
        with self._banco.transacao() as con:
            return con.execute(
                "select public.verificar_cadeia_auditoria() as primeira_falha"
            ).fetchone()["primeira_falha"]


def _mascarar_cpf(cpf: str | None) -> str | None:
    if not cpf:
        return None
    digitos = "".join(c for c in cpf if c.isdigit())
    return "***.***.***-" + digitos[-2:] if len(digitos) >= 2 else "***"


class VerificacoesAdminPostgres:
    def __init__(self, banco: Banco) -> None:
        self._banco = banco

    def listar(
        self, status: Sequence[str], limite: int, deslocamento: int
    ) -> tuple[Sequence[VerificacaoAdmin], int]:
        with self._banco.transacao() as con:
            total = con.execute(
                "select count(*) as n from public.verificacoes where status = any(%s)",
                (list(status),),
            ).fetchone()["n"]
            linhas = con.execute(
                "select v.id, v.profissional_id, u.nome, v.nivel_solicitado, v.status, "
                "v.enviada_em, v.decidida_em, v.motivo_recusa "
                "from public.verificacoes v join public.usuarios u on u.id = v.profissional_id "
                "where v.status = any(%s) order by v.enviada_em limit %s offset %s",
                (list(status), limite, deslocamento),
            ).fetchall()
        return tuple(self._de_linha(l) for l in linhas), int(total)  # noqa: E741

    @staticmethod
    def _de_linha(l: dict[str, Any], **extra: Any) -> VerificacaoAdmin:  # noqa: E741
        return VerificacaoAdmin(
            id=str(l["id"]),
            profissional_id=str(l["profissional_id"]),
            profissional_nome=l["nome"],
            nivel_solicitado=l["nivel_solicitado"],
            status=l["status"],
            enviada_em=l["enviada_em"],
            decidida_em=l["decidida_em"],
            motivo_recusa=l["motivo_recusa"],
            **extra,
        )

    def obter(self, verificacao_id: str) -> VerificacaoAdmin | None:
        achado = como_uuid(verificacao_id)
        if achado is None:
            return None
        with self._banco.transacao() as con:
            linha = con.execute(
                "select v.id, v.profissional_id, u.nome, v.nivel_solicitado, v.status, "
                "v.enviada_em, v.decidida_em, v.motivo_recusa, p.cpf "
                "from public.verificacoes v join public.usuarios u on u.id = v.profissional_id "
                "left join public.usuarios_privados p on p.usuario_id = v.profissional_id "
                "where v.id = %s",
                (achado,),
            ).fetchone()
            if linha is None:
                return None
            docs = con.execute(
                "select id, tipo, validade_em from public.verificacao_documentos "
                "where verificacao_id = %s order by criado_em, id",
                (achado,),
            ).fetchall()
        return self._de_linha(
            linha,
            cpf_mascarado=_mascarar_cpf(linha["cpf"]),
            documentos=tuple(
                DocumentoAdmin(str(d["id"]), d["tipo"], _txt(d["validade_em"])) for d in docs
            ),
        )

    def caminho_do_documento(self, verificacao_id: str, documento_id: str) -> str | None:
        v, d = como_uuid(verificacao_id), como_uuid(documento_id)
        if v is None or d is None:
            return None
        with self._banco.transacao() as con:
            linha = con.execute(
                "select storage_path from public.verificacao_documentos "
                "where id = %s and verificacao_id = %s",
                (d, v),
            ).fetchone()
        return None if linha is None else str(linha["storage_path"])

    def decidir(self, verificacao_id: str, analista_id: str, aprovar: bool, motivo: str) -> None:
        achado = exigir_uuid(verificacao_id, "id da verificação")
        novo = "aprovada" if aprovar else "recusada"
        with self._banco.transacao() as con:
            linha = con.execute(
                "select status, profissional_id, nivel_solicitado from public.verificacoes "
                "where id = %s for update",
                (achado,),
            ).fetchone()
            if linha is None:
                raise NaoEncontrado("Verificação não encontrada.")
            if linha["status"] not in ("enviada", "em_analise"):
                raise RegraDoBanco("Essa verificação já foi decidida.")
            con.execute(
                "update public.verificacoes set status = %s, analista_id = %s, "
                "motivo_recusa = %s, decidida_em = now() where id = %s",
                (novo, analista_id, None if aprovar else motivo, achado),
            )
            if aprovar:
                con.execute(
                    "update public.perfis_profissional set status = 'aprovado', "
                    "nivel_verificacao = %s where usuario_id = %s",
                    (linha["nivel_solicitado"], linha["profissional_id"]),
                )
            else:
                con.execute(
                    "update public.perfis_profissional set status = 'recusado' "
                    "where usuario_id = %s and status = 'em_analise'",
                    (linha["profissional_id"],),
                )
            _auditar(
                con,
                analista_id,
                f"verificacao.{novo}",
                entidade="verificacoes",
                entidade_id=achado,
                antes={"status": linha["status"]},
                depois={"status": novo, "nivel": linha["nivel_solicitado"]},
                motivo=motivo,
            )


class UsuariosAdminPostgres:
    def __init__(self, banco: Banco) -> None:
        self._banco = banco

    _BASE = (
        "select u.id, u.nome, u.status, u.criado_em, "
        "exists (select 1 from public.equipe e where e.usuario_id = u.id "
        "        and e.ativo and e.revogado_em is null) as eh_equipe, "
        "p.status as status_profissional, p.nivel_verificacao "
        "from public.usuarios u left join public.perfis_profissional p on p.usuario_id = u.id "
    )

    @staticmethod
    def _de_linha(l: dict[str, Any]) -> UsuarioAdmin:  # noqa: E741
        if l["eh_equipe"]:
            tipo = "equipe"
        elif l["status_profissional"] == "aprovado":
            tipo = "profissional"
        else:
            tipo = "cliente"
        return UsuarioAdmin(
            str(l["id"]), l["nome"], l["status"], tipo, l["criado_em"],
            l["nivel_verificacao"], l["status_profissional"],
        )  # fmt: skip

    def buscar(
        self, termo: str | None, status: str | None, limite: int, deslocamento: int
    ) -> tuple[Sequence[UsuarioAdmin], int]:
        onde = (
            "where (%(status)s::text is null or u.status = %(status)s) "
            "and (%(termo)s::text is null or u.nome ilike %(like)s escape '\\' "
            "     or u.id::text = %(termo)s)"
        )
        params = {
            "status": status,
            "termo": termo,
            "like": _like(termo) if termo else None,
            "limite": limite,
            "deslocamento": deslocamento,
        }
        with self._banco.transacao() as con:
            total = con.execute(
                f"select count(*) as n from public.usuarios u {onde}", params
            ).fetchone()["n"]
            linhas = con.execute(
                f"{self._BASE}{onde} order by u.nome, u.id limit %(limite)s "
                "offset %(deslocamento)s",
                params,
            ).fetchall()
        return tuple(self._de_linha(l) for l in linhas), int(total)  # noqa: E741

    def obter(self, usuario_id: str) -> UsuarioAdmin | None:
        achado = como_uuid(usuario_id)
        if achado is None:
            return None
        with self._banco.transacao() as con:
            linha = con.execute(f"{self._BASE}where u.id = %s", (achado,)).fetchone()
        return None if linha is None else self._de_linha(linha)

    def nomes(self, ids: Sequence[str]) -> dict[str, str]:
        validos = [i for i in (como_uuid(x) for x in ids) if i]
        if not validos:
            return {}
        with self._banco.transacao() as con:
            linhas = con.execute(
                "select id, nome from public.usuarios where id = any(%s::uuid[])", (validos,)
            ).fetchall()
        return {str(l["id"]): l["nome"] for l in linhas}  # noqa: E741

    def dados_pessoais(
        self, usuario_id: str, ator_id: str, motivo: str
    ) -> DadosPessoaisAdmin | None:
        achado = como_uuid(usuario_id)
        if achado is None:
            return None
        with self._banco.transacao() as con:
            existe = con.execute(
                "select 1 from public.usuarios where id = %s", (achado,)
            ).fetchone()
            if existe is None:
                return None
            linha = con.execute(
                "select cpf, telefone, data_nascimento, telefone_confirmado_em, "
                "email_confirmado_em from public.usuarios_privados where usuario_id = %s",
                (achado,),
            ).fetchone()
            # Registra os CAMPOS revelados, nunca os valores.
            _auditar(
                con,
                ator_id,
                "dado_pessoal.revelado",
                entidade="usuarios_privados",
                entidade_id=achado,
                depois={"campos": ["cpf", "telefone", "data_nascimento"]},
                motivo=motivo,
            )
        if linha is None:
            return DadosPessoaisAdmin(None, None, None, None, None)
        return DadosPessoaisAdmin(
            linha["cpf"], linha["telefone"], _txt(linha["data_nascimento"]),
            linha["telefone_confirmado_em"], linha["email_confirmado_em"],
        )  # fmt: skip


class PedidosAdminPostgres:
    def __init__(self, banco: Banco) -> None:
        self._banco = banco

    def buscar(
        self,
        termo: str | None,
        estado: str | None,
        cliente_id: str | None,
        profissional_id: str | None,
        limite: int,
        deslocamento: int,
    ) -> tuple[Sequence[PedidoResumoAdmin], int]:
        cliente = como_uuid(cliente_id) if cliente_id else None
        profissional = como_uuid(profissional_id) if profissional_id else None
        if (cliente_id and cliente is None) or (profissional_id and profissional is None):
            return (), 0
        onde = (
            "where (%(estado)s::text is null or p.status = %(estado)s) "
            "and (%(cliente)s::uuid is null or p.cliente_id = %(cliente)s::uuid) "
            "and (%(profissional)s::uuid is null or c.profissional_id = %(profissional)s::uuid) "
            "and (%(termo)s::text is null or p.titulo ilike %(like)s escape '\\' "
            "     or p.id::text = %(termo)s)"
        )
        juncao = "from public.pedidos p left join public.contratos c on c.pedido_id = p.id "
        params = {
            "estado": _ESTADO_PARA_BANCO.get(estado, estado) if estado else None,
            "cliente": cliente,
            "profissional": profissional,
            "termo": termo,
            "like": _like(termo) if termo else None,
            "limite": limite,
            "deslocamento": deslocamento,
        }
        with self._banco.transacao() as con:
            total = con.execute(f"select count(*) as n {juncao}{onde}", params).fetchone()["n"]
            linhas = con.execute(
                "select p.id, p.titulo, p.status, p.cliente_id, u.nome as cliente_nome, "
                "c.profissional_id, c.valor_total_centavos, p.criado_em "
                f"{juncao}join public.usuarios u on u.id = p.cliente_id {onde} "
                "order by p.criado_em desc, p.id limit %(limite)s offset %(deslocamento)s",
                params,
            ).fetchall()
        return (
            tuple(
                PedidoResumoAdmin(
                    str(l["id"]),
                    l["titulo"],
                    _ESTADO_DO_BANCO.get(l["status"], l["status"]),
                    str(l["cliente_id"]),
                    l["cliente_nome"],
                    _txt(l["profissional_id"]),
                    None if l["valor_total_centavos"] is None else int(l["valor_total_centavos"]),
                    l["criado_em"],
                )  # fmt: skip
                for l in linhas  # noqa: E741
            ),
            int(total),
        )


_COLUNAS_VERSAO = (
    "id, numero, status, motivo, criada_por, aprovada_por, vigente_desde, revertida_de, criado_em"
)


def _recusa_do_banco(erro: ErroPersistencia) -> ErroPersistencia:
    """Gatilhos da configuração fazem `raise exception` com texto nosso; mostramos esse texto."""
    causa = erro.__cause__
    if isinstance(causa, psycopg.errors.RaiseException) and causa.diag.message_primary:
        return RegraDoBanco(causa.diag.message_primary)
    return erro


class ConfigAdminPostgres:
    def __init__(self, banco: Banco) -> None:
        self._banco = banco

    # --- leitura --------------------------------------------------------------------------

    def definicoes(self) -> Sequence[DefinicaoConfig]:
        with self._banco.transacao() as con:
            return self._definicoes(con)

    @staticmethod
    def _definicoes(con: psycopg.Connection[Any]) -> tuple[DefinicaoConfig, ...]:
        linhas = con.execute(
            "select chave, descricao, unidade, minimo, maximo, escopos_permitidos, "
            "exige_dupla_aprovacao from public.config_definicoes order by chave"
        ).fetchall()
        return tuple(
            DefinicaoConfig(
                l["chave"],
                l["descricao"],
                l["unidade"],
                None if l["minimo"] is None else int(l["minimo"]),
                None if l["maximo"] is None else int(l["maximo"]),
                tuple(l["escopos_permitidos"]),
                bool(l["exige_dupla_aprovacao"]),
            )  # fmt: skip
            for l in linhas  # noqa: E741
        )

    @staticmethod
    def _versao_de_linha(l: dict[str, Any], con=None, completa: bool = False) -> VersaoConfig:  # noqa: E741
        parametros: tuple[ParametroConfig, ...] = ()
        faixas: tuple[FaixaTaxa, ...] = ()
        if completa and con is not None:
            parametros = tuple(
                ParametroConfig(
                    p["chave"],
                    int(p["valor"]),
                    p["escopo_tipo"],
                    _txt(p["escopo_id"]),
                    p["escopo_texto"],
                )  # fmt: skip
                for p in con.execute(
                    "select chave, valor, escopo_tipo, escopo_id, escopo_texto "
                    "from public.config_parametros where versao_id = %s "
                    "order by chave, escopo_tipo, escopo_id, escopo_texto",
                    (l["id"],),
                ).fetchall()
            )
            faixas = tuple(
                FaixaTaxa(
                    int(f["de_centavos"]),
                    None if f["ate_centavos"] is None else int(f["ate_centavos"]),
                    int(f["taxa_bps"]),
                    f["escopo_tipo"],
                    _txt(f["escopo_id"]),
                    f["escopo_texto"],
                )  # fmt: skip
                for f in con.execute(
                    "select de_centavos, ate_centavos, taxa_bps, escopo_tipo, escopo_id, "
                    "escopo_texto from public.config_faixas_taxa where versao_id = %s "
                    "order by escopo_tipo, escopo_id, escopo_texto, de_centavos",
                    (l["id"],),
                ).fetchall()
            )
        return VersaoConfig(
            id=str(l["id"]),
            numero=int(l["numero"]),
            status=l["status"],
            motivo=l["motivo"],
            criada_por=str(l["criada_por"]),
            aprovada_por=_txt(l["aprovada_por"]),
            vigente_desde=l["vigente_desde"],
            revertida_de=_txt(l["revertida_de"]),
            criado_em=l["criado_em"],
            parametros=parametros,
            faixas=faixas,
        )

    def versoes(self) -> Sequence[VersaoConfig]:
        with self._banco.transacao() as con:
            linhas = con.execute(
                f"select {_COLUNAS_VERSAO} from public.config_versoes order by numero desc"
            ).fetchall()
        return tuple(self._versao_de_linha(l) for l in linhas)  # noqa: E741

    def versao(self, versao_id: str) -> VersaoConfig | None:
        achado = como_uuid(versao_id)
        if achado is None:
            return None
        with self._banco.transacao() as con:
            return self._ler(con, achado)

    def _ler(self, con: psycopg.Connection[Any], versao_id: str, travar: bool = False):
        linha = con.execute(
            f"select {_COLUNAS_VERSAO} from public.config_versoes where id = %s"
            + (" for update" if travar else ""),
            (versao_id,),
        ).fetchone()
        return None if linha is None else self._versao_de_linha(linha, con, completa=True)

    def _exigir(self, con: psycopg.Connection[Any], versao_id: str, travar: bool = True):
        versao = self._ler(con, exigir_uuid(versao_id, "id da versão"), travar)
        if versao is None:
            raise NaoEncontrado("Versão de configuração não encontrada.")
        return versao

    def vigente(self) -> VersaoConfig | None:
        with self._banco.transacao() as con:
            linha = con.execute(
                f"select {_COLUNAS_VERSAO} from public.config_versoes where status = 'vigente'"
            ).fetchone()
            return None if linha is None else self._versao_de_linha(linha, con, completa=True)

    # --- escrita --------------------------------------------------------------------------

    def _inserir(
        self,
        con: psycopg.Connection[Any],
        autor_id: str,
        motivo: str,
        parametros: Sequence[ParametroConfig],
        faixas: Sequence[FaixaTaxa],
        vigente_desde: datetime | None,
        revertida_de: str | None,
        status: str,
    ) -> VersaoConfig:
        regras.validar_itens(self._definicoes(con), parametros, faixas)
        linha = con.execute(
            "insert into public.config_versoes (status, criada_por, motivo, vigente_desde, "
            f"revertida_de) values (%s, %s, %s, %s, %s) returning {_COLUNAS_VERSAO}",
            (status, autor_id, motivo, vigente_desde, revertida_de),
        ).fetchone()
        for p in parametros:
            con.execute(
                "insert into public.config_parametros (versao_id, chave, valor, escopo_tipo, "
                "escopo_id, escopo_texto) values (%s, %s, %s, %s, %s, %s)",
                (linha["id"], p.chave, p.valor, p.escopo_tipo, p.escopo_id, p.escopo_texto),
            )
        for f in faixas:
            con.execute(
                "insert into public.config_faixas_taxa (versao_id, de_centavos, ate_centavos, "
                "taxa_bps, escopo_tipo, escopo_id, escopo_texto) "
                "values (%s, %s, %s, %s, %s, %s, %s)",
                (
                    linha["id"], f.de_centavos, f.ate_centavos, f.taxa_bps, f.escopo_tipo,
                    f.escopo_id, f.escopo_texto,
                ),
            )  # fmt: skip
        return self._versao_de_linha(linha, con, completa=True)

    @staticmethod
    def _auditar(con, ator, acao, antes, versao: VersaoConfig, motivo: str) -> None:
        _auditar(
            con,
            ator,
            acao,
            entidade="config_versoes",
            entidade_id=versao.id,
            antes={"status": antes} if antes else None,
            depois={"status": versao.status, "numero": versao.numero},
            motivo=motivo,
        )

    def criar_rascunho(
        self, autor_id, motivo, parametros, faixas, vigente_desde, partir_da_vigente
    ) -> VersaoConfig:
        try:
            with self._banco.transacao() as con:
                if partir_da_vigente:
                    linha = con.execute(
                        "select id from public.config_versoes where status = 'vigente'"
                    ).fetchone()
                    if linha is not None:
                        base = self._ler(con, str(linha["id"]))
                        parametros, faixas = regras.mesclar(
                            base.parametros, base.faixas, parametros, faixas
                        )
                versao = self._inserir(
                    con, autor_id, motivo, parametros, faixas, vigente_desde, None, "rascunho"
                )
                self._auditar(con, autor_id, "config.rascunho_criado", None, versao, motivo)
                return versao
        except ErroPersistencia as erro:
            raise _recusa_do_banco(erro) from erro

    def enviar_para_aprovacao(self, versao_id, autor_id, motivo) -> VersaoConfig:
        try:
            with self._banco.transacao() as con:
                versao = self._exigir(con, versao_id)
                regras.exigir_status(versao, "rascunho")
                regras.validar_publicavel(versao)
                con.execute(
                    "update public.config_versoes set status = 'aguardando_aprovacao' "
                    "where id = %s",
                    (versao.id,),
                )
                novo = self._exigir(con, versao.id, travar=False)
                self._auditar(
                    con, autor_id, "config.enviada_para_aprovacao", versao.status, novo, motivo
                )
                return novo
        except ErroPersistencia as erro:
            raise _recusa_do_banco(erro) from erro

    def aprovar(self, versao_id, aprovador_id, motivo) -> VersaoConfig:
        try:
            with self._banco.transacao() as con:
                versao = self._exigir(con, versao_id)
                regras.exigir_status(versao, "aguardando_aprovacao")
                regras.exigir_outra_pessoa(versao, aprovador_id)
                con.execute(
                    "update public.config_versoes set status = 'aprovada', aprovada_por = %s, "
                    "vigente_desde = coalesce(vigente_desde, now()) where id = %s",
                    (aprovador_id, versao.id),
                )
                novo = self._exigir(con, versao.id, travar=False)
                self._auditar(con, aprovador_id, "config.aprovada", versao.status, novo, motivo)
                return novo
        except ErroPersistencia as erro:
            raise _recusa_do_banco(erro) from erro

    def publicar(self, versao_id, autor_id, motivo, agora) -> VersaoConfig:
        try:
            with self._banco.transacao() as con:
                versao = self._exigir(con, versao_id)
                regras.exigir_status(versao, "aprovada")
                regras.exigir_vigencia_chegou(versao, agora)
                regras.validar_publicavel(versao)
                fim = "revertida" if versao.revertida_de else "substituida"
                # A antiga sai antes: o banco só aceita uma versão vigente por vez.
                con.execute(
                    "update public.config_versoes set status = %s where status = 'vigente'",
                    (fim,),
                )
                con.execute(
                    "update public.config_versoes set status = 'vigente' where id = %s",
                    (versao.id,),
                )
                novo = self._exigir(con, versao.id, travar=False)
                self._auditar(con, autor_id, "config.publicada", versao.status, novo, motivo)
                return novo
        except ErroPersistencia as erro:
            raise _recusa_do_banco(erro) from erro

    def reverter(self, versao_alvo_id, autor_id, motivo) -> VersaoConfig:
        try:
            with self._banco.transacao() as con:
                alvo = self._exigir(con, versao_alvo_id, travar=False)
                if alvo.status not in ("vigente", "substituida", "revertida"):
                    raise RegraDoBanco("Só dá para reverter para uma versão que já valeu.")
                versao = self._inserir(
                    con, autor_id, motivo, alvo.parametros, alvo.faixas, None, alvo.id,
                    "aguardando_aprovacao",
                )  # fmt: skip
                self._auditar(con, autor_id, "config.reversao_proposta", None, versao, motivo)
                return versao
        except ErroPersistencia as erro:
            raise _recusa_do_banco(erro) from erro

    def descartar_rascunho(self, versao_id, autor_id, motivo) -> None:
        try:
            with self._banco.transacao() as con:
                versao = self._exigir(con, versao_id)
                regras.exigir_status(versao, "rascunho", "aguardando_aprovacao")
                con.execute(
                    "delete from public.config_parametros where versao_id = %s", (versao.id,)
                )
                con.execute(
                    "delete from public.config_faixas_taxa where versao_id = %s", (versao.id,)
                )
                con.execute("delete from public.config_versoes where id = %s", (versao.id,))
                self._auditar(
                    con, autor_id, "config.rascunho_descartado", versao.status, versao, motivo
                )
        except ErroPersistencia as erro:
            raise _recusa_do_banco(erro) from erro


def criar_admin_postgres(banco: Banco, assinador=None) -> AdminContexto:
    return AdminContexto(
        equipe=EquipePostgres(banco),
        verificacoes=VerificacoesAdminPostgres(banco),
        usuarios=UsuariosAdminPostgres(banco),
        pedidos=PedidosAdminPostgres(banco),
        config=ConfigAdminPostgres(banco),
        auditoria=AuditoriaAdminPostgres(banco),
        assinador=assinador,
    )
