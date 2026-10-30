"""Cadastro do profissional, verificação, upload seguro e prova de check-in/out (memória + fake)."""

from __future__ import annotations

import hashlib
import struct
from datetime import timedelta

import pytest
from conftest import AGORA, cab

from trato.api.auth import PapelUsuario
from trato.api.repositorios_app import Avaliacao, PerfilDetalhe
from trato.api.rotas_profissional_cadastro import modulo_em_memoria
from trato.pedidos.estados import Estado
from trato.profissional.config import ConfigProfissional
from trato.profissional.repositorio import PerfilProfissional
from trato.seguranca.config import obter_config_seguranca
from trato.uploads import ArmazenamentoFake
from trato.uploads.config import ConfigUploads
from trato.uploads.imagem import limpar_jpeg, limpar_png
from trato.uploads.servico import ServicoUploads, UploadsEmMemoria, distancia_metros


def _seg(marca: int, corpo: bytes) -> bytes:
    return bytes([0xFF, marca]) + struct.pack(">H", len(corpo) + 2) + corpo


EXIF_GPS = b"Exif\x00\x00GPSLatitude-19.9;GPSLongitude-43.9"
JPEG_COM_EXIF = (
    b"\xff\xd8"
    + _seg(0xE0, b"JFIF\x00\x01\x01\x00\x00\x01\x00\x01\x00\x00")
    + _seg(0xE1, EXIF_GPS)
    + _seg(0xC0, b"\x08\x00\x10\x00\x10\x01\x01\x11\x00")
    + b"\xff\xda\x00\x08\x01\x01\x00\x00\x3f\x00DADOS-DA-IMAGEM"
    + b"\xff\xd9"
)
EXECUTAVEL = b"MZ\x90\x00\x03\x00\x00\x00" + b"\x00" * 200


def png_com_texto() -> bytes:
    def bloco(tipo: bytes, dados: bytes) -> bytes:
        return struct.pack(">I", len(dados)) + tipo + dados + b"\x00\x00\x00\x00"

    return (
        b"\x89PNG\r\n\x1a\n"
        + bloco(b"IHDR", b"\x00" * 13)
        + bloco(b"eXIf", b"GPSsegredo")
        + bloco(b"tEXt", b"Comment\x00localizacao")
        + bloco(b"IDAT", b"\x00\x01")
        + bloco(b"IEND", b"")
    )


class Ambiente2:
    def __init__(self, amb):
        self.amb = amb
        self.armazenamento = ArmazenamentoFake()
        self.repo = UploadsEmMemoria()
        self.alvo: tuple[float, float] | None = None
        self.servico = ServicoUploads(
            self.armazenamento,
            self.repo,
            obter_config_seguranca(),
            ConfigUploads(),
            amb.relogio,
            lambda _pedido: self.alvo,
        )
        amb.cliente.app.state.servico_uploads = self.servico
        self.modulo = modulo_em_memoria(amb.cliente.app)
        self.modulo.catalogo.categorias.update(
            {"cat-pintura": "pintura", "cat-eletrica": "eletrica"}
        )
        self.modulo.catalogo.cidades.update({"cid-bh"})

    def post(self, url, quem, corpo=None):
        return self.amb.cliente.post(url, json=corpo, headers=cab(quem))

    def get(self, url, quem="t-prof"):
        return self.amb.cliente.get(url, headers=cab(quem))

    def enviar(self, quem, destino, dados, *, nome="a.jpg", tipo="image/jpeg", **extra):
        """Pede a URL, 'envia' direto ao armazenamento fake e conclui. Devolve (pedir, concluir)."""
        corpo = {
            "destino": destino,
            "nome_arquivo": nome,
            "content_type": tipo,
            "tamanho_bytes": len(dados),
            **extra,
        }
        pedir = self.post("/v1/uploads", quem, corpo)
        if pedir.status_code != 201:
            return pedir, None
        sol = self.repo.solicitacao(pedir.json()["upload_id"])
        self.armazenamento.simular_envio(sol.bucket, sol.caminho, dados)
        return pedir, self.post(f"/v1/uploads/{sol.id}/concluir", quem)


@pytest.fixture
def e2(amb) -> Ambiente2:
    return Ambiente2(amb)


