"""TERMOS-BE-PROVAS: provas da ausência com link curto, contestação da retenção (8.7), campos do
painel e leitura auditada das conversas (11.3). Memória e provedor falso."""

from __future__ import annotations

import threading
from datetime import timedelta

import pytest
from conftest import AGORA, CLIENTE, MEMBROS_EQUIPE, PROFISSIONAL
from test_ausencia_cliente import (
    LONGE,
    RETENCAO,
    justificar,
    painel,
    registrado,
    remarcado_para_longe,
    ver,
)
from test_desistencia import desistir, iniciado
from test_fluxo_pagamento_e2e import VALOR, Fluxo, fluxo  # noqa: F401 - fixtures
from test_termos_m2_dinheiro import total_estornado

from trato.api.admin.memoria import EquipeEmMemoria
from trato.api.admin.papeis import PapelEquipe
from trato.api.admin.repositorios import FiltroAuditoria, MembroEquipe
from trato.api.auth import PapelUsuario, Usuario
from trato.pedidos.estados import Estado
from trato.uploads.servico import Midia, UploadsEmMemoria

SETE_UTEIS = timedelta(days=10)


class Arquivos:
    """Serviço de envio mínimo: só o que a leitura das provas usa."""

    def __init__(self) -> None:
        self.repo = UploadsEmMemoria()
        self.armazenamento = self

    def url_leitura(self, bucket: str, caminho: str, segundos: int) -> str:
        return f"https://arquivos.test/{bucket}/{caminho}?expira={segundos}"

    def guardar(self, arquivo: str, pedido: str, quem: str) -> None:
        self.repo.salvar_midia(
            Midia(arquivo, pedido, quem, "disputa", "pedido-midias", arquivo, "image/png",
                  10, "0" * 64, AGORA)
        )  # fmt: skip


def lider(f: Fluxo) -> None:
    """Segundo analista com permissão de decidir."""
    novo = MembroEquipe("eq-lider", PapelEquipe.LIDER_SUPORTE, alcada_centavos=10**9)
    admin = MembroEquipe("eq-admin", PapelEquipe.ADMINISTRADOR)
    f.amb.admin.equipe = EquipeEmMemoria([*MEMBROS_EQUIPE.values(), novo, admin])
    f.ctx.auth._usuarios["t-lider"] = Usuario("eq-lider", PapelUsuario.EQUIPE)
    f.ctx.auth._usuarios["t-admin"] = Usuario("eq-admin", PapelUsuario.EQUIPE)


def com_retencao(f: Fluxo) -> tuple[str, str, Arquivos]:
    lider(f)
    pid, cobranca = remarcado_para_longe(f)
    registrado(f, pid, LONGE)
    arquivos = Arquivos()
    arquivos.guardar("nota-1", pid, PROFISSIONAL.id)
    arquivos.guardar("atestado", pid, CLIENTE.id)
    arquivos.guardar("de-outro", "outro-pedido", PROFISSIONAL.id)
    f.http.app.state.servico_uploads = arquivos
    r = f.chamar(
        "POST",
        f"/v1/pedidos/{pid}/ausencia/justificativa",
        "t-cliente",
        {"texto": "Estava no hospital.", "anexos": [anexo("atestado")]},
    )
    assert r.status_code == 200, r.text
    r = painel(f, pid, **RETENCAO)
    assert r.status_code == 200, r.text
    return pid, cobranca, arquivos


def anexo(arquivo: str) -> dict:
    return {"arquivo_id": arquivo, "tirada_em": AGORA.isoformat()}


def contestar(f: Fluxo, pid: str, texto="Não considerou o atestado.", quem="t-cliente"):
    url = f"/v1/pedidos/{pid}/ausencia/contestacao"
    return f.chamar("POST", url, quem, {"texto": texto})


def responder(f: Fluxo, pid: str, quem="t-lider", resultado="mantida", **extra):
    corpo = {"resultado": resultado, "resposta": "Conferimos o atestado enviado."} | extra
    return f.chamar("POST", f"/v1/admin/ausencias/{pid}/contestacao/decisao", quem, corpo)


def confirmar(f: Fluxo, pid: str, quem="t-mediador", **extra):
    return painel(f, pid, quem, "confirmar", **extra)


def auditoria(f: Fluxo, acao: str) -> list:
    linhas, _ = f.amb.admin.auditoria.listar(FiltroAuditoria(acao=acao), 50, 0)
    return list(linhas)


