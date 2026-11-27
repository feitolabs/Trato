# ruff: noqa: F811
"""TERMOS-BE-69 (6.9): contestação de nota de material (usuário + admin + 4 olhos)."""

from __future__ import annotations

from concurrent.futures import ThreadPoolExecutor
from dataclasses import replace
from datetime import UTC, datetime, timedelta
from types import SimpleNamespace

import pytest
from admin_ambiente import adm, cab, token_de  # noqa: F401
from conftest import CLIENTE, PROFISSIONAL

from trato.api.admin.repositorios import FiltroAuditoria
from trato.api.ausencia_base import comprovantes_possiveis
from trato.api.repositorios_app import NotaMaterial
from trato.api.rotas_upload import urls_fotos_do_pedido
from trato.pedidos.estados import Estado, Pedido
from trato.persistencia.materiais_contestacao import ContestacaoMaterialEmMemoria
from trato.uploads import ArmazenamentoFake
from trato.uploads.servico import Midia, UploadsEmMemoria

AGORA = datetime(2026, 11, 26, 15, 0, tzinfo=UTC)


def semear_pedido_e_nota(adm, total_centavos: int = 12_000) -> tuple[str, str]:
    pedido = Pedido(
        id="ped-mat-1",
        cliente_id=CLIENTE.id,
        profissional_id=PROFISSIONAL.id,
        estado=Estado.EM_ANDAMENTO,
        aberto_em=AGORA,
    )
    adm.contexto.pedidos.salvar(pedido)
    nota = adm.contexto.notas_material.registrar(
        NotaMaterial(
            id="nm-1",
            pedido_id=pedido.id,
            profissional_id=PROFISSIONAL.id,
            foto_storage_path="notas/nm-1.jpg",
            itens=(("Cimento", 2, 6_000, 12_000),),
            total_centavos=total_centavos,
            enviada_em=AGORA,
        )
    )
    return pedido.id, nota.id


