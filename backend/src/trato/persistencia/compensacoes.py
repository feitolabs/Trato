"""Compensação em repasses (Termos 8.6 e 17.4; migration 20261126061000).

Quem lança no livro são as funções do banco (`compensacao_*`). Este módulo só as chama e lê as
dívidas. Sem elas (ou em memória) `disponivel()` é falso e a liberação segue como antes.
"""

from __future__ import annotations

import uuid
from dataclasses import dataclass
from datetime import datetime
from typing import Any, Protocol

from trato.persistencia.comum import como_uuid
from trato.persistencia.conexao import Banco


@dataclass(frozen=True)
class Divida:
    id: str
    contrato_id: str
    pedido_id: str
    profissional_id: str
    origem_tipo: str  # disputa | disputa_contestacao | regresso
    valor_centavos: int
    compensado_centavos: int
    motivo: str
    status: str  # aberta | quitada | cancelada
    criada_em: datetime
    avisado_em: datetime | None = None
    cancelada_em: datetime | None = None
    motivo_cancelamento: str | None = None


@dataclass(frozen=True)
class Registro:
    # ok | ja_registrada | conflito | acima_do_devido | origem_nao_decidida |
    # decisao_substituida | contrato_nao_encontrado | analista_invalido | indisponivel
    resultado: str
    divida_id: str | None = None
    maximo_centavos: int = 0


@dataclass(frozen=True)
class Aplicacao:
    # ok | nada_a_compensar | ja_aplicada | contrato_nao_encontrado | indisponivel
    resultado: str
    aplicado_centavos: int = 0
    liberado_restante_centavos: int | None = None


@dataclass(frozen=True)
class Cancelamento:
    resultado: str  # ok | ja_cancelada | nao_encontrada | analista_invalido | indisponivel
    devolvido_centavos: int = 0


@dataclass(frozen=True)
class Proposta:
    """Proposta de regresso (17.4): uma pessoa propõe, outra aprova ou recusa."""

    id: str
    contrato_id: str
    pedido_id: str
    profissional_id: str
    referencia: str
    valor_centavos: int
    motivo: str
    status: str  # proposta | aprovada | recusada
    proposta_por: str
    proposta_em: datetime
    decidida_por: str | None = None
    decidida_em: datetime | None = None
    motivo_decisao: str | None = None
    divida_id: str | None = None


@dataclass(frozen=True)
class Proposto:
    # ok | ja_proposta | conflito | ja_registrada | analista_invalido |
    # contrato_nao_encontrado | indisponivel
    resultado: str
    proposta_id: str | None = None


class RepositorioCompensacoes(Protocol):
    def disponivel(self) -> bool: ...

    def registrar_disputa(
        self,
        pedido_id: str,
        contestacao_id: str | None,
        valor_centavos: int,
        motivo: str,
        operador_id: str,
    ) -> Registro:
        """`operador_id`: quem registrou (é ele que o banco audita, não quem decidiu)."""

    def registrar_regresso(
        self,
        pedido_id: str,
        referencia: str,
        valor_centavos: int,
        motivo: str,
        analista_id: str,
        aprovador_id: str,
    ) -> Registro: ...

    def avisar(self, divida_id: str, operador_id: str) -> str: ...

    def regresso_disponivel(self) -> bool: ...

    def propor_regresso(
        self,
        pedido_id: str,
        referencia: str,
        valor_centavos: int,
        motivo: str,
        operador_id: str,
    ) -> Proposto: ...

    def aprovar_regresso(self, proposta_id: str, operador_id: str) -> Registro:
        """ok | ja_aprovada | ja_recusada | nao_encontrada | analista_invalido |
        mesma_pessoa | proponente_invalido | acima_do_devido | conflito |
        contrato_nao_encontrado | indisponivel"""

    def recusar_regresso(self, proposta_id: str, operador_id: str, motivo: str) -> str: ...

    def proposta(self, proposta_id: str) -> Proposta | None: ...

    def propostas(
        self, status: str | None = None, limite: int = 50, deslocamento: int = 0
    ) -> tuple[list[Proposta], int]: ...

    def aplicar(self, pedido_id: str, chave: str) -> Aplicacao:
        """Na transação da liberação: tira do liberado o que as dívidas avisadas pedem."""

    def cancelar(self, divida_id: str, analista_id: str, motivo: str) -> Cancelamento: ...

    def obter(self, divida_id: str) -> Divida | None: ...

    def listar(
        self,
        profissional_id: str | None = None,
        pedido_id: str | None = None,
        status: str | None = None,
        limite: int = 50,
        deslocamento: int = 0,
    ) -> tuple[list[Divida], int]: ...


