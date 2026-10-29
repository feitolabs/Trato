"""Fluxo completo contra o Postgres local: pedido -> orçamento -> aceite/contrato -> agendamento
e check-in/out -> mensagem -> notificação -> auditoria (e a cadeia de hash)."""

from __future__ import annotations

from datetime import UTC, datetime, timedelta
from decimal import Decimal

import pytest

from trato.api.repositorios import Contrato
from trato.pedidos import estados
from trato.pedidos.estados import Ator, Papel, ProvaPagamento
from trato.persistencia.erros import ConfigNaoPublicada, Duplicado, RegraDoBanco
from trato.persistencia.orcamentos import EtapaProposta, ItemOrcamento

pytestmark = pytest.mark.integracao


def agora() -> datetime:
    return datetime.now(UTC)


def corpo_pedido(c, **extra):
    return {
        "categoria_id": c.categoria_id,
        "cidade_id": c.cidade_id,
        "titulo": "Pintar a sala",
        "descricao": "Duas demãos, paredes brancas.",
        "bairro": "Centro",
        "respostas": [{"pergunta_id": c.pergunta_id, "resposta": 3}],
        "endereco": {"logradouro": "Rua A", "numero": "10", "lat": -19.9, "lng": -43.9},
        **extra,
    }


def abrir_pedido(c) -> str:
    r = c.cliente.post("/v1/pedidos", json=corpo_pedido(c), headers=c.token("cliente"))
    assert r.status_code == 201, r.text
    return r.json()["id"]


def enviar_orcamento(c, pedido_id: str, quem="profissional") -> str:
    return c.contexto.orcamentos.enviar(
        pedido_id=pedido_id,
        profissional_id=c.ids[quem],
        itens=[
            ItemOrcamento("horas", "Mão de obra", Decimal("8"), 10_000),
            ItemOrcamento("material", "Tinta", Decimal("2.5"), 4_000),
        ],
        etapas=[EtapaProposta("Preparar paredes", 40_000), EtapaProposta("Pintar", 50_000)],
        agora=agora(),
        prazo_execucao_dias=5,
        garantia_dias=90,
    )


def acao(c, quem, pedido_id, nome, prova=None):
    corpo = {"prova": prova} if prova is not None else None
    return c.cliente.post(
        f"/v1/pedidos/{pedido_id}/acoes/{nome}", json=corpo, headers=c.token(quem)
    )


def foto(nome="foto-1"):
    return {
        "arquivo_id": f"{nome}-{datetime.now(UTC).timestamp()}",
        "tirada_em": agora().isoformat(),
    }