def test_cliente_abre_idempotente_terceiro_bloqueado_e_admin_decide_com_4_olhos(adm):
    pid, nid = semear_pedido_e_nota(adm, 12_000)

    # Profissional não pode contestar (403); terceiro recebe 404
    assert (
        adm.cliente.post(
            f"/v1/pedidos/{pid}/materiais/{nid}/contestar",
            json={
                "motivo": "nao_comprovado",
                "descricao": "Profissional tentando contestar a própria nota.",
                "valor_contestado_centavos": 5_000,
            },
            headers=cab("t-prof"),
        ).status_code
        == 403
    )

    # Valor acima da nota -> 422
    assert (
        adm.cliente.post(
            f"/v1/pedidos/{pid}/materiais/{nid}/contestar",
            json={
                "motivo": "nao_comprovado",
                "descricao": "Valor maior que o total da nota de material.",
                "valor_contestado_centavos": 12_001,
            },
            headers=cab("t-cliente"),
        ).status_code
        == 422
    )

    # Cliente abre contestação -> 201; repetir -> 200 idempotente
    r1 = adm.cliente.post(
        f"/v1/pedidos/{pid}/materiais/{nid}/contestar",
        json={
            "motivo": "diferente_do_combinado",
            "descricao": "Foi cobrado um saco extra que não estava combinado.",
            "valor_contestado_centavos": 6_000,
        },
        headers=cab("t-cliente"),
    )
    assert r1.status_code == 201, r1.text
    c1 = r1.json()
    assert c1["status"] == "aberta" and c1["protocolo"].startswith("CNM-")
    assert "analista_id" not in c1 and "aprovada_por" not in c1

    r2 = adm.cliente.post(
        f"/v1/pedidos/{pid}/materiais/{nid}/contestar",
        json={
            "motivo": "diferente_do_combinado",
            "descricao": "Foi cobrado um saco extra que não estava combinado.",
            "valor_contestado_centavos": 6_000,
        },
        headers=cab("t-cliente"),
    )
    assert r2.status_code == 200 and r2.json()["id"] == c1["id"]

    # Conteúdo diferente com uma em aberto: 409 (nunca ignora o novo valor em silêncio)
    r3 = adm.cliente.post(
        f"/v1/pedidos/{pid}/materiais/{nid}/contestar",
        json={
            "motivo": "diferente_do_combinado",
            "descricao": "Foi cobrado um saco extra que não estava combinado.",
            "valor_contestado_centavos": 5_000,
        },
        headers=cab("t-cliente"),
    )
    assert r3.status_code == 409 and c1["protocolo"] in r3.text

    # O profissional não lê as contestações do cliente
    assert (
        adm.cliente.get(
            f"/v1/pedidos/{pid}/materiais/contestacoes", headers=cab("t-prof")
        ).status_code
        == 403
    )

    # Consulta pelo cliente não expõe analista_id/aprovada_por
    lista_u = adm.cliente.get(f"/v1/pedidos/{pid}/materiais/contestacoes", headers=cab("t-cliente"))
    assert lista_u.status_code == 200 and lista_u.json()["total"] == 1
    assert "analista_id" not in lista_u.json()["itens"][0]

    # Admin: mediador analisa e decide parcial (valor acima do contestado = 422)
    h_med = cab(token_de("mediador"))
    h_lider = cab(token_de("lider_suporte"))
    h_adm = cab(token_de("administrador"))

    assert (
        adm.cliente.post(
            f"/v1/admin/materiais/contestacoes/{c1['id']}/analisar", headers=h_med
        ).status_code
        == 200
    )
    assert (
        adm.cliente.post(
            f"/v1/admin/materiais/contestacoes/{c1['id']}/decidir",
            json={
                "status": "parcial",
                "resposta": "Tentativa com valor acima do contestado.",
                "valor_reconhecido_centavos": 7_000,
            },
            headers=h_med,
        ).status_code
        == 422
    )

    # Líder de suporte decide parcial = 4000 centavos
    r_dec = adm.cliente.post(
        f"/v1/admin/materiais/contestacoes/{c1['id']}/decidir",
        json={
            "status": "parcial",
            "resposta": "Comprovado excesso de R$ 40,00 na nota fiscal.",
            "valor_reconhecido_centavos": 4_000,
        },
        headers=h_lider,
    )
    assert r_dec.status_code == 200 and r_dec.json()["valor_reconhecido_centavos"] == 4_000

    # 4 olhos: o MESMO líder que decidiu é bloqueado (403); mediador não tem permissão (403)
    assert (
        adm.cliente.post(
            f"/v1/admin/materiais/contestacoes/{c1['id']}/aprovar-financeiro",
            json={"motivo": "Autoaprovação não permitida pela regra de 4 olhos."},
            headers=h_lider,
        ).status_code
        == 403
    )
    assert (
        adm.cliente.post(
            f"/v1/admin/materiais/contestacoes/{c1['id']}/aprovar-financeiro",
            json={"motivo": "Mediador não tem permissão de aprovação financeira."},
            headers=h_med,
        ).status_code
        == 403
    )

    # Administrador (segunda pessoa) aprova efeito financeiro -> pendente_financeiro (e idempotente)
    r_apr = adm.cliente.post(
        f"/v1/admin/materiais/contestacoes/{c1['id']}/aprovar-financeiro",
        json={"motivo": "Conferida a nota e aprovada a devolução parcial."},
        headers=h_adm,
    )
    assert r_apr.status_code == 200 and r_apr.json()["efeito_financeiro"] == "pendente_financeiro"
    assert (
        adm.cliente.post(
            f"/v1/admin/materiais/contestacoes/{c1['id']}/aprovar-financeiro",
            json={"motivo": "Repetição idempotente da aprovação."},
            headers=h_adm,
        ).status_code
        == 200
    )

    eventos, _ = adm.admin.auditoria.listar(FiltroAuditoria(), 50, 0)
    acoes = [e.acao for e in eventos]
    assert {
        "material.contestacao_em_analise",
        "material.contestacao_decidida",
        "material.contestacao_financeiro_aprovado",
    } <= set(acoes)


