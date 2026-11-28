"""TERMOS-BE-REACEITE (1.4, 1.7 e 23.4): saber se há aceite pendente e registrar o aceite."""

from __future__ import annotations

from concurrent.futures import ThreadPoolExecutor
from datetime import UTC, date, datetime

import pytest
from ambiente_seg import Relogio, cab, montar
from psycopg.errors import UndefinedTable

from trato import legal
from trato.persistencia.erros import ErroPersistencia

AGORA = datetime(2026, 11, 26, 15, 0, tzinfo=UTC)
VER, ACEITAR, CONS = "/v1/me/termos", "/v1/me/termos/aceite", "/v1/me/consentimentos"


def _amb():
    return montar(Relogio(AGORA))


def _ver(amb, quem="t-cli"):
    r = amb.cliente.get(VER, headers=cab(quem))
    assert r.status_code == 200, r.text
    return r.json()


def _aceitar(amb, versao="1.1", quem="t-cli"):
    return amb.cliente.post(ACEITAR, json={"versao": versao}, headers=cab(quem))


def _linhas(amb, usuario="cli-1"):
    return list(amb.contexto.extras["lgpd"].consentimentos.historico(usuario))


def test_pendente_aceita_com_data_ip_e_repeticao_nao_duplica():
    amb = _amb()
    assert _ver(amb) == {
        "versao_vigente": "1.1",
        "vigente_desde": "2026-11-22",
        "registro_disponivel": True,
        "aceite_pendente": True,
        "versao_aceita": None,
        "aceita_em": None,
        "aceito_ip": None,
    }
    r = _aceitar(amb)
    assert r.status_code == 201, r.text
    assert r.json()["aceite_pendente"] is False and r.json()["versao_aceita"] == "1.1"
    primeira = r.json()["aceita_em"]
    amb.relogio.avancar(days=2)
    repetida = _aceitar(amb)
    assert repetida.status_code == 200 and repetida.json()["aceita_em"] == primeira
    (linha,) = _linhas(amb)
    assert (linha.finalidade, linha.versao_texto, linha.registrado_em) == (
        "termos_de_uso",
        "1.1",
        AGORA,
    )
    assert linha.ip and _ver(amb)["aceito_ip"] == linha.ip  # 1.4: o próprio usuário consulta
    assert "consentimento.registrado" in amb.auditoria
    assert _ver(amb, "t-outro")["aceite_pendente"] is True  # o aceite é de cada um


@pytest.mark.parametrize("versao", ["1.0", "1.2", "qualquer"])
def test_so_aceita_a_versao_vigente(versao):
    amb = _amb()
    r = _aceitar(amb, versao)
    assert r.status_code == 409 and "1.1" in r.text
    assert _linhas(amb) == []


def test_corpo_invalido_e_sem_login():
    amb = _amb()
    assert amb.cliente.post(ACEITAR, json={}, headers=cab("t-cli")).status_code == 422
    com_data = {"versao": "1.1", "aceita_em": "2020-01-01"}  # a data é do servidor
    assert amb.cliente.post(ACEITAR, json=com_data, headers=cab("t-cli")).status_code == 422
    assert amb.cliente.get(VER).status_code == 401
    assert amb.cliente.post(ACEITAR, json={"versao": "1.1"}).status_code == 401


def test_versao_nova_volta_a_pedir_aceite_so_a_partir_da_vigencia(monkeypatch):
    amb = _amb()
    assert _aceitar(amb).status_code == 201
    # Versão fictícia, só no teste: nada é publicado.
    nova = legal.VersaoDosTermos("9.0", date(2026, 12, 10))
    monkeypatch.setattr(legal, "VERSOES", (*legal.VERSOES, nova))
    # A rota antiga deixa gravar a versão antes de ela valer: isso não conta como aceite.
    antecipado = {"finalidade": "termos_de_uso", "aceito": True, "versao_texto": "9.0"}
    assert amb.cliente.post(CONS, json=antecipado, headers=cab("t-cli")).status_code == 201
    assert _ver(amb)["aceite_pendente"] is False and _ver(amb)["versao_vigente"] == "1.1"

    amb.relogio.agora = datetime(2026, 12, 10, 3, 0, tzinfo=UTC)  # 00:00 em Brasília
    situacao = _ver(amb)
    assert situacao["versao_vigente"] == "9.0" and situacao["aceite_pendente"] is True
    assert situacao["versao_aceita"] == "1.1"
    assert _aceitar(amb, "1.1").status_code == 409
    assert _aceitar(amb, "9.0").status_code == 201
    assert _ver(amb)["aceite_pendente"] is False


