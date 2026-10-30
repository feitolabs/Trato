"""Agendador em memória: rotinas reais, idempotência, relógio injetado e duas instâncias."""

from __future__ import annotations

import threading
from datetime import timedelta

from conftest import AGORA, CLIENTE, PROFISSIONAL

from trato.agendador import Agendador
from trato.agendador.executor import ExecutorContexto, FonteContexto, ids_ativos_memoria
from trato.agendador.registro import RegistroEmMemoria
from trato.agendador.trava import TravaEmMemoria, chave_advisory
from trato.financeiro.ledger import TipoLancamento
from trato.notificacoes import ligar_ao_contexto
from trato.notificacoes.canais import Canais, CanalApp
from trato.notificacoes.config import ConfigNotificacoes
from trato.notificacoes.repositorio import RepositorioEmMemoria
from trato.notificacoes.servico import ServicoNotificacoes
from trato.pedidos.estados import Estado
from trato.rotinas.regras import ConfigRotinas

H = timedelta(hours=1)
D = timedelta(days=1)


def montar(amb, complemento=None, **extra):
    notif = ServicoNotificacoes(
        RepositorioEmMemoria(), Canais(CanalApp()), ConfigNotificacoes(_env_file=None), amb.relogio
    )
    ligar_ao_contexto(amb.cliente.app, amb.contexto, notif)
    registro = extra.pop("registro", RegistroEmMemoria())
    executor = extra.pop("executor", ExecutorContexto(amb.contexto, notif))
    agendador = Agendador(
        FonteContexto(amb.contexto, ids_ativos_memoria(amb.contexto), complemento),
        executor,
        registro,
        extra.pop("trava", TravaEmMemoria()),
        amb.relogio,
        notif,
        **extra,
    )
    return agendador, notif, registro


def test_conclui_por_prazo_uma_unica_vez(amb):
    amb.semear_pedido(Estado.EM_CONFIRMACAO, check_out_em=AGORA - 8 * D)
    agendador, notif, _ = montar(amb)
    primeiro = agendador.rodar_uma_vez()
    assert primeiro.executadas == 1 and primeiro.falhas == 0
    assert amb.contexto.pedidos.obter("ped-1").estado is Estado.CONCLUIDO
    segundo = agendador.rodar_uma_vez()
    assert (segundo.executadas, segundo.repetidas, segundo.falhas) == (0, 0, 0)
    assert len(amb.contexto.pedidos.eventos("ped-1")) == 1


def test_nada_a_fazer_quando_o_prazo_nao_venceu(amb):
    amb.semear_pedido(Estado.EM_CONFIRMACAO, check_out_em=AGORA - 1 * D)
    agendador, _, _ = montar(amb)
    assert agendador.rodar_uma_vez().executadas == 0
    amb.relogio.avancar(days=7)  # o relógio injetado é quem manda
    assert agendador.rodar_uma_vez().executadas == 1


def test_libera_o_saldo_depois_do_prazo_e_nao_repete(amb):
    amb.semear_pedido(Estado.CONCLUIDO, concluido_em=AGORA - 10 * D)
    amb.semear_dinheiro(taxa=7_500)
    agendador, _, _ = montar(amb, ConfigRotinas(prazo_liberacao=7 * D))
    antes = amb.contexto.ledger.saldos_pedido("ped-1", PROFISSIONAL.id)
    assert antes.a_liberar == 92_500 and antes.liberado == 0
    assert agendador.rodar_uma_vez().executadas == 1
    depois = amb.contexto.ledger.saldos_pedido("ped-1", PROFISSIONAL.id)
    assert (depois.a_liberar, depois.liberado) == (0, 92_500)
    assert agendador.rodar_uma_vez().executadas == 0
    liberacoes = [
        x for x in amb.contexto.ledger.lancamentos("ped-1") if x.tipo is TipoLancamento.REPASSE
    ]
    assert len(liberacoes) == 1


def test_sem_prazo_configurado_a_rotina_fica_desligada(amb):
    amb.semear_pedido(Estado.CONCLUIDO, concluido_em=AGORA - 90 * D)
    amb.semear_dinheiro(taxa=7_500)
    agendador, _, _ = montar(amb)  # nenhum prazo_liberacao: nada de número fixo no código
    assert agendador.rodar_uma_vez().executadas == 0


