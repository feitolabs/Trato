import hashlib
import hmac
import json

from conftest import AGORA, SEGREDO_WEBHOOK

URL = "/v1/webhooks/stripe"


def assinar(corpo: bytes, segredo: str = SEGREDO_WEBHOOK, t: int | None = None) -> str:
    t = int(AGORA.timestamp()) if t is None else t
    v1 = hmac.new(segredo.encode(), f"{t}.".encode() + corpo, hashlib.sha256).hexdigest()
    return f"t={t},v1={v1}"


def evento(id_="evt_1", tipo="payment_intent.succeeded") -> bytes:
    return json.dumps({"id": id_, "type": tipo, "data": {"object": {"amount": 30000}}}).encode()


def enviar(amb, corpo: bytes, cabecalho: str | None):
    cabs = {"Stripe-Signature": cabecalho} if cabecalho else {}
    return amb.cliente.post(URL, content=corpo, headers=cabs)


def test_evento_assinado_e_guardado(amb):
    corpo = evento(tipo="customer.created")  # tipo sem manipulador: guardado, sem efeito

    r = enviar(amb, corpo, assinar(corpo))

    assert r.status_code == 200
    assert r.json() == {"recebido": True, "duplicado": False, "tratado": False}
    guardado = amb.contexto.eventos_webhook.listar()
    assert [(e.provedor, e.evento_id, e.tipo) for e in guardado] == [
        ("stripe", "evt_1", "customer.created")
    ]


def test_manipulador_roda_uma_vez_mesmo_com_reenvio(amb):
    chamadas = []
    amb.contexto.manipuladores_webhook["payment_intent.succeeded"] = lambda ev, ctx: (
        chamadas.append(ev.evento_id)
    )
    corpo = evento()
    cabecalho = assinar(corpo)

    primeiro = enviar(amb, corpo, cabecalho)
    segundo = enviar(amb, corpo, cabecalho)

    assert primeiro.json() == {"recebido": True, "duplicado": False, "tratado": True}
    assert segundo.status_code == 200
    assert segundo.json()["duplicado"] is True
    assert chamadas == ["evt_1"]
    assert len(amb.contexto.eventos_webhook.listar()) == 1


def test_eventos_diferentes_rodam_cada_um(amb):
    chamadas = []
    amb.contexto.manipuladores_webhook["payment_intent.succeeded"] = lambda ev, ctx: (
        chamadas.append(ev.evento_id)
    )

    for id_ in ("evt_a", "evt_b"):
        corpo = evento(id_)
        assert enviar(amb, corpo, assinar(corpo)).status_code == 200

    assert chamadas == ["evt_a", "evt_b"]


def test_falha_no_manipulador_libera_para_novo_envio(amb):
    estado = {"falhar": True, "ok": 0}

    def manipulador(ev, ctx):
        if estado["falhar"]:
            raise RuntimeError("banco fora do ar")
        estado["ok"] += 1

    amb.contexto.manipuladores_webhook["payment_intent.succeeded"] = manipulador
    corpo = evento()
    cabecalho = assinar(corpo)

    try:
        enviar(amb, corpo, cabecalho)
    except RuntimeError:
        pass  # TestClient repassa a exceção do servidor
    estado["falhar"] = False
    r = enviar(amb, corpo, cabecalho)

    assert r.status_code == 200 and r.json()["duplicado"] is False
    assert estado["ok"] == 1


def test_assinatura_errada_da_400_e_nao_processa(amb):
    corpo = evento()

    r = enviar(amb, corpo, assinar(corpo, segredo="outro-segredo-qualquer"))

    assert r.status_code == 400
    assert amb.contexto.eventos_webhook.listar() == ()


def test_sem_cabecalho_da_400(amb):
    assert enviar(amb, evento(), None).status_code == 400


def test_corpo_adulterado_da_400(amb):
    corpo = evento()
    cabecalho = assinar(corpo)

    assert enviar(amb, corpo.replace(b"30000", b"90000"), cabecalho).status_code == 400


def test_assinatura_velha_da_400(amb):
    corpo = evento()

    r = enviar(amb, corpo, assinar(corpo, t=int(AGORA.timestamp()) - 3600))

    assert r.status_code == 400


def test_segredo_nao_configurado_da_503(amb):
    amb.contexto.segredo_webhook = lambda: ""
    corpo = evento()

    assert enviar(amb, corpo, assinar(corpo)).status_code == 503


def test_json_invalido_ou_sem_id_da_400(amb):
    for corpo in (b"nao e json", b'{"type": "x"}', b"[]"):
        assert enviar(amb, corpo, assinar(corpo)).status_code == 400
