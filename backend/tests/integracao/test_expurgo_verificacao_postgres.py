"""BE-148-DOCS no Postgres local, com Storage falso: o que sai e, principalmente, o que NÃO sai."""

# ruff: noqa: F811 - o parâmetro com nome da fixture importada é do pytest

from __future__ import annotations

import logging
import uuid
from datetime import UTC, datetime, timedelta

import pytest

from trato.agendador.__main__ import rotina_de_expurgo_verificacao
from trato.agendador.config import ConfigAgendador
from trato.persistencia.verificacao_expurgo import ExpurgoVerificacaoPostgres
from trato.uploads import ArmazenamentoFake

from .test_disputa_painel_postgres import em_disputa
from .test_pagamento_postgres import (  # noqa: F401 - `pg` e `migrations_novas` são fixtures
    linhas,
    migrations_novas,
    pg,
)

pytestmark = pytest.mark.integracao

DIA = timedelta(days=1)


@pytest.fixture
def amb(pg):
    def limpar():
        with pg.local.admin() as con:
            con.execute("set session_replication_role = replica")
            con.execute("delete from public.verificacao_documentos")
            con.execute("delete from public.verificacoes")

    limpar()
    yield pg
    limpar()


class Cena:
    def __init__(self, c) -> None:
        self.c = c
        self.arquivos = ArmazenamentoFake()
        self.agora = datetime.now(UTC)
        self.repo = ExpurgoVerificacaoPostgres(c.banco, self.arquivos)

    def sql(self, texto, *args):
        with self.c.local.admin() as con:
            cur = con.execute(texto, args)
            return cur.fetchone() if cur.description else None

    def usuario(self) -> str:
        uid = str(uuid.uuid4())
        self.sql("insert into auth.users (id) values (%s)", uid)
        self.sql("insert into public.usuarios (id, nome) values (%s, 'Pessoa de teste')", uid)
        return uid

    def profissional(self) -> str:
        uid = self.usuario()
        self.sql("insert into public.perfis_profissional (usuario_id) values (%s)", uid)
        return uid

    def equipe(self) -> str:
        uid = self.usuario()
        self.sql(
            "insert into public.equipe (usuario_id, papel, ativo) values (%s, 'seguranca', true)",
            uid,
        )
        return uid

    def verificacao(self, pessoa, status, dias, tipos=("documento_frente",), caminhos=None):
        """`dias` = há quantos dias foi decidida (ou enviada, se pendente)."""
        quando = self.agora - dias * DIA
        decidida = quando if status in ("aprovada", "recusada") else None
        (vid,) = self.sql(
            "insert into public.verificacoes (profissional_id, nivel_solicitado, status, "
            "motivo_recusa, consentimento_lgpd_em, enviada_em, decidida_em) "
            "values (%s, 'verificado', %s, %s, %s, %s, %s) returning id",
            pessoa,
            status,
            "ilegível" if status == "recusada" else None,
            quando,
            quando,
            decidida,
        )
        saida = []
        for i, tipo in enumerate(tipos):
            caminho = caminhos[i] if caminhos else f"{pessoa}/pendente/{uuid.uuid4().hex}.jpg"
            self.arquivos.simular_envio("verificacao", caminho, b"x")
            (did,) = self.sql(
                "insert into public.verificacao_documentos (verificacao_id, tipo, storage_path) "
                "values (%s, %s, %s) returning id",
                vid,
                tipo,
                caminho,
            )
            saida.append((str(did), caminho))
        return saida

    def existe(self, doc) -> tuple[bool, bool]:
        """(referência, arquivo)"""
        did, caminho = doc
        (n,) = self.sql("select count(*) from public.verificacao_documentos where id = %s", did)
        return bool(n), ("verificacao", caminho) in self.arquivos.arquivos

    def rodar(self, limite=100) -> int:
        return self.repo.expurgar(self.agora, 90, limite)


FICA, SAIU = (True, True), (False, False)


