"""BE-INATIVO-4.9 (Termos 4.9): inativação após aviso prévio >= 30 dias e reativação gratuita."""

# ruff: noqa: F811

from __future__ import annotations

from datetime import timedelta
from types import SimpleNamespace

from admin_ambiente import CLIENTE, adm, cab  # noqa: F401

from trato.api.admin.repositorios import FiltroAuditoria
from trato.api.auth import PapelUsuario
from trato.api.auth_supabase import ProvedorAuthSupabase
from trato.financeiro import periodo


class _NotificadorFake:
    def notificar(self, *_args, **_kwargs):
        return ["ok"]


def _ligar_notificador(adm) -> None:
    adm.contexto.extras["notificador"] = _NotificadorFake()
    adm.contexto.usuarios.atualizar_nome(CLIENTE.id, "Maria Cliente")


def _enviar_aviso_inatividade(adm, dias: int = 30, ref: str = "inat-cli-1"):
    vigencia = (
        adm.relogio().astimezone(periodo.BRASILIA).date() + timedelta(days=dias)
    ).isoformat()
    return adm.cliente.post(
        "/v1/admin/avisos-previos",
        json={
            "tipo": "inatividade",
            "referencia": ref,
            "vigencia": vigencia,
            "usuario_id": CLIENTE.id,
        },
        headers=cab("t-administrador"),
    )


def test_inativar_recusado_sem_aviso_previo_e_antes_de_30_dias(adm):
    _ligar_notificador(adm)
    # Sem aviso prévio -> 409
    r0 = adm.cliente.post(
        f"/v1/admin/usuarios/{CLIENTE.id}/inativar",
        json={"motivo": "Conta sem uso há mais de um ano."},
        headers=cab("t-administrador"),
    )
    assert r0.status_code == 409, r0.text

    # Envia aviso prévio com vigência em 30 dias e grava entidade_id + usuario_id na auditoria
    av = _enviar_aviso_inatividade(adm, dias=30)
    assert av.status_code == 200, av.text
    entradas, _ = adm.admin.auditoria.listar(
        FiltroAuditoria(entidade="aviso_previo", entidade_id=CLIENTE.id), 10, 0
    )
    assert len(entradas) == 1
    assert entradas[0].depois["usuario_id"] == CLIENTE.id

    # Com apenas 29 dias -> ainda recusado (409)
    adm.relogio.avancar(days=29)
    r29 = adm.cliente.post(
        f"/v1/admin/usuarios/{CLIENTE.id}/inativar",
        json={"motivo": "Tentativa antes de completar 30 dias."},
        headers=cab("t-administrador"),
    )
    assert r29.status_code == 409, r29.text


def test_inativar_apos_30_dias_bloqueia_uso_normal_e_reativacao_admin_funciona(adm):
    _ligar_notificador(adm)
    assert _enviar_aviso_inatividade(adm, dias=30).status_code == 200
    adm.relogio.avancar(days=30)

    # Inativa sem criar medida punitiva
    r = adm.cliente.post(
        f"/v1/admin/usuarios/{CLIENTE.id}/inativar",
        json={"motivo": "Prazo de 30 dias do aviso prévio cumprido."},
        headers=cab("t-administrador"),
    )
    assert r.status_code == 200, r.text
    assert r.json()["status"] == "inativo"
    assert adm.contexto.medidas.listar(CLIENTE.id, None, 20, 0)[0] == []

    # Filtro GET /v1/admin/usuarios?status=inativo encontra o usuário
    busca = adm.cliente.get(
        "/v1/admin/usuarios", params={"status": "inativo"}, headers=cab("t-administrador")
    )
    assert busca.status_code == 200, busca.text
    assert [u["id"] for u in busca.json()["itens"]] == [CLIENTE.id]

    # Conta inativa não usa rotas normais (403 conta_inativa)
    bloqueado = adm.cliente.get("/v1/me/moedas", headers=cab("t-cliente"))
    assert bloqueado.status_code == 403, bloqueado.text
    assert bloqueado.json()["codigo"] == "conta_inativa"

    # Reativação pelo admin funciona gratuitamente e audita
    reat = adm.cliente.post(
        f"/v1/admin/usuarios/{CLIENTE.id}/reativar",
        json={"motivo": "Cliente solicitou reativação pelo suporte."},
        headers=cab("t-administrador"),
    )
    assert reat.status_code == 200, reat.text
    assert reat.json()["status"] == "ativo"
    assert adm.cliente.get("/v1/me/moedas", headers=cab("t-cliente")).status_code == 200

    aud_in, _ = adm.admin.auditoria.listar(FiltroAuditoria(acao="usuario.inativar"), 10, 0)
    aud_re, _ = adm.admin.auditoria.listar(FiltroAuditoria(acao="usuario.reativar"), 10, 0)
    assert len(aud_in) == 1 and len(aud_re) == 1


def test_reativacao_pelo_proprio_usuario_funciona_e_bloqueado_continua_barrado(adm):
    _ligar_notificador(adm)
    assert _enviar_aviso_inatividade(adm, dias=30).status_code == 200
    adm.relogio.avancar(days=30)
    assert (
        adm.cliente.post(
            f"/v1/admin/usuarios/{CLIENTE.id}/inativar",
            json={"motivo": "Inativação após aviso prévio de 30 dias."},
            headers=cab("t-administrador"),
        ).status_code
        == 200
    )

    # Rota normal bloqueada com 403 conta_inativa
    assert adm.cliente.get("/v1/me/moedas", headers=cab("t-cliente")).status_code == 403

    # Próprio usuário reativa em POST /v1/me/reativar
    r = adm.cliente.post("/v1/me/reativar", headers=cab("t-cliente"))
    assert r.status_code == 200, r.text
    assert r.json() == {"usuario_id": CLIENTE.id, "status": "ativo", "reativada": True}

    # Após reativar, volta a acessar rotas normais
    assert adm.cliente.get("/v1/me/moedas", headers=cab("t-cliente")).status_code == 200

    # Conta bloqueada (punitiva) NÃO pode usar /v1/me/reativar (403 conta_bloqueada)
    adm.contexto.auth.bloqueados.add("t-cliente")
    r_bloq = adm.cliente.post("/v1/me/reativar", headers=cab("t-cliente"))
    assert r_bloq.status_code == 403, r_bloq.text
    assert r_bloq.json()["codigo"] == "conta_bloqueada"


def test_auth_supabase_trata_status_inativo():
    class _UsuariosFake:
        def perfil(self, sub: str):
            return SimpleNamespace(id=sub, papel=PapelUsuario.CLIENTE, status="inativo")

    auth = ProvedorAuthSupabase(_UsuariosFake(), segredo_hs256=lambda: "s")  # type: ignore[arg-type]
    auth._decodificar = lambda _tok: {"sub": "u-inat"}  # type: ignore[method-assign]
    assert auth.autenticar("tok") is None
    assert auth.conta_inativa("tok") is True
    assert auth.conta_bloqueada("tok") is False
    suporte = auth.autenticar_para_suporte("tok")
    assert suporte is not None and suporte.id == "u-inat"
