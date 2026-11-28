"""BE-CHECKOUT-SEM-CODIGO-57 no Postgres local (20261127230000_checkout_sem_codigo_casos.sql):
função checkout_sem_codigo_vigente, abertura idempotente, prazo com trigger de 5 dias úteis,
prorrogação 22.3 na leitura, confirmação/disputa, contato manual auditado, retrabalho fora e
comportamento limpo sem a tabela."""

# ruff: noqa: F811 - o parâmetro com nome da fixture importada é do pytest

from __future__ import annotations

from datetime import UTC, datetime, timedelta

import pytest

from trato.api.checkout_sem_codigo import CONFIRMOU, RELATOU
from trato.notificacoes import ligar_ao_contexto
from trato.notificacoes.canais import Canais, CanalApp, CanalFake
from trato.notificacoes.config import ConfigNotificacoes
from trato.notificacoes.repositorio import RepositorioEmMemoria
from trato.notificacoes.servico import ServicoNotificacoes
from trato.persistencia.checkout_sem_codigo import CheckoutSemCodigoPostgres
from trato.persistencia.indisponibilidades import Janela as JanelaFalha

from .test_compensacao_postgres import check_in
from .test_desistencia_postgres import agendado
from .test_disputa_painel_postgres import equipe  # noqa: F401 - fixture
from .test_pagamento_postgres import migrations_novas, pg  # noqa: F401

URL_FILA = "/v1/admin/checkout-sem-codigo"


class _EmailsFake:
    def __init__(self, mapa: dict[str, str]) -> None:
        self._mapa = mapa

    def email_de(self, usuario_id: str) -> str | None:
        return self._mapa.get(usuario_id)


def _checkout_sem_codigo(pg, pid: str):
    http, contexto, _ = pg.pagto
    agora = contexto.agora().isoformat()
    return http.post(
        f"/v1/pedidos/{pid}/acoes/fazer_check_out",
        json={
            "prova": {
                "foto_final": {"arquivo_id": f"foto-{pid}", "tirada_em": agora},
                "localizacao": {"latitude": -19.9167, "longitude": -43.9345},
                "sem_codigo": True,
                "justificativa": "Cliente saiu antes do término do serviço.",
            }
        },
        headers=pg.token("profissional"),
    )


def _limpar(pg):
    with pg.local.admin() as con:
        con.execute("set session_replication_role = replica")
        con.execute("delete from public.checkout_sem_codigo_casos")
        con.execute("delete from public.janelas_indisponibilidade")


@pytest.fixture
def ambiente_57(pg, equipe):
    _limpar(pg)
    yield pg
    _limpar(pg)


def test_fluxo_completo_confirmacao_e_prorrogacao_223_no_postgres(ambiente_57):
    c = ambiente_57
    http, contexto, _ = c.pagto
    email = CanalFake("email")
    notif = ServicoNotificacoes(
        RepositorioEmMemoria(),
        Canais(CanalApp(), email=email),
        ConfigNotificacoes(_env_file=None),
        contexto.agora,
        emails=_EmailsFake({c.ids["cliente"]: "cliente@exemplo.com"}),
    )
    anterior = contexto.extras.get("notificador")
    ligar_ao_contexto(http.app, contexto, notif)
    try:
        pid, _ = agendado(c)
        check_in(c, pid)
        r = _checkout_sem_codigo(c, pid)
        assert r.status_code == 200, r.text

        # Banco tem exatamente 1 caso com check_out_em == checkout_sem_codigo_vigente(pid)
        vigente = contexto.checkout_sem_codigo.vigente(pid)
        assert vigente is not None
        caso = contexto.checkout_sem_codigo.abrir(pid, vigente, contexto.agora())  # idempotente
        assert caso.canal == "app+email"
        assert caso.contatado_em is not None and caso.responder_ate is not None
        assert any(m.destinos == ("cliente@exemplo.com",) for m in email.enviados)

        with c.local.admin() as con:
            row = con.execute(
                "select count(*) as n, bool_and(analista_id is null and decisao is null "
                "and justificativa is null and decidido_em is null) as travado "
                "from public.checkout_sem_codigo_casos where pedido_id = %s",
                (pid,),
            ).fetchone()
            assert row[0] == 1 and row[1] is True

        # Prorrogação 22.3 na leitura sem alterar a coluna gravada
        inicio_falha = caso.contatado_em + timedelta(hours=1)
        contexto.indisponibilidades.criar(
            JanelaFalha(
                id="",
                origem="app",
                inicio_em=inicio_falha,
                fim_em=inicio_falha + timedelta(hours=3),
                motivo="Instabilidade no aplicativo",
                criada_por=c.ids["adm_a"],
                encerrada_por=c.ids["adm_a"],
            )
        )
        fila = http.get(URL_FILA, headers=c.token("med_a"))
        assert fila.status_code == 200, fila.text
        item = next(i for i in fila.json()["itens"] if i["pedido_id"] == pid)
        assert datetime.fromisoformat(item["responder_ate"]) == caso.responder_ate + timedelta(
            hours=3
        )
        assert contexto.checkout_sem_codigo.obter(caso.id).responder_ate == caso.responder_ate

        # Confirmação registra resposta e tira da fila
        r_conf = http.post(
            f"/v1/pedidos/{pid}/acoes/confirmar_conclusao", headers=c.token("cliente")
        )
        assert r_conf.status_code == 200, r_conf.text
        depois = contexto.checkout_sem_codigo.obter(caso.id)
        assert depois.resposta == CONFIRMOU and depois.respondido_em is not None
        fila2 = http.get(URL_FILA, headers=c.token("med_a")).json()["itens"]
        assert all(i["pedido_id"] != pid for i in fila2)
    finally:
        if anterior is None:
            contexto.extras.pop("notificador", None)
        else:
            contexto.extras["notificador"] = anterior


