"""Spec QA5-B: testes adversariais reais no backend em memoria.

Cobre:
1. Upload real (/v1/uploads e /v1/uploads/{id}/concluir): tipo invalido, content-type falso,
   arquivo vazio, tamanho acima do limite e path traversal.
2. Rate limit do perfil publico (GET /v1/publico/profissionais/{id}) com MiddlewareProtecao ativo.
3. Concorrencia real com threads simultaneas (Barrier): reserva de Tratinhos, cupom, abertura e
   resposta de disputa, exclusao LGPD e exclusividade de 48h (teto 3, idempotencia e estorno).
4. Tetos de desconto de Tratinhos no centavo exato (R$ 5 cliente, R$ 10 dia, R$ 300 mes) e
   fronteira de dia/mes em America/Sao_Paulo usando o relogio/contexto real do Trato.
"""

from __future__ import annotations

import struct
import threading
from dataclasses import replace
from datetime import UTC, date, datetime, timedelta

import pytest
from conftest import (
    AGORA,
    CLIENTE,
    OUTRO_CLIENTE,
    OUTRO_PROFISSIONAL,
    PROFISSIONAL,
    TOKENS,
    Ambiente,
    Relogio,
    cab,
)
from fastapi.testclient import TestClient
from test_fluxo_pagamento_e2e import Fluxo, fluxo  # noqa: F401

from trato.api import Contexto, criar_app
from trato.api.auth import PapelUsuario, ProvedorAuthFalso
from trato.api.memoria import (
    ConfigEmMemoria,
    ContratosEmMemoria,
    DisputasEmMemoria,
    EventosWebhookEmMemoria,
    GarantiasEmMemoria,
    LedgerEmMemoria,
    OrcamentosEmMemoria,
    PedidosEmMemoria,
)
from trato.api.moedas import (
    MOTIVO_LIMITE_DIARIO,
    MOTIVO_ORCAMENTO_ESGOTADO,
    MOTIVO_TETO_CLIENTE,
    ConfigMoedas,
    DescontoMoedasIndisponivel,
    LancamentoMoeda,
    MoedasEmMemoria,
    calcular_uso_moedas,
    conceder_bonus_avaliacao,
    dia_ref,
    disponibilidade_desconto,
    mes_ref,
    reservar_desconto,
    saldo_profissional,
)
from trato.api.repositorios import ConfigApi, DadosPedido, Orcamento
from trato.api.repositorios_app import PerfilDetalhe
from trato.api.rotas_profissional_cadastro import modulo_em_memoria
from trato.disputas import ConfigDisputa
from trato.garantias import ConfigGarantia
from trato.lgpd.memoria import FonteDadosEmMemoria, criar_repositorios_memoria
from trato.pagamentos.cupons import confirmar_uso_cupom
from trato.pedidos.estados import Estado as E
from trato.pedidos.estados import PrazosPedido
from trato.profissional.repositorio import PerfilProfissional
from trato.seguranca.config import ConfigSeguranca, RegraLimite, obter_config_seguranca
from trato.seguranca.contadores import Contadores
from trato.seguranca.instalacao import instalar_seguranca
from trato.uploads import ArmazenamentoFake
from trato.uploads.armazenamento import ArquivoNaoEncontrado
from trato.uploads.config import ConfigUploads
from trato.uploads.servico import ServicoUploads, UploadsEmMemoria


@pytest.fixture(autouse=True)
def oferta_antiga_ligada(request):
    """Estes testes cobrem a prioridade paga pelo profissional, hoje desligada por padrão."""
    if "amb" in request.fixturenames:
        config = request.getfixturevalue("amb").contexto.config
        config._config = replace(config.carregar(), exclusividade_profissional_ofertada=True)


def _seg_jpeg(marca: int, corpo: bytes) -> bytes:
    return bytes([0xFF, marca]) + struct.pack(">H", len(corpo) + 2) + corpo


EXIF_GPS = b"Exif\x00\x00GPSLatitude-19.9;GPSLongitude-43.9"
JPEG_COM_EXIF = (
    b"\xff\xd8"
    + _seg_jpeg(0xE0, b"JFIF\x00\x01\x01\x00\x00\x01\x00\x01\x00\x00")
    + _seg_jpeg(0xE1, EXIF_GPS)
    + _seg_jpeg(0xC0, b"\x08\x00\x10\x00\x10\x01\x01\x11\x00")
    + b"\xff\xda\x00\x08\x01\x01\x00\x00\x3f\x00DADOS-DA-IMAGEM"
    + b"\xff\xd9"
)
EXECUTAVEL = b"MZ\x90\x00\x03\x00\x00\x00" + b"\x00" * 120


def _ligar_uploads(amb: Ambiente) -> tuple[ArmazenamentoFake, UploadsEmMemoria, ServicoUploads]:
    armazenamento = ArmazenamentoFake()
    repo = UploadsEmMemoria()
    servico = ServicoUploads(
        armazenamento,
        repo,
        obter_config_seguranca(),
        ConfigUploads(),
        amb.relogio,
    )
    amb.cliente.app.state.servico_uploads = servico
    return armazenamento, repo, servico


