"""FIX-77 (Termos 7.7): profissional não compareceu = o cliente recebe de volta TUDO o que está
retido. Agendador e rotas reais, repositórios em memória e provedor falso."""

from __future__ import annotations

import threading
from dataclasses import replace
from datetime import timedelta

from conftest import AGORA, CLIENTE, PROFISSIONAL
from test_fluxo_pagamento_e2e import VALOR, Fluxo, fluxo  # noqa: F401 - `fluxo` é fixture
from test_moedas_pix_reserva import _cobrar, _ligar, _pagar

from trato.agendador import Agendador
from trato.agendador.executor import ExecutorContexto, FonteContexto, ids_ativos_memoria
from trato.agendador.registro import RegistroEmMemoria
from trato.agendador.trava import TravaEmMemoria
from trato.api.moedas import chave_reserva, situacao_reserva
from trato.financeiro.ledger import CUSTODIA, TipoLancamento, a_liberar
from trato.pagamentos.custo import MeioPagamento
from trato.pagamentos.modelos import Aditivo, EstadoAditivo, EstadoCobranca
from trato.pagamentos.provedor import TipoEvento
from trato.pedidos.estados import Acao, Estado, Janela
from trato.rotinas.regras import AcaoRotina, TipoAcaoRotina

ADITIVO = 20_000


def agendador(f: Fluxo) -> Agendador:
    """Um agendador "novo em folha" (outra máquina: registro e trava próprios)."""
    trava = type("TravaLivre", (TravaEmMemoria,), {"_ocupadas": set()})()
    return Agendador(
        FonteContexto(f.ctx, ids_ativos_memoria(f.ctx)),
        ExecutorContexto(f.ctx),
        RegistroEmMemoria(),
        trava,
        f.amb.relogio,
    )


def acao_de_ausencia(pid: str) -> AcaoRotina:
    return AcaoRotina(
        TipoAcaoRotina.TRANSICIONAR, pid, f"ausencia:{pid}", acao=Acao.REGISTRAR_AUSENCIA
    )


def pedido_pago_e_agendado(f: Fluxo) -> tuple[str, dict]:
    pid = f.aceitar()
    cobranca = f.pagar(pid)
    f.agendar(pid)
    return pid, cobranca


def aditivo_aprovado(f: Fluxo, pid: str, *, pago: bool):
    aditivo = Aditivo(
        "ad-1", pid, "Peça extra", ADITIVO, EstadoAditivo.APROVADO, f.amb.relogio.agora
    )
    f.servico.aditivos.salvar(aditivo)
    cobranca = f.servico.cobrar(
        f.ctx, f.ctx.pedidos.obter(pid), ADITIVO, MeioPagamento.PIX, aditivo.id
    )
    if pago:
        f.fake.marcar_paga(cobranca.id)
        assert f.webhook(TipoEvento.PAGAMENTO_CONFIRMADO, cobranca.id).status_code == 200
    return cobranca


def vencer_a_tolerancia(f: Fluxo) -> None:
    f.amb.relogio.avancar(days=3)  # a janela é daqui a 2 dias; tolerância de 1 h


def estornos_no_provedor(f: Fluxo) -> list[str]:
    return [chave for nome, chave in f.fake.chamadas if nome == "estornar"]


def test_ausencia_do_profissional_devolve_tudo_que_esta_retido(fluxo: Fluxo):  # noqa: F811
    pid, cobranca = pedido_pago_e_agendado(fluxo)
    assert fluxo.ctx.ledger.saldo_da_conta(CUSTODIA, pid) == VALOR
    vencer_a_tolerancia(fluxo)

    assert agendador(fluxo).rodar_uma_vez().falhas == 0

    assert fluxo.ctx.pedidos.obter(pid).estado is Estado.CANCELADO
    saldo = fluxo.saldo(pid)
    assert saldo["retido_centavos"] == 0 and saldo["cliente_pagou_centavos"] == 0
    assert fluxo.ctx.ledger.saldo_da_conta(a_liberar(PROFISSIONAL.id), pid) == 0
    assert list(fluxo.ctx.repasses.do_pedido(pid)) == []  # nada para o profissional
    (ordem,) = fluxo.servico.ordens.do_pedido(pid)
    assert ordem.valor_centavos == VALOR and ordem.estado == "enviada"
    assert ordem.chave == f"din/{pid}/ausencia/{cobranca['id']}"
    assert estornos_no_provedor(fluxo) == [ordem.chave]
    assert fluxo.servico.cobrancas.obter(cobranca["id"]).estornado_centavos == VALOR
    assert TipoLancamento.ESTORNO in fluxo.tipos(pid)
    fluxo.ctx.ledger.livro.verificar_partidas()