def test_contato_manual_disputa_retrabalho_e_sem_tabela_no_postgres(ambiente_57, monkeypatch):
    c = ambiente_57
    http, contexto, _ = c.pagto
    anterior = contexto.extras.pop("notificador", None)
    try:
        pid, _ = agendado(c)
        check_in(c, pid)
        assert _checkout_sem_codigo(c, pid).status_code == 200

        # Sem notificador -> caso sem contato na fila
        fila = http.get(URL_FILA, headers=c.token("med_a"))
        assert fila.status_code == 200, fila.text
        item = next(i for i in fila.json()["itens"] if i["pedido_id"] == pid)
        assert item["contatado_em"] is None and item["responder_ate"] is None

        # Contato manual por mediador + bloqueio de repetição
        r_man = http.post(
            f"{URL_FILA}/{item['id']}/contato",
            json={"canal": "telefone", "motivo": "Contato telefônico feito com o cliente."},
            headers=c.token("med_a"),
        )
        assert r_man.status_code == 200, r_man.text
        assert r_man.json()["canal"] == "telefone" and r_man.json()["responder_ate"] is not None
        assert (
            http.post(
                f"{URL_FILA}/{item['id']}/contato",
                json={"canal": "whatsapp", "motivo": "Tentativa repetida de contato."},
                headers=c.token("med_a"),
            ).status_code
            == 409
        )

        # Abrir disputa registra resposta e tira da fila
        r_disp = http.post(
            f"/v1/pedidos/{pid}/disputa",
            json={"motivo": "mal_feito", "descricao": "Não terminou o serviço."},
            headers=c.token("cliente"),
        )
        assert r_disp.status_code == 201, r_disp.text
        depois = contexto.checkout_sem_codigo.obter(item["id"])
        assert depois.resposta == RELATOU and depois.respondido_em is not None
        assert all(
            i["pedido_id"] != pid
            for i in http.get(URL_FILA, headers=c.token("med_a")).json()["itens"]
        )

        # Retrabalho resolvido não é caso vigente no banco
        pid2, _ = agendado(c)
        with c.local.admin() as con:
            con.execute(
                "update public.pedidos set status = 'em_confirmacao' where id = %s",
                (pid2,),
            )
            con.execute(
                "insert into public.pedido_historico (pedido_id, de_status, para_status, "
                "ator_id, ocorrida_em, prova) values (%s, 'em_retrabalho', 'em_confirmacao', "
                '%s, %s, \'{"acao": "resolver_retrabalho", "dados": {}}\'::jsonb)',
                (pid2, c.ids["profissional"], datetime.now(UTC)),
            )
        assert contexto.checkout_sem_codigo.vigente(pid2) is None

        # Sem a tabela, não quebra e admin devolve 503
        monkeypatch.setattr(CheckoutSemCodigoPostgres, "_existe", staticmethod(lambda _con: False))
        assert contexto.checkout_sem_codigo.disponivel() is False
        assert contexto.checkout_sem_codigo.vigente(pid) is None
        assert contexto.checkout_sem_codigo.responder(pid, CONFIRMOU, contexto.agora()) == 0
        assert http.get(URL_FILA, headers=c.token("med_a")).status_code == 503
    finally:
        if anterior is not None:
            contexto.extras["notificador"] = anterior
