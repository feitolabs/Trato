"""Canais de entrega por interface: `app`, `push`, `email`, `sms`, `whatsapp`.

Cada canal tem um FAKE (testes e desenvolvimento) e, quando faz sentido, um ADAPTADOR REAL que
só liga com a configuração do `.env`. Os adaptadores não fazem rede sozinhos: o envio HTTP/SMTP
entra por um transporte injetado, e o padrão é "desligado". Nada aqui chama provedor de verdade
sem o João preencher as chaves (docs/backend-notificacoes.md).

D14: SMS só para confirmar o celular (`ServicoSmsConfirmacao`). WhatsApp fica para a V1.
"""

from __future__ import annotations

import base64
import binascii
import importlib.util
import json
import re
import smtplib
import time
from collections.abc import Callable
from dataclasses import dataclass, field
from email.message import EmailMessage
from pathlib import Path
from typing import Any, Protocol

import httpx
import jwt

from trato.notificacoes.config import ConfigNotificacoes

CANAIS = ("app", "push", "email", "sms", "whatsapp")
CANAIS_DE_NOTIFICACAO = ("app", "push", "email")  # sms/whatsapp não são notificação comum


class FalhaEnvio(Exception):
    """O canal não conseguiu entregar agora; vale tentar de novo depois."""


class TokenInvalido(FalhaEnvio):
    """O provedor disse que o token do aparelho não existe mais."""

    def __init__(self, token: str) -> None:
        super().__init__("Token de push inválido.")
        self.token = token


@dataclass(frozen=True)
class Mensagem:
    usuario_id: str
    titulo: str
    corpo: str | None
    dados: dict[str, Any]
    destinos: tuple[str, ...] = ()  # tokens (push) ou endereços (e-mail)
    destinos_plataforma: tuple[tuple[str, str], ...] = ()  # (token, plataforma)


class Canal(Protocol):
    nome: str

    @property
    def disponivel(self) -> bool:
        """Falso = canal desligado ou sem configuração: o serviço nem tenta."""

    def enviar(self, mensagem: Mensagem) -> None: ...


class CanalApp:
    """A caixa de entrada: a própria linha em `notificacoes` já é a entrega."""

    nome = "app"
    disponivel = True

    def enviar(self, mensagem: Mensagem) -> None:
        return None


@dataclass
class CanalFake:
    """Guarda o que "enviou". `falhar_proximos(n)` simula queda do provedor."""

    nome: str
    enviados: list[Mensagem] = field(default_factory=list)
    ligado: bool = True
    _falhas: int = 0
    tokens_invalidos: set[str] = field(default_factory=set)

    @property
    def disponivel(self) -> bool:
        return self.ligado

    def falhar_proximos(self, n: int) -> None:
        self._falhas = n

    def enviar(self, mensagem: Mensagem) -> None:
        if self._falhas > 0:
            self._falhas -= 1
            raise FalhaEnvio("Provedor fora do ar (simulado).")
        for destino in mensagem.destinos:
            if destino in self.tokens_invalidos:
                raise TokenInvalido(destino)
        self.enviados.append(mensagem)


# --- Push ---------------------------------------------------------------------------------

# (url, cabeçalhos, corpo JSON) -> código HTTP. O real usa httpx; os testes passam um falso.
TransporteHttp = Callable[[str, dict[str, str], dict[str, Any]], int]


def _dados_texto(dados: dict[str, Any]) -> dict[str, str]:
    return {str(k): str(v) for k, v in dados.items()}


class PushFcm:
    """Firebase Cloud Messaging (HTTP v1). Liga com TRATO_NOTIF_PUSH_ATIVO + FCM_PROJETO_ID.

    `token_acesso` devolve o OAuth2 da conta de serviço (o João fornece o JSON; quem o lê é o
    ponto de integração, não este módulo).
    """

    nome = "push"

    def __init__(
        self,
        config: ConfigNotificacoes,
        transporte: TransporteHttp | None = None,
        token_acesso: Callable[[], str] | None = None,
    ) -> None:
        self._config = config
        self._transporte = transporte
        self._token_acesso = token_acesso

    @property
    def disponivel(self) -> bool:
        c = self._config
        return bool(c.push_ativo and c.fcm_projeto_id and self._transporte and self._token_acesso)

    def carga(self, token: str, mensagem: Mensagem) -> dict[str, Any]:
        return {
            "message": {
                "token": token,
                "notification": {"title": mensagem.titulo, "body": mensagem.corpo or ""},
                "data": _dados_texto(mensagem.dados),
            }
        }

    def enviar(self, mensagem: Mensagem) -> None:
        if not (self.disponivel and self._transporte and self._token_acesso):
            raise FalhaEnvio("Push desligado.")
        url = f"https://fcm.googleapis.com/v1/projects/{self._config.fcm_projeto_id}/messages:send"
        cab = {"Authorization": f"Bearer {self._token_acesso()}"}
        falhou = False
        for token in mensagem.destinos:
            status = self._transporte(url, cab, self.carga(token, mensagem))
            if status in (400, 404):
                raise TokenInvalido(token)
            if status >= 300:
                falhou = True
        if falhou:
            raise FalhaEnvio("FCM recusou o envio.")


