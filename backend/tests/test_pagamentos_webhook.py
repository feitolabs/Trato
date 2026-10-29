import hashlib
import hmac

import pytest

from trato.pagamentos.idempotencia import RegistroEventosEmMemoria, processar_uma_vez
from trato.pagamentos.webhook import (
    AssinaturaExpirada,
    AssinaturaInvalida,
    verificar_assinatura,
)

SEGREDO = "whsec_valor_falso_de_teste"  # verificar: ignorar
PAYLOAD = b'{"id":"evt_1","type":"payment_intent.succeeded"}'
AGORA = 1_800_000_000


def assinar(payload: bytes, carimbo: int, segredo: str = SEGREDO) -> str:
    return hmac.new(segredo.encode(), f"{carimbo}.".encode() + payload, hashlib.sha256).hexdigest()


def cabecalho(carimbo: int = AGORA, assinatura: str | None = None) -> str:
    return f"t={carimbo},v1={assinatura or assinar(PAYLOAD, carimbo)}"


def test_assinatura_valida_devolve_carimbo():
    assert verificar_assinatura(PAYLOAD, cabecalho(), SEGREDO, agora=AGORA) == AGORA


def test_aceita_varias_v1_e_outras_versoes():
    boa = assinar(PAYLOAD, AGORA)
    texto = f"t={AGORA},v1={'0' * 64},v0=abc,v1={boa}"
    assert verificar_assinatura(PAYLOAD, texto, SEGREDO, agora=AGORA) == AGORA


def test_payload_adulterado_e_recusado():
    with pytest.raises(AssinaturaInvalida):
        verificar_assinatura(PAYLOAD + b" ", cabecalho(), SEGREDO, agora=AGORA)


def test_segredo_errado_e_recusado():
    with pytest.raises(AssinaturaInvalida):
        verificar_assinatura(PAYLOAD, cabecalho(), "outro_segredo_falso", agora=AGORA)


def test_assinatura_errada_e_recusada():
    with pytest.raises(AssinaturaInvalida):
        verificar_assinatura(PAYLOAD, cabecalho(assinatura="0" * 64), SEGREDO, agora=AGORA)


def test_assinatura_expirada():
    with pytest.raises(AssinaturaExpirada):
        verificar_assinatura(PAYLOAD, cabecalho(), SEGREDO, agora=AGORA + 301)


def test_dentro_da_tolerancia_configuravel():
    assert verificar_assinatura(
        PAYLOAD, cabecalho(), SEGREDO, tolerancia_segundos=600, agora=AGORA + 600
    )
    with pytest.raises(AssinaturaExpirada):
        verificar_assinatura(
            PAYLOAD, cabecalho(), SEGREDO, tolerancia_segundos=10, agora=AGORA + 11
        )


def test_carimbo_no_futuro_alem_da_tolerancia_e_recusado():
    with pytest.raises(AssinaturaExpirada):
        verificar_assinatura(PAYLOAD, cabecalho(), SEGREDO, agora=AGORA - 301)


def test_expirada_com_assinatura_errada_e_invalida_comum():
    with pytest.raises(AssinaturaInvalida) as erro:
        verificar_assinatura(PAYLOAD, cabecalho(assinatura="0" * 64), SEGREDO, agora=AGORA + 9_999)
    assert not isinstance(erro.value, AssinaturaExpirada)


@pytest.mark.parametrize("texto", [None, "", "lixo", "t=abc,v1=x", f"t={AGORA}", "v1=abc"])
def test_cabecalho_ausente_ou_malformado(texto):
    with pytest.raises(AssinaturaInvalida):
        verificar_assinatura(PAYLOAD, texto, SEGREDO, agora=AGORA)


def test_segredo_vazio_e_recusado():
    with pytest.raises(AssinaturaInvalida):
        verificar_assinatura(PAYLOAD, cabecalho(), "", agora=AGORA)


def test_segredo_em_bytes():
    assert verificar_assinatura(PAYLOAD, cabecalho(), SEGREDO.encode(), agora=AGORA)


def test_mesmo_evento_nao_processa_duas_vezes():
    registro = RegistroEventosEmMemoria()
    chamadas = []

    primeira = processar_uma_vez(registro, "stripe:evt_1", lambda: chamadas.append(1) or "ok")
    segunda = processar_uma_vez(registro, "stripe:evt_1", lambda: chamadas.append(2) or "ok")

    assert primeira == (True, "ok")
    assert segunda == (False, None)
    assert chamadas == [1]
    assert registro.foi_processada("stripe:evt_1")


def test_eventos_diferentes_sao_independentes():
    registro = RegistroEventosEmMemoria()
    assert processar_uma_vez(registro, "stripe:evt_1", lambda: 1)[0]
    assert processar_uma_vez(registro, "stripe:evt_2", lambda: 2)[0]


def test_falha_libera_a_chave_para_nova_tentativa():
    registro = RegistroEventosEmMemoria()

    def quebra():
        raise RuntimeError("falhou")

    with pytest.raises(RuntimeError):
        processar_uma_vez(registro, "stripe:evt_1", quebra)

    assert not registro.foi_processada("stripe:evt_1")
    assert processar_uma_vez(registro, "stripe:evt_1", lambda: "ok") == (True, "ok")


def test_evento_em_processamento_nao_entra_de_novo():
    registro = RegistroEventosEmMemoria()
    assert registro.iniciar("stripe:evt_1")
    assert not registro.iniciar("stripe:evt_1")


def test_chave_vazia_e_recusada():
    with pytest.raises(ValueError):
        RegistroEventosEmMemoria().iniciar("")