def test_elimina_recusado_e_substituido_e_preserva_o_resto(amb):
    c = Cena(amb)
    p1, p2, p3, p4 = (c.profissional() for _ in range(4))
    (recusado,) = c.verificacao(p1, "recusada", 91)
    (recusado_recente,) = c.verificacao(p1, "recusada", 89)
    (pendente,) = c.verificacao(p1, "enviada", 400)
    (vigente,) = c.verificacao(p2, "aprovada", 400)
    velho_frente, velho_selfie, velho_outro = c.verificacao(
        p3, "aprovada", 500, ("documento_frente", "selfie", "outro")
    )
    novo_frente, novo_outro = c.verificacao(p3, "aprovada", 100, ("documento_frente", "outro"))
    (recem_substituido,) = c.verificacao(p4, "aprovada", 500)
    (substituto,) = c.verificacao(p4, "aprovada", 30)
    (em_analise,) = c.verificacao(p4, "em_analise", 200)

    assert c.rodar() == 2
    assert c.existe(recusado) == SAIU and c.existe(velho_frente) == SAIU
    for doc in (
        recusado_recente,
        pendente,
        vigente,
        velho_selfie,  # não veio selfie nova: continua valendo
        velho_outro,  # "outro" não se substitui
        novo_frente,
        novo_outro,
        recem_substituido,  # substituído há 30 dias
        substituto,
        em_analise,
    ):
        assert c.existe(doc) == FICA, doc
    assert c.rodar() == 0  # repetir não faz nada


def test_arquivo_ainda_usado_ou_fora_da_pasta_da_pessoa_nao_sai(amb):
    c = Cena(amb)
    dono, outro = c.profissional(), c.profissional()
    mesmo = f"{dono}/pendente/mesmo.jpg"
    (recusado,) = c.verificacao(dono, "recusada", 200, caminhos=[mesmo])
    c.verificacao(dono, "aprovada", 100, caminhos=[f"verificacao/{mesmo}"])
    alheio = f"{outro}/pendente/alheio.jpg"
    (apontando,) = c.verificacao(dono, "recusada", 200, caminhos=[alheio])
    (subindo,) = c.verificacao(dono, "recusada", 200, caminhos=[f"{dono}/../{alheio}"])
    assert c.rodar() == 0
    for doc in (recusado, apontando, subindo):
        assert c.existe(doc) == FICA


@pytest.mark.parametrize("guarda", ["usuario", "pedido", "incidente"])
def test_guarda_ou_incidente_aberto_segura_e_encerrado_libera(amb, guarda):
    c = Cena(amb)
    pessoa, analista = c.profissional(), c.equipe()
    (doc,) = c.verificacao(pessoa, "recusada", 200)
    if guarda == "usuario":
        c.sql(
            "insert into public.acessos_conta_guardas (usuario_id, motivo, criada_por) "
            "values (%s, 'Processo', %s)",
            pessoa,
            analista,
        )
        encerrar = (
            "update public.acessos_conta_guardas set encerrada_em = now(), encerrada_por = %s "
            "where usuario_id = %s"
        )
        args = (analista, pessoa)
    elif guarda == "pedido":
        # pedido da própria pessoa como cliente
        (pedido,) = c.sql(
            "insert into public.pedidos (cliente_id, categoria_id, cidade_id, titulo, descricao) "
            "values (%s, %s, %s, 'Teste', 'Teste') returning id",
            pessoa,
            amb.categoria_id,
            amb.cidade_id,
        )
        c.sql(
            "insert into public.pedido_guardas (pedido_id, tipo, motivo, criada_por) "
            "values (%s, 'processo', 'Processo', %s)",
            pedido,
            analista,
        )
        encerrar = (
            "update public.pedido_guardas set encerrada_em = now(), encerrada_por = %s "
            "where pedido_id = %s"
        )
        args = (analista, pedido)
    else:
        (incidente,) = c.sql(
            "insert into public.incidentes_seguranca (canal, tipo, envolvido_id, cautela_ate, contato) "
            "values ('painel', 'outro', %s, now() + interval '23 hours', 'teste@exemplo.test') returning id",
            pessoa,
        )
        encerrar = None
    assert c.rodar() == 0
    assert c.existe(doc) == FICA
    if encerrar:
        c.sql(encerrar, *args)
        assert c.rodar() == 1
        assert c.existe(doc) == SAIU