def test_fluxo_completo(cenario):
    c = cenario
    # 1) o cliente abre o pedido (respostas guiadas e endereço vão junto)
    pedido_id = abrir_pedido(c)
    with c.local.admin() as con:
        assert (
            con.execute(
                "select count(*) from public.pedido_respostas where pedido_id = %s", (pedido_id,)
            ).fetchone()[0]
            == 1
        )
        assert (
            con.execute(
                "select pergunta_texto from public.pedido_respostas where pedido_id = %s",
                (pedido_id,),
            ).fetchone()[0]
            == "Quantos cômodos?"
        )
        assert (
            con.execute(
                "select liberado_em from public.pedidos_endereco where pedido_id = %s", (pedido_id,)
            ).fetchone()[0]
            is None
        )  # endereço só é liberado depois da contratação

    # 2) o profissional envia o orçamento (total conferido pelo banco no COMMIT)
    orcamento_id = enviar_orcamento(c, pedido_id)
    orc = c.contexto.orcamentos.obter(orcamento_id)
    assert orc.valor_centavos == 8 * 10_000 + 10_000  # 80.000 + 2,5 x 4.000
    assert orc.categoria_id == c.categoria_id

    # 3) o cliente aceita: nasce o contrato, com as regras do momento congeladas
    r = acao(c, "cliente", pedido_id, "aceitar_orcamento", {"orcamento_id": orcamento_id})
    assert r.status_code == 200, r.text
    assert r.json()["estado"] == "orcamento_aceito"
    with c.local.admin() as con:
        ctr = con.execute(
            "select valor_total_centavos, taxa_bps_aplicada, taxa_trato_centavos, "
            "liquido_profissional_centavos, adiantamento_centavos, regras_aplicadas "
            "from public.contratos where pedido_id = %s",
            (pedido_id,),
        ).fetchone()
        assert ctr[0:5] == (90_000, 750, 6_750, 83_250, 27_000)
        assert ctr[5]["adiantamento_bps"] == 3000
        # as etapas propostas foram vinculadas ao contrato
        assert (
            con.execute(
                "select count(*) from public.etapas e "
                "join public.contratos c on c.id = e.contrato_id "
                "where c.pedido_id = %s",
                (pedido_id,),
            ).fetchone()[0]
            == 2
        )
    # o app não paga: cliente e profissional não confirmam pagamento
    assert acao(c, "cliente", pedido_id, "confirmar_pagamento").status_code == 403
    assert acao(c, "profissional", pedido_id, "confirmar_pagamento").status_code == 403

    # 4) o webhook assinado (simulado: ator sistema) confirma o pagamento
    pedido = c.contexto.pedidos.obter(pedido_id)
    t = estados.transicionar(
        pedido,
        estados.Acao.CONFIRMAR_PAGAMENTO,
        Ator(Papel.SISTEMA, "sistema"),
        agora(),
        ProvaPagamento("pi_teste_123"),
    )
    c.contexto.pedidos.salvar(t.pedido, t.evento)
    assert c.contexto.pedidos.obter(pedido_id).referencia_pagamento == "pi_teste_123"

    # 5) o profissional confirma a agenda; o cliente vê o código, o profissional não
    inicio = agora() + timedelta(days=2)
    janela = {"inicio": inicio.isoformat(), "fim": (inicio + timedelta(hours=3)).isoformat()}
    r = acao(c, "profissional", pedido_id, "confirmar_agenda", {"janela": janela})
    assert r.status_code == 200, r.text
    assert r.json()["estado"] == "agendado" and r.json()["codigo_inicio"] is None
    codigo = c.cliente.get(f"/v1/pedidos/{pedido_id}", headers=c.token("cliente")).json()[
        "codigo_inicio"
    ]
    assert len(codigo) == 4
    with c.local.admin() as con:  # o banco guarda só o hash
        h = con.execute(
            "select a.codigo_inicio_hash from public.agendamentos a "
            "join public.contratos ct on ct.id = a.contrato_id where ct.pedido_id = %s",
            (pedido_id,),
        ).fetchone()[0]
        assert len(h) == 64 and codigo not in h

    # 6) check-in com o código errado falha; com o certo funciona
    entrada = {
        "foto": foto(),
        "localizacao": {"latitude": -19.9, "longitude": -43.9},
        "codigo_inicio": "0000" if codigo != "0000" else "1111",
    }
    assert acao(c, "profissional", pedido_id, "fazer_check_in", entrada).status_code == 422
    entrada["codigo_inicio"] = codigo
    r = acao(c, "profissional", pedido_id, "fazer_check_in", entrada)
    assert r.status_code == 200, r.text
    assert r.json()["estado"] == "em_andamento"
    # a presença usa a hora do servidor (gatilho) e fica ligada ao agendamento
    presencas = c.contexto.extras["execucao"].presencas_do_pedido(pedido_id)
    assert [p.tipo for p in presencas] == ["check_in"] and presencas[0].codigo_validado
    assert abs(presencas[0].registrada_em - agora()) < timedelta(minutes=2)

    # check-out com o código de conclusão que o cliente vê
    codigo_saida = c.cliente.get(f"/v1/pedidos/{pedido_id}", headers=c.token("cliente")).json()[
        "codigo_conclusao"
    ]
    r = acao(
        c, "profissional", pedido_id, "fazer_check_out",
        {"foto_final": foto("fim"), "codigo_conclusao": codigo_saida},
    )  # fmt: skip
    assert r.status_code == 200 and r.json()["estado"] == "em_confirmacao"
    assert acao(c, "cliente", pedido_id, "confirmar_conclusao").json()["estado"] == "concluido"
    assert [p.tipo for p in c.contexto.extras["execucao"].presencas_do_pedido(pedido_id)] == [
        "check_in",
        "check_out",
    ]
    final = c.contexto.pedidos.obter(pedido_id)
    assert final.concluido_em is not None and final.check_out_em is not None
    # o código de início nunca foi gravado em claro no histórico
    with c.local.admin() as con:
        provas = con.execute(
            "select prova::text from public.pedido_historico where pedido_id = %s", (pedido_id,)
        ).fetchall()
        assert all(codigo not in p[0] and codigo_saida not in p[0] for p in provas)
    historico = c.cliente.get(f"/v1/pedidos/{pedido_id}/eventos", headers=c.token("cliente")).json()
    assert [e["acao"] for e in historico] == [
        "aceitar_orcamento", "confirmar_pagamento", "confirmar_agenda",
        "fazer_check_in", "fazer_check_out", "confirmar_conclusao",
    ]  # fmt: skip
    assert historico[1]["ator_papel"] == "sistema"

    # 7) conversa e mensagem (contato mascarado só antes da contratação)
    conversas = c.contexto.extras["conversas"]
    conversa = conversas.abrir(pedido_id, c.ids["profissional"])
    assert conversas.abrir(pedido_id, c.ids["profissional"]) == conversa
    conversas.enviar(conversa, c.ids["cliente"], "Oi! Pode chegar às 9h?")
    conversas.enviar(conversa, c.ids["profissional"], "Posso sim. Meu zap 31 99999-8888")
    textos = [m.texto for m in conversas.listar(conversa)]
    assert textos[0] == "Oi! Pode chegar às 9h?"
    assert "99999" in textos[1]  # já contratado: não mascara
    with pytest.raises(Exception, match="partes"):  # quem não é parte não escreve
        conversas.enviar(conversa, c.ids["cliente2"], "intruso")

    # 8) notificação
    notificacoes = c.contexto.extras["notificacoes"]
    nid = notificacoes.criar(
        c.ids["cliente"], "pedido.concluido", "Serviço concluído", dados={"pedido_id": pedido_id}
    )
    assert [n.id for n in notificacoes.listar(c.ids["cliente"], apenas_nao_lidas=True)] == [nid]
    notificacoes.marcar_lida(nid, c.ids["cliente"], agora())
    assert notificacoes.listar(c.ids["cliente"], apenas_nao_lidas=True) == ()

    # 9) auditoria: uma linha por transição, na ordem, e a cadeia continua íntegra
    trilha = c.contexto.extras["auditoria"].da_entidade("pedido", pedido_id)
    assert [t.acao for t in trilha] == [
        "pedido.aberto", "pedido.aceitar_orcamento", "pedido.confirmar_pagamento",
        "pedido.confirmar_agenda", "pedido.fazer_check_in", "pedido.fazer_check_out",
        "pedido.confirmar_conclusao",
    ]  # fmt: skip
    assert trilha[2].ator_tipo == "sistema" and trilha[2].ator_id is None
    contrato_trilha = c.contexto.extras["auditoria"].da_entidade(
        "contrato", _contrato_id(c, pedido_id)
    )
    assert [t.acao for t in contrato_trilha] == ["contrato.aceito"]
    assert c.contexto.extras["auditoria"].verificar_cadeia() is None


