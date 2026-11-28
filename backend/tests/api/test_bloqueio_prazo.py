"""BE-BLOQUEIO-PRAZO (Termos 20.6 e 20.10): a janela de confirmação recomeça no desbloqueio e o
cliente bloqueado se defende no próprio pedido contratado (ausência, disputa e a foto dela).
Memória e provedor falso."""

# ruff: noqa: F811 - o parâmetro com nome da fixture importada é do pytest

from __future__ import annotations

from datetime import timedelta

import pytest
from conftest import CLIENTE, cab
from test_ausencia_cliente import LONGE, justificar, registrado, remarcado_para_longe
from test_cliente_bloqueado_pedido import TIPOS, bloquear, por_prazo, recusado
from test_contestacao_decisao import contestar, decidido, ver
from test_fluxo_pagamento_e2e import fluxo  # noqa: F401
from test_profissional_upload import JPEG_COM_EXIF, Ambiente2
from test_provas_ausencia import com_retencao

from trato.agendador.executor import Adiada, ExecutorContexto
from trato.api.medidas import reverter
from trato.pedidos.estados import Estado


class Avisos:
    def __init__(self) -> None:
        self.itens: dict[str, str] = {}

    def notificar(self, evento, usuario, *, chave, pedido_id=None, corpo=None, **_):
        self.itens.setdefault(chave, corpo or "")
        return []


def prazo(f) -> timedelta:
    return f.ctx.config.carregar().prazos_pedido.confirmacao_cliente


def rodar(f, pid, avisos=None):
    ExecutorContexto(f.ctx, avisos).executar(por_prazo(pid), f.ctx.agora())


def adiado(f, pid, motivo, avisos=None):
    with pytest.raises(Adiada, match=motivo):
        rodar(f, pid, avisos)
    assert f.ctx.pedidos.obter(pid).estado is Estado.EM_CONFIRMACAO
    assert not list(f.ctx.repasses.do_pedido(pid))


@pytest.mark.parametrize("tipo", TIPOS)
def test_janela_recomeca_no_desbloqueio_e_avisa_uma_vez(fluxo, tipo):
    pid = fluxo.ate_em_confirmacao()
    medida = bloquear(fluxo, tipo)
    fluxo.amb.relogio.avancar(days=8)
    adiado(fluxo, pid, "cliente_bloqueado")
    assert reverter(fluxo.ctx, medida, "eq-mediador")
    avisos = Avisos()
    adiado(fluxo, pid, "janela_reaberta", avisos)  # 1º ciclo depois do desbloqueio
    fluxo.amb.relogio.avancar(seconds=(prazo(fluxo) - timedelta(seconds=1)).total_seconds())
    adiado(fluxo, pid, "janela_reaberta", avisos)
    (corpo,) = avisos.itens.values()
    assert "recomeçou" in corpo
    fluxo.amb.relogio.avancar(seconds=1)
    rodar(fluxo, pid, avisos)
    rodar(fluxo, pid, avisos)
    assert fluxo.ctx.pedidos.obter(pid).estado is Estado.CONCLUIDO
    assert len(list(fluxo.ctx.repasses.do_pedido(pid))) == 1


def test_medida_que_vence_sozinha_tambem_reabre(fluxo):
    pid = fluxo.ate_em_confirmacao()
    medida = bloquear(fluxo)
    fim = fluxo.ctx.agora() + timedelta(days=8)
    assert fluxo.ctx.medidas.mudar(medida.id, {"fim_em": fim})
    fluxo.amb.relogio.avancar(days=8, hours=1)
    fluxo.ctx.medidas.status[CLIENTE.id] = "ativo"  # o agendador devolve a conta
    adiado(fluxo, pid, "janela_reaberta")
    fluxo.amb.relogio.agora = fim + prazo(fluxo)
    rodar(fluxo, pid)
    assert fluxo.ctx.pedidos.obter(pid).estado is Estado.CONCLUIDO


def test_segundo_bloqueio_recomeca_do_ultimo_desbloqueio(fluxo):
    pid = fluxo.ate_em_confirmacao()
    for tipo in ("suspensao", "bloqueio_preventivo"):
        medida = bloquear(fluxo, tipo)
        fluxo.amb.relogio.avancar(days=3)
        assert reverter(fluxo.ctx, medida, "eq-mediador")
        fluxo.amb.relogio.avancar(hours=1)
        adiado(fluxo, pid, "janela_reaberta")
    fluxo.amb.relogio.avancar(seconds=prazo(fluxo).total_seconds())
    rodar(fluxo, pid)
    assert fluxo.ctx.pedidos.obter(pid).estado is Estado.CONCLUIDO


def test_bloqueio_encerrado_antes_do_check_out_nao_conta(fluxo):
    pid = fluxo.aceitar()
    medida = bloquear(fluxo, "bloqueio_preventivo")  # suspensão cancelaria o pedido (20.6)
    fluxo.amb.relogio.avancar(minutes=1)
    assert reverter(fluxo.ctx, medida, "eq-mediador")
    fluxo.amb.contexto.auth.bloqueados.discard("t-cliente")
    fluxo.amb.relogio.avancar(minutes=1)
    fluxo.pagar(pid)
    fluxo.agendar(pid)
    fluxo.iniciar(pid)
    fluxo.encerrar_execucao(pid)
    fluxo.amb.relogio.avancar(days=8)
    rodar(fluxo, pid)
    assert fluxo.ctx.pedidos.obter(pid).estado is Estado.CONCLUIDO