def test_aceite_pendente_nao_bloqueia_outras_rotas():
    amb = _amb()
    assert _ver(amb)["aceite_pendente"] is True
    assert amb.cliente.get(CONS, headers=cab("t-cli")).status_code == 200


def test_toques_simultaneos_gravam_uma_vez():
    amb = _amb()
    with ThreadPoolExecutor(max_workers=6) as pool:
        saidas = sorted(pool.map(lambda _: _aceitar(amb).status_code, range(6)))
    assert saidas == [200] * 5 + [201]
    assert len(_linhas(amb)) == 1


def test_sem_a_tabela_nao_quebra_e_nao_pede_aceite():
    amb = _amb()

    def sem_tabela(*_):
        raise ErroPersistencia("Erro ao acessar o banco de dados.") from UndefinedTable()

    repo = amb.contexto.extras["lgpd"].consentimentos
    repo.historico = repo.registrar = sem_tabela
    situacao = _ver(amb)
    assert situacao["registro_disponivel"] is False and situacao["aceite_pendente"] is False
    assert _aceitar(amb).status_code == 503


def test_aceitar_termos_envia_copia_por_email_com_versao_data_ip_e_texto():
    """BE-EMAIL-TERMOS-1.5: envia cópia dos Termos por e-mail ao aceitar (uma única vez)."""
    from trato.notificacoes.eventos import MODELOS, Evento

    envios: list[dict] = []

    class _NotificadorFake:
        def notificar(self, evento, usuario_id, **kwargs):
            envios.append({"evento": evento, "usuario_id": usuario_id, **kwargs})
            return ["email"]

    amb = _amb()
    amb.contexto.extras["notificador"] = _NotificadorFake()

    r = _aceitar(amb)
    assert r.status_code == 201, r.text
    assert len(envios) == 1
    e = envios[0]
    assert e["evento"] is Evento.TERMOS_ACEITOS
    assert MODELOS[Evento.TERMOS_ACEITOS].email_obrigatorio is True
    assert e["usuario_id"] == "cli-1"
    assert e["chave"] == "termos-aceite:cli-1:1.1"
    assert "1.1" in e["titulo"]
    assert "versão 1.1" in e["corpo"]
    assert "26/11/2026" in e["corpo"]
    assert "Termos de Uso" in e["corpo"] or "Versão 1.1" in e["corpo"]
    assert e["dados"]["versao"] == "1.1"

    # Repetição idempotente (200) não reenvia o e-mail
    assert _aceitar(amb).status_code == 200
    assert len(envios) == 1


def test_falha_no_envio_de_email_nao_bloqueia_aceite():
    """BE-EMAIL-TERMOS-1.5: falha de SMTP/notificador é logada e não derruba o aceite."""

    class _NotificadorQuebrado:
        def notificar(self, *_args, **_kwargs):
            raise RuntimeError("SMTP indisponível")

    amb = _amb()
    amb.contexto.extras["notificador"] = _NotificadorQuebrado()
    r = _aceitar(amb)
    assert r.status_code == 201, r.text
    assert r.json()["aceite_pendente"] is False
    assert len(_linhas(amb)) == 1


def test_consentimento_termos_de_uso_tambem_dispara_copia_por_email():
    """BE-EMAIL-TERMOS-1.5: aceite via /me/consentimentos também dispara cópia por e-mail."""
    from trato.notificacoes.eventos import Evento

    envios: list[dict] = []

    class _NotificadorFake:
        def notificar(self, evento, usuario_id, **kwargs):
            envios.append({"evento": evento, "usuario_id": usuario_id, **kwargs})
            return ["email"]

    amb = _amb()
    amb.contexto.extras["notificador"] = _NotificadorFake()
    r = amb.cliente.post(
        CONS,
        json={"finalidade": "termos_de_uso", "aceito": True, "versao_texto": "1.1"},
        headers=cab("t-cli"),
    )
    assert r.status_code == 201, r.text
    assert len(envios) == 1
    assert envios[0]["evento"] is Evento.TERMOS_ACEITOS
    assert envios[0]["dados"]["versao"] == "1.1"
