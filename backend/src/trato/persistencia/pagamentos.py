"""Pagamento no Postgres: cobranças, aditivos, ordens de estorno, termos e a config do fluxo.

O serviço de pagamento (`pagamentos/orquestrador.py`) fala em PEDIDO e no id do PROVEDOR; o banco
fala em CONTRATO e uuid próprio. Aqui a ponte:

  * `CobrancaLocal.id` = `pagamentos.stripe_payment_intent_id` (o uuid da linha fica interno);
  * o pedido acha o contrato por `contratos.pedido_id`; o pagador é o cliente do contrato;
  * a cobrança principal é o tipo `saldo` (valor total do contrato, que fica retido); a de aditivo
    é o tipo `aditivo`. A chave de idempotência da linha é `cob/<id do provedor>`;
  * estados: aguardando=pendente, paga=confirmado (ou reembolsado_parcial se algo já foi
    devolvido), falhou=falhou, cancelada=expirado, devolvida=reembolsado;
  * aditivo `pago` não existe no banco: é um aditivo `aprovado` cujo pagamento foi confirmado.

Dinheiro sempre em centavos inteiros. Os gatilhos do banco continuam valendo (imutáveis, pagador).
Usa a coluna `pagamentos.instrucao` (migration 20261031000000, ainda não aplicada no Supabase real).
"""

from __future__ import annotations

import uuid
from collections.abc import Sequence
from typing import Any

import psycopg

from trato.pagamentos.custo import MeioPagamento
from trato.pagamentos.modelos import (
    Aditivo,
    CobrancaLocal,
    ConfigPagamento,
    EstadoAditivo,
    EstadoCobranca,
    OrdemEstorno,
    TermosContrato,
)
from trato.pagamentos.parcelamento import ConfigParcelamento
from trato.pagamentos.taxa import ConfigTaxa
from trato.persistencia.comum import como_uuid, exigir_uuid
from trato.persistencia.conexao import Banco
from trato.persistencia.config import parametros_globais, versao_vigente
from trato.persistencia.erros import ConfigNaoPublicada, NaoEncontrado

_MEIO_PARA_BANCO = {MeioPagamento.PIX: "pix", MeioPagamento.CARTAO: "cartao_credito"}
_STATUS_PARA_BANCO = {
    EstadoCobranca.AGUARDANDO: "pendente",
    EstadoCobranca.PAGA: "confirmado",
    EstadoCobranca.FALHOU: "falhou",
    EstadoCobranca.CANCELADA: "expirado",
    EstadoCobranca.DEVOLVIDA: "reembolsado",
}
_STATUS_DO_BANCO = {
    "pendente": EstadoCobranca.AGUARDANDO,
    "confirmado": EstadoCobranca.PAGA,
    "reembolsado_parcial": EstadoCobranca.PAGA,
    "falhou": EstadoCobranca.FALHOU,
    "expirado": EstadoCobranca.CANCELADA,
    "reembolsado": EstadoCobranca.DEVOLVIDA,
    "contestado": EstadoCobranca.PAGA,
}


def _hex(valor: object) -> str:
    return uuid.UUID(str(valor)).hex


def _contrato_do_pedido(con: psycopg.Connection[Any], pedido_id: str) -> dict[str, Any]:
    pedido = como_uuid(pedido_id)
    linha = (
        con.execute(
            "select id, cliente_id, profissional_id from public.contratos where pedido_id = %s",
            (pedido,),
        ).fetchone()
        if pedido
        else None
    )
    if linha is None:
        raise NaoEncontrado("Este pedido ainda não tem contrato.")
    return linha


_SELECT_COBRANCA = (
    "select p.stripe_payment_intent_id, c.pedido_id, p.aditivo_id, p.valor_centavos, p.meio, "
    "p.status, p.criado_em, p.instrucao, p.confirmado_em, p.estornado_centavos "
    "from public.pagamentos p join public.contratos c on c.id = p.contrato_id "
)


