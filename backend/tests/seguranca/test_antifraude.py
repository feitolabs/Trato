"""F8.2: SMS pumping, conta duplicada, contorno da plataforma e flags (só revisão humana)."""

from __future__ import annotations

from ambiente_seg import CLIENTE, EQUIPE, Relogio, cab, montar

from trato.api.memoria_app import ConversasEmMemoria
from trato.seguranca.contorno import avaliar_contorno
from trato.seguranca.conversas import ConversasVigiadas
from trato.seguranca.duplicidade import DetectorDuplicidade, IdentificadoresEmMemoria
from trato.seguranca.sms import ProtecaoSms, normalizar_telefone

TEL = "+55 11 98765-4321"


def sms(**config):
    amb = montar(**config)
    return amb, ProtecaoSms(amb.seg)


def test_telefone_e_normalizado_e_estrangeiro_e_negado():
    assert normalizar_telefone("+55 (11) 98765-4321") == "5511987654321"
    assert normalizar_telefone("12") is None
    _, p = sms()
    d = p.autorizar("+1 415 555 0100")
    assert not d.permitido and d.motivo == "pais_nao_permitido"
    assert not p.autorizar("abc").permitido


def test_primeiro_envio_passa_e_reenvio_rapido_espera_backoff():
    amb, p = sms(sms_backoff_base_s=30, sms_backoff_fator=2.0)
    assert p.autorizar(TEL, "disp-1", "1.1.1.1").permitido
    d = p.autorizar(TEL, "disp-1", "1.1.1.1")
    assert not d.permitido and d.motivo == "reenvio_muito_rapido"
    assert 0 < d.retry_apos_s <= 31
    amb.relogio.avancar(seconds=31)
    assert p.autorizar(TEL, "disp-1", "1.1.1.1").permitido
    amb.relogio.avancar(seconds=31)  # o segundo intervalo é 60 s
    assert p.autorizar(TEL, "disp-1", "1.1.1.1").motivo == "reenvio_muito_rapido"


def test_limite_por_numero_por_hora_vem_da_configuracao():
    amb, p = sms(sms_backoff_base_s=0, sms_max_por_numero_hora=2, sms_max_por_numero_dia=9)
    assert p.autorizar(TEL).permitido
    assert p.autorizar(TEL).permitido
    d = p.autorizar(TEL)
    assert not d.permitido and d.motivo == "limite_por_numero"
    assert d.retry_apos_s > 0
    amb.relogio.avancar(hours=2)
    assert p.autorizar(TEL).permitido


def test_estourar_limite_do_dispositivo_bloqueia_e_abre_flag():
    amb, p = sms(
        sms_backoff_base_s=0, sms_max_por_dispositivo_dia=2, sms_max_numeros_por_dispositivo_dia=9
    )
    assert p.autorizar("+5511911110001", "disp-x").permitido
    assert p.autorizar("+5511911110002", "disp-x").permitido
    d = p.autorizar("+5511911110003", "disp-x")
    assert d.motivo == "limite_por_dispositivo" and d.retry_apos_s >= 3600
    # bloqueio temporário: nem um número novo passa naquele aparelho
    assert p.autorizar("+5511911110004", "disp-x").motivo == "bloqueio_temporario"
    assert "antifraude.sms_bloqueio_temporario" in amb.auditoria
    flags = amb.seg.flags.listar("aberta")
    assert [f.tipo for f in flags] == ["sms_pumping"]
    # nada de dado pessoal na flag nem na auditoria
    assert "5511911110003" not in repr(flags) + repr(amb.seg.auditoria_em_memoria.eventos)
    # e o bloqueio expira sozinho
    amb.relogio.avancar(hours=25)
    assert p.autorizar("+5511911110005", "disp-x").permitido


def test_muitos_numeros_no_mesmo_aparelho():
    _, p = sms(sms_backoff_base_s=0, sms_max_numeros_por_dispositivo_dia=2)
    assert p.autorizar("+5511911110001", "d").permitido
    assert p.autorizar("+5511911110002", "d").permitido
    assert p.autorizar("+5511911110003", "d").motivo == "muitos_numeros_no_dispositivo"