# --- limpeza de metadados -----------------------------------------------------------------


def test_limpar_jpeg_tira_exif_e_gps_e_mantem_a_imagem():
    limpo = limpar_jpeg(JPEG_COM_EXIF)
    assert b"GPS" not in limpo and b"Exif" not in limpo
    assert b"JFIF" in limpo and b"DADOS-DA-IMAGEM" in limpo and limpo.endswith(b"\xff\xd9")


def test_limpar_png_tira_blocos_de_metadado():
    limpo = limpar_png(png_com_texto())
    assert b"eXIf" not in limpo and b"tEXt" not in limpo and b"IDAT" in limpo


def test_distancia_no_servidor():
    assert distancia_metros(-19.9, -43.9, -19.9, -43.9) == 0
    assert 1000 < distancia_metros(-19.9, -43.9, -19.9, -43.89) < 1100


# --- upload: fluxo, autorização, limites, arquivo falso -----------------------------------


def test_upload_de_foto_de_checkin_revalida_limpa_e_registra(e2, amb):
    amb.semear_pedido(Estado.AGENDADO, codigo_inicio="1234")
    pedir, concluir = e2.enviar("t-prof", "checkin", JPEG_COM_EXIF, pedido_id="ped-1")
    assert (
        pedir.json()["expira_em_segundos"] == 300 and "storage.invalid" in pedir.json()["url_envio"]
    )
    corpo = concluir.json()
    assert concluir.status_code == 200 and corpo["status"] == "concluida"
    midia = e2.repo.midia(corpo["midia_id"])
    assert midia.pedido_id == "ped-1" and midia.enviada_por == "pro-1"
    assert midia.bucket == "pedido-midias" and midia.storage_path.startswith("ped-1/")
    guardado = e2.armazenamento.ler(midia.bucket, midia.storage_path)
    assert b"GPS" not in guardado  # EXIF/GPS saiu do arquivo guardado
    assert midia.sha256 == corpo["sha256"] == hashlib.sha256(guardado).hexdigest()
    # idempotente: concluir de novo devolve a mesma mídia
    assert e2.post(f"/v1/uploads/{pedir.json()['upload_id']}/concluir", "t-prof").json() == corpo


def test_usuario_a_nao_anexa_midia_no_pedido_de_b(e2, amb):
    amb.semear_pedido(Estado.AGENDADO)
    corpo = {"destino": "disputa", "nome_arquivo": "a.jpg", "content_type": "image/jpeg",
             "tamanho_bytes": 1000, "pedido_id": "ped-1"}  # fmt: skip
    for quem in ("t-outro-cliente", "t-outro-prof"):
        assert e2.post("/v1/uploads", quem, corpo).status_code == 404
    assert e2.post("/v1/uploads", "t-equipe", corpo).status_code == 403
    assert amb.cliente.post("/v1/uploads", json=corpo).status_code == 401
    assert e2.post("/v1/uploads", "t-cliente", corpo).status_code == 201  # o dono pode
    assert e2.armazenamento.urls_emitidas and len(e2.armazenamento.urls_emitidas) == 1


def test_papel_no_pedido_decide_a_finalidade(e2, amb):
    amb.semear_pedido(Estado.AGENDADO)
    base = {"nome_arquivo": "a.jpg", "content_type": "image/jpeg", "tamanho_bytes": 1000,
            "pedido_id": "ped-1"}  # fmt: skip
    assert e2.post("/v1/uploads", "t-cliente", {**base, "destino": "checkin"}).status_code == 403
    assert e2.post("/v1/uploads", "t-prof", {**base, "destino": "pedido"}).status_code == 403
    assert e2.post("/v1/uploads", "t-prof", {**base, "destino": "xyz"}).status_code == 422
    sem_pedido = {**base, "destino": "checkin"}
    del sem_pedido["pedido_id"]
    assert e2.post("/v1/uploads", "t-prof", sem_pedido).status_code == 422


def test_outro_usuario_nao_conclui_o_envio_alheio(e2, amb):
    amb.semear_pedido(Estado.AGENDADO)
    pedir, _ = e2.enviar("t-prof", "depois", JPEG_COM_EXIF, pedido_id="ped-1")
    uid = pedir.json()["upload_id"]
    assert e2.post(f"/v1/uploads/{uid}/concluir", "t-cliente").status_code == 404
    assert e2.post(f"/v1/uploads/{uid}/concluir", "t-outro-prof").status_code == 404


