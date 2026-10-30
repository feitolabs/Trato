"""M9 (texto livre), M10 (aceite com IP e aparelho), M12 (docs/CORS/limite) e A8 (documento)."""

from __future__ import annotations

from conftest import AGORA, cab
from fastapi import FastAPI
from fastapi.testclient import TestClient

from trato.api import criar_app
from trato.api.fabrica import criar_app_da_config
from trato.config import Config
from trato.pedidos.estados import Estado
from trato.seguranca.config import ConfigSeguranca, parametros_docs
from trato.seguranca.contadores import Contadores
from trato.seguranca.limite_taxa import LimitadorTaxa

CFG = ConfigSeguranca(_env_file=None)
AVALIAR = "/v1/pedidos/ped-1/avaliacao"


def _avaliar(amb, **corpo):
    amb.semear_pedido(Estado.CONCLUIDO, concluido_em=AGORA)
    return amb.cliente.post(AVALIAR, json={"nota_geral": 5, **corpo}, headers=cab("t-cliente"))


# --- M9 --------------------------------------------------------------------------------------


def test_comentario_da_avaliacao_esconde_telefone_e_email(amb):
    r = _avaliar(amb, comentario="Ótimo! Me chama no zap 31 99999-8888 ou joao@exemplo.com")
    assert r.status_code == 201, r.text
    texto = r.json()["comentario"]
    assert "99999" not in texto and "joao@" not in texto
    assert "Ótimo" in texto


def test_comentario_acima_do_limite_da_configuracao_e_recusado(amb):
    assert _avaliar(amb, comentario="a" * CFG.comentario_max_chars).status_code == 201


def test_comentario_longo_demais_e_422(amb):
    r = _avaliar(amb, comentario="a" * (CFG.comentario_max_chars + 1))
    assert r.status_code == 422


def test_etiquetas_tem_limite_de_quantidade_e_de_tamanho(amb):
    assert _avaliar(amb, etiquetas=["x"] * (CFG.etiquetas_max + 1)).status_code == 422
    assert _avaliar(amb, etiquetas=["a" * (CFG.etiqueta_max_chars + 1)]).status_code == 422


def test_etiqueta_com_telefone_e_mascarada(amb):
    r = _avaliar(amb, etiquetas=["pontual", "liga 31 98888-7777"])
    assert r.status_code == 201
    assert not any("98888" in e for e in r.json()["etiquetas"])


def test_titulo_e_descricao_do_pedido_sao_limitados_e_mascarados(amb):
    gravado = {}
    original = amb.contexto.pedidos.salvar

    def espiar(pedido, evento=None, dados=None):
        gravado["dados"] = dados
        return original(pedido, evento)

    amb.contexto.pedidos.salvar = espiar
    corpo = {
        "categoria_id": "c",
        "cidade_id": "x",
        "titulo": "Pintar sala",
        "descricao": "Me ligue no zap 31 97777-6666 para combinar",
    }
    r = amb.cliente.post("/v1/pedidos", json=corpo, headers=cab("t-cliente"))
    assert r.status_code == 201, r.text
    assert "97777" not in gravado["dados"].descricao
    assert gravado["dados"].titulo == "Pintar sala"

    corpo["titulo"] = "t" * (CFG.titulo_max_chars + 1)
    assert amb.cliente.post("/v1/pedidos", json=corpo, headers=cab("t-cliente")).status_code == 422


# --- M10 -------------------------------------------------------------------------------------


def test_aceite_grava_ip_e_dispositivo_do_pedido(amb):
    r = amb.cliente.post("/v1/pedidos", headers=cab("t-cliente"))
    pid = r.json()["id"]
    amb.contexto.orcamentos.adicionar(_orcamento(pid))
    r = amb.cliente.post(
        f"/v1/pedidos/{pid}/acoes/aceitar_orcamento",
        json={"prova": {"orcamento_id": "orc-m10"}},
        headers={**cab("t-cliente"), "X-Dispositivo-Id": "aparelho-123"},
    )
    assert r.status_code == 200, r.text
    contrato = amb.contexto.contratos.obter_do_pedido(pid)
    assert contrato.aceite_ip == "testclient"  # IP de quem chamou (TestClient)
    assert contrato.aceite_dispositivo == "aparelho-123"


def test_ip_so_vem_do_x_forwarded_for_se_a_configuracao_confia_no_proxy():
    from starlette.requests import Request

    from trato.seguranca.cliente import ip_do_cliente

    escopo = {
        "type": "http",
        "headers": [(b"x-forwarded-for", b"6.6.6.6, 10.0.0.9")],
        "client": ("1.1.1.1", 5000),
    }
    assert ip_do_cliente(Request(escopo), CFG) == "1.1.1.1"  # padrão: não confia no cabeçalho
    confia = ConfigSeguranca(_env_file=None, confiar_x_forwarded_for=True)
    assert ip_do_cliente(Request(escopo), confia) == "10.0.0.9"  # o que o PROXY acrescentou