class PushApns:
    """APNs direto (iOS), opcional. Liga com TRATO_NOTIF_APNS_ATIVO + chaves. Mesmo molde do FCM."""

    nome = "push"

    def __init__(
        self,
        config: ConfigNotificacoes,
        transporte: TransporteHttp | None = None,
        jwt_provedor: Callable[[], str] | None = None,
    ) -> None:
        self._config = config
        self._transporte = transporte
        self._jwt = jwt_provedor

    @property
    def disponivel(self) -> bool:
        c = self._config
        return bool(
            c.apns_ativo and c.apns_bundle_id and c.apns_chave_id and self._transporte and self._jwt
        )

    def carga(self, mensagem: Mensagem) -> dict[str, Any]:
        return {
            "aps": {"alert": {"title": mensagem.titulo, "body": mensagem.corpo or ""}},
            **_dados_texto(mensagem.dados),
        }

    def enviar(self, mensagem: Mensagem) -> None:
        if not (self.disponivel and self._transporte and self._jwt):
            raise FalhaEnvio("APNs desligado.")
        cab = {
            "authorization": f"bearer {self._jwt()}",
            "apns-topic": self._config.apns_bundle_id,
        }
        for token in mensagem.destinos:
            url = f"https://api.push.apple.com/3/device/{token}"
            status = self._transporte(url, cab, self.carga(mensagem))
            if status == 410:
                raise TokenInvalido(token)
            if status >= 300:
                raise FalhaEnvio("APNs recusou o envio.")


# --- E-mail -------------------------------------------------------------------------------


class EmailSmtp:
    """SMTP. Liga com TRATO_NOTIF_EMAIL_ATIVO + SMTP_HOST + EMAIL_REMETENTE (+ usuário/senha)."""

    nome = "email"

    def __init__(
        self,
        config: ConfigNotificacoes,
        fabrica_smtp: Callable[[str, int], smtplib.SMTP] = smtplib.SMTP,
    ) -> None:
        self._config = config
        self._fabrica = fabrica_smtp

    @property
    def disponivel(self) -> bool:
        c = self._config
        return bool(c.email_ativo and c.smtp_host and c.email_remetente)

    def enviar(self, mensagem: Mensagem) -> None:
        if not self.disponivel:
            raise FalhaEnvio("E-mail desligado.")
        c = self._config
        corpo = EmailMessage()
        corpo["From"], corpo["Subject"] = c.email_remetente, mensagem.titulo
        corpo["To"] = ", ".join(mensagem.destinos)
        corpo.set_content(mensagem.corpo or mensagem.titulo)
        try:
            with self._fabrica(c.smtp_host, c.smtp_porta) as smtp:
                smtp.starttls()
                if c.smtp_usuario:
                    smtp.login(c.smtp_usuario, c.smtp_senha.get_secret_value())
                smtp.send_message(corpo)
        except (smtplib.SMTPException, OSError) as erro:
            raise FalhaEnvio("SMTP falhou.") from erro


# --- SMS (só confirmação de celular, D14) ---------------------------------------------------


class ProvedorSms(Protocol):
    def enviar(self, telefone: str, texto: str) -> None: ...


@dataclass
class SmsFake:
    enviados: list[tuple[str, str]] = field(default_factory=list)

    def enviar(self, telefone: str, texto: str) -> None:
        self.enviados.append((telefone, texto))


class LimiteSmsExcedido(Exception):
    pass


