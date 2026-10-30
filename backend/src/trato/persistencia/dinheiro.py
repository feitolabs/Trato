"""Repositórios Postgres do resto do dinheiro: eventos de webhook, disputas, garantias e
retrabalhos, avaliações e repasses (tabelas da F3.5 e F3.6).

Todos usam `Banco.transacao()`, que é reentrante: dentro da transação de uma operação financeira
(`Contexto.transacao`) eles entram na MESMA transação do ledger e do pedido.
"""

from __future__ import annotations

from collections.abc import Sequence
from datetime import datetime
from typing import Any

import psycopg
from psycopg.types.json import Jsonb

from trato.api.repositorios import EventoWebhook, Repasse
from trato.api.repositorios_app import Avaliacao
from trato.disputas import (
    Decisao,
    Disputa,
    Estado,
    Motivo,
    Prazos,
    Resultado,
    dividir_valor,
)
from trato.garantias import EstadoRetrabalho, Garantia, Retrabalho
from trato.persistencia.comum import como_uuid, exigir_uuid, para_json
from trato.persistencia.conexao import Banco
from trato.persistencia.erros import ConflitoDeEstado, RegraDoBanco


def _contrato(con: psycopg.Connection[Any], pedido_id: str, travar: bool = False):
    pid = como_uuid(pedido_id)
    if pid is None:
        return None
    consulta = "select id, cliente_id, profissional_id from public.contratos where pedido_id = %s"
    if travar:
        consulta += " for update"
    return con.execute(consulta, (pid,)).fetchone()  # noqa: S608 - só texto fixo do código


def _exigir_contrato(con: psycopg.Connection[Any], pedido_id: str, travar: bool = False):
    linha = _contrato(con, pedido_id, travar)
    if linha is None:
        raise RegraDoBanco("Este pedido ainda não tem contrato.")
    return linha


# --- Eventos do webhook -------------------------------------------------------------------------


class EventosWebhookPostgres:
    """Idempotência (`unique(provedor, evento_id)`) + cópia do evento recebido.

    `iniciar` trava a chave até o fim da transação (`pg_advisory_xact_lock`): dois workers com o
    mesmo evento nunca processam juntos, e o segundo, ao destravar, vê o evento já processado.
    Se o processamento falha, a transação inteira desfaz (inclusive o registro do evento): o
    provedor reenvia e o evento roda de novo.
    """

    def __init__(self, banco: Banco) -> None:
        self._banco = banco

    @staticmethod
    def _separar(chave: str) -> tuple[str, str]:
        provedor, _, evento_id = chave.partition(":")
        return provedor, evento_id

    def iniciar(self, chave: str) -> bool:
        if not chave:
            raise ValueError("chave de idempotência vazia")
        provedor, evento_id = self._separar(chave)
        with self._banco.transacao() as con:
            con.execute("select pg_advisory_xact_lock(hashtextextended(%s, 0))", (chave,))
            linha = con.execute(
                "select processado_em from public.eventos_webhook "
                "where provedor = %s and evento_id = %s",
                (provedor, evento_id),
            ).fetchone()
        return not (linha is not None and linha["processado_em"] is not None)

    def concluir(self, chave: str) -> None:
        provedor, evento_id = self._separar(chave)
        with self._banco.transacao() as con:
            con.execute(
                "update public.eventos_webhook set processado_em = now() "
                "where provedor = %s and evento_id = %s and processado_em is null",
                (provedor, evento_id),
            )

    def liberar(self, chave: str) -> None:
        """Nada a desfazer: a transação que falhou já foi desfeita junto com o registro."""

    def registrar(self, evento: EventoWebhook) -> None:
        with self._banco.transacao() as con:
            con.execute(
                "insert into public.eventos_webhook (provedor, evento_id, tipo, assinatura_valida, "
                "payload, recebido_em) values (%s, %s, %s, true, %s, %s) "
                "on conflict (provedor, evento_id) do nothing",
                (
                    evento.provedor,
                    evento.evento_id,
                    evento.tipo,
                    Jsonb(para_json(evento.payload)),
                    evento.recebido_em,
                ),
            )

    def descartar(self, evento: EventoWebhook) -> None:
        """Nada: a transação que falhou já desfez o registro."""

    def marcar_revisao(self, evento: EventoWebhook, motivo: str) -> None:
        """Deixa o evento guardado com o motivo da divergência (o financeiro revisa)."""
        with self._banco.transacao() as con:
            con.execute(
                "update public.eventos_webhook set erro = %s "
                "where provedor = %s and evento_id = %s",
                (f"revisar: {motivo}"[:500], evento.provedor, evento.evento_id),
            )

    def em_revisao(self) -> Sequence[tuple[EventoWebhook, str]]:
        with self._banco.transacao() as con:
            linhas = con.execute(
                "select provedor, evento_id, tipo, payload, recebido_em, erro "
                "from public.eventos_webhook where erro like 'revisar:%' order by recebido_em"
            ).fetchall()
        return tuple(
            (
                EventoWebhook(
                    l["provedor"], l["evento_id"], l["tipo"], l["payload"], l["recebido_em"]
                ),
                l["erro"],
            )
            for l in linhas  # noqa: E741
        )

    def listar(self) -> Sequence[EventoWebhook]:
        with self._banco.transacao() as con:
            linhas = con.execute(
                "select provedor, evento_id, tipo, payload, recebido_em "
                "from public.eventos_webhook where processado_em is not null order by recebido_em"
            ).fetchall()
        return tuple(
            EventoWebhook(l["provedor"], l["evento_id"], l["tipo"], l["payload"], l["recebido_em"])
            for l in linhas  # noqa: E741
        )