def _montar_app_com_seguranca(
    *,
    relogio: Relogio | None = None,
    limites: list[RegraLimite] | None = None,
):
    rel = relogio or Relogio()
    cfg_api = ConfigApi(
        prazos_pedido=PrazosPedido(
            receber_orcamentos=timedelta(days=3),
            pagamento=timedelta(hours=24),
            tolerancia_comparecimento=timedelta(hours=1),
            confirmacao_cliente=timedelta(days=7),
        ),
        disputas=ConfigDisputa(
            prazo_resposta_horas=48,
            prazo_decisao_dias_uteis=5,
            prazo_congelar_repasse_horas=72,
        ),
        garantias=ConfigGarantia(garantia_dias_padrao=30, prazo_atendimento_dias=7),
    )
    ctx = Contexto(
        auth=ProvedorAuthFalso(TOKENS),
        pedidos=PedidosEmMemoria(),
        orcamentos=OrcamentosEmMemoria([]),
        contratos=ContratosEmMemoria(),
        ledger=LedgerEmMemoria(),
        disputas=DisputasEmMemoria(),
        garantias=GarantiasEmMemoria(),
        eventos_webhook=EventosWebhookEmMemoria(),
        config=ConfigEmMemoria(cfg_api),
        agora=rel,
    )
    app = criar_app(ctx)
    kwargs_seg = {"limites": limites} if limites is not None else {}
    cfg_seg = ConfigSeguranca(_env_file=None, **kwargs_seg)
    instalar_seguranca(app, cfg_seg, contadores=Contadores(lambda: rel.agora.timestamp()))
    fonte = FonteDadosEmMemoria()
    repos_lgpd = criar_repositorios_memoria(fonte)
    ctx.extras["lgpd"] = repos_lgpd
    app.state.seguranca.agora = rel
    return TestClient(app), app, ctx, rel, fonte, repos_lgpd


def _dar_moedas(
    repo: MoedasEmMemoria,
    usuario_id: str,
    quantidade: int,
    chave: str,
    agora: datetime = AGORA,
    carteira: str = "cliente",
) -> None:
    tipo = "bonus_avaliacao_profissional" if carteira == "profissional" else "bonus_avaliacao"
    assert repo.lancar(
        LancamentoMoeda(
            usuario_id=usuario_id,
            tipo=tipo,
            quantidade=quantidade,
            chave_idempotencia=chave,
            criada_em=agora,
            carteira=carteira,
        )
    )


# ================================================================================================
# 1. UPLOAD DE ARQUIVOS / IMAGENS (rotas reais /v1/uploads e /v1/uploads/{id}/concluir)
# ================================================================================================


def test_upload_tipo_invalido_e_extensao_incompativel_recusados(amb: Ambiente):
    _ligar_uploads(amb)

    r_exe = amb.cliente.post(
        "/v1/uploads",
        headers=cab("t-cliente"),
        json={
            "destino": "avatar",
            "nome_arquivo": "malware.exe",
            "content_type": "application/octet-stream",
            "tamanho_bytes": len(EXECUTAVEL),
        },
    )
    assert r_exe.status_code == 422, r_exe.text
    assert "permitido" in r_exe.json()["detail"].lower()

    # Extensao .exe declarando image/jpeg tambem e bloqueada na porta.
    r_ext = amb.cliente.post(
        "/v1/uploads",
        headers=cab("t-cliente"),
        json={
            "destino": "avatar",
            "nome_arquivo": "malware.exe",
            "content_type": "image/jpeg",
            "tamanho_bytes": len(EXECUTAVEL),
        },
    )
    assert r_ext.status_code == 422, r_ext.text
    assert "extensão" in r_ext.json()["detail"].lower()


def test_upload_content_type_falso_recusado_e_apagado_no_concluir(amb: Ambiente):
    armazenamento, repo, _ = _ligar_uploads(amb)

    pedir = amb.cliente.post(
        "/v1/uploads",
        headers=cab("t-cliente"),
        json={
            "destino": "avatar",
            "nome_arquivo": "disfarcado.jpg",
            "content_type": "image/jpeg",
            "tamanho_bytes": len(EXECUTAVEL),
        },
    )
    assert pedir.status_code == 201, pedir.text
    upload_id = pedir.json()["upload_id"]
    sol = repo.solicitacao(upload_id)
    assert sol is not None

    # Envia bytes de executavel fingindo ser JPEG.
    armazenamento.gravar(sol.bucket, sol.caminho, EXECUTAVEL, "image/jpeg")

    concluir = amb.cliente.post(f"/v1/uploads/{upload_id}/concluir", headers=cab("t-cliente"))
    assert concluir.status_code == 422, concluir.text
    assert "conteúdo" in concluir.json()["detail"].lower()
    # Arquivo suspeito precisa ser removido do bucket.
    with pytest.raises(ArquivoNaoEncontrado):
        armazenamento.ler(sol.bucket, sol.caminho)


def test_upload_arquivo_vazio_recusado_no_pedir_e_no_concluir(amb: Ambiente):
    armazenamento, repo, _ = _ligar_uploads(amb)

    r_zero = amb.cliente.post(
        "/v1/uploads",
        headers=cab("t-cliente"),
        json={
            "destino": "avatar",
            "nome_arquivo": "vazio.jpg",
            "content_type": "image/jpeg",
            "tamanho_bytes": 0,
        },
    )
    assert r_zero.status_code == 422, r_zero.text

    # Mente tamanho > 0 no pedir, mas grava 0 bytes no storage.
    pedir = amb.cliente.post(
        "/v1/uploads",
        headers=cab("t-cliente"),
        json={
            "destino": "avatar",
            "nome_arquivo": "vazio.jpg",
            "content_type": "image/jpeg",
            "tamanho_bytes": 64,
        },
    )
    assert pedir.status_code == 201, pedir.text
    sol = repo.solicitacao(pedir.json()["upload_id"])
    assert sol is not None
    armazenamento.gravar(sol.bucket, sol.caminho, b"", "image/jpeg")

    concluir = amb.cliente.post(f"/v1/uploads/{sol.id}/concluir", headers=cab("t-cliente"))
    assert concluir.status_code == 422, concluir.text
    with pytest.raises(ArquivoNaoEncontrado):
        armazenamento.ler(sol.bucket, sol.caminho)


