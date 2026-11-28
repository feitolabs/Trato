"""BE-CHECKOUT-SEM-CODIGO-57 (fase 1, sem dinheiro): aviso app + e-mail, abertura do caso,
prazo de 5 dias úteis (Brasília + feriados + 22.3 na leitura), resposta ao confirmar ou relatar,
fila do painel, contato manual auditado e segurança sem a tabela."""

from __future__ import annotations

from dataclasses import replace
from datetime import UTC, date, datetime, timedelta

from conftest import AGORA, CLIENTE, PROFISSIONAL, cab
from test_checkin_checkout_sem_codigo import _foto, _loc, _montar_agendador

from trato.api.admin.repositorios import FiltroAuditoria
from trato.api.checkout_sem_codigo import CONFIRMOU, RELATOU
from trato.financeiro import periodo
from trato.financeiro.ledger import registrar_cobranca, repartir_custodia
from trato.notificacoes import ligar_ao_contexto
from trato.notificacoes.canais import Canais, CanalApp, CanalFake
from trato.notificacoes.config import ConfigNotificacoes
from trato.notificacoes.eventos import Evento
from trato.notificacoes.repositorio import RepositorioEmMemoria
from trato.notificacoes.servico import ServicoNotificacoes
from trato.pedidos.estados import Acao, Janela, ProvaRetrabalho
from trato.pedidos.estados import Estado as E
from trato.pedidos.estados import Evento as EventoPedido
from trato.persistencia.indisponibilidades import Janela as JanelaFalha

URL_FILA = "/v1/admin/checkout-sem-codigo"


class _EmailsFake:
    def __init__(self, mapa: dict[str, str]) -> None:
        self._mapa = mapa

    def email_de(self, usuario_id: str) -> str | None:
        return self._mapa.get(usuario_id)


def _ligar_notificador(amb, *, com_email: bool = True):
    email = CanalFake("email")
    canais = Canais(CanalApp(), email=email if com_email else None)
    emails = _EmailsFake({CLIENTE.id: "cliente@exemplo.com"}) if com_email else None
    notif = ServicoNotificacoes(
        RepositorioEmMemoria(),
        canais,
        ConfigNotificacoes(_env_file=None),
        amb.relogio,
        emails=emails,
    )
    ligar_ao_contexto(amb.cliente.app, amb.contexto, notif)
    return notif, email


def _semear_em_andamento(amb, pid: str = "ped-1"):
    amb.semear_pedido(
        E.EM_ANDAMENTO,
        id=pid,
        janela=Janela(
            amb.relogio.agora - timedelta(hours=1), amb.relogio.agora + timedelta(hours=1)
        ),
        check_in_em=amb.relogio.agora,
        codigo_inicio="1234",
        codigo_conclusao="5678",
    )
    livro = amb.contexto.ledger.livro
    registrar_cobranca(livro, pid, 100_000, f"cob-{pid}", amb.relogio.agora)
    repartir_custodia(livro, pid, PROFISSIONAL.id, 0, f"rep-{pid}", amb.relogio.agora)


def _checkout_sem_codigo(amb, pid: str = "ped-1"):
    return amb.cliente.post(
        f"/v1/pedidos/{pid}/acoes/fazer_check_out",
        json={
            "prova": {
                "foto_final": _foto(amb, f"foto-{pid}"),
                "localizacao": _loc(),
                "sem_codigo": True,
                "justificativa": "Cliente saiu antes do término.",
            }
        },
        headers=cab("t-prof"),
    )