# --- Disputas -----------------------------------------------------------------------------------

_MOTIVO_PARA_BANCO = {Motivo.DIFERENTE_DO_COMBINADO: "diferente_combinado"}
_MOTIVO_DO_BANCO = {v: k for k, v in _MOTIVO_PARA_BANCO.items()}
_SELECT_DISPUTA = (
    "select id, motivo, status, valor_congelado_centavos, resposta_ate, decisao_ate, decisao, "
    "valor_reembolso_centavos, decidida_por, aprovada_por, aberta_em, decidida_em "
    "from public.disputas where pedido_id = %s order by aberta_em desc, id limit 1"
)


def _historico(con: psycopg.Connection[Any], pid: str, acao: str, campo: str) -> str | None:
    linha = con.execute(
        "select prova -> 'dados' ->> %s as valor from public.pedido_historico "
        "where pedido_id = %s and prova ->> 'acao' = %s order by id desc limit 1",
        (campo, pid, acao),
    ).fetchone()
    valor = linha["valor"] if linha else None
    return valor if valor and valor.strip() else None


class DisputasPostgres:
    """`disputas` (F3.6). O estado `aguardando_aprovacao` do domínio é `em_analise` com a decisão
    já proposta; o banco só aceita `decidida` com mediador ativo e alçada conferida (gatilho).

    A descrição vem do histórico do pedido (`abrir_disputa`) e a justificativa da decisão do
    histórico (`decidir_disputa`): grave o pedido ANTES da disputa na mesma transação.
    """

    def __init__(self, banco: Banco) -> None:
        self._banco = banco

    def obter(self, pedido_id: str) -> Disputa | None:
        pid = como_uuid(pedido_id)
        if pid is None:
            return None
        with self._banco.transacao() as con:
            linha = con.execute(_SELECT_DISPUTA, (pid,)).fetchone()
            if linha is None:
                return None
            respondeu = con.execute(
                "select min(criado_em) as em from public.disputa_evidencias "
                "where disputa_id = %s and tipo = 'resposta'",
                (linha["id"],),
            ).fetchone()["em"]
        return self._montar(linha, respondeu)

    @staticmethod
    def _montar(linha: dict[str, Any], respondeu_em: datetime | None) -> Disputa:
        status = linha["status"]
        decisao = None
        if linha["decisao"]:
            decisao = Decisao(
                Resultado(linha["decisao"]),
                valor_cliente_centavos=(
                    linha["valor_reembolso_centavos"]
                    if linha["decisao"] == "reembolso_parcial"
                    else None
                ),
            )
        congelado = int(linha["valor_congelado_centavos"])
        if status == "decidida":
            estado = Estado.DECIDIDA
        elif status in ("em_analise", "acordo") and decisao is not None:
            estado = Estado.AGUARDANDO_APROVACAO
        elif status in ("em_analise", "acordo"):
            estado = Estado.EM_ANALISE
        else:
            estado = Estado.ABERTA
        prazos = Prazos(linha["resposta_ate"], linha["decisao_ate"])
        sem_resposta = (
            estado is Estado.EM_ANALISE and respondeu_em is None and linha["decidida_por"] is None
        )
        return Disputa(
            valor_congelado=congelado,
            motivo=_MOTIVO_DO_BANCO.get(linha["motivo"]) or Motivo(linha["motivo"]),
            aberta_em=linha["aberta_em"],
            prazos=prazos,
            estado=estado,
            respondida_em=respondeu_em,
            sem_resposta=sem_resposta,
            decisao=decisao,
            decidido_por=str(linha["decidida_por"]) if linha["decidida_por"] else None,
            decidido_em=linha["decidida_em"],
            aprovado_por=str(linha["aprovada_por"]) if linha["aprovada_por"] else None,
            # O banco não guarda a hora da aprovação à parte: vale a da decisão registrada.
            aprovado_em=linha["decidida_em"] if linha["aprovada_por"] else None,
            divisao=dividir_valor(congelado, decisao)
            if estado is Estado.DECIDIDA and decisao
            else None,
        )

    def salvar(self, pedido_id: str, disputa: Disputa) -> None:
        pid = exigir_uuid(pedido_id, "pedido")
        with self._banco.transacao() as con:
            contrato = _exigir_contrato(con, pid, travar=True)
            atual = con.execute(_SELECT_DISPUTA, (pid,)).fetchone()
            status = {
                Estado.ABERTA: "aberta",
                Estado.EM_ANALISE: "em_analise",
                Estado.AGUARDANDO_APROVACAO: "em_analise",
                Estado.DECIDIDA: "decidida",
            }[disputa.estado]
            decisao = disputa.decisao
            reembolso = None
            if decisao is not None:
                reembolso = dividir_valor(disputa.valor_congelado, decisao).para_cliente
            justificativa = None
            if disputa.estado is Estado.DECIDIDA:
                justificativa = (
                    _historico(con, pid, "decidir_disputa", "justificativa")
                    or "Decisão registrada pela equipe."
                )
            campos = (
                status,
                decisao.resultado.value if decisao else None,
                reembolso if decisao else None,
                disputa.decidido_por,
                disputa.aprovado_por,
                justificativa,
                disputa.decidido_em,
                disputa.prazos.resposta_ate,
                disputa.prazos.decisao_ate,
            )
            mesma = atual is not None and atual["aberta_em"] == disputa.aberta_em
            if mesma:
                con.execute(
                    "update public.disputas set status = %s, decisao = %s, "
                    "valor_reembolso_centavos = %s, decidida_por = %s, aprovada_por = %s, "
                    "justificativa = %s, decidida_em = %s, resposta_ate = %s, decisao_ate = %s "
                    "where id = %s",
                    (*campos, atual["id"]),
                )
                return
            descricao = (
                _historico(con, pid, "abrir_disputa", "descricao") or "Disputa aberta pelo cliente."
            )
            con.execute(
                "insert into public.disputas (contrato_id, pedido_id, aberta_por, motivo, "
                "descricao, valor_congelado_centavos, aberta_em, status, decisao, "
                "valor_reembolso_centavos, decidida_por, aprovada_por, justificativa, "
                "decidida_em, resposta_ate, decisao_ate) "
                "values (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s)",
                (
                    contrato["id"],
                    pid,
                    contrato["cliente_id"],
                    _MOTIVO_PARA_BANCO.get(disputa.motivo, disputa.motivo.value),
                    descricao,
                    disputa.valor_congelado,
                    disputa.aberta_em,
                    *campos,
                ),
            )