# --- 1) provas com link curto --------------------------------------------------------------------


def test_cliente_ve_a_prova_antes_da_cobranca_e_o_profissional_so_as_dele(fluxo):  # noqa: F811
    pid, _, _ = com_retencao(fluxo)
    url = f"/v1/pedidos/{pid}/ausencia/anexos"
    do_cliente = fluxo.chamar("GET", url, "t-cliente").json()
    por_id = {a["arquivo_id"]: a for a in do_cliente}
    assert por_id["nota-1"]["tipo"] == "comprovante_retencao"
    assert por_id["nota-1"]["url"].endswith("expira=300")
    assert por_id["atestado"]["enviado_por"] == "cliente" and por_id["atestado"]["url"]
    do_pro = fluxo.chamar("GET", url, "t-prof").json()
    assert [a["arquivo_id"] for a in do_pro] == ["nota-1"]
    assert fluxo.chamar("GET", url, "t-outro-cliente").status_code in (403, 404)
    fluxo.http.app.state.servico_uploads = None
    assert fluxo.chamar("GET", url, "t-cliente").status_code == 503


def test_painel_ve_os_links_com_permissao_e_auditoria(fluxo):  # noqa: F811
    pid, _, _ = com_retencao(fluxo)
    url = f"/v1/admin/ausencias/{pid}/anexos"
    corpo = {"motivo": "Conferir as provas do caso."}
    for quem in ("t-financeiro", "t-cliente", "t-prof"):
        assert fluxo.chamar("POST", url, quem, corpo).status_code == 403
    # o GET (motivo na URL) saiu
    assert fluxo.chamar("GET", f"{url}?motivo=Conferir+as+provas", "t-mediador").status_code == 405
    for ruim in ({}, {"motivo": "curto"}, {"motivo": " " * 20}, {"motivo": "x" * 501}):
        assert fluxo.chamar("POST", url, "t-mediador", ruim).status_code == 422, ruim
    assert fluxo.chamar("POST", f"{url}?motivo=Pela+URL+nao+vale", "t-mediador").status_code == 422
    assert auditoria(fluxo, "dado_pessoal.ausencia_anexos_vistos") == []
    r = fluxo.chamar("POST", url, "t-mediador", corpo)
    assert r.status_code == 200, r.text
    por_id = {a["arquivo_id"]: a["url"] for a in r.json()}
    assert por_id["nota-1"] and por_id["atestado"]
    assert por_id["f1"] is None  # foto sem arquivo guardado neste pedido: sem link
    (linha,) = auditoria(fluxo, "dado_pessoal.ausencia_anexos_vistos")
    assert linha.ator_id == "eq-med" and linha.motivo == corpo["motivo"]


@pytest.mark.parametrize("arquivo", ["de-outro", "nota-1", "nao-existe"])
def test_justificativa_so_com_arquivo_proprio_deste_pedido(fluxo, arquivo):  # noqa: F811
    pid, _ = remarcado_para_longe(fluxo)
    registrado(fluxo, pid, LONGE)
    arquivos = Arquivos()
    arquivos.guardar("de-outro", "outro-pedido", CLIENTE.id)
    arquivos.guardar("nota-1", pid, PROFISSIONAL.id)
    fluxo.http.app.state.servico_uploads = arquivos
    r = fluxo.chamar(
        "POST",
        f"/v1/pedidos/{pid}/ausencia/justificativa",
        "t-cliente",
        {"texto": "Veja.", "anexos": [anexo(arquivo)]},
    )
    assert r.status_code == 422 and ver(fluxo, pid).json()["status"] == "aguardando_justificativa"


def test_comprovante_de_outro_pedido_e_recusado(fluxo):  # noqa: F811
    pid, _ = remarcado_para_longe(fluxo)
    registrado(fluxo, pid, LONGE)
    justificar(fluxo, pid)
    arquivos = Arquivos()
    arquivos.guardar("de-outro", "outro-pedido", PROFISSIONAL.id)
    fluxo.http.app.state.servico_uploads = arquivos
    r = painel(fluxo, pid, **(RETENCAO | {"retencao_comprovantes": ["de-outro"]}))
    assert r.status_code == 422


# --- 2) contestação ------------------------------------------------------------------------------