class ServicoSmsConfirmacao:
    """Único uso de SMS no MVP: o código de confirmação do celular no cadastro (D14).

    Limita os envios por celular (config). O CAPTCHA antes do envio e a validade de 5 min do
    código ficam no fluxo do Supabase Auth (Send SMS Hook), que chama este serviço.
    """

    def __init__(self, provedor: ProvedorSms, max_envios: int) -> None:
        self._provedor = provedor
        self._max = max_envios
        self._envios: dict[str, int] = {}

    def enviar_codigo(self, telefone: str, codigo: str) -> None:
        if self._envios.get(telefone, 0) >= self._max:
            raise LimiteSmsExcedido("Muitos envios para este celular.")
        self._envios[telefone] = self._envios.get(telefone, 0) + 1
        self._provedor.enviar(telefone, f"Seu código Trato: {codigo}. Vale por 5 minutos.")


@dataclass
class Canais:
    """Os canais ativos do serviço. `None` = não existe/desligado."""

    app: Canal = field(default_factory=CanalApp)
    push: Canal | None = None
    email: Canal | None = None

    def por_nome(self, nome: str) -> Canal | None:
        return getattr(self, nome, None) if nome in CANAIS_DE_NOTIFICACAO else None


class PushPorPlataforma:
    """Roteia tokens iOS para APNs (quando ativo) e demais tokens para FCM."""

    nome = "push"

    def __init__(self, fcm: PushFcm, apns: PushApns) -> None:
        self.fcm = fcm
        self.apns = apns

    @property
    def disponivel(self) -> bool:
        return self.fcm.disponivel or self.apns.disponivel

    def enviar(self, mensagem: Mensagem) -> None:
        pares = mensagem.destinos_plataforma or tuple((t, "android") for t in mensagem.destinos)
        tokens_ios = tuple(t for t, plat in pares if plat == "ios")
        tokens_outros = tuple(t for t, plat in pares if plat != "ios")
        if self.apns.disponivel and tokens_ios:
            self.apns.enviar(
                Mensagem(
                    mensagem.usuario_id,
                    mensagem.titulo,
                    mensagem.corpo,
                    mensagem.dados,
                    destinos=tokens_ios,
                )
            )
        elif tokens_ios:
            tokens_outros = (*tokens_outros, *tokens_ios)
        if self.fcm.disponivel and tokens_outros:
            self.fcm.enviar(
                Mensagem(
                    mensagem.usuario_id,
                    mensagem.titulo,
                    mensagem.corpo,
                    mensagem.dados,
                    destinos=tokens_outros,
                )
            )


def _transporte_httpx(url: str, cabecalhos: dict[str, str], corpo: dict[str, Any]) -> int:
    try:
        with httpx.Client(timeout=10.0) as cliente:
            return cliente.post(url, headers=cabecalhos, json=corpo).status_code
    except httpx.HTTPError as erro:
        raise FalhaEnvio("Falha de rede ao enviar push.") from erro


def _transporte_apns_http2(url: str, cabecalhos: dict[str, str], corpo: dict[str, Any]) -> int:
    try:
        with httpx.Client(http2=True, timeout=10.0) as cliente:
            return cliente.post(url, headers=cabecalhos, json=corpo).status_code
    except httpx.HTTPError as erro:
        raise FalhaEnvio("Falha de rede ao enviar APNs.") from erro


class _ProvedorTokenFcm:
    """Troca JWT RS256 da conta de serviço Firebase por token OAuth2 em cache."""

    _ESCOPO = "https://www.googleapis.com/auth/firebase.messaging"

    def __init__(
        self,
        email_conta: str,
        chave_privada: str,
        token_uri: str = "https://oauth2.googleapis.com/token",  # noqa: S107
        cliente_oauth: Callable[[str, dict[str, str]], dict[str, Any]] | None = None,
    ) -> None:
        self._email = email_conta
        self._chave = chave_privada
        self._token_uri = token_uri
        self._cliente_oauth = cliente_oauth or self._trocar_token
        self._token = ""
        self._expira_em = 0.0

    @staticmethod
    def _trocar_token(uri: str, form: dict[str, str]) -> dict[str, Any]:
        try:
            with httpx.Client(timeout=10.0) as cliente:
                resp = cliente.post(uri, data=form)
            if resp.status_code >= 300:
                raise FalhaEnvio("Falha ao autenticar conta FCM.")
            dados = resp.json()
            return dados if isinstance(dados, dict) else {}
        except (httpx.HTTPError, ValueError) as erro:
            raise FalhaEnvio("Falha de rede ao autenticar FCM.") from erro

    def __call__(self) -> str:
        agora = time.time()
        if self._token and agora < self._expira_em - 60:
            return self._token
        asserto = jwt.encode(
            {
                "iss": self._email,
                "scope": self._ESCOPO,
                "aud": self._token_uri,
                "iat": int(agora),
                "exp": int(agora) + 3600,
            },
            self._chave,
            algorithm="RS256",
        )
        dados = self._cliente_oauth(
            self._token_uri,
            {
                "grant_type": "urn:ietf:params:oauth:grant-type:jwt-bearer",
                "assertion": asserto,
            },
        )
        token = str(dados.get("access_token") or "")
        if not token:
            raise FalhaEnvio("Token OAuth2 FCM ausente.")
        expira = int(dados.get("expires_in") or 3600)
        self._token = token
        self._expira_em = agora + max(60, expira)
        return self._token