def test_improcedente_bloqueia_aprovacao_financeira(adm):
    pid, nid = semear_pedido_e_nota(adm, 8_000)
    c = adm.cliente.post(
        f"/v1/pedidos/{pid}/materiais/{nid}/contestar",
        json={
            "motivo": "nao_comprovado",
            "descricao": "Não reconheço o material cobrado na nota.",
            "valor_contestado_centavos": 8_000,
        },
        headers=cab("t-cliente"),
    ).json()

    r_dec = adm.cliente.post(
        f"/v1/admin/materiais/contestacoes/{c['id']}/decidir",
        json={"status": "improcedente", "resposta": "Nota fiscal legítima e compatível."},
        headers=cab(token_de("mediador")),
    )
    assert r_dec.status_code == 200 and r_dec.json()["valor_reconhecido_centavos"] == 0

    assert (
        adm.cliente.post(
            f"/v1/admin/materiais/contestacoes/{c['id']}/aprovar-financeiro",
            json={"motivo": "Tentativa em contestação improcedente."},
            headers=cab(token_de("administrador")),
        ).status_code
        == 409
    )


def _contestar(adm, pid, nid, valor, **extra):
    return adm.cliente.post(
        f"/v1/pedidos/{pid}/materiais/{nid}/contestar",
        json={
            "motivo": "nao_comprovado",
            "descricao": "Não reconheço este material.",
            "valor_contestado_centavos": valor,
            **extra,
        },
        headers=cab("t-cliente"),
    )


def test_item_da_nota_tem_id_teto_proprio_e_nao_se_sobrepoe_a_nota_inteira(adm):
    pid, nid = semear_pedido_e_nota(adm, 12_000)
    item = adm.contexto.notas_material.do_pedido(pid)[0].item_ids[0]
    notas = adm.cliente.get(f"/v1/contratos/{pid}/notas-material", headers=cab("t-cliente"))
    if notas.status_code == 200:
        assert notas.json()[0]["itens"][0]["id"] == item

    assert _contestar(adm, pid, nid, 100, item_id="nao-existe").status_code == 404
    assert _contestar(adm, pid, nid, 12_001, item_id=item).status_code == 422
    r = _contestar(adm, pid, nid, 3_000, item_id=item)
    assert r.status_code == 201 and r.json()["item_id"] == item
    assert _contestar(adm, pid, nid, 1_000).status_code == 409  # nota inteira sobrepõe o item
    assert _contestar(adm, pid, "nm-outra", 1_000).status_code == 404


def test_anexo_que_o_cliente_nao_enviou_e_recusado(adm):
    pid, nid = semear_pedido_e_nota(adm)
    r = _contestar(adm, pid, nid, 1_000, anexos=["https://exemplo.test/qualquer.jpg"])
    assert r.status_code == 422 and r.json()["codigo"] == "anexo_invalido"
    assert adm.contexto.materiais_contestacao.listar_do_pedido(pid) == []


def test_prazo_de_resposta_vem_da_configuracao(adm):
    pid, nid = semear_pedido_e_nota(adm)
    base = adm.contexto.config.carregar()
    adm.contexto.config = SimpleNamespace(carregar=lambda: replace(base, sac_resposta_dias_uteis=1))
    r = _contestar(adm, pid, nid, 1_000)
    assert r.status_code == 201, r.text
    aberta = datetime.fromisoformat(r.json()["aberta_em"])
    ate = datetime.fromisoformat(r.json()["responder_ate"])
    assert timedelta(days=1) <= ate - aberta <= timedelta(days=4)  # 1 dia útil


def test_decisao_exige_valor_coerente_repete_sem_duplicar_e_nao_muda_depois(adm):
    pid, nid = semear_pedido_e_nota(adm)
    cid = _contestar(adm, pid, nid, 6_000).json()["id"]
    url = f"/v1/admin/materiais/contestacoes/{cid}/decidir"
    h = cab(token_de("mediador"))
    texto = "Conferida a nota enviada."
    for status, valor in (
        ("procedente", 5_000),
        ("parcial", 6_000),
        ("parcial", 0),
        ("parcial", None),
        ("improcedente", 1),
    ):
        corpo = {"status": status, "resposta": texto, "valor_reconhecido_centavos": valor}
        assert adm.cliente.post(url, json=corpo, headers=h).status_code == 422, (status, valor)
    for quebrado in (10.5, "100", -1):
        corpo = {"status": "parcial", "resposta": texto, "valor_reconhecido_centavos": quebrado}
        assert adm.cliente.post(url, json=corpo, headers=h).status_code == 422
    corpo = {"status": "procedente", "resposta": texto}
    primeira = adm.cliente.post(url, json=corpo, headers=h)
    assert primeira.status_code == 200 and primeira.json()["valor_reconhecido_centavos"] == 6_000
    assert primeira.json()["efeito_financeiro"] == "nenhum"  # decidir não move dinheiro
    assert adm.cliente.post(url, json=corpo, headers=h).status_code == 200
    outra = {"status": "improcedente", "resposta": texto}
    assert adm.cliente.post(url, json=outra, headers=h).status_code == 409
    eventos, _ = adm.admin.auditoria.listar(FiltroAuditoria(), 50, 0)
    assert [e.acao for e in eventos].count("material.contestacao_decidida") == 1


