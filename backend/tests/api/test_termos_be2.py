"""TERMOS-BE2: avisos que afetam direitos pelo app e e-mail (15.2), portfólio só com perfil de
profissional e endereço só na conversa do contratado (5.4)."""

from __future__ import annotations

from dataclasses import replace

from admin_ambiente import PEDIDO, adm  # noqa: F401
from admin_ambiente import cab as cab_admin
from conftest import AGORA, CLIENTE, PROFISSIONAL, cab
from test_fluxo_pagamento_e2e import DISPUTA, VALOR, fluxo  # noqa: F401 - fixtures
from test_profissional_upload import e2  # noqa: F401 - serviço de envio ligado

from trato.api.auth import PapelUsuario
from trato.notificacoes import ligar_ao_contexto
from trato.notificacoes.canais import Canais, CanalApp, CanalFake
from trato.notificacoes.config import ConfigNotificacoes
from trato.notificacoes.eventos import MODELOS, Categoria, Evento
from trato.notificacoes.repositorio import RepositorioEmMemoria
from trato.notificacoes.servico import ServicoNotificacoes
from trato.pagamentos.provedor import TipoEvento
from trato.pedidos.estados import Estado
from trato.seguranca.mascaramento import AVISO_MASCARA


class Emails:
    def email_de(self, usuario_id):
        return f"{usuario_id}@exemplo.test"


def ouvir(app, contexto) -> tuple[CanalFake, CanalFake]:
    push, email = CanalFake("push"), CanalFake("email")
    servico = ServicoNotificacoes(
        RepositorioEmMemoria(),
        Canais(CanalApp(), push, email),
        ConfigNotificacoes(_env_file=None),
        contexto.agora,
        Emails(),
    )
    desligado = {"app": False, "push": False, "email": False}
    for usuario in (CLIENTE.id, PROFISSIONAL.id):  # quem tentou desligar tudo
        servico.repo.salvar_preferencias(
            usuario, {"disputas": desligado, "pagamentos": desligado}, AGORA
        )
    ligar_ao_contexto(app, contexto, servico)
    return push, email


def enviados(email: CanalFake, titulo: str) -> list[str]:
    return sorted(m.usuario_id for m in email.enviados if m.titulo == titulo)


# --- 15.2: disputa e decisão ---------------------------------------------------------------------


def test_abrir_responder_e_decidir_avisam_por_email(fluxo):  # noqa: F811
    _, email = ouvir(fluxo.http.app, fluxo.ctx)
    pid = fluxo.ate_em_confirmacao()
    assert (
        fluxo.chamar("POST", f"/v1/pedidos/{pid}/disputa", "t-cliente", DISPUTA).status_code == 201
    )
    assert enviados(email, "Reclamação aberta") == sorted([CLIENTE.id, PROFISSIONAL.id])
    assert fluxo.chamar("POST", f"/v1/pedidos/{pid}/disputa/resposta", "t-prof").status_code == 200
    assert enviados(email, "Reclamação respondida") == [CLIENTE.id]
    corpo = {"resultado": "reembolso_total", "justificativa": "Serviço não feito."}
    for _ in range(2):  # repetir não avisa de novo
        fluxo.chamar("POST", f"/v1/pedidos/{pid}/disputa/decisao", "t-mediador", corpo)
    assert enviados(email, "Reclamação analisada") == sorted([CLIENTE.id, PROFISSIONAL.id])
    assert enviados(email, "Estorno solicitado") == [CLIENTE.id]
    (estorno,) = [m for m in email.enviados if m.titulo == "Estorno solicitado"]
    assert "R$ 1.000,00" in estorno.corpo and VALOR == 100_000
    decisao = [m for m in email.enviados if m.titulo == "Reclamação analisada"]
    assert all("reembolso total ao cliente" in m.corpo for m in decisao)


def _painel(adm, quem="t-mediador", rota="decisao"):  # noqa: F811
    corpo = {"justificativa": "Fotos conferidas com cuidado."}
    if rota == "decisao":
        corpo["resultado"] = "reembolso_parcial"
        corpo["valor_cliente_centavos"] = 20_000
    return adm.cliente.post(
        f"/v1/admin/disputas/{PEDIDO}/{rota}", json=corpo, headers=cab_admin(quem)
    )


def test_painel_so_avisa_depois_da_aprovacao_final(adm):  # noqa: F811
    adm.semear_disputa()
    _, email = ouvir(adm.cliente.app, adm.contexto)
    assert _painel(adm, "t-mediador_sem_alcada").status_code == 200
    assert email.enviados == []
    assert _painel(adm, "t-administrador", "aprovacao").status_code == 200
    assert len(enviados(email, "Reclamação analisada")) == 2
    assert len(enviados(email, "Estorno solicitado")) == 1


def test_falha_no_aviso_nao_desfaz_a_decisao(adm):  # noqa: F811
    adm.semear_disputa()
    ouvir(adm.cliente.app, adm.contexto)

    class Quebrado:
        def notificar(self, *args, **kwargs):
            raise RuntimeError("fora do ar")

    adm.contexto.extras["notificador"] = Quebrado()
    assert _painel(adm).status_code == 200
    assert adm.pedido().estado is Estado.CONCLUIDO


