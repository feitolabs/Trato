"""TERMOS-BE-FIXSEG: achados da revisão de segurança (A1, M2, M4, M5, M6 e arquivos auditados).
Memória e provedor falso."""

from __future__ import annotations

import pytest
from conftest import (
    AGORA,
    CLIENTE,
    MEMBROS_EQUIPE,
    OUTRO_PROFISSIONAL,
    PROFISSIONAL,
    cab,
)
from test_ausencia_cliente import (
    INICIO,
    LONGE,
    RETENCAO,
    justificar,
    painel,
    registrado,
)
from test_fluxo_pagamento_e2e import fluxo  # noqa: F401 - fixture
from test_medidas import aplicar, contesto, decide
from test_provas_ausencia import auditoria, com_retencao, ler
from test_termos_m2_dinheiro import custodia, parcelado, total_estornado

from trato.api.admin.memoria import EquipeEmMemoria
from trato.api.admin.papeis import PapelEquipe
from trato.api.admin.repositorios import MembroEquipe
from trato.api.auth import PapelUsuario, Usuario
from trato.api.denuncias import marcador
from trato.api.repositorios_app import PerfilDetalhe
from trato.financeiro.ledger import TAXA_TRATO, a_liberar
from trato.persistencia.compensacoes import CompensacoesIndisponiveis, Registro

EQUIPE_EXTRA = {"t-lider": PapelEquipe.LIDER_SUPORTE, "t-admin": PapelEquipe.ADMINISTRADOR}


def com_equipe(amb) -> None:
    """Acrescenta um líder de suporte e um administrador."""
    novos = [
        MembroEquipe(f"eq-{t[2:]}", papel, alcada_centavos=10**9)
        for t, papel in EQUIPE_EXTRA.items()
    ]
    amb.admin.equipe = EquipeEmMemoria([*MEMBROS_EQUIPE.values(), *novos])
    for t in EQUIPE_EXTRA:
        amb.contexto.auth._usuarios[t] = Usuario(f"eq-{t[2:]}", PapelUsuario.EQUIPE)


# --- A1: o operador é quem registra ---------------------------------------------------------------


class Espia(CompensacoesIndisponiveis):
    def __init__(self) -> None:
        self.registros: list[tuple] = []
        self.cancelados: list[tuple] = []

    def disponivel(self) -> bool:
        return True

    def registrar_disputa(self, pedido_id, contestacao_id, valor_centavos, motivo, operador_id):
        self.registros.append((pedido_id, contestacao_id, valor_centavos, motivo, operador_id))
        return Registro("analista_invalido")

    def cancelar(self, divida_id, analista_id, motivo):
        self.cancelados.append((divida_id, analista_id))
        return super().cancelar(divida_id, analista_id, motivo)


@pytest.mark.parametrize("quem,operador", [("t-mediador", "eq-med"), ("t-admin", "eq-admin")])
def test_a1_registro_leva_o_id_de_quem_operou(fluxo, quem, operador):  # noqa: F811
    com_equipe(fluxo.amb)
    pid = fluxo.aceitar()
    espia = fluxo.ctx.compensacoes = Espia()
    corpo = {"pedido_id": pid, "valor_centavos": 100, "motivo": "Reembolso decidido depois."}
    r = fluxo.chamar("POST", "/v1/admin/compensacoes", quem, corpo)
    assert r.status_code == 403 and r.json()["codigo"] == "analista_invalido", r.text
    assert espia.registros == [(pid, None, 100, corpo["motivo"], operador)]
    assert fluxo.servico.ordens.do_pedido(pid) == []  # recusado: nenhuma ordem


def test_a1_modo_memoria_tem_o_mesmo_contrato():
    memoria = CompensacoesIndisponiveis()
    r = memoria.registrar_disputa("p", None, 1, "motivo", "operador")
    assert r.resultado == "indisponivel"


# --- M2: custo do parcelado fora da repartição ----------------------------------------------------


@pytest.mark.parametrize("retencao", [1, 4_999, 5_000, 5_001])
def test_m2_retencao_menor_que_o_custo_pela_rota(fluxo, retencao):  # noqa: F811
    pid, cobranca = parcelado(fluxo)  # custo do parcelado: 5.000
    cobrado = fluxo.servico.cobrancas.obter(cobranca).valor_centavos
    fluxo.amb.relogio.agora = INICIO + LONGE
    registrado(fluxo, pid, LONGE)
    justificar(fluxo, pid)
    assert painel(fluxo, pid, **(RETENCAO | {"retencao_centavos": retencao})).status_code == 200
    fluxo.amb.relogio.avancar(days=10)
    r = painel(fluxo, pid, rota="confirmar")
    assert r.status_code == 200, r.text
    assert total_estornado(fluxo, cobranca) == cobrado - retencao
    assert fluxo.ctx.ledger.saldo_da_conta(a_liberar(PROFISSIONAL.id), pid) == retencao
    assert fluxo.ctx.ledger.saldo_da_conta(TAXA_TRATO, pid) == 0 and custodia(fluxo, pid) == 0
    fluxo.ctx.ledger.livro.verificar_partidas()


# --- M4: cancelar compensação ---------------------------------------------------------------------


@pytest.mark.parametrize(
    "quem,passa",
    [("t-lider", True), ("t-admin", True), ("t-mediador", False), ("t-financeiro", False),
     ("t-seguranca", False), ("t-prof", False)],
)  # fmt: skip
def test_m4_so_lider_ou_administrador_cancela(amb, quem, passa):
    com_equipe(amb)
    espia = amb.contexto.compensacoes = Espia()
    url = "/v1/admin/compensacoes/abc/cancelar"
    r = amb.cliente.post(url, json={"motivo": "Contestação aceita."}, headers=cab(quem))
    assert (r.status_code != 403) is passa, r.text
    assert len(espia.cancelados) == (1 if passa else 0)


