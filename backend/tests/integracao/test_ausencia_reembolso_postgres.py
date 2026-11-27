"""FIX-77 no Postgres LOCAL descartável: o agendador de produção (`montar`) devolve o dinheiro na
ausência do profissional, em transação única. Provedor falso. Nunca toca no Supabase."""

from __future__ import annotations

import secrets
import threading
import uuid
from datetime import UTC, datetime, timedelta

import pytest
from pydantic import SecretStr

import trato.agendador.__main__ as principal
from trato.agendador.config import ConfigAgendador
from trato.api import fabrica
from trato.config import Config
from trato.financeiro.ledger import CUSTODIA
from trato.notificacoes.config import ConfigNotificacoes
from trato.pagamentos.provedor import TipoEvento
from trato.pedidos.estados import Acao
from trato.rotinas.regras import AcaoRotina, TipoAcaoRotina

from .test_pagamento_postgres import (  # noqa: F401 - `pg` e `migrations_novas` são fixtures
    VALOR_ORCAMENTO,
    cobrar_ok,
    estado_pedido,
    linhas,
    migrations_novas,
    pedido_aceito,
    pg,
    webhook,
)

pytestmark = pytest.mark.integracao


@pytest.fixture
def montar(pg, monkeypatch):  # noqa: F811
    """O `montar()` real do agendador, com configuração de teste (sem ler `.env`)."""
    config = Config(
        _env_file=None,
        trato_persistencia="postgres",
        database_url=SecretStr(pg.local.uri),
        trato_banco_papel="service_role",
        trato_codigo_segredo=SecretStr(secrets.token_hex(16)),
        supabase_jwt_secret=SecretStr(pg.segredo_jwt),
    )
    provedor = pg.pagto[2].provedor  # o mesmo falso que "recebeu" o pagamento
    monkeypatch.setattr(principal, "obter_config", lambda: config)
    monkeypatch.setattr(
        principal, "obter_config_agendador", lambda: ConfigAgendador(_env_file=None)
    )
    monkeypatch.setattr(
        principal, "obter_config_notificacoes", lambda: ConfigNotificacoes(_env_file=None)
    )
    monkeypatch.setattr(fabrica, "escolher_provedor", lambda _: provedor)

    def novo():
        agendador, _, _ = principal.montar(pg.banco)
        return agendador._executor

    return novo


def pago_e_agendado(c) -> tuple[str, str, datetime]:
    http, _, servico = c.pagto
    pid = pedido_aceito(c)
    cob = cobrar_ok(c, pid)
    servico.provedor.marcar_paga(cob["id"])
    r = webhook(c, TipoEvento.PAGAMENTO_CONFIRMADO, cob["id"], evento_id=f"evt_{uuid.uuid4().hex}")
    assert r.status_code == 200, r.text
    inicio = datetime.now(UTC).replace(microsecond=0) + timedelta(days=2)
    janela = {"inicio": inicio.isoformat(), "fim": (inicio + timedelta(hours=3)).isoformat()}
    r = http.post(
        f"/v1/pedidos/{pid}/acoes/confirmar_agenda",
        json={"prova": {"janela": janela}},
        headers=c.token("profissional"),
    )
    if r.status_code != 200:
        r = http.post(
            f"/v1/pedidos/{pid}/acoes/confirmar_agenda",
            json={"janela": janela},
            headers=c.token("profissional"),
        )
    assert r.status_code == 200, r.text
    return pid, cob["id"], inicio + timedelta(days=3)  # instante já depois da tolerância


def ausencia(pid: str) -> AcaoRotina:
    return AcaoRotina(
        TipoAcaoRotina.TRANSICIONAR, pid, f"ausencia:{pid}", acao=Acao.REGISTRAR_AUSENCIA
    )


def ordens(c, pid):
    return c.pagto[2].ordens.do_pedido(pid)


def historico_cancelado(c, pid) -> int:
    return linhas(
        c,
        "select count(*) from public.pedido_historico where pedido_id = %s "
        "and prova ->> 'acao' = 'registrar_ausencia'",
        (pid,),
    )[0][0]