class CompensacoesIndisponiveis:
    """Memória: as regras vivem no banco; aqui nada é compensado."""

    def disponivel(self) -> bool:
        return False

    def registrar_disputa(
        self,
        pedido_id: str,
        contestacao_id: str | None,
        valor_centavos: int,
        motivo: str,
        operador_id: str,
    ) -> Registro:
        return Registro("indisponivel")

    def registrar_regresso(self, *_: Any) -> Registro:
        return Registro("indisponivel")

    def avisar(self, divida_id: str, operador_id: str) -> str:
        return "nao_encontrada"

    def regresso_disponivel(self) -> bool:
        return False

    def propor_regresso(self, *_: Any) -> Proposto:
        return Proposto("indisponivel")

    def aprovar_regresso(self, *_: Any) -> Registro:
        return Registro("indisponivel")

    def recusar_regresso(self, *_: Any) -> str:
        return "indisponivel"

    def proposta(self, proposta_id: str) -> Proposta | None:
        return None

    def propostas(self, *_: Any, **__: Any) -> tuple[list[Proposta], int]:
        return [], 0

    def aplicar(self, pedido_id: str, chave: str) -> Aplicacao:
        return Aplicacao("indisponivel")

    def cancelar(self, *_: Any) -> Cancelamento:
        return Cancelamento("indisponivel")

    def obter(self, divida_id: str) -> Divida | None:
        return None

    def listar(self, *_: Any, **__: Any) -> tuple[list[Divida], int]:
        return [], 0


_SELECT = (
    "select d.id, d.contrato_id, d.pedido_id, d.profissional_id, d.origem_tipo, "
    "d.valor_centavos, d.motivo, d.status, d.criada_em, d.avisado_em, d.cancelada_em, "
    "d.motivo_cancelamento, coalesce((select sum(a.valor_centavos) from "
    "public.compensacoes_aplicadas a where a.divida_id = d.id and not exists "
    "(select 1 from public.lancamentos e where e.estorna_id = a.lancamento_id)), 0)::bigint "
    "as compensado from public.compensacoes_dividas d"
)


def _divida(x: dict[str, Any]) -> Divida:
    return Divida(
        id=str(x["id"]),
        contrato_id=str(x["contrato_id"]),
        pedido_id=str(x["pedido_id"]),
        profissional_id=str(x["profissional_id"]),
        origem_tipo=x["origem_tipo"],
        valor_centavos=int(x["valor_centavos"]),
        compensado_centavos=int(x["compensado"]),
        motivo=x["motivo"],
        status=x["status"],
        criada_em=x["criada_em"],
        avisado_em=x["avisado_em"],
        cancelada_em=x["cancelada_em"],
        motivo_cancelamento=x["motivo_cancelamento"],
    )


_SELECT_PROPOSTA = (
    "select id, contrato_id, pedido_id, profissional_id, referencia, valor_centavos, motivo, "
    "status, proposta_por, proposta_em, decidida_por, decidida_em, motivo_decisao, divida_id "
    "from public.compensacao_propostas_regresso"
)


def _proposta(x: dict[str, Any]) -> Proposta:
    textos = ("id", "contrato_id", "pedido_id", "profissional_id", "referencia", "proposta_por")
    dados = dict(x)
    for campo in textos:
        dados[campo] = str(x[campo])
    for campo in ("decidida_por", "divida_id"):
        dados[campo] = str(x[campo]) if x[campo] else None
    dados["valor_centavos"] = int(x["valor_centavos"])
    return Proposta(**dados)