def test_lembrete_de_confirmacao_vira_notificacao_uma_vez(amb):
    amb.semear_pedido(Estado.EM_CONFIRMACAO, check_out_em=AGORA - 30 * H)
    agendador, notif, _ = montar(amb, ConfigRotinas(lembrete_confirmacao_apos=24 * H))
    assert agendador.rodar_uma_vez().executadas == 1
    [nota] = notif.repo.listar(CLIENTE.id, False, 10)
    assert nota.tipo == "execucao.confirmar_conclusao" and nota.dados["pedido_id"] == "ped-1"
    agendador.rodar_uma_vez()
    assert len(notif.repo.listar(CLIENTE.id, False, 10)) == 1


def test_falha_numa_acao_nao_marca_e_tenta_de_novo(amb):
    amb.semear_pedido(Estado.EM_CONFIRMACAO, check_out_em=AGORA - 8 * D)

    class Instavel(ExecutorContexto):
        quebrar = True

        def executar(self, acao, agora):
            if self.quebrar:
                raise RuntimeError("banco caiu")
            super().executar(acao, agora)

    executor = Instavel(amb.contexto)
    agendador, _, registro = montar(amb, executor=executor)
    r1 = agendador.rodar_uma_vez()
    assert (r1.executadas, r1.falhas) == (0, 1) and registro.ja_executadas() == frozenset()
    executor.quebrar = False
    assert agendador.rodar_uma_vez().executadas == 1


def test_lembrete_de_agenda_so_com_antecedencia_configurada(amb):
    from trato.pedidos.estados import Janela

    amb.semear_pedido(Estado.AGENDADO, janela=Janela(AGORA + 5 * H, AGORA + 8 * H))
    sem, notif, _ = montar(amb)
    assert sem.rodar_uma_vez().lembretes_agenda == 0
    com, notif, _ = montar(amb, antecedencia_lembrete_agenda=6 * H)
    assert com.rodar_uma_vez().lembretes_agenda == 2  # cliente e profissional
    assert com.rodar_uma_vez().lembretes_agenda == 0  # idempotente
    assert notif.repo.listar(PROFISSIONAL.id, False, 5)[0].tipo == "agenda.lembrete"


def test_trava_impede_duas_instancias_ao_mesmo_tempo(amb):
    amb.semear_pedido(Estado.EM_CONFIRMACAO, check_out_em=AGORA - 8 * D)
    dentro, liberar = threading.Event(), threading.Event()
    execucoes = []

    class Lento(ExecutorContexto):
        def executar(self, acao, agora):
            execucoes.append(acao.chave)
            dentro.set()
            assert liberar.wait(5)
            super().executar(acao, agora)

    registro = RegistroEmMemoria()
    a, _, _ = montar(amb, executor=Lento(amb.contexto), registro=registro)
    b, _, _ = montar(amb, executor=Lento(amb.contexto), registro=registro)
    resultado = {}
    fio = threading.Thread(target=lambda: resultado.update(a=a.rodar_uma_vez()))
    fio.start()
    assert dentro.wait(5)
    segundo = b.rodar_uma_vez()  # a primeira ainda está no meio do ciclo
    liberar.set()
    fio.join(5)
    assert segundo.travado is True and segundo.executadas == 0
    assert resultado["a"].executadas == 1 and len(execucoes) == 1
    assert b.rodar_uma_vez().travado is False  # trava solta ao fim do ciclo


def test_duas_instancias_em_sequencia_nao_repetem_pela_chave(amb):
    amb.semear_pedido(Estado.CONCLUIDO, concluido_em=AGORA - 10 * D)
    amb.semear_dinheiro(taxa=7_500)
    registro = RegistroEmMemoria()
    a, _, _ = montar(amb, ConfigRotinas(prazo_liberacao=7 * D), registro=registro)
    b, _, _ = montar(amb, ConfigRotinas(prazo_liberacao=7 * D), registro=registro)
    assert a.rodar_uma_vez().executadas == 1
    assert b.rodar_uma_vez().executadas == 0


def test_chave_advisory_e_estavel_e_cabe_em_bigint():
    assert chave_advisory("trato-agendador") == chave_advisory("trato-agendador")
    assert chave_advisory("a") != chave_advisory("b")
    assert -(2**63) <= chave_advisory("trato-agendador") < 2**63


def test_rodar_sempre_para_quando_pedem(amb):
    agendador, _, _ = montar(amb)
    parar = threading.Event()
    ciclos = []
    original = agendador.rodar_uma_vez

    def contar():
        ciclos.append(1)
        parar.set()
        return original()

    agendador.rodar_uma_vez = contar
    agendador.rodar_sempre(parar, 0.01)
    assert ciclos == [1]
