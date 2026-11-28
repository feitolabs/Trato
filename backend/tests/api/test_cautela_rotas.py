"""BE-96-TESTES (Termos 9.6): cada rota que grava mensagem entre as partes respeita o bloqueio
de contato, e a preservação segura a remoção de arquivos. HTTP, memória e provedor falso."""

# ruff: noqa: F811 - o parâmetro com nome da fixture importada é do pytest

from __future__ import annotations

from dataclasses import replace
from datetime import timedelta

from conftest import AGORA, CLIENTE, PROFISSIONAL, cab
from test_ausencia_cliente import INICIO, ausente, chegar, pedido_marcado
from test_conta_valores import lgpd
from test_contraproposta import _contra, _pedido_com_orcamento
from test_fluxo_pagamento_e2e import fluxo  # noqa: F401

from trato.api.cautela import CONTATO_BLOQUEADO
from trato.api.repositorios import DadosPedido, EnderecoPedido
from trato.pedidos.estados import Estado
from trato.persistencia.incidentes import Incidente
from trato.uploads import ArmazenamentoFake

H = timedelta(hours=1)


def incidente(ctx, pedido_id, medida) -> str:
    agora = ctx.agora()
    item, _ = ctx.incidentes.abrir(
        Incidente(
            tipo="agressao_ameaca_assedio",
            descricao=f"Relato do pedido {pedido_id} ({medida}).",
            canal="app",
            contato="app",
            pedido_id=pedido_id,
            aberto_em=agora,
            cautela_ate=agora + 24 * H,
        )
    )
    assert ctx.incidentes.registrar_medida(item.id, medida, "Cautela.", "eq", agora) == "ok"
    return item.id


def encerrar(ctx, iid) -> None:
    assert ctx.incidentes.encerrar(iid, "Apurado e resolvido.", "eq", ctx.agora()) == "ok"


def mensagens(ctx) -> int:
    return sum(len(v) for v in ctx.conversas._mensagens.values())


def bloqueada(r) -> bool:
    return r.status_code == 409 and r.json()["detail"] == CONTATO_BLOQUEADO


# --- negociação do orçamento (pedido ainda aberto; o relato é de outro pedido do par) -------------


def negociacao(amb):
    amb.semear_pedido(Estado.CONCLUIDO, id="ped-0", concluido_em=AGORA)
    return _pedido_com_orcamento(amb)


def orcamentos(amb) -> list[tuple[str, str]]:
    itens = amb.contexto.orcamentos._detalhes.values()
    return sorted((o.id, o.status) for o in itens)


def nova_versao(amb, orc, caminho):
    url = f"/v1/pedidos/ped-1/orcamentos/{orc}/{caminho}"
    return amb.cliente.post(url, json={"valor_centavos": 25_000}, headers=cab("t-prof"))


def test_contraproposta_do_cliente(amb):
    orc = negociacao(amb)
    iid = incidente(amb.contexto, "ped-0", "bloquear_contato")
    antes = (mensagens(amb.contexto), orcamentos(amb))
    r = _contra(amb, orc, 25_000)
    assert bloqueada(r), r.text
    assert (mensagens(amb.contexto), orcamentos(amb)) == antes
    encerrar(amb.contexto, iid)
    assert _contra(amb, orc, 25_000).status_code == 201
    assert mensagens(amb.contexto) == antes[0] + 1


def test_aceitar_contraproposta(amb):
    orc = negociacao(amb)
    assert _contra(amb, orc, 25_000).status_code == 201
    iid = incidente(amb.contexto, "ped-0", "bloquear_contato")
    antes = (mensagens(amb.contexto), orcamentos(amb))
    r = nova_versao(amb, orc, "contraproposta/aceitar")
    assert bloqueada(r), r.text
    assert (mensagens(amb.contexto), orcamentos(amb)) == antes
    encerrar(amb.contexto, iid)
    assert nova_versao(amb, orc, "contraproposta/aceitar").status_code == 201
    assert mensagens(amb.contexto) > antes[0] and orcamentos(amb) != antes[1]


