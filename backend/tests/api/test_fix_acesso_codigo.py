"""A1: limite de tentativas do código de 4 dígitos do check-in/check-out."""

from __future__ import annotations

from datetime import timedelta

from conftest import AGORA, cab

from trato.pedidos.estados import Estado, Janela
from trato.seguranca.config import ConfigSeguranca

CFG = ConfigSeguranca(_env_file=None)


def _prova_in(codigo: str) -> dict:
    return {
        "foto": {"arquivo_id": "f1", "tirada_em": (AGORA - timedelta(minutes=5)).isoformat()},
        "localizacao": {"latitude": -19.9, "longitude": -43.9},
        "codigo_inicio": codigo,
    }


def _semear(amb, **campos):
    amb.semear_pedido(
        Estado.AGENDADO,
        codigo_inicio="4321",
        janela=Janela(AGORA + timedelta(hours=1), AGORA + timedelta(hours=3)),
        **campos,
    )


def _in(amb, codigo, quem="t-prof", headers=None):
    return amb.cliente.post(
        "/v1/pedidos/ped-1/acoes/fazer_check_in",
        json={"prova": _prova_in(codigo)},
        headers={**cab(quem), **(headers or {})},
    )


def _errar_ate_bloquear(amb):
    """Erra respeitando o backoff (avança o relógio) até o limite do agendamento."""
    for n in range(CFG.codigo_max_erros_agendamento):
        r = _in(amb, f"000{n}")
        assert r.status_code == 422, (n, r.text)
        amb.relogio.avancar(seconds=CFG.codigo_backoff_teto_s // 5)  # passa a espera do backoff


def test_erros_sem_espera_respondem_422_e_o_proximo_espera(amb):
    _semear(amb)
    for n in range(CFG.codigo_erros_sem_espera + 1):
        assert _in(amb, f"900{n}").status_code == 422
    r = _in(amb, "9999")  # dentro da espera do backoff
    assert r.status_code == 429
    assert int(r.headers["Retry-After"]) >= 1


def test_backoff_libera_depois_da_espera_e_cresce(amb):
    _semear(amb)
    for n in range(CFG.codigo_erros_sem_espera + 1):
        _in(amb, f"900{n}")
    primeira = int(_in(amb, "9999").headers["Retry-After"])
    amb.relogio.avancar(seconds=primeira)
    assert _in(amb, "9998").status_code == 422  # esperou: volta a tentar
    segunda = int(_in(amb, "9997").headers["Retry-After"])
    assert segunda > primeira  # espera cresce


def test_bloqueia_o_agendamento_e_recusa_ate_o_codigo_certo(amb):
    _semear(amb)
    _errar_ate_bloquear(amb)
    r = _in(amb, "4321")
    assert r.status_code == 429
    assert amb.contexto.pedidos.obter("ped-1").estado is Estado.AGENDADO  # não começou
    amb.relogio.avancar(seconds=CFG.codigo_bloqueio_s + 1)  # bloqueio acabou
    assert _in(amb, "4321").status_code == 200


def test_cliente_nao_e_afetado_nem_o_bloqueio_vaza_para_outro_pedido(amb):
    _semear(amb)
    _errar_ate_bloquear(amb)
    assert amb.cliente.get("/v1/pedidos/ped-1", headers=cab("t-cliente")).status_code == 200
    amb.contexto.limite_codigo.checar("ped-outro", "9.9.9.9")  # outro agendamento: livre


def test_codigo_certo_zera_os_erros(amb):
    _semear(amb)
    _in(amb, "0001")
    _in(amb, "0002")
    assert _in(amb, "4321").status_code == 200
    # check-out: contador próprio do pedido recomeça do zero
    c = amb.contexto.limite_codigo
    c.checar("ped-1", "9.9.9.9")  # não levanta


def test_limite_por_ip_bloqueia_varios_agendamentos(amb):
    c = amb.contexto.limite_codigo
    from trato.seguranca.tentativas_codigo import CodigoBloqueado

    for n in range(CFG.codigo_max_erros_ip):
        c.errou(f"ped-{n}", "1.2.3.4", acao="fazer_check_in", ator_id="pro-1", dispositivo=None)
    try:
        c.checar("ped-novo", "1.2.3.4")  # pedido limpo, mas o IP estourou
    except CodigoBloqueado as erro:
        assert erro.retry_apos_s > 0
    else:
        raise AssertionError("o IP deveria estar bloqueado")
    c.checar("ped-novo", "5.6.7.8")  # outro IP segue livre


def test_erros_e_bloqueio_vao_para_a_auditoria_com_ip_e_dispositivo(amb):
    _semear(amb)
    _errar_ate_bloquear(amb)
    eventos = amb.contexto.limite_codigo.auditoria_em_memoria.eventos
    acoes = [e["acao"] for e in eventos]
    assert acoes.count("checkin.codigo_incorreto") == CFG.codigo_max_erros_agendamento
    assert acoes.count("checkin.codigo_bloqueado") == 1
    erro = eventos[0]
    assert erro["ator_id"] == "pro-1" and erro["entidade_id"] == "ped-1"
    assert erro["ip"]
    assert "codigo" not in str(erro["depois"]).replace("codigo_", "")  # nunca o código informado


def test_dispositivo_do_cabecalho_vai_para_a_auditoria(amb):
    _semear(amb)
    _in(amb, "0001", headers={"X-Dispositivo-Id": "aparelho-xyz"})
    evento = amb.contexto.limite_codigo.auditoria_em_memoria.eventos[0]
    assert evento["dispositivo"] == "aparelho-xyz"


def test_limites_vem_da_configuracao_nao_do_codigo(monkeypatch):
    cfg = ConfigSeguranca(_env_file=None, codigo_max_erros_agendamento=2, codigo_bloqueio_s=60)
    assert cfg.codigo_max_erros_agendamento == 2 and cfg.codigo_bloqueio_s == 60
    monkeypatch.setenv("TRATO_SEG_CODIGO_MAX_ERROS_IP", "7")
    assert ConfigSeguranca(_env_file=None).codigo_max_erros_ip == 7
