"""BE-INDISPONIBILIDADE-22.3-C, de ponta a ponta em memória: contestar e avaliar depois do prazo
original, repasse retido pelo congelamento, exclusividade e versão nova do orçamento."""

# ruff: noqa: F811 - o parâmetro com nome da fixture importada é do pytest

from __future__ import annotations

from dataclasses import replace
from datetime import datetime, timedelta

from conftest import AGORA, cab
from test_agendador import montar
from test_exclusividade import _ligar, _orcar, _pedido, _pedir, _responder, _saldo
from test_exclusividade_cliente import PRO, ligar
from test_exclusividade_cliente import pedir as pedir_como_cliente
from test_fixseg import com_equipe
from test_indisponibilidade_223 import MOTIVO, URL, falha
from test_liberacao_automatica import VALOR, concluido, repasses, saldo
from test_medidas import MINHAS, aplicar, contesto, preparar
from test_orcamentos_do_profissional_e_papel import ORC, _aberto, _post

from trato.agendador.executor import Adiada, ExecutorContexto
from trato.api.rotas_app import _limite_para_avaliar
from trato.api.validade import validade_vigente
from trato.pedidos.estados import Estado
from trato.rotinas.regras import AcaoRotina, TipoAcaoRotina

H = timedelta(hours=1)
D = timedelta(days=1)


def test_contestar_medida_depois_do_prazo_original_so_com_a_falha(amb):
    preparar(amb)
    mid = aplicar(amb).json()["id"]
    amb.contexto.auth.bloqueados.add("t-cliente")
    amb.relogio.avancar(days=31)
    recusada = contesto(amb, mid)
    assert recusada.status_code == 409 and recusada.json()["codigo"] == "prazo_encerrado"
    falha(amb.contexto, AGORA + 2 * D, AGORA + 4 * D)  # +2 dias
    (item,) = amb.cliente.get(MINHAS, headers=cab("t-cliente")).json()
    assert datetime.fromisoformat(item["contestavel_ate"]) == AGORA + 32 * D
    assert contesto(amb, mid).status_code == 200


def avaliar(amb):
    return amb.cliente.post(
        "/v1/pedidos/ped-1/avaliacao", json={"nota_geral": 5}, headers=cab("t-cliente")
    )


def test_avaliar_depois_do_prazo_original_so_com_a_falha(amb):
    pedido = amb.semear_pedido(Estado.CONCLUIDO, concluido_em=AGORA)
    ate, _ = _limite_para_avaliar(amb.contexto, pedido)
    amb.relogio.agora = ate + H
    recusada = avaliar(amb)
    assert recusada.status_code == 409 and "prazo para avaliar" in recusada.json()["detail"]
    falha(amb.contexto, AGORA + D, AGORA + D + 2 * H)
    assert avaliar(amb).status_code == 201


def test_repasse_espera_o_congelamento_prorrogado_e_sai_uma_vez(amb):
    concluido(amb)  # concluído há 10 dias, liberação em 7
    inicio = AGORA - 10 * D
    horas = amb.contexto.config.carregar().disputas.prazo_congelar_repasse_horas
    # A falha de 9 dias empurra o fim do congelamento para daqui a algumas horas.
    falha(amb.contexto, inicio + H, inicio + H + 9 * D)
    fim = inicio + timedelta(hours=horas) + 9 * D
    assert fim > AGORA
    acao = AcaoRotina(
        TipoAcaoRotina.LIBERAR_SALDO,
        "ped-1",
        f"liberacao:ped-1:{VALOR}",
        valor_centavos=VALOR,
        profissional_id=amb.contexto.pedidos.obter("ped-1").profissional_id,
    )
    try:
        ExecutorContexto(amb.contexto).executar(acao, AGORA)
        raise AssertionError("liberou durante o congelamento prorrogado")
    except Adiada as adiada:
        assert "indisponibilidade" in str(adiada)
    agendador, _, _ = montar(amb)
    agendador.rodar_uma_vez()
    assert saldo(amb) == (VALOR, 0) and repasses(amb) == 0
    amb.relogio.agora = fim + timedelta(seconds=1)
    agendador.rodar_uma_vez()
    agendador.rodar_uma_vez()
    montar(amb)[0].rodar_uma_vez()  # outra instância
    assert saldo(amb) == (0, VALOR) and repasses(amb) == 1


def ligar_oferta(amb) -> None:
    config = amb.contexto.config
    config._config = replace(config.carregar(), exclusividade_profissional_ofertada=True)
    _ligar(amb)