# --- Garantias e retrabalhos ---------------------------------------------------------------------


class GarantiasPostgres:
    """`garantias` e `retrabalhos` (F3.6). A garantia é uma por contrato e não muda depois de
    aberta (colunas protegidas); o retrabalho muda de estado."""

    def __init__(self, banco: Banco) -> None:
        self._banco = banco

    def obter_garantia(self, pedido_id: str) -> Garantia | None:
        pid = como_uuid(pedido_id)
        if pid is None:
            return None
        with self._banco.transacao() as con:
            linha = con.execute(
                "select g.inicio_em, g.dias from public.garantias g "
                "join public.contratos c on c.id = g.contrato_id where c.pedido_id = %s",
                (pid,),
            ).fetchone()
        return Garantia(linha["inicio_em"], int(linha["dias"])) if linha else None

    def salvar_garantia(self, pedido_id: str, garantia: Garantia) -> None:
        with self._banco.transacao() as con:
            contrato = _exigir_contrato(con, pedido_id)
            con.execute(
                "insert into public.garantias (contrato_id, inicio_em, fim_em, dias) "
                "values (%s, %s, %s, %s) on conflict (contrato_id) do nothing",
                (contrato["id"], garantia.inicio_em, garantia.fim_em, garantia.dias),
            )

    def retrabalhos(self, pedido_id: str) -> Sequence[Retrabalho]:
        pid = como_uuid(pedido_id)
        if pid is None:
            return ()
        with self._banco.transacao() as con:
            linhas = con.execute(
                "select r.aberto_em, r.atender_ate, r.descricao, r.status, r.atendido_em, "
                "r.outro_profissional_id from public.retrabalhos r "
                "join public.garantias g on g.id = r.garantia_id "
                "join public.contratos c on c.id = g.contrato_id "
                "where c.pedido_id = %s order by r.aberto_em, r.id",
                (pid,),
            ).fetchall()
        return tuple(
            Retrabalho(
                aberto_em=l["aberto_em"],
                atender_ate=l["atender_ate"],
                descricao=l["descricao"],
                estado=EstadoRetrabalho(l["status"]),
                atendido_em=l["atendido_em"],
                outro_profissional_id=(
                    str(l["outro_profissional_id"]) if l["outro_profissional_id"] else None
                ),
            )
            for l in linhas  # noqa: E741
        )

    def salvar_retrabalho(self, pedido_id: str, retrabalho: Retrabalho) -> None:
        """Abre o retrabalho ou, se já existe (mesma hora de abertura), grava a nova situação."""
        with self._banco.transacao() as con:
            contrato = _exigir_contrato(con, pedido_id)
            garantia = con.execute(
                "select id from public.garantias where contrato_id = %s", (contrato["id"],)
            ).fetchone()
            if garantia is None:
                raise RegraDoBanco("O pedido não tem garantia aberta.")
            existente = con.execute(
                "select id from public.retrabalhos where garantia_id = %s and aberto_em = %s",
                (garantia["id"], retrabalho.aberto_em),
            ).fetchone()
            if existente is not None:
                con.execute(
                    "update public.retrabalhos set status = %s, atender_ate = %s, "
                    "atendido_em = %s, outro_profissional_id = %s where id = %s",
                    (
                        retrabalho.estado.value,
                        retrabalho.atender_ate,
                        retrabalho.atendido_em,
                        retrabalho.outro_profissional_id,
                        existente["id"],
                    ),
                )
                return
            con.execute(
                "insert into public.retrabalhos (garantia_id, aberto_por, descricao, status, "
                "atender_ate, atendido_em, outro_profissional_id, aberto_em) "
                "values (%s, %s, %s, %s, %s, %s, %s, %s)",
                (
                    garantia["id"],
                    contrato["cliente_id"],
                    retrabalho.descricao,
                    retrabalho.estado.value,
                    retrabalho.atender_ate,
                    retrabalho.atendido_em,
                    retrabalho.outro_profissional_id,
                    retrabalho.aberto_em,
                ),
            )