def test_propor_novo_valor(amb):
    orc = negociacao(amb)
    iid = incidente(amb.contexto, "ped-0", "bloquear_contato")
    antes = (mensagens(amb.contexto), orcamentos(amb))
    r = nova_versao(amb, orc, "propor")
    assert bloqueada(r), r.text
    assert (mensagens(amb.contexto), orcamentos(amb)) == antes
    encerrar(amb.contexto, iid)
    r = nova_versao(amb, orc, "propor")
    assert r.status_code == 201, r.text
    assert mensagens(amb.contexto) > antes[0] and orcamentos(amb) != antes[1]


# --- agenda da visita ----------------------------------------------------------------------------


def janela(f, horas=48) -> dict:
    inicio = f.ctx.agora() + horas * H
    return {"inicio": inicio.isoformat(), "fim": (inicio + 3 * H).isoformat()}


def foto_do_pedido(f, pid):
    p = f.ctx.pedidos.obter(pid)
    return (p.estado, p.janela, len(f.ctx.pedidos.eventos(pid)), mensagens(f.ctx))


def test_propor_agenda(fluxo):
    pid = fluxo.aceitar()
    fluxo.pagar(pid)
    iid = incidente(fluxo.ctx, pid, "bloquear_contato")
    antes = foto_do_pedido(fluxo, pid)
    url = f"/v1/pedidos/{pid}/agenda/propor"
    for quem in ("t-cliente", "t-prof"):
        r = fluxo.chamar("POST", url, quem, {"janela": janela(fluxo)})
        assert bloqueada(r), (quem, r.text)
    assert foto_do_pedido(fluxo, pid) == antes
    encerrar(fluxo.ctx, iid)
    r = fluxo.chamar("POST", url, "t-cliente", {"janela": janela(fluxo)})
    assert r.status_code == 201, r.text
    assert mensagens(fluxo.ctx) == antes[3] + 1


def test_aceitar_agenda_confirmando_a_visita(fluxo):
    pid = fluxo.aceitar()
    fluxo.pagar(pid)
    url = f"/v1/pedidos/{pid}/agenda/propor"
    sugestao = fluxo.chamar("POST", url, "t-prof", {"janela": janela(fluxo)})
    assert sugestao.status_code == 201, sugestao.text
    iid = incidente(fluxo.ctx, pid, "bloquear_contato")
    antes = foto_do_pedido(fluxo, pid)
    aceite = f"/v1/pedidos/{pid}/agenda/aceitar"
    corpo = {"mensagem_id": sugestao.json()["id"]}
    r = fluxo.chamar("POST", aceite, "t-cliente", corpo)
    assert bloqueada(r), r.text
    assert foto_do_pedido(fluxo, pid) == antes and antes[0] is Estado.PAGO_E_RETIDO
    encerrar(fluxo.ctx, iid)
    r = fluxo.chamar("POST", aceite, "t-cliente", corpo)
    assert r.status_code == 200 and r.json()["estado"] == "agendado", r.text
    assert mensagens(fluxo.ctx) == antes[3] + 1


# --- chegada e cliente ausente: o registro vale, a mensagem automática não sai --------------------


def test_chegada_e_cliente_ausente_registram_sem_mensagem(fluxo):
    pid, _ = pedido_marcado(fluxo)
    incidente(fluxo.ctx, pid, "bloquear_contato")
    antes = mensagens(fluxo.ctx)
    fluxo.amb.relogio.agora = INICIO
    r = chegar(fluxo, pid)
    assert r.status_code == 200, r.text
    fluxo.amb.relogio.avancar(minutes=20)
    r = ausente(fluxo, pid)
    assert r.status_code == 200, r.text
    assert fluxo.ctx.pedidos.obter(pid).cliente_ausente_em is not None
    assert mensagens(fluxo.ctx) == antes


def test_chegada_e_cliente_ausente_sem_bloqueio_mandam_a_mensagem(fluxo):
    pid, _ = pedido_marcado(fluxo)
    antes = mensagens(fluxo.ctx)
    fluxo.amb.relogio.agora = INICIO
    assert chegar(fluxo, pid).status_code == 200
    assert mensagens(fluxo.ctx) == antes + 1
    fluxo.amb.relogio.avancar(minutes=20)
    assert ausente(fluxo, pid).status_code == 200
    assert mensagens(fluxo.ctx) == antes + 2


# --- preservação: a remoção de arquivos espera ---------------------------------------------------


