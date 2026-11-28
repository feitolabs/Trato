"""BE-208-237: encerramento sem falta com aviso de 30 dias (20.8) e histórico de versões dos
Termos (23.7). Memória; nada é enviado de verdade."""

# ruff: noqa: F811 - o parâmetro com nome da fixture importada é do pytest

from __future__ import annotations

from contextlib import contextmanager
from datetime import date, timedelta

import pytest
from conftest import CLIENTE, PROFISSIONAL, cab
from test_fixseg import com_equipe
from test_fluxo_pagamento_e2e import fluxo  # noqa: F401

from trato.api import medidas as regras
from trato.persistencia.medidas import Medida

DIA = timedelta(days=1)


def encerrar(amb, quem=CLIENTE.id, **extra) -> Medida:
    medida = Medida(
        usuario_id=quem,
        tipo="encerramento",
        motivo="O serviço será encerrado na sua região.",
        clausulas=("20.8",),
        inicio_em=amb.contexto.agora(),
        aplicada_por="eq-admin",
        efeito=regras.EFEITO_PADRAO,
        como_contestar=regras.COMO_CONTESTAR,
        **({"sem_falta": True} | extra),
    )
    return regras.aplicar(amb.contexto, medida)[0]


def status(amb) -> str:
    return "bloqueado" if amb.contexto.medidas.conta_bloqueada_travada(CLIENTE.id) else "ativo"


def rotina(amb) -> int:
    return regras.iniciar_agendadas(amb.contexto, amb.contexto.agora())


def test_sem_falta_so_comeca_depois_de_30_dias_e_a_rotina_bloqueia_uma_vez(amb):
    agora = amb.contexto.agora()
    medida = encerrar(amb)
    assert medida.inicio_em == agora + 30 * DIA and medida.avisado_em == agora
    assert not medida.vigente(agora) and status(amb) == "ativo"
    assert amb.cliente.get("/v1/pedidos", headers=cab("t-cliente")).status_code == 200
    amb.relogio.avancar(days=30, seconds=-1)
    assert rotina(amb) == 0 and status(amb) == "ativo"
    amb.relogio.avancar(seconds=1)
    assert rotina(amb) == 1 and status(amb) == "bloqueado"
    assert rotina(amb) == 0


@pytest.mark.parametrize("publicado,dias", [(5, 30), (45, 45)])
def test_configuracao_so_aumenta_o_prazo(amb, publicado, dias):
    amb.contexto.config.parametros["aviso_previo_encerramento_dias"] = publicado
    medida = encerrar(amb)
    assert medida.inicio_em - medida.avisado_em == dias * DIA


@pytest.mark.parametrize("sem_falta", [False, None])
def test_encerramento_por_falta_ou_sem_resposta_continua_imediato(amb, sem_falta):
    medida = encerrar(amb, sem_falta=sem_falta)
    assert medida.inicio_em == amb.contexto.agora() and status(amb) == "bloqueado"
    assert rotina(amb) == 0


def test_repetir_logo_depois_nao_cria_outro(amb):
    primeira = encerrar(amb)
    amb.relogio.avancar(minutes=1)
    assert encerrar(amb).id == primeira.id


def test_revertido_antes_do_dia_nao_bloqueia_nem_mexe_na_conta(amb):
    medida = encerrar(amb)
    amb.contexto.medidas.definir_status(CLIENTE.id, ("ativo",), "restrito")  # outra origem
    amb.relogio.avancar(days=10)
    assert regras.reverter(amb.contexto, medida, "eq-admin") is True
    assert regras.reverter(amb.contexto, medida, "eq-admin") is False
    amb.relogio.avancar(days=20)
    assert rotina(amb) == 0 and status(amb) == "ativo"


def test_rotina_nao_bloqueia_de_novo_quem_voltou_depois(amb):
    encerrar(amb)
    amb.relogio.avancar(days=30)
    assert rotina(amb) == 1
    amb.contexto.medidas.definir_status(CLIENTE.id, ("bloqueado",), "ativo")  # voltou
    amb.relogio.avancar(days=8)
    assert rotina(amb) == 0 and status(amb) == "ativo"