def _orcamento(pedido_id):
    from conftest import PROFISSIONAL

    from trato.api.repositorios import Orcamento

    return Orcamento("orc-m10", pedido_id, PROFISSIONAL.id, 50_000, "pintura")


# --- M12 -------------------------------------------------------------------------------------


def test_docs_e_openapi_existem_so_em_desenvolvimento():
    for ambiente, existe in (
        ("desenvolvimento", True),
        ("teste", True),
        ("producao", False),
        ("staging", False),
        ("", False),
    ):
        app = FastAPI(**parametros_docs(ambiente, CFG))
        c = TestClient(app)
        assert (c.get("/openapi.json").status_code == 200) is existe, ambiente
        assert (c.get("/docs").status_code == 200) is existe, ambiente
        assert (c.get("/redoc").status_code == 200) is existe, ambiente


def test_app_da_fabrica_em_producao_nao_publica_docs():
    producao = Config(_env_file=None, trato_ambiente="producao")
    c = TestClient(criar_app_da_config(producao))
    assert c.get("/docs").status_code == 404
    assert c.get("/openapi.json").status_code == 404
    dev = TestClient(criar_app_da_config(Config(_env_file=None, trato_ambiente="desenvolvimento")))
    assert dev.get("/openapi.json").status_code == 200


def test_ambientes_com_docs_vem_da_configuracao():
    cfg = ConfigSeguranca(_env_file=None, ambientes_com_docs=["homolog"])
    assert parametros_docs("homolog", cfg) == {}
    assert parametros_docs("desenvolvimento", cfg)["docs_url"] is None


def test_criar_app_usa_o_ambiente_da_config(monkeypatch):
    monkeypatch.setenv("TRATO_AMBIENTE", "producao")
    from trato.config import obter_config

    obter_config.cache_clear()
    try:
        assert TestClient(criar_app()).get("/openapi.json").status_code == 404
    finally:
        monkeypatch.undo()
        obter_config.cache_clear()


def test_limites_padrao_cobrem_as_rotas_sensiveis():
    nomes = {r.nome for r in CFG.limites}
    assert {"verificacao_envio", "documentos_url", "admin_escrita", "mensagens"} <= nomes
    limitador = LimitadorTaxa(CFG.limites, Contadores())
    regra = next(r for r in CFG.limites if r.nome == "documentos_url")
    url = "/v1/admin/verificacoes/v1/documentos/d1/url"
    decisoes = [
        limitador.checar("POST", url, "ip-hash", "usuario-1") for _ in range(regra.maximo + 1)
    ]
    assert all(d.permitido for d in decisoes[:-1])
    assert not decisoes[-1].permitido and decisoes[-1].retry_apos_s > 0


# --- A8 --------------------------------------------------------------------------------------


def test_url_do_documento_dura_o_que_a_configuracao_diz(adm):  # noqa: F811
    assert adm.admin.segundos_url == CFG.url_documento_segundos == 60


def test_so_o_cadastro_recebe_url_com_motivo_e_fica_registrado(adm):  # noqa: F811
    url = "/v1/admin/verificacoes/ver-1/documentos/doc-1/url"
    corpo = {"motivo": "Conferir o documento do cadastro"}
    for token in ("t-moderador", "t-financeiro", "t-atendente_n1", "t-administrador", "t-mediador"):
        assert adm.cliente.post(url, json=corpo, headers=cab(token)).status_code == 403, token
    assert adm.assinador.chamadas == []
    sem_motivo = adm.cliente.post(url, json={}, headers=cab("t-cadastro"))
    assert sem_motivo.status_code == 422 and adm.assinador.chamadas == []

    ok = adm.cliente.post(url, json=corpo, headers=cab("t-cadastro"))
    assert ok.status_code == 200 and ok.json()["expira_em_segundos"] == 60
    assert adm.assinador.chamadas == [("bucket-privado/ver-1/frente.jpg", 60)]
    assert "bucket-privado" not in ok.text  # o caminho do storage nunca sai

    achados, _ = adm.admin.auditoria.listar(_filtro(), 20, 0)
    vistos = [e for e in achados if e.acao == "dado_pessoal.documento_revelado"]
    assert len(vistos) == 1
    assert vistos[0].ator_id == "eq-cadastro" and vistos[0].motivo == corpo["motivo"]
    assert vistos[0].ocorrida_em is not None  # quando


def _filtro():
    from trato.api.admin.repositorios import FiltroAuditoria

    return FiltroAuditoria()


from admin_ambiente import adm  # noqa: E402, F401