def test_estorno_pendente_so_avisa_quando_o_provedor_aceita(fluxo, monkeypatch):  # noqa: F811
    _, email = ouvir(fluxo.http.app, fluxo.ctx)
    pid = fluxo.aceitar()
    fluxo.pagar(pid)

    def fora(*args):
        raise RuntimeError("fora do ar")

    with monkeypatch.context() as m:
        m.setattr(fluxo.fake, "estornar", fora)
        fluxo.acao(pid, "cancelar", "t-cliente", {"motivo": "Desisti"})
    assert enviados(email, "Estorno solicitado") == []
    for _ in range(2):
        fluxo.servico.reenviar_estornos()
    assert enviados(email, "Estorno solicitado") == [CLIENTE.id]


def test_estorno_feito_por_fora_tambem_avisa_uma_vez(fluxo):  # noqa: F811
    _, email = ouvir(fluxo.http.app, fluxo.ctx)
    pid = fluxo.aceitar()
    cobranca = fluxo.pagar(pid)
    for evento in ("ev-a", "ev-b"):
        r = fluxo.webhook(
            TipoEvento.ESTORNO_CONFIRMADO, cobranca["id"], valor_centavos=5_000, evento_id=evento
        )
        assert r.status_code == 200, r.text
    assert enviados(email, "Estorno solicitado") == [CLIENTE.id]


def test_somente_app_nao_inclui_disputa_nem_estorno():
    somente = {e for e, m in MODELOS.items() if m.somente_app}
    assert somente == {
        Evento.SERVICO_INICIADO,
        Evento.CODIGO_CONCLUSAO,
        Evento.CLIENTE_CONFIRMOU,
        Evento.ADITIVO_APROVADO,
        Evento.ADITIVO_PAGO,
        Evento.NOTA_MATERIAL,
    }
    assert all(MODELOS[e].categoria is not Categoria.DISPUTAS for e in somente)
    assert not MODELOS[Evento.ESTORNO_SOLICITADO].somente_app


# --- portfólio -----------------------------------------------------------------------------------

FOTO = {
    "destino": "portfolio",
    "nome_arquivo": "a.jpg",
    "content_type": "image/jpeg",
    "tamanho_bytes": 1_000,
}


SESSAO_DO_CLIENTE = "t-cliente"


def _enviar_foto(amb, token=SESSAO_DO_CLIENTE):
    return amb.cliente.post("/v1/uploads", json=FOTO, headers=cab(token))


def test_conta_sem_perfil_profissional_nao_envia_foto_de_portfolio(e2):  # noqa: F811
    amb = e2.amb
    r = _enviar_foto(amb)
    assert r.status_code == 403 and "cadastro de profissional" in r.text


def test_conta_dupla_e_profissional_continuam_enviando(e2):  # noqa: F811
    amb = e2.amb
    assert CLIENTE.papel is PapelUsuario.CLIENTE
    amb.contexto.usuarios.profissionais.add(CLIENTE.id)
    for token in ("t-cliente", "t-prof"):
        assert _enviar_foto(amb, token).status_code == 201, token


# --- 5.4: endereço -------------------------------------------------------------------------------

RUA = "Pode vir na Rua das Flores, 123"


def _na_conversa(amb, profissional: str, autor: str = CLIENTE.id):
    contexto = amb.contexto
    conversa = contexto.conversas.abrir("ped-1", profissional)
    nova = contexto.conversas.enviar(conversa, autor, RUA)
    return conversa, lambda: next(m for m in contexto.conversas.listar(conversa) if m.id == nova)


def test_endereco_passa_so_na_conversa_do_contratado(amb):
    amb.semear_pedido(Estado.PAGO_E_RETIDO)
    _, contratado = _na_conversa(amb, PROFISSIONAL.id)
    _, outro = _na_conversa(amb, "pro-nao-contratado")
    assert contratado().texto == RUA and not contratado().mascarada
    assert "Flores" not in outro().texto and AVISO_MASCARA in outro().texto and outro().mascarada


def test_sem_pagamento_ou_cancelado_o_endereco_fica_oculto(amb):
    amb.semear_pedido(Estado.ORCAMENTO_ACEITO)
    _, antes = _na_conversa(amb, PROFISSIONAL.id)
    assert "Flores" not in antes().texto
    pedido = amb.contexto.pedidos.obter("ped-1")
    amb.contexto.pedidos.salvar(replace(pedido, estado=Estado.PAGO_E_RETIDO))
    _, depois = _na_conversa(amb, PROFISSIONAL.id)
    assert depois().texto == RUA
    amb.contexto.pedidos.salvar(replace(pedido, estado=Estado.CANCELADO))
    assert "Flores" not in depois().texto


def test_previa_da_lista_esconde_o_endereco_de_quem_nao_e_o_contratado(amb):
    amb.semear_pedido(Estado.PAGO_E_RETIDO)
    contexto = amb.contexto
    conversa, _ = _na_conversa(amb, "pro-nao-contratado")
    # mensagem antiga, gravada em claro antes desta regra
    lista = contexto.conversas._mensagens[conversa]
    lista[-1] = replace(lista[-1], texto=RUA, mascarada=False)
    previas = amb.cliente.get("/v1/conversas", headers=cab("t-cliente")).json()
    achada = next(c for c in previas if c["id"] == conversa)
    assert "Flores" not in achada["ultima_mensagem"]
