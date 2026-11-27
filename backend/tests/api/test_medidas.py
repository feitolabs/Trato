"""TERMOS-BE-MEDIDAS: privacidade da ausência, exclusividades no painel e medidas de conta
(11.8 e 20). Memória."""

from __future__ import annotations

import threading
from datetime import timedelta

import pytest
from conftest import AGORA, CLIENTE, MEMBROS_EQUIPE, PROFISSIONAL, cab
from test_exclusividade import _pedido
from test_exclusividade_cliente import desistir, ligar, pedir
from test_fluxo_pagamento_e2e import fluxo  # noqa: F401 - fixture
from test_provas_ausencia import com_retencao, contestar
from test_termos_be2 import enviados, ouvir

from trato.api.admin.memoria import EquipeEmMemoria
from trato.api.admin.papeis import PapelEquipe
from trato.api.admin.repositorios import FiltroAuditoria, MembroEquipe
from trato.api.auth import PapelUsuario, Usuario
from trato.api.medidas import aplicar_automatica, encerrar_vencidas
from trato.api.repositorios_app import PerfilDetalhe

PAINEL = "/v1/admin/medidas"
MINHAS = "/v1/me/medidas"


# --- 1) privacidade -------------------------------------------------------------------------------


def test_profissional_nao_le_o_que_o_cliente_escreveu(fluxo):  # noqa: F811
    pid, _, _ = com_retencao(fluxo)
    contestar(fluxo, pid, "Estive internado no hospital.")
    url = f"/v1/pedidos/{pid}/ausencia"
    cliente = fluxo.chamar("GET", url, "t-cliente").json()
    assert cliente["justificativa_texto"] and cliente["contestacao"]["texto"]
    r = fluxo.chamar("GET", url, "t-prof")
    assert r.status_code == 200
    assert "hospital" not in r.text and "atestado" not in r.text
    dados = r.json()
    assert dados["justificativa_texto"] is None and dados["anexos"] == []
    assert dados["contestacao"]["status"] == "aberta" and dados["contestacao"]["texto"] == ""
    chegada = fluxo.chamar(
        "POST",
        f"{url}/chegada",
        "t-prof",
        {"localizacao": {"latitude": -23.5, "longitude": -46.6}},
    )
    assert "hospital" not in chegada.text
    anexos = fluxo.chamar("GET", f"{url}/anexos", "t-cliente").json()
    assert {a["content_type"] for a in anexos if a["url"]} == {"image/png"}


# --- 2) exclusividades ----------------------------------------------------------------------------


def test_painel_lista_exclusividades_do_cliente(amb):
    ligar(amb)
    _pedido(amb)
    eid = pedir(amb).json()["id"]
    desistir(amb, eid)

    def listar(quem="t-mediador", filtro=""):
        return amb.cliente.get(f"/v1/admin/exclusividades{filtro}", headers=cab(quem))

    class Nomes:
        def nomes(self, ids):
            return {i: f"Nome {i}" for i in ids}  # chaves como o repositório devolver

    amb.admin.usuarios = Nomes()
    assert listar("t-financeiro").status_code == 403
    r = listar(filtro=f"?pedido_id=ped-1&cliente_id={CLIENTE.id}&status=cancelada")
    assert r.status_code == 200, r.text
    (item,) = r.json()["itens"]
    assert item["id"] == eid and item["moedas"] == 100 and item["estornada"]
    assert item["estornada_em"] and item["profissional_nome"] == f"Nome {PROFISSIONAL.id}"
    assert listar(filtro="?status=ativa").json()["total"] == 0
    erro = amb.cliente.post(
        "/v1/admin/exclusividades/nao-existe/falha-trato",
        json={"motivo": "Falha registrada no sistema."},
        headers=cab("t-mediador"),
    )
    assert erro.status_code == 404 and erro.json()["codigo"] == "nao_encontrada"


# --- 3) medidas -----------------------------------------------------------------------------------


