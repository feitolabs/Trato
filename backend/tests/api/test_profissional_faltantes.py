"""Testes dos 6 itens faltantes do Profissional (backend API e regras)."""

from __future__ import annotations

import struct
from datetime import timedelta

from conftest import AGORA, CLIENTE, OUTRO_PROFISSIONAL, PROFISSIONAL, cab

from trato.api.repositorios import DadosPedido
from trato.api.rotas_profissional_cadastro import modulo_em_memoria
from trato.financeiro.ledger import TipoLancamento, liberar
from trato.pedidos import estados
from trato.pedidos.estados import Ator, Estado, Janela, Papel, Pedido
from trato.profissional.repositorio import PerfilProfissional, Regiao
from trato.rotinas.regras import ConfigRotinas, PedidoMonitorado, transicoes_por_prazo
from trato.seguranca.config import obter_config_seguranca
from trato.uploads import ArmazenamentoFake
from trato.uploads.config import ConfigUploads
from trato.uploads.servico import ServicoUploads, UploadsEmMemoria


def _seg(marca: int, corpo: bytes) -> bytes:
    return bytes([0xFF, marca]) + struct.pack(">H", len(corpo) + 2) + corpo


_JPEG_TESTE = (
    b"\xff\xd8"
    + _seg(0xE0, b"JFIF\x00\x01\x01\x00\x00\x01\x00\x01\x00\x00")
    + _seg(0xC0, b"\x08\x00\x10\x00\x10\x01\x01\x11\x00")
    + b"\xff\xda\x00\x08\x01\x01\x00\x00\x3f\x00IMG"
    + b"\xff\xd9"
)


def _instalar_modulo(amb, *, usuario_id=PROFISSIONAL.id, disponivel=False):
    mod = modulo_em_memoria(amb.cliente.app)
    mod.catalogo.categorias["cat-pintura"] = "pintura"
    mod.catalogo.nomes["cat-pintura"] = "Pintura"
    mod.catalogo.cidades.add("bh")
    mod.repo.salvar(
        PerfilProfissional(
            usuario_id=usuario_id,
            status="aprovado",
            bio="Pintor residencial",
            categorias=("cat-pintura", "pintura"),
            regioes=(Regiao("bh", "Centro"),),
            disponibilidade=(),
            portfolio=(),
            criado_em=AGORA,
            nivel_verificacao="verificado",
            disponivel_agora=disponivel,
        )
    )
    return mod


def _instalar_uploads(amb, alvo: tuple[float, float] | None = (-19.919, -43.938)):
    armazenamento = ArmazenamentoFake()
    repo = UploadsEmMemoria()
    servico = ServicoUploads(
        armazenamento,
        repo,
        obter_config_seguranca(),
        ConfigUploads(),
        amb.relogio,
        lambda _pid: alvo,
    )
    amb.cliente.app.state.servico_uploads = servico
    return armazenamento, repo


def _enviar_foto(amb, armazenamento, repo, quem: str, destino: str, pedido_id: str) -> str:
    pedir = amb.cliente.post(
        "/v1/uploads",
        json={
            "destino": destino,
            "pedido_id": pedido_id,
            "nome_arquivo": "foto.jpg",
            "content_type": "image/jpeg",
            "tamanho_bytes": len(_JPEG_TESTE),
        },
        headers=cab(quem),
    )
    assert pedir.status_code == 201, pedir.text
    sol = repo.solicitacao(pedir.json()["upload_id"])
    armazenamento.simular_envio(sol.bucket, sol.caminho, _JPEG_TESTE)
    concluir = amb.cliente.post(f"/v1/uploads/{sol.id}/concluir", headers=cab(quem))
    assert concluir.status_code == 200, concluir.text
    return concluir.json()["midia_id"]