def test_preservacao_adia_a_remocao_de_arquivos_ate_encerrar(fluxo):
    pid = fluxo.aceitar()
    servico = lgpd(fluxo)
    armazem = ArmazenamentoFake()
    servico._arquivos = armazem
    for uid in (CLIENTE.id, PROFISSIONAL.id, "sem-relato"):
        armazem.simular_envio("verificacao", f"{uid}/doc.jpg", b"documento")
        servico._r.fonte.a_remover[uid] = [("verificacao", f"{uid}/doc.jpg")]
    iid = incidente(fluxo.ctx, pid, "preservar_registros")

    def guardados() -> set[str]:
        return {caminho.split("/")[0] for _, caminho in armazem.arquivos}

    for _ in range(2):
        saida = servico.processar_vencidas(fluxo.ctx.agora())
        assert saida["arquivos_pendentes"] == 2, saida
        assert guardados() == {CLIENTE.id, PROFISSIONAL.id}
    encerrar(fluxo.ctx, iid)
    saida = servico.processar_vencidas(fluxo.ctx.agora())
    assert "arquivos_pendentes" not in saida, saida
    assert guardados() == set() and servico._r.fonte.limpezas_pendentes() == []


# --- endereço completo do cliente: ocultado ao profissional com contato bloqueado (9.6) ----------


def _gravar_endereco(ctx, pedido_id: str) -> None:
    atual = ctx.pedidos.dados_do_pedido(pedido_id)
    endereco = EnderecoPedido(
        logradouro="Rua das Flores",
        numero="123",
        bairro="Centro",
        cep="01001000",
        complemento="Apto 4",
        referencia="Portão azul",
    )
    if atual is None:
        novos = DadosPedido(
            categoria_id="cat-1",
            cidade_id="cid-1",
            titulo="Reparo elétrico",
            descricao="Trocar disjuntor",
            bairro="Centro",
            endereco=endereco,
        )
    else:
        novos = replace(atual, bairro="Centro", endereco=endereco)
    ctx.pedidos.atualizar_dados(pedido_id, CLIENTE.id, novos)


def test_endereco_ocultado_para_profissional_com_contato_bloqueado(fluxo):
    pid, _ = pedido_marcado(fluxo)
    _gravar_endereco(fluxo.ctx, pid)

    # Sem bloqueio: endereço liberado aparece para o profissional
    r = fluxo.amb.cliente.get(f"/v1/pedidos/{pid}/dados", headers=cab("t-prof"))
    assert r.status_code == 200, r.text
    assert r.json()["endereco"]["logradouro"] == "Rua das Flores"
    assert r.json()["endereco"]["numero"] == "123"
    assert r.json()["bairro"] == "Centro"

    # Com bloqueio de contato (9.6): ocultado para o profissional, mantido para o cliente
    iid = incidente(fluxo.ctx, pid, "bloquear_contato")
    r_prof = fluxo.amb.cliente.get(f"/v1/pedidos/{pid}/dados", headers=cab("t-prof"))
    assert r_prof.status_code == 200, r_prof.text
    assert r_prof.json()["endereco"] is None
    assert "Rua das Flores" not in r_prof.text
    assert r_prof.json()["bairro"] == "Centro"

    r_cli = fluxo.amb.cliente.get(f"/v1/pedidos/{pid}/dados", headers=cab("t-cliente"))
    assert r_cli.status_code == 200, r_cli.text
    assert r_cli.json()["endereco"]["logradouro"] == "Rua das Flores"

    # Após encerrar o incidente: volta a aparecer para o profissional
    encerrar(fluxo.ctx, iid)
    r_depois = fluxo.amb.cliente.get(f"/v1/pedidos/{pid}/dados", headers=cab("t-prof"))
    assert r_depois.status_code == 200, r_depois.text
    assert r_depois.json()["endereco"]["logradouro"] == "Rua das Flores"


def test_endereco_ocultado_em_outro_pedido_do_mesmo_par_com_contato_bloqueado(fluxo):
    fluxo.amb.semear_pedido(Estado.CONCLUIDO, id="ped-outro", concluido_em=AGORA)
    pid, _ = pedido_marcado(fluxo)
    _gravar_endereco(fluxo.ctx, pid)

    incidente(fluxo.ctx, "ped-outro", "bloquear_contato")
    r = fluxo.amb.cliente.get(f"/v1/pedidos/{pid}/dados", headers=cab("t-prof"))
    assert r.status_code == 200, r.text
    assert r.json()["endereco"] is None
    assert "Rua das Flores" not in r.text