def test_faixa_de_numeros_vizinhos_e_limitada():
    _, p = sms(sms_backoff_base_s=0, sms_max_por_faixa_hora=3, sms_faixa_digitos=10)
    for fim in range(3):
        assert p.autorizar(f"+55119876543{fim}0".replace("+5511", "+5511"), None, f"9.9.9.{fim}")
    d = p.autorizar("+5511987654399", None, "9.9.9.9")
    assert d.motivo in ("limite_por_faixa", "bloqueio_temporario")


def test_limite_por_ip():
    _, p = sms(sms_backoff_base_s=0, sms_max_por_ip_hora=2)
    assert p.autorizar("+5511911110001", None, "2.2.2.2").permitido
    assert p.autorizar("+5511922220002", None, "2.2.2.2").permitido
    assert p.autorizar("+5511933330003", None, "2.2.2.2").motivo == "limite_por_ip"
    assert p.autorizar("+5511933330003", None, "3.3.3.3").permitido


def test_rota_do_hook_exige_segredo():
    desligado = montar()
    assert (
        desligado.cliente.post("/v1/seguranca/sms/autorizar", json={"telefone": TEL}).status_code
        == 503
    )

    amb = montar(sms_hook_segredo="segredo-de-teste")
    url = "/v1/seguranca/sms/autorizar"
    assert amb.cliente.post(url, json={"telefone": TEL}).status_code == 401
    assert (
        amb.cliente.post(
            url, json={"telefone": TEL}, headers={"X-Hook-Segredo": "errado"}
        ).status_code
        == 401
    )
    r = amb.cliente.post(
        url, json={"telefone": TEL}, headers={"X-Hook-Segredo": "segredo-de-teste"}
    )
    assert r.status_code == 200 and r.json()["permitido"] is True
    r = amb.cliente.post(
        url, json={"telefone": TEL}, headers={"X-Hook-Segredo": "segredo-de-teste"}
    )
    assert r.json()["permitido"] is False


# --- Conta duplicada -------------------------------------------------------------------


def detector(**config):
    amb = montar(**config)
    return amb, DetectorDuplicidade(amb.seg, IdentificadoresEmMemoria())


def test_mesmo_cpf_com_formatos_diferentes_abre_flag_alta():
    amb, d = detector()
    assert d.verificar("u1", cpf="123.456.789-09") == []
    abertas = d.verificar("u2", cpf="12345678909")
    assert [f.severidade for f in abertas] == ["alta"] and abertas[0].tipo == "conta_duplicada"
    assert abertas[0].detalhes["outras_contas"] == ["u1"]
    assert "12345678909" not in repr(amb.seg.auditoria_em_memoria.eventos)
    # não duplica a flag para a mesma conta
    assert d.verificar("u2", cpf="123.456.789-09") == []


def test_mesmo_telefone_ignora_ddi_e_formatacao():
    _, d = detector()
    d.verificar("u1", telefone="+55 11 98765-4321")
    assert len(d.verificar("u2", telefone="(11) 98765-4321")) == 1


def test_dispositivo_compartilhado_so_acima_do_limite():
    _, d = detector(max_contas_por_dispositivo=2)
    assert d.verificar("u1", dispositivo="aparelho-1") == []
    assert d.verificar("u2", dispositivo="aparelho-1") == []  # 2 contas ainda pode (família)
    flags = d.verificar("u3", dispositivo="aparelho-1")
    assert [f.severidade for f in flags] == ["media"]


def test_rota_de_identificadores_nao_revela_duplicidade():
    amb = montar()
    corpo = {"cpf": "123.456.789-09"}
    a = amb.cliente.post("/v1/seguranca/identificadores", json=corpo, headers=cab("t-cli"))
    b = amb.cliente.post("/v1/seguranca/identificadores", json=corpo, headers=cab("t-outro"))
    assert a.status_code == b.status_code == 204 and b.content == b""
    assert len(amb.seg.flags.listar("aberta")) == 1
    assert amb.cliente.post("/v1/seguranca/identificadores", json=corpo).status_code == 401


# --- Contorno da plataforma ------------------------------------------------------------