def preparar(amb):
    for quem in (CLIENTE.id, PROFISSIONAL.id):
        amb.contexto.usuarios.adicionar(PerfilDetalhe(quem, "Pessoa", PapelUsuario.CLIENTE))
    novo = MembroEquipe("eq-lider", PapelEquipe.LIDER_SUPORTE, alcada_centavos=0)
    amb.admin.equipe = EquipeEmMemoria([*MEMBROS_EQUIPE.values(), novo])
    amb.contexto.auth._usuarios["t-lider"] = Usuario("eq-lider", PapelUsuario.EQUIPE)


def aplicar(amb, quem="t-mediador", **extra):
    corpo = {
        "usuario_id": CLIENTE.id,
        "tipo": "suspensao",
        "motivo": "Ofensas no chat do pedido.",
        "clausulas": ["11.4", "20.1"],
        "dias": 7,
    } | extra
    return amb.cliente.post(PAINEL, json=corpo, headers=cab(quem))


def status(amb, quem=CLIENTE.id):
    return amb.contexto.medidas.status.get(quem, "ativo")


def minhas(amb, quem="t-cliente"):
    return amb.cliente.get(MINHAS, headers=cab(quem))


def contesto(amb, mid, versao="Não fui eu.", quem="t-cliente"):
    url = f"{MINHAS}/{mid}/contestacao"
    return amb.cliente.post(url, json={"versao": versao}, headers=cab(quem))


def decide(amb, mid, quem="t-lider", resultado="revertida", **extra):
    corpo = {"resultado": resultado, "resposta": "Revimos as provas do caso."} | extra
    url = f"{PAINEL}/{mid}/contestacao/decisao"
    return amb.cliente.post(url, json=corpo, headers=cab(quem))


def test_aplica_avisa_bloqueia_e_o_usuario_ve_e_contesta(amb):
    preparar(amb)
    _, email = ouvir(amb.cliente.app, amb.contexto)
    r = aplicar(amb, nota_interna="Relato de outra pessoa.")
    assert r.status_code == 201, r.text
    mid = r.json()["id"]
    assert r.json()["protocolo"].startswith("MED-") and status(amb) == "bloqueado"
    assert aplicar(amb, nota_interna="Relato de outra pessoa.").status_code == 200
    assert enviados(email, "Medida na sua conta") == [CLIENTE.id]
    corpo = email.enviados[0].corpo
    assert "Ofensas" in corpo and "11.4" in corpo and "Conteste" in corpo
    amb.contexto.auth.bloqueados.add("t-cliente")
    visto = minhas(amb)
    assert visto.status_code == 200 and "outra pessoa" not in visto.text
    (item,) = visto.json()
    assert item["vigente"] and item["contestavel_ate"].startswith("2026-11-28")
    assert contesto(amb, mid, quem="t-prof").status_code == 404
    assert contesto(amb, mid).status_code == 200
    assert contesto(amb, mid).status_code == 200
    assert contesto(amb, mid, "Outra versão.").json()["codigo"] == "ja_contestada"


def test_detalhe_adiado_avisa_na_hora_so_com_as_clausulas(amb):
    preparar(amb)
    _, email = ouvir(amb.cliente.app, amb.contexto)
    sem = aplicar(amb, detalhe_adiado=True)
    assert sem.status_code == 422 and sem.json()["codigo"] == "falta_justificativa"
    r = aplicar(amb, detalhe_adiado=True, justificativa_adiamento="Investigação em curso.")
    assert r.status_code == 201
    (aviso,) = email.enviados
    assert "Ofensas" not in aviso.corpo and "11.4" in aviso.corpo
    assert "Ofensas" not in minhas(amb).text


@pytest.mark.parametrize(
    "quem,codigo",
    [("t-mediador", 201), ("t-lider", 201), ("t-seguranca", 201), ("t-financeiro", 403),
     ("t-n1", 403), ("t-juridico", 403), ("t-cliente", 403), ("t-prof", 403)],
)  # fmt: skip
def test_quem_aplica(amb, quem, codigo):
    preparar(amb)
    assert aplicar(amb, quem).status_code == codigo
    if codigo == 403:
        assert amb.cliente.get(PAINEL, headers=cab(quem)).status_code == 403
        assert status(amb) == "ativo"