def test_agendador_montado_estorna_tudo_na_ausencia(pg, montar):  # noqa: F811
    pid, cobranca_id, depois = pago_e_agendado(pg)
    contexto = pg.pagto[1]
    assert contexto.ledger.saldo_da_conta(CUSTODIA, pid) == VALOR_ORCAMENTO

    executor = montar()
    executor.executar(ausencia(pid), depois)
    executor.executar(ausencia(pid), depois)  # de novo: nada muda

    assert estado_pedido(pg, pid) == "cancelado"
    assert contexto.ledger.saldo_da_conta(CUSTODIA, pid) == 0
    (ordem,) = ordens(pg, pid)
    assert ordem.valor_centavos == VALOR_ORCAMENTO and ordem.estado == "enviada"
    assert ordem.cobranca_id == cobranca_id and "/ausencia/" in ordem.chave
    assert historico_cancelado(pg, pid) == 1


def test_duas_maquinas_ao_mesmo_tempo_estornam_uma_vez(pg, montar):  # noqa: F811
    pid, _, depois = pago_e_agendado(pg)
    executores = [montar(), montar()]
    barreira, erros = threading.Barrier(2), []

    def rodar(executor) -> None:
        barreira.wait()
        try:
            executor.executar(ausencia(pid), depois)
        except Exception as erro:  # noqa: BLE001 - o teste confere abaixo
            erros.append(erro)

    fios = [threading.Thread(target=rodar, args=(e,)) for e in executores]
    [f.start() for f in fios]
    [f.join(30) for f in fios]

    assert not any(f.is_alive() for f in fios) and erros == []  # a segunda espera e não age
    assert len(ordens(pg, pid)) == 1 and historico_cancelado(pg, pid) == 1
    assert pg.pagto[1].ledger.saldo_da_conta(CUSTODIA, pid) == 0


def test_falha_ao_gravar_o_estorno_desfaz_o_cancelamento(pg, montar, monkeypatch):  # noqa: F811
    from trato.pagamentos.orquestrador import ServicoPagamento

    pid, _, depois = pago_e_agendado(pg)
    executor = montar()

    def quebra(*args, **kwargs):
        raise RuntimeError("banco caiu no meio")

    with monkeypatch.context() as m:
        m.setattr(ServicoPagamento, "_registrar_intencao", quebra)
        with pytest.raises(RuntimeError):
            executor.executar(ausencia(pid), depois)
    assert estado_pedido(pg, pid) == "agendado"  # nada gravou: o próximo ciclo tenta de novo
    assert historico_cancelado(pg, pid) == 0 and ordens(pg, pid) == []

    executor.executar(ausencia(pid), depois)
    assert estado_pedido(pg, pid) == "cancelado" and len(ordens(pg, pid)) == 1


def test_falha_do_provedor_no_banco_deixa_ordem_pendente(pg, montar, monkeypatch):  # noqa: F811
    pid, _, depois = pago_e_agendado(pg)
    executor = montar()
    provedor = pg.pagto[2].provedor

    def fora_do_ar(*args, **kwargs):
        raise RuntimeError("provedor fora do ar")

    with monkeypatch.context() as m:
        m.setattr(provedor, "estornar", fora_do_ar)
        executor.executar(ausencia(pid), depois)
    assert estado_pedido(pg, pid) == "cancelado"
    assert [o.estado for o in ordens(pg, pid)] == ["pendente"]
    assert pg.pagto[2].reenviar_estornos(pid) == 1


def test_trava_faz_outro_gravador_esperar(pg):  # noqa: F811
    pid, _, _ = pago_e_agendado(pg)
    contexto = pg.pagto[1]
    entrou, terminou = threading.Event(), threading.Event()

    def outro() -> None:
        with contexto.transacao():
            entrou.set()
            contexto.pedidos.travar(pid)
        terminou.set()

    with contexto.transacao():
        contexto.pedidos.travar(pid)
        fio = threading.Thread(target=outro)
        fio.start()
        assert entrou.wait(10)
        assert not terminou.wait(1.0)  # esperando a trava da linha
    assert terminou.wait(10)
    fio.join(10)
