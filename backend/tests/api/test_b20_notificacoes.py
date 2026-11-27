"""B20: notificações novas (NOT-1) e retrabalho resolvido volta ao fluxo (RET-1)."""

from __future__ import annotations

from dataclasses import replace

from conftest import CLIENTE, PROFISSIONAL
from test_fluxo_pagamento_e2e import Fluxo, fluxo  # noqa: F401

from trato.notificacoes import ligar_ao_contexto
from trato.notificacoes.canais import Canais, CanalApp
from trato.notificacoes.config import ConfigNotificacoes
from trato.notificacoes.eventos import MODELOS, Evento
from trato.notificacoes.repositorio import RepositorioEmMemoria
from trato.notificacoes.servico import ServicoNotificacoes
from trato.pagamentos.provedor import TipoEvento
from trato.pedidos.estados import Estado


def _ligar(fl) -> ServicoNotificacoes:
    notif = ServicoNotificacoes(
        RepositorioEmMemoria(),
        Canais(CanalApp()),
        ConfigNotificacoes(_env_file=None),
        fl.amb.relogio,
    )
    ligar_ao_contexto(fl.http.app, fl.ctx, notif)
    return notif


def _avisos(notif, usuario_id, evento):
    return [n for n in notif.repo.listar(usuario_id, False, 100) if n.tipo == evento.value]


def _um(notif, usuario_id, evento):
    achados = _avisos(notif, usuario_id, evento)
    assert len(achados) == 1, (evento, achados)
    return achados[0]


def test_pagamento_confirmado_avisa_cliente_e_profissional_uma_vez(fluxo: Fluxo):  # noqa: F811
    notif = _ligar(fluxo)
    pid = fluxo.aceitar()
    cobranca = fluxo.cobrar(pid)
    fluxo.fake.marcar_paga(cobranca["id"])
    assert fluxo.webhook(TipoEvento.PAGAMENTO_CONFIRMADO, cobranca["id"]).status_code == 200
    assert fluxo.webhook(TipoEvento.PAGAMENTO_CONFIRMADO, cobranca["id"]).status_code == 200

    cli = _um(notif, CLIENTE.id, Evento.PAGAMENTO_CONFIRMADO)
    assert cli.titulo == "Pagamento confirmado"
    assert cli.corpo == "Pagamento confirmado. Combine o início com o profissional."
    assert cli.dados["pedido_id"] == pid
    pro = _um(notif, PROFISSIONAL.id, Evento.PAGAMENTO_CONFIRMADO)
    assert pro.titulo == "Pagamento recebido"
    assert pro.corpo == "Pagamento recebido: o valor fica retido até o cliente confirmar o serviço."


def test_codigo_de_inicio_ganha_corpo_e_janela_da_agenda(fluxo: Fluxo):  # noqa: F811
    notif = _ligar(fluxo)
    pid = fluxo.aceitar()
    fluxo.pagar(pid)
    fluxo.agendar(pid)

    aviso = _um(notif, CLIENTE.id, Evento.CODIGO_INICIO)
    assert aviso.titulo == "Código de início disponível"
    assert aviso.corpo.startswith("Abra o pedido para ver o código")
    # janela_futura(): AGORA + 2 dias, 3 h (12:00 UTC = 09:00 em Brasília)
    assert "Serviço marcado para" in aviso.corpo and "das 09:00 às 12:00." in aviso.corpo
    assert aviso.dados["pedido_id"] == pid


def test_servico_iniciado_e_codigo_de_conclusao_no_check_in(fluxo: Fluxo):  # noqa: F811
    notif = _ligar(fluxo)
    pid = fluxo.aceitar()
    fluxo.pagar(pid)
    fluxo.agendar(pid)
    fluxo.iniciar(pid)

    ini = _um(notif, CLIENTE.id, Evento.SERVICO_INICIADO)
    assert (ini.titulo, ini.corpo) == ("Serviço iniciado", "O profissional começou o serviço.")
    cod = _um(notif, CLIENTE.id, Evento.CODIGO_CONCLUSAO)
    assert cod.titulo == "Código de conclusão disponível"
    assert cod.corpo == (
        "Passe este código ao profissional quando o serviço estiver pronto. Não envie por mensagem."
    )
    codigo = fluxo.pedido(pid)["codigo_conclusao"]
    assert codigo not in cod.corpo and codigo not in str(cod.dados)


