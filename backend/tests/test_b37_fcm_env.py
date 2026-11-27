"""B37: credencial FCM via TRATO_NOTIF_FCM_CREDENCIAIS_JSON (JSON cru, base64 e erro seguro)."""

from __future__ import annotations

import base64
import json
import logging
from pathlib import Path

import pytest
from pydantic import SecretStr

from trato.notificacoes.canais import canais_da_config
from trato.notificacoes.config import ConfigNotificacoes

_CONTA_FAKE = {
    "client_email": "fcm-bot@trato-test.iam.gserviceaccount.com",
    "private_key": "-----BEGIN "
    + "PRIVATE KEY-----\nCHAVE-EXEMPLO-TESTE\n-----END PRIVATE KEY-----\n",
    "token_uri": "https://oauth2.googleapis.com/token",
}


def test_fcm_carrega_de_env_json_cru(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setenv("TRATO_NOTIF_PUSH_ATIVO", "true")
    monkeypatch.setenv("TRATO_NOTIF_FCM_PROJETO_ID", "proj-fly")
    monkeypatch.setenv("TRATO_NOTIF_FCM_CREDENCIAIS_JSON", json.dumps(_CONTA_FAKE))
    monkeypatch.delenv("TRATO_NOTIF_FCM_CREDENCIAIS_ARQUIVO", raising=False)

    cfg = ConfigNotificacoes(_env_file=None)  # type: ignore[call-arg]
    canais = canais_da_config(cfg)
    assert canais.push is not None and canais.push.disponivel
    # SecretStr não expõe conteúdo no repr
    assert "CHAVE-EXEMPLO-TESTE" not in repr(cfg)


def test_fcm_carrega_de_env_base64(monkeypatch: pytest.MonkeyPatch) -> None:
    b64 = base64.b64encode(json.dumps(_CONTA_FAKE).encode("utf-8")).decode("ascii")
    # Quebras de linha comuns em segredos colados no Fly.io também devem funcionar
    b64_com_quebra = f"{b64[:40]}\n{b64[40:]}\n"
    monkeypatch.setenv("TRATO_NOTIF_PUSH_ATIVO", "true")
    monkeypatch.setenv("TRATO_NOTIF_FCM_PROJETO_ID", "proj-fly")
    monkeypatch.setenv("TRATO_NOTIF_FCM_CREDENCIAIS_JSON", b64_com_quebra)
    monkeypatch.delenv("TRATO_NOTIF_FCM_CREDENCIAIS_ARQUIVO", raising=False)

    cfg = ConfigNotificacoes(_env_file=None)  # type: ignore[call-arg]
    canais = canais_da_config(cfg)
    assert canais.push is not None and canais.push.disponivel


def test_fcm_mantem_compatibilidade_com_arquivo(tmp_path: Path) -> None:
    arq = tmp_path / "fcm.json"
    arq.write_text(json.dumps(_CONTA_FAKE), encoding="utf-8")
    cfg = ConfigNotificacoes(
        _env_file=None,  # type: ignore[call-arg]
        push_ativo=True,
        fcm_projeto_id="proj-arq",
        fcm_credenciais_arquivo=str(arq),
    )
    canais = canais_da_config(cfg)
    assert canais.push is not None and canais.push.disponivel


@pytest.mark.parametrize(
    "valor_invalido",
    [
        "SEGREDO_MUITO_SENSIVEL_NAO_VAZAR_12345",
        base64.b64encode(b"nao-e-json-SEGREDO_SENSIVEL_999").decode("ascii"),
        json.dumps(["lista", "SEGREDO_SENSIVEL_888"]),
        json.dumps({"client_email": "so-email@x.iam.gserviceaccount.com"}),
        json.dumps({"private_key": "SEGREDO_SEM_EMAIL_777"}),
    ],
)
def test_fcm_invalido_desliga_canal_sem_vazar_segredo(
    caplog: pytest.LogCaptureFixture, valor_invalido: str
) -> None:
    with caplog.at_level(logging.DEBUG):
        cfg = ConfigNotificacoes(
            _env_file=None,  # type: ignore[call-arg]
            push_ativo=True,
            fcm_projeto_id="proj-fly",
            fcm_credenciais_json=SecretStr(valor_invalido),
        )
        canais = canais_da_config(cfg)

    assert canais.push is not None and not canais.push.disponivel
    assert "SEGREDO" not in caplog.text
    assert "SEGREDO" not in repr(cfg)
