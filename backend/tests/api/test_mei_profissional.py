"""MEI do profissional: validação do CNPJ (BrasilAPI simulada) e bloqueio do orçamento."""

from __future__ import annotations

from datetime import UTC, datetime, timedelta

import pytest
from conftest import cab

from trato.api.rotas_profissional_cadastro import modulo_em_memoria
from trato.pedidos.estados import Estado
from trato.profissional.mei import (
    MOTIVO_NAO_ENCONTRADO,
    MOTIVO_NAO_MEI,
    ConfigMei,
    ConsultaCnpj,
    MeiEmMemoria,
    ServicoMei,
    StatusMei,
    cnpj_valido,
)

CNPJ_OK = "11222333000181"  # dígitos verificadores corretos (exemplo de teste)
CNPJ_DV_ERRADO = "11222333000182"
ORCAMENTO = {
    "prazo_execucao_dias": 3,
    "validade_ate": "2099-01-01T00:00:00Z",
    "itens": [
        {
            "tipo": "horas",
            "descricao": "Pintura",
            "quantidade": "1",
            "valor_unitario_centavos": 5000,
        }
    ],
    "fora_do_escopo": "Materiais não incluídos.",
    "garantia_dias": 90,
}


class Relogio:
    def __init__(self) -> None:
        self.t = datetime(2026, 11, 24, 12, 0, tzinfo=UTC)

    def __call__(self) -> datetime:
        return self.t


class BrasilApiFalsa:
    def __init__(self, resposta=None) -> None:
        self.resposta = resposta
        self.urls: list[str] = []

    def __call__(self, url):
        self.urls.append(url)
        if isinstance(self.resposta, Exception):
            raise self.resposta
        return self.resposta


def _corpo(ativa=True, mei=True):
    return {
        "razao_social": "JOAO DA SILVA 12345678900",
        "descricao_situacao_cadastral": "ATIVA" if ativa else "BAIXADA",
        "situacao_cadastral": 2 if ativa else 8,
        "opcao_pelo_mei": mei,
    }


def _servico(resposta, obrigatorio=True, relogio=None):
    relogio = relogio or Relogio()
    busca = BrasilApiFalsa(resposta)
    cfg = ConfigMei(obrigatorio=obrigatorio)
    return ServicoMei(consulta=ConsultaCnpj(busca, cfg, relogio), config=cfg, agora=relogio), busca


def test_digito_verificador():
    assert cnpj_valido("11.222.333/0001-81")
    assert not cnpj_valido(CNPJ_DV_ERRADO)
    assert not cnpj_valido("11111111111111")
    assert not cnpj_valido("123")
    assert not cnpj_valido(None)


def test_cnpj_invalido_nao_chama_a_api():
    svc, busca = _servico((200, _corpo()))
    r = svc.informar("pro-1", CNPJ_DV_ERRADO)
    assert r.mei_status is StatusMei.INVALIDO
    assert "não é válido" in r.mei_motivo
    assert busca.urls == []


def test_mei_ativo_valido_e_so_o_cnpj_sai_na_requisicao():
    svc, busca = _servico((200, _corpo()))
    r = svc.informar("pro-1", "11.222.333/0001-81")
    assert r.mei_status is StatusMei.VALIDO
    assert r.cnpj == CNPJ_OK
    assert r.razao_social == "JOAO DA SILVA 12345678900"
    assert r.mei_validado_em is not None
    assert busca.urls == [f"https://brasilapi.com.br/api/cnpj/v1/{CNPJ_OK}"]
    assert svc.liberado("pro-1")


def test_cnpj_inativo_e_invalido():
    svc, _ = _servico((200, _corpo(ativa=False)))
    r = svc.informar("pro-1", CNPJ_OK)
    assert r.mei_status is StatusMei.INVALIDO
    assert "ativa" in r.mei_motivo
    assert not svc.liberado("pro-1")


def test_cnpj_ativo_que_nao_e_mei_nao_vale():
    svc, _ = _servico((200, _corpo(mei=False)))
    r = svc.informar("pro-1", CNPJ_OK)
    assert r.mei_status is StatusMei.INVALIDO and r.mei_motivo == MOTIVO_NAO_MEI
    assert r.cnpj is None and r.tipo_cnpj is None
    assert svc.status("pro-1").mei_status is StatusMei.INVALIDO


def test_cnpj_optante_mei_guarda_o_tipo_mei():
    svc, _ = _servico((200, _corpo(mei=True)))
    assert svc.informar("pro-1", CNPJ_OK).tipo_cnpj == "mei"


