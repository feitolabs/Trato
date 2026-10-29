"""Orçamentos e itens. O total é calculado AQUI e o banco confere no COMMIT (gatilho adiado)."""

from __future__ import annotations

from collections.abc import Sequence
from dataclasses import dataclass
from datetime import datetime
from decimal import ROUND_HALF_UP, Decimal

from trato.api.repositorios import Orcamento
from trato.api.repositorios_app import OrcamentoDoPedido
from trato.persistencia.comum import como_uuid, exigir_uuid
from trato.persistencia.conexao import Banco
from trato.persistencia.erros import DadosInvalidos, RegraDoBanco


@dataclass(frozen=True)
class ItemOrcamento:
    tipo: str  # deslocamento | horas | material | outro
    descricao: str
    quantidade: Decimal
    valor_unitario_centavos: int

    @property
    def total_centavos(self) -> int:
        """Quantidade x unitário, arredondado para o centavo (meio para cima)."""
        return int(
            (self.quantidade * self.valor_unitario_centavos).to_integral_value(ROUND_HALF_UP)
        )


@dataclass(frozen=True)
class EtapaProposta:
    descricao: str
    valor_centavos: int


class OrcamentosPostgres:
    def __init__(self, banco: Banco) -> None:
        self._banco = banco

    def obter(self, orcamento_id: str) -> Orcamento | None:
        achado = como_uuid(orcamento_id)
        if achado is None:
            return None
        with self._banco.transacao() as con:
            linha = con.execute(
                "select o.id, o.pedido_id, o.profissional_id, o.valor_total_centavos, "
                "p.categoria_id from public.orcamentos o "
                "join public.pedidos p on p.id = o.pedido_id "
                "where o.id = %s",
                (achado,),
            ).fetchone()
        if linha is None:
            return None
        return Orcamento(
            id=str(linha["id"]),
            pedido_id=str(linha["pedido_id"]),
            profissional_id=str(linha["profissional_id"]),
            valor_centavos=int(linha["valor_total_centavos"]),
            categoria_id=str(linha["categoria_id"]),
        )

    def do_pedido(self, pedido_id: str) -> Sequence[OrcamentoDoPedido]:
        """Última versão enviada (ou a aceita) de cada profissional, do mais barato ao mais caro."""
        achado = como_uuid(pedido_id)
        if achado is None:
            return ()
        with self._banco.transacao() as con:
            linhas = con.execute(
                "select o.id, o.profissional_id, u.nome, o.versao, o.valor_total_centavos, "
                "o.prazo_execucao_dias, o.garantia_dias, o.observacoes, o.enviado_em "
                "from public.orcamentos o join public.usuarios u on u.id = o.profissional_id "
                "where o.pedido_id = %s and o.status in ('enviado', 'aceito') "
                "order by o.valor_total_centavos, o.enviado_em, o.id",
                (achado,),
            ).fetchall()
        return tuple(
            OrcamentoDoPedido(
                str(l["id"]),
                str(l["profissional_id"]),
                l["nome"],
                int(l["versao"]),
                int(l["valor_total_centavos"]),
                l["prazo_execucao_dias"],
                l["garantia_dias"],
                l["observacoes"],
                l["enviado_em"],
            )  # fmt: skip
            for l in linhas  # noqa: E741
        )

    def enviar(
        self,
        *,
        pedido_id: str,
        profissional_id: str,
        itens: Sequence[ItemOrcamento],
        agora: datetime,
        etapas: Sequence[EtapaProposta] = (),
        prazo_execucao_dias: int | None = None,
        validade_ate: datetime | None = None,
        garantia_dias: int | None = None,
        fora_do_escopo: str | None = None,
        sinal_material_centavos: int | None = None,
        observacoes: str | None = None,
    ) -> str:
        """Cria a nova versão do orçamento do profissional e a envia (uma transação).

        A versão anterior ainda 'enviada' do mesmo profissional vira 'substituido'.
        Quem pode orçar (profissional aprovado e verificado) é conferido pelo banco.
        """
        if not itens:
            raise DadosInvalidos("O orçamento precisa de ao menos um item.")
        pedido = exigir_uuid(pedido_id, "pedido")
        profissional = exigir_uuid(profissional_id, "profissional")
        total = sum(i.total_centavos for i in itens)
        with self._banco.transacao() as con:
            pedido_linha = con.execute(
                "select status from public.pedidos where id = %s for update", (pedido,)
            ).fetchone()
            if pedido_linha is None:
                raise DadosInvalidos("Pedido não encontrado.")
            if pedido_linha["status"] != "aberto":
                raise RegraDoBanco("Este pedido não recebe mais orçamentos.")
            versao = con.execute(
                "select coalesce(max(versao), 0) + 1 as v from public.orcamentos "
                "where pedido_id = %s and profissional_id = %s",
                (pedido, profissional),
            ).fetchone()["v"]
            novo = con.execute(
                "insert into public.orcamentos (pedido_id, profissional_id, versao, "
                "valor_total_centavos, prazo_execucao_dias, validade_ate, garantia_dias, "
                "fora_do_escopo, sinal_material_centavos, observacoes) "
                "values (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s) returning id",
                (
                    pedido, profissional, versao, total, prazo_execucao_dias, validade_ate,
                    garantia_dias, fora_do_escopo, sinal_material_centavos, observacoes,
                ),
            ).fetchone()["id"]  # fmt: skip
            for ordem, item in enumerate(itens):
                con.execute(
                    "insert into public.orcamento_itens (orcamento_id, tipo, descricao, "
                    "quantidade, valor_unitario_centavos, total_centavos, ordem) "
                    "values (%s, %s, %s, %s, %s, %s, %s)",
                    (novo, item.tipo, item.descricao, item.quantidade,
                     item.valor_unitario_centavos, item.total_centavos, ordem),
                )  # fmt: skip
            for ordem, etapa in enumerate(etapas):
                con.execute(
                    "insert into public.etapas (orcamento_id, ordem, descricao, valor_centavos) "
                    "values (%s, %s, %s, %s)",
                    (novo, ordem, etapa.descricao, etapa.valor_centavos),
                )
            con.execute(
                "update public.orcamentos set status = 'substituido' "
                "where pedido_id = %s and profissional_id = %s and status = 'enviado'",
                (pedido, profissional),
            )
            con.execute(
                "update public.orcamentos set status = 'enviado', enviado_em = %s where id = %s",
                (agora, novo),
            )
        return str(novo)