class _ProvedorJwtApns:
    """Gera e guarda em cache (45 min) o JWT ES256 exigido pela API APNs."""

    def __init__(self, chave_privada: str, chave_id: str, time_id: str) -> None:
        self._chave = chave_privada
        self._chave_id = chave_id
        self._time_id = time_id
        self._jwt = ""
        self._emitido_em = 0.0

    def __call__(self) -> str:
        agora = time.time()
        if self._jwt and agora - self._emitido_em < 45 * 60:
            return self._jwt
        token = jwt.encode(
            {"iss": self._time_id, "iat": int(agora)},
            self._chave,
            algorithm="ES256",
            headers={"kid": self._chave_id},
        )
        self._jwt = token
        self._emitido_em = agora
        return token


def _decodificar_credenciais_fcm_texto(texto: str) -> dict[str, Any] | None:
    """Lê JSON cru ou base64 de JSON da conta de serviço FCM. Nunca expõe o conteúdo em erros."""
    limpo = texto.strip()
    if not limpo:
        return None
    try:
        dados = json.loads(limpo)
        return dados if isinstance(dados, dict) else None
    except ValueError:
        pass
    try:
        compacto = re.sub(r"\s+", "", limpo)
        decodificado = base64.b64decode(compacto, validate=True).decode("utf-8")
        dados = json.loads(decodificado)
        return dados if isinstance(dados, dict) else None
    except (binascii.Error, UnicodeDecodeError, ValueError):
        return None


def _ler_credenciais_fcm(config: ConfigNotificacoes) -> dict[str, Any] | None:
    bruto_env = config.fcm_credenciais_json.get_secret_value().strip()
    if bruto_env:
        return _decodificar_credenciais_fcm_texto(bruto_env)
    if not config.fcm_credenciais_arquivo:
        return None
    caminho = Path(config.fcm_credenciais_arquivo)
    if not caminho.is_file():
        return None
    try:
        dados = json.loads(caminho.read_text(encoding="utf-8"))
        return dados if isinstance(dados, dict) else None
    except (OSError, ValueError):
        return None


def _montar_fcm(config: ConfigNotificacoes) -> PushFcm:
    if not (config.push_ativo and config.fcm_projeto_id):
        return PushFcm(config)
    bruto = _ler_credenciais_fcm(config)
    if bruto is None:
        return PushFcm(config)
    email = str(bruto.get("client_email") or "").strip()
    chave = str(bruto.get("private_key") or "").strip()
    uri = str(bruto.get("token_uri") or "https://oauth2.googleapis.com/token").strip()
    if not email or not chave:
        return PushFcm(config)
    return PushFcm(config, _transporte_httpx, _ProvedorTokenFcm(email, chave, uri))


def _montar_apns(config: ConfigNotificacoes) -> PushApns | None:
    if not (
        config.apns_ativo
        and config.apns_bundle_id
        and config.apns_chave_id
        and config.apns_time_id
        and config.apns_chave_arquivo
        and importlib.util.find_spec("h2") is not None
    ):
        return None
    caminho = Path(config.apns_chave_arquivo)
    if not caminho.is_file():
        return None
    try:
        chave = caminho.read_text(encoding="utf-8").strip()
    except OSError:
        return None
    if not chave:
        return None
    return PushApns(
        config,
        _transporte_apns_http2,
        _ProvedorJwtApns(chave, config.apns_chave_id, config.apns_time_id),
    )


def canais_da_config(config: ConfigNotificacoes) -> Canais:
    """Monta os canais reais conforme o `.env`; sem credenciais válidas, ficam desligados."""
    fcm = _montar_fcm(config)
    apns = _montar_apns(config)
    push: Canal = PushPorPlataforma(fcm, apns) if apns is not None and apns.disponivel else fcm
    return Canais(push=push, email=EmailSmtp(config))
