"""Ranking de profissionais: média ponderada, nota composta, pesos em configuração e busca."""

from __future__ import annotations

from contextlib import contextmanager

import pytest
from conftest import AGORA, cab

from trato.api.auth import PapelUsuario
from trato.api.repositorios_app import PerfilDetalhe
from trato.api.rotas_profissional_cadastro import modulo_em_memoria
from trato.persistencia.profissionais import ProfissionaisPostgres
from trato.profissional.ranking import (
    ConfigRanking,
    RankingEmMemoria,
    nota_ponderada,
    pontuacao,
)
from trato.profissional.repositorio import FiltroBusca, PerfilProfissional, Regiao

CFG = ConfigRanking()


# --- a conta -------------------------------------------------------------------------------


def test_uma_avaliacao_perfeita_nao_passa_quem_tem_muitas_boas():
    um_cinco = nota_ponderada(5.0, 1, CFG)
    veterano = nota_ponderada(4.8, 200, CFG)
    assert veterano > um_cinco


def test_sem_avaliacao_vale_a_nota_prior_e_com_muitas_vale_a_propria_nota():
    assert nota_ponderada(None, 0, CFG) == CFG.nota_prior
    assert nota_ponderada(None, 12, CFG) == CFG.nota_prior
    assert nota_ponderada(3.0, 100_000, CFG) == pytest.approx(3.0, abs=0.001)


def test_nota_com_contagem_zero_nao_divide_por_zero():
    cfg = ConfigRanking(prior_avaliacoes=0)
    assert nota_ponderada(4.0, 0, cfg) == 4.0  # nota existe => pelo menos 1 avaliação


def test_pontuacao_fica_entre_0_e_1_e_cada_fator_pesa():
    base = {"nota": 4.5, "avaliacoes": 10, "concluidos": 5, "disponivel_agora": False, "cfg": CFG}
    comum = pontuacao(nivel_verificacao="basico", **base)
    mais_verificado = pontuacao(nivel_verificacao="verificado_plus", **base)
    assert 0 <= comum < mais_verificado <= 1
    disponivel = pontuacao(nivel_verificacao="basico", **{**base, "disponivel_agora": True})
    assert disponivel > comum
    mais_servicos = pontuacao(nivel_verificacao="basico", **{**base, "concluidos": 20})
    assert mais_servicos > comum
    # o volume satura: passar da referência não rende mais
    assert pontuacao(nivel_verificacao="basico", **{**base, "concluidos": 500}) == mais_servicos


def test_pesos_zerados_caem_na_media_ponderada_pura():
    zero = ConfigRanking(peso_nota=0, peso_volume=0, peso_verificacao=0, peso_disponivel=0)
    p = pontuacao(
        nota=4.0,
        avaliacoes=50,
        concluidos=0,
        nivel_verificacao=None,
        disponivel_agora=False,
        cfg=zero,
    )
    assert p == pytest.approx(nota_ponderada(4.0, 50, zero) / 5)


# --- busca em memória ----------------------------------------------------------------------


@pytest.fixture
def busca(amb):
    modulo = modulo_em_memoria(amb.cliente.app)
    modulo.catalogo.categorias.update({"c-pint": "pintura"})
    modulo.catalogo.nomes.update({"c-pint": "Pintura"})
    modulo.catalogo.cidades.add("bh")

    def novo(uid, nome, nota, avaliacoes, concluidos, nivel="verificado"):
        modulo.repo.salvar(
            PerfilProfissional(uid, "aprovado", "Bio.", ("c-pint",), (Regiao("bh"),), (), (), AGORA)
        )
        amb.contexto.usuarios.adicionar(
            PerfilDetalhe(
                uid,
                nome,
                PapelUsuario.PROFISSIONAL,
                "ativo",
                nivel,
                nota,
                concluidos,
                None,
                avaliacoes,
            )
        )

    novo("novato5", "Novato Cinco", 5.0, 1, 1)
    novo("veterano", "Veterano Bom", 4.8, 200, 150)
    novo("sem_nota", "Sem Nota", None, 0, 0)
    return modulo


def ids(r):
    return [i["id"] for i in r.json()["itens"]]


def test_busca_poe_o_veterano_na_frente_de_quem_tem_uma_avaliacao_perfeita(amb, busca):
    r = amb.cliente.get("/v1/profissionais", headers=cab("t-cliente"))
    assert r.status_code == 200
    assert ids(r)[0] == "veterano"
    # o que o app mostra continua sendo a nota real, não a ponderada
    novato = next(i for i in r.json()["itens"] if i["id"] == "novato5")
    assert novato["nota_publica"] == 5.0


