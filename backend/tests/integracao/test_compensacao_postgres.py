"""TERMOS-BE-86 no Postgres local (migrations 20261126061000 e 20261126061100): dívida, ordem de
estorno, aviso, desconto na liberação, cancelamento, foto da chegada e o app sem as funções."""

from __future__ import annotations

import struct
import threading
import uuid
from datetime import UTC, datetime, timedelta

import pytest

from trato.agendador.executor import ExecutorContexto
from trato.financeiro.ledger import a_compensar, liberado
from trato.persistencia.uploads import UploadsPostgres
from trato.rotinas.regras import AcaoRotina, TipoAcaoRotina
from trato.seguranca.config import obter_config_seguranca
from trato.uploads import ArmazenamentoFake
from trato.uploads.config import ConfigUploads
from trato.uploads.servico import ServicoUploads

from .test_ausencia_cliente_postgres import _no_passado, _post
from .test_desistencia_postgres import agendado, check_in
from .test_disputa_painel_postgres import equipe  # noqa: F401 - fixture
from .test_fluxo_postgres import foto
from .test_pagamento_postgres import (  # noqa: F401 - `pg` e `migrations_novas` são fixtures
    VALOR_ORCAMENTO,
    linhas,
    migrations_novas,
    pg,
)

PAINEL = "/v1/admin/compensacoes"
PARTE = VALOR_ORCAMENTO // 4


class Avisos:
    def __init__(self) -> None:
        self.enviados = []
        self.fora = False

    def notificar(self, evento, usuario, **kw):
        if self.fora:
            raise RuntimeError("fora do ar")
        self.enviados.append((evento.value, usuario, kw.get("corpo")))


@pytest.fixture
def avisos(pg, monkeypatch):  # noqa: F811
    falso = Avisos()
    monkeypatch.setitem(pg.pagto[1].extras, "notificador", falso)
    return falso


def concluido(c) -> str:
    """Pago, executado e confirmado: o valor fica 'a liberar' para o profissional."""
    pid, _ = agendado(c)
    check_in(c, pid)
    visto = c.pagto[0].get(f"/v1/pedidos/{pid}", headers=c.token("cliente")).json()
    saida = {"foto_final": foto(), "codigo_conclusao": visto["codigo_conclusao"]}
    url = f"/v1/pedidos/{pid}/acoes"
    r = _post(c, "profissional", f"{url}/fazer_check_out", {"prova": saida})
    assert r.status_code == 200, r.text
    r = _post(c, "cliente", f"{url}/confirmar_conclusao", None)
    assert r.status_code == 200, r.text
    return pid


def liberar(c, pid, depois=timedelta(0)) -> AcaoRotina:
    """`depois`: pedido com disputa decidida só libera após o prazo de contestar (8.7)."""
    contexto = c.pagto[1]
    pedido = contexto.pedidos.obter(pid)
    saldo = contexto.ledger.saldos_pedido(pid, pedido.profissional_id).a_liberar
    assert saldo > 0
    acao = AcaoRotina(
        TipoAcaoRotina.LIBERAR_SALDO,
        pid,
        f"liberacao:{pid}:{saldo}",
        valor_centavos=saldo,
        profissional_id=pedido.profissional_id,
    )
    executor(c).executar(acao, datetime.now(UTC) + depois)
    return acao


def executor(c) -> ExecutorContexto:
    http, contexto, servico = c.pagto
    return ExecutorContexto(
        contexto, cobrancas=servico.cobrancas, provedor=servico.provedor, pagamento=servico
    )


def disponivel_do_profissional(c, pid) -> int:
    contexto = c.pagto[1]
    return contexto.ledger.saldo_da_conta(
        liberado(contexto.pedidos.obter(pid).profissional_id), pid
    )


def regresso(c, pid, valor=PARTE):
    return c.pagto[1].compensacoes.registrar_regresso(
        pid, str(uuid.uuid4()), valor, "Garantia acionada depois do repasse.",
        c.ids["med_a"], c.ids["adm_a"],
    )  # fmt: skip


def tem_funcao_com_operador(c) -> bool:
    ((tem,),) = linhas(
        c,
        "select to_regprocedure('public.compensacao_registrar_disputa("
        "uuid,uuid,bigint,text,uuid)') is not null",
    )
    return tem


def zerar(c):
    """Dívidas de um teste não podem descontar o seguinte."""
    with c.local.admin() as con:
        con.execute("set session_replication_role = replica")
        if con.execute("select to_regclass('public.compensacao_propostas_regresso')").fetchone()[0]:
            con.execute("delete from public.compensacao_propostas_regresso")
        con.execute("delete from public.compensacoes_aplicadas")
        con.execute("delete from public.compensacoes_dividas")


