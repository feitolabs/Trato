"""TERMOS-BE-SAC: atendimento do usuário e do painel (25.3 a 25.5, 20.5), leitura da conversa com o
original (11.3) e créditos de Tratinhos por validade (13.4). Memória."""

from __future__ import annotations

import threading
from dataclasses import replace
from datetime import datetime, timedelta

import pytest
from conftest import AGORA, CLIENTE, PROFISSIONAL, cab
from test_exclusividade_cliente import ligar
from test_termos_be2 import enviados, ouvir

from trato.api.admin.repositorios import FiltroAuditoria
from trato.pedidos.estados import Estado
from trato.persistencia.chamados import ASSUNTO

URL = "/v1/sac/chamados"
PAINEL = "/v1/admin/chamados"
NOVO = {"categoria": "duvida", "assunto": "Não consigo pagar", "texto": "O Pix não abre."}


def abrir(amb, quem="t-cliente", **extra):
    return amb.cliente.post(URL, json=NOVO | extra, headers=cab(quem))


def ver(amb, cid, quem="t-cliente"):
    return amb.cliente.get(f"{URL}/{cid}", headers=cab(quem))


def falar(amb, cid, texto="Ainda não abre.", quem="t-cliente"):
    url = f"{URL}/{cid}/mensagens"
    return amb.cliente.post(url, json={"texto": texto}, headers=cab(quem))


def painel(amb, caminho="", quem="t-n1", corpo=None):
    if corpo is None and caminho.count("/") < 2:
        return amb.cliente.get(PAINEL + caminho, headers=cab(quem))
    return amb.cliente.post(PAINEL + caminho, json=corpo, headers=cab(quem))


def test_abre_com_protocolo_prazo_e_confirmacao(amb):
    _, email = ouvir(amb.cliente.app, amb.contexto)
    r = abrir(amb)
    assert r.status_code == 201, r.text
    dados = r.json()
    assert dados["protocolo"].startswith("SAC-2026-") and dados["status"] == "aberto"
    # AGORA é quinta 29/10; 5 dias úteis pulam o fim de semana
    assert dados["responder_ate"].startswith("2026-11-05")
    assert [m["autor"] for m in dados["mensagens"]] == ["usuario"]
    assert enviados(email, "Recebemos o seu contato") == [CLIENTE.id]
    assert dados["protocolo"] in email.enviados[0].corpo
    repetido = abrir(amb)
    assert repetido.status_code == 200 and repetido.json()["id"] == dados["id"]
    assert len(enviados(email, "Recebemos o seu contato")) == 1


def test_feriado_da_configuracao_e_dados_pessoais_em_15_dias(amb):
    config = amb.contexto.config
    atual = config.carregar()
    feriados = frozenset({AGORA.date() + timedelta(days=1)})
    config._config = replace(atual, disputas=replace(atual.disputas, feriados=feriados))
    assert abrir(amb).json()["responder_ate"].startswith("2026-11-06")
    lgpd = abrir(amb, categoria="dados_pessoais", assunto="Meus dados").json()
    assert datetime.fromisoformat(lgpd["responder_ate"]) == AGORA + timedelta(days=15)


def test_oito_toques_juntos_um_chamado(amb):
    respostas = []
    threads = [threading.Thread(target=lambda: respostas.append(abrir(amb))) for _ in range(8)]
    for t in threads:
        t.start()
    for t in threads:
        t.join()
    assert sorted(r.status_code for r in respostas) == [200] * 7 + [201]
    assert len({r.json()["id"] for r in respostas}) == 1


@pytest.mark.parametrize("quem", ["t-cliente", "t-prof"])
def test_conta_bloqueada_abre_e_acompanha(amb, quem):
    amb.contexto.auth.bloqueados.add(quem)
    assert amb.cliente.get("/v1/me/moedas", headers=cab(quem)).status_code == 403
    r = abrir(amb, quem)
    assert r.status_code == 201, r.text
    cid = r.json()["id"]
    assert ver(amb, cid, quem).status_code == 200
    assert falar(amb, cid, quem=quem).status_code == 200
    assert amb.cliente.get(URL, headers=cab(quem)).json()["total"] == 1


