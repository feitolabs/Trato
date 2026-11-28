"""Eliminação de documentos de verificação recusados ou substituídos (Política de Privacidade
v1.2, seção 5; Termos 14.8 e 16.3): até 90 dias depois da decisão.

Elegível: documento de verificação `recusada`; ou de uma `aprovada` substituída por uma
aprovação POSTERIOR da mesma pessoa. Só se substitui o que é 1 para 1 (`selfie`, frente e
verso do documento): um só do tipo na antiga e um só na nova; frente e verso só saem se a nova
traz todos os lados que a antiga tinha. Os demais tipos podem ser vários e ficam. Aprovado
vigente, enviada e em análise nunca entram.

Nada sai com guarda ou incidente aberto da pessoa ou de pedido dela; com qualquer bloqueio de
`retencao_pedido_bloqueios` num pedido dela (disputa, contestação de disputa ou de nota,
pagamento contestado, preservação, guardas); com contestação de cartão ou medida de conta
aberta; com arquivo que outro documento não elegível ainda usa; ou com caminho fora da pasta
da própria pessoa. Sem essas tabelas, nada é eliminado. Cada eliminação é auditada na mesma
transação, sem dado pessoal; os logs só levam o id do documento.
"""

# ruff: noqa: S608 - só trechos fixos de SQL são concatenados; valores vão por parâmetro

from __future__ import annotations

import logging
from datetime import datetime, timedelta

from psycopg.types.json import Jsonb

from trato.persistencia.conexao import Banco
from trato.uploads.armazenamento import ArmazenamentoArquivos

log = logging.getLogger("trato.verificacao.expurgo")

BUCKET = "verificacao"

_CAMINHO = "regexp_replace({d}.storage_path, '^verificacao/', '')"

# Quantos documentos do tipo `{tipo}` a verificação `{ver}` tem.
_QUANTOS = (
    "(select count(*) from public.verificacao_documentos q "
    "where q.verificacao_id = {ver} and q.tipo = {tipo})"
)

# Quando o documento deixou de valer (nulo: ainda vale ou está pendente).
_DECISAO = (
    "case v.status when 'recusada' then v.decidida_em when 'aprovada' then "
    "(select min(n.decidida_em) from public.verificacoes n "
    "where n.profissional_id = v.profissional_id and n.status = 'aprovada' "
    "and n.decidida_em > v.decidida_em "
    "and d.tipo in ('selfie', 'documento_frente', 'documento_verso') "
    "and " + _QUANTOS.format(ver="v.id", tipo="d.tipo") + " = 1 "
    "and " + _QUANTOS.format(ver="n.id", tipo="d.tipo") + " = 1 "
    # frente e verso: a nova precisa trazer cada lado que a antiga tinha
    "and (d.tipo = 'selfie' or not exists (select 1 from public.verificacao_documentos s "
    "where s.verificacao_id = v.id and s.tipo in ('documento_frente', 'documento_verso') "
    "and " + _QUANTOS.format(ver="n.id", tipo="s.tipo") + " <> 1))) end"
)

_PEDIDOS_DA_PESSOA = (
    "select p.id from public.pedidos p where p.cliente_id = e.pessoa union "
    "select c.pedido_id from public.contratos c "
    "where e.pessoa in (c.cliente_id, c.profissional_id)"
)

_SELECAO = (
    "with todos as ("
    "select d.id, v.profissional_id as pessoa, "
    + _CAMINHO.format(d="d")
    + " as caminho, "
    + _DECISAO
    + " as decisao, v.status as origem from public.verificacao_documentos d "
    "join public.verificacoes v on v.id = d.verificacao_id), "
    "e as (select * from todos where decisao <= %(corte)s) "
    "select e.id, e.caminho, e.origem from e where "
    # só dentro da pasta da própria pessoa
    "replace(split_part(e.caminho, '/', 1), '-', '') = replace(e.pessoa::text, '-', '') "
    "and split_part(e.caminho, '/', 2) <> '' "
    "and not ('..' = any(string_to_array(e.caminho, '/'))) "
    # o mesmo arquivo num documento que ainda vale
    "and not exists (select 1 from public.verificacao_documentos o where "
    + _CAMINHO.format(d="o")
    + " = e.caminho and not exists (select 1 from e x where x.id = o.id)) "
    "and not exists (select 1 from public.acessos_conta_guardas g "
    "where g.usuario_id = e.pessoa and g.encerrada_em is null) "
    "and not public.usuario_com_registros_preservados(e.pessoa) "
    "and not exists (select 1 from public.incidentes_seguranca i "
    "where i.status <> 'encerrado' and (i.envolvido_id = e.pessoa "
    "or i.pedido_id in (" + _PEDIDOS_DA_PESSOA + "))) "
    "and not exists (select 1 from public.pedido_guardas g "
    "where g.encerrada_em is null and g.pedido_id in (" + _PEDIDOS_DA_PESSOA + ")) "
    # os mesmos bloqueios de `retencao_pedido_situacao`, em todos os pedidos da pessoa
    "and not exists (select 1 from (" + _PEDIDOS_DA_PESSOA + ") r(pedido) "
    "where cardinality(public.retencao_pedido_bloqueios(r.pedido)) > 0) "
    # contestação de cartão em aberto
    "and not exists (select 1 from public.contestacoes k "
    "where k.status in ('aberta', 'em_analise') "
    "and k.pedido_id in (" + _PEDIDOS_DA_PESSOA + ")) "
    # medida de conta em vigor ou com contestação em aberto
    "and not exists (select 1 from public.medidas_conta m where m.usuario_id = e.pessoa "
    "and m.revertida_em is null and (m.fim_em is null or m.fim_em > now())) "
    "and not exists (select 1 from public.medida_contestacoes mc "
    "where mc.usuario_id = e.pessoa and mc.status in ('aberta', 'em_analise')) "
)