def test_divida_avisada_e_descontada_na_liberacao_uma_vez_e_cancelada(pg, equipe, avisos):  # noqa: F811
    zerar(pg)
    contexto = pg.pagto[1]
    antigo = concluido(pg)
    liberar(pg, antigo)
    r = regresso(pg, antigo)
    assert r.resultado == "ok", r
    assert contexto.compensacoes.listar(pedido_id=antigo)[1] == 1
    # o livro com os lançamentos novos carrega
    assert any(i.tipo.value == "reembolso" for i in contexto.ledger.lancamentos(antigo))

    avisos.fora = True
    url = f"{PAINEL}/{r.divida_id}/avisar"
    assert _post(pg, "med_a", url, None).json()["avisado"] is False
    sem_aviso = concluido(pg)
    liberar(pg, sem_aviso)
    assert disponivel_do_profissional(pg, sem_aviso) == VALOR_ORCAMENTO  # sem aviso, nada sai

    avisos.fora = False
    assert _post(pg, "med_a", url, None).json()["avisado"] is True
    assert "Garantia acionada" in avisos.enviados[-1][2]
    novo = concluido(pg)
    acao = liberar(pg, novo)
    assert disponivel_do_profissional(pg, novo) == VALOR_ORCAMENTO - PARTE
    repetidas = [
        threading.Thread(target=executor(pg).executar, args=(acao, datetime.now(UTC)))
        for _ in range(4)
    ]
    for t in repetidas:
        t.start()
    for t in repetidas:
        t.join()
    assert disponivel_do_profissional(pg, novo) == VALOR_ORCAMENTO - PARTE
    divida = contexto.compensacoes.obter(r.divida_id)
    assert divida.status == "quitada" and divida.compensado_centavos == PARTE
    prof = contexto.pedidos.obter(novo).profissional_id
    assert contexto.ledger.saldo_da_conta(a_compensar(prof), novo) == PARTE
    assert contexto.ledger.lancamentos()  # o livro inteiro continua carregando

    minhas = pg.pagto[0].get("/v1/me/compensacoes", headers=pg.token("profissional")).json()
    assert minhas[0]["restante_centavos"] == 0
    cancelar = f"{PAINEL}/{r.divida_id}/cancelar"
    corpo = {"motivo": "Contestação do profissional aceita."}
    assert _post(pg, "cliente", cancelar, corpo).status_code == 403
    assert _post(pg, "med_a", cancelar, corpo).status_code == 403  # mediador não cancela
    primeira = _post(pg, "adm_a", cancelar, corpo)
    assert primeira.status_code == 200, primeira.text
    assert primeira.json()["devolvido_centavos"] == PARTE
    assert _post(pg, "adm_a", cancelar, corpo).json()["resultado"] == "ja_cancelada"
    assert disponivel_do_profissional(pg, novo) == VALOR_ORCAMENTO
    assert contexto.ledger.lancamentos(novo) and contexto.ledger.lancamentos(antigo)
    zerar(pg)


def test_painel_registra_pela_contestacao_e_cria_a_ordem_de_estorno(pg, equipe, avisos):  # noqa: F811
    if not tem_funcao_com_operador(pg):
        pytest.skip("Depende da migration do Banco: compensacao_registrar_disputa com p_operador.")
    zerar(pg)
    pid, cobranca = agendado(pg)
    check_in(pg, pid)
    http = pg.pagto[0]
    disputa = {
        "motivo": "mal_feito",
        "descricao": "Parede manchada.",
        "fotos": [],
    }
    r = _post(pg, "cliente", f"/v1/pedidos/{pid}/disputa", disputa)
    assert r.status_code == 201, r.text
    assert _post(pg, "profissional", f"/v1/pedidos/{pid}/disputa/resposta", None).status_code == 200
    decisao = {"resultado": "liberar_tudo", "justificativa": "Serviço entregue como combinado."}
    r = _post(pg, "med_a", f"/v1/admin/disputas/{pid}/decisao", decisao)
    assert r.status_code == 200, r.text
    liberar(pg, pid, timedelta(days=15))
    corpo = {"pedido_id": pid, "valor_centavos": PARTE, "motivo": "Revisão: dano comprovado."}
    nada = _post(pg, "med_a", PAINEL, corpo)  # a decisão original não manda reembolsar
    assert nada.status_code == 422 and nada.json()["codigo"] == "acima_do_devido", nada.text
    ((disputa_id,),) = linhas(
        pg,
        "select d.id::text from public.disputas d join public.contratos k on k.id = d.contrato_id "
        "where k.pedido_id = %s",
        (pid,),
    )
    contestacao = str(uuid.uuid4())
    _no_passado(
        pg,
        "insert into public.disputa_contestacoes (id, protocolo, disputa_id, pedido_id, "
        "contestante_id, o_que_faltou, canal, contestar_ate, responder_ate, status, analista_id, "
        "resposta, nova_decisao, novo_valor_reembolso_centavos, aprovada_por, decidida_em, "
        "efeito_financeiro) values (%s, 'CDS-2026-990001', %s, %s, %s, 'Fotos', 'app', "
        "now() + interval '5 days', now() + interval '10 days', 'alterada', %s, 'Procede.', "
        "'reembolso_parcial', %s, %s, now(), 'pendente_financeiro')",
        (contestacao, disputa_id, pid, pg.ids["cliente"], pg.ids["med_b"], PARTE,
         pg.ids["adm_b"]),
    )  # fmt: skip
    corpo["contestacao_id"] = contestacao
    assert _post(pg, "cliente", PAINEL, corpo).status_code == 403
    r = _post(pg, "med_a", PAINEL, corpo)
    assert r.status_code == 200, r.text
    assert r.json()["resultado"] == "ok" and r.json()["avisado"] is True
    ((ator,),) = linhas(  # A1: a auditoria fica em quem registrou, não em quem decidiu
        pg,
        "select ator_id::text from public.auditoria where acao = "
        "'financeiro.compensacao_registrada' and entidade_id = %s",
        (r.json()["compensacao"]["id"],),
    )
    assert ator == pg.ids["med_a"]
    r2 = _post(pg, "med_a", PAINEL, corpo)
    assert r2.json()["resultado"] == "ja_registrada", r2.text
    outro = _post(pg, "med_a", PAINEL, corpo | {"valor_centavos": PARTE - 1})
    assert outro.status_code == 409 and outro.json()["codigo"] == "conflito"
    servico = pg.pagto[2]
    assert [o.valor_centavos for o in servico.ordens.do_pedido(pid)] == [PARTE]
    assert [e.valor_centavos for e in servico.provedor.estornos_da_cobranca(cobranca)] == [PARTE]
    assert http.get(PAINEL, headers=pg.token("med_a")).json()["total"] == 1
    zerar(pg)