def test_tipo_so_existe_com_cnpj_valido():
    svc, busca = _servico((200, _corpo(ativa=False)))
    assert svc.informar("pro-1", CNPJ_OK).tipo_cnpj is None
    assert svc.informar("pro-2", CNPJ_DV_ERRADO).tipo_cnpj is None


def test_cnpj_inexistente_404_e_invalido():
    svc, _ = _servico((404, {"message": "nao encontrado"}))
    assert svc.informar("pro-1", CNPJ_OK).mei_status is StatusMei.INVALIDO


@pytest.mark.parametrize("resposta", [TimeoutError("lento"), (503, None), (429, None), (200, None)])
def test_api_fora_do_ar_fica_pendente_e_nunca_reprova(resposta):
    svc, busca = _servico(resposta)
    r = svc.informar("pro-1", CNPJ_OK)
    assert r.mei_status is StatusMei.PENDENTE
    assert len(busca.urls) == 2  # tentativa + 1 retry
    assert not svc.liberado("pro-1")


def test_pendente_nao_guarda_o_cnpj_e_valida_quando_o_app_manda_de_novo():
    svc, busca = _servico(TimeoutError("x"))
    r = svc.informar("pro-1", CNPJ_OK)
    assert r.mei_status is StatusMei.PENDENTE
    assert svc.status("pro-1").cnpj is None  # não reserva o CNPJ enquanto não validou
    busca.resposta = (200, _corpo())
    assert svc.informar("pro-1", CNPJ_OK).mei_status is StatusMei.VALIDO


def test_cache_de_24h_nao_repete_a_consulta_e_expira():
    relogio = Relogio()
    svc, busca = _servico((200, _corpo()), relogio=relogio)
    svc.informar("pro-1", CNPJ_OK)
    svc.informar("pro-2", CNPJ_OK)
    assert len(busca.urls) == 1
    relogio.t += timedelta(hours=25)
    svc.informar("pro-3", CNPJ_OK)
    assert len(busca.urls) == 2


def test_falha_nao_entra_no_cache():
    svc, busca = _servico((503, None))
    svc.informar("pro-1", CNPJ_OK)
    svc.informar("pro-1", CNPJ_OK)
    assert len(busca.urls) == 4


def test_nao_informado_por_padrao():
    svc, _ = _servico((200, _corpo()))
    assert svc.status("pro-9").mei_status is StatusMei.NAO_INFORMADO
    assert not svc.liberado("pro-9")


# --- API -------------------------------------------------------------------------------------


def _liga(amb, resposta, obrigatorio=True):
    svc, busca = _servico(resposta, obrigatorio=obrigatorio)
    amb.cliente.app.state.servico_mei = svc
    return svc, busca


def test_rota_envia_cnpj_e_le_status(amb):
    _liga(amb, (200, _corpo()))
    r = amb.cliente.get("/v1/profissional/mei", headers=cab("t-prof"))
    assert r.status_code == 200
    assert r.json()["mei_status"] == "nao_informado"
    assert r.json()["pode_orcar_e_receber"] is False
    r = amb.cliente.put("/v1/profissional/mei", json={"cnpj": CNPJ_OK}, headers=cab("t-prof"))
    assert r.status_code == 200, r.text
    assert r.json()["mei_status"] == "valido"
    assert r.json()["pode_orcar_e_receber"] is True
    assert amb.cliente.get("/v1/profissional/mei", headers=cab("t-prof")).json()["cnpj"] == CNPJ_OK


def test_rota_so_para_profissional(amb):
    _liga(amb, (200, _corpo()))
    assert amb.cliente.get("/v1/profissional/mei", headers=cab("t-cliente")).status_code == 403
    assert amb.cliente.get("/v1/profissional/mei").status_code == 401


def test_orcamento_bloqueado_sem_mei_valido_e_liberado_com_mei(amb):
    amb.semear_pedido(Estado.ABERTO, profissional_id=None, orcamento_id=None)
    _liga(amb, (200, _corpo()))
    r = amb.cliente.post("/v1/pedidos/ped-1/orcamentos", json=ORCAMENTO, headers=cab("t-prof"))
    assert r.status_code == 422
    assert "CNPJ" in r.json()["detail"]

    amb.cliente.put("/v1/profissional/mei", json={"cnpj": CNPJ_DV_ERRADO}, headers=cab("t-prof"))
    r = amb.cliente.post("/v1/pedidos/ped-1/orcamentos", json=ORCAMENTO, headers=cab("t-prof"))
    assert r.status_code == 422  # CNPJ inválido não libera

    svc, busca = _liga(amb, (200, _corpo()))
    amb.cliente.put("/v1/profissional/mei", json={"cnpj": CNPJ_OK}, headers=cab("t-prof"))
    r = amb.cliente.post("/v1/pedidos/ped-1/orcamentos", json=ORCAMENTO, headers=cab("t-prof"))
    assert r.status_code == 201, r.text