def test_upload_tamanho_acima_do_limite_recusado_no_pedir_e_no_concluir(amb: Ambiente):
    armazenamento, repo, _ = _ligar_uploads(amb)
    limite_foto = obter_config_seguranca().uploads["foto"].tamanho_max_bytes

    r_grande = amb.cliente.post(
        "/v1/uploads",
        headers=cab("t-cliente"),
        json={
            "destino": "avatar",
            "nome_arquivo": "gigante.jpg",
            "content_type": "image/jpeg",
            "tamanho_bytes": limite_foto + 1,
        },
    )
    assert r_grande.status_code == 422, r_grande.text
    assert "grande" in r_grande.json()["detail"].lower()

    # Declara 64 bytes no pedir, mas envia JPEG maior que o declarado.
    pedir = amb.cliente.post(
        "/v1/uploads",
        headers=cab("t-cliente"),
        json={
            "destino": "avatar",
            "nome_arquivo": "mentiroso.jpg",
            "content_type": "image/jpeg",
            "tamanho_bytes": 64,
        },
    )
    assert pedir.status_code == 201, pedir.text
    sol = repo.solicitacao(pedir.json()["upload_id"])
    assert sol is not None
    armazenamento.gravar(sol.bucket, sol.caminho, JPEG_COM_EXIF + b"\x00" * 200, "image/jpeg")

    concluir = amb.cliente.post(f"/v1/uploads/{sol.id}/concluir", headers=cab("t-cliente"))
    assert concluir.status_code == 422, concluir.text
    assert "maior" in concluir.json()["detail"].lower()
    with pytest.raises(ArquivoNaoEncontrado):
        armazenamento.ler(sol.bucket, sol.caminho)


@pytest.mark.parametrize(
    "nome_hostil",
    [
        "../../etc/passwd.jpg",
        "..\\..\\windows\\win.ini.jpg",
        "subdir/foto.jpg",
        "foto\x00.jpg",
    ],
)
def test_upload_path_traversal_no_nome_recusado(amb: Ambiente, nome_hostil: str):
    _ligar_uploads(amb)

    r = amb.cliente.post(
        "/v1/uploads",
        headers=cab("t-cliente"),
        json={
            "destino": "avatar",
            "nome_arquivo": nome_hostil,
            "content_type": "image/jpeg",
            "tamanho_bytes": len(JPEG_COM_EXIF),
        },
    )
    assert r.status_code == 422, f"{nome_hostil!r} -> {r.status_code}: {r.text}"
    assert "inválido" in r.json()["detail"].lower()


def test_upload_jpeg_valido_remove_exif_e_conclui_200(amb: Ambiente):
    armazenamento, repo, _ = _ligar_uploads(amb)

    pedir = amb.cliente.post(
        "/v1/uploads",
        headers=cab("t-cliente"),
        json={
            "destino": "avatar",
            "nome_arquivo": "perfil.jpg",
            "content_type": "image/jpeg",
            "tamanho_bytes": len(JPEG_COM_EXIF),
        },
    )
    assert pedir.status_code == 201, pedir.text
    sol = repo.solicitacao(pedir.json()["upload_id"])
    assert sol is not None
    armazenamento.gravar(sol.bucket, sol.caminho, JPEG_COM_EXIF, "image/jpeg")

    concluir = amb.cliente.post(f"/v1/uploads/{sol.id}/concluir", headers=cab("t-cliente"))
    assert concluir.status_code == 200, concluir.text
    assert concluir.json()["status"] == "concluida"
    gravado = armazenamento.ler(sol.bucket, sol.caminho)
    assert b"GPSLatitude" not in gravado


# ================================================================================================
# 2. RATE LIMIT DO PERFIL PUBLICO COM MIDDLEWARE LIGADO (GET /v1/publico/profissionais/{id})
# ================================================================================================


def test_perfil_publico_rate_limit_middleware_padrao_dispara_429():
    http, app, ctx, _, _, _ = _montar_app_com_seguranca()
    modulo = modulo_em_memoria(app)
    ctx.usuarios.adicionar(
        PerfilDetalhe(
            id=PROFISSIONAL.id,
            papel=PapelUsuario.PROFISSIONAL,
            nome="Carlos Almeida",
            status="ativo",
            nota_publica=4.9,
            avaliacoes_total=12,
            servicos_concluidos=18,
        )
    )
    modulo.repo.salvar(
        PerfilProfissional(
            usuario_id=PROFISSIONAL.id,
            status="aprovado",
            bio="Eletricista residencial.",
            categorias=(),
            regioes=(),
            disponibilidade=(),
            portfolio=(),
            criado_em=AGORA,
            nivel_verificacao="verificado",
        )
    )

    url = f"/v1/publico/profissionais/{PROFISSIONAL.id}"
    # Regra padrao publico_perfil: 60 GETs/min por IP, bloqueio de 300s no 61o.
    codigos = []
    ultima = None
    for _ in range(61):
        ultima = http.get(url)
        codigos.append(ultima.status_code)

    assert codigos[:60] == [200] * 60
    assert codigos[60] == 429
    assert ultima is not None
    assert int(ultima.headers["retry-after"]) >= 300


