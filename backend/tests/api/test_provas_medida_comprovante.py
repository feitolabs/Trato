"""TERMOS-BE-PROVAS (06h): comprovante da retenção pelo painel (8.7), provas na contestação de
medida (20.5) e campos novos de medidas, chamados e avisos."""

from __future__ import annotations

import threading

from conftest import AGORA, CLIENTE, PROFISSIONAL, cab
from test_ausencia_cliente import (
    LONGE,
    RETENCAO,
    justificar,
    painel,
    registrado,
    remarcado_para_longe,
)
from test_fluxo_pagamento_e2e import fluxo  # noqa: F401 - fixture
from test_medidas import aplicar, contesto, decide, minhas, preparar
from test_profissional_upload import JPEG_COM_EXIF, png_com_texto
from test_provas_ausencia import auditoria, com_retencao, contestar
from test_termos_be2 import ouvir

from trato.seguranca.config import obter_config_seguranca
from trato.uploads import ArmazenamentoFake
from trato.uploads.config import ConfigUploads
from trato.uploads.servico import Midia, ServicoUploads, UploadsEmMemoria

MOTIVO = {"motivo": "Conferir os custos do caso."}


def arquivos(app, relogio) -> ServicoUploads:
    servico = ServicoUploads(
        ArmazenamentoFake(), UploadsEmMemoria(), obter_config_seguranca(), ConfigUploads(), relogio
    )
    app.state.servico_uploads = servico
    return servico


# --- 1) comprovante da retenção ------------------------------------------------------------------


def _caso(f):
    pid, _ = remarcado_para_longe(f)
    registrado(f, pid, LONGE)
    justificar(f, pid)
    servico = arquivos(f.http.app, f.amb.relogio)

    def midia(mid, pedido, quem, finalidade="nota_material"):
        bucket = "chat-anexos" if finalidade == "chat" else "pedido-midias"
        servico.repo.salvar_midia(
            Midia(mid, pedido, quem, finalidade, bucket, mid, "image/png", 10, "0" * 64, AGORA)
        )

    midia("do-pro", pid, PROFISSIONAL.id)
    midia("do-cliente", pid, CLIENTE.id, "disputa")
    midia("do-chat", pid, PROFISSIONAL.id, "chat")
    midia("de-outro", "outro-pedido", PROFISSIONAL.id)
    return pid, servico


def _painel(f, pid, caminho="", quem="t-mediador", corpo=None):
    url = f"/v1/admin/ausencias/{pid}/arquivos{caminho}"
    return f.chamar("POST", url, quem, MOTIVO if corpo is None else corpo)


def test_lista_so_o_que_comprova_com_auditoria_e_motivo_no_corpo(fluxo):  # noqa: F811
    pid, _ = _caso(fluxo)
    for quem in ("t-financeiro", "t-cliente", "t-prof"):
        assert _painel(fluxo, pid, quem=quem).status_code == 403
    for ruim in ({}, {"motivo": "curto"}, {"motivo": " " * 12}):
        assert _painel(fluxo, pid, corpo=ruim).status_code == 422
    url = f"/v1/admin/ausencias/{pid}/arquivos?motivo=pela+url+nao"
    assert fluxo.chamar("GET", url, "t-mediador").status_code == 405
    assert auditoria(fluxo, "dado_pessoal.ausencia_arquivos_listados") == []
    r = _painel(fluxo, pid)
    assert r.status_code == 200, r.text
    (item,) = r.json()
    assert item["arquivo_id"] == "do-pro" and item["enviado_por"] == "profissional"
    assert item["url"] and item["content_type"] == "image/png"
    (linha,) = auditoria(fluxo, "dado_pessoal.ausencia_arquivos_listados")
    assert linha.motivo == MOTIVO["motivo"]


