"""TERMOS-BE-REG no Postgres local (migrations 20261126195000 e 20261126195100)."""

from __future__ import annotations

import threading
import uuid
from datetime import UTC, datetime
from pathlib import Path

from trato.persistencia.lgpd import criar_repositorios_lgpd_postgres
from trato.uploads import ArmazenamentoFake

from .test_ausencia_cliente_postgres import _post
from .test_compensacao_postgres import (  # noqa: F401 - `avisos` é fixture
    PARTE,
    avisos,
    concluido,
    liberar,
    zerar,
)
from .test_disputa_painel_postgres import equipe, ordens  # noqa: F401 - fixture
from .test_medidas_postgres import aplicar, limpar
from .test_pagamento_postgres import (  # noqa: F401 - `pg` e `migrations_novas` são fixtures
    VALOR_ORCAMENTO,
    linhas,
    migrations_novas,
    pg,
)
from .test_provas_medida_postgres import PNG, arquivos  # noqa: F401 - `arquivos` é fixture

URL = "/v1/admin/compensacoes/regressos"
MOTIVO = "Garantia acionada depois do repasse."


def propor(c, pid, quem="med_a", referencia=None, valor=PARTE):
    corpo = {
        "pedido_id": pid,
        "referencia": referencia or str(uuid.uuid4()),
        "valor_centavos": valor,
        "motivo": MOTIVO,
    }
    return _post(c, quem, URL, corpo)


def aprovar(c, proposta, quem="adm_a"):
    return _post(c, quem, f"{URL}/{proposta}/aprovacao", None)


def dividas(c, pid) -> int:
    sql = "select count(*) from public.compensacoes_dividas where pedido_id = %s"
    return linhas(c, sql, (pid,))[0][0]


def test_regresso_propoe_aprova_uma_vez_com_ordem_e_aviso(pg, equipe, avisos):  # noqa: F811
    zerar(pg)
    pid = concluido(pg)
    liberar(pg, pid)
    referencia = str(uuid.uuid4())
    r = propor(pg, pid, referencia=referencia)
    assert r.status_code == 201, r.text
    proposta = r.json()["proposta"]["id"]
    r = propor(pg, pid, referencia=referencia)
    assert r.status_code == 200 and r.json()["resultado"] == "ja_proposta", r.text
    r = propor(pg, pid, referencia=referencia, valor=PARTE + 1)
    assert r.status_code == 409 and r.json()["codigo"] == "conflito", r.text
    assert aprovar(pg, proposta, "med_a").status_code == 403
    assert dividas(pg, pid) == 0
    antes = len(ordens(pg, pid))

    codigos: list[tuple[int, str]] = []
    barreira = threading.Barrier(2)

    def rodar(quem: str) -> None:
        barreira.wait()
        x = aprovar(pg, proposta, quem)
        codigos.append((x.status_code, x.json().get("resultado", x.text)))

    fios = [threading.Thread(target=rodar, args=(q,)) for q in ("adm_a", "adm_b")]
    [f.start() for f in fios]
    [f.join(60) for f in fios]
    assert sorted(codigos) == [(200, "ja_aprovada"), (200, "ok")]
    assert dividas(pg, pid) == 1 and len(ordens(pg, pid)) == antes + 1
    ((avisado,),) = linhas(
        pg, "select avisado_em from public.compensacoes_dividas where pedido_id = %s", (pid,)
    )
    # o aviso de estorno ao cliente sai depois do commit e pode chegar por último
    assert avisado is not None and any(MOTIVO in (a[2] or "") for a in avisos.enviados)
    visto = pg.pagto[0].get(f"{URL}?status=aprovada", headers=pg.token("med_a")).json()
    assert [p["id"] for p in visto["itens"]] == [proposta] and visto["itens"][0]["compensacao_id"]
    r = propor(pg, pid, referencia=referencia)
    assert r.json()["resultado"] == "ja_proposta", r.text
    zerar(pg)


def test_mesma_pessoa_recusa_e_acima_do_devido_nao_deixam_nada(pg, equipe, avisos):  # noqa: F811
    zerar(pg)
    pid = concluido(pg)
    liberar(pg, pid)
    antes = len(ordens(pg, pid))
    propria = propor(pg, pid, "adm_a").json()["proposta"]["id"]
    r = aprovar(pg, propria, "adm_a")
    assert r.status_code == 403 and r.json()["codigo"] == "mesma_pessoa", r.text
    grande = propor(pg, pid, valor=VALOR_ORCAMENTO * 10).json()["proposta"]["id"]
    r = aprovar(pg, grande)
    assert r.status_code == 422 and r.json()["codigo"] == "acima_do_devido", r.text
    assert dividas(pg, pid) == 0 and len(ordens(pg, pid)) == antes
    recusa = {"motivo": "O dano não ficou comprovado."}
    url = f"{URL}/{grande}/recusa"
    assert _post(pg, "adm_a", url, recusa).json()["resultado"] == "ok"
    assert _post(pg, "adm_a", url, recusa).json()["resultado"] == "ja_recusada"
    r = aprovar(pg, grande)
    assert r.status_code == 409 and r.json()["codigo"] == "ja_recusada", r.text
    assert aprovar(pg, str(uuid.uuid4())).status_code == 404
    zerar(pg)


