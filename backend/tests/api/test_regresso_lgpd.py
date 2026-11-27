"""TERMOS-BE-REG: regresso pelo painel (17.4) e remoção de arquivos pela LGPD. Memória e porta de
armazenamento falsa (o efeito no livro fica nos testes do Postgres)."""

# ruff: noqa: F811 - o parâmetro com nome da fixture importada é do pytest

from __future__ import annotations

import uuid
from datetime import UTC, datetime
from types import SimpleNamespace

import httpx
import pytest
from conftest import cab
from test_fixseg import com_equipe
from test_fluxo_pagamento_e2e import fluxo  # noqa: F401 - fixture
from test_medidas import aplicar, contesto, decide, preparar
from test_provas_medida_comprovante import arquivos

from trato.lgpd.config import obter_config_lgpd
from trato.lgpd.memoria import FonteDadosEmMemoria, criar_repositorios_memoria
from trato.lgpd.repositorios import PedidoExclusao
from trato.lgpd.servico import ServicoLgpd
from trato.persistencia.compensacoes import CompensacoesIndisponiveis, Proposta, Proposto
from trato.uploads import ArmazenamentoFake
from trato.uploads.armazenamento import ArmazenamentoSupabase

URL = "/v1/admin/compensacoes/regressos"
MOTIVO = "Garantia acionada depois do repasse."


class Regressos(CompensacoesIndisponiveis):
    def __init__(self, resultado: str = "ok") -> None:
        self.resultado = resultado
        self.chamadas: list[tuple] = []

    def regresso_disponivel(self) -> bool:
        return True

    def propor_regresso(self, *args):
        self.chamadas.append(("propor", *args))
        return Proposto(self.resultado, "p1")

    def recusar_regresso(self, *args):
        self.chamadas.append(("recusar", *args))
        return self.resultado

    def proposta(self, proposta_id):
        agora = datetime.now(UTC)
        return Proposta(
            "p1", "c1", "ped-1", "pro-1", "ref", 100, MOTIVO, "proposta", "eq-med", agora
        )


def corpo() -> dict:
    return {
        "pedido_id": "ped-1",
        "referencia": str(uuid.uuid4()),
        "valor_centavos": 100,
        "motivo": MOTIVO,
    }


@pytest.mark.parametrize(
    "quem,propoe,aprova",
    [("t-mediador", True, False), ("t-seguranca", True, False), ("t-lider", True, True),
     ("t-admin", True, True), ("t-financeiro", False, False), ("t-n1", False, False),
     ("t-prof", False, False)],
)  # fmt: skip
def test_quem_propoe_e_quem_aprova(amb, quem, propoe, aprova):
    com_equipe(amb)
    amb.contexto.compensacoes = Regressos()
    r = amb.cliente.post(URL, json=corpo(), headers=cab(quem))
    assert (r.status_code == 201) is propoe, r.text
    recusa = amb.cliente.post(f"{URL}/p1/recusa", json={"motivo": MOTIVO}, headers=cab(quem))
    assert (recusa.status_code == 200) is aprova, recusa.text
    aprovacao = amb.cliente.post(f"{URL}/p1/aprovacao", headers=cab(quem))
    assert (aprovacao.status_code != 403) is aprova, aprovacao.text


@pytest.mark.parametrize(
    "resultado,status",
    [("ja_proposta", 200), ("conflito", 409), ("ja_registrada", 409), ("analista_invalido", 403),
     ("contrato_nao_encontrado", 404), ("indisponivel", 503)],
)  # fmt: skip
def test_respostas_da_proposta_levam_o_operador(amb, resultado, status):
    com_equipe(amb)
    espia = amb.contexto.compensacoes = Regressos(resultado)
    enviado = corpo()
    r = amb.cliente.post(URL, json=enviado, headers=cab("t-mediador"))
    assert r.status_code == status, r.text
    assert espia.chamadas == [("propor", "ped-1", enviado["referencia"], 100, MOTIVO, "eq-med")]


def test_sem_as_funcoes_503_e_sem_registro_direto(amb):
    com_equipe(amb)
    for metodo, url in (("GET", URL), ("POST", f"{URL}/p1/aprovacao")):
        r = amb.cliente.request(metodo, url, headers=cab("t-admin"))
        assert r.status_code == 503 and r.json()["codigo"] == "indisponivel", r.text
    assert amb.cliente.post(URL, json=corpo(), headers=cab("t-admin")).status_code == 503
    caminhos = amb.cliente.app.openapi()["paths"]
    assert sorted(p for p in caminhos if "regresso" in p) == [
        URL,
        URL + "/{proposta_id}/aprovacao",
        URL + "/{proposta_id}/recusa",
    ]


# --- contestação de medida -------------------------------------------------------------------------


class Instavel(ArmazenamentoFake):
    fora = False

    def remover(self, bucket, caminho):
        if self.fora:
            raise RuntimeError("fora do ar")
        super().remover(bucket, caminho)


def _contestada(amb) -> tuple[str, Instavel]:
    preparar(amb)
    com_equipe(amb)
    servico = arquivos(amb.cliente.app, amb.relogio)
    armazem = servico.armazenamento = Instavel()
    mid = aplicar(amb).json()["id"]
    assert contesto(amb, mid).status_code == 200
    item = amb.contexto.medidas.contestacao(mid)
    caminho = f"contestacao-medida/{mid}/prova.png"
    armazem.gravar("verificacao", caminho, b"x", "image/png")
    anexo = {
        "anexo_id": "a" * 32 + ".png",
        "bucket": "verificacao",
        "caminho": caminho,
        "content_type": "image/png",
        "tamanho_bytes": 1,
        "sha256": "0" * 64,
    }
    object.__setattr__(item, "anexos", (anexo,))
    return mid, armazem