# --- M5: conta da equipe --------------------------------------------------------------------------


def _alvo_da_equipe(amb) -> str:
    com_equipe(amb)
    for quem in ("eq-n1", CLIENTE.id):
        amb.contexto.usuarios.adicionar(PerfilDetalhe(quem, "Pessoa", PapelUsuario.CLIENTE))
    return "eq-n1"


@pytest.mark.parametrize("quem", ["t-mediador", "t-lider", "t-seguranca"])
def test_m5_medida_na_equipe_so_o_administrador_aplica_e_reverte(amb, quem):
    alvo = _alvo_da_equipe(amb)
    r = aplicar(amb, quem, usuario_id=alvo)
    assert r.status_code == 403 and "equipe" in r.text
    assert amb.contexto.medidas.listar(usuario_id=alvo)[1] == 0
    assert amb.contexto.medidas.status.get(alvo, "ativo") == "ativo"
    mid = aplicar(amb, "t-admin", usuario_id=alvo).json()["id"]
    url = f"/v1/admin/medidas/{mid}/reverter"
    corpo = {"motivo": "Revisão do caso concluída."}
    assert amb.cliente.post(url, json=corpo, headers=cab(quem)).status_code == 403
    amb.contexto.auth._usuarios["t-alvo"] = Usuario(alvo, PapelUsuario.CLIENTE)
    assert contesto(amb, mid, quem="t-alvo").status_code == 200
    assert decide(amb, mid, quem).status_code == 403
    assert amb.contexto.medidas.status[alvo] == "bloqueado"
    assert amb.cliente.post(url, json=corpo, headers=cab("t-admin")).status_code == 200
    assert amb.contexto.medidas.status[alvo] == "ativo"


def test_m5_conta_comum_continua_com_os_mesmos_papeis(amb):
    _alvo_da_equipe(amb)
    assert aplicar(amb, "t-lider").status_code == 201


# --- M6: conversas --------------------------------------------------------------------------------


def _tres_conversas(f) -> str:
    com_equipe(f.amb)
    pid = f.aceitar()
    f.pagar(pid)
    for prof, texto in (
        (PROFISSIONAL.id, "contratado"),
        (OUTRO_PROFISSIONAL.id, "do-alerta"),
        ("pro-3", "alheio"),
    ):
        conversa = f.ctx.conversas.abrir(pid, prof)
        f.ctx.conversas.enviar(conversa, CLIENTE.id, f"mensagem {texto}")
    return pid


def _profissionais(r) -> set[str]:
    assert r.status_code == 200, r.text
    return {c["profissional_id"] for c in r.json()["conversas"]}


def test_m6_ordem_judicial_so_administrador_e_so_as_partes(fluxo):  # noqa: F811
    pid = _tres_conversas(fluxo)
    for quem in ("t-mediador", "t-lider", "t-seguranca"):
        r = ler(fluxo, pid, quem, referencia="0001234-55")
        assert r.status_code == 403 and "mensagem" not in r.text
    r = ler(fluxo, pid, "t-admin", referencia="0001234-55")
    assert _profissionais(r) == {PROFISSIONAL.id}
    assert "alheio" not in r.text and "do-alerta" not in r.text
    (linha,) = auditoria(fluxo, "dado_pessoal.conversa_lida")
    assert len(linha.depois["conversas"]) == 1


@pytest.mark.parametrize(
    "denunciado,detalhes",
    [
        (OUTRO_PROFISSIONAL.id, f"Denúncia{marcador(CLIENTE.id, OUTRO_PROFISSIONAL.id)} x"),
        (CLIENTE.id, f"Denúncia{marcador(OUTRO_PROFISSIONAL.id, CLIENTE.id)} x"),
    ],
)
def test_m6_denuncia_inclui_o_profissional_do_alerta(fluxo, denunciado, detalhes):  # noqa: F811
    pid = _tres_conversas(fluxo)
    fluxo.ctx.denuncias.registrar(denunciado, pid, "denuncia_chat", "media", detalhes, AGORA)
    fluxo.ctx.chamados.vinculos.add(("denuncia", pid))
    r = ler(fluxo, pid, base="denuncia")
    assert _profissionais(r) == {PROFISSIONAL.id, OUTRO_PROFISSIONAL.id}
    assert "alheio" not in r.text


def test_m6_disputa_traz_so_o_contratado_e_o_fato_informa_as_partes(fluxo):  # noqa: F811
    pid = _tres_conversas(fluxo)
    fluxo.ctx.chamados.vinculos.add(("incidente", pid))
    assert _profissionais(ler(fluxo, pid, base="incidente")) == {PROFISSIONAL.id}
    fluxo.ctx.chamados.partes[("incidente", pid)] = {"pro-3"}
    assert _profissionais(ler(fluxo, pid, base="incidente")) == {PROFISSIONAL.id, "pro-3"}


# --- anexos do painel -----------------------------------------------------------------------------


def test_anexos_auditam_quais_arquivos_receberam_link(fluxo):  # noqa: F811
    pid, _, _ = com_retencao(fluxo)
    url = f"/v1/admin/ausencias/{pid}/anexos"
    r = fluxo.chamar("POST", url, "t-mediador", {"motivo": "Conferir as provas do caso."})
    assert r.status_code == 200, r.text
    com_link = [a["arquivo_id"] for a in r.json() if a["url"]]
    (linha,) = auditoria(fluxo, "dado_pessoal.ausencia_anexos_vistos")
    assert com_link and linha.depois["arquivos"] == com_link
    assert "f1" not in linha.depois["arquivos"]  # sem link: não conta