def test_sem_contestacao_so_confirma_depois_dos_5_dias_uteis(fluxo):  # noqa: F811
    pid, cobranca, _ = com_retencao(fluxo)
    limite = ver(fluxo, pid).json()["contestar_ate"]
    assert confirmar(fluxo, pid).status_code == 409
    assert fluxo.servico.ordens.do_pedido(pid) == []
    fluxo.amb.relogio.avancar(days=10)
    assert fluxo.amb.relogio.agora.isoformat() > limite[:19]
    assert contestar(fluxo, pid).status_code == 409  # prazo encerrado
    r = confirmar(fluxo, pid)
    assert r.status_code == 200, r.text
    assert total_estornado(fluxo, cobranca) == VALOR - 30_000
    ultima = auditoria(fluxo, "financeiro.ausencia_cliente_decidida")
    assert any(i.motivo == "Conferido o prazo de contestação." for i in ultima)


def test_confirmar_exige_motivo(fluxo):  # noqa: F811
    pid, _, _ = com_retencao(fluxo)
    url = f"/v1/admin/ausencias/{pid}/confirmar"
    for corpo in ({}, {"motivo": "curto"}, {"retirar_retencao": True}):
        assert fluxo.chamar("POST", url, "t-mediador", corpo).status_code == 422


def test_contestada_nada_move_e_outro_analista_responde(fluxo):  # noqa: F811
    pid, cobranca, _ = com_retencao(fluxo)
    assert contestar(fluxo, pid, quem="t-prof").status_code == 403
    primeira = contestar(fluxo, pid)
    assert primeira.status_code == 200, primeira.text
    assert primeira.json()["contestacao"]["status"] == "aberta"
    assert contestar(fluxo, pid).json() == primeira.json()
    assert contestar(fluxo, pid, "Outra coisa.").status_code == 409
    fluxo.amb.relogio.avancar(days=30)
    for retirar in (False, True):
        assert confirmar(fluxo, pid, retirar_retencao=retirar).status_code == 409
    assert fluxo.servico.ordens.do_pedido(pid) == []
    r = responder(fluxo, pid, "t-mediador")
    assert r.status_code == 403 and "8.7" in r.text
    assert responder(fluxo, pid, "t-financeiro").status_code == 403
    assert responder(fluxo, pid, resultado="alterada").status_code == 422
    alto = responder(fluxo, pid, resultado="alterada", retencao_centavos=30_000)
    assert alto.status_code == 422
    r = responder(fluxo, pid, resultado="alterada", retencao_centavos=10_000)
    assert r.status_code == 200, r.text
    assert r.json()["retencao_centavos"] == 10_000
    assert r.json()["contestacao"]["status"] == "alterada"
    assert responder(fluxo, pid).status_code == 409
    assert fluxo.servico.ordens.do_pedido(pid) == []
    assert confirmar(fluxo, pid).status_code == 200
    assert total_estornado(fluxo, cobranca) == VALOR - 10_000


def test_revertida_devolve_tudo_so_na_confirmacao(fluxo):  # noqa: F811
    pid, cobranca, _ = com_retencao(fluxo)
    contestar(fluxo, pid)
    assert responder(fluxo, pid, resultado="revertida").status_code == 200
    assert fluxo.ctx.pedidos.obter(pid).estado is Estado.AGENDADO
    assert confirmar(fluxo, pid).status_code == 200
    assert total_estornado(fluxo, cobranca) == VALOR


def test_seis_contestacoes_e_respostas_juntas(fluxo):  # noqa: F811
    pid, _, _ = com_retencao(fluxo)
    for chamada, esperado in ((lambda: contestar(fluxo, pid), [200] * 6), (None, None)):
        if chamada is None:
            chamada, esperado = (lambda: responder(fluxo, pid)), [200] + [409] * 5
        codigos: list[int] = []
        threads = [
            threading.Thread(target=lambda c=chamada, s=codigos: s.append(c().status_code))
            for _ in range(6)
        ]
        for t in threads:
            t.start()
        for t in threads:
            t.join()
        assert sorted(codigos) == esperado
    assert len(fluxo.ctx.chamados._revisoes) == 1


# --- 3) painel -----------------------------------------------------------------------------------