def test_perfil_publico_inexistente_flood_tambem_dispara_429():
    regra = RegraLimite(
        nome="publico_perfil",
        prefixo="/v1/publico",
        metodos=["GET"],
        escopo="ip",
        maximo=5,
        janela_s=60,
        bloqueio_s=120,
    )
    http, app, _, _, _, _ = _montar_app_com_seguranca(limites=[regra])
    modulo_em_memoria(app)

    respostas = [http.get("/v1/publico/profissionais/prof-inexistente") for _ in range(6)]
    assert [r.status_code for r in respostas[:5]] == [404] * 5
    assert respostas[5].status_code == 429
    assert int(respostas[5].headers["retry-after"]) >= 120


# ================================================================================================
# 3. CONCORRENCIA COM THREADS SIMULTANEAS
# ================================================================================================


def test_concorrencia_reserva_tratinhos_no_mesmo_cliente_respeita_teto_e_saldo(fluxo: Fluxo):  # noqa: F811
    # Saldo 500 e teto cliente 500: em 8 cobrancas simultaneas do mesmo cliente, so 1 leva 500.
    repo = MoedasEmMemoria(
        ConfigMoedas(
            ativo=True,
            valor_moeda_centavos=1,
            teto_desconto_cliente_mes_centavos=500,
            teto_diario_desconto_centavos=1_000,
            orcamento_mensal_desconto_centavos=30_000,
            max_reservas_abertas=10,
            dias_liberacao_bonus=0,
        )
    )
    _dar_moedas(repo, CLIENTE.id, 500, "bonus:cli-corrida")
    fluxo.ctx.moedas = repo

    pedidos = [fluxo.aceitar() for _ in range(8)]
    respostas: list[tuple[int, int]] = []
    trava_lista = threading.Lock()
    largada = threading.Barrier(8)

    def cobrar(pid: str):
        largada.wait()
        r = fluxo.chamar(
            "POST",
            f"/v1/contratos/{pid}/cobranca",
            "t-cliente",
            {"meio": "pix", "usar_moedas": True},
        )
        with trava_lista:
            desconto = 100_000 - r.json()["valor_centavos"] if r.status_code == 201 else -1
            respostas.append((r.status_code, desconto))

    fios = [threading.Thread(target=cobrar, args=(pid,)) for pid in pedidos]
    for f in fios:
        f.start()
    for f in fios:
        f.join()

    assert len(respostas) == 8
    assert all(status == 201 for status, _ in respostas)
    descontos = [d for _, d in respostas]
    assert sum(descontos) == 500
    assert descontos.count(500) == 1
    assert descontos.count(0) == 7
    assert repo.orcamento_usado(mes_ref(AGORA)) == 500
    assert repo.orcamento_usado_dia(dia_ref(AGORA)) == 500


def test_concorrencia_cupom_limite_por_usuario_1_em_cobrancas_simultaneas(amb: Ambiente):
    amb.contexto.extras["cupons"] = {
        "UNICO10": {
            "codigo": "UNICO10",
            "tipo": "fixo",
            "valor": 1_000,
            "valor_minimo_centavos": 5_000,
            "limite_usos": 10,
            "limite_por_usuario": 1,
            "usos_atuais": 0,
            "ativo": True,
        }
    }
    resultados: list[bool] = []
    trava = threading.Lock()
    largada = threading.Barrier(6)

    def confirmar(idx: int):
        largada.wait()
        ok = confirmar_uso_cupom(
            amb.contexto,
            "UNICO10",
            usuario_id=CLIENTE.id,
            cobranca_id=f"cob-{idx}",
            pedido_id=f"ped-{idx}",
            desconto_centavos=1_000,
            confirmado_em=AGORA,
        )
        with trava:
            resultados.append(ok)

    fios = [threading.Thread(target=confirmar, args=(i,)) for i in range(6)]
    for f in fios:
        f.start()
    for f in fios:
        f.join()

    # limite_por_usuario=1: apenas 1 confirmacao pode ser aceita para o mesmo cliente.
    assert resultados.count(True) == 1
    assert amb.contexto.extras["cupons"]["UNICO10"]["usos_atuais"] == 1
    assert len(amb.contexto.extras["cupom_usos"]) == 1


def test_concorrencia_abertura_disputa_so_uma_vence_sem_duplicacao_nem_500(amb: Ambiente):
    amb.semear_pedido(E.EM_CONFIRMACAO, concluido_em=AGORA - timedelta(hours=2))
    amb.semear_dinheiro(100_000)

    statuses: list[int] = []
    trava = threading.Lock()
    largada = threading.Barrier(8)

    def abrir():
        largada.wait()
        r = amb.cliente.post(
            "/v1/pedidos/ped-1/disputa",
            headers=cab("t-cliente"),
            json={
                "motivo": "mal_feito",
                "descricao": "Problema voltou logo apos a conclusao.",
            },
        )
        with trava:
            statuses.append(r.status_code)

    fios = [threading.Thread(target=abrir) for _ in range(8)]
    for f in fios:
        f.start()
    for f in fios:
        f.join()

    assert len(statuses) == 8
    assert 500 not in statuses
    assert statuses.count(201) == 1
    assert statuses.count(409) == 7
    assert amb.contexto.pedidos.obter("ped-1").estado is E.EM_DISPUTA
    assert len(amb.contexto.disputas.listar()) == 1


