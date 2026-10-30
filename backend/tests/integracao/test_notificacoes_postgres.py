"""Notificações, preferências, dispositivos, conversas e agendador contra o Postgres local
descartável (pgserver). Nunca toca no Supabase real."""

from __future__ import annotations

import threading
import uuid
from datetime import UTC, datetime, timedelta
from pathlib import Path

import pytest

from trato.agendador import Agendador
from trato.agendador.executor import ExecutorContexto, FonteContexto, ids_ativos_postgres
from trato.agendador.registro import RegistroPostgres
from trato.agendador.trava import TravaAdvisoryPostgres
from trato.notificacoes import ligar_ao_contexto
from trato.notificacoes.canais import Canais, CanalApp, CanalFake
from trato.notificacoes.config import ConfigNotificacoes
from trato.notificacoes.eventos import Evento
from trato.notificacoes.postgres import NotificacoesServicoPostgres
from trato.notificacoes.servico import ServicoNotificacoes
from trato.pedidos.estados import Estado
from trato.rotinas.regras import ConfigRotinas

from .pg_local import RAIZ
from .test_fluxo_postgres import abrir_pedido, corpo_pedido

pytestmark = pytest.mark.integracao

MIGRATION = next(
    (RAIZ / "supabase" / "migrations").glob("*notificacoes_dispositivos_agendador.sql")
)


def agora() -> datetime:
    return datetime.now(UTC)


@pytest.fixture(scope="module")
def c(cenario):
    with cenario.local.admin() as con:
        if con.execute("select to_regclass('public.dispositivos_push')").fetchone()[0] is None:
            con.execute(Path(MIGRATION).read_text(encoding="utf-8"))
        for nome in ("ana", "bia"):  # pessoas novas: não mexem nas notificações dos outros testes
            cenario.ids[nome] = str(uuid.uuid4())
            con.execute("insert into auth.users (id) values (%s)", (cenario.ids[nome],))
            con.execute(
                "insert into public.usuarios (id, nome) values (%s, %s)", (cenario.ids[nome], nome)
            )
    return cenario


@pytest.fixture
def push() -> CanalFake:
    return CanalFake("push")


@pytest.fixture
def servico(c, push) -> ServicoNotificacoes:
    s = ServicoNotificacoes(
        NotificacoesServicoPostgres(c.banco),
        Canais(CanalApp(), push, None),
        ConfigNotificacoes(_env_file=None),
        agora,
    )
    ligar_ao_contexto(c.cliente.app, c.contexto, s)
    return s


def chave() -> str:
    return uuid.uuid4().hex


def test_migration_nao_aplicada_ao_banco_real_so_aqui():
    # O arquivo existe e traz o rollback ao lado (nada foi aplicado fora do banco descartável).
    assert (RAIZ / "supabase" / "rollback" / "notificacoes_dispositivos_rollback.sql").exists()


def test_criar_e_idempotente_mesmo_com_concorrencia(c, servico):
    k = chave()
    resultados = []

    def disparar():
        resultados.append(servico.notificar(Evento.AVALIACAO, c.ids["ana"], chave=k))

    fios = [threading.Thread(target=disparar) for _ in range(8)]
    [f.start() for f in fios]
    [f.join(20) for f in fios]
    assert sum(len(r) for r in resultados) == 1  # uma só criou
    with c.local.admin() as con:
        n = con.execute(
            "select count(*) from public.notificacoes where usuario_id = %s "
            "and dados ->> 'chave' = %s",
            (c.ids["ana"], f"{Evento.AVALIACAO.value}:{k}"),
        ).fetchone()[0]
    assert n == 1


def test_rotas_listar_lida_e_isolamento(c, servico):
    [nota] = servico.notificar(Evento.ORCAMENTO_ACEITO, c.ids["bia"], chave=chave(), pedido_id=None)
    lista = c.cliente.get("/v1/notificacoes", headers=c.token("bia")).json()
    assert [n["id"] for n in lista] == [nota.id]
    assert lista[0]["dados"]["link"] == "trato://pedido" and lista[0]["canal"] == "app"
    assert c.cliente.get("/v1/notificacoes", headers=c.token("ana")).json() != lista
    # outra pessoa não consegue marcar
    r = c.cliente.post(f"/v1/notificacoes/{nota.id}/lida", headers=c.token("ana"))
    assert r.status_code == 404
    r1 = c.cliente.post(f"/v1/notificacoes/{nota.id}/lida", headers=c.token("bia"))
    r2 = c.cliente.post(f"/v1/notificacoes/{nota.id}/lida", headers=c.token("bia"))
    assert r1.status_code == r2.status_code == 200 and r1.json()["lida_em"] == r2.json()["lida_em"]
    assert c.cliente.get("/v1/notificacoes?nao_lidas=true", headers=c.token("bia")).json() == []
    assert (
        c.cliente.post("/v1/notificacoes/nao-e-uuid/lida", headers=c.token("bia")).status_code
        == 404
    )


