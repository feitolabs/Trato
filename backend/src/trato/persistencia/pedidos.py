"""Pedidos no Postgres: `pedidos`, `pedido_historico`, respostas, endereço, agendamento e presença.

O pedido do domínio (`trato.pedidos.estados.Pedido`) é a visão montada de várias tabelas:
  * estado, cliente, abertura        <- `pedidos`
  * profissional, orçamento, aceite  <- `contratos`
  * janela                           <- `agendamentos` (o mais recente que não foi remarcado)
  * check-in / check-out             <- `presencas` (hora do SERVIDOR, escrita pelo gatilho)
  * conclusão, estado antes da disputa e referência do pagamento <- `pedido_historico`
  * códigos de início/conclusão      <- recalculados do segredo (ver `codigos.py`)
Cada `salvar` é UMA transação: pedido + histórico + auditoria + agendamento + presença.
"""

from __future__ import annotations

import uuid
from collections.abc import Callable, Sequence
from typing import Any

import psycopg
from psycopg.types.json import Jsonb

from trato.api.repositorios import DadosPedido
from trato.pedidos.estados import (
    Acao,
    Ator,
    Estado,
    Evento,
    Janela,
    Papel,
    Pedido,
    ProvaCheckIn,
    ProvaCheckOut,
)
from trato.persistencia.auditoria import registrar_na_transacao
from trato.persistencia.codigos import codigo_do_agendamento, hash_do_codigo
from trato.persistencia.comum import como_uuid, exigir_uuid, para_json
from trato.persistencia.conexao import Banco
from trato.persistencia.erros import DadosInvalidos, RegraDoBanco

_PARA_BANCO = {Estado.PAGO_E_RETIDO: "pago_retido"}
_DO_BANCO = {"pago_retido": Estado.PAGO_E_RETIDO}
_SEGREDOS_DA_PROVA = ("codigo_inicio", "codigo_conclusao")
_TIPO_ATOR = {
    Papel.CLIENTE: "cliente",
    Papel.PROFISSIONAL: "profissional",
    Papel.MEDIADOR: "equipe",
    Papel.SISTEMA: "sistema",
}

# Colunas explícitas (agendamentos tem colunas de hash: nada de `select *`).
_SELECT_PEDIDO = """
select p.id, p.cliente_id, p.status, p.criado_em,
       c.profissional_id, c.orcamento_id, c.aceito_em, c.id as contrato_id,
       ag.id as ag_id, ag.janela_inicio, ag.janela_fim,
       ci.registrada_em as check_in_em, co.registrada_em as check_out_em,
       (select h.ocorrida_em from public.pedido_historico h
         where h.pedido_id = p.id and h.para_status = 'concluido'
         order by h.id desc limit 1) as concluido_em,
       (select h.de_status from public.pedido_historico h
         where h.pedido_id = p.id and h.para_status = 'em_disputa'
         order by h.id desc limit 1) as antes_da_disputa,
       (select h.prova -> 'dados' ->> 'referencia_pagamento' from public.pedido_historico h
         where h.pedido_id = p.id and h.para_status = 'pago_retido'
         order by h.id desc limit 1) as referencia_pagamento
  from public.pedidos p
  left join public.contratos c on c.pedido_id = p.id
  left join lateral (
      select a.id, a.janela_inicio, a.janela_fim from public.agendamentos a
       where a.contrato_id = c.id and a.status <> 'remarcado'
       order by a.criado_em desc, a.id limit 1) ag on true
  left join public.presencas ci on ci.agendamento_id = ag.id and ci.tipo = 'check_in'
  left join public.presencas co on co.agendamento_id = ag.id and co.tipo = 'check_out'
"""


def _banco(estado: Estado) -> str:
    return _PARA_BANCO.get(estado, estado.value)


def _estado(status: str) -> Estado:
    return _DO_BANCO.get(status) or Estado(status)