def test_oferta_do_profissional_prorrogada_suspensa_e_expirada(amb):
    ligar_oferta(amb)
    _pedido(amb)
    criada = _pedir(amb).json()
    original = datetime.fromisoformat(criada["responder_ate"])
    repo = amb.contexto.exclusividades
    janela = falha(amb.contexto, AGORA + H)  # ativa
    visto = amb.cliente.get("/v1/pedidos/ped-1/exclusividade", headers=cab("t-cliente")).json()
    assert visto["responder_ate"] is None and visto["prazo_suspenso"] is True
    amb.relogio.agora = original + 5 * H
    assert repo.expirar(amb.relogio.agora) == []  # suspenso: não expira nem estorna
    amb.contexto.indisponibilidades.encerrar(janela.id, original + 5 * H, "eq-admin")
    novo = original + (original + 5 * H - (AGORA + H))
    visto = amb.cliente.get("/v1/pedidos/ped-1/exclusividade", headers=cab("t-cliente")).json()
    assert datetime.fromisoformat(visto["responder_ate"]) == novo
    assert visto["prazo_suspenso"] is False
    assert repo.expirar(novo) == []
    antes = _saldo(amb)
    assert len(repo.expirar(novo + H)) == 1 and repo.expirar(novo + H) == []
    assert _saldo(amb) == antes + criada["moedas_cobradas"]  # estorno uma vez


def test_oferta_aceita_depois_do_prazo_original_com_a_falha(amb):
    ligar_oferta(amb)
    _pedido(amb)
    criada = _pedir(amb).json()
    original = datetime.fromisoformat(criada["responder_ate"])
    falha(amb.contexto, AGORA + H, AGORA + 4 * H)
    amb.relogio.agora = original + 2 * H
    assert _responder(amb, criada["id"], "aceitar").status_code == 200


def test_cliente_so_reserva_com_orcamento_valido_pela_223(amb):
    ligar(amb)
    _pedido(amb)
    assert _orcar(amb).status_code == 201
    orcamento = next(
        o for o in amb.contexto.orcamentos.do_pedido("ped-1") if o.profissional_id == PRO
    )
    detalhes = amb.contexto.orcamentos._detalhes
    detalhes[orcamento.id] = replace(
        detalhes[orcamento.id], enviado_em=AGORA - 5 * H, validade_ate=AGORA - H
    )
    r = pedir_como_cliente(amb, orcamento_id=orcamento.id)
    assert r.json()["codigo"] == "orcamento_invalido", r.text
    falha(amb.contexto, AGORA - 4 * H, AGORA - 2 * H, "pagamento")  # vale até AGORA + 1 h
    assert pedir_como_cliente(amb, orcamento_id=orcamento.id).status_code == 201


def test_versao_nova_nao_conta_a_mesma_falha_duas_vezes(amb):
    _aberto(amb)
    base = "/v1/pedidos/ped-1/orcamentos"
    original = AGORA + 10 * H
    novo = _post(amb, base, "t-prof", ORC | {"validade_ate": original.isoformat()}).json()["id"]
    janela = falha(amb.contexto, AGORA + H)  # ativa quando a versão nova nasce
    amb.relogio.agora = AGORA + 3 * H
    url = f"{base}/{novo}/contraproposta"
    assert _post(amb, url, "t-cliente", {"valor_centavos": 8_000}).status_code < 300
    r = _post(amb, f"{url}/aceitar", "t-prof", {"valor_centavos": 8_000})
    assert r.status_code < 300, r.text
    (versao,) = amb.contexto.orcamentos.do_pedido("ped-1")
    detalhe = amb.contexto.orcamentos.detalhe(versao.id)
    assert detalhe.id != novo
    assert detalhe.validade_ate == original + 2 * H  # falha até o envio da versão
    amb.contexto.indisponibilidades.encerrar(janela.id, AGORA + 6 * H, "eq-admin")
    amb.relogio.agora = AGORA + 7 * H
    # Falha total de 5 h: a versão nova vence em original + 5 h, nem um minuto a mais.
    assert validade_vigente(amb.contexto, detalhe) == original + 5 * H


def test_fim_no_futuro_e_recusado(amb):
    com_equipe(amb)
    corpo = {
        "origem": "app",
        "inicio_em": (AGORA - 2 * H).isoformat(),
        "fim_em": (AGORA + H).isoformat(),
        "motivo": MOTIVO,
    }
    r = amb.cliente.post(URL, json=corpo, headers=cab("t-lider"))
    assert r.status_code == 422, r.text
    assert amb.contexto.indisponibilidades.listar() == []