def test_so_comprovante_da_lista_vale_na_retencao(fluxo):  # noqa: F811
    pid, _ = _caso(fluxo)
    for ruim in ("do-cliente", "do-chat", "de-outro", "nao-existe"):
        r = painel(fluxo, pid, **(RETENCAO | {"retencao_comprovantes": [ruim]}))
        assert r.status_code == 422, ruim
    r = painel(fluxo, pid, **(RETENCAO | {"retencao_comprovantes": ["do-pro"]}))
    assert r.status_code == 200, r.text


def test_analista_envia_comprovante_novo_e_usa_na_retencao(fluxo):  # noqa: F811
    pid, servico = _caso(fluxo)
    pedido = MOTIVO | {
        "nome_arquivo": "nota.jpg",
        "content_type": "image/jpeg",
        "tamanho_bytes": len(JPEG_COM_EXIF),
    }
    assert _painel(fluxo, pid, "/envio", "t-financeiro", pedido).status_code == 403
    pdf = pedido | {"content_type": "application/pdf"}
    assert _painel(fluxo, pid, "/envio", corpo=pdf).status_code == 422
    r = _painel(fluxo, pid, "/envio", corpo=pedido)
    assert r.status_code == 201, r.text
    envio = r.json()["envio_id"]
    concluir = f"/envio/{envio}/concluir"
    assert _painel(fluxo, pid, concluir).status_code == 409  # ainda não enviou o arquivo
    sol = servico.repo.solicitacao(envio)
    servico.armazenamento.simular_envio(sol.bucket, sol.caminho, JPEG_COM_EXIF)
    assert _painel(fluxo, "outro", concluir).status_code == 404
    primeiro = _painel(fluxo, pid, concluir)
    assert primeiro.status_code == 200, primeiro.text
    assert primeiro.json()["enviado_por"] == "equipe"
    assert _painel(fluxo, pid, concluir).json()["arquivo_id"] == primeiro.json()["arquivo_id"]
    novo = primeiro.json()["arquivo_id"]
    assert novo in {a["arquivo_id"] for a in _painel(fluxo, pid).json()}
    assert b"GPS" not in servico.armazenamento.ler(sol.bucket, sol.caminho)
    r = painel(fluxo, pid, **(RETENCAO | {"retencao_comprovantes": [novo]}))
    assert r.status_code == 200, r.text
    assert auditoria(fluxo, "financeiro.ausencia_comprovante_enviado")


# --- 2) provas na contestação de medida ----------------------------------------------------------

ABRIR = {"motivo": "Analisar a contestação."}


def _medida(amb):
    preparar(amb)
    servico = arquivos(amb.cliente.app, amb.relogio)
    return aplicar(amb).json()["id"], servico


def pedir(amb, mid, quem="t-cliente", base="/v1/me/medidas", **extra):
    corpo = {"nome_arquivo": "a.png", "content_type": "image/png", "tamanho_bytes": 200} | extra
    return amb.cliente.post(f"{base}/{mid}/contestacao/anexos", json=corpo, headers=cab(quem))


def subir(servico, mid, anexo_id, dados):
    caminho = f"contestacao-medida/{CLIENTE.id}/{mid}/envio/{anexo_id}"
    servico.armazenamento.simular_envio("verificacao", caminho, dados)
    return caminho


def contesta_com(amb, mid, anexos, quem="t-cliente", versao="Não fui eu."):
    corpo = {"versao": versao, "anexos": anexos}
    url = f"/v1/me/medidas/{mid}/contestacao"
    return amb.cliente.post(url, json=corpo, headers=cab(quem))


def abrir(amb, mid, quem="t-mediador", corpo=None):
    url = f"/v1/admin/medidas/{mid}/contestacao/anexos/abrir"
    return amb.cliente.post(url, json=ABRIR if corpo is None else corpo, headers=cab(quem))