class PedidosPostgres:
    def __init__(self, banco: Banco, segredo_codigos: Callable[[], str]) -> None:
        self._banco = banco
        self._segredo = segredo_codigos

    # --- leitura -----------------------------------------------------------------------
    def obter(self, pedido_id: str) -> Pedido | None:
        achado = como_uuid(pedido_id)
        if achado is None:
            return None
        with self._banco.transacao() as con:
            return self._carregar(con, achado)

    def eventos(self, pedido_id: str) -> Sequence[Evento]:
        achado = como_uuid(pedido_id)
        if achado is None:
            return ()
        with self._banco.transacao() as con:
            linhas = con.execute(
                "select pedido_id, de_status, para_status, ator_id, prova, ocorrida_em "
                "from public.pedido_historico where pedido_id = %s order by id",
                (achado,),
            ).fetchall()
        eventos = []
        for linha in linhas:
            envelope = linha["prova"] or {}
            eventos.append(
                Evento(
                    pedido_id=str(linha["pedido_id"]),
                    acao=Acao(envelope["acao"]),
                    de=_estado(linha["de_status"]),
                    para=_estado(linha["para_status"]),
                    ator=Ator(
                        Papel(envelope.get("papel", "sistema")),
                        str(linha["ator_id"]) if linha["ator_id"] else "sistema",
                    ),
                    em=linha["ocorrida_em"],
                    prova=None,  # a prova tipada não é reconstruída; o JSON fica no banco
                )
            )
        return tuple(eventos)

    def listar_do_usuario(self, usuario_id: str, como_cliente: bool) -> Sequence[Pedido]:
        achado = como_uuid(usuario_id)
        if achado is None:
            return ()
        campo = "p.cliente_id" if como_cliente else "c.profissional_id"
        with self._banco.transacao() as con:
            linhas = con.execute(
                f"{_SELECT_PEDIDO} where {campo} = %s order by p.criado_em desc",  # noqa: S608
                (achado,),
            ).fetchall()
        return tuple(self._montar(linha) for linha in linhas)

    # --- escrita -----------------------------------------------------------------------
    def salvar(
        self, pedido: Pedido, evento: Evento | None = None, dados: DadosPedido | None = None
    ) -> Pedido:
        pid = exigir_uuid(pedido.id, "pedido")
        try:
            return self._salvar(pid, pedido, evento, dados)
        except RegraDoBanco as erro:
            if pedido.estado is Estado.AGUARDANDO_CONFIRMACAO:
                raise RegraDoBanco(
                    "O estado 'aguardando confirmação' ainda não existe no banco "
                    "(falta migration que o inclua em pedidos.status)."
                ) from erro
            raise

    def _salvar(
        self, pid: str, pedido: Pedido, evento: Evento | None, dados: DadosPedido | None
    ) -> Pedido:
        with self._banco.transacao() as con:
            existe = con.execute("select 1 from public.pedidos where id = %s", (pid,)).fetchone()
            if existe is None:
                if dados is None:
                    raise DadosInvalidos(
                        "Descreva o pedido: categoria, cidade, título e descrição."
                    )
                self._inserir(con, pid, pedido, dados)
            else:
                con.execute(
                    "update public.pedidos set status = %s where id = %s and status <> %s",
                    (_banco(pedido.estado), pid, _banco(pedido.estado)),
                )
            if evento is not None:
                self._registrar_evento(con, pid, evento)
            self._sincronizar_execucao(con, pid, pedido, evento)
            salvo = self._carregar(con, pid)
        if salvo is None:  # pragma: no cover - acabou de ser gravado
            raise RegraDoBanco("O pedido não foi encontrado depois de gravar.")
        return salvo

    # --- internos ----------------------------------------------------------------------
    def _carregar(self, con: psycopg.Connection[Any], pedido_id: str) -> Pedido | None:
        linha = con.execute(
            f"{_SELECT_PEDIDO} where p.id = %s",  # noqa: S608
            (pedido_id,),
        ).fetchone()
        return self._montar(linha) if linha else None

    def _montar(self, linha: dict[str, Any]) -> Pedido:
        estado = _estado(linha["status"])
        contratado = estado is not Estado.ABERTO and linha["contrato_id"] is not None
        codigo_inicio = codigo_conclusao = None
        if linha["ag_id"] is not None:
            ag = str(linha["ag_id"])
            codigo_inicio = codigo_do_agendamento(self._segredo(), ag, "inicio")
            if linha["check_in_em"] is not None:
                codigo_conclusao = codigo_do_agendamento(self._segredo(), ag, "conclusao")
        janela = (
            Janela(linha["janela_inicio"], linha["janela_fim"])
            if linha["janela_inicio"] is not None
            else None
        )
        em_disputa = estado is Estado.EM_DISPUTA and linha["antes_da_disputa"]
        return Pedido(
            id=str(linha["id"]),
            cliente_id=str(linha["cliente_id"]),
            aberto_em=linha["criado_em"],
            estado=estado,
            profissional_id=str(linha["profissional_id"]) if contratado else None,
            orcamento_id=str(linha["orcamento_id"]) if contratado else None,
            aceito_em=linha["aceito_em"] if contratado else None,
            referencia_pagamento=linha["referencia_pagamento"],
            janela=janela,
            codigo_inicio=codigo_inicio,
            codigo_conclusao=codigo_conclusao,
            check_in_em=linha["check_in_em"],
            check_out_em=linha["check_out_em"],
            concluido_em=linha["concluido_em"],
            estado_antes_da_disputa=_estado(linha["antes_da_disputa"]) if em_disputa else None,
        )

    def _inserir(
        self, con: psycopg.Connection[Any], pid: str, pedido: Pedido, d: DadosPedido
    ) -> None:
        categoria = exigir_uuid(d.categoria_id, "categoria")
        con.execute(
            "insert into public.pedidos (id, cliente_id, categoria_id, cidade_id, bairro, "
            "local_aprox_lat, local_aprox_lng, titulo, descricao, prazo_desejado, "
            "faixa_preco_min_centavos, faixa_preco_max_centavos, urgente, status, criado_em) "
            "values (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s)",
            (
                pid,
                exigir_uuid(pedido.cliente_id, "cliente"),
                categoria,
                exigir_uuid(d.cidade_id, "cidade"),
                d.bairro,
                d.local_aprox_lat,
                d.local_aprox_lng,
                d.titulo,
                d.descricao,
                d.prazo_desejado,
                d.faixa_preco_min_centavos,
                d.faixa_preco_max_centavos,
                d.urgente,
                _banco(pedido.estado),
                pedido.aberto_em,
            ),
        )
        for resposta in d.respostas:
            pergunta = con.execute(
                "select texto from public.categoria_perguntas "
                "where id = %s and categoria_id = %s and ativa",
                (exigir_uuid(resposta.pergunta_id, "pergunta"), categoria),
            ).fetchone()
            if pergunta is None:
                raise DadosInvalidos("Uma das perguntas não existe nesta categoria.")
            con.execute(
                "insert into public.pedido_respostas (pedido_id, pergunta_id, pergunta_texto, "
                "resposta) values (%s, %s, %s, %s)",
                (pid, resposta.pergunta_id, pergunta["texto"], Jsonb(resposta.resposta)),
            )
        e = d.endereco
        if e is not None:
            con.execute(
                "insert into public.pedidos_endereco (pedido_id, cep, logradouro, numero, "
                "complemento, bairro, referencia, lat, lng) "
                "values (%s, %s, %s, %s, %s, %s, %s, %s, %s)",
                (pid, e.cep, e.logradouro, e.numero, e.complemento, e.bairro, e.referencia,
                 e.lat, e.lng),
            )  # fmt: skip
        registrar_na_transacao(
            con,
            ator_id=pedido.cliente_id,
            ator_tipo="cliente",
            acao="pedido.aberto",
            entidade="pedido",
            entidade_id=pid,
            depois={"status": _banco(pedido.estado), "categoria_id": categoria},
        )

    def _registrar_evento(self, con: psycopg.Connection[Any], pid: str, ev: Evento) -> None:
        sistema = ev.ator.papel is Papel.SISTEMA
        ator_id = None if sistema else exigir_uuid(ev.ator.id, "ator")
        dados = para_json(ev.prova)
        if isinstance(dados, dict):
            if any(k in dados for k in _SEGREDOS_DA_PROVA):
                dados["codigo_validado"] = True
            for chave in _SEGREDOS_DA_PROVA:  # o código nunca é gravado em claro
                dados.pop(chave, None)
        envelope = {"acao": ev.acao.value, "papel": ev.ator.papel.value, "dados": dados}
        con.execute(
            "insert into public.pedido_historico (pedido_id, de_status, para_status, ator_id, "
            "motivo, prova, ocorrida_em) values (%s, %s, %s, %s, %s, %s, %s)",
            (
                pid,
                _banco(ev.de),
                _banco(ev.para),
                ator_id,
                dados.get("motivo") if isinstance(dados, dict) else None,
                Jsonb(envelope),
                ev.em,
            ),
        )
        registrar_na_transacao(
            con,
            ator_id=ator_id,
            ator_tipo=_TIPO_ATOR[ev.ator.papel],
            acao=f"pedido.{ev.acao.value}",
            entidade="pedido",
            entidade_id=pid,
            antes={"status": _banco(ev.de)},
            depois={"status": _banco(ev.para)},
        )

    def _sincronizar_execucao(
        self, con: psycopg.Connection[Any], pid: str, pedido: Pedido, ev: Evento | None
    ) -> None:
        """Agendamento (janela e códigos) e presenças (check-in/out) do pedido."""
        if pedido.janela is None:
            return
        contrato = con.execute(
            "select id from public.contratos where pedido_id = %s", (pid,)
        ).fetchone()
        if contrato is None:
            raise RegraDoBanco("O pedido ainda não tem contrato para agendar.")
        segredo = self._segredo()
        atual = con.execute(
            "select id, janela_inicio, janela_fim, status from public.agendamentos "
            "where contrato_id = %s and status <> 'remarcado' "
            "order by criado_em desc, id limit 1",
            (contrato["id"],),
        ).fetchone()
        j = pedido.janela
        if atual is None or (atual["janela_inicio"], atual["janela_fim"]) != (j.inicio, j.fim):
            novo = str(uuid.uuid4())
            codigo = codigo_do_agendamento(segredo, novo, "inicio")
            con.execute(
                "insert into public.agendamentos (id, contrato_id, data, janela_inicio, "
                "janela_fim, status, remarcado_de, codigo_inicio_hash) "
                "values (%s, %s, %s, %s, %s, 'confirmado', %s, %s)",
                (
                    novo,
                    contrato["id"],
                    j.inicio.date(),
                    j.inicio,
                    j.fim,
                    atual["id"] if atual else None,
                    hash_do_codigo(segredo, novo, "inicio", codigo),
                ),
            )
            if atual is not None:
                con.execute(
                    "update public.agendamentos set status = 'remarcado' where id = %s",
                    (atual["id"],),
                )
            atual = {"id": novo, "status": "confirmado"}
        ag = str(atual["id"])

        if ev is not None and pedido.check_in_em and isinstance(ev.prova, ProvaCheckIn):
            self._presenca(con, pid, ag, "check_in", ev, ev.prova.foto, ev.prova.localizacao)
            conclusao = codigo_do_agendamento(segredo, ag, "conclusao")
            con.execute(
                "update public.agendamentos set codigo_conclusao_hash = %s where id = %s",
                (hash_do_codigo(segredo, ag, "conclusao", conclusao), ag),
            )
        if ev is not None and pedido.check_out_em and isinstance(ev.prova, ProvaCheckOut):
            self._presenca(con, pid, ag, "check_out", ev, ev.prova.foto_final, None)

        if ev is not None and ev.acao is Acao.REGISTRAR_AUSENCIA:
            alvo = "nao_compareceu"
        elif pedido.estado is Estado.CANCELADO:
            alvo = "cancelado"
        elif pedido.check_out_em:
            alvo = "realizado"
        else:
            alvo = "confirmado"
        if str(atual["status"]) != alvo:
            con.execute("update public.agendamentos set status = %s where id = %s", (alvo, ag))

    def _presenca(
        self,
        con: psycopg.Connection[Any],
        pid: str,
        ag: str,
        tipo: str,
        ev: Evento,
        foto: Any,
        local: Any,
    ) -> None:
        # A hora da presença é a do servidor (gatilho); a do aparelho fica só como referência.
        ator = exigir_uuid(ev.ator.id, "ator")
        lat = local.latitude if local else None
        lng = local.longitude if local else None
        midia = con.execute(
            "insert into public.midias (pedido_id, enviada_por, finalidade, storage_path, "
            "capturada_em, lat, lng) values (%s, %s, %s, %s, %s, %s, %s) returning id",
            (
                pid,
                ator,
                "checkin" if tipo == "check_in" else "checkout",
                foto.arquivo_id,
                foto.tirada_em,
                lat,
                lng,
            ),
        ).fetchone()
        con.execute(
            "insert into public.presencas (agendamento_id, tipo, registrada_por, lat, lng, "
            "foto_midia_id, codigo_validado) values (%s, %s, %s, %s, %s, %s, true)",
            (ag, tipo, ator, lat, lng, midia["id"]),
        )
