"""TERMOS-BE-1310 (13.10 e I.11): Tratinhos no encerramento voluntário da conta. Memória."""

from __future__ import annotations

import threading
from datetime import timedelta

import pytest
from ambiente_seg import AGORA, CLIENTE, cab, montar

from trato.api.moedas import (
    CARTEIRA_CLIENTE,
    CARTEIRA_PROFISSIONAL,
    LancamentoMoeda,
    MoedasEmMemoria,
    saldo_total_disponivel,
    zerar_tratinhos_encerramento_voluntario,
)

URL = "/v1/me/exclusao"
PROCESSAR = "/v1/lgpd/exclusoes/processar"


def creditar(
    moedas: MoedasEmMemoria,
    usuario_id: str,
    qtd: int,
    chave: str,
    *,
    carteira: str = CARTEIRA_CLIENTE,
    expira_em=None,
    criada_em=AGORA,
) -> None:
    tipo = "bonus_avaliacao" if carteira == CARTEIRA_CLIENTE else "bonus_avaliacao_profissional"
    assert moedas.lancar(
        LancamentoMoeda(
            usuario_id=usuario_id,
            tipo=tipo,
            quantidade=qtd,
            chave_idempotencia=chave,
            criada_em=criada_em,
            expira_em=expira_em,
            carteira=carteira,
        )
    )


def test_previa_mostra_tratinhos_a_perder_com_saldo_zero():
    amb = montar()
    r_get = amb.cliente.get(URL, headers=cab("t-cli"))
    assert r_get.status_code == 200
    assert r_get.json()["tratinhos_a_perder"] == 0

    r_post = amb.cliente.post(URL, headers=cab("t-cli"))
    assert r_post.status_code == 200
    assert r_post.json()["tratinhos_a_perder"] == 0


def test_previa_soma_carteiras_e_ignora_creditos_vencidos():
    amb = montar()
    moedas = amb.contexto.moedas
    creditar(moedas, CLIENTE.id, 120, "c-valido", expira_em=AGORA + timedelta(days=30))
    creditar(moedas, CLIENTE.id, 40, "c-vencido", expira_em=AGORA - timedelta(days=1))
    creditar(
        moedas,
        CLIENTE.id,
        80,
        "p-valido",
        carteira=CARTEIRA_PROFISSIONAL,
        expira_em=AGORA + timedelta(days=60),
    )

    r_get = amb.cliente.get(URL, headers=cab("t-cli"))
    assert r_get.status_code == 200 and r_get.json()["tratinhos_a_perder"] == 200

    r_post = amb.cliente.post(URL, headers=cab("t-cli"))
    assert r_post.status_code == 200 and r_post.json()["tratinhos_a_perder"] == 200


def test_cancelar_durante_carencia_mantem_tratinhos():
    amb = montar()
    moedas = amb.contexto.moedas
    creditar(moedas, CLIENTE.id, 90, "c-1", expira_em=AGORA + timedelta(days=90))

    token = amb.cliente.post(URL, headers=cab("t-cli")).json()["token_confirmacao"]
    r_conf = amb.cliente.post(URL, json={"token_confirmacao": token}, headers=cab("t-cli"))
    assert r_conf.status_code == 200 and r_conf.json()["status"] == "agendada"
    assert moedas.saldo(CLIENTE.id, amb.relogio.agora, CARTEIRA_CLIENTE) == 90

    r_del = amb.cliente.delete(URL, headers=cab("t-cli"))
    assert r_del.status_code == 204
    assert moedas.saldo(CLIENTE.id, amb.relogio.agora, CARTEIRA_CLIENTE) == 90
    assert len(moedas.lancamentos_da_carteira(CLIENTE.id, CARTEIRA_CLIENTE)) == 1