def test_1_conta_recebimento_valida_titularidade_mascara_e_nao_vaza_publico(amb):
    _instalar_modulo(amb)
    r_cpf_dono = amb.cliente.post(
        "/v1/me/dados-pessoais",
        json={"cpf": "52998224725"},
        headers=cab("t-prof"),
    )
    assert r_cpf_dono.status_code == 204, r_cpf_dono.text

    vazio = amb.cliente.get("/v1/profissional/conta-recebimento", headers=cab("t-prof"))
    assert vazio.status_code == 200 and vazio.json()["cadastrada"] is False

    invalido = amb.cliente.put(
        "/v1/profissional/conta-recebimento",
        json={"tipo_pix": "cpf", "chave_pix": "00000000000"},
        headers=cab("t-prof"),
    )
    assert invalido.status_code == 422

    terceiro = amb.cliente.put(
        "/v1/profissional/conta-recebimento",
        json={"tipo_pix": "cpf", "chave_pix": "12345678909"},
        headers=cab("t-prof"),
    )
    assert terceiro.status_code == 422
    assert "titular" in terceiro.json()["detail"]

    ok = amb.cliente.put(
        "/v1/profissional/conta-recebimento",
        json={
            "tipo_pix": "cpf",
            "chave_pix": "529.982.247-25",
            "banco_codigo": "341",
            "banco_nome": "Itaú",
            "agencia": "1234",
            "conta": "56789-0",
            "tipo_conta": "corrente",
        },
        headers=cab("t-prof"),
    )
    assert ok.status_code == 200, ok.text
    corpo = ok.json()
    assert corpo["cadastrada"] is True
    assert corpo["chave_pix"] == "52998224725"
    assert "***.982.247-**" in corpo["chave_pix_mascarada"]
    assert "Itaú" in corpo["resumo_exibicao"]

    pub = amb.cliente.get(f"/v1/profissionais/{PROFISSIONAL.id}", headers=cab("t-cliente"))
    assert pub.status_code == 200
    assert "conta_recebimento" not in pub.json()
    assert "52998224725" not in pub.text


def test_2_detalhe_pedido_aberto_inclui_fotos_urls_do_cliente(amb):
    _instalar_modulo(amb)
    armazenamento, repo = _instalar_uploads(amb)
    amb.contexto.pedidos.salvar(
        Pedido("ped-foto", CLIENTE.id, AGORA),
        None,
        DadosPedido("pintura", "bh", "Pintura quarto", "Parede manchada", bairro="Centro"),
    )
    _enviar_foto(amb, armazenamento, repo, "t-cliente", "pedido", "ped-foto")

    det = amb.cliente.get("/v1/profissional/pedidos-abertos/ped-foto", headers=cab("t-prof"))
    assert det.status_code == 200, det.text
    fotos = det.json()["fotos_urls"]
    assert len(fotos) == 1 and "ped-foto" in fotos[0]