class CompensacoesPostgres:
    def __init__(self, banco: Banco) -> None:
        self._banco = banco

    @staticmethod
    def _tem(con: Any) -> bool:
        # Conferir antes: uma chamada que falha estragaria a transação da liberação.
        return con.execute(
            "select to_regprocedure('public.compensacao_aplicar(uuid,text)') is not null as tem"
        ).fetchone()["tem"]

    def disponivel(self) -> bool:
        with self._banco.transacao() as con:
            return self._tem(con)

    @staticmethod
    def _contrato(con: Any, pedido_id: str) -> Any:
        pid = como_uuid(pedido_id)
        if pid is None:
            return None
        linha = con.execute(
            "select id from public.contratos where pedido_id = %s and status <> 'cancelado'",
            (pid,),
        ).fetchone()
        return linha["id"] if linha else None

    @staticmethod
    def _registro(linha: Any) -> Registro:
        divida = linha["divida_id"]
        return Registro(
            str(linha["resultado"]),
            str(divida) if divida else None,
            int(linha["maximo_centavos"] or 0),
        )

    def registrar_disputa(
        self,
        pedido_id: str,
        contestacao_id: str | None,
        valor_centavos: int,
        motivo: str,
        operador_id: str,
    ) -> Registro:
        operador = como_uuid(operador_id)
        with self._banco.transacao() as con:
            # Só a assinatura com o operador: a antiga atribuiria o registro a quem decidiu.
            if not con.execute(
                "select to_regprocedure('public.compensacao_registrar_disputa("
                "uuid,uuid,bigint,text,uuid)') is not null as tem"
            ).fetchone()["tem"]:
                return Registro("indisponivel")
            if operador is None:
                return Registro("analista_invalido")
            contrato = self._contrato(con, pedido_id)
            if contrato is None:
                return Registro("contrato_nao_encontrado")
            disputa = con.execute(
                "select id from public.disputas where contrato_id = %s and status = 'decidida' "
                "order by aberta_em desc limit 1",
                (contrato,),
            ).fetchone()
            if disputa is None:
                return Registro("origem_nao_decidida")
            contestacao = como_uuid(contestacao_id) if contestacao_id else None
            if contestacao_id and contestacao is None:
                return Registro("origem_nao_decidida")
            linha = con.execute(
                "select resultado, divida_id, maximo_centavos "
                "from public.compensacao_registrar_disputa(%s, %s, %s, %s, %s)",
                (disputa["id"], contestacao, valor_centavos, motivo, operador),
            ).fetchone()
        return self._registro(linha)

    def registrar_regresso(
        self,
        pedido_id: str,
        referencia: str,
        valor_centavos: int,
        motivo: str,
        analista_id: str,
        aprovador_id: str,
    ) -> Registro:
        with self._banco.transacao() as con:
            if not self._tem(con):
                return Registro("indisponivel")
            contrato = self._contrato(con, pedido_id)
            if contrato is None:
                return Registro("contrato_nao_encontrado")
            linha = con.execute(
                "select resultado, divida_id, maximo_centavos "
                "from public.compensacao_registrar_regresso(%s, %s, %s, %s, %s, %s)",
                (contrato, uuid.UUID(referencia), valor_centavos, motivo,
                 como_uuid(analista_id), como_uuid(aprovador_id)),
            ).fetchone()  # fmt: skip
        return self._registro(linha)

    def avisar(self, divida_id: str, operador_id: str) -> str:
        did, operador = como_uuid(divida_id), como_uuid(operador_id)
        with self._banco.transacao() as con:
            if did is None or not self._tem(con):
                return "nao_encontrada"
            if not con.execute(
                "select to_regprocedure('public.compensacao_avisar(uuid,uuid)') is not null as tem"
            ).fetchone()["tem"]:  # banco ainda sem a 20261126195000: assinatura antiga
                sql, valores = "select public.compensacao_avisar(%s) as r", (did,)
            elif operador is None:
                return "analista_invalido"
            else:
                sql, valores = "select public.compensacao_avisar(%s, %s) as r", (did, operador)
            return str(con.execute(sql, valores).fetchone()["r"])

    @staticmethod
    def _tem_regresso(con: Any) -> bool:
        return con.execute(
            "select to_regprocedure('public.compensacao_aprovar_regresso(uuid,uuid)') "
            "is not null as tem"
        ).fetchone()["tem"]

    def regresso_disponivel(self) -> bool:
        with self._banco.transacao() as con:
            return self._tem_regresso(con)

    def propor_regresso(
        self,
        pedido_id: str,
        referencia: str,
        valor_centavos: int,
        motivo: str,
        operador_id: str,
    ) -> Proposto:
        operador, ref = como_uuid(operador_id), como_uuid(referencia)
        with self._banco.transacao() as con:
            if not self._tem_regresso(con) or ref is None:
                return Proposto("indisponivel")
            if operador is None:
                return Proposto("analista_invalido")
            contrato = self._contrato(con, pedido_id)
            if contrato is None:
                return Proposto("contrato_nao_encontrado")
            x = con.execute(
                "select resultado, proposta_id "
                "from public.compensacao_propor_regresso(%s, %s, %s, %s, %s)",
                (contrato, ref, valor_centavos, motivo, operador),
            ).fetchone()
        proposta = x["proposta_id"]
        return Proposto(str(x["resultado"]), str(proposta) if proposta else None)

    def aprovar_regresso(self, proposta_id: str, operador_id: str) -> Registro:
        pid, operador = como_uuid(proposta_id), como_uuid(operador_id)
        with self._banco.transacao() as con:
            if not self._tem_regresso(con):
                return Registro("indisponivel")
            if pid is None:
                return Registro("nao_encontrada")
            if operador is None:
                return Registro("analista_invalido")
            linha = con.execute(
                "select resultado, divida_id, maximo_centavos "
                "from public.compensacao_aprovar_regresso(%s, %s)",
                (pid, operador),
            ).fetchone()
        return self._registro(linha)

    def recusar_regresso(self, proposta_id: str, operador_id: str, motivo: str) -> str:
        pid, operador = como_uuid(proposta_id), como_uuid(operador_id)
        with self._banco.transacao() as con:
            if not self._tem_regresso(con):
                return "indisponivel"
            if pid is None:
                return "nao_encontrada"
            if operador is None:
                return "analista_invalido"
            return str(
                con.execute(
                    "select public.compensacao_recusar_regresso(%s, %s, %s) as r",
                    (pid, operador, motivo),
                ).fetchone()["r"]
            )

    def proposta(self, proposta_id: str) -> Proposta | None:
        pid = como_uuid(proposta_id)
        with self._banco.transacao() as con:
            if pid is None or not self._tem_regresso(con):
                return None
            linha = con.execute(_SELECT_PROPOSTA + " where id = %s", (pid,)).fetchone()
        return _proposta(linha) if linha else None

    def propostas(
        self, status: str | None = None, limite: int = 50, deslocamento: int = 0
    ) -> tuple[list[Proposta], int]:
        onde, valores = ("", []) if status is None else (" where status = %s", [status])
        with self._banco.transacao() as con:
            if not self._tem_regresso(con):
                return [], 0
            total = con.execute(
                "select count(*) as n from public.compensacao_propostas_regresso" + onde,  # noqa: S608
                valores,
            ).fetchone()["n"]
            linhas = con.execute(
                _SELECT_PROPOSTA + onde + " order by proposta_em desc, id limit %s offset %s",
                [*valores, limite, deslocamento],
            ).fetchall()
        return [_proposta(x) for x in linhas], int(total)

    def aplicar(self, pedido_id: str, chave: str) -> Aplicacao:
        with self._banco.transacao() as con:
            if not self._tem(con):
                return Aplicacao("indisponivel")
            contrato = self._contrato(con, pedido_id)
            if contrato is None:
                return Aplicacao("contrato_nao_encontrado")
            x = con.execute(
                "select resultado, aplicado_centavos, liberado_restante_centavos "
                "from public.compensacao_aplicar(%s, %s)",
                (contrato, chave),
            ).fetchone()
        return Aplicacao(
            str(x["resultado"]),
            int(x["aplicado_centavos"] or 0),
            int(x["liberado_restante_centavos"] or 0),
        )

    def cancelar(self, divida_id: str, analista_id: str, motivo: str) -> Cancelamento:
        did, analista = como_uuid(divida_id), como_uuid(analista_id)
        with self._banco.transacao() as con:
            if not self._tem(con):
                return Cancelamento("indisponivel")
            if did is None:
                return Cancelamento("nao_encontrada")
            if analista is None:
                return Cancelamento("analista_invalido")
            x = con.execute(
                "select resultado, devolvido_centavos from public.compensacao_cancelar(%s, %s, %s)",
                (did, analista, motivo),
            ).fetchone()
        return Cancelamento(str(x["resultado"]), int(x["devolvido_centavos"] or 0))

    def obter(self, divida_id: str) -> Divida | None:
        did = como_uuid(divida_id)
        with self._banco.transacao() as con:
            if did is None or not self._tem(con):
                return None
            linha = con.execute(_SELECT + " where d.id = %s", (did,)).fetchone()
        return _divida(linha) if linha else None

    def listar(
        self,
        profissional_id: str | None = None,
        pedido_id: str | None = None,
        status: str | None = None,
        limite: int = 50,
        deslocamento: int = 0,
    ) -> tuple[list[Divida], int]:
        condicoes, valores = ["true"], []
        for coluna, valor in (("profissional_id", profissional_id), ("pedido_id", pedido_id)):
            if valor is not None:
                if como_uuid(valor) is None:
                    return [], 0
                condicoes.append(f"d.{coluna} = %s")
                valores.append(como_uuid(valor))
        if status is not None:
            condicoes.append("d.status = %s")
            valores.append(status)
        onde = " where " + " and ".join(condicoes)
        with self._banco.transacao() as con:
            if not self._tem(con):
                return [], 0
            total = con.execute(
                "select count(*) as n from public.compensacoes_dividas d" + onde,  # noqa: S608
                valores,
            ).fetchone()["n"]
            linhas = con.execute(
                _SELECT + onde + " order by d.criada_em desc, d.id limit %s offset %s",
                [*valores, limite, deslocamento],
            ).fetchall()
        return [_divida(x) for x in linhas], int(total)