def test_conclusao_para_confirmar_traz_o_prazo_da_configuracao(fluxo: Fluxo):  # noqa: F811
    notif = _ligar(fluxo)
    pid = fluxo.ate_em_confirmacao()

    aviso = _um(notif, CLIENTE.id, Evento.CONCLUSAO_PARA_CONFIRMAR)
    assert aviso.titulo == "Confirme o serviço"
    prazo = fluxo.ctx.config.carregar().prazos_pedido.confirmacao_cliente
    assert "O profissional terminou. Você tem" in aviso.corpo
    assert f"{int(prazo.total_seconds() // 3600)} horas" in aviso.corpo or "dias" in aviso.corpo
    assert aviso.dados["pedido_id"] == pid


def test_cliente_confirmou_avisa_o_profissional_com_a_data_de_liberacao(fluxo: Fluxo):  # noqa: F811
    config = fluxo.ctx.config
    config._config = replace(config.carregar(), prazo_liberacao_dias=0)
    notif = _ligar(fluxo)
    pid = fluxo.ate_em_confirmacao()
    fluxo.concluir(pid)
    fluxo.acao(pid, "confirmar_conclusao", "t-cliente")  # duplo toque: nada novo

    aviso = _um(notif, PROFISSIONAL.id, Evento.CLIENTE_CONFIRMOU)
    assert aviso.titulo == "Serviço confirmado pelo cliente"
    assert aviso.corpo.startswith(
        "O cliente confirmou o serviço. A liberação do valor está prevista para "
    )
    assert aviso.corpo.endswith("/2026.") or aviso.corpo.endswith("/2027.")


def test_avaliacao_recebida_sem_expor_o_comentario(fluxo: Fluxo):  # noqa: F811
    notif = _ligar(fluxo)
    pid = fluxo.ate_em_confirmacao()
    fluxo.concluir(pid)
    url = f"/v1/pedidos/{pid}/avaliacao"
    corpo = {"nota_geral": 5, "comentario": "Texto privado do cliente"}
    assert fluxo.chamar("POST", url, "t-cliente", corpo).status_code == 201
    assert fluxo.chamar("POST", url, "t-cliente", corpo).status_code == 200  # duplo toque
    assert fluxo.chamar("POST", url, "t-prof", {"nota_geral": 4}).status_code == 201

    pro = _um(notif, PROFISSIONAL.id, Evento.AVALIACAO)
    assert (pro.titulo, pro.corpo) == ("Nova avaliação", "Você recebeu uma avaliação.")
    assert "Texto privado" not in pro.corpo and "Texto privado" not in str(pro.dados)
    cli = _um(notif, CLIENTE.id, Evento.AVALIACAO)
    assert (cli.titulo, cli.corpo) == ("Nova avaliação", "Seu profissional avaliou você.")


def test_aditivo_proposto_aprovado_e_nota_de_material(fluxo: Fluxo):  # noqa: F811
    notif = _ligar(fluxo)
    pid = fluxo.aceitar()
    fluxo.pagar(pid)
    fluxo.agendar(pid)
    fluxo.iniciar(pid)

    base = f"/v1/contratos/{pid}"
    r = fluxo.chamar(
        "POST",
        f"{base}/aditivos",
        "t-prof",
        {"descricao": "Trocar o registro", "valor_centavos": 5000},
    )
    assert r.status_code == 201, r.text
    aditivo_id = r.json()["id"]
    pendente = _um(notif, CLIENTE.id, Evento.ADITIVO_PENDENTE)
    assert pendente.titulo == "Aditivo aguardando você"
    assert pendente.dados["pedido_id"] == pid

    r = fluxo.chamar("POST", f"{base}/aditivos/{aditivo_id}/aprovar", "t-cliente", {"meio": "pix"})
    assert r.status_code == 200, r.text
    aprovado = _um(notif, PROFISSIONAL.id, Evento.ADITIVO_APROVADO)
    assert (aprovado.titulo, aprovado.corpo) == (
        "Aditivo aprovado",
        "O cliente aprovou o aditivo do serviço.",
    )

    nota = {
        "foto_storage_path": f"pedidos/{pid}/nota.jpg",
        "itens": [{"descricao": "Fio", "quantidade": "2", "valor_unitario_centavos": 1500}],
    }
    assert fluxo.chamar("POST", f"{base}/notas-material", "t-prof", nota).status_code == 201
    assert fluxo.chamar("POST", f"{base}/notas-material", "t-prof", nota).status_code == 409
    aviso = _um(notif, CLIENTE.id, Evento.NOTA_MATERIAL)
    assert aviso.titulo == "Nota de material enviada"
    assert aviso.corpo == "O profissional enviou uma nota de material. Veja os itens e o valor."