def test_so_o_dono_ve_e_pedido_alheio_nao_serve(amb):
    cid = abrir(amb).json()["id"]
    assert ver(amb, cid, "t-prof").status_code == 404
    assert falar(amb, cid, quem="t-outro-cliente").status_code == 404
    assert amb.cliente.get(URL, headers=cab("t-prof")).json()["total"] == 0
    amb.semear_pedido(Estado.PAGO_E_RETIDO)
    assert abrir(amb, "t-outro-cliente", pedido_id="ped-1").status_code == 404
    assert abrir(amb, "t-mediador").status_code == 403
    assert amb.cliente.get(URL).status_code == 401
    assert abrir(amb, assunto=ASSUNTO).status_code == 422


def test_painel_responde_com_nota_interna_prazo_e_encerra(amb):
    _, email = ouvir(amb.cliente.app, amb.contexto)
    cid = abrir(amb).json()["id"]
    assert painel(amb, f"/{cid}/assumir", corpo={}).status_code == 200
    r = painel(amb, f"/{cid}/mensagens", corpo={"texto": "Ver com o financeiro", "interna": True})
    assert r.status_code == 200 and r.json()["status"] == "em_atendimento"
    for _ in range(2):  # repetir não duplica
        r = painel(amb, f"/{cid}/mensagens", corpo={"texto": "Tente atualizar o app."})
    assert r.json()["status"] == "respondido" and r.json()["primeira_resposta_em"]
    assert len(r.json()["mensagens"]) == 3
    copia = ver(amb, cid).json()
    assert [m["autor"] for m in copia["mensagens"]] == ["usuario", "equipe"]
    assert "financeiro" not in str(copia) and "autor_id" not in str(copia)
    ate = (AGORA + timedelta(days=20)).isoformat()
    cedo = {"novo_prazo_ate": AGORA.isoformat(), "motivo": "Falta o retorno do banco."}
    assert painel(amb, f"/{cid}/prazo", corpo=cedo).status_code == 422
    for _ in range(2):
        r = painel(amb, f"/{cid}/prazo", corpo=cedo | {"novo_prazo_ate": ate})
        assert r.status_code == 200, r.text
    copia = ver(amb, cid).json()
    assert copia["motivo_extensao"] == "Falta o retorno do banco."
    assert copia["mensagens"][-1]["autor"] == "sistema" and "banco" in str(copia["mensagens"][-1])
    assert enviados(email, "Novo prazo do atendimento") == [CLIENTE.id]
    fim = {"mensagem": "Resolvido com a atualização."}
    assert painel(amb, f"/{cid}/encerrar", corpo=fim).json()["status"] == "encerrado"
    assert painel(amb, f"/{cid}/encerrar", corpo=fim).status_code == 409
    assert painel(amb, f"/{cid}/mensagens", corpo={"texto": "mais"}).status_code == 409
    assert falar(amb, cid, "reabre?").status_code == 409
    acoes, _total = amb.admin.auditoria.listar(FiltroAuditoria(acao="suporte."), 20, 0)
    assert {a.acao for a in acoes} == {
        "suporte.chamado_assumido",
        "suporte.chamado_prazo",
        "suporte.chamado_encerrado",
    }


@pytest.mark.parametrize(
    "quem", ["t-financeiro", "t-mediador", "t-seguranca", "t-juridico", "t-cliente", "t-prof"]
)
def test_sem_permissao_nao_ve_nem_responde(amb, quem):
    cid = abrir(amb).json()["id"]
    assert painel(amb, "", quem).status_code == 403
    assert painel(amb, f"/{cid}", quem).status_code == 403
    for rota, corpo in (
        ("assumir", {}),
        ("mensagens", {"texto": "oi"}),
        ("encerrar", {"mensagem": "Encerrado sem motivo."}),
    ):
        assert painel(amb, f"/{cid}/{rota}", quem, corpo).status_code == 403
    contato = NOVO | {"canal": "telefone", "contato": "31999999999"}
    assert amb.cliente.post(PAINEL, json=contato, headers=cab(quem)).status_code == 403


def test_contato_por_telefone_filtros_e_paginacao(amb):
    sem = amb.cliente.post(PAINEL, json=NOVO | {"canal": "telefone"}, headers=cab("t-n1"))
    assert sem.status_code == 422
    corpo = NOVO | {"canal": "telefone", "contato": "31999999999", "nome_contato": "Ana"}
    r = amb.cliente.post(PAINEL, json=corpo, headers=cab("t-n1"))
    assert r.status_code == 201, r.text
    assert r.json()["protocolo"] and r.json()["solicitante"] == "Ana"
    abrir(amb, categoria="seguranca", assunto="Conta invadida")
    tudo = painel(amb, "?limite=1").json()
    assert tudo["total"] == 2 and len(tudo["itens"]) == 1
    assert painel(amb, "?categoria=seguranca").json()["itens"][0]["prioridade"] == "alta"
    assert painel(amb, "?atrasados=true").json()["total"] == 0
    amb.relogio.avancar(days=30)
    assert painel(amb, "?atrasados=true").json()["total"] == 2