def test_sem_as_funcoes_a_liberacao_segue_como_antes(pg, equipe):  # noqa: F811
    mudar = "alter function public.compensacao_aplicar(uuid, text) rename to {}"
    voltar = "alter function public.compensacao_fora(uuid, text) rename to compensacao_aplicar"
    pid = concluido(pg)
    with pg.local.admin() as con:
        con.execute(mudar.format("compensacao_fora"))
    try:
        liberar(pg, pid)
        assert disponivel_do_profissional(pg, pid) == VALOR_ORCAMENTO
        r = pg.pagto[0].get(PAINEL, headers=pg.token("med_a"))
        assert r.status_code == 503 and r.json()["codigo"] == "indisponivel"
    finally:
        with pg.local.admin() as con:
            con.execute(voltar)


def _segmento(marca: int, corpo: bytes) -> bytes:
    return bytes([0xFF, marca]) + struct.pack(">H", len(corpo) + 2) + corpo


JPEG = (
    bytes([0xFF, 0xD8])
    + _segmento(0xE0, b"JFIF" + bytes([0, 1, 1, 0, 0, 1, 0, 1, 0, 0]))
    + _segmento(0xC0, bytes([8, 0, 16, 0, 16, 1, 1, 17, 0]))
    + bytes([0xFF, 0xDA, 0, 8, 1, 1, 0, 0, 63, 0])
    + b"DADOS"
    + bytes([0xFF, 0xD9])
)


def test_foto_da_chegada_fica_gravada(pg, monkeypatch):  # noqa: F811
    pid, _ = agendado(pg)
    agora = datetime.now(UTC)
    _no_passado(
        pg,
        "update public.agendamentos ag set janela_inicio = %s, janela_fim = %s, data = %s "
        "from public.contratos k where k.id = ag.contrato_id and k.pedido_id = %s",
        (agora - timedelta(minutes=30), agora + timedelta(hours=2), agora.date(), pid),
    )
    servico = ServicoUploads(
        ArmazenamentoFake(), UploadsPostgres(pg.banco), obter_config_seguranca(),
        ConfigUploads(), lambda: datetime.now(UTC),
    )  # fmt: skip
    monkeypatch.setattr(pg.pagto[0].app.state, "servico_uploads", servico, raising=False)
    prof = pg.ids["profissional"]
    sol, _ = servico.pedir(prof, "checkin", "image/jpeg", len(JPEG), "c.jpg", pedido_id=pid)
    servico.armazenamento.simular_envio(sol.bucket, sol.caminho, JPEG)
    midia = servico.concluir(prof, sol.id).registro_id
    corpo = {
        "foto": {"arquivo_id": midia, "tirada_em": agora.isoformat()},
        "localizacao": {"latitude": -19.9, "longitude": -43.9},
    }
    url = f"/v1/pedidos/{pid}/ausencia/chegada"
    for _ in range(2):
        r = _post(pg, "profissional", url, corpo)
        assert r.status_code == 200, r.text
    ((gravada,),) = linhas(
        pg,
        "select foto_chegada_midia_id::text from public.ausencias_cliente where pedido_id = %s",
        (pid,),
    )
    assert gravada.replace("-", "") == midia.replace("-", "")