def test_checkout_sem_codigo_abre_caso_avisa_app_e_email_e_calcula_prazo_com_feriado(amb):
    # Quinta 2026-11-12 10:00 Brasília (= 13:00 UTC); segunda 16/11 é feriado.
    # 5 dias úteis: sex 13 (1), ter 17 (2), qua 18 (3), qui 19 (4), sex 20 (5).
    amb.relogio.agora = datetime(2026, 11, 12, 13, 0, tzinfo=UTC)
    cfg = amb.contexto.config.carregar()
    cfg_feriado = replace(
        cfg,
        disputas=replace(cfg.disputas, feriados=frozenset({date(2026, 11, 16)})),
    )
    amb.contexto.config.carregar = lambda: cfg_feriado
    notif, email = _ligar_notificador(amb)
    # Mesmo com preferência de e-mail desligada, e-mail obrigatório precisa sair.
    notif.repo.salvar_preferencias(CLIENTE.id, {"pagamentos": {"email": False}}, amb.relogio.agora)
    _semear_em_andamento(amb)

    r = _checkout_sem_codigo(amb)
    assert r.status_code == 200, r.text

    # Aviso essencial no app + e-mail obrigatório
    avisos = [
        n
        for n in notif.repo.listar(CLIENTE.id, False, 20)
        if n.tipo == Evento.CHECKOUT_SEM_CODIGO.value
    ]
    assert len(avisos) == 1
    assert "20/11/2026" in avisos[0].corpo
    assert any(m.destinos == ("cliente@exemplo.com",) for m in email.enviados)

    casos = amb.contexto.checkout_sem_codigo.em_aberto()
    assert len(casos) == 1
    caso = casos[0]
    assert caso.canal == "app+email"
    assert caso.contatado_em == amb.relogio.agora
    assert caso.responder_ate == datetime(2026, 11, 20, 23, 59, 59, tzinfo=periodo.BRASILIA)

    # Prorrogação 22.3 na leitura (falha do app de 4h não altera o responder_ate gravado)
    amb.contexto.indisponibilidades.criar(
        JanelaFalha(
            id="falha-1",
            origem="app",
            inicio_em=datetime(2026, 11, 13, 14, 0, tzinfo=UTC),
            fim_em=datetime(2026, 11, 13, 18, 0, tzinfo=UTC),
            motivo="Instabilidade no aplicativo",
            criada_por="eq-adm",
        )
    )
    fila = amb.cliente.get(URL_FILA, headers=cab("t-mediador"))
    assert fila.status_code == 200, fila.text
    item = fila.json()["itens"][0]
    esperado_prorrogado = caso.responder_ate + timedelta(hours=4)
    assert datetime.fromisoformat(item["responder_ate"]) == esperado_prorrogado
    assert item["vencido"] is False
    assert amb.contexto.checkout_sem_codigo.obter(caso.id).responder_ate == caso.responder_ate


def test_config_prazo_aumenta_mas_nunca_abaixo_de_5_dias_uteis(amb):
    amb.relogio.agora = datetime(2026, 11, 12, 13, 0, tzinfo=UTC)
    _ligar_notificador(amb)

    # Valor configurado maior que 5 (7 dias úteis: 13, 16, 17, 18, 19, 20, 23)
    amb.contexto.config.parametro_inteiro = lambda c: (
        7 if c == "checkout_sem_codigo_resposta_dias_uteis" else None
    )
    _semear_em_andamento(amb, "ped-7")
    assert _checkout_sem_codigo(amb, "ped-7").status_code == 200
    c7 = [c for c in amb.contexto.checkout_sem_codigo.em_aberto() if c.pedido_id == "ped-7"][0]
    assert c7.responder_ate == datetime(2026, 11, 23, 23, 59, 59, tzinfo=periodo.BRASILIA)

    # Valor configurado abaixo de 5 respeita piso 5 (13, 16, 17, 18, 19)
    amb.contexto.config.parametro_inteiro = lambda c: (
        2 if c == "checkout_sem_codigo_resposta_dias_uteis" else None
    )
    _semear_em_andamento(amb, "ped-2")
    assert _checkout_sem_codigo(amb, "ped-2").status_code == 200
    c2 = [c for c in amb.contexto.checkout_sem_codigo.em_aberto() if c.pedido_id == "ped-2"][0]
    assert c2.responder_ate == datetime(2026, 11, 19, 23, 59, 59, tzinfo=periodo.BRASILIA)