def test_dois_analistas_assumem_so_um(amb):
    from conftest import MEMBROS_EQUIPE

    from trato.api.admin.memoria import EquipeEmMemoria
    from trato.api.admin.papeis import PapelEquipe
    from trato.api.admin.repositorios import MembroEquipe
    from trato.api.auth import PapelUsuario, Usuario

    amb.admin.equipe = EquipeEmMemoria(
        [*MEMBROS_EQUIPE.values(), MembroEquipe("eq-n2", PapelEquipe.ATENDENTE_N2)]
    )
    amb.contexto.auth._usuarios["t-n2"] = Usuario("eq-n2", PapelUsuario.EQUIPE)
    cid = abrir(amb).json()["id"]
    codigos = []
    threads = [
        threading.Thread(
            target=lambda q=q: codigos.append(painel(amb, f"/{cid}/assumir", q, {}).status_code)
        )
        for q in ("t-n1", "t-n2")
    ]
    for t in threads:
        t.start()
    for t in threads:
        t.join()
    assert sorted(codigos) == [200, 409]
    assert painel(amb, f"/{cid}/assumir", "t-n2", {"substituir": True}).status_code == 200


def test_sem_a_tabela_responde_503_e_o_resto_segue(amb, monkeypatch):
    monkeypatch.setattr(amb.contexto.sac, "disponivel", lambda: False)
    assert abrir(amb).status_code == 503
    assert painel(amb, "").status_code == 503
    assert amb.cliente.get("/v1/me/moedas", headers=cab("t-cliente")).status_code == 200


# --- 11.3 e 13.4 ---------------------------------------------------------------------------------


def test_leitura_devolve_o_original_marcando_o_mascarado(amb):
    amb.semear_pedido(Estado.PAGO_E_RETIDO)
    conversa = amb.contexto.conversas.abrir("ped-1", PROFISSIONAL.id)
    amb.contexto.conversas.enviar(conversa, CLIENTE.id, "me paga por fora no joao@gmail.com")
    from conftest import MEMBROS_EQUIPE

    from trato.api.admin.memoria import EquipeEmMemoria
    from trato.api.admin.papeis import PapelEquipe
    from trato.api.admin.repositorios import MembroEquipe
    from trato.api.auth import PapelUsuario, Usuario

    admin = MembroEquipe("eq-admin", PapelEquipe.ADMINISTRADOR)
    amb.admin.equipe = EquipeEmMemoria([*MEMBROS_EQUIPE.values(), admin])
    amb.contexto.auth._usuarios["t-admin"] = Usuario("eq-admin", PapelUsuario.EQUIPE)
    r = amb.cliente.post(
        "/v1/admin/pedidos/ped-1/conversas/leitura",
        json={
            "motivo": "Ordem judicial recebida.",
            "base": "ordem_judicial",
            "referencia": "0001234-55",
        },
        headers=cab("t-admin"),
    )
    assert r.status_code == 200, r.text
    (msg,) = r.json()["conversas"][0]["mensagens"]
    assert msg["texto"] == "me paga por fora no joao@gmail.com" and msg["mascarada"]
    assert "joao@gmail.com" not in msg["texto_exibido"]
    do_app = amb.cliente.get("/v1/pedidos/ped-1/mensagens", headers=cab("t-prof")).text
    assert "joao@gmail.com" not in do_app


def test_moedas_trazem_creditos_por_validade(amb):
    ligar(amb, (60, 30), (240, 90), (10, -1))
    r = amb.cliente.get("/v1/me/moedas", headers=cab("t-cliente"))
    assert r.status_code == 200, r.text
    creditos = r.json()["creditos"]
    assert [c["moedas"] for c in creditos] == [60, 240]
    assert creditos[0]["expira_em"] < creditos[1]["expira_em"]
    assert sum(c["moedas"] for c in creditos) == r.json()["saldo"]