def _contrato_id(c, pedido_id: str) -> str:
    with c.local.admin() as con:
        return str(
            con.execute(
                "select id from public.contratos where pedido_id = %s", (pedido_id,)
            ).fetchone()[0]
        )


def test_autenticacao_jwt_do_supabase(cenario):
    import jwt as pyjwt

    c = cenario
    ok = c.token("cliente")
    assert c.cliente.get("/v1/pedidos", headers=ok).status_code == 200

    def com(carga, segredo=None, algoritmo="HS256"):
        base = {"aud": "authenticated", "exp": datetime.now(UTC) + timedelta(hours=1)}
        token = pyjwt.encode({**base, **carga}, segredo or c.segredo_jwt, algoritmo)
        return {"Authorization": f"Bearer {token}"}

    quem = c.ids["cliente"]
    rota = "/v1/pedidos"
    assert c.cliente.get(rota).status_code == 401  # sem token
    assert c.cliente.get(rota, headers=com({"sub": quem}, segredo="x" * 40)).status_code == 401
    assert c.cliente.get(rota, headers=com({"sub": quem, "exp": 1})).status_code == 401  # vencido
    assert c.cliente.get(rota, headers=com({"sub": quem, "aud": "outro"})).status_code == 401
    assert c.cliente.get(rota, headers=com({"sub": c.categoria_id})).status_code == 401  # sem conta
    assert c.cliente.get(rota, headers=com({"sub": "nao-e-uuid"})).status_code == 401
    sem_exp = pyjwt.encode({"sub": quem, "aud": "authenticated"}, c.segredo_jwt, "HS256")
    assert c.cliente.get(rota, headers={"Authorization": f"Bearer {sem_exp}"}).status_code == 401
    sem_assinatura = pyjwt.encode({"sub": quem, "aud": "authenticated"}, None, "none")
    assert (
        c.cliente.get(rota, headers={"Authorization": f"Bearer {sem_assinatura}"}).status_code
        == 401
    )
    # o papel vem do banco, não do token: dizer "role: equipe" no token não promove ninguém
    forjado = com({"sub": quem, "role": "equipe", "app_metadata": {"papel": "equipe"}})
    assert c.cliente.post("/v1/pedidos", json=corpo_pedido(c), headers=forjado).status_code == 201
    # conta bloqueada não entra, mesmo com token válido
    with c.local.admin() as con:
        con.execute("update public.usuarios set status = 'bloqueado' where id = %s", (quem,))
    try:
        assert c.cliente.get(rota, headers=ok).status_code == 401
    finally:
        with c.local.admin() as con:
            con.execute("update public.usuarios set status = 'ativo' where id = %s", (quem,))
    # equipe vê o pedido de qualquer um; profissional sem contrato não
    pedido_id = abrir_pedido(c)
    assert c.cliente.get(f"/v1/pedidos/{pedido_id}", headers=c.token("equipe1")).status_code == 200
    assert (
        c.cliente.get(f"/v1/pedidos/{pedido_id}", headers=c.token("profissional")).status_code
        == 404
    )


