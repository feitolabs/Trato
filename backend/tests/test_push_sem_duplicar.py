"""BUG-C17: push em dobro. Tag que substitui na bandeja, falha isolada por aparelho e reenvio
só depois da idade mínima. Tudo em memória, com transporte falso (nenhum provedor real)."""

from __future__ import annotations

import threading
from datetime import UTC, datetime, timedelta

import pytest
from pydantic import ValidationError

from trato.notificacoes.canais import (
    Canais,
    CanalApp,
    FalhaEnvio,
    Mensagem,
    PushApns,
    PushFcm,
    PushPorPlataforma,
    tag_do_push,
)
from trato.notificacoes.config import ConfigNotificacoes
from trato.notificacoes.eventos import Evento
from trato.notificacoes.repositorio import RepositorioEmMemoria
from trato.notificacoes.servico import ServicoNotificacoes

T0 = datetime(2026, 11, 25, 9, 0, tzinfo=UTC)
ANA = "ana"
A, B = "token-aparelho-A", "token-aparelho-B"


def cfg(**campos) -> ConfigNotificacoes:
    return ConfigNotificacoes(
        _env_file=None,
        push_ativo=True,
        fcm_projeto_id="proj",
        apns_ativo=True,
        apns_bundle_id="br.com.trato",
        apns_chave_id="K1",
        **campos,
    )


class Provedor:
    """Transporte falso: responde o status combinado por token e guarda o que recebeu."""

    def __init__(self) -> None:
        self.status: dict[str, int] = {}
        self.sem_rede: set[str] = set()
        self.chamadas: list[tuple[str, dict, dict]] = []  # (token, cabeçalhos, corpo)
        self.durante = None

    def __call__(self, url: str, cab: dict, corpo: dict) -> int:
        token = corpo["message"]["token"] if "message" in corpo else url.rsplit("/", 1)[-1]
        self.chamadas.append((token, cab, corpo))
        if self.durante is not None:
            gancho, self.durante = self.durante, None
            gancho()
        if token in self.sem_rede:
            raise FalhaEnvio("Falha de rede ao enviar push.")
        return self.status.get(token, 200)

    @property
    def tokens(self) -> list[str]:
        return [c[0] for c in self.chamadas]


class Relogio:
    def __init__(self) -> None:
        self.agora = T0

    def __call__(self) -> datetime:
        return self.agora


@pytest.fixture
def provedor() -> Provedor:
    return Provedor()


@pytest.fixture
def relogio() -> Relogio:
    return Relogio()


def montar(provedor, relogio, *tokens, canal=None, **campos) -> ServicoNotificacoes:
    config = cfg(**campos)
    canal = canal or PushFcm(config, provedor, lambda: "t")
    s = ServicoNotificacoes(
        RepositorioEmMemoria(), Canais(CanalApp(), canal, None), config, relogio
    )
    for token in tokens:
        s.repo.registrar_dispositivo(ANA, token, "android", T0)
    return s


def mensagem(s: ServicoNotificacoes, n: int = 1, conversa: str = "cv-1"):
    return s.notificar(
        Evento.MENSAGEM_NOVA, ANA, chave=f"{conversa}:{n}", dados={"conversa_id": conversa}
    )


def pendentes(s: ServicoNotificacoes) -> int:
    return len(s.repo.pendentes(T0 - timedelta(days=1), 50))


def passar_idade_minima(s: ServicoNotificacoes, relogio: Relogio) -> None:
    relogio.agora += s.config.reenvio_idade_minima


# --- tag / collapse-id ----------------------------------------------------------------------


def test_dois_tokens_recebem_a_mesma_tag_da_conversa(provedor, relogio):
    s = montar(provedor, relogio, A, B)
    mensagem(s)
    assert provedor.tokens == [A, B]
    corpos = [c[2]["message"] for c in provedor.chamadas]
    assert {c["android"]["notification"]["tag"] for c in corpos} == {"conversa:cv-1"}
    assert {c["apns"]["headers"]["apns-collapse-id"] for c in corpos} == {"conversa:cv-1"}
    assert corpos[0]["data"]["conversa_id"] == "cv-1"  # os dados do toque seguem iguais


