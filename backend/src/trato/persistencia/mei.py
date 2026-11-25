"""MEI do profissional no Postgres (colunas de `public.perfis_profissional`).

Colunas: `cnpj`, `mei_status`, `mei_validado_em`, `razao_social`, `mei_motivo`. O `cnpj` só é
gravado quando o MEI está `valido`; pendente e inválido gravam só o estado e deixam `cnpj` nulo,
para um pedido de validação não ocupar o índice único `ux_perfis_profissional_cnpj` (squatting).
Se a coluna nova ainda não existe, a leitura cai no padrão (`nao_informado`) sem quebrar.
"""

from __future__ import annotations

import psycopg

from trato.persistencia.comum import como_uuid
from trato.persistencia.conexao import Banco
from trato.persistencia.erros import Duplicado, ErroPersistencia
from trato.profissional.mei import (
    MOTIVOS,
    CnpjEmUso,
    PerfilInexistente,
    RegistroMei,
    StatusMei,
)


class MeiPostgres:
    def __init__(self, banco: Banco) -> None:
        self._banco = banco

    _LER = "cnpj, mei_status, mei_motivo, mei_validado_em, razao_social"

    def obter(self, profissional_id: str) -> RegistroMei | None:
        uid = como_uuid(profissional_id)
        if uid is None:
            return None
        try:
            linha = self._ler(uid, com_tipo=True)
        except ErroPersistencia as erro:
            if not isinstance(erro.__cause__, psycopg.errors.UndefinedColumn):
                raise
            # coluna nova ainda não aplicada: tenta sem `tipo_cnpj`; sem as outras, padrão
            try:
                linha = self._ler(uid, com_tipo=False)
            except ErroPersistencia as erro2:
                if isinstance(erro2.__cause__, psycopg.errors.UndefinedColumn):
                    return None
                raise
        if linha is None:
            return None
        status = StatusMei(linha["mei_status"])
        return RegistroMei(
            profissional_id=profissional_id,
            cnpj=linha["cnpj"],
            mei_status=status,
            mei_motivo=linha["mei_motivo"] or MOTIVOS.get(status, ""),
            mei_validado_em=linha["mei_validado_em"],
            razao_social=linha["razao_social"],
            tipo_cnpj=linha.get("tipo_cnpj"),
        )

    def _ler(self, uid, *, com_tipo: bool):  # type: ignore[no-untyped-def]
        colunas = self._LER + (", tipo_cnpj" if com_tipo else "")
        with self._banco.transacao() as con:
            return con.execute(
                f"select {colunas} from public.perfis_profissional "  # noqa: S608
                "where usuario_id = %s",
                (uid,),
            ).fetchone()

    def salvar(self, registro: RegistroMei) -> None:
        uid = como_uuid(registro.profissional_id)
        if uid is None:
            raise PerfilInexistente
        try:
            try:
                self._gravar(uid, registro, com_tipo=True)
            except ErroPersistencia as erro:
                if not isinstance(erro.__cause__, psycopg.errors.UndefinedColumn):
                    raise
                self._gravar(uid, registro, com_tipo=False)  # sem a coluna `tipo_cnpj` ainda
        except (Duplicado, psycopg.errors.UniqueViolation) as erro:
            # Nunca vaza o motivo (nem o CNPJ) para quem chamou: o serviço responde neutro.
            raise CnpjEmUso from erro

    def _gravar(self, uid, registro: RegistroMei, *, com_tipo: bool) -> None:  # type: ignore[no-untyped-def]
        valido = registro.mei_status is StatusMei.VALIDO
        extra = ", tipo_cnpj = %s" if com_tipo else ""
        valores = [
            registro.cnpj if valido else None,
            registro.mei_status.value,
            registro.mei_motivo,
            registro.mei_validado_em,
            registro.razao_social if valido else None,
        ]
        if com_tipo:
            valores.append(registro.tipo_cnpj if valido else None)
        with self._banco.transacao() as con:
            feito = con.execute(
                "update public.perfis_profissional set cnpj = %s, mei_status = %s, "  # noqa: S608
                f"mei_motivo = %s, mei_validado_em = %s, razao_social = %s{extra} "
                "where usuario_id = %s",
                (*valores, uid),
            )
            if feito.rowcount == 0:
                raise PerfilInexistente