def _cobranca(linha: dict[str, Any]) -> CobrancaLocal:
    devolvida = linha["status"] == "reembolsado"
    return CobrancaLocal(
        id=linha["stripe_payment_intent_id"],
        pedido_id=_hex(linha["pedido_id"]),
        valor_centavos=int(linha["valor_centavos"]),
        meio=MeioPagamento.PIX if linha["meio"] == "pix" else MeioPagamento.CARTAO,
        status=_STATUS_DO_BANCO[linha["status"]],
        criada_em=linha["criado_em"],
        aditivo_id=_hex(linha["aditivo_id"]) if linha["aditivo_id"] else None,
        instrucao=linha["instrucao"],
        pago_em=None if devolvida else linha["confirmado_em"],
        estornado_centavos=int(linha["estornado_centavos"]),
    )


class CobrancasPostgres:
    def __init__(self, banco: Banco) -> None:
        self._banco = banco

    def obter(self, cobranca_id: str) -> CobrancaLocal | None:
        if not cobranca_id:
            return None
        with self._banco.transacao() as con:
            linha = con.execute(
                _SELECT_COBRANCA + "where p.stripe_payment_intent_id = %s", (cobranca_id,)
            ).fetchone()
        return _cobranca(linha) if linha else None

    def do_pedido(self, pedido_id: str) -> Sequence[CobrancaLocal]:
        pedido = como_uuid(pedido_id)
        if pedido is None:
            return ()
        with self._banco.transacao() as con:
            linhas = con.execute(
                _SELECT_COBRANCA + "where c.pedido_id = %s and p.stripe_payment_intent_id "
                "is not null order by p.criado_em, p.id",
                (pedido,),
            ).fetchall()
        return [_cobranca(linha) for linha in linhas]

    def salvar(self, cobranca: CobrancaLocal) -> None:
        """Cria a cobrança ou atualiza só o que muda depois (estado, confirmação, devolução)."""
        status = _STATUS_PARA_BANCO[cobranca.status]
        if cobranca.status is EstadoCobranca.PAGA and cobranca.estornado_centavos > 0:
            status = "reembolsado_parcial"
        confirmado_em = None
        if status not in ("pendente", "falhou", "expirado"):
            confirmado_em = cobranca.pago_em or cobranca.criada_em
        with self._banco.transacao() as con:
            existente = con.execute(
                "select id from public.pagamentos where stripe_payment_intent_id = %s for update",
                (cobranca.id,),
            ).fetchone()
            if existente is not None:
                con.execute(
                    "update public.pagamentos set status = %s, estornado_centavos = %s, "
                    "confirmado_em = coalesce(confirmado_em, %s) where id = %s",
                    (status, cobranca.estornado_centavos, confirmado_em, existente["id"]),
                )
                return
            contrato = _contrato_do_pedido(con, cobranca.pedido_id)
            aditivo = como_uuid(cobranca.aditivo_id) if cobranca.aditivo_id else None
            con.execute(
                "insert into public.pagamentos (contrato_id, pagador_id, tipo, aditivo_id, meio, "
                "valor_centavos, status, stripe_payment_intent_id, chave_idempotencia, "
                "confirmado_em, estornado_centavos, instrucao, criado_em) "
                "values (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s)",
                (
                    contrato["id"],
                    contrato["cliente_id"],
                    "aditivo" if aditivo else "saldo",
                    aditivo,
                    _MEIO_PARA_BANCO[cobranca.meio],
                    cobranca.valor_centavos,
                    status,
                    cobranca.id,
                    f"cob/{cobranca.id}",
                    confirmado_em,
                    cobranca.estornado_centavos,
                    cobranca.instrucao,
                    cobranca.criada_em,
                ),
            )