def test_novos_eventos_aparecem_so_na_lista_do_app():
    for evento in (
        Evento.SERVICO_INICIADO,
        Evento.CODIGO_CONCLUSAO,
        Evento.CLIENTE_CONFIRMOU,
        Evento.ADITIVO_APROVADO,
        Evento.NOTA_MATERIAL,
    ):
        assert MODELOS[evento].somente_app and MODELOS[evento].essencial
    # Termos 15.2: o que trata de reclamação ou garantia sai também por e-mail.
    assert not MODELOS[Evento.RETRABALHO_RESOLVIDO].somente_app


# --- RET-1: o ciclo do retrabalho ----------------------------------------------------------


def test_ciclo_completo_do_retrabalho_volta_ao_fluxo_sem_mexer_no_dinheiro(fluxo: Fluxo):  # noqa: F811
    notif = _ligar(fluxo)
    pid = fluxo.ate_em_confirmacao()
    fluxo.concluir(pid)
    garantia = fluxo.ctx.garantias.obter_garantia(pid)
    lancamentos = len(fluxo.ctx.ledger.lancamentos(pid))
    concluido_em = fluxo.ctx.pedidos.obter(pid).concluido_em

    # cliente pede retrabalho -> profissional é avisado
    r = fluxo.chamar("POST", f"/v1/pedidos/{pid}/retrabalho", "t-cliente", {"descricao": "Vazou"})
    assert r.status_code == 201, r.text
    assert fluxo.pedido(pid)["estado"] == "retrabalho"
    _um(notif, PROFISSIONAL.id, Evento.RETRABALHO)

    # profissional atende; ao resolver, o pedido aguarda o cliente
    atender = f"/v1/pedidos/{pid}/retrabalho/atender"
    for etapa in ("aceitar", "iniciar", "resolver"):
        assert fluxo.chamar("POST", atender, "t-prof", {"etapa": etapa}).status_code == 200, etapa
    assert fluxo.pedido(pid, "t-prof")["estado"] == "em_confirmacao"
    repetida = fluxo.chamar("POST", atender, "t-prof", {"etapa": "resolver"})
    assert repetida.status_code == 200  # repetir é seguro
    resolvido = _um(notif, CLIENTE.id, Evento.RETRABALHO_RESOLVIDO)
    assert (resolvido.titulo, resolvido.corpo) == (
        "Retrabalho resolvido",
        "O profissional informou que resolveu o problema. Confirme se está tudo certo.",
    )

    # cliente confirma de novo; sem auto-conclusão por prazo e sem novo dinheiro nem garantia
    assert fluxo.ctx.pedidos.obter(pid).check_out_sem_codigo is True
    fluxo.concluir(pid)
    pedido = fluxo.ctx.pedidos.obter(pid)
    assert pedido.estado is Estado.CONCLUIDO and pedido.concluido_em == concluido_em
    assert fluxo.ctx.garantias.obter_garantia(pid) == garantia
    assert len(fluxo.ctx.ledger.lancamentos(pid)) == lancamentos

    # e a avaliação do profissional continua possível
    r = fluxo.chamar("POST", f"/v1/pedidos/{pid}/avaliacao", "t-prof", {"nota_geral": 5})
    assert r.status_code == 201, r.text


def test_resolver_retrabalho_nao_e_acao_livre_do_pedido(fluxo: Fluxo):  # noqa: F811
    pid = fluxo.ate_em_confirmacao()
    fluxo.concluir(pid)
    assert fluxo.acao(pid, "resolver_retrabalho", "t-prof").status_code == 400  # rota dedicada
    assert fluxo.acao(pid, "resolver_retrabalho", "t-cliente").status_code in (400, 403)
    assert fluxo.pedido(pid)["estado"] == "concluido"