def test_falha_no_storage_mantem_a_referencia_sem_dado_pessoal_no_log(amb, monkeypatch, caplog):
    c = Cena(amb)
    pessoa = c.profissional()
    (a,) = c.verificacao(pessoa, "recusada", 300)
    (b,) = c.verificacao(pessoa, "recusada", 200)
    original = c.arquivos.remover

    def falha(bucket, caminho):
        if caminho == a[1]:
            raise RuntimeError(f"Storage fora: {bucket}/{caminho}")
        original(bucket, caminho)

    monkeypatch.setattr(c.arquivos, "remover", falha)
    with caplog.at_level(logging.DEBUG):
        assert c.rodar() == 1
    assert c.existe(a) == FICA and c.existe(b) == SAIU
    assert a[0] in caplog.text and pessoa not in caplog.text and a[1] not in caplog.text
    monkeypatch.setattr(c.arquivos, "remover", original)
    assert c.rodar() == 1 and c.existe(a) == SAIU


def test_lote_limitado_desligado_por_padrao_e_prazo_validado(amb):
    c = Cena(amb)
    pessoa = c.profissional()
    docs = [c.verificacao(pessoa, "recusada", 100 + i)[0] for i in range(3)]
    desligada = ConfigAgendador(_env_file=None)
    assert desligada.expurgo_verificacao_ligado is False
    assert rotina_de_expurgo_verificacao(amb.banco, desligada, c.arquivos) is None
    ligada = ConfigAgendador(
        _env_file=None, expurgo_verificacao_ligado=True, expurgo_verificacao_limite=2
    )
    rotina = rotina_de_expurgo_verificacao(amb.banco, ligada, c.arquivos)
    assert (rotina(c.agora), rotina(c.agora), rotina(c.agora)) == (2, 1, 0)
    assert all(c.existe(d) == SAIU for d in docs)
    for dias, limite in ((91, 10), (0, 10), (90, 0)):
        with pytest.raises(ValueError):
            c.repo.expurgar(c.agora, dias, limite)
    assert not linhas(amb, "select 1 from public.verificacao_documentos")


@pytest.mark.parametrize(
    ("antigos", "novos", "saem"),
    [
        # frente e verso: a nova sem verso não substitui nenhum dos lados
        (("documento_frente", "documento_verso"), ("documento_frente",), 0),
        (("documento_frente", "documento_verso"), ("documento_frente", "documento_verso"), 2),
        # dois do mesmo tipo, de um lado ou do outro: não é 1 para 1
        (("selfie", "selfie"), ("selfie",), 0),
        (("selfie",), ("selfie", "selfie"), 0),
        # tipos que podem ser vários documentos diferentes
        (
            ("comprovante_endereco", "curso_nr10", "registro_profissional", "antecedentes"),
            ("comprovante_endereco", "curso_nr10", "registro_profissional", "antecedentes"),
            0,
        ),
        (("seguro", "outro"), ("seguro", "outro"), 0),
    ],
)
def test_substituido_so_quando_e_um_para_um(amb, antigos, novos, saem):
    c = Cena(amb)
    pessoa = c.profissional()
    velhos = c.verificacao(pessoa, "aprovada", 500, antigos)
    atuais = c.verificacao(pessoa, "aprovada", 200, novos)
    assert c.rodar() == saem
    for doc in velhos:
        assert c.existe(doc) == (SAIU if saem else FICA)
    for doc in atuais:
        assert c.existe(doc) == FICA