@pytest.mark.parametrize("dias_depois,codigo", [(30, 200), (31, 409)])
def test_prazo_de_30_dias(amb, dias_depois, codigo):
    preparar(amb)
    mid = aplicar(amb, dias=None).json()["id"]
    amb.relogio.avancar(days=dias_depois)
    assert contesto(amb, mid).status_code == codigo


def test_outro_analista_decide_ou_o_mesmo_justifica(amb):
    preparar(amb)
    mid = aplicar(amb).json()["id"]
    contesto(amb, mid)
    mesmo = decide(amb, mid, "t-mediador")
    assert mesmo.status_code == 422 and mesmo.json()["codigo"] == "mesmo_analista"
    codigos = []
    threads = [
        threading.Thread(target=lambda: codigos.append(decide(amb, mid).status_code))
        for _ in range(6)
    ]
    for t in threads:
        t.start()
    for t in threads:
        t.join()
    assert sorted(codigos) == [200] + [409] * 5
    assert status(amb) == "ativo"
    assert minhas(amb).json()[0]["contestacao"]["status"] == "revertida"
    outra = aplicar(amb, motivo="Novo caso de ofensas.").json()["id"]
    contesto(amb, outra)
    r = decide(
        amb, outra, "t-mediador", "alterada", dias_a_partir_de_hoje=2,
        mesmo_analista_justificativa="Não há outro analista de plantão hoje.",
    )  # fmt: skip
    assert r.status_code == 200, r.text
    assert r.json()["fim_em"].startswith("2026-10-31")
    acoes, _ = amb.admin.auditoria.listar(FiltroAuditoria(acao="bloqueio."), 20, 0)
    assert "bloqueio.medida_contestacao_decidida" in {a.acao for a in acoes}


def test_fim_automatico_devolve_a_conta_uma_vez_e_respeita_outra_medida(amb):
    preparar(amb)
    aplicar(amb, dias=3)
    aplicar(amb, tipo="restricao", motivo="Orçamentos repetidos.", dias=10)
    assert status(amb) == "bloqueado"
    assert encerrar_vencidas(amb.contexto, AGORA + timedelta(days=2)) == 0
    amb.relogio.avancar(days=3, minutes=1)
    assert encerrar_vencidas(amb.contexto, amb.relogio.agora) == 1
    assert encerrar_vencidas(amb.contexto, amb.relogio.agora) == 0
    assert status(amb) == "restrito"
    amb.relogio.avancar(days=8)
    assert encerrar_vencidas(amb.contexto, amb.relogio.agora) == 1
    assert status(amb) == "ativo"


def test_automatica_nunca_passa_de_72_horas(amb):
    medida, _ = aplicar_automatica(
        amb.contexto, CLIENTE.id, "restricao", "Alerta automático.", ("20.2",), horas=500
    )
    assert medida.fim_em == AGORA + timedelta(hours=72) and medida.origem == "automatica"
    assert medida.aplicada_por is None
    for tipo in ("encerramento", "suspensao"):
        with pytest.raises(ValueError):
            aplicar_automatica(amb.contexto, CLIENTE.id, tipo, "x" * 12, ("20.2",))


def test_contato_no_atendimento_com_conta_existente(amb):
    preparar(amb)
    corpo = {
        "canal": "telefone",
        "categoria": "duvida",
        "assunto": "Ligação",
        "texto": "Pediu ajuda.",
        "usuario_id": CLIENTE.id,
    }
    r = amb.cliente.post("/v1/admin/chamados", json=corpo, headers=cab("t-n1"))
    assert r.status_code == 201, r.text
    corpo["usuario_id"] = "nao-existe"
    r = amb.cliente.post("/v1/admin/chamados", json=corpo, headers=cab("t-n1"))
    assert r.status_code == 404


def test_sem_a_tabela_503_com_codigo(amb, monkeypatch):
    preparar(amb)
    monkeypatch.setattr(amb.contexto.medidas, "disponivel", lambda: False)
    for r in (aplicar(amb), minhas(amb), amb.cliente.get(PAINEL, headers=cab("t-mediador"))):
        assert r.status_code == 503 and r.json()["codigo"] == "indisponivel"
    assert amb.cliente.get("/v1/me/moedas", headers=cab("t-cliente")).status_code == 200