def test_bloqueado_envia_prova_contesta_e_o_analista_abre(amb):
    mid, servico = _medida(amb)
    amb.contexto.auth.bloqueados.add("t-cliente")
    r = pedir(amb, mid)
    assert r.status_code == 201, r.text
    anexo = r.json()["anexo_id"]
    assert contesta_com(amb, mid, [anexo]).json()["codigo"] == "anexo_nao_enviado"
    temporario = subir(servico, mid, anexo, png_com_texto())
    r = contesta_com(amb, mid, [anexo])
    assert r.status_code == 200, r.text
    (visto,) = r.json()["contestacao"]["anexos"]
    assert visto["anexo_id"] == anexo and visto["content_type"] == "image/png"
    assert "url" not in r.text and "caminho" not in r.text
    assert contesta_com(amb, mid, [anexo]).status_code == 200
    assert contesta_com(amb, mid, []).json()["codigo"] == "ja_contestada"
    assert pedir(amb, mid).json()["codigo"] == "ja_contestada"
    # trocar o arquivo temporário depois não muda a prova guardada
    assert ("verificacao", temporario) not in servico.armazenamento.arquivos
    servico.armazenamento.simular_envio("verificacao", temporario, b"trocado")
    (final,) = amb.contexto.medidas.contestacao(mid).anexos
    assert final["caminho"] != temporario
    assert b"GPS" not in servico.armazenamento.ler("verificacao", final["caminho"])
    for quem in ("t-financeiro", "t-cliente"):
        assert abrir(amb, mid, quem).status_code in (401, 403)
    assert abrir(amb, mid, corpo={"motivo": "curto"}).status_code == 422
    acoes = "dado_pessoal.medida_anexos_vistos"
    assert amb.admin.auditoria.listar(_filtro(acoes), 10, 0)[1] == 0
    r = abrir(amb, mid)
    assert r.status_code == 200, r.text
    assert final["caminho"] in r.json()[0]["url"] and r.json()[0]["expira_em_segundos"] == 300
    assert amb.admin.auditoria.listar(_filtro(acoes), 10, 0)[1] == 1


def _filtro(acao):
    from trato.api.admin.repositorios import FiltroAuditoria

    return FiltroAuditoria(acao=acao)


def test_anexo_ruim_ou_de_outra_pessoa_nao_entra(amb):
    mid, servico = _medida(amb)
    assert pedir(amb, mid, quem="t-prof").status_code == 404
    assert pedir(amb, mid, content_type="video/mp4").json()["codigo"] == "arquivo_invalido"
    assert pedir(amb, mid, tamanho_bytes=11 * 1024 * 1024).status_code == 422
    anexo = pedir(amb, mid).json()["anexo_id"]
    subir(servico, mid, anexo, b"MZ executavel disfarcado" * 10)
    assert contesta_com(amb, mid, [anexo]).json()["codigo"] == "arquivo_invalido"
    for ruim in ("../../outro.png", "x.png"):
        assert contesta_com(amb, mid, [ruim]).json()["codigo"] == "anexo_invalido"
    assert contesta_com(amb, mid, [anexo, anexo]).json()["codigo"] == "anexo_invalido"
    assert amb.contexto.medidas.contestacao(mid) is None
    amb.relogio.avancar(days=31)
    assert pedir(amb, mid).json()["codigo"] == "prazo_encerrado"


def test_atendimento_registra_com_prova_e_seis_toques_juntos(amb):
    mid, servico = _medida(amb)
    r = pedir(amb, mid, "t-mediador", "/v1/admin/medidas")
    assert r.status_code == 201, r.text
    anexo = r.json()["anexo_id"]
    subir(servico, mid, anexo, png_com_texto())
    url = f"/v1/admin/medidas/{mid}/contestacao"
    corpo = {"versao": "Ligou e contou.", "anexos": [anexo]}
    codigos = []
    threads = [
        threading.Thread(
            target=lambda: codigos.append(
                amb.cliente.post(url, json=corpo, headers=cab("t-mediador")).status_code
            )
        )
        for _ in range(6)
    ]
    for t in threads:
        t.start()
    for t in threads:
        t.join()
    assert codigos == [200] * 6
    assert len(amb.contexto.medidas.contestacao(mid).anexos) == 1
    assert minhas(amb).json()[0]["contestacao"]["anexos"][0]["anexo_id"] == anexo


