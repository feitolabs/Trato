"""BE-MARKETING-154: campanha de marketing só para quem consentiu e não desligou o push.
Memória (a rota exige banco: o fluxo completo está em `tests/integracao`)."""

from __future__ import annotations

from datetime import UTC, datetime, timedelta

import pytest

from trato.lgpd.memoria import ConsentimentosEmMemoria
from trato.lgpd.repositorios import Consentimento
from trato.notificacoes.marketing import separar_marketing

T = datetime(2026, 11, 1, tzinfo=UTC)


def registrar(repo, quem, aceito, quando, finalidade="comunicacoes_marketing"):
    repo.registrar(Consentimento(quem, finalidade, aceito, "1", quando))


def test_sem_registro_aceitou_revogou_reaceitou():
    repo = ConsentimentosEmMemoria()
    registrar(repo, "a", True, T, finalidade="termos_de_uso")  # outra finalidade não vale
    assert separar_marketing(["a"], repo, set()) == ([], 1)
    for passo, aceito in enumerate((True, False, True), start=1):
        registrar(repo, "a", aceito, T + timedelta(days=passo))
        assert separar_marketing(["a"], repo, set()) == ((["a"], 0) if aceito else ([], 1))


def test_no_mesmo_instante_vale_o_ultimo_gravado_e_a_data_manda():
    repo = ConsentimentosEmMemoria()
    registrar(repo, "a", True, T)
    registrar(repo, "a", False, T)
    registrar(repo, "b", False, T + timedelta(days=2))
    registrar(repo, "b", True, T + timedelta(days=1))  # gravado depois, mas mais antigo
    assert separar_marketing(["a", "b"], repo, set()) == ([], 2)


def test_fora_soma_sem_consentimento_e_desligados_sem_contar_duas_vezes():
    repo = ConsentimentosEmMemoria()
    for quem in ("aceitou", "desligou"):
        registrar(repo, quem, True, T)
    todos = ["aceitou", "desligou", "nunca", "nunca-e-desligou"]
    recebem, fora = separar_marketing(todos, repo, {"desligou", "nunca-e-desligou"})
    assert (recebem, fora) == (["aceitou"], 3)


def test_erro_na_leitura_sobe_para_nada_ser_enviado():
    class Quebrado:
        def ultimos(self, *_):
            raise RuntimeError("sem tabela")

    with pytest.raises(RuntimeError):
        separar_marketing(["a"], Quebrado(), set())