def test_painel_traz_valor_do_servico_nomes_e_numero(fluxo):  # noqa: F811
    pid, _, _ = com_retencao(fluxo)

    class Rotulos:
        def rotulos(self, ids):
            return {i: (42, "Pintura") for i in ids}

    class Nomes:
        def nomes(self, ids):
            return {i: f"Nome {i}" for i in ids}

    fluxo.amb.admin.pedidos, fluxo.amb.admin.usuarios = Rotulos(), Nomes()
    dados = fluxo.chamar("GET", f"/v1/admin/ausencias/{pid}", "t-mediador").json()
    assert dados["pedido_numero"] == 42 and dados["valor_servico_centavos"] == VALOR
    assert dados["cliente_nome"] == f"Nome {CLIENTE.id}"
    assert dados["profissional_nome"] == f"Nome {PROFISSIONAL.id}"
    assert ver(fluxo, pid).json()["cliente_nome"] is None  # no app não vai


def test_fila_de_disputas_marca_a_desistencia(fluxo):  # noqa: F811
    pid = iniciado(fluxo, True)
    desistir(fluxo, pid)

    class Vazio:
        def rotulos(self, ids):
            return {}

        def nomes(self, ids):
            return {}

    fluxo.amb.admin.pedidos = fluxo.amb.admin.usuarios = Vazio()
    r = fluxo.chamar("GET", "/v1/admin/disputas", "t-mediador")
    (item,) = r.json()["itens"]
    assert item["pedido_id"] == pid and item["desistencia"] is True


# --- 4) conversas (11.3) -------------------------------------------------------------------------


def _com_conversa(f: Fluxo) -> str:
    pid = f.aceitar()
    f.pagar(pid)
    conversa = f.ctx.conversas.abrir(pid, PROFISSIONAL.id)
    f.ctx.conversas.enviar(conversa, CLIENTE.id, "Combinado para sexta.")
    return pid


def ler(f: Fluxo, pid: str, quem="t-mediador", base="ordem_judicial", **extra):
    corpo = {"motivo": "Pedido de análise do caso.", "base": base} | extra
    return f.chamar("POST", f"/v1/admin/pedidos/{pid}/conversas/leitura", quem, corpo)


@pytest.mark.parametrize(
    "quem,codigo",
    [
        ("t-mediador", 200),
        ("t-seguranca", 200),
        ("t-lider", 200),
        ("t-financeiro", 403),
        ("t-n1", 403),
        ("t-juridico", 403),
        ("t-moderador", 403),
        ("t-cliente", 403),
        ("t-prof", 403),
    ],
)
def test_quem_pode_ler(fluxo, quem, codigo):  # noqa: F811
    lider(fluxo)
    pid = _com_conversa(fluxo)
    fluxo.ctx.chamados.vinculos.add(("relato", pid))
    r = ler(fluxo, pid, quem, base="relato")
    assert r.status_code == codigo, r.text
    assert ("Combinado" in r.text) is (codigo == 200)
    assert len(auditoria(fluxo, "dado_pessoal.conversa_lida")) == (1 if codigo == 200 else 0)


@pytest.mark.parametrize(
    "base", ["relato", "disputa", "denuncia", "incidente", "fraude", "autorizacao_usuario"]
)
def test_sem_vinculo_nada_e_lido(fluxo, base):  # noqa: F811
    pid = _com_conversa(fluxo)
    r = ler(fluxo, pid, base=base, referencia="SAC-2026-000001")
    assert r.status_code == 409 and "Combinado" not in r.text
    assert auditoria(fluxo, "dado_pessoal.conversa_lida") == []
    fluxo.ctx.chamados.vinculos.add((base, pid))
    if base == "disputa":
        return  # só a disputa do próprio pedido vale
    assert ler(fluxo, pid, base=base, referencia="SAC-2026-000001").status_code == 200


def test_motivo_base_e_referencia_obrigatorios(fluxo):  # noqa: F811
    pid = _com_conversa(fluxo)
    assert ler(fluxo, pid, motivo="curto").status_code == 422
    assert ler(fluxo, pid, base="curiosidade").status_code == 422
    lider(fluxo)
    assert ler(fluxo, pid, "t-admin").status_code == 409  # ordem judicial sem número
    assert ler(fluxo, "nao-existe").status_code == 404


def test_sem_auditoria_o_texto_nao_sai(fluxo, monkeypatch):  # noqa: F811
    pid = _com_conversa(fluxo)

    def fora(**_):
        raise RuntimeError("auditoria fora")

    monkeypatch.setattr(fluxo.amb.admin.auditoria, "registrar", fora)
    lider(fluxo)
    with pytest.raises(RuntimeError):
        ler(fluxo, pid, "t-admin", referencia="0001234-55.2026")