class AditivosPostgres:
    def __init__(self, banco: Banco) -> None:
        self._banco = banco

    _SELECT = (
        "select a.id, c.pedido_id, a.motivo, a.valor_centavos, a.status, a.criado_em, "
        "a.decidido_em, exists (select 1 from public.pagamentos p where p.aditivo_id = a.id "
        "and p.status in ('confirmado', 'reembolsado_parcial', 'reembolsado')) as pago "
        "from public.aditivos a join public.contratos c on c.id = a.contrato_id "
    )

    @staticmethod
    def _aditivo(linha: dict[str, Any]) -> Aditivo:
        if linha["pago"]:
            estado = EstadoAditivo.PAGO
        else:
            estado = {
                "pendente": EstadoAditivo.PROPOSTO,
                "aprovado": EstadoAditivo.APROVADO,
            }.get(linha["status"], EstadoAditivo.RECUSADO)
        aprovado = estado in (EstadoAditivo.APROVADO, EstadoAditivo.PAGO)
        return Aditivo(
            _hex(linha["id"]),
            _hex(linha["pedido_id"]),
            linha["motivo"],
            int(linha["valor_centavos"]),
            estado,
            linha["criado_em"],
            linha["decidido_em"] if aprovado else None,
        )

    def obter(self, aditivo_id: str) -> Aditivo | None:
        achado = como_uuid(aditivo_id)
        if achado is None:
            return None
        with self._banco.transacao() as con:
            linha = con.execute(self._SELECT + "where a.id = %s", (achado,)).fetchone()
        return self._aditivo(linha) if linha else None

    def do_pedido(self, pedido_id: str) -> Sequence[Aditivo]:
        pedido = como_uuid(pedido_id)
        if pedido is None:
            return ()
        with self._banco.transacao() as con:
            linhas = con.execute(
                self._SELECT + "where c.pedido_id = %s order by a.criado_em, a.id", (pedido,)
            ).fetchall()
        return [self._aditivo(linha) for linha in linhas]

    def salvar(self, aditivo: Aditivo) -> None:
        """Cria o aditivo proposto; aprova ou recusa uma vez. O banco proíbe mexer em decidido,
        então repetir o mesmo estado (ou `pago`, que já é `aprovado` lá) não escreve nada."""
        alvo = {
            EstadoAditivo.PROPOSTO: "pendente",
            EstadoAditivo.APROVADO: "aprovado",
            EstadoAditivo.PAGO: "aprovado",
            EstadoAditivo.RECUSADO: "recusado",
        }[aditivo.estado]
        with self._banco.transacao() as con:
            contrato = _contrato_do_pedido(con, aditivo.pedido_id)
            id_ = exigir_uuid(aditivo.id, "aditivo")
            atual = con.execute(
                "select status from public.aditivos where id = %s for update", (id_,)
            ).fetchone()
            if atual is None:
                con.execute(
                    "insert into public.aditivos (id, contrato_id, criado_por, motivo, "
                    "valor_centavos, criado_em) values (%s, %s, %s, %s, %s, %s)",
                    (
                        id_,
                        contrato["id"],
                        contrato["profissional_id"],
                        aditivo.descricao,
                        aditivo.valor_centavos,
                        aditivo.criado_em,
                    ),
                )
                atual = {"status": "pendente"}
            if alvo == atual["status"] or alvo == "pendente":
                return
            con.execute(
                "update public.aditivos set status = %s, decidido_por = %s, "
                "decidido_em = coalesce(%s, now()) where id = %s",
                (alvo, contrato["cliente_id"], aditivo.aprovado_em, id_),
            )