def test_tag_por_conversa_nas_mensagens_e_pela_chave_no_resto(provedor, relogio):
    s = montar(provedor, relogio, A)
    mensagem(s, 1, "cv-1")
    mensagem(s, 2, "cv-1")  # mesma conversa: substitui
    mensagem(s, 3, "cv-2")  # outra conversa: aparece à parte
    s.notificar(Evento.AVALIACAO, ANA, chave="p1")
    s.notificar(Evento.AVALIACAO, ANA, chave="p2")
    tags = [c[2]["message"]["android"]["notification"]["tag"] for c in provedor.chamadas]
    assert tags[:3] == ["conversa:cv-1", "conversa:cv-1", "conversa:cv-2"]
    assert tags[3] != tags[4] and tags[3] == f"{Evento.AVALIACAO.value}:p1"


def test_tag_cabe_no_limite_do_apns_e_e_estavel():
    longa = {"chave": "pedido.evento:" + "ç" * 80}
    tag = tag_do_push(longa)
    assert tag is not None and len(tag.encode()) <= 64 and tag == tag_do_push(dict(longa))
    uuid_conversa = {"conversa_id": "123e4567-e89b-12d3-a456-426614174000"}
    assert len(tag_do_push(uuid_conversa).encode()) <= 64
    assert tag_do_push({}) is None


def test_sem_chave_nem_conversa_a_carga_vai_sem_tag(provedor):
    corpo = PushFcm(cfg(), provedor, lambda: "t").carga(A, Mensagem(ANA, "T", None, {}))
    assert "android" not in corpo["message"] and "apns" not in corpo["message"]


def test_apns_direto_leva_collapse_id_no_cabecalho(provedor):
    apns = PushApns(cfg(), provedor, lambda: "jwt")
    apns.enviar(Mensagem(ANA, "T", "C", {"conversa_id": "cv-9"}, destinos=(A, B)))
    assert [c[1]["apns-collapse-id"] for c in provedor.chamadas] == ["conversa:cv-9"] * 2


# --- falha isolada por aparelho -------------------------------------------------------------


@pytest.mark.parametrize("ordem", [(A, B), (B, A)])
@pytest.mark.parametrize("status", [400, 404])
def test_bom_mais_invalido_desativa_e_nao_reenvia(provedor, relogio, ordem, status):
    s = montar(provedor, relogio, *ordem)
    provedor.status[B] = status
    mensagem(s)
    assert sorted(provedor.tokens) == [A, B]
    assert s.repo.tokens(ANA) == (A,) and pendentes(s) == 0
    passar_idade_minima(s, relogio)
    assert s.reenviar_pendentes() == 0
    assert provedor.tokens.count(A) == 1


def test_varios_invalidos_sao_todos_desativados(provedor, relogio):
    s = montar(provedor, relogio, B, A, "token-aparelho-C")
    provedor.status.update({B: 404, "token-aparelho-C": 404})
    mensagem(s)
    assert s.repo.tokens(ANA) == (A,) and pendentes(s) == 0


@pytest.mark.parametrize("sem_rede", [False, True])
def test_bom_mais_falha_passageira_marca_enviada_sem_desativar(provedor, relogio, sem_rede):
    s = montar(provedor, relogio, B, A)
    if sem_rede:
        provedor.sem_rede.add(B)
    else:
        provedor.status[B] = 503
    mensagem(s)
    passar_idade_minima(s, relogio)
    assert s.reenviar_pendentes() == 0
    assert provedor.tokens == [B, A] and set(s.repo.tokens(ANA)) == {A, B}


def test_provedor_apns_fora_do_ar_nao_segura_o_android(provedor, relogio):
    config = cfg()
    roteado = PushPorPlataforma(
        PushFcm(config, provedor, lambda: "t"), PushApns(config, provedor, lambda: "jwt")
    )
    s = montar(provedor, relogio, canal=roteado)
    s.repo.registrar_dispositivo(ANA, "token-iphone-01", "ios", T0)
    s.repo.registrar_dispositivo(ANA, A, "android", T0)
    provedor.status["token-iphone-01"] = 500
    mensagem(s)
    assert provedor.tokens == ["token-iphone-01", A] and pendentes(s) == 0


def test_iphone_invalido_com_android_bom_desativa_so_o_iphone(provedor, relogio):
    config = cfg()
    roteado = PushPorPlataforma(
        PushFcm(config, provedor, lambda: "t"), PushApns(config, provedor, lambda: "jwt")
    )
    s = montar(provedor, relogio, canal=roteado)
    s.repo.registrar_dispositivo(ANA, "token-iphone-01", "ios", T0)
    s.repo.registrar_dispositivo(ANA, A, "android", T0)
    provedor.status["token-iphone-01"] = 410
    mensagem(s)
    assert s.repo.tokens(ANA) == (A,) and pendentes(s) == 0