def test_orcamento_bloqueado_com_api_fora_do_ar(amb):
    amb.semear_pedido(Estado.ABERTO, profissional_id=None, orcamento_id=None)
    _liga(amb, TimeoutError("x"))
    amb.cliente.put("/v1/profissional/mei", json={"cnpj": CNPJ_OK}, headers=cab("t-prof"))
    r = amb.cliente.post("/v1/pedidos/ped-1/orcamentos", json=ORCAMENTO, headers=cab("t-prof"))
    assert r.status_code == 422


def test_bloqueio_desligado_nao_afeta_orcamento(amb):
    amb.semear_pedido(Estado.ABERTO, profissional_id=None, orcamento_id=None)
    _liga(amb, (200, _corpo()), obrigatorio=False)
    r = amb.cliente.post("/v1/pedidos/ped-1/orcamentos", json=ORCAMENTO, headers=cab("t-prof"))
    assert r.status_code == 201, r.text


# --- unicidade, squatting, persistência, taxa e privacidade ----------------------------------


def _servicos_com_repo_comum(resposta):
    relogio = Relogio()
    cfg = ConfigMei(obrigatorio=True)
    repo = MeiEmMemoria()
    busca = BrasilApiFalsa(resposta)

    def novo():  # simula reinício: serviço novo, mesmo repositório
        return ServicoMei(
            repo=repo, consulta=ConsultaCnpj(busca, cfg, relogio), config=cfg, agora=relogio
        )

    return novo, repo, busca


def test_cnpj_duplicado_por_dois_profissionais_responde_neutro():
    novo, _, _ = _servicos_com_repo_comum((200, _corpo()))
    svc = novo()
    assert svc.informar("pro-1", CNPJ_OK).mei_status is StatusMei.VALIDO
    segundo = svc.informar("pro-2", CNPJ_OK)
    assert segundo.mei_status is StatusMei.INVALIDO
    assert segundo.cnpj is None
    assert segundo.mei_motivo == MOTIVO_NAO_ENCONTRADO  # igual ao de "CNPJ não validado"
    assert "outr" not in segundo.mei_motivo.lower() and "já" not in segundo.mei_motivo.lower()
    assert svc.status("pro-1").mei_status is StatusMei.VALIDO  # o dono não é afetado


def test_nao_squatting_pendente_e_invalido_nao_ocupam_o_cnpj():
    novo, repo, busca = _servicos_com_repo_comum(TimeoutError("fora"))
    svc = novo()
    assert svc.informar("squatter", CNPJ_OK).mei_status is StatusMei.PENDENTE
    assert repo.obter("squatter").cnpj is None
    # outra consulta (sem cache) vê CNPJ inativo: também não reserva o CNPJ
    cfg = ConfigMei(obrigatorio=True)
    ruim = ServicoMei(
        repo=repo,
        consulta=ConsultaCnpj(BrasilApiFalsa((200, _corpo(ativa=False))), cfg),
        config=cfg,
    )
    assert ruim.informar("squatter", CNPJ_OK).mei_status is StatusMei.INVALIDO
    assert repo.obter("squatter").cnpj is None
    busca.resposta = (200, _corpo())
    assert svc.informar("dono", CNPJ_OK).mei_status is StatusMei.VALIDO


def test_tentativa_ruim_nao_derruba_o_mei_ja_valido():
    novo, repo, busca = _servicos_com_repo_comum((200, _corpo()))
    svc = novo()
    svc.informar("pro-1", CNPJ_OK)
    busca.resposta = (200, _corpo(ativa=False))
    outro = "27865757000102"
    assert cnpj_valido(outro)
    assert svc.informar("pro-1", outro).mei_status is StatusMei.INVALIDO
    assert repo.obter("pro-1").mei_status is StatusMei.VALIDO
    assert repo.obter("pro-1").cnpj == CNPJ_OK


def test_persiste_apos_novo_servico():
    novo, _, _ = _servicos_com_repo_comum((200, _corpo()))
    novo().informar("pro-1", CNPJ_OK)
    depois = novo()
    assert depois.status("pro-1").mei_status is StatusMei.VALIDO
    assert depois.liberado("pro-1")


