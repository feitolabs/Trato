"""MEI do profissional no Postgres local (pgserver): unicidade, squatting, persistência, sigilo."""

from __future__ import annotations

import uuid

import pytest
from psycopg.rows import dict_row

from trato.persistencia.mei import MeiPostgres
from trato.profissional.mei import (
    MOTIVO_NAO_ENCONTRADO,
    CnpjEmUso,
    ConfigMei,
    ConsultaCnpj,
    PerfilInexistente,
    RegistroMei,
    ServicoMei,
    StatusMei,
    cnpj_valido,
)

pytestmark = pytest.mark.integracao


def cnpj_novo() -> str:
    """CNPJ com dígitos verificadores corretos e base única por chamada."""
    base = f"{uuid.uuid4().int % 10**8:08d}0001"

    def dv(b: str) -> str:
        pesos = (
            [5, 4, 3, 2, 9, 8, 7, 6, 5, 4, 3, 2]
            if len(b) == 12
            else [6, *range(5, 1, -1), 9, 8, 7, 6, 5, 4, 3, 2]
        )
        resto = sum(int(d) * p for d, p in zip(b, pesos, strict=True)) % 11
        return "0" if resto < 2 else str(11 - resto)

    d1 = dv(base)
    cnpj = base + d1 + dv(base + d1)
    assert cnpj_valido(cnpj)
    return cnpj


def corpo(ativa=True, mei=True):
    return {
        "razao_social": "EMPRESA TESTE MEI",
        "descricao_situacao_cadastral": "ATIVA" if ativa else "BAIXADA",
        "opcao_pelo_mei": mei,
    }


class Api:
    def __init__(self, resposta) -> None:
        self.resposta = resposta
        self.urls: list[str] = []

    def __call__(self, url):
        self.urls.append(url)
        if isinstance(self.resposta, Exception):
            raise self.resposta
        return self.resposta


def servico(c, resposta) -> ServicoMei:
    cfg = ConfigMei(obrigatorio=True)
    return ServicoMei(
        repo=MeiPostgres(c.banco), consulta=ConsultaCnpj(Api(resposta), cfg), config=cfg
    )


def novo_profissional(c, aprovado=True) -> str:
    uid = str(uuid.uuid4())
    with c.local.admin() as con:
        con.execute("insert into auth.users (id) values (%s)", (uid,))
        con.execute(
            "insert into public.usuarios (id, nome) values (%s, %s)", (uid, "Maria Teste Silva")
        )
        con.execute("insert into public.perfis_profissional (usuario_id) values (%s)", (uid,))
        if aprovado:
            con.execute(
                "update public.perfis_profissional set status = 'aprovado', "
                "nivel_verificacao = 'verificado' where usuario_id = %s",
                (uid,),
            )
    c.ids[f"mei-{uid}"] = uid
    return uid


def linha(c, uid):
    with c.local.admin() as con:
        return (
            con.cursor(row_factory=dict_row)
            .execute(
                "select cnpj, mei_status, mei_motivo, mei_validado_em, razao_social "
                "from public.perfis_profissional where usuario_id = %s",
                (uid,),
            )
            .fetchone()
        )


def liga_http(c, resposta) -> None:
    c.cliente.app.state.servico_mei = servico(c, resposta)


def put(c, uid, cnpj):
    return c.cliente.put("/v1/profissional/mei", json={"cnpj": cnpj}, headers=c.token(f"mei-{uid}"))


def get(c, uid):
    return c.cliente.get("/v1/profissional/mei", headers=c.token(f"mei-{uid}"))


def test_mei_valido_persiste_apos_novo_servico(cenario):
    c = cenario
    uid, cnpj = novo_profissional(c), cnpj_novo()
    assert servico(c, (200, corpo())).informar(uid, cnpj).mei_status is StatusMei.VALIDO
    depois = servico(c, TimeoutError("fora"))  # "reinício": serviço novo, mesmo banco
    r = depois.status(uid)
    assert (r.mei_status, r.cnpj, r.razao_social) == (StatusMei.VALIDO, cnpj, "EMPRESA TESTE MEI")
    assert r.mei_validado_em is not None
    assert depois.liberado(uid)
    assert linha(c, uid)["cnpj"] == cnpj