# --- 3) nomes, marca e chamado_id ----------------------------------------------------------------


class Nomes:
    def nomes(self, ids):
        return {i: f"Nome {i}" for i in ids}


def test_nomes_de_analista_so_para_a_equipe(amb):
    preparar(amb)
    amb.admin.usuarios = Nomes()
    mid = aplicar(amb).json()["id"]
    contesto(amb, mid)
    assert decide(amb, mid, resultado="mantida").status_code == 200
    visto = amb.cliente.get(f"/v1/admin/medidas/{mid}", headers=cab("t-mediador")).json()
    assert visto["aplicada_por_nome"] == "Nome eq-med"
    assert visto["contestacao_analista_nome"] == "Nome eq-lider"
    lista = amb.cliente.get("/v1/admin/medidas", headers=cab("t-mediador")).json()
    assert lista["itens"][0]["contestacao_analista_nome"] == "Nome eq-lider"
    do_usuario = minhas(amb).text
    assert "eq-med" not in do_usuario and "Nome " not in do_usuario


def test_chamado_traz_responsavel_marca_e_id_no_aviso(amb):
    push, _ = ouvir(amb.cliente.app, amb.contexto)
    amb.admin.usuarios = Nomes()
    amb.contexto.extras["notificador"].repo.registrar_dispositivo(
        CLIENTE.id, "token-aparelho-1", "android", AGORA
    )
    corpo = {"categoria": "duvida", "assunto": "Ajuda", "texto": "Oi, preciso de ajuda."}
    novo = amb.cliente.post("/v1/sac/chamados", json=corpo, headers=cab("t-cliente")).json()
    assert novo["contestacao_retencao"] is False
    base = f"/v1/admin/chamados/{novo['id']}"
    amb.cliente.post(f"{base}/assumir", json={}, headers=cab("t-n1"))
    resposta = {"texto": "Vamos resolver."}
    amb.cliente.post(f"{base}/mensagens", json=resposta, headers=cab("t-n1"))
    visto = amb.cliente.get(base, headers=cab("t-n1")).json()
    assert visto["responsavel_nome"] == "Nome eq-n1" and visto["contestacao_retencao"] is False
    do_usuario = amb.cliente.get(f"/v1/sac/chamados/{novo['id']}", headers=cab("t-cliente"))
    assert "responsavel" not in do_usuario.text and "Nome " not in do_usuario.text
    avisos = amb.cliente.get("/v1/notificacoes", headers=cab("t-cliente")).json()
    itens = avisos["itens"] if isinstance(avisos, dict) else avisos
    do_sac = [a for a in itens if a["tipo"].startswith("suporte.chamado")]
    assert len(do_sac) == 2
    assert {a["dados"]["chamado_id"] for a in do_sac} == {novo["id"]}
    assert all(m.dados["chamado_id"] == novo["id"] for m in push.enviados)


def test_contestacao_de_retencao_e_marcada(fluxo):  # noqa: F811
    pid, _, _ = com_retencao(fluxo)
    contestar(fluxo, pid)
    caso = fluxo.ctx.chamados.revisao(pid, AGORA)
    assert caso is not None
    from trato.api.rotas_sac import eh_contestacao_de_retencao
    from trato.persistencia.chamados import ASSUNTO
    from trato.persistencia.sac import Chamado

    marcado = Chamado("contestacao", ASSUNTO, "app", AGORA, AGORA)
    comum = Chamado("contestacao", "Outra contestação", "app", AGORA, AGORA)
    assert eh_contestacao_de_retencao(marcado) and not eh_contestacao_de_retencao(comum)