@pytest.mark.parametrize(
    ("corpo", "trecho"),
    [
        ({"content_type": "application/x-msdownload", "nome_arquivo": "a.exe"}, "Tipo"),
        (
            {"content_type": "application/pdf", "nome_arquivo": "a.pdf"},
            "Tipo",
        ),  # foto não aceita pdf
        ({"nome_arquivo": "a.png"}, "extensão"),  # png declarado como jpeg
        ({"nome_arquivo": "../../etc/passwd.jpg"}, "Nome"),
        ({"tamanho_bytes": 6 * 1024 * 1024}, "grande demais"),  # limite de foto: 5 MB
    ],
)
def test_limites_de_tipo_tamanho_e_nome(e2, amb, corpo, trecho):
    amb.semear_pedido(Estado.AGENDADO)
    base = {"destino": "checkin", "nome_arquivo": "a.jpg", "content_type": "image/jpeg",
            "tamanho_bytes": 1000, "pedido_id": "ped-1"}  # fmt: skip
    r = e2.post("/v1/uploads", "t-prof", {**base, **corpo})
    assert r.status_code == 422 and trecho in r.json()["detail"]
    assert e2.armazenamento.urls_emitidas == []


def test_arquivo_falso_com_extensao_jpg_e_conteudo_executavel(e2, amb):
    amb.semear_pedido(Estado.AGENDADO)
    pedir, concluir = e2.enviar("t-prof", "checkin", EXECUTAVEL, pedido_id="ped-1")
    assert concluir.status_code == 422 and "conteúdo" in concluir.json()["detail"]
    sol = e2.repo.solicitacao(pedir.json()["upload_id"])
    assert sol.status == "pendente" and e2.repo.midias == {}
    assert (sol.bucket, sol.caminho) not in e2.armazenamento.arquivos  # apagado


def test_arquivo_maior_do_que_o_informado_e_recusado(e2, amb):
    amb.semear_pedido(Estado.AGENDADO)
    pedir = e2.post("/v1/uploads", "t-prof", {"destino": "checkin", "nome_arquivo": "a.jpg",
        "content_type": "image/jpeg", "tamanho_bytes": 10, "pedido_id": "ped-1"})  # fmt: skip
    sol = e2.repo.solicitacao(pedir.json()["upload_id"])
    e2.armazenamento.simular_envio(sol.bucket, sol.caminho, JPEG_COM_EXIF)
    assert e2.post(f"/v1/uploads/{sol.id}/concluir", "t-prof").status_code == 422


def test_concluir_sem_enviar_e_depois_do_prazo(e2, amb):
    amb.semear_pedido(Estado.AGENDADO)
    pedir = e2.post("/v1/uploads", "t-prof", {"destino": "checkin", "nome_arquivo": "a.jpg",
        "content_type": "image/jpeg", "tamanho_bytes": 100, "pedido_id": "ped-1"})  # fmt: skip
    uid = pedir.json()["upload_id"]
    assert e2.post(f"/v1/uploads/{uid}/concluir", "t-prof").status_code == 409
    amb.relogio.avancar(hours=2)
    assert e2.post(f"/v1/uploads/{uid}/concluir", "t-prof").status_code == 410


def test_sem_armazenamento_ligado_as_rotas_dizem_503(amb):
    amb.cliente.app.state.servico_uploads = None
    r = amb.cliente.post("/v1/uploads", headers=cab("t-prof"), json={"destino": "avatar",
        "nome_arquivo": "a.jpg", "content_type": "image/jpeg", "tamanho_bytes": 10})  # fmt: skip
    assert r.status_code == 503


def test_avatar_vai_para_o_bucket_com_o_id_do_dono(e2):
    _, concluir = e2.enviar("t-cliente", "avatar", JPEG_COM_EXIF)
    assert concluir.status_code == 200 and concluir.json()["midia_id"] is None
    sol = next(iter(e2.repo.solicitacoes.values()))
    assert sol.bucket == "avatar" and sol.caminho.startswith("cli-1/")


# --- verificação ---------------------------------------------------------------------------