class OrdensEstornoPostgres:
    def __init__(self, banco: Banco) -> None:
        self._banco = banco

    _SELECT = (
        "select o.chave_idempotencia, c.pedido_id, p.stripe_payment_intent_id, o.valor_centavos, "
        "o.criada_em, o.estado, o.provedor_estorno_id from public.ordens_estorno o "
        "join public.pagamentos p on p.id = o.pagamento_id "
        "join public.contratos c on c.id = o.contrato_id "
    )

    @staticmethod
    def _ordem(linha: dict[str, Any]) -> OrdemEstorno:
        return OrdemEstorno(
            linha["chave_idempotencia"],
            _hex(linha["pedido_id"]),
            linha["stripe_payment_intent_id"],
            int(linha["valor_centavos"]),
            linha["criada_em"],
            linha["estado"],
            linha["provedor_estorno_id"],
        )

    def salvar(self, ordem: OrdemEstorno) -> None:
        with self._banco.transacao() as con:
            existente = con.execute(
                "select id from public.ordens_estorno where chave_idempotencia = %s for update",
                (ordem.chave,),
            ).fetchone()
            if existente is not None:
                con.execute(
                    "update public.ordens_estorno set estado = %s, provedor_estorno_id = %s, "
                    "enviada_em = case when %s = 'enviada' then coalesce(enviada_em, now()) end "
                    "where id = %s",
                    (ordem.estado, ordem.provedor_estorno_id, ordem.estado, existente["id"]),
                )
                return
            pagamento = con.execute(
                "select id, contrato_id from public.pagamentos where stripe_payment_intent_id = %s",
                (ordem.cobranca_id,),
            ).fetchone()
            if pagamento is None:
                raise NaoEncontrado("Cobrança da ordem de estorno não encontrada.")
            con.execute(
                "insert into public.ordens_estorno (contrato_id, pagamento_id, valor_centavos, "
                "estado, chave_idempotencia, provedor_estorno_id, criada_em, enviada_em) "
                "values (%s, %s, %s, %s, %s, %s, %s, case when %s = 'enviada' then now() end)",
                (
                    pagamento["contrato_id"],
                    pagamento["id"],
                    ordem.valor_centavos,
                    ordem.estado,
                    ordem.chave,
                    ordem.provedor_estorno_id,
                    ordem.criada_em,
                    ordem.estado,
                ),
            )

    def pendentes(self, pedido_id: str | None = None) -> Sequence[OrdemEstorno]:
        filtro, args = "", ()
        if pedido_id is not None:
            achado = como_uuid(pedido_id)
            if achado is None:
                return ()
            filtro, args = "and c.pedido_id = %s ", (achado,)
        with self._banco.transacao() as con:
            linhas = con.execute(
                self._SELECT + "where o.estado = 'pendente' " + filtro + "order by o.criada_em",
                args,
            ).fetchall()
        return [self._ordem(linha) for linha in linhas]

    def do_pedido(self, pedido_id: str) -> Sequence[OrdemEstorno]:
        achado = como_uuid(pedido_id)
        if achado is None:
            return ()
        with self._banco.transacao() as con:
            linhas = con.execute(
                self._SELECT + "where c.pedido_id = %s order by o.criada_em", (achado,)
            ).fetchall()
        return [self._ordem(linha) for linha in linhas]


class TermosPostgres:
    """Os termos do contrato JÁ moram no contrato (`taxa_bps_aplicada` e `regras_aplicadas`,
    gravados no aceite com a configuração do momento). Por isso `salvar` não escreve nada e `obter`
    devolve None: o serviço cai na taxa congelada do contrato (`taxa_congelada`), mesma fonte."""

    def obter(self, pedido_id: str) -> TermosContrato | None:
        return None

    def salvar(self, termos: TermosContrato) -> None:
        return None


class ConfigPagamentoPostgres:
    """`ConfigPagamento` lida da versão VIGENTE da configuração, a cada chamada.

    A taxa do ACEITE já fica congelada no contrato; esta só vale como referência (menor faixa e
    o mínimo). `alcada_disputa_centavos` vem do parâmetro de mesmo nome; sem ele, 0 (toda decisão
    de disputa pede segunda pessoa: o lado seguro)."""

    def __init__(self, banco: Banco) -> None:
        self._banco = banco

    def __call__(self) -> ConfigPagamento:
        with self._banco.transacao() as con:
            versao = versao_vigente(con)
            parametros = parametros_globais(con, versao)
            faixa = con.execute(
                "select taxa_bps from public.config_faixas_taxa where versao_id = %s "
                "and escopo_tipo = 'global' order by de_centavos limit 1",
                (versao,),
            ).fetchone()
        if faixa is None:
            raise ConfigNaoPublicada("As faixas de taxa (P2) ainda não foram publicadas.")
        taxa = ConfigTaxa(int(faixa["taxa_bps"]), parametros.get("taxa_minima_centavos", 0))
        # Custo do parcelado repassado ao cliente: parâmetros opcionais
        # `custo_parcelamento_<N>x_bps` (N de 2 a 12), do provedor. Nenhum cadastrado = parcelado
        # desligado (João, 31/10/2026).
        custos = {
            n: parametros[chave]
            for n in range(2, 13)
            if (chave := f"custo_parcelamento_{n}x_bps") in parametros
        }
        return ConfigPagamento(
            taxa,
            parametros.get("alcada_disputa_centavos", 0),
            parcelamento=ConfigParcelamento(custos),
            cancelamento_devolve_taxa=bool(parametros.get("cancelamento_devolve_taxa", 0)),
        )


__all__ = [
    "AditivosPostgres",
    "CobrancasPostgres",
    "ConfigPagamentoPostgres",
    "OrdensEstornoPostgres",
    "TermosPostgres",
]