def test_silencio_nunca_libera_nem_estorna_e_fila_ordena_vencidos_primeiro(amb):
    amb.relogio.agora = datetime(2026, 11, 2, 13, 0, tzinfo=UTC)
    agendador, _ = _montar_agendador(amb)

    # Pedido 1: com contato, vai vencer
    _semear_em_andamento(amb, "ped-vencido")
    assert _checkout_sem_codigo(amb, "ped-vencido").status_code == 200

    # Avança 10 dias: ped-vencido passa do prazo
    amb.relogio.avancar(days=10)

    # Pedido 2: com contato agora (ainda no prazo)
    _semear_em_andamento(amb, "ped-no-prazo")
    assert _checkout_sem_codigo(amb, "ped-no-prazo").status_code == 200

    # Pedido 3: sem notificador -> sem contato
    amb.contexto.extras.pop("notificador", None)
    _semear_em_andamento(amb, "ped-sem-contato")
    assert _checkout_sem_codigo(amb, "ped-sem-contato").status_code == 200

    fila = amb.cliente.get(URL_FILA, headers=cab("t-mediador"))
    assert fila.status_code == 200, fila.text
    itens = fila.json()["itens"]
    assert [i["pedido_id"] for i in itens] == ["ped-vencido", "ped-sem-contato", "ped-no-prazo"]
    assert itens[0]["vencido"] is True
    assert itens[1]["contatado_em"] is None and itens[1]["responder_ate"] is None
    assert itens[2]["vencido"] is False

    # Silêncio após vencer NUNCA conclui, libera ou estorna
    assert agendador.rodar_uma_vez().executadas == 0
    assert amb.contexto.pedidos.obter("ped-vencido").estado is E.EM_CONFIRMACAO
    saldos = amb.contexto.ledger.saldos_pedido("ped-vencido", PROFISSIONAL.id)
    assert saldos.a_liberar == 100_000 and saldos.liberado == 0


def test_contato_manual_auditado_permissoes_e_primeiro_contato_imutavel(amb):
    amb.relogio.agora = datetime(2026, 11, 2, 13, 0, tzinfo=UTC)
    amb.contexto.extras.pop("notificador", None)
    _semear_em_andamento(amb, "ped-manual")
    assert _checkout_sem_codigo(amb, "ped-manual").status_code == 200
    caso = amb.contexto.checkout_sem_codigo.em_aberto()[0]
    assert caso.contatado_em is None

    # Permissões
    for quem in ("t-n1", "t-cadastro", "t-financeiro", "t-cliente", "t-prof"):
        assert amb.cliente.get(URL_FILA, headers=cab(quem)).status_code == 403, quem
        assert (
            amb.cliente.post(
                f"{URL_FILA}/{caso.id}/contato",
                json={"canal": "whatsapp", "motivo": "Contato realizado por WhatsApp."},
                headers=cab(quem),
            ).status_code
            == 403
        ), quem

    # Validações
    assert (
        amb.cliente.post(
            f"{URL_FILA}/{caso.id}/contato",
            json={"canal": "whatsapp", "motivo": "curto"},
            headers=cab("t-mediador"),
        ).status_code
        == 422
    )
    assert (
        amb.cliente.post(
            f"{URL_FILA}/nao-existe/contato",
            json={"canal": "telefone", "motivo": "Contato feito por ligação telefônica."},
            headers=cab("t-mediador"),
        ).status_code
        == 404
    )

    # Registro válido
    r = amb.cliente.post(
        f"{URL_FILA}/{caso.id}/contato",
        json={"canal": "whatsapp", "motivo": "Cliente avisado pelo canal oficial."},
        headers=cab("t-mediador"),
    )
    assert r.status_code == 200, r.text
    corpo = r.json()
    assert corpo["canal"] == "whatsapp" and corpo["contatado_em"] is not None
    assert corpo["responder_ate"] is not None

    # Auditoria
    regs = amb.admin.auditoria.listar(FiltroAuditoria(), 50, 0)[0]
    assert any(
        e.acao == "checkout_sem_codigo.contato_manual" and e.entidade_id == "ped-manual"
        for e in regs
    )

    # Segundo contato manual falha com 409
    r2 = amb.cliente.post(
        f"{URL_FILA}/{caso.id}/contato",
        json={"canal": "telefone", "motivo": "Tentativa duplicada de contato manual."},
        headers=cab("t-mediador"),
    )
    assert r2.status_code == 409


