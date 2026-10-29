"""Execução do contrato: etapas, aditivos, notas de material, agendamentos e presenças.

Agendamento e presença são GRAVADOS por `PedidosPostgres` (junto com a transição de estado);
aqui só se lê (sem as colunas de hash dos códigos). Etapas, aditivos e notas têm escrita própria.
"""

from __future__ import annotations

from collections.abc import Sequence
from dataclasses import dataclass
from datetime import datetime
from decimal import ROUND_HALF_UP, Decimal

from trato.persistencia.comum import como_uuid, exigir_uuid
from trato.persistencia.conexao import Banco
from trato.persistencia.erros import NaoEncontrado

STATUS_ETAPA = ("prevista", "em_execucao", "aguardando_aprovacao", "aprovada", "paga", "liberada")


@dataclass(frozen=True)
class Etapa:
    id: str
    ordem: int
    descricao: str
    valor_centavos: int
    status: str


@dataclass(frozen=True)
class Aditivo:
    id: str
    motivo: str
    valor_centavos: int
    status: str
    decidido_em: datetime | None


@dataclass(frozen=True)
class ItemNota:
    descricao: str
    quantidade: Decimal
    valor_unitario_centavos: int

    @property
    def total_centavos(self) -> int:
        return int(
            (self.quantidade * self.valor_unitario_centavos).to_integral_value(ROUND_HALF_UP)
        )


@dataclass(frozen=True)
class Agendamento:
    id: str
    status: str
    janela_inicio: datetime
    janela_fim: datetime
    remarcado_de: str | None


@dataclass(frozen=True)
class Presenca:
    tipo: str
    registrada_por: str
    registrada_em: datetime
    codigo_validado: bool