def _apagar(amb, cid, quem="t-admin"):
    url = f"/v1/admin/medidas/contestacoes/{cid}/anonimizacao"
    pedido = {"motivo": "Pedido do titular atendido."}
    return amb.cliente.post(url, json=pedido, headers=cab(quem))


def test_apaga_so_decidida_e_repete_a_remocao_quando_falha(amb):
    mid, armazem = _contestada(amb)
    cid = amb.contexto.medidas.contestacao(mid).id
    assert _apagar(amb, cid, "t-mediador").status_code == 403
    r = _apagar(amb, cid)
    assert r.status_code == 409 and r.json()["codigo"] == "nao_decidida", r.text
    assert armazem.arquivos
    assert decide(amb, mid).status_code == 200
    armazem.fora = True
    r = _apagar(amb, cid)
    assert r.status_code == 200, r.text
    assert r.json() == {"resultado": "ok", "arquivos": 1, "removidos": 0, "pendentes": 1}
    assert amb.contexto.medidas.contestacao(mid).versao == "[anonimizado]"
    armazem.fora = False
    r = _apagar(amb, cid)
    assert r.json() == {
        "resultado": "ja_anonimizada",
        "arquivos": 1,
        "removidos": 1,
        "pendentes": 0,
    }
    assert armazem.arquivos == {}
    assert _apagar(amb, "nao-existe").status_code == 404


# --- exclusão de conta -----------------------------------------------------------------------------


def _servico(armazem) -> tuple[ServicoLgpd, FonteDadosEmMemoria]:
    fonte = FonteDadosEmMemoria()
    fonte.documentos["u1"] = ["u1/frente.jpg", "u1/selfie.jpg"]
    repos = criar_repositorios_memoria(fonte)
    agora = datetime.now(UTC)
    repos.exclusoes.salvar(PedidoExclusao("e1", "u1", "agendada", agora, executar_apos=agora))
    seg = SimpleNamespace(auditar=lambda *a, **k: None)
    return ServicoLgpd(obter_config_lgpd(), repos, seg, armazem), fonte


def _semear(armazem) -> None:
    for caminho in (
        "u1/frente.jpg",
        "u1/selfie.jpg",
        "contestacao-medida/u1/m1/envio/a.png",
        "contestacao-medida/m1/prova-guardada.png",
        "contestacao-medida/u2/m9/envio/b.png",
    ):
        armazem.gravar("verificacao", caminho, b"x", "image/png")


def test_exclusao_apaga_documentos_e_temporarios_e_guarda_a_prova():
    armazem = ArmazenamentoFake()
    _semear(armazem)
    servico, _ = _servico(armazem)
    agora = datetime.now(UTC)
    assert servico.processar_vencidas(agora) == {"anonimizadas": 1, "adiadas": 0}
    assert sorted(c for _, c in armazem.arquivos) == [
        "contestacao-medida/m1/prova-guardada.png",
        "contestacao-medida/u2/m9/envio/b.png",
    ]


@pytest.mark.parametrize("porta", ["fora", "ausente"])
def test_exclusao_com_armazenamento_falhando_fica_pendente_e_repete(porta):
    armazem = Instavel()
    _semear(armazem)
    armazem.fora = True
    servico, fonte = _servico(armazem if porta == "fora" else None)
    agora = datetime.now(UTC)
    saida = servico.processar_vencidas(agora)
    assert saida == {"anonimizadas": 1, "adiadas": 0, "arquivos_pendentes": 1}
    assert len(armazem.arquivos) == 5
    armazem.fora = False
    outro = ServicoLgpd(servico._cfg, servico._r, servico._seg, armazem)
    assert outro.processar_vencidas(agora) == {"anonimizadas": 0, "adiadas": 0}
    assert len(armazem.arquivos) == 2 and fonte.limpezas_pendentes() == []


def test_adaptador_do_storage_lista_pastas_e_ignora_o_que_ja_sumiu():
    def responder(pedido: httpx.Request) -> httpx.Response:
        if pedido.method == "DELETE":
            if pedido.url.path.endswith("sumiu"):
                return httpx.Response(400, json={"error": "not_found"})
            return httpx.Response(500 if pedido.url.path.endswith("erro") else 200, json={})
        pasta = pedido.read().decode()
        if '"pasta/sub"' in pasta.replace(" ", ""):
            return httpx.Response(200, json=[{"name": "b.png", "id": "2"}])
        return httpx.Response(200, json=[{"name": "a.png", "id": "1"}, {"name": "sub", "id": None}])

    cliente = httpx.Client(transport=httpx.MockTransport(responder))
    porta = ArmazenamentoSupabase("https://storage.invalid", "chave-falsa", cliente)
    assert porta.listar("verificacao", "pasta/") == ["pasta/a.png", "pasta/sub/b.png"]
    porta.remover("verificacao", "sumiu")
    with pytest.raises(httpx.HTTPStatusError):
        porta.remover("verificacao", "erro")