@pytest.mark.parametrize("bloqueio", ["medida", "contestacao_da_medida", "cartao"])
def test_medida_e_contestacao_de_cartao_abertas_seguram(amb, bloqueio):
    c = Cena(amb)
    pessoa = c.profissional()
    (doc,) = c.verificacao(pessoa, "recusada", 200)
    with amb.local.admin() as con:
        con.execute("set session_replication_role = replica")  # só para montar o cenário
        if bloqueio == "cartao":
            (pedido,) = con.execute(
                "insert into public.pedidos (cliente_id, categoria_id, cidade_id, titulo, "
                "descricao) values (%s, %s, %s, 'Teste', 'Teste') returning id",
                (pessoa, amb.categoria_id, amb.cidade_id),
            ).fetchone()
            con.execute(
                "insert into public.contestacoes (provedor_contestacao_id, pedido_id, "
                "valor_centavos, status, aberta_em, atualizada_em) "
                "values (%s, %s, 100, 'aberta', now(), now())",
                (f"dp_{uuid.uuid4().hex}", pedido),
            )
            soltar = (
                "update public.contestacoes set status = 'ganha' where pedido_id = %s",
                pedido,
            )
        else:
            fim = datetime.now(UTC) - DIA if bloqueio == "contestacao_da_medida" else None
            analista = c.equipe()
            (medida,) = con.execute(
                "insert into public.medidas_conta (protocolo, usuario_id, tipo, motivo_usuario, "
                "clausulas, inicio_em, fim_em, efeito_pedidos_valores, como_contestar, origem, "
                "aplicada_por) values (%s, %s, 'restricao', 'Motivo', array['20.2'], "
                "now() - interval '3 days', %s, 'Nenhum', 'No app', 'analista', %s) "
                "returning id",
                (f"MED-2026-{uuid.uuid4().int % 10**9:09d}", pessoa, fim, analista),
            ).fetchone()
            if bloqueio == "medida":
                soltar = (
                    "update public.medidas_conta set fim_em = now() - interval '1 hour' "
                    "where id = %s",
                    medida,
                )
            else:
                con.execute(
                    "insert into public.medida_contestacoes (protocolo, medida_id, usuario_id, "
                    "versao_usuario, canal, responder_ate) "
                    "values (%s, %s, %s, 'Discordo', 'app', now() + interval '5 days')",
                    (f"CMD-2026-{uuid.uuid4().int % 10**9:09d}", medida, pessoa),
                )
                soltar = (
                    "delete from public.medida_contestacoes where medida_id = %s",
                    medida,
                )
    try:
        assert c.rodar() == 0
        assert c.existe(doc) == FICA
        with amb.local.admin() as con:
            con.execute("set session_replication_role = replica")
            con.execute(soltar[0], (soltar[1],))
        assert c.rodar() == 1 and c.existe(doc) == SAIU
    finally:
        with amb.local.admin() as con:
            con.execute("set session_replication_role = replica")
            con.execute("delete from public.contestacoes")
            con.execute("delete from public.medida_contestacoes")
            con.execute("delete from public.medidas_conta")


def test_disputa_aberta_segura_os_documentos_do_profissional(amb):
    c = Cena(amb)
    em_disputa(amb)
    pessoa = amb.ids["profissional"]
    (doc,) = c.verificacao(pessoa, "recusada", 200)
    assert c.rodar() == 0
    assert c.existe(doc) == FICA


def test_auditoria_sem_dado_pessoal_e_so_do_que_saiu(amb, monkeypatch):
    c = Cena(amb)
    pessoa = c.profissional()
    (doc,) = c.verificacao(pessoa, "recusada", 200)
    consulta = (
        "select ator_id, ator_tipo, antes, depois::text, motivo from public.auditoria "
        "where acao = 'lgpd.documento_verificacao_eliminado' and entidade_id = %s"
    )

    def falha(bucket, caminho):
        raise RuntimeError("fora do ar")

    with monkeypatch.context() as m:
        m.setattr(c.arquivos, "remover", falha)
        assert c.rodar() == 0
    assert not linhas(amb, consulta, (doc[0],))  # não saiu: não há registro de eliminação
    assert c.rodar() == 1 and c.rodar() == 0
    ((ator, tipo, antes, depois, motivo),) = linhas(amb, consulta, (doc[0],))
    assert (ator, tipo, antes) == (None, "sistema", None)
    assert depois == '{"regra": "recusado"}'
    assert pessoa not in f"{depois}{motivo}" and doc[1] not in f"{depois}{motivo}"