class ExecucaoPostgres:
    def __init__(self, banco: Banco) -> None:
        self._banco = banco

    # --- etapas ------------------------------------------------------------------------
    def etapas_do_pedido(self, pedido_id: str) -> Sequence[Etapa]:
        achado = como_uuid(pedido_id)
        if achado is None:
            return ()
        with self._banco.transacao() as con:
            linhas = con.execute(
                "select e.id, e.ordem, e.descricao, e.valor_centavos, e.status "
                "from public.etapas e join public.contratos c on c.id = e.contrato_id "
                "where c.pedido_id = %s order by e.ordem",
                (achado,),
            ).fetchall()
        return tuple(
            Etapa(str(l["id"]), l["ordem"], l["descricao"], int(l["valor_centavos"]), l["status"])
            for l in linhas  # noqa: E741
        )

    def mudar_etapa(self, etapa_id: str, status: str, agora: datetime) -> None:
        """Muda o status da etapa. Descrição e valor ficam congelados (o banco recusa)."""
        with self._banco.transacao() as con:
            linha = con.execute(
                "update public.etapas set status = %s, "
                "aprovada_em = case when %s = 'aprovada' then %s else aprovada_em end "
                "where id = %s returning id",
                (status, status, agora, exigir_uuid(etapa_id, "etapa")),
            ).fetchone()
        if linha is None:
            raise NaoEncontrado("Etapa não encontrada.")

    # --- aditivos ----------------------------------------------------------------------
    def propor_aditivo(
        self, pedido_id: str, profissional_id: str, motivo: str, valor_centavos: int
    ) -> str:
        with self._banco.transacao() as con:
            contrato = con.execute(
                "select id from public.contratos where pedido_id = %s",
                (exigir_uuid(pedido_id, "pedido"),),
            ).fetchone()
            if contrato is None:
                raise NaoEncontrado("Este pedido ainda não tem contrato.")
            linha = con.execute(
                "insert into public.aditivos (contrato_id, criado_por, motivo, valor_centavos) "
                "values (%s, %s, %s, %s) returning id",
                (contrato["id"], exigir_uuid(profissional_id, "profissional"), motivo,
                 valor_centavos),
            ).fetchone()  # fmt: skip
        return str(linha["id"])

    def decidir_aditivo(
        self, aditivo_id: str, cliente_id: str, aprovar: bool, agora: datetime
    ) -> None:
        """Só o cliente do contrato aprova (o banco confere). Decisão tomada não muda mais."""
        with self._banco.transacao() as con:
            linha = con.execute(
                "update public.aditivos set status = %s, decidido_por = %s, decidido_em = %s "
                "where id = %s returning id",
                (
                    "aprovado" if aprovar else "recusado",
                    exigir_uuid(cliente_id, "cliente"),
                    agora,
                    exigir_uuid(aditivo_id, "aditivo"),
                ),
            ).fetchone()
        if linha is None:
            raise NaoEncontrado("Aditivo não encontrado.")

    def aditivos_do_pedido(self, pedido_id: str) -> Sequence[Aditivo]:
        achado = como_uuid(pedido_id)
        if achado is None:
            return ()
        with self._banco.transacao() as con:
            linhas = con.execute(
                "select a.id, a.motivo, a.valor_centavos, a.status, a.decidido_em "
                "from public.aditivos a join public.contratos c on c.id = a.contrato_id "
                "where c.pedido_id = %s order by a.criado_em, a.id",
                (achado,),
            ).fetchall()
        return tuple(
            Aditivo(
                str(l["id"]), l["motivo"], int(l["valor_centavos"]), l["status"], l["decidido_em"]
            )
            for l in linhas  # noqa: E741
        )

    # --- notas de material -------------------------------------------------------------
    def registrar_nota_material(
        self,
        pedido_id: str,
        profissional_id: str,
        foto_storage_path: str,
        itens: Sequence[ItemNota],
        *,
        aditivo_id: str | None = None,
    ) -> str:
        """Foto da notinha + nota + itens, na mesma transação (o banco confere o total)."""
        pedido = exigir_uuid(pedido_id, "pedido")
        profissional = exigir_uuid(profissional_id, "profissional")
        with self._banco.transacao() as con:
            contrato = con.execute(
                "select id from public.contratos where pedido_id = %s", (pedido,)
            ).fetchone()
            if contrato is None:
                raise NaoEncontrado("Este pedido ainda não tem contrato.")
            midia = con.execute(
                "insert into public.midias (pedido_id, enviada_por, finalidade, storage_path) "
                "values (%s, %s, 'nota_material', %s) returning id",
                (pedido, profissional, foto_storage_path),
            ).fetchone()
            nota = con.execute(
                "insert into public.notas_material (contrato_id, aditivo_id, enviada_por, "
                "midia_id, total_centavos) values (%s, %s, %s, %s, %s) returning id",
                (
                    contrato["id"],
                    exigir_uuid(aditivo_id, "aditivo") if aditivo_id else None,
                    profissional,
                    midia["id"],
                    sum(i.total_centavos for i in itens),
                ),
            ).fetchone()
            for ordem, item in enumerate(itens):
                con.execute(
                    "insert into public.nota_material_itens (nota_id, descricao, quantidade, "
                    "valor_unitario_centavos, total_centavos, ordem) "
                    "values (%s, %s, %s, %s, %s, %s)",
                    (nota["id"], item.descricao, item.quantidade, item.valor_unitario_centavos,
                     item.total_centavos, ordem),
                )  # fmt: skip
        return str(nota["id"])

    # --- leitura de agendamentos e presenças ------------------------------------------
    def agendamentos_do_pedido(self, pedido_id: str) -> Sequence[Agendamento]:
        achado = como_uuid(pedido_id)
        if achado is None:
            return ()
        with self._banco.transacao() as con:
            linhas = con.execute(
                "select a.id, a.status, a.janela_inicio, a.janela_fim, a.remarcado_de "
                "from public.agendamentos a join public.contratos c on c.id = a.contrato_id "
                "where c.pedido_id = %s order by a.criado_em, a.id",
                (achado,),
            ).fetchall()
        return tuple(
            Agendamento(
                str(l["id"]),
                l["status"],
                l["janela_inicio"],
                l["janela_fim"],
                str(l["remarcado_de"]) if l["remarcado_de"] else None,
            )  # fmt: skip
            for l in linhas  # noqa: E741
        )

    def presencas_do_pedido(self, pedido_id: str) -> Sequence[Presenca]:
        achado = como_uuid(pedido_id)
        if achado is None:
            return ()
        with self._banco.transacao() as con:
            linhas = con.execute(
                "select pr.tipo, pr.registrada_por, pr.registrada_em, pr.codigo_validado "
                "from public.presencas pr join public.agendamentos a on a.id = pr.agendamento_id "
                "join public.contratos c on c.id = a.contrato_id "
                "where c.pedido_id = %s order by pr.registrada_em, pr.tipo",
                (achado,),
            ).fetchall()
        return tuple(
            Presenca(l["tipo"], str(l["registrada_por"]), l["registrada_em"], l["codigo_validado"])
            for l in linhas  # noqa: E741
        )