def enviar_docs(e2, quem, tipos=("documento_frente", "selfie")):
    docs = []
    for tipo in tipos:
        pedir, concluir = e2.enviar(quem, "verificacao", JPEG_COM_EXIF, tipo_documento=tipo)
        assert concluir.status_code == 200, concluir.text
        # documento nunca volta ao dono: nem caminho, nem link, nem id de mídia
        assert concluir.json()["midia_id"] is None
        assert "caminho" not in concluir.text and "storage" not in concluir.text.replace(
            "upload", ""
        )
        docs.append({"tipo": tipo, "upload_id": pedir.json()["upload_id"]})
    return docs


def cadastrar(e2, quem="t-prof", categorias=("cat-pintura",)):
    return e2.post("/v1/profissional/cadastro", quem, {
        "categorias": list(categorias), "regioes": [{"cidade_id": "cid-bh", "bairro": "Savassi"}],
    })  # fmt: skip


def test_verificacao_por_upload_registra_consentimento_retencao_e_status(e2, amb):
    cadastrar(e2)
    docs = enviar_docs(e2, "t-prof")
    r = e2.post("/v1/profissional/verificacao", "t-prof",
                {"consentimento_lgpd": True, "documentos": docs})  # fmt: skip
    assert r.status_code == 201, r.text
    corpo = r.json()
    assert corpo["status_app"] == "em_analise" and corpo["motivo"] is None
    assert corpo["retencao_dias"] == 365 and "Confirmar" in corpo["finalidade"]
    assert "storage_path" not in r.text and "sha256" not in r.text
    guardada = amb.contexto.verificacoes.da_pessoa("pro-1")[0]
    assert all(
        d.sha256 and d.excluir_em == AGORA + timedelta(days=365) for d in guardada.documentos
    )
    lista = e2.get("/v1/profissional/verificacao").json()
    assert lista[0]["status_app"] == "em_analise"


def test_status_aprovado_e_pendente_com_motivo(e2, amb):
    from dataclasses import replace

    cadastrar(e2)
    r = e2.post("/v1/profissional/verificacao", "t-prof",
                {"consentimento_lgpd": True, "documentos": enviar_docs(e2, "t-prof")})  # fmt: skip
    mem = amb.contexto.verificacoes
    original = mem._itens[0]
    mem._itens[0] = replace(original, status="recusada", motivo_recusa="Foto do documento ilegível")
    pendente = e2.get("/v1/profissional/verificacao").json()[0]
    assert (
        pendente["status_app"] == "pendente" and pendente["motivo"] == "Foto do documento ilegível"
    )
    mem._itens[0] = replace(original, status="aprovada")
    aprovado = e2.get("/v1/profissional/verificacao").json()[0]
    assert aprovado["status_app"] == "aprovado" and aprovado["motivo"] is None
    assert r.status_code == 201


def test_verificacao_nao_aceita_upload_alheio_nem_de_outro_tipo(e2):
    docs = enviar_docs(e2, "t-prof")
    corpo = {"consentimento_lgpd": True, "documentos": docs}
    # usuário B tenta usar os uploads do usuário A
    assert e2.post("/v1/profissional/verificacao", "t-outro-prof", corpo).status_code == 422
    # tipo declarado diferente do enviado
    trocado = [{**docs[0], "tipo": "selfie"}, docs[1]]
    assert e2.post("/v1/profissional/verificacao", "t-prof",
                   {**corpo, "documentos": trocado}).status_code == 422  # fmt: skip
    # caminho cru do app não vale quando o serviço de upload está ligado
    cru = [{"tipo": "documento_frente", "storage_path": "pro-1/x/f.jpg"},
           {"tipo": "selfie", "storage_path": "pro-1/x/s.jpg"}]  # fmt: skip
    assert e2.post("/v1/profissional/verificacao", "t-prof",
                   {**corpo, "documentos": cru}).status_code == 422  # fmt: skip


