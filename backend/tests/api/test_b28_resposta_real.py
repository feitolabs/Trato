"""B28: selo de resposta real (`responde_em_faixa`), só o lado positivo e calculado na leitura."""

from __future__ import annotations

from datetime import timedelta
from types import SimpleNamespace

from conftest import AGORA, CLIENTE, PROFISSIONAL
from test_profissional_upload import _aprovar, e2  # noqa: F401

from trato.api.memoria import OrcamentosEmMemoria
from trato.api.repositorios import Orcamento
from trato.api.repositorios_app import OrcamentoDetalhe
from trato.api.resposta_real import (
    FAIXA_NO_MESMO_DIA,
    JANELA_DIAS,
    MEDIANA_MAXIMA,
    MIN_PEDIDOS_RESPONDIDOS,
    responde_em_faixa,
)
from trato.pedidos.estados import Estado, Pedido

PRO = "pro-1"


def _detalhe(oid, pedido_id, pro, versao, enviado_em):
    return OrcamentoDetalhe(
        id=oid, pedido_id=pedido_id, profissional_id=pro, profissional_nome=None, versao=versao,
        status="enviado", valor_centavos=1000, prazo_execucao_dias=None, validade_ate=None,
        garantia_dias=None, fora_do_escopo=None, sinal_material_centavos=None, observacoes=None,
        enviado_em=enviado_em,
    )  # fmt: skip


class Cenario:
    """Repositório de orçamentos real (memória) e pedidos com data de criação conhecida."""

    def __init__(self) -> None:
        self.orcamentos = OrcamentosEmMemoria()
        self.criados: dict[str, object] = {}
        self.pedidos = SimpleNamespace(
            obter=lambda pid: (
                SimpleNamespace(aberto_em=self.criados[pid]) if pid in self.criados else None
            )
        )
        self._n = 0

    def responder(self, pedido_id, criado_em, apos, pro=PRO, versao=1):
        """Cria o pedido (se novo) e um orçamento enviado `apos` depois da criação."""
        self.criados.setdefault(pedido_id, criado_em)
        self._n += 1
        oid = f"orc-{self._n}"
        self.orcamentos.adicionar(
            Orcamento(oid, pedido_id, pro, 1000, "pintura"),
            _detalhe(oid, pedido_id, pro, versao, self.criados[pedido_id] + apos),
        )

    def faixa(self, pro=PRO):
        return responde_em_faixa(self, pro, AGORA)


def _cinco_rapidos(c, horas=2):
    for i in range(MIN_PEDIDOS_RESPONDIDOS):
        c.responder(f"p{i}", AGORA - timedelta(days=10 + i), timedelta(hours=horas))


def test_constantes_da_regra():
    assert (MIN_PEDIDOS_RESPONDIDOS, JANELA_DIAS) == (5, 90)
    assert MEDIANA_MAXIMA == timedelta(hours=24)


def test_menos_de_cinco_pedidos_e_null():
    c = Cenario()
    for i in range(MIN_PEDIDOS_RESPONDIDOS - 1):
        c.responder(f"p{i}", AGORA - timedelta(days=5), timedelta(minutes=10))
    assert c.faixa() is None


def test_cinco_pedidos_com_mediana_ate_24h_vira_no_mesmo_dia():
    c = Cenario()
    _cinco_rapidos(c)
    assert c.faixa() == FAIXA_NO_MESMO_DIA == "no mesmo dia"


def test_mediana_exatamente_24h_ainda_vale_e_acima_nao():
    c = Cenario()
    _cinco_rapidos(c, horas=24)
    assert c.faixa() == FAIXA_NO_MESMO_DIA
    c2 = Cenario()
    _cinco_rapidos(c2, horas=24.5)
    assert c2.faixa() is None