def test_efetivacao_zera_carteiras_no_livro_imutavel_e_e_idempotente():
    amb = montar()
    moedas = amb.contexto.moedas
    creditar(moedas, CLIENTE.id, 150, "c-1", expira_em=AGORA + timedelta(days=90))
    creditar(
        moedas,
        CLIENTE.id,
        60,
        "p-1",
        carteira=CARTEIRA_PROFISSIONAL,
        expira_em=AGORA + timedelta(days=90),
    )

    token = amb.cliente.post(URL, headers=cab("t-cli")).json()["token_confirmacao"]
    assert (
        amb.cliente.post(URL, json={"token_confirmacao": token}, headers=cab("t-cli")).status_code
        == 200
    )

    amb.relogio.avancar(days=8)
    r = amb.cliente.post(PROCESSAR, headers=cab("t-equipe"))
    assert r.status_code == 200 and r.json()["anonimizadas"] == 1

    assert moedas.saldo(CLIENTE.id, amb.relogio.agora, CARTEIRA_CLIENTE) == 0
    assert moedas.saldo(CLIENTE.id, amb.relogio.agora, CARTEIRA_PROFISSIONAL) == 0
    cli_lancs = moedas.lancamentos_da_carteira(CLIENTE.id, CARTEIRA_CLIENTE)
    prof_lancs = moedas.lancamentos_da_carteira(CLIENTE.id, CARTEIRA_PROFISSIONAL)
    assert [(i.tipo, i.quantidade) for i in cli_lancs] == [
        ("bonus_avaliacao", 150),
        ("ajuste", -150),
    ]
    assert [(i.tipo, i.quantidade) for i in prof_lancs] == [
        ("bonus_avaliacao_profissional", 60),
        ("ajuste", -60),
    ]
    assert amb.seg.auditoria_em_memoria.eventos[-1]["depois"]["tratinhos_zerados"] == 210

    r2 = amb.cliente.post(PROCESSAR, headers=cab("t-equipe"))
    assert r2.status_code == 200 and r2.json()["anonimizadas"] == 0
    assert len(moedas.lancamentos_da_carteira(CLIENTE.id, CARTEIRA_CLIENTE)) == 2
    assert len(moedas.lancamentos_da_carteira(CLIENTE.id, CARTEIRA_PROFISSIONAL)) == 2


def test_efetivacao_com_saldo_zero_nao_cria_lancamento_vazio():
    amb = montar()
    moedas = amb.contexto.moedas
    token = amb.cliente.post(URL, headers=cab("t-cli")).json()["token_confirmacao"]
    assert (
        amb.cliente.post(URL, json={"token_confirmacao": token}, headers=cab("t-cli")).status_code
        == 200
    )
    amb.relogio.avancar(days=8)
    r = amb.cliente.post(PROCESSAR, headers=cab("t-equipe"))
    assert r.status_code == 200 and r.json()["anonimizadas"] == 1
    assert moedas.lancamentos_da_carteira(CLIENTE.id, CARTEIRA_CLIENTE) == []
    assert moedas.lancamentos_da_carteira(CLIENTE.id, CARTEIRA_PROFISSIONAL) == []
    assert amb.seg.auditoria_em_memoria.eventos[-1]["depois"]["tratinhos_zerados"] == 0


def test_concorrencia_e_repeticao_direta_nunca_duplicam_nem_negativam():
    moedas = MoedasEmMemoria()
    creditar(moedas, "u-1", 100, "c-1", expira_em=AGORA + timedelta(days=90))
    creditar(
        moedas,
        "u-1",
        50,
        "p-1",
        carteira=CARTEIRA_PROFISSIONAL,
        expira_em=AGORA + timedelta(days=90),
    )

    resultados: list[int] = []
    barreira = threading.Barrier(8)

    def rodar(i: int) -> None:
        barreira.wait()
        pid = "ped-1" if i < 4 else f"ped-{i}"
        resultados.append(zerar_tratinhos_encerramento_voluntario(moedas, "u-1", pid, AGORA))

    threads = [threading.Thread(target=rodar, args=(i,)) for i in range(8)]
    for t in threads:
        t.start()
    for t in threads:
        t.join()

    assert sum(resultados) == 150
    assert moedas.saldo("u-1", AGORA, CARTEIRA_CLIENTE) == 0
    assert moedas.saldo("u-1", AGORA, CARTEIRA_PROFISSIONAL) == 0
    assert len(moedas.lancamentos_da_carteira("u-1", CARTEIRA_CLIENTE)) == 2
    assert len(moedas.lancamentos_da_carteira("u-1", CARTEIRA_PROFISSIONAL)) == 2


def test_degradacao_segura_sem_servico_de_moedas():
    assert saldo_total_disponivel(None, "u-1", AGORA) == 0
    assert zerar_tratinhos_encerramento_voluntario(None, "u-1", "ped-1", AGORA) == 0

    class RepoQuebrado:
        def saldo(self, *_a, **_kw):
            raise RuntimeError("tabela ausente")

        def trava(self, *_a, **_kw):
            raise RuntimeError("tabela ausente")

    quebrado = RepoQuebrado()
    assert saldo_total_disponivel(quebrado, "u-1", AGORA) == 0  # type: ignore[arg-type]
    # A4: falha que não é ausência conferida da estrutura sobe (aborta a exclusão).
    with pytest.raises(RuntimeError):
        zerar_tratinhos_encerramento_voluntario(quebrado, "u-1", "ped-1", AGORA)  # type: ignore[arg-type]

    class SemEstrutura(RepoQuebrado):
        def carteira_disponivel(self, _carteira):
            return False

    assert zerar_tratinhos_encerramento_voluntario(SemEstrutura(), "u-1", "ped-1", AGORA) == 0  # type: ignore[arg-type]