def test_quem_nao_tem_avaliacao_nao_fica_sempre_no_fim(amb, busca):
    # Só peso de nota: o sem nota (prior 4,0) fica acima de quem tem uma nota ruim.
    amb.contexto.ranking = RankingEmMemoria(
        ConfigRanking(nota_prior=4.0, peso_volume=0, peso_verificacao=0, peso_disponivel=0)
    )
    busca.repo.salvar(
        PerfilProfissional("ruim", "aprovado", "Bio.", ("c-pint",), (Regiao("bh"),), (), (), AGORA)
    )
    amb.contexto.usuarios.adicionar(
        PerfilDetalhe(
            "ruim", "Pro Ruim", PapelUsuario.PROFISSIONAL, "ativo", "verificado", 2.0, 30, None, 30
        )
    )
    ordem = ids(amb.cliente.get("/v1/profissionais", headers=cab("t-cliente")))
    assert ordem.index("sem_nota") < ordem.index("ruim")


def test_os_pesos_da_configuracao_mudam_a_ordem(amb, busca):
    # Só volume de serviços: quem tem mais serviços concluídos vem primeiro.
    amb.contexto.ranking = RankingEmMemoria(
        ConfigRanking(peso_nota=0, peso_volume=1, peso_verificacao=0, peso_disponivel=0)
    )
    ordem = ids(amb.cliente.get("/v1/profissionais", headers=cab("t-cliente")))
    assert ordem[0] == "veterano"
    assert ordem.index("novato5") < ordem.index("sem_nota")


# --- Postgres (conexão simulada): ordem e parâmetros da consulta -----------------------------


class _Resultado:
    def __init__(self, linhas):
        self._linhas = linhas

    def fetchall(self):
        return self._linhas

    def fetchone(self):
        return self._linhas[0] if self._linhas else None


class _Con:
    def __init__(self, respostas):
        self.respostas = respostas
        self.chamadas = []

    def execute(self, sql, params=None):
        self.chamadas.append((sql, list(params or [])))
        return _Resultado(self.respostas[len(self.chamadas) - 1])


class _Banco:
    def __init__(self, respostas):
        self.con = _Con(respostas)

    @contextmanager
    def transacao(self):
        yield self.con


def _cand(uid, nota, concluidos, avaliacoes, nivel="verificado", ordem_texto=2, ordem_bairro=1):
    return {
        "usuario_id": uid,
        "nota_publica": nota,
        "servicos_concluidos": concluidos,
        "nivel_verificacao": nivel,
        "disponivel_agora": False,
        "n_avaliacoes": avaliacoes,
        "sem_bio": 0,
        "ordem_texto": ordem_texto,
        "ordem_bairro": ordem_bairro,
    }


def _detalhe(uid):
    return {
        "usuario_id": uid,
        "nome": uid,
        "bio": "b",
        "nivel_verificacao": "verificado",
        "nota_publica": 4.0,
        "servicos_concluidos": 1,
        "atende_remoto": False,
        "categorias": [],
        "cidades": [],
        "bairros": [],
    }


def test_postgres_ordena_pela_nota_composta_e_pagina_depois_de_ordenar():
    novato = "11111111-1111-1111-1111-111111111111"
    veterano = "22222222-2222-2222-2222-222222222222"
    medio = "33333333-3333-3333-3333-333333333333"
    candidatos = [
        _cand(novato, 5.0, 1, 1),
        _cand(veterano, 4.8, 150, 200),
        _cand(medio, 4.0, 10, 10),
    ]
    banco = _Banco([candidatos, [_detalhe(veterano), _detalhe(medio)]])
    achados, total = ProfissionaisPostgres(banco).buscar(
        FiltroBusca(limite=2, deslocamento=0, ranking=CFG)
    )
    assert total == 3
    assert [a.usuario_id for a in achados] == [veterano, medio]  # veterano na frente
    sql_fase1, _ = banco.con.chamadas[0]
    assert "limit" not in sql_fase1.lower()  # a página só é cortada depois de ordenar
    sql_fase2, params2 = banco.con.chamadas[1]
    assert "any(%s::uuid[])" in sql_fase2
    assert params2 == [[veterano, medio]]


def test_postgres_texto_manda_primeiro_e_parametros_batem_com_os_marcadores():
    a = "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"
    b = "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb"
    # b tem nota melhor, mas a casa melhor com o texto (ordem_texto menor): a vem antes.
    banco = _Banco(
        [
            [_cand(a, 4.0, 1, 1, ordem_texto=0), _cand(b, 5.0, 99, 99)],
            [_detalhe(a), _detalhe(b)],
        ]
    )
    filtro = FiltroBusca(texto="pintura", bairro="Savassi", ranking=CFG, limite=10)
    achados, _ = ProfissionaisPostgres(banco).buscar(filtro)
    assert [x.usuario_id for x in achados] == [a, b]
    sql, params = banco.con.chamadas[0]
    assert sql.count("%s") == len(params)  # nenhum marcador sobrando nem faltando


def test_postgres_pagina_vazia_nao_faz_a_segunda_consulta():
    banco = _Banco([[_cand("11111111-1111-1111-1111-111111111111", 4.0, 1, 1)]])
    achados, total = ProfissionaisPostgres(banco).buscar(
        FiltroBusca(limite=10, deslocamento=50, ranking=CFG)
    )
    assert achados == []
    assert total == 1
    assert len(banco.con.chamadas) == 1