# --- Avaliações ----------------------------------------------------------------------------------


class AvaliacoesPostgres:
    """`avaliacoes` (F3.6): uma por contrato e direção; nota e comentário não se editam."""

    def __init__(self, banco: Banco) -> None:
        self._banco = banco

    def obter(self, pedido_id: str, direcao: str) -> Avaliacao | None:
        pid = como_uuid(pedido_id)
        if pid is None:
            return None
        with self._banco.transacao() as con:
            l = con.execute(  # noqa: E741
                "select a.avaliador_id, a.avaliado_id, a.nota_geral, a.comentario, a.etiquetas, "
                "a.criada_em from public.avaliacoes a "
                "join public.contratos c on c.id = a.contrato_id "
                "where c.pedido_id = %s and a.direcao = %s",
                (pid, direcao),
            ).fetchone()
        if l is None:
            return None
        return Avaliacao(
            pedido_id=pid,
            direcao=direcao,
            avaliador_id=str(l["avaliador_id"]),
            avaliado_id=str(l["avaliado_id"]),
            nota_geral=int(l["nota_geral"]),
            comentario=l["comentario"],
            etiquetas=tuple(l["etiquetas"] or ()),
            criada_em=l["criada_em"],
        )

    def salvar(self, avaliacao: Avaliacao) -> None:
        with self._banco.transacao() as con:
            contrato = _exigir_contrato(con, avaliacao.pedido_id)
            con.execute(
                "insert into public.avaliacoes (contrato_id, direcao, avaliador_id, avaliado_id, "
                "nota_geral, comentario, etiquetas, criada_em) "
                "values (%s, %s, %s, %s, %s, %s, %s, %s)",
                (
                    contrato["id"],
                    avaliacao.direcao,
                    exigir_uuid(avaliacao.avaliador_id, "avaliador"),
                    exigir_uuid(avaliacao.avaliado_id, "avaliado"),
                    avaliacao.nota_geral,
                    avaliacao.comentario,
                    list(avaliacao.etiquetas),
                    avaliacao.criada_em,
                ),
            )