def test_listagem_por_papel_e_privacidade(cenario):
    c = cenario
    pedido_id = abrir_pedido(c)
    meus = c.cliente.get("/v1/pedidos", headers=c.token("cliente")).json()
    assert pedido_id in [p["id"] for p in meus]
    # outro cliente não vê (404), nem sabe que existe
    assert c.cliente.get(f"/v1/pedidos/{pedido_id}", headers=c.token("cliente2")).status_code == 404
    # id que não é uuid também é 404, não erro 500
    assert c.cliente.get("/v1/pedidos/abc", headers=c.token("cliente")).status_code == 404
    # profissional não abre pedido
    assert (
        c.cliente.post("/v1/pedidos", json=corpo_pedido(c), headers=c.token("profissional"))
    ).status_code == 403


def test_pedido_sem_dados_e_pergunta_invalida_sao_recusados(cenario):
    c = cenario
    r = c.cliente.post("/v1/pedidos", headers=c.token("cliente"))
    assert r.status_code == 422
    r = c.cliente.post(
        "/v1/pedidos",
        json=corpo_pedido(c, respostas=[{"pergunta_id": c.categoria_id, "resposta": 1}]),
        headers=c.token("cliente"),
    )
    assert r.status_code == 422
    # nada ficou pela metade: transação desfeita
    with c.local.admin() as con:
        assert (
            con.execute(
                "select count(*) from public.pedidos where titulo = 'Pintar a sala' "
                "and status = 'aberto' "
                "and id not in (select pedido_id from public.pedido_respostas)"
            ).fetchone()[0]
            == 0
        )