def test_nivel_de_verificacao_proporcional_ao_risco_da_categoria(e2, monkeypatch):
    cfg = ConfigProfissional(verificacao_nivel_por_categoria={"eletrica": "verificado_plus"})
    monkeypatch.setattr("trato.api.rotas_app.obter_config_profissional", lambda: cfg)
    e2.modulo.config = cfg
    assert (
        cadastrar(e2, categorias=("cat-eletrica",)).json()["nivel_verificacao_exigido"]
        == "verificado_plus"
    )
    docs = enviar_docs(e2, "t-prof")
    corpo = {"consentimento_lgpd": True, "documentos": docs}
    r = e2.post("/v1/profissional/verificacao", "t-prof", corpo)
    assert r.status_code == 422 and "verificado_plus" in r.json()["detail"]
    mais = enviar_docs(e2, "t-prof", ("documento_frente", "selfie", "antecedentes"))
    r = e2.post("/v1/profissional/verificacao", "t-prof",
                {**corpo, "nivel_solicitado": "verificado_plus", "documentos": mais})  # fmt: skip
    assert r.status_code == 201


def test_verificacao_do_nivel_plus_exige_antecedentes(e2):
    cadastrar(e2)
    docs = enviar_docs(e2, "t-prof")
    r = e2.post("/v1/profissional/verificacao", "t-prof", {"consentimento_lgpd": True,
        "nivel_solicitado": "verificado_plus", "documentos": docs})  # fmt: skip
    assert r.status_code == 422 and "antecedentes" in r.json()["detail"]


# --- check-in / check-out com foto, coordenadas e hora do servidor -------------------------


def prova_checkin(midia_id, lat=-19.9, lng=-43.9, tirada="2026-10-29T11:59:00+00:00"):
    return {"prova": {"foto": {"arquivo_id": midia_id, "tirada_em": tirada},
            "localizacao": {"latitude": lat, "longitude": lng}, "codigo_inicio": "1234"}}  # fmt: skip


def checkin(e2, quem, midia_id, **kw):
    return e2.post("/v1/pedidos/ped-1/acoes/fazer_check_in", quem, prova_checkin(midia_id, **kw))


def test_checkin_exige_midia_registrada_do_proprio_profissional(e2, amb):
    amb.semear_pedido(Estado.AGENDADO, codigo_inicio="1234")
    assert checkin(e2, "t-prof", "foto-inventada").status_code == 422
    _, concluir = e2.enviar("t-prof", "checkout", JPEG_COM_EXIF, pedido_id="ped-1")
    assert (
        checkin(e2, "t-prof", concluir.json()["midia_id"]).status_code == 422
    )  # finalidade errada


def test_checkin_usa_hora_do_servidor_e_calcula_distancia(e2, amb):
    amb.semear_pedido(Estado.AGENDADO, codigo_inicio="1234")
    e2.alvo = (-19.9, -43.9)
    _, concluir = e2.enviar("t-prof", "checkin", JPEG_COM_EXIF, pedido_id="ped-1")
    mid = concluir.json()["midia_id"]
    longe = checkin(e2, "t-prof", mid, lat=-19.95, lng=-43.9)  # ~5,5 km
    assert longe.status_code == 422 and "longe" in longe.json()["detail"]
    # data no futuro vinda do app não derruba nem vale: a hora é a do servidor
    ok = checkin(e2, "t-prof", mid, tirada="2030-01-01T00:00:00+00:00")
    assert ok.status_code == 200 and ok.json()["estado"] == "em_andamento"


def test_checkout_com_foto_registrada(e2, amb):
    amb.semear_pedido(Estado.EM_ANDAMENTO, codigo_conclusao="4321")
    corpo = lambda m: {"prova": {"foto_final": {"arquivo_id": m, "tirada_em": AGORA.isoformat()},  # noqa: E731
                                 "codigo_conclusao": "4321"}}  # fmt: skip
    url = "/v1/pedidos/ped-1/acoes/fazer_check_out"
    assert e2.post(url, "t-prof", corpo("nao-existe")).status_code == 422
    _, concluir = e2.enviar("t-prof", "checkout", JPEG_COM_EXIF, pedido_id="ped-1")
    r = e2.post(url, "t-prof", corpo(concluir.json()["midia_id"]))
    assert r.status_code == 200 and r.json()["estado"] == "em_confirmacao"


# --- cadastro e perfil ---------------------------------------------------------------------