def test_3_ver_detalhe_e_editar_orcamento_enviado_antes_do_aceite(amb):
    amb.contexto.pedidos.salvar(
        Pedido("ped-orc", CLIENTE.id, AGORA),
        None,
        DadosPedido("pintura", "bh", "Pintura sala", "Sala 25m2", bairro="Centro"),
    )
    r1 = amb.cliente.post(
        "/v1/pedidos/ped-orc/orcamentos",
        json={
            "itens": [
                {
                    "tipo": "deslocamento",
                    "descricao": "Deslocamento",
                    "quantidade": "1",
                    "valor_unitario_centavos": 10_000,
                },
                {
                    "tipo": "horas",
                    "descricao": "Mão de obra",
                    "quantidade": "3",
                    "valor_unitario_centavos": 10_000,
                },
                {
                    "tipo": "material",
                    "descricao": "Tinta 18L",
                    "quantidade": "1",
                    "valor_unitario_centavos": 20_000,
                },
            ],
            "prazo_execucao_dias": 2,
            "garantia_dias": 90,
            "fora_do_escopo": "Massa corrida",
            "observacoes": "Inclui proteção do piso",
        },
        headers=cab("t-prof"),
    )
    assert r1.status_code == 201, r1.text
    orc_v1 = r1.json()["id"]

    det1 = amb.cliente.get(f"/v1/orcamentos/{orc_v1}", headers=cab("t-prof"))
    assert det1.status_code == 200, det1.text
    j1 = det1.json()
    assert j1["versao"] == 1
    assert j1["valor_centavos"] == 60_000
    assert j1["horas_deslocamento"] == "1"
    assert j1["horas_trabalhadas"] == "3"
    assert j1["fora_do_escopo"] == "Massa corrida"
    assert j1["observacoes"] == "Inclui proteção do piso"
    assert "taxa_centavos" not in j1 and "liquido_centavos" not in j1

    # Envia edição (v2) antes de qualquer contraproposta
    r2 = amb.cliente.post(
        "/v1/pedidos/ped-orc/orcamentos",
        json={
            "itens": [
                {
                    "tipo": "horas",
                    "descricao": "Mão de obra revisada",
                    "quantidade": "4",
                    "valor_unitario_centavos": 12_000,
                },
            ],
            "prazo_execucao_dias": 3,
            "garantia_dias": 120,
            "fora_do_escopo": "Remoção de papel de parede",
        },
        headers=cab("t-prof"),
    )
    assert r2.status_code == 201, r2.text
    orc_v2 = r2.json()["id"]
    assert orc_v2 != orc_v1 and r2.json()["versao"] == 2

    lista = amb.cliente.get("/v1/profissional/orcamentos", headers=cab("t-prof")).json()
    do_pedido = [o for o in lista if o["pedido_id"] == "ped-orc"]
    assert len(do_pedido) == 1
    assert do_pedido[0]["orcamento_id"] == orc_v2
    assert do_pedido[0]["versao"] == 2
    assert do_pedido[0]["situacao"] == "aguardando"
    assert do_pedido[0]["valor_centavos"] == 48_000


def test_4_baixar_extrato_mensal_em_pdf_pelo_profissional(amb):
    amb.semear_pedido(Estado.CONCLUIDO)
    amb.semear_dinheiro(cobrado=100_000, taxa=7_500)
    liberar(amb.contexto.ledger.livro, "ped-1", PROFISSIONAL.id, "lib-1", AGORA)
    assert any(item.tipo is TipoLancamento.REPASSE for item in amb.contexto.ledger.lancamentos())

    ok = amb.cliente.get("/v1/profissionais/me/extrato.pdf?mes=2026-10", headers=cab("t-prof"))
    assert ok.status_code == 200, ok.text
    assert ok.headers["content-type"].startswith("application/pdf")
    assert "trato_extrato_2026_10.pdf" in ok.headers.get("content-disposition", "")
    assert ok.content.startswith(b"%PDF-")

    invalido = amb.cliente.get(
        "/v1/profissionais/me/extrato.pdf?mes=2026-13", headers=cab("t-prof")
    )
    assert invalido.status_code == 422

    proibido_cliente = amb.cliente.get(
        "/v1/profissionais/me/extrato.pdf?mes=2026-10", headers=cab("t-cliente")
    )
    assert proibido_cliente.status_code == 403