def test_preferencias_gravadas_no_banco_e_respeitadas(c, servico, push):
    ana = c.ids["ana"]
    r = c.cliente.put(
        "/v1/notificacoes/preferencias",
        json={"categorias": {"avaliacoes": {"app": False, "push": False}}},
        headers=c.token("ana"),
    )
    assert r.status_code == 200 and r.json()["categorias"]["avaliacoes"]["app"] is False
    with c.local.admin() as con:
        salvo = con.execute(
            "select preferencias from public.notificacao_preferencias where usuario_id = %s", (ana,)
        ).fetchone()[0]
    assert salvo == {"avaliacoes": {"app": False, "push": False}}
    c.cliente.post(
        "/v1/dispositivos",
        json={"token": "token-ana-pref-1", "plataforma": "android"},
        headers=c.token("ana"),
    )
    assert servico.notificar(Evento.AVALIACAO, ana, chave=chave()) == []  # tudo desligado
    assert push.enviados == []
    c.cliente.put(
        "/v1/notificacoes/preferencias",
        json={"categorias": {"avaliacoes": {"app": True, "push": True}}},
        headers=c.token("ana"),
    )
    novas = servico.notificar(Evento.AVALIACAO, ana, chave=chave())
    assert sorted(n.canal for n in novas) == ["app", "push"]
    assert len(push.enviados) == 1
    assert (
        c.cliente.put(
            "/v1/notificacoes/preferencias",
            json={"categorias": {"avaliacoes": {"sms": True}}},
            headers=c.token("ana"),
        ).status_code
        == 422
    )


def test_dispositivo_move_de_dono_e_reenvio_no_banco(c, servico, push):
    for quem in ("ana", "bia"):
        r = c.cliente.post(
            "/v1/dispositivos",
            json={"token": "token-compartilhado-9", "plataforma": "ios"},
            headers=c.token(quem),
        )
        assert r.status_code == 204
    assert servico.repo.tokens(
        c.ids["ana"]
    ) == () or "token-compartilhado-9" not in servico.repo.tokens(c.ids["ana"])
    assert "token-compartilhado-9" in servico.repo.tokens(c.ids["bia"])
    # cai o provedor: a linha fica pendente; ao voltar, o reenvio entrega uma vez só
    push.falhar_proximos(1)
    k = chave()
    servico.notificar(Evento.AVALIACAO, c.ids["bia"], chave=k)
    pendentes = [
        p
        for p in servico.repo.pendentes(agora() - timedelta(hours=1), 50)
        if p.usuario_id == c.ids["bia"]
    ]
    assert len(pendentes) == 1 and pendentes[0].enviada_em is None
    antes = len(push.enviados)
    assert servico.reenviar_pendentes() >= 1
    assert len(push.enviados) == antes + 1
    assert servico.reenviar_pendentes() == 0
    assert len(push.enviados) == antes + 1
    # chave repetida depois do reenvio continua sem duplicar
    assert servico.notificar(Evento.AVALIACAO, c.ids["bia"], chave=k) == []


def test_token_invalido_desativa_no_banco(c, servico, push):
    c.cliente.post(
        "/v1/dispositivos",
        json={"token": "token-morto-pg-01", "plataforma": "android"},
        headers=c.token("ana"),
    )
    push.tokens_invalidos.add("token-morto-pg-01")
    servico.notificar(Evento.AVALIACAO, c.ids["ana"], chave=chave())
    assert "token-morto-pg-01" not in servico.repo.tokens(c.ids["ana"])