def test_anonimiza_contestacao_decidida_e_repete_pela_auditoria(pg, equipe, arquivos, monkeypatch):  # noqa: F811
    limpar(pg)
    try:
        servico = arquivos()
        mid = aplicar(pg).json()["id"]
        url = f"/v1/me/medidas/{mid}/contestacao"
        corpo = {"nome_arquivo": "a.png", "content_type": "image/png", "tamanho_bytes": 200}
        anexo = _post(pg, "profissional", f"{url}/anexos", corpo).json()["anexo_id"]
        bucket, caminho, _ = servico.armazenamento.urls_emitidas[-1]
        servico.armazenamento.simular_envio(bucket, caminho, PNG)
        envio = {"versao": "Foi um erro do app.", "anexos": [anexo]}
        assert _post(pg, "profissional", url, envio).status_code == 200
        ((cid, guardados),) = linhas(
            pg,
            "select id::text, anexos from public.medida_contestacoes where medida_id = %s",
            (mid,),
        )
        prova = (guardados[0]["bucket"], guardados[0]["caminho"])
        apagar = f"/v1/admin/medidas/contestacoes/{cid}/anonimizacao"
        pedido = {"motivo": "Pedido do titular atendido."}
        r = _post(pg, "adm_a", apagar, pedido)
        assert r.status_code == 409 and r.json()["codigo"] == "nao_decidida", r.text
        decisao = {"resultado": "mantida", "resposta": "Revimos as provas do caso."}
        r = _post(pg, "adm_b", f"/v1/admin/medidas/{mid}/contestacao/decisao", decisao)
        assert r.status_code == 200, r.text
        assert _post(pg, "med_a", apagar, pedido).status_code == 403

        def fora(*_):
            raise RuntimeError("fora do ar")

        with monkeypatch.context() as m:
            m.setattr(servico.armazenamento, "remover", fora)
            r = _post(pg, "adm_a", apagar, pedido)
        assert r.status_code == 200, r.text
        assert r.json() == {"resultado": "ok", "arquivos": 1, "removidos": 0, "pendentes": 1}
        assert prova in servico.armazenamento.arquivos
        r = _post(pg, "adm_a", apagar, pedido)
        assert r.json()["resultado"] == "ja_anonimizada" and r.json()["removidos"] == 1, r.text
        assert prova not in servico.armazenamento.arquivos
        ((versao, anexos),) = linhas(
            pg,
            "select versao_usuario, anexos from public.medida_contestacoes where id = %s",
            (cid,),
        )
        assert (versao, anexos) == ("[anonimizado]", [])
    finally:
        limpar(pg)


def test_exclusao_de_conta_guarda_os_caminhos_e_so_conclui_depois_de_apagar(pg):  # noqa: F811
    migracoes = Path(__file__).resolve().parents[3] / "supabase" / "migrations"
    usuario = str(uuid.uuid4())
    with pg.local.admin() as con:
        if con.execute("select to_regclass('public.dispositivos_push')").fetchone()[0] is None:
            (arquivo,) = migracoes.glob("*_notificacoes_dispositivos_agendador.sql")
            con.execute(arquivo.read_text(encoding="utf-8"))
        con.execute("insert into auth.users (id) values (%s)", (usuario,))
        con.execute("insert into public.usuarios (id, nome) values (%s, 'Sai')", (usuario,))
        con.execute("insert into public.perfis_profissional (usuario_id) values (%s)", (usuario,))
        verificacao = con.execute(
            "insert into public.verificacoes (profissional_id, nivel_solicitado, "
            "consentimento_lgpd_em) values (%s, 'verificado', %s) returning id",
            (usuario, datetime.now(UTC)),
        ).fetchone()[0]
        con.execute(
            "insert into public.verificacao_documentos (verificacao_id, tipo, storage_path) "
            "values (%s, 'documento_frente', %s)",
            (verificacao, f"{usuario}/frente.jpg"),
        )
    fonte = criar_repositorios_lgpd_postgres(pg.banco).fonte
    fonte.anonimizar(usuario)
    esperado = [("verificacao", f"{usuario}/frente.jpg")]
    assert fonte.arquivos_a_remover(usuario) == esperado
    assert fonte.pastas_temporarias(usuario) == [("verificacao", f"contestacao-medida/{usuario}/")]
    assert usuario in fonte.limpezas_pendentes()
    fonte.anonimizar(usuario)  # repetir não perde os caminhos já guardados
    assert fonte.arquivos_a_remover(usuario) == esperado

    from types import SimpleNamespace

    from trato.lgpd.config import obter_config_lgpd
    from trato.lgpd.servico import ServicoLgpd

    armazem = ArmazenamentoFake()
    armazem.gravar("verificacao", f"{usuario}/frente.jpg", b"x", "image/jpeg")
    temporario = f"contestacao-medida/{usuario}/m1/envio/a.png"
    armazem.gravar("verificacao", temporario, b"x", "image/png")
    armazem.gravar("verificacao", "contestacao-medida/m1/prova.png", b"x", "image/png")
    repos = criar_repositorios_lgpd_postgres(pg.banco)
    seg = SimpleNamespace(auditar=lambda *a, **k: None)
    servico = ServicoLgpd(obter_config_lgpd(), repos, seg, armazem)
    servico.processar_vencidas(datetime.now(UTC))
    assert list(armazem.arquivos) == [("verificacao", "contestacao-medida/m1/prova.png")]
    assert usuario not in fonte.limpezas_pendentes()
    assert fonte.arquivos_a_remover(usuario) == []
