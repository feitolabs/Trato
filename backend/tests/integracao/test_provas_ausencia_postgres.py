"""TERMOS-BE-PROVAS no Postgres local: contestação como chamado, outro analista, painel com nomes
e leitura auditada das conversas."""

from __future__ import annotations

import threading

from .test_ausencia_cliente_postgres import _no_passado, _post, justificar, painel, registrado
from .test_disputa_painel_postgres import equipe  # noqa: F401 - fixture
from .test_pagamento_postgres import (  # noqa: F401 - `pg` e `migrations_novas` são fixtures
    VALOR_ORCAMENTO,
    linhas,
    migrations_novas,
    pg,
)

RETENCAO = VALOR_ORCAMENTO // 5


def com_retencao(c) -> str:
    pid, _ = registrado(c, fora_dos_7_dias=True)
    justificar(c, pid)
    r = painel(
        c,
        pid,
        retencao_centavos=RETENCAO,
        retencao_justificativa="Deslocamento e material comprado.",
        retencao_comprovantes=["nota-1"],
    )
    assert r.status_code == 200, r.text
    return pid


def contestar(c, pid):
    url = f"/v1/pedidos/{pid}/ausencia/contestacao"
    return _post(c, "cliente", url, {"texto": "Não considerou o atestado."})


def responder(c, pid, quem, resultado="revertida"):
    url = f"/v1/admin/ausencias/{pid}/contestacao/decisao"
    corpo = {"resultado": resultado, "resposta": "Conferimos o atestado enviado."}
    return _post(c, quem, url, corpo)


def _juntos(chamada, vezes=6) -> list[int]:
    codigos: list[int] = []
    threads = [
        threading.Thread(target=lambda: codigos.append(chamada().status_code)) for _ in range(vezes)
    ]
    for t in threads:
        t.start()
    for t in threads:
        t.join()
    return sorted(codigos)


def test_contestacao_vira_chamado_e_outro_analista_responde(pg, equipe):  # noqa: F811
    pid = com_retencao(pg)
    assert _juntos(lambda: contestar(pg, pid)) == [200] * 6
    sql = (
        "select c.categoria, c.status, c.protocolo, (select count(*) from "
        "public.chamado_mensagens m where m.chamado_id = c.id) from public.chamados c "
        "where c.pedido_id = %s"
    )
    ((categoria, status, protocolo, mensagens),) = linhas(pg, sql, (pid,))
    assert (categoria, status, mensagens) == ("contestacao", "aberto", 1)
    assert protocolo.startswith("SAC-")
    ((aceita,),) = linhas(
        pg,
        "select retencao_aceita_cliente from public.cancelamentos_pedido where pedido_id = %s",
        (pid,),
    )
    assert aceita is False
    _no_passado(  # mesmo depois do prazo, contestação aberta segura o dinheiro
        pg,
        "update public.cancelamentos_pedido set retencao_mostrada_cliente_em = "
        "retencao_mostrada_cliente_em - interval '12 days' where pedido_id = %s",
        (pid,),
    )
    _no_passado(
        pg,
        "update public.chamados set criado_em = criado_em - interval '1 day' where pedido_id = %s",
        (pid,),
    )
    assert painel(pg, pid, "confirmar").status_code == 409
    assert responder(pg, pid, "med_a").status_code == 403  # foi quem decidiu
    assert _juntos(lambda: responder(pg, pid, "med_b")) == [200] + [409] * 5
    dados = pg.pagto[0].get(f"/v1/admin/ausencias/{pid}", headers=pg.token("med_a")).json()
    assert dados["contestacao"]["status"] == "revertida" and dados["retencao_centavos"] == 0
    assert dados["valor_servico_centavos"] == VALOR_ORCAMENTO
    assert dados["pedido_numero"] and dados["cliente_nome"] and dados["profissional_nome"]
    assert painel(pg, pid, "confirmar").status_code == 200
    assert [o.valor_centavos for o in pg.pagto[2].ordens.do_pedido(pid)] == [VALOR_ORCAMENTO]


def test_leitura_de_conversa_audita_antes_e_exige_vinculo(pg, equipe):  # noqa: F811
    pid = com_retencao(pg)  # a chegada já escreveu no chat do pedido
    url = f"/v1/admin/pedidos/{pid}/conversas/leitura"

    def ler(quem, base, **extra):
        corpo = {"motivo": "Pedido de análise do caso.", "base": base} | extra
        return _post(pg, quem, url, corpo)

    contagem = (
        "select count(*) from public.auditoria where acao = 'dado_pessoal.conversa_lida' "
        "and entidade_id = %s"
    )
    for base in ("disputa", "denuncia", "incidente", "fraude", "relato"):
        assert ler("med_a", base).status_code == 409, base
    assert ler("cliente", "ordem_judicial", referencia="0001234-55").status_code == 403
    assert linhas(pg, contagem, (pid,))[0][0] == 0
    contestar(pg, pid)  # agora há um relato do cliente (chamado)
    r = ler("med_a", "relato")
    assert r.status_code == 200, r.text
    assert "Cheguei ao local" in r.text
    ((protocolo,),) = linhas(
        pg, "select protocolo from public.chamados where pedido_id = %s", (pid,)
    )
    assert ler("adm_a", "autorizacao_usuario", referencia="SAC-2026-999999").status_code == 409
    assert ler("adm_a", "autorizacao_usuario", referencia=protocolo).status_code == 200
    assert linhas(pg, contagem, (pid,))[0][0] == 2