def test_ausencia_devolve_principal_e_o_aditivo_pago_fora_da_execucao_ja_voltou(
    fluxo: Fluxo,  # noqa: F811
):
    """Termos 6.8: aditivo é trabalho extra surgido DURANTE o serviço. Com o pedido ainda
    agendado ele nem pode ser proposto, e nenhum caminho volta do serviço iniciado para
    agendado. A cobrança aqui é forçada (defesa): paga fora da execução, volta inteira."""
    pid, principal = pedido_pago_e_agendado(fluxo)
    corpo = {"descricao": "Peça extra", "valor_centavos": ADITIVO}
    r = fluxo.chamar("POST", f"/v1/pedidos/{pid}/aditivos", "t-prof", corpo)
    assert r.status_code == 409, r.text

    extra = aditivo_aprovado(fluxo, pid, pago=True)
    assert fluxo.ctx.ledger.saldo_da_conta(CUSTODIA, pid) == VALOR  # o extra não entrou
    devolvida = fluxo.servico.cobrancas.obter(extra.id)
    assert devolvida.status is EstadoCobranca.DEVOLVIDA
    assert devolvida.estornado_centavos == ADITIVO
    assert estornos_no_provedor(fluxo) == [f"orfao/{extra.id}"]
    assert [e.valor_centavos for e in fluxo.fake.estornos_da_cobranca(extra.id)] == [ADITIVO]
    assert fluxo.webhook(TipoEvento.PAGAMENTO_CONFIRMADO, extra.id).status_code == 200
    assert estornos_no_provedor(fluxo) == [f"orfao/{extra.id}"]  # repetir não devolve de novo
    vencer_a_tolerancia(fluxo)

    agendador(fluxo).rodar_uma_vez()

    assert fluxo.ctx.pedidos.obter(pid).estado is Estado.CANCELADO
    assert fluxo.ctx.ledger.saldo_da_conta(CUSTODIA, pid) == 0
    assert fluxo.ctx.ledger.saldo_da_conta(a_liberar(PROFISSIONAL.id), pid) == 0
    ordens = {o.cobranca_id: o.valor_centavos for o in fluxo.servico.ordens.do_pedido(pid)}
    assert ordens == {principal["id"]: VALOR}
    assert len(estornos_no_provedor(fluxo)) == 2  # a órfã do extra e o principal
    assert fluxo.servico.cobrancas.obter(principal["id"]).estornado_centavos == VALOR
    fluxo.ctx.ledger.livro.verificar_partidas()


def test_ausencia_cancela_cobranca_pendente_sem_estornar_ela(fluxo: Fluxo):  # noqa: F811
    pid, principal = pedido_pago_e_agendado(fluxo)
    pendente = aditivo_aprovado(fluxo, pid, pago=False)
    vencer_a_tolerancia(fluxo)

    agendador(fluxo).rodar_uma_vez()

    assert fluxo.servico.cobrancas.obter(pendente.id).status is EstadoCobranca.CANCELADA
    assert [o.cobranca_id for o in fluxo.servico.ordens.do_pedido(pid)] == [principal["id"]]


def test_ausencia_devolve_tratinhos_da_cobranca_paga(fluxo: Fluxo):  # noqa: F811
    repo = _ligar(fluxo)
    pid = fluxo.aceitar()
    cob = _cobrar(fluxo, pid).json()
    _pagar(fluxo, cob["cobranca_id"])
    assert repo.saldo(CLIENTE.id, fluxo.amb.relogio.agora) < 5_000
    fluxo.agendar(pid)
    vencer_a_tolerancia(fluxo)

    agendador(fluxo).rodar_uma_vez()

    assert repo.saldo(CLIENTE.id, fluxo.amb.relogio.agora) == 5_000
    assert situacao_reserva(repo, cobranca_id=cob["cobranca_id"]) == "devolvida"
    assert fluxo.ctx.ledger.saldo_da_conta(CUSTODIA, pid) == 0


def test_ausencia_devolve_reserva_de_cobranca_pendente(fluxo: Fluxo):  # noqa: F811
    repo = _ligar(fluxo)
    pid = fluxo.aceitar()
    cob = _cobrar(fluxo, pid).json()
    assert repo._reservas[chave_reserva(cob["cobranca_id"])].status == "reservada"
    # pedido agendado com a cobrança ainda pendente (o caminho da ausência é o mesmo)
    pedido = fluxo.ctx.pedidos.obter(pid)
    inicio = AGORA + timedelta(days=2)
    fluxo.ctx.pedidos.salvar(
        replace(pedido, estado=Estado.AGENDADO, janela=Janela(inicio, inicio + timedelta(hours=3)))
    )
    vencer_a_tolerancia(fluxo)

    agendador(fluxo).rodar_uma_vez()

    assert situacao_reserva(repo, cobranca_id=cob["cobranca_id"]) == "devolvida"
    assert fluxo.servico.cobrancas.obter(cob["cobranca_id"]).status is EstadoCobranca.CANCELADA
    assert estornos_no_provedor(fluxo) == []