def test_duplo_toque_abre_uma_so_na_memoria():
    repo = ContestacaoMaterialEmMemoria()

    def abrir(_):
        return repo.abrir(
            pedido_id="p",
            nota_id="n",
            nota_total_centavos=1_000,
            item_id=None,
            item_total_centavos=None,
            cliente_id="c",
            motivo="nao_comprovado",
            descricao="Não foi entregue.",
            anexos=(),
            valor_contestado_centavos=1_000,
            aberta_em=AGORA,
            responder_ate=AGORA + timedelta(days=1),
        )

    with ThreadPoolExecutor(max_workers=8) as pool:
        saidas = list(pool.map(abrir, range(8)))
    assert sorted(s[2] for s in saidas) == ["ja_aberta"] * 7 + ["ok"]
    assert len(repo.listar_do_pedido("p")) == 1


@pytest.mark.parametrize(
    ("metodo", "caminho", "corpo", "token"),
    [
        ("GET", "/v1/pedidos/ped-1/materiais/contestacoes", None, "t-cliente"),
        ("GET", "/v1/admin/materiais/contestacoes", None, token_de("mediador")),
        ("POST", "/v1/admin/materiais/contestacoes/cnm-1/analisar", None, token_de("mediador")),
    ],
)
def test_tabela_ausente_responde_503_limpo(adm, metodo, caminho, corpo, token):
    adm.contexto.materiais_contestacao = ContestacaoMaterialEmMemoria(disponivel=False)
    r = adm.cliente.request(metodo, caminho, json=corpo, headers=cab(token))
    assert r.status_code == 503


# --- anexos no painel -------------------------------------------------------------------

_MOTIVO = {"motivo": "Conferir a prova para decidir."}


def _midia(mid, pid, quem, caminho, sha="a" * 64):
    return Midia(
        mid, pid, quem, "nota_material", "pedido-midias", caminho, "image/jpeg", 10, sha, AGORA
    )


def _com_arquivos(adm, *, sha_nota="b" * 64):
    pid, nid = semear_pedido_e_nota(adm)
    repo = UploadsEmMemoria()
    repo.salvar_midia(_midia("foto-nota", pid, PROFISSIONAL.id, "notas/nm-1.jpg", sha_nota))
    repo.salvar_midia(_midia("prova-1", pid, CLIENTE.id, "provas/p1.jpg"))
    repo.salvar_midia(_midia("prova-solta", pid, CLIENTE.id, "provas/p2.jpg"))
    adm.cliente.app.state.servico_uploads = SimpleNamespace(
        repo=repo, armazenamento=ArmazenamentoFake()
    )
    r = _contestar(adm, pid, nid, 1_000, anexos=["prova-1"])
    assert r.status_code == 201, r.text
    return r.json()["id"], pid, repo


def _abrir(adm, cid, corpo=None, papel="mediador"):
    return adm.cliente.post(
        f"/v1/admin/materiais/contestacoes/{cid}/anexos",
        json=corpo or _MOTIVO,
        headers=cab(token_de(papel)),
    )


def _vistos(adm):
    eventos, _ = adm.admin.auditoria.listar(FiltroAuditoria(), 50, 0)
    return [e for e in eventos if e.acao == "dado_pessoal.material_contestacao_anexos_vistos"]