def test_orcamento_e_contrato_respeitam_os_gatilhos(cenario):
    c = cenario
    pedido_id = abrir_pedido(c)
    # o cliente não orça o próprio pedido
    with pytest.raises(RegraDoBanco):
        c.contexto.orcamentos.enviar(
            pedido_id=pedido_id, profissional_id=c.ids["cliente"],
            itens=[ItemOrcamento("outro", "x", Decimal("1"), 100)], agora=agora(),
        )  # fmt: skip
    # reenvio do mesmo profissional substitui a versão anterior
    primeiro = enviar_orcamento(c, pedido_id)
    segundo = enviar_orcamento(c, pedido_id)
    with c.local.admin() as con:
        status = dict(con.execute(
            "select id::text, status from public.orcamentos where pedido_id = %s", (pedido_id,)
        ).fetchall())  # fmt: skip
    assert status[primeiro] == "substituido" and status[segundo] == "enviado"
    # orçamento substituído não pode ser aceito
    r = acao(c, "cliente", pedido_id, "aceitar_orcamento", {"orcamento_id": primeiro})
    assert r.status_code == 409
    assert c.contexto.pedidos.obter(pedido_id).estado is estados.Estado.ABERTO

    r = acao(c, "cliente", pedido_id, "aceitar_orcamento", {"orcamento_id": segundo})
    assert r.status_code == 200
    # repetir a gravação do contrato com o mesmo orçamento não duplica; outro orçamento é recusado
    mesmo = Contrato(pedido_id, segundo, c.ids["profissional"], 90_000)
    c.contexto.contratos.salvar(mesmo)
    with pytest.raises(Duplicado):
        c.contexto.contratos.salvar(Contrato(pedido_id, primeiro, c.ids["profissional"], 1))
    # contrato congelado: o banco recusa mudar o valor, mesmo para o dono das tabelas
    with c.local.admin() as con, pytest.raises(Exception, match="não pode ser alterada"):
        con.execute(
            "update public.contratos set valor_total_centavos = 1 where pedido_id = %s",
            (pedido_id,),
        )


def test_execucao_etapas_aditivo_e_nota_de_material(cenario):
    c = cenario
    exe = c.contexto.extras["execucao"]
    pedido_id = abrir_pedido(c)
    orc = enviar_orcamento(c, pedido_id)
    assert (
        acao(c, "cliente", pedido_id, "aceitar_orcamento", {"orcamento_id": orc}).status_code == 200
    )

    etapas = exe.etapas_do_pedido(pedido_id)
    assert [(e.ordem, e.valor_centavos, e.status) for e in etapas] == [
        (0, 40_000, "prevista"),
        (1, 50_000, "prevista"),
    ]
    exe.mudar_etapa(etapas[0].id, "em_execucao", agora())
    assert exe.etapas_do_pedido(pedido_id)[0].status == "em_execucao"

    # aditivo: só o profissional propõe, só o cliente decide, e decidido não muda mais
    aditivo = exe.propor_aditivo(pedido_id, c.ids["profissional"], "Mais uma demão", 5_000)
    with pytest.raises(RegraDoBanco):
        exe.decidir_aditivo(aditivo, c.ids["cliente2"], True, agora())
    exe.decidir_aditivo(aditivo, c.ids["cliente"], True, agora())
    assert exe.aditivos_do_pedido(pedido_id)[0].status == "aprovado"
    with pytest.raises(RegraDoBanco):
        exe.decidir_aditivo(aditivo, c.ids["cliente"], False, agora())

    # nota de material: itens e total fecham no COMMIT; total errado é recusado pelo banco
    from trato.persistencia.execucao import ItemNota

    nota = exe.registrar_nota_material(
        pedido_id, c.ids["profissional"], f"notas/{pedido_id}.jpg",
        [ItemNota("Rolo", Decimal("2"), 1_550), ItemNota("Fita", Decimal("1"), 990)],
    )  # fmt: skip
    assert nota
    with c.local.admin() as con:
        assert (
            con.execute(
                "select total_centavos from public.notas_material where id = %s", (nota,)
            ).fetchone()[0]
            == 4_090
        )