def test_cadastro_valida_categorias_e_cidades_ativas(e2):
    base = {"categorias": ["cat-pintura"], "regioes": [{"cidade_id": "cid-bh"}]}
    assert (
        e2.post(
            "/v1/profissional/cadastro", "t-prof", {**base, "categorias": ["cat-velha"]}
        ).status_code
        == 422
    )
    assert (
        e2.post(
            "/v1/profissional/cadastro", "t-prof", {**base, "regioes": [{"cidade_id": "x"}]}
        ).status_code
        == 422
    )
    assert (
        e2.post("/v1/profissional/cadastro", "t-prof", {**base, "categorias": []}).status_code
        == 422
    )
    assert (
        e2.post("/v1/profissional/cadastro", "t-prof", {**base, "papel": "equipe"}).status_code
        == 422
    )
    bad = {**base, "disponibilidade": [{"dia_semana": 1, "inicio": "18:00", "fim": "08:00"}]}
    assert e2.post("/v1/profissional/cadastro", "t-prof", bad).status_code == 422
    assert e2.post("/v1/profissional/cadastro", "t-equipe", base).status_code == 403
    ok = e2.post("/v1/profissional/cadastro", "t-prof", {**base, "bio": "Pinto casas. Ligue 31 99999-8888",
        "disponibilidade": [{"dia_semana": 1, "inicio": "08:00", "fim": "18:00"}],
        "portfolio": [{"titulo": "Sala", "descricao": "Pintura completa"}]})  # fmt: skip
    assert ok.status_code == 201 and ok.json()["status"] == "em_analise"
    assert "99999" not in ok.json()["bio"]  # contato mascarado no texto livre
    assert e2.post("/v1/profissional/cadastro", "t-prof", base).status_code == 409


def test_perfil_proprio_e_edicao_parcial(e2):
    assert e2.get("/v1/profissional/perfil").status_code == 404
    cadastrar(e2)
    r = e2.amb.cliente.patch("/v1/profissional/perfil", headers=cab("t-prof"),
                             json={"bio": "Nova bio", "categorias": ["cat-eletrica"]})  # fmt: skip
    assert r.status_code == 200 and r.json()["bio"] == "Nova bio"
    assert (
        r.json()["categorias"] == ["cat-eletrica"] and r.json()["regioes"][0]["bairro"] == "Savassi"
    )
    nega = e2.amb.cliente.patch(
        "/v1/profissional/perfil", headers=cab("t-prof"), json={"status": "aprovado"}
    )
    assert nega.status_code == 422  # status só a equipe muda
    assert e2.get("/v1/profissional/perfil", "t-outro-prof").status_code == 404


def test_perfil_publico_so_de_aprovado_sem_dado_sensivel_e_com_avaliacoes(e2, amb):
    cadastrar(e2)
    assert e2.get("/v1/profissionais/pro-1", "t-cliente").status_code == 404  # ainda em análise
    mod = e2.modulo
    perfil = mod.repo.obter("pro-1")
    mod.repo.salvar(
        PerfilProfissional(
            **{**vars(perfil), "status": "aprovado", "nivel_verificacao": "verificado"}
        )
    )
    amb.contexto.usuarios.adicionar(PerfilDetalhe("pro-1", "João Vitor Cardoso", PapelUsuario.PROFISSIONAL,
                                                  nota_publica=4.8, servicos_concluidos=12))  # fmt: skip
    amb.contexto.avaliacoes.salvar(Avaliacao("ped-9", "cliente_para_profissional", "cli-1", "pro-1",
                                             5, "Ótimo", ("pontual",), AGORA))  # fmt: skip
    amb.contexto.avaliacoes.salvar(Avaliacao("ped-9", "profissional_para_cliente", "pro-1", "cli-1",
                                             4, "Cliente ok", (), AGORA))  # fmt: skip
    r = e2.get("/v1/profissionais/pro-1", "t-cliente")
    assert r.status_code == 200
    corpo = r.json()
    assert corpo["nome"] == "João C." and corpo["nota_publica"] == 4.8
    assert [a["nota_geral"] for a in corpo["avaliacoes"]] == [
        5
    ]  # só as recebidas como profissional
    for proibido in ("cpf", "telefone", "email", "endereco", "avaliador", "cli-1", "usuario_id"):
        assert proibido not in r.text
    assert e2.amb.cliente.get("/v1/profissionais/pro-1").status_code == 401