def test_5_disponivel_agora_prioriza_e_notifica_pedidos_urgentes(amb):
    mod = _instalar_modulo(amb, usuario_id=PROFISSIONAL.id, disponivel=False)
    mod.repo.salvar(
        PerfilProfissional(
            usuario_id=OUTRO_PROFISSIONAL.id,
            status="aprovado",
            bio="Pintor 2",
            categorias=("cat-pintura", "pintura"),
            regioes=(Regiao("bh", "Centro"),),
            disponibilidade=(),
            portfolio=(),
            criado_em=AGORA,
            nivel_verificacao="verificado",
            disponivel_agora=False,
        )
    )

    # Liga disponivel_agora para t-prof (OUTRO_PROFISSIONAL continua desligado)
    patch = amb.cliente.patch(
        "/v1/profissional/perfil",
        json={"disponivel_agora": True},
        headers=cab("t-prof"),
    )
    assert patch.status_code == 200 and patch.json()["disponivel_agora"] is True
    assert amb.cliente.get("/v1/me", headers=cab("t-prof")).json()["disponivel_agora"] is True

    # Pedido urgente mais antigo vs pedido normal mais novo
    amb.contexto.pedidos.salvar(
        Pedido("ped-urgente-antigo", CLIENTE.id, AGORA - timedelta(hours=2)),
        None,
        DadosPedido("pintura", "bh", "Vazamento urgente", "Urgente", bairro="Centro", urgente=True),
    )
    amb.contexto.pedidos.salvar(
        Pedido("ped-normal-novo", CLIENTE.id, AGORA - timedelta(minutes=10)),
        None,
        DadosPedido(
            "pintura", "bh", "Pintura sem pressa", "Normal", bairro="Centro", urgente=False
        ),
    )

    lista_ativo = amb.cliente.get("/v1/profissional/pedidos-abertos", headers=cab("t-prof")).json()
    assert [p["id"] for p in lista_ativo][:2] == ["ped-urgente-antigo", "ped-normal-novo"]

    lista_desligado = amb.cliente.get(
        "/v1/profissional/pedidos-abertos", headers=cab("t-outro-prof")
    ).json()
    assert [p["id"] for p in lista_desligado][:2] == ["ped-normal-novo", "ped-urgente-antigo"]

    # Abrir pedido urgente pela API notifica apenas t-prof
    abrir = amb.cliente.post(
        "/v1/pedidos",
        json={
            "categoria_id": "pintura",
            "cidade_id": "bh",
            "titulo": "Urgente agora",
            "descricao": "Preciso hoje",
            "modalidade": "presencial",
            "urgente": True,
            "endereco": {
                "logradouro": "Av Afonso Pena",
                "numero": "100",
                "bairro": "Centro",
                "cep": "30130-000",
            },
        },
        headers=cab("t-cliente"),
    )
    assert abrir.status_code == 201, abrir.text
    notas_ativo = amb.cliente.get("/v1/notificacoes", headers=cab("t-prof")).json()
    notas_inativo = amb.cliente.get("/v1/notificacoes", headers=cab("t-outro-prof")).json()
    assert any(n["tipo"] == "pedido.urgente" for n in notas_ativo)
    assert not any(n["tipo"] == "pedido.urgente" for n in notas_inativo)