def test_painel_abre_nota_e_provas_com_link_curto_e_auditoria(adm):
    cid, _, _ = _com_arquivos(adm)
    r = _abrir(adm, cid)
    assert r.status_code == 200, r.text
    itens = r.json()
    assert [(i["tipo"], i["arquivo_id"], i["enviado_por"]) for i in itens] == [
        ("nota_material", "foto-nota", "profissional"),
        ("contestacao", "prova-1", "cliente"),
    ]
    assert all(i["url"] and i["expira_em_segundos"] == 300 for i in itens)
    assert all("storage_path" not in i and "bucket" not in i for i in itens)
    (evento,) = _vistos(adm)
    assert evento.depois["arquivos"] == ["foto-nota", "prova-1"]
    assert "nm-1.jpg" not in str(evento.depois) and CLIENTE.id not in str(evento.depois)

    um = _abrir(adm, cid, {**_MOTIVO, "arquivo_id": "prova-1"})
    assert um.status_code == 200 and [i["arquivo_id"] for i in um.json()] == ["prova-1"]


def test_arquivo_de_fora_da_contestacao_e_404_sem_auditar_link(adm):
    cid, _, _ = _com_arquivos(adm)
    for outro in ("prova-solta", "nao-existe"):
        assert _abrir(adm, cid, {**_MOTIVO, "arquivo_id": outro}).status_code == 404
    assert _abrir(adm, "cnm-999").status_code == 404
    assert _vistos(adm) == []


def test_foto_sem_envio_conferido_ou_midia_de_outro_dono_nao_ganha_link(adm):
    cid, pid, repo = _com_arquivos(adm, sha_nota="")
    repo.salvar_midia(_midia("prova-1", pid, "outra-pessoa", "provas/alheia.jpg"))
    itens = _abrir(adm, cid).json()
    assert [i["url"] for i in itens] == [None, None]
    assert itens[0]["arquivo_id"] is None
    repo.salvar_midia(_midia("prova-1", "outro-pedido", CLIENTE.id, "provas/outro.jpg"))
    assert _abrir(adm, cid).json()[1]["url"] is None


def test_anexos_exigem_motivo_permissao_e_respondem_503_limpo(adm):
    cid, _, _ = _com_arquivos(adm)
    assert _abrir(adm, cid, {"motivo": "curto"}).status_code == 422
    assert _abrir(adm, cid, papel="atendente_n1").status_code == 403

    def quebrado(*_):
        raise RuntimeError("storage fora: pedido-midias/segredo")

    adm.cliente.app.state.servico_uploads.armazenamento.url_leitura = quebrado
    r = _abrir(adm, cid)
    assert r.status_code == 503 and "segredo" not in r.text
    adm.cliente.app.state.servico_uploads = None
    assert _abrir(adm, cid).status_code == 503
    adm.contexto.materiais_contestacao = ContestacaoMaterialEmMemoria(disponivel=False)
    assert _abrir(adm, cid).status_code == 503
    assert _vistos(adm) == []


def test_foto_enviada_com_destino_disputa_nao_vira_prova_de_disputa_nem_comprovante(adm):
    """O app envia a prova da 6.9 com destino `disputa`: só o vínculo explícito a leva à disputa."""
    pid, nid = semear_pedido_e_nota(adm)
    repo = UploadsEmMemoria()
    repo.salvar_midia(replace(_midia("prova-d", pid, CLIENTE.id, "p/d.jpg"), finalidade="disputa"))
    servico = SimpleNamespace(repo=repo, armazenamento=ArmazenamentoFake())
    adm.cliente.app.state.servico_uploads = servico
    antes = list(getattr(adm.contexto.disputas, "evidencias", lambda _: [])(pid))
    assert _contestar(adm, pid, nid, 1_000, anexos=["prova-d"]).status_code == 201

    assert list(getattr(adm.contexto.disputas, "evidencias", lambda _: [])(pid)) == antes
    assert adm.contexto.disputas.obter(pid) is None  # não abre disputa nem muda o pedido
    assert adm.contexto.pedidos.obter(pid).estado is Estado.EM_ANDAMENTO
    pedido = adm.contexto.pedidos.obter(pid)
    assert comprovantes_possiveis(servico, pedido) == []  # arquivo do cliente nunca é comprovante
    fotos = urls_fotos_do_pedido(SimpleNamespace(app=adm.cliente.app), pid)
    assert fotos == []