def test_confirmar_e_disputa_registram_resposta_e_tiram_da_fila(amb):
    _ligar_notificador(amb)
    _semear_em_andamento(amb, "ped-conf")
    assert _checkout_sem_codigo(amb, "ped-conf").status_code == 200
    caso_conf = [
        c for c in amb.contexto.checkout_sem_codigo.em_aberto() if c.pedido_id == "ped-conf"
    ][0]

    r_conf = amb.cliente.post(
        "/v1/pedidos/ped-conf/acoes/confirmar_conclusao", headers=cab("t-cliente")
    )
    assert r_conf.status_code == 200, r_conf.text
    atual = amb.contexto.checkout_sem_codigo.obter(caso_conf.id)
    assert atual.resposta == CONFIRMOU and atual.respondido_em is not None

    _semear_em_andamento(amb, "ped-disp")
    assert _checkout_sem_codigo(amb, "ped-disp").status_code == 200
    caso_disp = [
        c for c in amb.contexto.checkout_sem_codigo.em_aberto() if c.pedido_id == "ped-disp"
    ][0]

    r_disp = amb.cliente.post(
        "/v1/pedidos/ped-disp/disputa",
        json={"motivo": "mal_feito", "descricao": "Serviço não foi concluído."},
        headers=cab("t-cliente"),
    )
    assert r_disp.status_code == 201, r_disp.text
    atual_d = amb.contexto.checkout_sem_codigo.obter(caso_disp.id)
    assert atual_d.resposta == RELATOU and atual_d.respondido_em is not None

    # Ambos saíram da fila e contato manual retorna 409
    assert amb.cliente.get(URL_FILA, headers=cab("t-mediador")).json()["total"] == 0
    assert (
        amb.cliente.post(
            f"{URL_FILA}/{caso_conf.id}/contato",
            json={"canal": "telefone", "motivo": "Tentativa em caso já respondido."},
            headers=cab("t-mediador"),
        ).status_code
        == 409
    )


def test_checkout_com_codigo_e_retrabalho_nao_abrem_caso(amb):
    _ligar_notificador(amb)
    _semear_em_andamento(amb, "ped-normal")
    r = amb.cliente.post(
        "/v1/pedidos/ped-normal/acoes/fazer_check_out",
        json={"prova": {"foto_final": _foto(amb), "codigo_conclusao": "5678"}},
        headers=cab("t-prof"),
    )
    assert r.status_code == 200
    assert amb.contexto.checkout_sem_codigo.em_aberto() == []

    # Retrabalho resolvido (mesmo deixando check_out_sem_codigo=True no Pedido) NÃO é caso
    amb.semear_pedido(
        E.RETRABALHO,
        id="ped-retrab",
        check_in_em=AGORA,
        check_out_em=AGORA,
    )
    amb.contexto.pedidos.salvar(
        replace(
            amb.contexto.pedidos.obter("ped-retrab"),
            estado=E.EM_CONFIRMACAO,
            check_out_sem_codigo=True,
        ),
        EventoPedido(
            pedido_id="ped-retrab",
            acao=Acao.RESOLVER_RETRABALHO,
            de=E.RETRABALHO,
            para=E.EM_CONFIRMACAO,
            ator=PROFISSIONAL.id,
            em=AGORA,
            prova=ProvaRetrabalho(descricao="Ajustado", fotos=()),
        ),
    )
    assert amb.contexto.checkout_sem_codigo.vigente("ped-retrab") is None


def test_sem_tabela_nao_quebra_e_admin_responde_503(amb):
    amb.contexto.checkout_sem_codigo.disponivel = lambda: False
    amb.contexto.checkout_sem_codigo.vigente = lambda _pid: None
    assert amb.cliente.get(URL_FILA, headers=cab("t-mediador")).status_code == 503
    assert (
        amb.cliente.post(
            f"{URL_FILA}/qualquer/contato",
            json={"canal": "telefone", "motivo": "Contato manual sem a tabela criada."},
            headers=cab("t-mediador"),
        ).status_code
        == 503
    )

    _semear_em_andamento(amb, "ped-sem-tab")
    assert _checkout_sem_codigo(amb, "ped-sem-tab").status_code == 200
    assert (
        amb.cliente.post(
            "/v1/pedidos/ped-sem-tab/acoes/confirmar_conclusao", headers=cab("t-cliente")
        ).status_code
        == 200
    )