def test_concorrencia_resposta_disputa_so_uma_vence_sem_duplicar_evidencias(amb: Ambiente):
    amb.semear_pedido(E.EM_CONFIRMACAO, concluido_em=AGORA - timedelta(hours=2))
    amb.semear_dinheiro(100_000)
    abertura = amb.cliente.post(
        "/v1/pedidos/ped-1/disputa",
        headers=cab("t-cliente"),
        json={"motivo": "mal_feito", "descricao": "Acabamento com defeito."},
    )
    assert abertura.status_code == 201, abertura.text

    statuses: list[int] = []
    trava = threading.Lock()
    largada = threading.Barrier(8)

    def responder():
        largada.wait()
        r = amb.cliente.post(
            "/v1/pedidos/ped-1/disputa/resposta",
            headers=cab("t-prof"),
            json={"solucao": "discordar", "mensagem": "Servico executado conforme combinado."},
        )
        with trava:
            statuses.append(r.status_code)

    fios = [threading.Thread(target=responder) for _ in range(8)]
    for f in fios:
        f.start()
    for f in fios:
        f.join()

    assert len(statuses) == 8
    assert 500 not in statuses
    assert statuses.count(200) == 1
    assert statuses.count(409) == 7
    # Cada resposta grava 2 evidencias (resposta + proposta_retorno): nao pode duplicar.
    assert len(amb.contexto.disputas._evidencias.get("ped-1", [])) == 2


def test_concorrencia_lgpd_pedir_exclusao_cria_no_maximo_um_pedido_ativo():
    # Limite folgado para testar concorrencia da regra de negocio LGPD (nao rate limit).
    http, _, _, _, _, repos_lgpd = _montar_app_com_seguranca(limites=[])

    statuses: list[int] = []
    trava = threading.Lock()
    largada = threading.Barrier(6)

    def pedir():
        largada.wait()
        r = http.post("/v1/me/exclusao", headers=cab("t-cliente"))
        with trava:
            statuses.append(r.status_code)

    fios = [threading.Thread(target=pedir) for _ in range(6)]
    for f in fios:
        f.start()
    for f in fios:
        f.join()

    assert len(statuses) == 6
    assert 500 not in statuses
    assert all(s == 200 for s in statuses)
    ativos = [
        p
        for p in repos_lgpd.exclusoes._pedidos.values()
        if p.usuario_id == CLIENTE.id and p.status in ("aguardando_confirmacao", "agendada")
    ]
    assert len(ativos) == 1


def test_concorrencia_lgpd_confirmar_exclusao_idempotente_sem_duplicar_auditoria():
    http, app, _, _, _, _ = _montar_app_com_seguranca(limites=[])

    passo1 = http.post("/v1/me/exclusao", headers=cab("t-cliente"))
    assert passo1.status_code == 200, passo1.text
    token = passo1.json()["token_confirmacao"]

    statuses: list[int] = []
    trava = threading.Lock()
    largada = threading.Barrier(6)

    def confirmar():
        largada.wait()
        r = http.post(
            "/v1/me/exclusao",
            headers=cab("t-cliente"),
            json={"token_confirmacao": token},
        )
        with trava:
            statuses.append(r.status_code)

    fios = [threading.Thread(target=confirmar) for _ in range(6)]
    for f in fios:
        f.start()
    for f in fios:
        f.join()

    assert len(statuses) == 6
    assert 500 not in statuses
    assert statuses.count(200) == 1
    assert statuses.count(409) == 5
    agendamentos = [
        e
        for e in app.state.seguranca.auditoria_em_memoria.eventos
        if e["acao"] == "dado_pessoal.exclusao_agendada"
    ]
    assert len(agendamentos) == 1


