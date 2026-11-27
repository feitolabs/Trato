"""Contratos: gerados no aceite, com valores e regras congelados (a configuração do MOMENTO)."""

from __future__ import annotations

import hashlib
import json
from datetime import UTC, datetime

from psycopg.types.json import Jsonb

from trato.api.repositorios import Contrato
from trato.persistencia.auditoria import registrar_na_transacao
from trato.persistencia.comum import como_uuid, exigir_uuid
from trato.persistencia.conexao import Banco
from trato.persistencia.config import (
    exigir,
    parametros_globais,
    versao_vigente,
)
from trato.persistencia.erros import Duplicado, NaoEncontrado, RegraDoBanco

BPS = 10_000


def _meio_para_cima(valor: int, bps: int) -> int:
    """valor x bps / 10000, arredondado (meio para cima), só com inteiros."""
    return (valor * bps + BPS // 2) // BPS


class ContratosPostgres:
    def __init__(self, banco: Banco) -> None:
        self._banco = banco

    def obter_do_pedido(self, pedido_id: str) -> Contrato | None:
        achado = como_uuid(pedido_id)
        if achado is None:
            return None
        with self._banco.transacao() as con:
            linha = con.execute(
                "select c.pedido_id, c.orcamento_id, c.profissional_id, c.valor_total_centavos, "
                "c.aceito_em, c.prazo_execucao_dias, c.garantia_dias, "
                "p.categoria_id from public.contratos c "
                "join public.pedidos p on p.id = c.pedido_id where c.pedido_id = %s "
                "and c.status <> 'cancelado'",
                (achado,),
            ).fetchone()
        if linha is None:
            return None
        return Contrato(
            pedido_id=str(linha["pedido_id"]),
            orcamento_id=str(linha["orcamento_id"]),
            profissional_id=str(linha["profissional_id"]),
            valor_centavos=int(linha["valor_total_centavos"]),
            categoria_id=str(linha["categoria_id"]),
            aceito_em=linha["aceito_em"],
            prazo_execucao_dias=linha["prazo_execucao_dias"],
            garantia_dias=linha["garantia_dias"],
        )

    def encerrar_por_pagamento_expirado(self, pedido_id: str) -> bool:
        """Termos 5.2 e 6.3: sem pagamento no prazo, o contrato vigente é cancelado e o
        orçamento dele vence, na transação em curso. Contrato com dinheiro (cobrança paga ou
        lançamento no livro) nunca é cancelado. Sem a migration que permite um segundo
        contrato no pedido (20261127004000), nada muda."""
        pedido = como_uuid(pedido_id)
        if pedido is None:
            return False
        with self._banco.transacao() as con:
            if not con.execute(
                "select to_regclass('public.contratos_um_vigente_por_pedido_idx') is not null "
                "as tem"
            ).fetchone()["tem"]:
                return False
            atual = con.execute(
                "select id, orcamento_id from public.contratos where pedido_id = %s "
                "and status = 'aguardando_pagamento' for update",
                (pedido,),
            ).fetchone()
            if atual is None:
                return False
            # Consulta separada da trava: enxerga o que foi gravado enquanto se esperava por ela.
            if con.execute(
                "select exists (select 1 from public.lancamentos where contrato_id = %(c)s) "
                "or exists (select 1 from public.pagamentos where contrato_id = %(c)s "
                " and status in ('confirmado', 'reembolsado_parcial', 'contestado')) as tem",
                {"c": atual["id"]},
            ).fetchone()["tem"]:
                return False
            con.execute(
                "update public.pagamentos set status = 'expirado' "
                "where contrato_id = %s and status in ('pendente', 'falhou')",
                (atual["id"],),
            )
            con.execute(
                "update public.contratos set status = 'cancelado' where id = %s", (atual["id"],)
            )
            con.execute(
                "update public.orcamentos set status = 'expirado' "
                "where id = %s and status = 'aceito'",
                (atual["orcamento_id"],),
            )
            registrar_na_transacao(
                con,
                ator_id=None,
                ator_tipo="sistema",
                acao="contrato.cancelado_pagamento_expirado",
                entidade="contrato",
                entidade_id=str(atual["id"]),
                antes={"status": "aguardando_pagamento"},
                depois={"status": "cancelado", "pedido_id": pedido},
            )
        return True

    def salvar(self, contrato: Contrato) -> tuple[tuple[str, str], ...]:
        """Aceita o orçamento, recusa os outros `enviado` e gera o contrato na mesma transação.
        Devolve `(orcamento_id, profissional_id)` dos recusados agora; repetir é inofensivo."""
        pedido = exigir_uuid(contrato.pedido_id, "pedido")
        orcamento = exigir_uuid(contrato.orcamento_id, "orçamento")
        aceito_em = contrato.aceito_em or datetime.now(UTC)
        with self._banco.transacao() as con:
            existente = con.execute(
                "select orcamento_id from public.contratos where pedido_id = %s "
                "and status <> 'cancelado'",
                (pedido,),
            ).fetchone()
            if existente is not None:
                if str(existente["orcamento_id"]) == orcamento:
                    return ()
                raise Duplicado("Este pedido já tem contrato com outro orçamento.")

            orc = con.execute(
                "select id, profissional_id, status, valor_total_centavos, prazo_execucao_dias, "
                "garantia_dias, fora_do_escopo, validade_ate from public.orcamentos "
                "where id = %s and pedido_id = %s for update",
                (orcamento, pedido),
            ).fetchone()
            if orc is None:
                raise NaoEncontrado("Esse orçamento não existe neste pedido.")
            if orc["status"] != "enviado":
                raise RegraDoBanco("Só um orçamento enviado pode ser aceito.")
            if orc["validade_ate"] is not None and orc["validade_ate"] <= aceito_em:
                raise RegraDoBanco("Este orçamento venceu e não pode ser aceito (Termos 5.2).")
            ped = con.execute(
                "select cliente_id, titulo, descricao from public.pedidos where id = %s", (pedido,)
            ).fetchone()
            # Conta excluída não ganha contrato. A leitura espera uma exclusão em andamento.
            contas = con.execute(
                "select status from public.usuarios where id in (%s, %s) order by id for share",
                (ped["cliente_id"], orc["profissional_id"]),
            ).fetchall()
            if any(x["status"] == "anonimizado" for x in contas):
                raise RegraDoBanco("Uma das contas deste pedido foi excluída.")
            itens = con.execute(
                "select tipo, descricao, quantidade, valor_unitario_centavos, total_centavos "
                "from public.orcamento_itens where orcamento_id = %s order by ordem",
                (orcamento,),
            ).fetchall()

            versao = versao_vigente(con)
            parametros = parametros_globais(con, versao)
            valor = int(orc["valor_total_centavos"])
            adiantamento_bps = exigir(parametros, "adiantamento_bps")
            adiantamento = _meio_para_cima(valor, adiantamento_bps)
            regras = {
                "adiantamento_bps": adiantamento_bps,
                "parametros": parametros,
            }
            itens_json = [
                {**i, "quantidade": str(i["quantidade"])} for i in itens
            ]  # numeric -> texto, sem perder casas
            documento = {
                "pedido_id": pedido,
                "orcamento_id": orcamento,
                "cliente_id": str(ped["cliente_id"]),
                "profissional_id": str(orc["profissional_id"]),
                "valor_total_centavos": valor,
                "itens": itens_json,
                "regras": regras,
                "config_versao_id": versao,
            }
            hash_documento = hashlib.sha256(
                json.dumps(documento, sort_keys=True, separators=(",", ":")).encode()
            ).hexdigest()

            con.execute(
                "update public.orcamentos set status = 'aceito' where id = %s", (orcamento,)
            )
            recusados = con.execute(
                "update public.orcamentos set status = 'recusado' "
                "where pedido_id = %s and id <> %s and status = 'enviado' "
                "returning id, profissional_id",
                (pedido, orcamento),
            ).fetchall()
            novo = con.execute(
                "insert into public.contratos (pedido_id, orcamento_id, cliente_id, "
                "profissional_id, escopo_texto, fora_do_escopo, itens, prazo_execucao_dias, "
                "garantia_dias, valor_total_centavos, taxa_bps_aplicada, taxa_trato_centavos, "
                "liquido_profissional_centavos, adiantamento_centavos, config_versao_id, "
                "regras_aplicadas, hash_documento, aceito_em, aceite_ip, aceite_dispositivo) "
                "values (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, "
                "%s, %s) returning id",
                (
                    pedido, orcamento, ped["cliente_id"], orc["profissional_id"],
                    f"{ped['titulo']}\n\n{ped['descricao']}", orc["fora_do_escopo"],
                    Jsonb(itens_json), orc["prazo_execucao_dias"], orc["garantia_dias"], valor,
                    0, 0, valor, adiantamento, versao, Jsonb(regras),  # 0, 0: taxa (coluna legada)
                    hash_documento, aceito_em, contrato.aceite_ip, contrato.aceite_dispositivo,
                ),
            ).fetchone()  # fmt: skip
            con.execute(
                "update public.etapas set contrato_id = %s where orcamento_id = %s",
                (novo["id"], orcamento),
            )
            registrar_na_transacao(
                con,
                ator_id=str(ped["cliente_id"]),
                ator_tipo="cliente",
                acao="contrato.aceito",
                entidade="contrato",
                entidade_id=str(novo["id"]),
                depois={
                    "pedido_id": pedido,
                    "valor_total_centavos": valor,
                    "config_versao_id": versao,
                },
                ip=contrato.aceite_ip,
                dispositivo=contrato.aceite_dispositivo,
            )
            return tuple((str(r["id"]), str(r["profissional_id"])) for r in recusados)