def test_mediana_e_nao_media_dois_pedidos_lentos_nao_derrubam_o_selo():
    c = Cenario()
    for i, horas in enumerate((1, 2, 3, 100, 200)):  # média alta, mediana 3 h
        c.responder(f"p{i}", AGORA - timedelta(days=5), timedelta(hours=horas))
    assert c.faixa() == FAIXA_NO_MESMO_DIA
    c2 = Cenario()
    for i, horas in enumerate((1, 2, 30, 100, 200)):  # mediana 30 h
        c2.responder(f"p{i}", AGORA - timedelta(days=5), timedelta(hours=horas))
    assert c2.faixa() is None


def test_ignora_pedidos_fora_dos_90_dias():
    c = Cenario()
    for i in range(MIN_PEDIDOS_RESPONDIDOS - 1):
        c.responder(f"p{i}", AGORA - timedelta(days=5), timedelta(hours=1))
    # o 5º foi respondido há 100 dias: fora da janela, então são só 4 válidos
    c.responder("velho", AGORA - timedelta(days=JANELA_DIAS + 10), timedelta(hours=1))
    assert c.faixa() is None
    c.responder("novo", AGORA - timedelta(days=JANELA_DIAS - 5), timedelta(hours=1))
    assert c.faixa() == FAIXA_NO_MESMO_DIA


def test_usa_so_o_primeiro_orcamento_do_pedido():
    c = Cenario()
    _cinco_rapidos(c)
    # revisões tardias do mesmo pedido não pioram o tempo (nem contam como pedido novo)
    for i in range(MIN_PEDIDOS_RESPONDIDOS):
        c.responder(f"p{i}", AGORA, timedelta(days=3), versao=2)
    assert c.faixa() == FAIXA_NO_MESMO_DIA
    # e cinco versões 2 sem o primeiro envio rápido não fabricam o selo: 1 pedido só
    c2 = Cenario()
    for versao in range(1, 6):
        c2.responder("unico", AGORA - timedelta(days=3), timedelta(hours=1), versao=versao)
    assert c2.faixa() is None


def test_so_o_proprio_profissional():
    c = Cenario()
    _cinco_rapidos(c)
    for i in range(MIN_PEDIDOS_RESPONDIDOS):
        c.responder(f"q{i}", AGORA - timedelta(days=5), timedelta(hours=1), pro="outro")
    assert c.faixa("pro-sem-orcamento") is None
    assert c.faixa("outro") == FAIXA_NO_MESMO_DIA and c.faixa() == FAIXA_NO_MESMO_DIA
    c.responder("so-dele", AGORA - timedelta(days=5), timedelta(hours=40), pro="lento")
    assert c.faixa("lento") is None


def test_falha_de_leitura_vira_null():
    quebrado = SimpleNamespace(
        orcamentos=SimpleNamespace(
            primeiros_envios=lambda *a: (_ for _ in ()).throw(RuntimeError("x"))
        )
    )
    assert responde_em_faixa(quebrado, PRO, AGORA) is None


def test_perfil_publico_devolve_responde_em_faixa(e2):  # noqa: F811
    _aprovar(e2)
    contexto = e2.amb.contexto
    assert e2.get(f"/v1/profissionais/{PRO}", "t-cliente").json()["responde_em_faixa"] is None
    for i in range(MIN_PEDIDOS_RESPONDIDOS):
        criado = AGORA - timedelta(days=3 + i)
        contexto.pedidos.salvar(Pedido(f"rr-{i}", CLIENTE.id, criado, Estado.ABERTO))
        contexto.orcamentos.adicionar(
            Orcamento(f"orc-rr-{i}", f"rr-{i}", PROFISSIONAL.id, 1000, "pintura"),
            _detalhe(f"orc-rr-{i}", f"rr-{i}", PROFISSIONAL.id, 1, criado + timedelta(hours=3)),
        )
    corpo = e2.get(f"/v1/profissionais/{PRO}", "t-cliente").json()
    assert corpo["responde_em_faixa"] == "no mesmo dia"
    assert corpo["taxa_conclusao"] is None or isinstance(corpo["taxa_conclusao"], int)