def test_rodar_duas_vezes_ou_em_duas_maquinas_estorna_uma_vez(fluxo: Fluxo):  # noqa: F811
    pid, _ = pedido_pago_e_agendado(fluxo)
    vencer_a_tolerancia(fluxo)
    barreira, erros = threading.Barrier(2), []

    def maquina() -> None:
        executor = ExecutorContexto(fluxo.ctx)
        barreira.wait()
        try:
            executor.executar(acao_de_ausencia(pid), fluxo.amb.relogio.agora)
        except Exception as erro:  # noqa: BLE001 - perder a corrida é conflito de estado
            erros.append(type(erro).__name__)

    fios = [threading.Thread(target=maquina) for _ in range(2)]
    [f.start() for f in fios]
    [f.join(20) for f in fios]
    agendador(fluxo).rodar_uma_vez()
    agendador(fluxo).rodar_uma_vez()
    ExecutorContexto(fluxo.ctx).executar(acao_de_ausencia(pid), fluxo.amb.relogio.agora)

    assert set(erros) <= {"ConflitoDeEstado"}
    assert len(fluxo.servico.ordens.do_pedido(pid)) == 1
    assert len(estornos_no_provedor(fluxo)) == 1
    assert fluxo.tipos(pid).count(TipoLancamento.ESTORNO) == 1
    assert fluxo.saldo(pid)["cliente_pagou_centavos"] == 0


def test_falha_do_provedor_mantem_a_ordem_pendente(fluxo: Fluxo, monkeypatch):  # noqa: F811
    pid, _ = pedido_pago_e_agendado(fluxo)
    vencer_a_tolerancia(fluxo)
    original = fluxo.fake.estornar

    def fora_do_ar(*args, **kwargs):
        raise RuntimeError("provedor fora do ar")

    monkeypatch.setattr(fluxo.fake, "estornar", fora_do_ar)
    assert agendador(fluxo).rodar_uma_vez().falhas == 0
    assert fluxo.ctx.pedidos.obter(pid).estado is Estado.CANCELADO
    assert fluxo.ctx.ledger.saldo_da_conta(CUSTODIA, pid) == 0  # a intenção está no ledger
    (ordem,) = fluxo.servico.ordens.pendentes(pid)
    assert ordem.valor_centavos == VALOR

    # Sem a rotina de estornos ligada o agendador não reenvia; `reenviar_estornos` completa.
    monkeypatch.setattr(fluxo.fake, "estornar", original)
    agendador(fluxo).rodar_uma_vez()
    assert len(fluxo.servico.ordens.pendentes(pid)) == 1
    assert fluxo.servico.reenviar_estornos(pid) == 1
    assert fluxo.servico.reenviar_estornos(pid) == 0
    assert len(estornos_no_provedor(fluxo)) == 1


def test_pedido_sem_pagamento_nao_estorna(fluxo: Fluxo):  # noqa: F811
    inicio = AGORA - timedelta(days=1)
    fluxo.amb.semear_pedido(Estado.AGENDADO, janela=Janela(inicio, inicio + timedelta(hours=2)))

    assert agendador(fluxo).rodar_uma_vez().falhas == 0

    assert fluxo.ctx.pedidos.obter("ped-1").estado is Estado.CANCELADO
    assert fluxo.ctx.ledger.lancamentos("ped-1") == () or not list(
        fluxo.ctx.ledger.lancamentos("ped-1")
    )
    assert list(fluxo.servico.ordens.do_pedido("ped-1")) == []
    assert estornos_no_provedor(fluxo) == []


def test_cliente_ausente_registrado_continua_bloqueando(fluxo: Fluxo):  # noqa: F811
    pid, _ = pedido_pago_e_agendado(fluxo)
    vencer_a_tolerancia(fluxo)
    # a ação já estava planejada quando a chegada foi registrada
    pedido = fluxo.ctx.pedidos.obter(pid)
    fluxo.ctx.pedidos.salvar(replace(pedido, cliente_ausente_em=pedido.janela.inicio))

    ExecutorContexto(fluxo.ctx).executar(acao_de_ausencia(pid), fluxo.amb.relogio.agora)
    assert agendador(fluxo).rodar_uma_vez().executadas == 0

    assert fluxo.ctx.pedidos.obter(pid).estado is Estado.AGENDADO
    assert fluxo.ctx.ledger.saldo_da_conta(CUSTODIA, pid) == VALOR
    assert estornos_no_provedor(fluxo) == []


def test_cancelamento_comum_segue_igual(fluxo: Fluxo):  # noqa: F811
    pid, cobranca = pedido_pago_e_agendado(fluxo)
    r = fluxo.acao(pid, "cancelar", "t-cliente", {"motivo": "Desisti"})
    assert r.status_code == 200, r.text
    (ordem,) = fluxo.servico.ordens.do_pedido(pid)
    assert ordem.chave == f"din/{pid}/cancelamento/{cobranca['id']}"
    assert ordem.valor_centavos == VALOR
    vencer_a_tolerancia(fluxo)
    assert agendador(fluxo).rodar_uma_vez().executadas == 0  # cancelado não vira ausência
    assert len(estornos_no_provedor(fluxo)) == 1
