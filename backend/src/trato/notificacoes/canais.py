"""Canais de entrega por interface: `app`, `push`, `email`, `sms`, `whatsapp`.

Cada canal tem um FAKE (testes e desenvolvimento) e, quando faz sentido, um ADAPTADOR REAL que
só liga com a configuração do `.env`. Os adaptadores não fazem rede sozinhos: o envio HTTP/SMTP
entra por um transporte injetado, e o padrão é "desligado". Nada aqui chama provedor de verdade
sem o João preencher as chaves (docs/backend-notificacoes.md).

D14: SMS só para confirmar o celular (`ServicoSmsConfirmacao`). WhatsApp fica para a V1.
"""

from __future__ import annotations

import smtplib
from collections.abc import Callable
from dataclasses import dataclass, field
from email.message import EmailMessage
from typing import Any, Protocol

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


def canais_da_config(config: ConfigNotificacoes) -> Canais:
    """Canais reais conforme o `.env`. Sem transporte injetado, o push fica indisponível."""
    return Canais(push=PushFcm(config), email=EmailSmtp(config))