def test_sinais_de_contorno():
    cfg = montar().seg.config
    assert avaliar_contorno(
        "vamos fechar por fora, sem a taxa, me passa seu zap", frozenset(), cfg
    ).sinalizar
    assert avaliar_contorno("paga direto no pix pra mim", frozenset(), cfg).pontuacao == 2
    assert not avaliar_contorno(
        "Combinado, chego às 9h com o material.", frozenset(), cfg
    ).sinalizar
    assert not avaliar_contorno("tenho zap, mas prefiro o chat daqui", frozenset(), cfg).sinalizar
    # contato escondido pelo mascaramento soma pontos
    assert avaliar_contorno("meu zap", frozenset({"telefone"}), cfg).sinalizar


def _conversas(amb, contratado=False):
    inner = ConversasEmMemoria(contratado=lambda _p: contratado)
    return ConversasVigiadas(inner, amb.seg), inner.abrir("ped-1", "pro-1")


def test_contorno_abre_flag_mas_nao_bloqueia_a_mensagem():
    amb = montar()
    conversas, conv = _conversas(amb)
    nova = conversas.enviar(conv, "pro-1", "vamos por fora, sem taxa? meu zap 11 98765-4321")
    assert conversas.listar(conv)[0].id == nova  # a mensagem foi gravada
    assert conversas.listar(conv)[0].mascarada
    (flag,) = amb.seg.flags.listar("aberta")
    assert flag.tipo == "contorno_plataforma" and flag.usuario_id == "pro-1"
    assert "antifraude.contorno_plataforma" in amb.auditoria
    assert "98765" not in repr(flag) + repr(amb.seg.auditoria_em_memoria.eventos)
    # segunda tentativa soma na mesma flag
    conversas.enviar(conv, "pro-1", "paga direto por fora")
    (flag,) = amb.seg.flags.listar("aberta")
    assert flag.detalhes["ocorrencias"] == 2


def test_conversa_normal_nao_gera_flag():
    amb = montar()
    conversas, conv = _conversas(amb)
    conversas.enviar(conv, "pro-1", "Posso passar amanhã às 14h para ver o ponto de luz.")
    assert amb.seg.flags.listar() == ()


def test_falha_do_antifraude_nao_impede_a_mensagem():
    amb = montar()
    conversas, conv = _conversas(amb)
    amb.seg.flags = None  # força erro dentro da avaliação
    assert conversas.enviar(conv, "pro-1", "por fora, sem taxa, no zap") > 0


# --- Revisão humana --------------------------------------------------------------------


def test_equipe_revisa_flag_e_nada_e_suspenso():
    amb = montar()
    amb.seg.abrir_flag("contorno_plataforma", "media", ("canal_externo",), usuario_id=CLIENTE.id)
    assert amb.cliente.get("/v1/seguranca/flags", headers=cab("t-cli")).status_code == 403
    lista = amb.cliente.get("/v1/seguranca/flags", headers=cab("t-equipe")).json()
    assert len(lista) == 1 and lista[0]["status"] == "aberta"
    r = amb.cliente.post(
        f"/v1/seguranca/flags/{lista[0]['id']}/revisao",
        json={"decisao": "descartar", "nota": "falso positivo"},
        headers=cab("t-equipe"),
    )
    assert r.status_code == 200 and r.json()["status"] == "descartada"
    assert r.json()["revisada_por"] == EQUIPE.id
    assert amb.cliente.get("/v1/seguranca/flags", headers=cab("t-equipe")).json() == []
    assert "antifraude.flag_revisada" in amb.auditoria
    assert (
        amb.cliente.post(
            "/v1/seguranca/flags/nao-existe/revisao",
            json={"decisao": "confirmar"},
            headers=cab("t-equipe"),
        ).status_code
        == 404
    )
    # o usuário continua usando o app normalmente
    assert amb.cliente.get("/v1/me", headers=cab("t-cli")).status_code in (200, 404)


def test_relogio_e_independente_por_ambiente():
    a, b = montar(Relogio()), montar(Relogio())
    a.seg.contadores.adicionar("k")
    assert b.seg.contadores.quantos("k", 60) == 0