# --- o que o bloqueado faz no próprio pedido ------------------------------------------------------


def test_justifica_a_ausencia_e_so_o_dono(fluxo):
    pid, _ = remarcado_para_longe(fluxo)
    registrado(fluxo, pid, LONGE)
    bloquear(fluxo)
    for quem in ("t-outro-cliente", "t-prof"):
        fluxo.amb.contexto.auth.bloqueados.add(quem)
        assert recusado(justificar(fluxo, pid, quem=quem)), quem
        assert recusado(fluxo.chamar("GET", f"/v1/pedidos/{pid}/ausencia", quem)), quem
    assert fluxo.chamar("GET", f"/v1/pedidos/{pid}/ausencia", "t-cliente").status_code == 200
    r = justificar(fluxo, pid)
    assert r.status_code == 200 and r.json()["status"] == "em_analise", r.text
    assert justificar(fluxo, pid).status_code == 200  # repetir não muda


def test_contesta_a_retencao_proposta_antes_do_bloqueio(fluxo):
    pid, _, _ = com_retencao(fluxo)
    bloquear(fluxo)
    url = f"/v1/pedidos/{pid}/ausencia/contestacao"
    corpo = {"texto": "O material não foi comprado para este serviço."}
    fluxo.amb.contexto.auth.bloqueados.add("t-outro-cliente")
    assert recusado(fluxo.chamar("POST", url, "t-outro-cliente", corpo))
    assert fluxo.chamar("GET", f"/v1/pedidos/{pid}/ausencia/anexos", "t-cliente").status_code == 200
    antes = fluxo.tipos(pid)
    for _ in range(2):
        r = fluxo.chamar("POST", url, "t-cliente", corpo)
        assert r.status_code == 200 and r.json()["contestacao"]["status"] == "aberta", r.text
    assert fluxo.tipos(pid) == antes


def test_contesta_a_decisao_da_disputa_e_so_o_dono(fluxo):
    pid = decidido(fluxo)
    bloquear(fluxo)
    for quem in ("t-outro-cliente", "t-prof"):
        fluxo.amb.contexto.auth.bloqueados.add(quem)
        assert recusado(ver(fluxo, pid, quem)) and recusado(contestar(fluxo, pid, quem)), quem
    assert ver(fluxo, pid).json()["pode_contestar"] is True
    r = contestar(fluxo, pid)
    assert r.status_code == 201, r.text
    assert contestar(fluxo, pid).status_code == 200


def test_pedido_cancelado_depois_de_pago_ainda_pode_contestar(fluxo):
    from test_fixseg import com_equipe
    from test_fluxo_pagamento_e2e import _abrir_e_responder_disputa

    com_equipe(fluxo.amb)
    pid = fluxo.ate_em_confirmacao()
    _abrir_e_responder_disputa(fluxo, pid)
    corpo = {"resultado": "reembolso_total", "justificativa": "Serviço não foi feito."}
    r = fluxo.chamar("POST", f"/v1/pedidos/{pid}/disputa/decisao", "t-mediador", corpo)
    assert r.status_code == 200, r.text
    if fluxo.ctx.pedidos.obter(pid).estado is not Estado.CANCELADO:  # acima da alçada
        pytest.fail("a decisão deveria cancelar o pedido")
    bloquear(fluxo)
    r = contestar(fluxo, pid)
    assert r.status_code == 201, r.text


def test_envia_so_a_foto_da_disputa_do_proprio_pedido(fluxo):
    pid = fluxo.ate_em_confirmacao()
    envios = Ambiente2(fluxo.amb)
    fluxo.http.app.state.servico_uploads = envios.servico
    corpo = {"nome_arquivo": "a.jpg", "content_type": "image/jpeg", "tamanho_bytes": 10}
    # pedido antes do bloqueio: o envio de outro tipo não pode ser concluído depois
    chat = fluxo.chamar(
        "POST", "/v1/uploads", "t-cliente", corpo | {"destino": "chat", "pedido_id": pid}
    )
    assert chat.status_code == 201, chat.text
    bloquear(fluxo)
    pedir, concluir = envios.enviar("t-cliente", "disputa", JPEG_COM_EXIF, pedido_id=pid)
    assert pedir.status_code == 201 and concluir.status_code == 200, pedir.text
    assert concluir.json()["midia_id"]
    for extra in (
        {"destino": "chat", "pedido_id": pid},
        {"destino": "avatar"},
        {"destino": "disputa", "pedido_id": "ped-de-outro"},
        {"destino": "disputa"},
    ):
        r = fluxo.chamar("POST", "/v1/uploads", "t-cliente", corpo | extra)
        assert recusado(r), (extra, r.text)
    url = f"/v1/uploads/{chat.json()['upload_id']}/concluir"
    assert recusado(fluxo.chamar("POST", url, "t-cliente"))
    meu = f"/v1/uploads/{pedir.json()['upload_id']}/concluir"
    for quem in ("t-outro-cliente", "t-prof"):
        fluxo.amb.contexto.auth.bloqueados.add(quem)
        r = fluxo.chamar(
            "POST", "/v1/uploads", quem, corpo | {"destino": "disputa", "pedido_id": pid}
        )
        assert recusado(r), quem
        assert recusado(fluxo.http.post(meu, headers=cab(quem))), quem
        # sem pedido próprio contratado, 403 mesmo sem corpo (não revela mais nada)
        assert recusado(fluxo.http.post("/v1/uploads", headers=cab(quem))), quem