def test_concorrencia_exclusividade_48h_respeita_teto_3_e_idempotencia_sem_cobranca_dupla(
    amb: Ambiente,
):
    amb.contexto.moedas = MoedasEmMemoria(ConfigMoedas(ativo=True))
    _dar_moedas(amb.contexto.moedas, PROFISSIONAL.id, 1_000, "b:prof1", carteira="profissional")
    _dar_moedas(amb.contexto.moedas, OUTRO_PROFISSIONAL.id, 500, "b:prof2", carteira="profissional")
    for n in range(1, 10):
        pid = f"ped-ex-{n}"
        amb.semear_pedido(E.ABERTO, id=pid)
        amb.contexto.pedidos._dados[pid] = DadosPedido("cat-1", "cid-1", "Pintura", "Sala")

    # 1) 8 threads pedindo exclusividade em 8 pedidos distintos -> maximo 3 simultaneas, -300 moedas.
    resultados: list[tuple[int, str | None]] = []
    trava = threading.Lock()
    largada = threading.Barrier(8)

    def pedir(n: int):
        largada.wait()
        r = amb.cliente.post(
            "/v1/profissional/exclusividades",
            headers=cab("t-prof"),
            json={"pedido_id": f"ped-ex-{n}", "chave_idempotencia": f"chave-ex-{n}"},
        )
        with trava:
            resultados.append((r.status_code, r.json().get("codigo")))

    fios = [threading.Thread(target=pedir, args=(n,)) for n in range(1, 9)]
    for f in fios:
        f.start()
    for f in fios:
        f.join()

    assert len(resultados) == 8
    assert all(s != 500 for s, _ in resultados)
    assert sum(1 for s, _ in resultados if s == 201) == 3
    assert sum(1 for s, c in resultados if s == 409 and c == "limite_simultaneas") == 5
    assert saldo_profissional(amb.contexto.moedas, PROFISSIONAL.id, amb.relogio.agora) == 700

    # 2) 6 threads com a MESMA chave_idempotencia no mesmo pedido -> cobra apenas 100 (nunca em dobro).
    res_idem: list[int] = []
    largada2 = threading.Barrier(6)

    def pedir_mesma_chave():
        largada2.wait()
        r = amb.cliente.post(
            "/v1/profissional/exclusividades",
            headers=cab("t-outro-prof"),
            json={"pedido_id": "ped-ex-9", "chave_idempotencia": "chave-unica-9"},
        )
        with trava:
            res_idem.append(r.status_code)

    fios2 = [threading.Thread(target=pedir_mesma_chave) for _ in range(6)]
    for f in fios2:
        f.start()
    for f in fios2:
        f.join()

    assert 500 not in res_idem
    assert res_idem.count(201) == 1
    assert res_idem.count(200) == 5
    assert saldo_profissional(amb.contexto.moedas, OUTRO_PROFISSIONAL.id, amb.relogio.agora) == 400


def test_exclusividade_48h_devolve_moedas_quando_cliente_aceita_outro_orcamento_antes_48h(
    amb: Ambiente,
):
    amb.contexto.moedas = MoedasEmMemoria(ConfigMoedas(ativo=True))
    _dar_moedas(
        amb.contexto.moedas, PROFISSIONAL.id, 300, "b:prof-estorno", carteira="profissional"
    )
    amb.semear_pedido(E.ABERTO, id="ped-estorno")
    amb.contexto.pedidos._dados["ped-estorno"] = DadosPedido("cat-1", "cid-1", "Eletrica", "Quadro")
    amb.contexto.orcamentos.adicionar(
        Orcamento("orc-concorrente", "ped-estorno", OUTRO_PROFISSIONAL.id, 12_000, "cat-1")
    )

    pedir = amb.cliente.post(
        "/v1/profissional/exclusividades",
        headers=cab("t-prof"),
        json={"pedido_id": "ped-estorno", "chave_idempotencia": "k-estorno"},
    )
    assert pedir.status_code == 201, pedir.text
    eid = pedir.json()["id"]
    assert saldo_profissional(amb.contexto.moedas, PROFISSIONAL.id, amb.relogio.agora) == 200

    aceitar_ex = amb.cliente.post(
        f"/v1/pedidos/ped-estorno/exclusividade/{eid}/responder",
        headers=cab("t-cliente"),
        json={"decisao": "aceitar"},
    )
    assert aceitar_ex.status_code == 200 and aceitar_ex.json()["status"] == "ativa"

    # 12h depois (antes das 48h), cliente aceita orcamento do outro profissional.
    amb.relogio.avancar(hours=12)
    aceite = amb.cliente.post(
        "/v1/pedidos/ped-estorno/acoes/aceitar_orcamento",
        headers=cab("t-cliente"),
        json={"prova": {"orcamento_id": "orc-concorrente"}},
    )
    assert aceite.status_code == 200, aceite.text
    assert amb.contexto.pedidos.obter("ped-estorno").estado is E.ORCAMENTO_ACEITO
    assert amb.contexto.exclusividades.obter(eid).status == "cancelada"
    # Devolucao integral das 100 moedas ao profissional da exclusividade.
    assert saldo_profissional(amb.contexto.moedas, PROFISSIONAL.id, amb.relogio.agora) == 300


# ================================================================================================
# 4. TETOS DE TRATINHOS NO CENTAVO EXATO + FRONTEIRA DIA/MES EM AMERICA/SAO_PAULO
# ================================================================================================


def test_tratinhos_teto_cliente_500_centavos_no_centavo_exato():
    repo = MoedasEmMemoria(
        ConfigMoedas(ativo=True, max_reservas_abertas=10, dias_liberacao_bonus=0)
    )
    _dar_moedas(repo, CLIENTE.id, 2_000, "b:teto-cli")

    # 499 centavos usados: sobra exatamente 1 centavo.
    assert (
        reservar_desconto(repo, cobranca_id="c-499", moedas=499, usuario_id=CLIENTE.id, agora=AGORA)
        == 499
    )
    disp = disponibilidade_desconto(repo, usuario_id=CLIENTE.id, agora=AGORA)
    assert disp.disponivel is True and disp.restante_centavos == 1
    uso = calcular_uso_moedas(repo, usuario_id=CLIENTE.id, servico_centavos=50_000, agora=AGORA)
    assert (uso.moedas, uso.desconto_centavos) == (1, 1)

    # +1 centavo completa os 500 (R$ 5,00 exatos).
    assert (
        reservar_desconto(repo, cobranca_id="c-500", moedas=1, usuario_id=CLIENTE.id, agora=AGORA)
        == 1
    )
    disp_fim = disponibilidade_desconto(repo, usuario_id=CLIENTE.id, agora=AGORA)
    assert disp_fim.disponivel is False
    assert disp_fim.motivo == MOTIVO_TETO_CLIENTE
    assert disp_fim.restante_centavos == 0
    assert disp_fim.volta_em == date(2026, 11, 1)

    # +1 centavo alem do teto e recusado atomicamente.
    with pytest.raises(DescontoMoedasIndisponivel) as exc:
        reservar_desconto(repo, cobranca_id="c-501", moedas=1, usuario_id=CLIENTE.id, agora=AGORA)
    assert exc.value.motivo == MOTIVO_TETO_CLIENTE


