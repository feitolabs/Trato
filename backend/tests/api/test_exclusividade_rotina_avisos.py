"""Etapa B, rodada 2 (B4b): rotina de expiração no agendador e notificações da exclusividade."""

from __future__ import annotations

from conftest import AGORA, CLIENTE, OUTRO_PROFISSIONAL, PROFISSIONAL, cab

from trato.agendador import Agendador
from trato.agendador.executor import ExecutorContexto, FonteContexto, ids_ativos_memoria
from trato.agendador.registro import RegistroEmMemoria
from trato.agendador.trava import TravaEmMemoria
from trato.api.exclusividades import Expirada
from trato.api.moedas import ConfigMoedas, LancamentoMoeda, MoedasEmMemoria, saldo_profissional
from trato.api.repositorios import DadosPedido
from trato.notificacoes import ligar_ao_contexto
from trato.notificacoes.canais import Canais, CanalApp
from trato.notificacoes.config import ConfigNotificacoes
from trato.notificacoes.eventos import MODELOS, Evento
from trato.notificacoes.repositorio import RepositorioEmMemoria
from trato.notificacoes.servico import ServicoNotificacoes
from trato.pedidos.estados import Estado as E

PRO, OUTRO_PRO = PROFISSIONAL.id, OUTRO_PROFISSIONAL.id


def _ligar(amb, saldo=300, outro_saldo=0):
    amb.contexto.moedas = MoedasEmMemoria(ConfigMoedas(ativo=True))
    for quem, valor in ((PRO, saldo), (OUTRO_PRO, outro_saldo)):
        if valor:
            amb.contexto.moedas.lancamentos_teste = True
            amb.contexto.moedas.lancar(
                LancamentoMoeda(
                    quem,
                    "bonus_avaliacao_profissional",
                    valor,
                    f"b:{quem}",
                    AGORA,
                    carteira="profissional",
                )
            )


def _pedido(amb, pid="ped-1"):
    amb.semear_pedido(E.ABERTO, id=pid)
    amb.contexto.pedidos._dados[pid] = DadosPedido("cat-1", "cid", "Pintar", "Sala")
    return pid


def _pedir(amb, quem="t-prof", pid="ped-1", chave="k1"):
    return amb.cliente.post(
        "/v1/profissional/exclusividades",
        json={"pedido_id": pid, "chave_idempotencia": chave},
        headers=cab(quem),
    )


def _responder(amb, eid, decisao, quem="t-cliente", pid="ped-1"):
    return amb.cliente.post(
        f"/v1/pedidos/{pid}/exclusividade/{eid}/responder",
        json={"decisao": decisao},
        headers=cab(quem),
    )


def _orcar(amb, quem="t-prof", pid="ped-1"):
    corpo = {
        "itens": [
            {
                "tipo": "horas",
                "descricao": "Pintura",
                "quantidade": 1,
                "valor_unitario_centavos": 10_000,
            }
        ]
    }
    return amb.cliente.post(f"/v1/pedidos/{pid}/orcamentos", json=corpo, headers=cab(quem))


def _notas(amb, quem="t-cliente"):
    return amb.cliente.get("/v1/notificacoes", headers=cab(quem)).json()


def _montar_agendador(amb, *, notif=None, rotina_moedas=None, rotina_reservas=None):
    if notif is None:
        notif = ServicoNotificacoes(
            RepositorioEmMemoria(),
            Canais(CanalApp()),
            ConfigNotificacoes(_env_file=None),
            amb.relogio,
        )
    ligar_ao_contexto(amb.cliente.app, amb.contexto, notif)
    executor = ExecutorContexto(amb.contexto, notif)
    agendador = Agendador(
        FonteContexto(amb.contexto, ids_ativos_memoria(amb.contexto)),
        executor,
        RegistroEmMemoria(),
        TravaEmMemoria(),
        amb.relogio,
        notif,
        rotina_moedas=rotina_moedas,
        rotina_reservas=rotina_reservas,
        rotina_exclusividades=executor.expirar_exclusividades,
    )
    return agendador, notif, executor


# --- eventos das rotas (solicitar, responder, encerrar) ------------------------------------------


def test_solicitar_notifica_cliente_com_hora_e_sem_compromisso(amb):
    _ligar(amb)
    _pedido(amb)
    r = _pedir(amb)
    assert r.status_code == 201
    [nota] = _notas(amb, "t-cliente")
    assert nota["tipo"] == Evento.EXCLUSIVIDADE_OFERTA.value
    assert "Sem compromisso" in nota["corpo"]
    # AGORA é 12:00 UTC -> +6h = 18:00 UTC = 15:00 em America/Sao_Paulo
    assert "15:00" in nota["corpo"]
    assert nota["dados"]["pedido_id"] == "ped-1"