def test_autenticacao_do_provedor_caiu_continua_pendente(provedor, relogio):
    def sem_token() -> str:
        raise FalhaEnvio("Falha ao autenticar conta FCM.")

    s = montar(provedor, relogio, A, canal=PushFcm(cfg(), provedor, sem_token))
    mensagem(s)
    assert pendentes(s) == 1 and provedor.chamadas == []


# --- falha total ainda reenvia --------------------------------------------------------------


def test_falha_total_reenvia_depois_da_idade_minima_uma_vez_so(provedor, relogio):
    s = montar(provedor, relogio, A, B)
    provedor.status.update({A: 503, B: 500})
    mensagem(s)
    assert pendentes(s) == 1
    provedor.status.clear()
    relogio.agora += s.config.reenvio_idade_minima - timedelta(seconds=1)
    assert s.reenviar_pendentes() == 0 and provedor.tokens == [A, B]  # ainda nova
    relogio.agora += timedelta(seconds=1)  # no limite exato já reenvia
    assert s.reenviar_pendentes() == 1
    assert provedor.tokens == [A, B, A, B] and pendentes(s) == 0
    assert s.reenviar_pendentes() == 0 and mensagem(s) == []  # idempotente
    assert len(provedor.chamadas) == 4
    tags = {c[2]["message"]["android"]["notification"]["tag"] for c in provedor.chamadas}
    assert tags == {"conversa:cv-1"}  # o reenvio substitui, não empilha


def test_invalido_mais_falha_passageira_reenvia_so_ao_que_sobrou(provedor, relogio):
    s = montar(provedor, relogio, B, A)
    provedor.status.update({B: 404, A: 503})
    mensagem(s)
    assert s.repo.tokens(ANA) == (A,) and pendentes(s) == 1
    provedor.status.clear()
    passar_idade_minima(s, relogio)
    assert s.reenviar_pendentes() == 1
    assert provedor.tokens == [B, A, A]


def test_todos_invalidos_desativa_e_encerra_sem_novo_envio(provedor, relogio):
    s = montar(provedor, relogio, A, B)
    provedor.status.update({A: 404, B: 404})
    mensagem(s)
    assert s.repo.tokens(ANA) == ()
    passar_idade_minima(s, relogio)
    s.reenviar_pendentes()
    assert pendentes(s) == 0 and len(provedor.chamadas) == 2


# --- agendador durante o envio --------------------------------------------------------------


def test_agendador_durante_o_envio_nao_duplica(provedor, relogio):
    s = montar(provedor, relogio, A)
    enquanto_enviava = []
    provedor.durante = lambda: enquanto_enviava.append((pendentes(s), s.reenviar_pendentes()))
    mensagem(s)
    assert enquanto_enviava == [(1, 0)]  # a linha estava pendente e o agendador não a pegou
    assert provedor.tokens == [A] and pendentes(s) == 0


def test_agendador_em_outro_fio_durante_envio_lento_nao_duplica(provedor, relogio):
    s = montar(provedor, relogio, A)
    enviando, liberar = threading.Event(), threading.Event()

    def segurar() -> None:
        enviando.set()
        assert liberar.wait(10)

    provedor.durante = segurar
    fio = threading.Thread(target=mensagem, args=(s,))
    fio.start()
    try:
        assert enviando.wait(10)
        relogio.agora += timedelta(seconds=60)  # um ciclo do agendador depois, envio ainda aberto
        assert s.reenviar_pendentes() == 0
    finally:
        liberar.set()
        fio.join(10)
    assert provedor.tokens == [A] and pendentes(s) == 0


# --- configuração ----------------------------------------------------------------------------


def test_idade_minima_padrao_e_configuravel(provedor, relogio, monkeypatch):
    assert ConfigNotificacoes(_env_file=None).reenvio_idade_minima == timedelta(seconds=120)
    monkeypatch.setenv("TRATO_NOTIF_REENVIO_IDADE_MINIMA_SEGUNDOS", "300")
    assert ConfigNotificacoes(_env_file=None).reenvio_idade_minima == timedelta(minutes=5)
    with pytest.raises(ValidationError):
        ConfigNotificacoes(_env_file=None, reenvio_idade_minima_segundos=-1)
    s = montar(provedor, relogio, A, reenvio_idade_minima_segundos=0)
    provedor.status[A] = 503
    mensagem(s)
    provedor.status.clear()
    assert s.reenviar_pendentes() == 1