def test_tratinhos_teto_diario_1000_centavos_no_centavo_exato():
    repo = MoedasEmMemoria(
        ConfigMoedas(ativo=True, max_reservas_abertas=10, dias_liberacao_bonus=0)
    )
    for uid in ("cli-d1", "cli-d2", "cli-d3", "cli-d4"):
        _dar_moedas(repo, uid, 1_000, f"b:{uid}")

    assert (
        reservar_desconto(repo, cobranca_id="d1", moedas=500, usuario_id="cli-d1", agora=AGORA)
        == 500
    )
    assert (
        reservar_desconto(repo, cobranca_id="d2", moedas=499, usuario_id="cli-d2", agora=AGORA)
        == 499
    )
    assert repo.orcamento_usado_dia(dia_ref(AGORA)) == 999

    # Sobra exatamente 1 centavo no dia (1000 - 999).
    disp = disponibilidade_desconto(repo, usuario_id="cli-d3", agora=AGORA)
    assert disp.disponivel is True and disp.restante_centavos == 1
    uso = calcular_uso_moedas(repo, usuario_id="cli-d3", servico_centavos=50_000, agora=AGORA)
    assert (uso.moedas, uso.desconto_centavos) == (1, 1)

    assert (
        reservar_desconto(repo, cobranca_id="d3", moedas=1, usuario_id="cli-d3", agora=AGORA) == 1
    )
    assert repo.orcamento_usado_dia(dia_ref(AGORA)) == 1_000

    # Proximo centavo bate no teto diario (volta amanha em Sao Paulo: 2026-10-30).
    disp_fim = disponibilidade_desconto(repo, usuario_id="cli-d4", agora=AGORA)
    assert disp_fim.disponivel is False
    assert disp_fim.motivo == MOTIVO_LIMITE_DIARIO
    assert disp_fim.volta_em == date(2026, 10, 30)

    with pytest.raises(DescontoMoedasIndisponivel) as exc:
        reservar_desconto(repo, cobranca_id="d4", moedas=1, usuario_id="cli-d4", agora=AGORA)
    assert exc.value.motivo == MOTIVO_LIMITE_DIARIO


def test_tratinhos_orcamento_mensal_30000_centavos_no_centavo_exato():
    repo = MoedasEmMemoria(
        ConfigMoedas(ativo=True, max_reservas_abertas=10, dias_liberacao_bonus=0)
    )
    # 29 dias x 1000 centavos (2 clientes x 500 por dia) = 29.000 centavos.
    for dia in range(1, 30):
        instante = datetime(2026, 10, dia, 15, 0, tzinfo=UTC)  # 12:00 BRT
        for slot in (1, 2):
            uid = f"cli-m-{dia}-{slot}"
            _dar_moedas(repo, uid, 500, f"b:{uid}", agora=instante)
            reservar_desconto(
                repo, cobranca_id=f"c-{dia}-{slot}", moedas=500, usuario_id=uid, agora=instante
            )

    # Dia 30: +999 centavos (500 + 499) -> total mensal = 29.999 centavos.
    dia30 = datetime(2026, 10, 30, 15, 0, tzinfo=UTC)
    for uid, _val in (("cli-30-a", 500), ("cli-30-b", 499), ("cli-30-c", 500), ("cli-31", 500)):
        _dar_moedas(repo, uid, 500, f"b:{uid}", agora=dia30)
    reservar_desconto(repo, cobranca_id="c-30-a", moedas=500, usuario_id="cli-30-a", agora=dia30)
    reservar_desconto(repo, cobranca_id="c-30-b", moedas=499, usuario_id="cli-30-b", agora=dia30)
    assert repo.orcamento_usado(date(2026, 10, 1)) == 29_999

    # Sobra exatamente 1 centavo no orcamento mensal (30.000 - 29.999).
    uso = calcular_uso_moedas(repo, usuario_id="cli-30-c", servico_centavos=50_000, agora=dia30)
    assert (uso.moedas, uso.desconto_centavos) == (1, 1)
    reservar_desconto(repo, cobranca_id="c-30-c", moedas=1, usuario_id="cli-30-c", agora=dia30)
    assert repo.orcamento_usado(date(2026, 10, 1)) == 30_000

    # No dia 31 (novo dia, teto diario zerado), orcamento mensal continua esgotado.
    dia31 = datetime(2026, 10, 31, 15, 0, tzinfo=UTC)
    disp = disponibilidade_desconto(repo, usuario_id="cli-31", agora=dia31)
    assert disp.disponivel is False
    assert disp.motivo == MOTIVO_ORCAMENTO_ESGOTADO
    assert disp.volta_em == date(2026, 11, 1)

    with pytest.raises(DescontoMoedasIndisponivel) as exc:
        reservar_desconto(repo, cobranca_id="c-31", moedas=1, usuario_id="cli-31", agora=dia31)
    assert exc.value.motivo == MOTIVO_ORCAMENTO_ESGOTADO