class ExpurgoVerificacaoPostgres:
    def __init__(self, banco: Banco, armazenamento: ArmazenamentoArquivos) -> None:
        self._banco = banco
        self._arquivos = armazenamento

    def disponivel(self) -> bool:
        with self._banco.transacao() as con:
            linha = con.execute(
                "select to_regclass('public.verificacao_documentos') is not null "
                "and to_regclass('public.acessos_conta_guardas') is not null "
                "and to_regclass('public.pedido_guardas') is not null "
                "and to_regclass('public.incidentes_seguranca') is not null "
                "and to_regclass('public.contestacoes') is not null "
                "and to_regclass('public.medidas_conta') is not null "
                "and to_regclass('public.medida_contestacoes') is not null "
                "and to_regprocedure('public.retencao_pedido_bloqueios(uuid)') is not null "
                "and to_regprocedure('public.registrar_auditoria(uuid,text,text,text,uuid,"
                "jsonb,jsonb,text,text,text,text)') is not null "
                "and to_regprocedure('public.usuario_com_registros_preservados(uuid)') "
                "is not null as tem"
            ).fetchone()
        return bool(linha["tem"])

    def expurgar(self, agora: datetime, prazo_dias: int, limite: int) -> int:
        """Elimina até `limite` documentos. Repetir é seguro. Devolve quantos saíram."""
        if not 1 <= prazo_dias <= 90 or not 1 <= limite <= 1000:
            raise ValueError("Prazo (1 a 90 dias) ou limite (1 a 1000) fora do permitido.")
        if not self.disponivel():
            return 0
        corte = agora - timedelta(days=prazo_dias)
        with self._banco.transacao() as con:
            candidatos = con.execute(
                _SELECAO + "order by e.decisao, e.id limit %(limite)s",
                {"corte": corte, "limite": limite},
            ).fetchall()
        eliminados = 0
        for candidato in candidatos:
            try:
                eliminados += self._eliminar(candidato["id"], corte)
            except Exception as erro:  # noqa: BLE001 - fica para o próximo ciclo
                # Sem mensagem nem rastro: o erro do Storage pode citar o caminho (dado pessoal).
                log.warning(
                    "documento de verificação %s não eliminado (%s)",
                    candidato["id"],
                    type(erro).__name__,
                )
        return eliminados

    def _eliminar(self, documento_id: object, corte: datetime) -> int:
        with self._banco.transacao() as con:  # um documento por transação curta
            # As travas de `pode_eliminar_registros_pedido`: guarda ou incidente sendo gravado
            # agora espera aqui, e o que já foi gravado é visto na conferência abaixo.
            for trava in ("trato.expurgo_acessos", "trato.preservacao_registros"):
                con.execute("select pg_advisory_xact_lock(hashtextextended(%s, 0))", (trava,))
            atual = con.execute(
                _SELECAO + "and e.id = %(id)s", {"corte": corte, "id": documento_id}
            ).fetchone()
            if atual is None:
                return 0
            apagado = con.execute(
                "delete from public.verificacao_documentos where id = %s returning id",
                (documento_id,),
            ).fetchone()
            if apagado is None:
                return 0
            origem = "recusado" if atual["origem"] == "recusada" else "substituido"
            # Só o id do documento e a regra: nada de nome, caminho ou id da pessoa.
            con.execute(
                "select public.registrar_auditoria(null, 'sistema', "
                "'lgpd.documento_verificacao_eliminado', 'verificacao_documentos', %s, null, "
                "%s, 'Retenção vencida (Política de Privacidade, seção 5)', null, null, null)",
                (documento_id, Jsonb({"regra": origem})),
            )
            # Dentro da transação: se o Storage falhar, a referência volta. Se o commit falhar
            # depois, o próximo ciclo repete (apagar arquivo ausente não é erro).
            self._arquivos.remover(BUCKET, atual["caminho"])
        return 1