def test_rota_cnpj_em_uso_e_422_neutro_igual_ao_nao_validado(amb):
    svc, _ = _liga(amb, (200, _corpo()))
    svc.informar("pro-2", CNPJ_OK)  # outro profissional já tem
    em_uso = amb.cliente.put("/v1/profissional/mei", json={"cnpj": CNPJ_OK}, headers=cab("t-prof"))
    svc.consulta._buscador = BrasilApiFalsa((404, None))
    nao_validado = amb.cliente.put(
        "/v1/profissional/mei", json={"cnpj": "27865757000102"}, headers=cab("t-prof")
    )
    assert em_uso.status_code == nao_validado.status_code == 422
    assert em_uso.json() == nao_validado.json()


def test_regra_padrao_de_limite_do_put_mei_e_5_por_hora_por_usuario():
    from trato.seguranca.config import ConfigSeguranca

    (regra,) = [r for r in ConfigSeguranca(_env_file=None).limites if r.nome == "mei_cnpj"]
    assert (regra.metodos, regra.escopo, regra.maximo, regra.janela_s) == (
        ["PUT"],
        "usuario",
        5,
        3600,
    )


def test_cnpj_e_razao_social_so_para_o_proprio_profissional(amb):
    svc, _ = _liga(amb, (200, _corpo()))
    svc.informar("pro-1", CNPJ_OK)
    meu = amb.cliente.get("/v1/profissional/mei", headers=cab("t-prof")).json()
    assert meu["cnpj"] == CNPJ_OK and meu["razao_social"]
    outro = amb.cliente.get("/v1/profissional/mei", headers=cab("t-outro-prof"))
    assert CNPJ_OK not in outro.text and "JOAO" not in outro.text
    assert amb.cliente.get("/v1/profissional/mei", headers=cab("t-cliente")).status_code == 403


def test_postgres_sem_a_coluna_nova_cai_no_padrao_sem_quebrar():
    from contextlib import contextmanager

    import psycopg

    from trato.persistencia.erros import ErroPersistencia
    from trato.persistencia.mei import MeiPostgres

    class BancoSemColuna:
        @contextmanager
        def transacao(self):
            yield self
            raise AssertionError("não chega aqui")

        def execute(self, *_a, **_k):
            erro = ErroPersistencia("Erro ao acessar o banco de dados.")
            raise erro from psycopg.errors.UndefinedColumn("coluna mei_status não existe")

    assert MeiPostgres(BancoSemColuna()).obter("00000000-0000-0000-0000-000000000001") is None


def test_rota_devolve_tipo_cnpj(amb):
    _liga(amb, (200, _corpo(mei=False)))
    assert (
        amb.cliente.get("/v1/profissional/mei", headers=cab("t-prof")).json()["tipo_cnpj"] is None
    )
    r = amb.cliente.put("/v1/profissional/mei", json={"cnpj": CNPJ_OK}, headers=cab("t-prof"))
    assert r.status_code == 422, r.text
    lido = amb.cliente.get("/v1/profissional/mei", headers=cab("t-prof")).json()
    assert lido["tipo_cnpj"] is None and lido["pode_orcar_e_receber"] is False


def test_profissional_em_analise_acessa_so_a_rota_do_cnpj(amb):
    # t-cliente tem papel de cliente; com perfil profissional criado (em análise) ele entra aqui
    _liga(amb, (200, _corpo()))
    assert amb.cliente.get("/v1/profissional/mei", headers=cab("t-cliente")).status_code == 403
    modulo_em_memoria(amb.cliente.app)
    amb.contexto.usuarios.profissionais.add("cli-1")  # perfil criado, ainda não aprovado
    r = amb.cliente.put("/v1/profissional/mei", json={"cnpj": CNPJ_OK}, headers=cab("t-cliente"))
    assert r.status_code == 200, r.text
    assert r.json()["mei_status"] == "valido"
    # perfil recusado ou suspenso: 403 também nesta rota
    for status in ("recusado", "suspenso"):
        amb.contexto.usuarios.status_perfis["cli-1"] = status
        assert amb.cliente.get("/v1/profissional/mei", headers=cab("t-cliente")).status_code == 403
        r = amb.cliente.put(
            "/v1/profissional/mei", json={"cnpj": CNPJ_OK}, headers=cab("t-cliente")
        )
        assert r.status_code == 403
    amb.contexto.usuarios.status_perfis["cli-1"] = "em_analise"
    # as demais rotas de profissional seguem fechadas para quem está em análise
    amb.semear_pedido(Estado.ABERTO, profissional_id=None, orcamento_id=None)
    r = amb.cliente.post("/v1/pedidos/ped-1/orcamentos", json=ORCAMENTO, headers=cab("t-cliente"))
    assert r.status_code == 403
    # e o dado é só do próprio usuário
    outro = amb.cliente.get("/v1/profissional/mei", headers=cab("t-outro-cliente"))
    assert outro.status_code == 403
