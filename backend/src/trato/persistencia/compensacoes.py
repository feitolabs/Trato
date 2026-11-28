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
    suspensa: bool = False  # aberta, com a decisão de origem revista: não é descontada
    # Com reduções (191500), `valor_centavos` é o valor EFETIVO (o que continua devido).
    reduzido_centavos: int = 0
    devolvido_reducao_centavos: int = 0  # voltou ao profissional por redução
    # Revisão pendente (decisão posterior mais baixa que ainda não virou redução/cancelamento).
    revisao_contestacao_id: str | None = None
    revisao: str | None = None  # reducao | reversao | analisar
    reducao_maxima_centavos: int | None = None  # None: a redução não é possível agora


@dataclass(frozen=True)
class Registro:
    # ok | ja_registrada | conflito | acima_do_devido | origem_nao_decidida |
    # decisao_substituida | contrato_nao_encontrado | analista_invalido | indisponivel
    resultado: str
    divida_id: str | None = None
    maximo_centavos: int = 0


@dataclass(frozen=True)
class Reducao:
    # ok | ja_reduzida | conflito | analista_invalido | nao_encontrada | ja_cancelada |
    # contestacao_invalida | decisao_substituida | valor_invalido | indisponivel
    resultado: str
    devolvido_centavos: int = 0


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

    def reduzir(
        self, divida_id: str, contestacao_id: str, novo_valor: int, motivo: str, operador_id: str
    ) -> Reducao:
        """Reduz a dívida sem tocar no cliente (191500). Idempotente por dívida e contestação."""

    def obter(self, divida_id: str) -> Divida | None: ...

    def listar(
        self,
        profissional_id: str | None = None,
        pedido_id: str | None = None,
        status: str | None = None,
        limite: int = 50,
        deslocamento: int = 0,
        revisao_pendente: bool = False,
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

    def reduzir(self, *_: Any) -> Reducao:
        return Reducao("indisponivel")

    def obter(self, divida_id: str) -> Divida | None:
        return None

    def listar(self, *_: Any, **__: Any) -> tuple[list[Divida], int]:
        return [], 0


def _montar_select(com_reducoes: bool, com_estorno_direto: bool) -> str:
    """A leitura das dívidas. `suspensa` é a regra de `compensacao_origem_revista` (sem EXECUTE
    para o backend): com a 191500, a base é a contestação da redução mais recente e as já usadas
    em redução não suspendem."""
    reduzido = devolvido = "0"
    base_id, base_em = "o.id", "o.decidida_em"
    base_decisao, base_valor = "o.nova_decisao", "o.novo_valor_reembolso_centavos"
    juncao = usada = ""
    if com_reducoes:
        reducoes = "from public.compensacoes_reducoes r where r.divida_id = d.id"
        reduzido = f"coalesce((select sum(r.reducao_centavos) {reducoes}), 0)"
        devolvido = f"coalesce((select sum(r.devolvido_centavos) {reducoes}), 0)"
        juncao = (
            "left join lateral (select k.id, k.decidida_em, k.nova_decisao, "
            "k.novo_valor_reembolso_centavos from public.compensacoes_reducoes r "
            "join public.disputa_contestacoes k on k.id = r.contestacao_id "
            "where r.divida_id = d.id order by k.decidida_em desc, r.criada_em desc limit 1) "
            "red on true "
        )
        base_id, base_em = "coalesce(red.id, o.id)", "coalesce(red.decidida_em, o.decidida_em)"
        base_decisao = "coalesce(red.nova_decisao, o.nova_decisao)"
        base_valor = (
            "case when red.id is not null then red.novo_valor_reembolso_centavos "
            "else o.novo_valor_reembolso_centavos end"
        )
        usada = (
            " and not exists (select 1 from public.compensacoes_reducoes r "
            "where r.divida_id = d.id and r.contestacao_id = x.id)"
        )

    def teto(linha: str) -> str:
        return (
            f"(case {linha}.nova_decisao when 'reembolso_total' then "
            f"s.valor_congelado_centavos when 'reembolso_parcial' then "
            f"coalesce({linha}.novo_valor_reembolso_centavos, 0) else 0 end)::bigint"
        )

    base = (
        "from public.disputas s left join public.disputa_contestacoes o "
        f"on d.origem_tipo = 'disputa_contestacao' and o.id = d.origem_id {juncao}"
    )
    depois_da_base = (
        f"x.id is distinct from {base_id} and ({base_id} is null or x.decidida_em >= {base_em})"
    )
    abaixo_da_base = (
        f"{teto('x')} < coalesce(case coalesce({base_decisao}, s.decisao) "
        "when 'reembolso_total' then s.valor_congelado_centavos "
        f"when 'reembolso_parcial' then case when {base_id} is null "
        f"then s.valor_reembolso_centavos else {base_valor} end else 0 end, 0)"
    )
    # `suspensa`: a regra de `compensacao_origem_revista` (QUALQUER decisão posterior mais baixa).
    revista = (
        f"select exists (select 1 {base}"  # noqa: S608 - só trechos fixos
        "join public.disputa_contestacoes x on x.disputa_id = s.id "
        f"and x.status in ('alterada', 'revertida') where s.id = d.disputa_id "
        f"and {depois_da_base}{usada} and {abaixo_da_base}) as sim"
    )
    # O que oferecer: só a decisão tomada por ÚLTIMO e com efeito financeiro, como a redução do
    # banco aceita (as outras ela recusa como substituídas ou inválidas).
    revisao = (
        f"select x.id, x.status, x.aprovada_por is not null as aprovada, {teto('x')} as teto "  # noqa: S608
        f"{base}join lateral (select y.* from public.disputa_contestacoes y "
        "where y.disputa_id = s.id and y.status in ('alterada', 'revertida') "
        "order by y.decidida_em desc, y.id desc limit 1) x on true "
        f"where s.id = d.disputa_id and d.status <> 'cancelada' and {depois_da_base} "
        f"and x.efeito_financeiro <> 'nenhum'{usada} and {abaixo_da_base}"
    )
    direto = (
        "coalesce(public.compensacao_estornado_ao_cliente(d.disputa_id), 0)"
        if com_estorno_direto
        else "0"
    )
    # O que as OUTRAS dívidas vivas da mesma disputa já ocupam do teto.
    outras = (
        "select coalesce(sum(z.valor_centavos), 0) from public.compensacoes_dividas z "
        "where z.disputa_id = d.disputa_id and z.id <> d.id and z.status <> 'cancelada'"
    )
    if com_reducoes:
        outras = (
            "select coalesce(sum(z.valor_centavos - coalesce((select sum(r.reducao_centavos) "
            "from public.compensacoes_reducoes r where r.divida_id = z.id), 0)), 0) "
            "from public.compensacoes_dividas z where z.disputa_id = d.disputa_id "
            "and z.id <> d.id and z.status <> 'cancelada'"
        )
    return (
        "select d.id, d.contrato_id, d.pedido_id, d.profissional_id, d.origem_tipo, "  # noqa: S608
        "d.valor_centavos, d.motivo, d.status, d.criada_em, d.avisado_em, d.cancelada_em, "
        "d.motivo_cancelamento, coalesce((select sum(a.valor_centavos) from "
        "public.compensacoes_aplicadas a where a.divida_id = d.id and not exists "
        "(select 1 from public.lancamentos e where e.estorna_id = a.lancamento_id)), 0)::bigint "
        f"as compensado, ({reduzido})::bigint as reduzido, ({devolvido})::bigint as devolvido, "
        "(d.status = 'aberta' and sv.sim) as suspensa, rv.id as revisao_id, "
        "rv.status as revisao_status, rv.aprovada as revisao_aprovada, "
        f"rv.teto as revisao_teto, ({outras})::bigint as outras, "
        f"({direto})::bigint as estornado_direto, "
        f"{'true' if com_reducoes else 'false'} as reducao_disponivel "
        f"from public.compensacoes_dividas d left join lateral ({revisao}) rv on true "
        f"left join lateral ({revista}) sv on true"
    )


def _select(con: Any) -> str:
    tem = con.execute(
        "select to_regclass('public.compensacoes_reducoes') is not null as reducoes, "
        "to_regprocedure('public.compensacao_estornado_ao_cliente(uuid)') is not null as direto"
    ).fetchone()
    return _montar_select(bool(tem["reducoes"]), bool(tem["direto"]))


def _revisao(x: dict[str, Any]) -> tuple[str | None, str | None, int | None]:
    """(contestação, tipo, maior novo valor aceito pela redução)."""
    if x["revisao_id"] is None:
        return None, None, None
    efetivo = int(x["valor_centavos"]) - int(x["reduzido"])
    teto = int(x["revisao_teto"])
    # Quanto a nova decisão ainda deixa para esta dívida: o que já voltou ao cliente por
    # estorno direto também ocupa o teto.
    cabe = teto - int(x["outras"]) - int(x["estornado_direto"])
    if x["revisao_status"] == "revertida" or teto <= 0 or cabe <= 0:
        return str(x["revisao_id"]), "reversao", None
    if cabe >= efetivo:  # a decisão baixou, mas esta dívida ainda cabe nela
        return str(x["revisao_id"]), "analisar", None
    maximo = min(cabe, efetivo - 1)
    pode = x["reducao_disponivel"] and x["revisao_aprovada"] and maximo > 0
    return str(x["revisao_id"]), "reducao", maximo if pode else None


def _divida(x: dict[str, Any]) -> Divida:
    contestacao, tipo, maximo = _revisao(x)
    return Divida(
        id=str(x["id"]),
        contrato_id=str(x["contrato_id"]),
        pedido_id=str(x["pedido_id"]),
        profissional_id=str(x["profissional_id"]),
        origem_tipo=x["origem_tipo"],
        valor_centavos=int(x["valor_centavos"]) - int(x["reduzido"]),
        reduzido_centavos=int(x["reduzido"]),
        devolvido_reducao_centavos=int(x["devolvido"]),
        compensado_centavos=int(x["compensado"]),
        motivo=x["motivo"],
        status=x["status"],
        criada_em=x["criada_em"],
        avisado_em=x["avisado_em"],
        cancelada_em=x["cancelada_em"],
        motivo_cancelamento=x["motivo_cancelamento"],
        suspensa=bool(x["suspensa"]),
        revisao_contestacao_id=contestacao,
        revisao=tipo,
        reducao_maxima_centavos=maximo,
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

    def reduzir(
        self, divida_id: str, contestacao_id: str, novo_valor: int, motivo: str, operador_id: str
    ) -> Reducao:
        """A redução e a marca `executado` da contestação gravam juntas ou nada grava."""
        divida, contestacao = como_uuid(divida_id), como_uuid(contestacao_id)
        operador = como_uuid(operador_id)
        with self._banco.transacao() as con:
            if not con.execute(
                "select to_regprocedure('public.compensacao_reduzir("
                "uuid,uuid,bigint,text,uuid)') is not null as tem"
            ).fetchone()["tem"]:
                return Reducao("indisponivel")
            if operador is None:
                return Reducao("analista_invalido")
            if divida is None:
                return Reducao("nao_encontrada")
            if contestacao is None:
                return Reducao("contestacao_invalida")
            linha = con.execute(
                "select resultado, devolvido_ao_profissional_centavos as devolvido "
                "from public.compensacao_reduzir(%s, %s, %s, %s, %s)",
                (divida, contestacao, novo_valor, motivo, operador),
            ).fetchone()
            if linha["resultado"] == "ok":
                # O efeito financeiro desta contestação é a própria redução.
                con.execute(
                    "update public.disputa_contestacoes set efeito_financeiro = 'executado' "
                    "where id = %s and efeito_financeiro = 'pendente_financeiro'",
                    (contestacao,),
                )
        return Reducao(str(linha["resultado"]), int(linha["devolvido"] or 0))

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
            linha = con.execute(_select(con) + " where d.id = %s", (did,)).fetchone()
        return _divida(linha) if linha else None

    def listar(
        self,
        profissional_id: str | None = None,
        pedido_id: str | None = None,
        status: str | None = None,
        limite: int = 50,
        deslocamento: int = 0,
        revisao_pendente: bool = False,
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
        if revisao_pendente:
            # Inclui a suspensa sem oferta (ex.: decisão posterior subiu de novo): a equipe
            # precisa achá-la.
            condicoes.append("(rv.id is not null or (d.status = 'aberta' and sv.sim))")
        onde = " where " + " and ".join(condicoes)
        with self._banco.transacao() as con:
            if not self._tem(con):
                return [], 0
            consulta = _select(con) + onde
            total = con.execute(
                f"select count(*) as n from ({consulta}) t",  # noqa: S608
                valores,
            ).fetchone()["n"]
            linhas = con.execute(
                consulta + " order by d.criada_em desc, d.id limit %s offset %s",
                [*valores, limite, deslocamento],
            ).fetchall()
        return [_divida(x) for x in linhas], int(total)