def test_cnpj_duplicado_por_dois_profissionais_e_422_neutro_sem_500(cenario):
    c = cenario
    dono, outro, cnpj = novo_profissional(c), novo_profissional(c), cnpj_novo()
    liga_http(c, (200, corpo()))
    assert put(c, dono, cnpj).status_code == 200
    r = put(c, outro, cnpj)  # 23505 no índice único, escondido pelo serviço
    assert r.status_code == 422
    assert r.json()["detail"] == MOTIVO_NAO_ENCONTRADO
    for pista in ("já", "existe", "outra", "cadastrad", "uso"):
        assert pista not in r.text.lower()
    # texto idêntico ao de um CNPJ simplesmente não validado
    liga_http(c, (404, None))
    assert put(c, outro, cnpj_novo()).json() == r.json()
    assert linha(c, outro)["cnpj"] is None
    assert linha(c, dono)["cnpj"] == cnpj and linha(c, dono)["mei_status"] == "valido"


def test_repositorio_levanta_cnpj_em_uso_na_violacao_de_unicidade(cenario):
    c = cenario
    a, b, cnpj = novo_profissional(c), novo_profissional(c), cnpj_novo()
    repo = MeiPostgres(c.banco)
    valido = dict(mei_status=StatusMei.VALIDO, mei_motivo="MEI ativo.", cnpj=cnpj)
    repo.salvar(RegistroMei(a, **valido))
    with pytest.raises(CnpjEmUso):
        repo.salvar(RegistroMei(b, **valido))
    assert linha(c, b)["mei_status"] == "nao_informado"  # a transação foi desfeita


def test_nao_squatting_pendente_e_invalido_nao_ocupam_o_indice(cenario):
    c = cenario
    squatter, dono, cnpj = novo_profissional(c), novo_profissional(c), cnpj_novo()
    assert servico(c, TimeoutError("x")).informar(squatter, cnpj).mei_status is StatusMei.PENDENTE
    assert linha(c, squatter)["cnpj"] is None and linha(c, squatter)["mei_status"] == "pendente"
    assert (
        servico(c, (200, corpo(mei=False))).informar(squatter, cnpj).mei_status
        is StatusMei.INVALIDO
    )
    assert linha(c, squatter)["cnpj"] is None and linha(c, squatter)["razao_social"] is None
    assert servico(c, (200, corpo())).informar(dono, cnpj).mei_status is StatusMei.VALIDO
    assert linha(c, dono)["cnpj"] == cnpj


def test_tentativa_ruim_nao_derruba_mei_valido(cenario):
    c = cenario
    uid, cnpj = novo_profissional(c), cnpj_novo()
    servico(c, (200, corpo())).informar(uid, cnpj)
    servico(c, (200, corpo(ativa=False))).informar(uid, cnpj_novo())
    assert linha(c, uid)["mei_status"] == "valido" and linha(c, uid)["cnpj"] == cnpj


def test_sem_perfil_nao_grava_e_cnpj_so_aparece_para_o_dono(cenario):
    c = cenario
    sem_perfil = str(uuid.uuid4())
    with c.local.admin() as con:
        con.execute("insert into auth.users (id) values (%s)", (sem_perfil,))
        con.execute(
            "insert into public.usuarios (id, nome) values (%s, 'Sem Perfil')", (sem_perfil,)
        )
    with pytest.raises(PerfilInexistente):
        MeiPostgres(c.banco).salvar(
            RegistroMei(sem_perfil, cnpj_novo(), StatusMei.VALIDO, "MEI ativo.")
        )
    liga_http(c, (200, corpo()))

    dono, curioso, cnpj = novo_profissional(c), novo_profissional(c), cnpj_novo()
    assert put(c, dono, cnpj).status_code == 200
    assert get(c, dono).json()["cnpj"] == cnpj
    espiao = get(c, curioso)
    assert cnpj not in espiao.text and "EMPRESA TESTE MEI" not in espiao.text
    publico = c.cliente.get(f"/v1/publico/profissionais/{dono}")
    assert publico.status_code == 200
    assert cnpj not in publico.text and "EMPRESA TESTE" not in publico.text
    assert "cnpj" not in publico.text.lower() and "razao" not in publico.text.lower()


def test_servico_padrao_em_producao_usa_o_postgres(cenario):
    c = cenario
    uid = novo_profissional(c)
    app = c.cliente.app
    app.state.servico_mei = None  # sem serviço injetado: a rota monta o de produção
    r = get(c, uid)
    assert r.status_code == 200 and r.json()["mei_status"] == "nao_informado"
    assert isinstance(app.state.servico_mei.repo, MeiPostgres)
