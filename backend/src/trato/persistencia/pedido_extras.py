"""Recusa de pedido aberto e nota de material no Postgres.

A recusa depende da migration `20261030130000_pedido_recusas.sql` (preparada, NÃO aplicada).
"""

from __future__ import annotations

from collections.abc import Sequence
from decimal import Decimal

from psycopg.errors import UndefinedTable

from trato.api.repositorios_app import NotaMaterial, RecusaPedido
from trato.persistencia.comum import como_uuid, exigir_uuid
from trato.persistencia.conexao import Banco
from trato.persistencia.erros import ErroPersistencia
from trato.persistencia.execucao import ExecucaoPostgres, ItemNota


class RecusasPostgres:
    def __init__(self, banco: Banco) -> None:
        self._banco = banco

    def recusar(self, recusa: RecusaPedido) -> None:
        with self._banco.transacao() as con:
            con.execute(
                "insert into public.pedido_recusas (pedido_id, profissional_id, motivo, criada_em) "
                "values (%s, %s, %s, %s) on conflict (pedido_id, profissional_id) do nothing",
                (
                    exigir_uuid(recusa.pedido_id, "pedido"),
                    exigir_uuid(recusa.profissional_id, "profissional"),
                    recusa.motivo,
                    recusa.criada_em,
                ),
            )

    def do_profissional(self, profissional_id: str) -> Sequence[RecusaPedido]:
        achado = como_uuid(profissional_id)
        if achado is None:
            return ()
        try:
            with self._banco.transacao() as con:
                linhas = con.execute(
                    "select pedido_id, profissional_id, motivo, criada_em "
                    "from public.pedido_recusas where profissional_id = %s",
                    (achado,),
                ).fetchall()
        except ErroPersistencia as erro:
            if not isinstance(erro.__cause__, UndefinedTable):
                raise
            return ()  # migration das recusas ainda não aplicada: lista sem recusas
        return tuple(
            RecusaPedido(
                str(l["pedido_id"]), str(l["profissional_id"]), l["motivo"], l["criada_em"]
            )
            for l in linhas  # noqa: E741
        )


class NotasMaterialPostgres:
    def __init__(self, banco: Banco, execucao: ExecucaoPostgres) -> None:
        self._banco = banco
        self._execucao = execucao

    def registrar(self, nota: NotaMaterial) -> NotaMaterial:
        itens = [ItemNota(d, Decimal(q), unit) for d, q, unit, _ in nota.itens]
        nota_id = self._execucao.registrar_nota_material(
            nota.pedido_id, nota.profissional_id, nota.foto_storage_path, itens
        )
        return NotaMaterial(
            nota_id, nota.pedido_id, nota.profissional_id, nota.foto_storage_path,
            nota.itens, nota.total_centavos, nota.enviada_em,
        )  # fmt: skip

    def do_pedido(self, pedido_id: str) -> Sequence[NotaMaterial]:
        achado = como_uuid(pedido_id)
        if achado is None:
            return ()
        with self._banco.transacao() as con:
            notas = con.execute(
                "select n.id, n.enviada_por, n.total_centavos, n.enviada_em, m.storage_path "
                "from public.notas_material n join public.contratos c on c.id = n.contrato_id "
                "join public.midias m on m.id = n.midia_id "
                "where c.pedido_id = %s order by n.enviada_em, n.id",
                (achado,),
            ).fetchall()
            saida = []
            for n in notas:
                itens = con.execute(
                    "select descricao, quantidade, valor_unitario_centavos, total_centavos "
                    "from public.nota_material_itens where nota_id = %s order by ordem, id",
                    (n["id"],),
                ).fetchall()
                saida.append(
                    NotaMaterial(
                        str(n["id"]),
                        achado,
                        str(n["enviada_por"]),
                        n["storage_path"],
                        tuple(
                            (
                                i["descricao"],
                                str(i["quantidade"]),
                                int(i["valor_unitario_centavos"]),
                                int(i["total_centavos"]),
                            )
                            for i in itens
                        ),
                        int(n["total_centavos"]),
                        n["enviada_em"],
                    )  # fmt: skip
                )
        return tuple(saida)