def test_mensagem_antes_da_contratacao_mascara_contato_e_guarda_original(cenario):
    c = cenario
    pedido_id = abrir_pedido(c)
    conversas = c.contexto.extras["conversas"]
    conversa = conversas.abrir(pedido_id, c.ids["profissional2"])
    mid = conversas.enviar(conversa, c.ids["profissional2"], "Me liga: (31) 98888-7777 ou a@b.com")
    visto = conversas.listar(conversa)[-1]
    assert "98888" not in visto.texto and "a@b.com" not in visto.texto and visto.mascarada
    with c.local.admin() as con:  # o original é evidência e fica no banco
        assert (
            "98888"
            in con.execute("select corpo from public.mensagens where id = %s", (mid,)).fetchone()[0]
        )
        # mensagem não se edita nem se apaga, nem pelo dono
        with pytest.raises(Exception, match="não é editável"):
            con.execute("update public.mensagens set corpo = 'x' where id = %s", (mid,))
    conversas.marcar_lida(mid, agora())
    with pytest.raises(RegraDoBanco):  # só uma vez
        conversas.marcar_lida(mid, agora())


def test_cadeia_de_auditoria_detecta_adulteracao(cenario):
    c = cenario
    auditoria = c.contexto.extras["auditoria"]
    abrir_pedido(c)
    assert auditoria.verificar_cadeia() is None
    # adultera uma linha DENTRO de uma transação que é desfeita (a cadeia real não é tocada)
    with c.local.admin() as con:
        con.autocommit = False
        con.execute("alter table public.auditoria disable trigger auditoria_imutavel")
        alvo = con.execute("select id from public.auditoria order by id desc limit 1").fetchone()[0]
        con.execute("update public.auditoria set acao = 'pedido.adulterado' where id = %s", (alvo,))
        falha = con.execute("select public.verificar_cadeia_auditoria()").fetchone()[0]
        con.rollback()
    assert falha == alvo
    assert auditoria.verificar_cadeia() is None


def test_motivo_obrigatorio_em_auditoria_financeira(cenario):
    c = cenario
    with pytest.raises(RegraDoBanco):
        c.contexto.extras["auditoria"].registrar(
            ator_id=None, ator_tipo="sistema", acao="pagamento.estornado"
        )
    n = c.contexto.extras["auditoria"].registrar(
        ator_id=None, ator_tipo="sistema", acao="pagamento.estornado", motivo="teste"
    )
    assert n > 0


def test_backend_so_tem_os_privilegios_do_service_role(cenario):
    c = cenario
    # auditoria: o backend lê, mas não escreve direto (só por registrar_auditoria)
    with pytest.raises(Exception, match="permission|permiss"), c.banco.transacao() as con:
        con.execute(
            "insert into public.auditoria (id, ocorrida_em, ator_tipo, acao, hash) "
            "values (1, now(), 'sistema', 'x', 'x')"
        )
    # mídia é imutável: nem o service_role atualiza
    with pytest.raises(Exception, match="permission|permiss"), c.banco.transacao() as con:
        con.execute("update public.midias set mime = 'x'")


def test_config_sem_faixa_nao_aceita_orcamento(cenario):
    """Sem faixa de taxa para o valor, o aceite responde 503 e o pedido continua aberto."""
    c = cenario
    pedido_id = abrir_pedido(c)
    orc = enviar_orcamento(c, pedido_id)
    with c.local.admin() as con:
        con.execute("alter table public.config_faixas_taxa disable trigger all")
        faixas = con.execute(
            "select id, de_centavos, ate_centavos, taxa_bps, versao_id from "
            "public.config_faixas_taxa"
        ).fetchall()
        con.execute("delete from public.config_faixas_taxa")
    try:
        r = acao(c, "cliente", pedido_id, "aceitar_orcamento", {"orcamento_id": orc})
        assert r.status_code == 503
        assert c.contexto.pedidos.obter(pedido_id).estado is estados.Estado.ABERTO
        with pytest.raises(ConfigNaoPublicada):
            c.contexto.contratos.salvar(Contrato(pedido_id, orc, c.ids["profissional"], 90_000))
    finally:
        with c.local.admin() as con:
            for f in faixas:
                con.execute(
                    "insert into public.config_faixas_taxa "
                    "(id, de_centavos, ate_centavos, taxa_bps, versao_id) "
                    "values (%s, %s, %s, %s, %s)",
                    f,
                )
            con.execute("alter table public.config_faixas_taxa enable trigger all")