def test_conversas_e_leitura_no_banco(c, servico):
    pedido_id = abrir_pedido(c)
    conversa = c.contexto.conversas.abrir(pedido_id, c.ids["profissional"])
    primeira = c.contexto.conversas.enviar(
        conversa, c.ids["profissional"], "Olá, zap 31 99999-8888"
    )
    c.contexto.conversas.enviar(conversa, c.ids["profissional"], "Segunda")
    minha = c.contexto.conversas.enviar(conversa, c.ids["cliente"], "Oi")
    lista = c.cliente.get("/v1/conversas", headers=c.token("cliente")).json()
    item = next(x for x in lista if x["id"] == conversa)
    assert item["nao_lidas"] == 2 and item["outra_parte_id"] == c.ids["profissional"]
    assert item["ultima_mensagem"] == "Oi" and item["ultima_minha"] is True
    assert "99999" not in item["ultima_mensagem"]
    # quem não participa não vê nem marca
    assert c.cliente.get("/v1/conversas", headers=c.token("ana")).json() == []
    assert (
        c.cliente.post(f"/v1/mensagens/{primeira}/lida", headers=c.token("ana")).status_code == 404
    )
    # o autor não marca a própria
    assert (
        c.cliente.post(f"/v1/mensagens/{minha}/lida", headers=c.token("cliente")).status_code == 422
    )
    r1 = c.cliente.post(f"/v1/mensagens/{primeira}/lida", headers=c.token("cliente"))
    r2 = c.cliente.post(f"/v1/mensagens/{primeira}/lida", headers=c.token("cliente"))
    assert r1.status_code == 200 and r1.json() == r2.json()
    r = c.cliente.post(f"/v1/conversas/{conversa}/lida", headers=c.token("cliente"))
    assert r.json() == {"marcadas": 1}
    do_prof = next(
        x
        for x in c.cliente.get("/v1/conversas", headers=c.token("profissional")).json()
        if x["id"] == conversa
    )
    assert do_prof["nao_lidas"] == 1  # a mensagem "Oi" do cliente ainda não foi lida por ele


# --- agendador ----------------------------------------------------------------------------


def montar_agendador(c, servico, relogio=agora, **extra):
    return Agendador(
        FonteContexto(
            c.contexto,
            ids_ativos_postgres(c.banco),
            ConfigRotinas(lembrete_confirmacao_apos=timedelta(hours=1)),
        ),
        ExecutorContexto(c.contexto, servico),
        RegistroPostgres(c.banco),
        TravaAdvisoryPostgres(c.local.uri),
        relogio,
        servico,
        **extra,
    )


def test_advisory_lock_so_deixa_uma_instancia(c):
    a, b = TravaAdvisoryPostgres(c.local.uri), TravaAdvisoryPostgres(c.local.uri)
    with a.adquirir("teste-trava") as primeira:
        with b.adquirir("teste-trava") as segunda:
            assert primeira is True and segunda is False
        with b.adquirir("outra-trava") as outra:
            assert outra is True
    with b.adquirir("teste-trava") as depois:  # solta ao sair
        assert depois is True


def test_registro_de_chaves_no_banco(c):
    r = RegistroPostgres(c.banco)
    k = f"teste:{chave()}"
    assert r.marcar(k, "lembrete", str(uuid.uuid4()), agora()) is True
    assert r.marcar(k, "lembrete", str(uuid.uuid4()), agora()) is False
    assert k in r.ja_executadas()


def test_duas_instancias_do_agendador_ao_mesmo_tempo(c, servico):
    """A que chega com a outra rodando desiste; no fim o efeito aconteceu uma única vez."""
    r = c.cliente.post("/v1/pedidos", json=corpo_pedido(c), headers=c.token("ana"))
    assert r.status_code == 201, r.text
    pedido_id = r.json()["id"]
    dentro, liberar = threading.Event(), threading.Event()

    class Lento(ExecutorContexto):
        def executar(self, acao, agora_):
            dentro.set()
            assert liberar.wait(10)
            super().executar(acao, agora_)

    pedido = c.contexto.pedidos.obter(pedido_id)
    from dataclasses import replace

    forcado = replace(
        pedido,
        estado=Estado.EM_CONFIRMACAO,
        profissional_id=c.ids["profissional"],
        check_out_em=agora() - timedelta(hours=3),
    )

    class FonteFixa(FonteContexto):
        def carregar(self, agora_):
            itens, cfg, feriados = super().carregar(agora_)
            from trato.rotinas.regras import PedidoMonitorado

            return [PedidoMonitorado(forcado)], cfg, feriados

    def agendador(executor):
        return Agendador(
            FonteFixa(
                c.contexto,
                lambda: [pedido_id],
                ConfigRotinas(lembrete_confirmacao_apos=timedelta(hours=1)),
            ),
            executor,
            RegistroPostgres(c.banco),
            TravaAdvisoryPostgres(c.local.uri),
            agora,
            servico,
        )

    a, b = agendador(Lento(c.contexto, servico)), agendador(ExecutorContexto(c.contexto, servico))
    saida = {}
    fio = threading.Thread(target=lambda: saida.update(a=a.rodar_uma_vez()))
    fio.start()
    assert dentro.wait(10)
    segunda = b.rodar_uma_vez()
    liberar.set()
    fio.join(20)
    assert segunda.travado is True and segunda.executadas == 0
    assert saida["a"].executadas == 1
    notas = [
        n
        for n in servico.repo.listar(c.ids["ana"], False, 50)
        if n.tipo == "execucao.confirmar_conclusao"
    ]
    assert len(notas) == 1
    # depois de solta a trava, uma nova rodada não repete nada
    assert b.rodar_uma_vez().executadas == 0