def test_responder_aceitar_e_recusar_notificam_profissional(amb):
    _ligar(amb)
    _pedido(amb, "ped-1")
    eid1 = _pedir(amb, pid="ped-1", chave="k1").json()["id"]
    assert _responder(amb, eid1, "aceitar", pid="ped-1").status_code == 200
    notas_aceite = [n for n in _notas(amb, "t-prof") if n["tipo"] == Evento.EXCLUSIVIDADE_ACEITA]
    assert len(notas_aceite) == 1
    assert "prioridade que você ganhou avaliando" in notas_aceite[0]["corpo"]

    _pedido(amb, "ped-2")
    eid2 = _pedir(amb, pid="ped-2", chave="k2").json()["id"]
    assert _responder(amb, eid2, "recusar", pid="ped-2").status_code == 200
    notas_recusa = [n for n in _notas(amb, "t-prof") if n["tipo"] == Evento.EXCLUSIVIDADE_RECUSADA]
    assert len(notas_recusa) == 1
    assert (
        "O cliente preferiu ver outros orçamentos. Seus 100 Tratinhos voltaram."
        == (notas_recusa[0]["corpo"])
    )


def test_encerrar_por_cancelamento_ou_outro_orcamento_notifica_profissional(amb):
    _ligar(amb, saldo=300, outro_saldo=300)
    _pedido(amb, "ped-1")
    _pedir(amb, pid="ped-1", chave="k1")
    cancel = amb.cliente.post(
        "/v1/pedidos/ped-1/acoes/cancelar",
        json={"prova": {"motivo": "desisti"}},
        headers=cab("t-cliente"),
    )
    assert cancel.status_code == 200
    notas_cancel = [n for n in _notas(amb, "t-prof") if n["tipo"] == Evento.EXCLUSIVIDADE_CANCELADA]
    assert len(notas_cancel) == 1
    assert "100 Tratinhos" in notas_cancel[0]["corpo"]

    # Cliente aceita orçamento de outro profissional durante oferta pendente: cancela com aviso.
    _pedido(amb, "ped-2")
    orc_outro = _orcar(amb, "t-outro-prof", pid="ped-2").json()
    _pedir(amb, pid="ped-2", chave="k2")
    aceite_outro = amb.cliente.post(
        "/v1/pedidos/ped-2/acoes/aceitar_orcamento",
        json={"prova": {"orcamento_id": orc_outro["id"]}},
        headers=cab("t-cliente"),
    )
    assert aceite_outro.status_code == 200
    notas_cancel = [n for n in _notas(amb, "t-prof") if n["tipo"] == Evento.EXCLUSIVIDADE_CANCELADA]
    assert len(notas_cancel) == 2

    # Cliente aceita o orçamento do exclusivo: NÃO manda exclusividade.cancelada.
    _pedido(amb, "ped-3")
    eid3 = _pedir(amb, pid="ped-3", chave="k3").json()["id"]
    _responder(amb, eid3, "aceitar", pid="ped-3")
    orc_pro = _orcar(amb, "t-prof", pid="ped-3").json()
    aceite_pro = amb.cliente.post(
        "/v1/pedidos/ped-3/acoes/aceitar_orcamento",
        json={"prova": {"orcamento_id": orc_pro["id"]}},
        headers=cab("t-cliente"),
    )
    assert aceite_pro.status_code == 200
    notas_cancel = [n for n in _notas(amb, "t-prof") if n["tipo"] == Evento.EXCLUSIVIDADE_CANCELADA]
    assert len(notas_cancel) == 2


# --- rotina de expiração no agendador ------------------------------------------------------------


def test_expiracao_sem_resposta_estorna_1_vez_e_notifica_1_vez(amb):
    _ligar(amb, saldo=300)
    _pedido(amb)
    agendador, notif, _ = _montar_agendador(amb)
    assert _pedir(amb).status_code == 201
    assert saldo_profissional(amb.contexto.moedas, PRO, amb.relogio.agora) == 200

    amb.relogio.avancar(hours=7)
    r1 = agendador.rodar_uma_vez()
    assert r1.exclusividades_expiradas == 1
    assert saldo_profissional(amb.contexto.moedas, PRO, amb.relogio.agora) == 300
    notas_pro = [
        n
        for n in notif.repo.listar(PRO, False, 20)
        if n.tipo == Evento.EXCLUSIVIDADE_EXPIRADA_SEM_RESPOSTA
    ]
    assert len(notas_pro) == 1
    assert "100 Tratinhos" in (notas_pro[0].corpo or "")

    # Ciclo repetido não duplica estorno nem notificação.
    r2 = agendador.rodar_uma_vez()
    assert r2.exclusividades_expiradas == 0
    assert saldo_profissional(amb.contexto.moedas, PRO, amb.relogio.agora) == 300
    notas_pro = [
        n
        for n in notif.repo.listar(PRO, False, 20)
        if n.tipo == Evento.EXCLUSIVIDADE_EXPIRADA_SEM_RESPOSTA
    ]
    assert len(notas_pro) == 1