def test_tratinhos_fronteira_dia_e_mes_sao_paulo_no_contexto_e_rota_real(fluxo: Fluxo):  # noqa: F811
    # 2026-10-31 23:59:59 em America/Sao_Paulo = 2026-11-01 02:59:59 UTC!
    antes = datetime(2026, 11, 1, 2, 59, 59, tzinfo=UTC)
    fluxo.amb.relogio.agora = antes

    repo = MoedasEmMemoria(
        ConfigMoedas(ativo=True, max_reservas_abertas=10, dias_liberacao_bonus=0)
    )
    _dar_moedas(repo, CLIENTE.id, 1_500, "b:front-cli", agora=antes - timedelta(days=1))
    _dar_moedas(repo, OUTRO_CLIENTE.id, 1_000, "b:front-outro", agora=antes - timedelta(days=1))
    fluxo.ctx.moedas = repo

    pid = fluxo.aceitar()

    # Esgota teto diario (1000) e teto do cliente (500) em 31/10 (23:59:59 BRT).
    reservar_desconto(repo, cobranca_id="c-out-1", moedas=500, usuario_id=CLIENTE.id, agora=antes)
    repo.confirmar_reserva(repo._reservas[next(iter(repo._reservas))].cobranca_id)
    reservar_desconto(
        repo, cobranca_id="c-out-2", moedas=500, usuario_id=OUTRO_CLIENTE.id, agora=antes
    )
    assert dia_ref(antes) == date(2026, 10, 31)
    assert mes_ref(antes) == date(2026, 10, 1)

    previa_antes = fluxo.chamar("GET", f"/v1/pedidos/{pid}/pagamento?usar_moedas=true", "t-cliente")
    assert previa_antes.status_code == 200, previa_antes.text
    corpo_antes = previa_antes.json()
    assert corpo_antes["moedas_usadas"] == 0
    assert corpo_antes["desconto_disponivel"] is False
    assert corpo_antes["desconto_indisponivel_motivo"] == MOTIVO_LIMITE_DIARIO
    assert corpo_antes["desconto_volta_em"] == "2026-11-01"

    # +1 segundo: 2026-11-01 00:00:00 em America/Sao_Paulo (03:00:00 UTC) -> vira dia e mes!
    fluxo.amb.relogio.avancar(seconds=1)
    depois = fluxo.amb.relogio.agora
    assert dia_ref(depois) == date(2026, 11, 1)
    assert mes_ref(depois) == date(2026, 11, 1)

    previa_depois = fluxo.chamar(
        "GET", f"/v1/pedidos/{pid}/pagamento?usar_moedas=true", "t-cliente"
    )
    assert previa_depois.status_code == 200, previa_depois.text
    corpo_depois = previa_depois.json()
    assert corpo_depois["desconto_disponivel"] is True
    assert corpo_depois["desconto_centavos"] == 500
    assert corpo_depois["moedas_usadas"] == 500


def test_tratinhos_reserva_pendente_mes_anterior_nao_bloqueia_teto_novo_mes():
    # Cliente reservou 500 centavos as 23:55 BRT de 31/10 (ainda pendente aos 00:05 BRT de 01/11).
    antes = datetime(2026, 11, 1, 2, 55, 0, tzinfo=UTC)  # 31/10 23:55 BRT
    depois = datetime(2026, 11, 1, 3, 5, 0, tzinfo=UTC)  # 01/11 00:05 BRT

    repo = MoedasEmMemoria(ConfigMoedas(ativo=True, max_reservas_abertas=5, dias_liberacao_bonus=0))
    _dar_moedas(repo, CLIENTE.id, 1_500, "b:virada-res", agora=antes - timedelta(days=1))

    reservar_desconto(repo, cobranca_id="c-31out", moedas=500, usuario_id=CLIENTE.id, agora=antes)

    # Em 01/11 00:05 BRT, a reserva de 31/10 pertence a outubro (mes_ref=2026-10-01),
    # nao deve consumir o teto mensal de novembro do cliente.
    disp = disponibilidade_desconto(repo, usuario_id=CLIENTE.id, agora=depois)
    assert disp.disponivel is True
    assert disp.restante_centavos == 500


def test_tratinhos_bonus_avaliacao_respeita_fronteira_mes_sao_paulo():
    # Cliente ja atingiu o teto_mensal_moedas (500) em outubro (15/10).
    repo = MoedasEmMemoria(
        ConfigMoedas(
            ativo=True,
            bonus_avaliacao_moedas=50,
            teto_mensal_moedas=500,
            max_bonus_por_profissional_mes=10,
            dias_liberacao_bonus=0,
        )
    )
    outubro_meio = datetime(2026, 10, 15, 15, 0, tzinfo=UTC)
    _dar_moedas(repo, CLIENTE.id, 500, "avaliacao:ped-cheio", agora=outubro_meio)

    # 31/10 23:30 BRT = 01/11 02:30 UTC: ainda e outubro em America/Sao_Paulo!
    ainda_outubro_brt = datetime(2026, 11, 1, 2, 30, 0, tzinfo=UTC)
    assert mes_ref(ainda_outubro_brt) == date(2026, 10, 1)

    concedido = conceder_bonus_avaliacao(
        repo,
        cliente_id=CLIENTE.id,
        pedido_id="ped-ultimo-dia",
        valor_servico_centavos=10_000,
        agora=ainda_outubro_brt,
        profissional_id=PROFISSIONAL.id,
    )
    assert concedido == 0