def test_painel_recebe_a_data_futura(amb):
    com_equipe(amb)
    amb.contexto.usuarios.garantir(CLIENTE.id)
    corpo = {
        "usuario_id": CLIENTE.id,
        "tipo": "encerramento",
        "motivo": "O serviço será encerrado na sua região.",
        "clausulas": ["20.8"],
        "sem_falta": True,
    }
    r = amb.cliente.post("/v1/admin/medidas", json=corpo, headers=cab("t-admin"))
    assert r.status_code == 201, r.text
    assert r.json()["vigente"] is False and r.json()["inicio_em"] > r.json()["avisado_em"]


def test_pedido_pago_segue_durante_o_aviso_e_o_cliente_conclui_depois_do_dia(fluxo):
    pid = fluxo.ate_em_confirmacao()
    encerrar(fluxo.amb, PROFISSIONAL.id)
    assert fluxo.chamar("GET", f"/v1/pedidos/{pid}", "t-prof").status_code == 200
    fluxo.amb.relogio.avancar(days=30)
    assert regras.iniciar_agendadas(fluxo.ctx, fluxo.ctx.agora()) == 1
    fluxo.concluir(pid)  # o cliente confirma e o valor devido ao profissional segue
    assert fluxo.repasse(pid).valor_liquido_centavos > 0


# --- 23.7 ----------------------------------------------------------------------------------------


class Banco:
    def __init__(self, linhas=None):
        self.linhas = linhas

    @contextmanager
    def transacao(self):
        if self.linhas is None:
            raise RuntimeError('relation "termos_versoes" does not exist')
        linhas = self.linhas

        class Con:
            def execute(self, _sql):
                return type("R", (), {"fetchall": lambda self: linhas})()

        yield Con()


def versoes(amb):
    r = amb.cliente.get("/v1/termos/versoes")  # sem login
    assert r.status_code == 200, r.text
    return r.json()["itens"]


@pytest.mark.parametrize("banco", [None, Banco()])
def test_sem_a_tabela_vem_o_que_o_codigo_publicou(amb, banco):
    if banco:
        amb.contexto.extras["banco"] = banco
    amb.relogio.agora = amb.relogio.agora.replace(month=11, day=27)
    assert versoes(amb) == [
        {
            "versao": "1.1",
            "vigente_desde": "2026-11-22",
            "vigente_ate": None,
            "atual": True,
            "texto_disponivel": True,
        }
    ]


def test_tabela_manda_na_data_e_versao_futura_nao_aparece(amb):
    amb.contexto.extras["banco"] = Banco(
        [
            {"versao": "1.0", "vigente_desde": date(2026, 10, 31)},
            {"versao": "1.1", "vigente_desde": date(2026, 11, 22)},
            {"versao": "1.2", "vigente_desde": date(2026, 12, 12)},
        ]
    )
    amb.relogio.agora = amb.relogio.agora.replace(month=11, day=27)
    nova, antiga = versoes(amb)
    assert (nova["versao"], nova["atual"]) == ("1.1", True)
    assert (antiga["versao"], antiga["vigente_ate"]) == ("1.0", "2026-11-21")
    assert antiga["texto_disponivel"] is False
    assert amb.cliente.get("/v1/termos/versoes/1.1").json()["texto"].strip()
    for sem_texto in ("1.0", "1.2", "9.9"):
        assert amb.cliente.get(f"/v1/termos/versoes/{sem_texto}").status_code == 404


def test_virada_do_dia_e_a_de_brasilia(amb):
    amb.relogio.agora = amb.relogio.agora.replace(month=11, day=22, hour=2, minute=59)
    assert versoes(amb) == []  # em Brasília ainda é dia 21
    amb.relogio.avancar(minutes=1)
    assert [v["versao"] for v in versoes(amb)] == ["1.1"]