def test_expiracao_48h_reabre_pedido_sem_estorno_e_notifica_profissional_e_cliente(amb):
    _ligar(amb, saldo=300)
    _pedido(amb)
    agendador, notif, _ = _montar_agendador(amb)
    eid = _pedir(amb).json()["id"]
    assert _responder(amb, eid, "aceitar").status_code == 200
    assert amb.contexto.pedidos.obter("ped-1").estado is E.RESERVADO

    amb.relogio.avancar(hours=49)
    r1 = agendador.rodar_uma_vez()
    assert r1.exclusividades_expiradas == 1
    assert amb.contexto.pedidos.obter("ped-1").estado is E.ABERTO
    assert saldo_profissional(amb.contexto.moedas, PRO, amb.relogio.agora) == 200  # sem estorno

    notas_pro = [
        n
        for n in notif.repo.listar(PRO, False, 20)
        if n.tipo == Evento.EXCLUSIVIDADE_EXPIRADA_48H_PROFISSIONAL
    ]
    notas_cli = [
        n
        for n in notif.repo.listar(CLIENTE.id, False, 20)
        if n.tipo == Evento.EXCLUSIVIDADE_EXPIRADA_48H_CLIENTE
    ]
    assert len(notas_pro) == 1
    assert "48h" in (notas_pro[0].corpo or "")
    assert len(notas_cli) == 1
    assert notas_cli[0].corpo == "Seu pedido voltou a receber orçamentos de outros profissionais."

    # Segundo ciclo não duplica.
    assert agendador.rodar_uma_vez().exclusividades_expiradas == 0
    assert (
        len(
            [
                n
                for n in notif.repo.listar(CLIENTE.id, False, 20)
                if n.tipo == Evento.EXCLUSIVIDADE_EXPIRADA_48H_CLIENTE
            ]
        )
        == 1
    )


def test_chave_idempotente_nao_duplica_notificacao_mesmo_se_linha_repetir(amb):
    _ligar(amb, saldo=300)
    _pedido(amb)
    _, notif, executor = _montar_agendador(amb)

    class RepoRepetido:
        def expirar(self, agora):
            return [Expirada("exc-1", "sem_resposta", PRO, CLIENTE.id, "ped-1")]

    amb.contexto.exclusividades = RepoRepetido()
    assert executor.expirar_exclusividades(AGORA) == 1
    assert executor.expirar_exclusividades(AGORA) == 1
    notas = [
        n
        for n in notif.repo.listar(PRO, False, 20)
        if n.tipo == Evento.EXCLUSIVIDADE_EXPIRADA_SEM_RESPOSTA
    ]
    assert len(notas) == 1


def test_falha_na_notificacao_nao_impede_estorno_nem_acao(amb):
    _ligar(amb, saldo=300)
    _pedido(amb)

    class NotifQuebrada:
        def notificar(self, *args, **kwargs):
            raise RuntimeError("push fora do ar")

        def reenviar_pendentes(self):
            return 0

    agendador, _, _ = _montar_agendador(amb, notif=NotifQuebrada())
    assert _pedir(amb).status_code == 201  # solicitar segue mesmo com notificação quebrada
    amb.relogio.avancar(hours=7)
    r = agendador.rodar_uma_vez()
    assert r.exclusividades_expiradas == 1
    assert saldo_profissional(amb.contexto.moedas, PRO, amb.relogio.agora) == 300


def test_ciclo_agendador_tolerante_a_falha_entre_rotinas(amb):
    _ligar(amb, saldo=300)
    _pedido(amb)
    assert _pedir(amb).status_code == 201
    amb.relogio.avancar(hours=7)

    def rotina_quebrada(_agora):
        raise RuntimeError("falha simulada noutra rotina")

    agendador, _, _ = _montar_agendador(
        amb, rotina_moedas=rotina_quebrada, rotina_reservas=rotina_quebrada
    )
    r = agendador.rodar_uma_vez()
    assert r.exclusividades_expiradas == 1
    assert saldo_profissional(amb.contexto.moedas, PRO, amb.relogio.agora) == 300

    # E o inverso: falha na exclusividade não derruba o resto do ciclo.
    agendador_ok = Agendador(
        FonteContexto(amb.contexto, ids_ativos_memoria(amb.contexto)),
        ExecutorContexto(amb.contexto),
        RegistroEmMemoria(),
        TravaEmMemoria(),
        amb.relogio,
        rotina_moedas=lambda _agora: 2,
        rotina_exclusividades=rotina_quebrada,
    )
    r2 = agendador_ok.rodar_uma_vez()
    assert r2.bonus_liberados == 2 and r2.exclusividades_expiradas == 0


def test_textos_exclusividade_respeitam_regras_de_linguagem():
    for ev, modelo in MODELOS.items():
        if not ev.value.startswith("exclusividade."):
            continue
        texto = f"{modelo.titulo} {modelo.corpo}".lower()
        assert "comprar cliente" not in texto
        assert "r$" not in texto and "reais" not in texto