# --- Repasses ------------------------------------------------------------------------------------


class RepassesPostgres:
    """`repasses` (F3.5): a ORDEM de liberar ao parceiro (D15). Não é saldo nem saque."""

    def __init__(self, banco: Banco) -> None:
        self._banco = banco

    _COLUNAS = (
        "r.id, c.pedido_id, r.profissional_id, r.etapa_id, r.valor_bruto_centavos, "
        "r.taxa_centavos, r.valor_liquido_centavos, r.gatilho, r.status, r.liberar_em, "
        "r.provedor_transferencia_id, r.chave_idempotencia, r.lancamento_id, r.liberado_em"
    )

    def _de(self, l: dict[str, Any]) -> Repasse:  # noqa: E741
        return Repasse(
            id=str(l["id"]),
            pedido_id=str(l["pedido_id"]),
            profissional_id=str(l["profissional_id"]),
            valor_bruto_centavos=int(l["valor_bruto_centavos"]),
            taxa_centavos=int(l["taxa_centavos"]),
            valor_liquido_centavos=int(l["valor_liquido_centavos"]),
            gatilho=l["gatilho"],
            chave=l["chave_idempotencia"],
            status=l["status"],
            liberar_em=l["liberar_em"],
            provedor_transferencia_id=l["provedor_transferencia_id"],
            lancamento_id=str(l["lancamento_id"]) if l["lancamento_id"] else None,
            liberado_em=l["liberado_em"],
        )

    def criar(self, repasse: Repasse) -> Repasse:
        """Cria a ordem; a mesma chave devolve a que já existe (idempotente)."""
        with self._banco.transacao() as con:
            contrato = _exigir_contrato(con, repasse.pedido_id)
            con.execute(
                "insert into public.repasses (id, contrato_id, profissional_id, "
                "valor_bruto_centavos, taxa_centavos, valor_liquido_centavos, gatilho, status, "
                "liberar_em, chave_idempotencia) values (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s) "
                "on conflict (chave_idempotencia) do nothing",
                (
                    _uuid_ou_novo(repasse.id),
                    contrato["id"],
                    contrato["profissional_id"],
                    repasse.valor_bruto_centavos,
                    repasse.taxa_centavos,
                    repasse.valor_liquido_centavos,
                    repasse.gatilho,
                    repasse.status,
                    repasse.liberar_em,
                    repasse.chave,
                ),
            )
        achado = self.por_chave(repasse.chave)
        assert achado is not None  # noqa: S101 - acabou de ser gravado
        return achado

    def por_chave(self, chave: str) -> Repasse | None:
        return self._um("r.chave_idempotencia = %s", (chave,))

    def obter(self, repasse_id: str) -> Repasse | None:
        rid = como_uuid(repasse_id)
        return self._um("r.id = %s", (rid,)) if rid else None

    def por_transferencia(self, provedor_transferencia_id: str) -> Repasse | None:
        return self._um("r.provedor_transferencia_id = %s", (provedor_transferencia_id,))

    def do_pedido(self, pedido_id: str) -> Sequence[Repasse]:
        pid = como_uuid(pedido_id)
        if pid is None:
            return ()
        with self._banco.transacao() as con:
            linhas = con.execute(
                f"select {self._COLUNAS} from public.repasses r "  # noqa: S608
                "join public.contratos c on c.id = r.contrato_id where c.pedido_id = %s "
                "order by r.criado_em, r.id",
                (pid,),
            ).fetchall()
        return tuple(self._de(l) for l in linhas)  # noqa: E741

    def _um(self, filtro: str, parametros: tuple) -> Repasse | None:
        with self._banco.transacao() as con:
            linha = con.execute(
                f"select {self._COLUNAS} from public.repasses r "  # noqa: S608
                f"join public.contratos c on c.id = r.contrato_id where {filtro}",
                parametros,
            ).fetchone()
        return self._de(linha) if linha else None

    def vincular_transferencia(self, repasse_id: str, provedor_transferencia_id: str) -> None:
        with self._banco.transacao() as con:
            con.execute(
                "update public.repasses set provedor_transferencia_id = %s "
                "where id = %s and provedor_transferencia_id is null",
                (provedor_transferencia_id, repasse_id),
            )

    def marcar_liberado(self, repasse_id: str, lancamento_id: str, em: datetime) -> None:
        """`agendado` -> `liberado` (uma vez só): quem chega depois leva `ConflitoDeEstado`."""
        with self._banco.transacao() as con:
            alterou = con.execute(
                "update public.repasses set status = 'liberado', lancamento_id = %s, "
                "liberado_em = %s where id = %s and status = 'agendado'",
                (_uuid_ou_novo(lancamento_id), em, repasse_id),
            ).rowcount
        if not alterou:
            raise ConflitoDeEstado("Este repasse não está mais agendado.")

    def congelar(self, repasse_id: str, disputa_id: str) -> None:
        with self._banco.transacao() as con:
            con.execute(
                "update public.repasses set status = 'congelado', congelado_por_disputa_id = %s "
                "where id = %s and status = 'agendado'",
                (disputa_id, repasse_id),
            )


def _uuid_ou_novo(valor: str | None) -> str:
    import uuid

    return str(uuid.UUID(valor)) if valor else str(uuid.uuid4())