def test_6_cliente_ausente_exige_prova_notifica_envia_chat_e_bloqueia_ausencia_automatica(amb):
    armazenamento, repo = _instalar_uploads(amb, alvo=(-19.919, -43.938))
    inicio = AGORA + timedelta(minutes=5)  # dentro da janela (até 15 min antes)
    fim = inicio + timedelta(hours=2)
    amb.semear_pedido(
        Estado.AGENDADO,
        janela=Janela(inicio, fim),
        codigo_inicio="1234",
    )

    # Sem foto e GPS -> 422
    sem_prova = amb.cliente.post(
        "/v1/pedidos/ped-1/acoes/registrar_cliente_ausente",
        json={"prova": {}},
        headers=cab("t-prof"),
    )
    assert sem_prova.status_code == 422

    # Longe do local -> 422
    midia_longe = _enviar_foto(amb, armazenamento, repo, "t-prof", "checkin", "ped-1")
    longe = amb.cliente.post(
        "/v1/pedidos/ped-1/acoes/registrar_cliente_ausente",
        json={
            "prova": {
                "foto": {"arquivo_id": midia_longe, "tirada_em": AGORA.isoformat()},
                "localizacao": {"latitude": -23.550, "longitude": -46.633},
            }
        },
        headers=cab("t-prof"),
    )
    assert longe.status_code == 422

    # Muito antes da janela (> 15 min) -> 422
    inicio_longe = AGORA + timedelta(hours=4)
    amb.semear_pedido(
        Estado.AGENDADO, janela=Janela(inicio_longe, inicio_longe + timedelta(hours=2))
    )
    cedo = amb.cliente.post(
        "/v1/pedidos/ped-1/acoes/registrar_cliente_ausente",
        json={
            "prova": {
                "foto": {"arquivo_id": midia_longe, "tirada_em": AGORA.isoformat()},
                "localizacao": {"latitude": -19.919, "longitude": -43.938},
            }
        },
        headers=cab("t-prof"),
    )
    assert cedo.status_code == 409

    # Cenário válido dentro da janela + GPS no endereço + foto
    amb.semear_pedido(Estado.AGENDADO, janela=Janela(inicio, fim), codigo_inicio="1234")
    midia_ok = _enviar_foto(amb, armazenamento, repo, "t-prof", "checkin", "ped-1")
    ok = amb.cliente.post(
        "/v1/pedidos/ped-1/acoes/registrar_cliente_ausente",
        json={
            "prova": {
                "foto": {"arquivo_id": midia_ok, "tirada_em": AGORA.isoformat()},
                "localizacao": {"latitude": -19.919, "longitude": -43.938},
                "observacao": "Interfone sem resposta após 15 min",
            }
        },
        headers=cab("t-prof"),
    )
    assert ok.status_code == 200, ok.text
    corpo = ok.json()
    assert corpo["estado"] == "agendado"
    assert corpo["cliente_ausente_em"] is not None

    # Notificação ao cliente e mensagem automática no chat
    notas_cli = amb.cliente.get("/v1/notificacoes", headers=cab("t-cliente")).json()
    assert any(n["tipo"] == "agenda.cliente_ausente" for n in notas_cli)
    msgs = amb.cliente.get("/v1/pedidos/ped-1/mensagens", headers=cab("t-cliente")).json()
    assert any("não encontrei o cliente" in m["texto"] for m in msgs)

    # Rotina automática registrar_ausencia não cancela o pedido após tolerância vencer
    salvo = amb.contexto.pedidos.obter("ped-1")
    apos_tolerancia = fim + timedelta(hours=3)
    cfg = ConfigRotinas(tolerancia_comparecimento=timedelta(hours=1))
    assert transicoes_por_prazo(apos_tolerancia, [PedidoMonitorado(salvo)], cfg) == []

    # Máquina de estados também bloqueia diretamente registrar_ausencia do sistema
    try:
        estados.transicionar(
            salvo,
            estados.Acao.REGISTRAR_AUSENCIA,
            Ator(Papel.SISTEMA, "rotina"),
            apos_tolerancia,
            prazos=amb.contexto.config.carregar().prazos_pedido,
        )
        raise AssertionError("REGISTRAR_AUSENCIA deveria estar bloqueada após cliente_ausente")
    except estados.ForaDoPrazo:
        pass


def test_extrato_pdf_traz_o_cpf_do_proprio_profissional_e_os_servicos(amb):
    amb.semear_pedido(Estado.CONCLUIDO)
    amb.semear_dinheiro(cobrado=100_000, taxa=7_500)
    liberar(amb.contexto.ledger.livro, "ped-1", PROFISSIONAL.id, "lib-1", AGORA)
    url = "/v1/profissionais/me/extrato.pdf?mes=2026-10"

    sem = amb.cliente.get(url, headers=cab("t-prof"))
    assert b"CPF" not in sem.content  # sem cadastro de CPF, sem a linha

    amb.contexto.usuarios._cpfs["12345678909"] = PROFISSIONAL.id
    com = amb.cliente.get(url, headers=cab("t-prof"))

    assert com.status_code == 200
    assert b"CPF 123.456.789-09" in com.content
    assert "Serviços do período".encode("cp1252") in com.content
    assert b"R$ 925,00" in com.content  # líquido recebido do serviço
