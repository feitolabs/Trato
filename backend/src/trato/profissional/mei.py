"""MEI do profissional: valida o CNPJ na BrasilAPI e guarda o estado da validação.

Regra: CNPJ com dígito verificador válido + situação cadastral ATIVA + optante pelo MEI.
Falha da API (rede, timeout, 429, 5xx) nunca aprova nem reprova: fica "pendente".
Só o CNPJ (14 dígitos) sai na requisição; nenhum dado pessoal.
"""

from __future__ import annotations

import os
import re
import threading
from collections.abc import Callable
from dataclasses import dataclass, replace
from datetime import UTC, datetime, timedelta
from enum import StrEnum
from typing import Any, Protocol

import httpx

_DIGITOS = re.compile(r"\D")
URL_BRASILAPI = "https://brasilapi.com.br/api/cnpj/v1/{cnpj}"

BuscadorJson = Callable[[str], tuple[int, dict[str, Any] | None]]


class StatusMei(StrEnum):
    NAO_INFORMADO = "nao_informado"
    PENDENTE = "pendente"
    VALIDO = "valido"
    INVALIDO = "invalido"


MOTIVOS = {
    StatusMei.NAO_INFORMADO: "Informe o CNPJ do seu MEI para enviar orçamentos e receber.",
    StatusMei.PENDENTE: "Não conseguimos consultar a Receita agora. Tentaremos de novo em breve.",
    StatusMei.VALIDO: "MEI ativo.",
}
MOTIVO_DIGITO = "O CNPJ informado não é válido. Confira os 14 números."
MOTIVO_NAO_ENCONTRADO = "Não encontramos esse CNPJ na Receita Federal."
MOTIVO_INATIVO = "O CNPJ não está com situação cadastral ativa na Receita Federal."
MOTIVO_NAO_MEI = "O CNPJ existe, mas não é de um MEI. Só MEI ativo pode orçar e receber."
MENSAGEM_BLOQUEIO = (
    "Para enviar orçamentos, valide o CNPJ do seu MEI no perfil. Seu cadastro e a navegação "
    "continuam liberados."
)


@dataclass(frozen=True)
class ConfigMei:
    """Valores ajustáveis (env `TRATO_MEI_*`); nada fixo no código das regras."""

    obrigatorio: bool = False  # liga o bloqueio de orçamento; sem persistência fica desligado
    cache_horas: int = 24
    timeout_segundos: float = 3.0
    tentativas_extras: int = 1


def obter_config_mei() -> ConfigMei:
    padrao = ConfigMei()

    def _num(nome: str, valor, tipo):
        try:
            return tipo(os.environ.get(nome, valor))
        except ValueError:
            return valor

    return ConfigMei(
        obrigatorio=os.environ.get("TRATO_MEI_OBRIGATORIO", "").strip().lower()
        in ("1", "true", "sim"),
        cache_horas=_num("TRATO_MEI_CACHE_HORAS", padrao.cache_horas, int),
        timeout_segundos=_num("TRATO_MEI_TIMEOUT_S", padrao.timeout_segundos, float),
        tentativas_extras=_num("TRATO_MEI_TENTATIVAS_EXTRAS", padrao.tentativas_extras, int),
    )


# --- CNPJ ---------------------------------------------------------------------------------


def normalizar_cnpj(bruto: str | None) -> str:
    return _DIGITOS.sub("", bruto or "")


def cnpj_valido(bruto: str | None) -> bool:
    """14 dígitos, não repetidos, com os dois dígitos verificadores corretos."""
    cnpj = normalizar_cnpj(bruto)
    if len(cnpj) != 14 or len(set(cnpj)) == 1:
        return False

    def dv(base: str) -> str:
        pesos = (
            [5, 4, 3, 2, 9, 8, 7, 6, 5, 4, 3, 2]
            if len(base) == 12
            else [6, 5, 4, 3, 2, 9, 8, 7, 6, 5, 4, 3, 2]
        )
        resto = sum(int(d) * p for d, p in zip(base, pesos, strict=True)) % 11
        return "0" if resto < 2 else str(11 - resto)

    primeiro = dv(cnpj[:12])
    return cnpj[12] == primeiro and cnpj[13] == dv(cnpj[:12] + primeiro)


# --- Estado e repositório -------------------------------------------------------------------


@dataclass(frozen=True)
class RegistroMei:
    profissional_id: str
    cnpj: str | None = None
    mei_status: StatusMei = StatusMei.NAO_INFORMADO
    mei_motivo: str = MOTIVOS[StatusMei.NAO_INFORMADO]
    mei_validado_em: datetime | None = None
    razao_social: str | None = None


class RepositorioMei(Protocol):
    def obter(self, profissional_id: str) -> RegistroMei | None: ...

    def salvar(self, registro: RegistroMei) -> None: ...


class MeiEmMemoria:
    def __init__(self) -> None:
        self._dados: dict[str, RegistroMei] = {}
        self._trava = threading.Lock()

    def obter(self, profissional_id: str) -> RegistroMei | None:
        with self._trava:
            return self._dados.get(profissional_id)

    def salvar(self, registro: RegistroMei) -> None:
        with self._trava:
            self._dados[registro.profissional_id] = registro


# --- Consulta à BrasilAPI --------------------------------------------------------------------


class ConsultaIndisponivel(Exception):
    """A BrasilAPI não respondeu de forma conclusiva (rede, timeout, 429, 5xx)."""


@dataclass(frozen=True)
class DadosCnpj:
    encontrado: bool
    ativo: bool = False
    mei: bool = False
    razao_social: str | None = None


def _buscar_httpx_com(timeout: float) -> BuscadorJson:
    def buscar(url: str) -> tuple[int, dict[str, Any] | None]:
        with httpx.Client(timeout=timeout, follow_redirects=False) as cliente:
            resp = cliente.get(url, headers={"Accept": "application/json"})
        try:
            dados = resp.json() if resp.content else None
        except ValueError:
            dados = None
        return resp.status_code, dados if isinstance(dados, dict) else None

    return buscar


class ConsultaCnpj:
    """Cliente da BrasilAPI com 1 retry e cache de resultados conclusivos (24 h)."""

    def __init__(
        self,
        buscador: BuscadorJson | None = None,
        config: ConfigMei | None = None,
        agora: Callable[[], datetime] | None = None,
    ) -> None:
        self._config = config or obter_config_mei()
        self._buscador = buscador or _buscar_httpx_com(self._config.timeout_segundos)
        self._agora = agora or (lambda: datetime.now(UTC))
        self._cache: dict[str, tuple[datetime, DadosCnpj]] = {}
        self._trava = threading.Lock()

    def consultar(self, cnpj: str) -> DadosCnpj:
        agora = self._agora()
        with self._trava:
            achado = self._cache.get(cnpj)
        if achado and agora - achado[0] < timedelta(hours=self._config.cache_horas):
            return achado[1]
        dados = self._consultar_com_retry(cnpj)
        with self._trava:
            self._cache[cnpj] = (agora, dados)
        return dados

    def _consultar_com_retry(self, cnpj: str) -> DadosCnpj:
        url = URL_BRASILAPI.format(cnpj=cnpj)
        ultimo: Exception | None = None
        for _ in range(1 + max(0, self._config.tentativas_extras)):
            try:
                status, corpo = self._buscador(url)
            except Exception as erro:  # noqa: BLE001 - qualquer falha de rede vira "pendente"
                ultimo = erro
                continue
            if status in (400, 404):
                return DadosCnpj(encontrado=False)
            if status == 200 and corpo is not None:
                return _ler_resposta(corpo)
            ultimo = ConsultaIndisponivel(f"BrasilAPI respondeu {status}.")
        raise ConsultaIndisponivel("BrasilAPI indisponível.") from ultimo


def _ler_resposta(corpo: dict[str, Any]) -> DadosCnpj:
    descricao = str(corpo.get("descricao_situacao_cadastral") or "").strip().upper()
    ativo = descricao == "ATIVA" or corpo.get("situacao_cadastral") == 2
    return DadosCnpj(
        encontrado=True,
        ativo=bool(ativo),
        mei=corpo.get("opcao_pelo_mei") is True,
        razao_social=(str(corpo.get("razao_social") or "").strip() or None),
    )


def avaliar(dados: DadosCnpj) -> tuple[StatusMei, str]:
    """Aplica a regra do MEI sobre a resposta já lida."""
    if not dados.encontrado:
        return StatusMei.INVALIDO, MOTIVO_NAO_ENCONTRADO
    if not dados.ativo:
        return StatusMei.INVALIDO, MOTIVO_INATIVO
    if not dados.mei:
        return StatusMei.INVALIDO, MOTIVO_NAO_MEI
    return StatusMei.VALIDO, MOTIVOS[StatusMei.VALIDO]


# --- Serviço -----------------------------------------------------------------------------------


class ServicoMei:
    def __init__(
        self,
        repo: RepositorioMei | None = None,
        consulta: ConsultaCnpj | None = None,
        config: ConfigMei | None = None,
        agora: Callable[[], datetime] | None = None,
    ) -> None:
        self.config = config or obter_config_mei()
        self.repo = repo or MeiEmMemoria()
        self._agora = agora or (lambda: datetime.now(UTC))
        self.consulta = consulta or ConsultaCnpj(config=self.config, agora=self._agora)

    def status(self, profissional_id: str) -> RegistroMei:
        """Estado atual; se está pendente, tenta validar de novo (a API pode ter voltado)."""
        atual = self.repo.obter(profissional_id) or RegistroMei(profissional_id)
        if atual.mei_status is StatusMei.PENDENTE and atual.cnpj:
            return self._validar(atual, atual.cnpj)
        return atual

    def informar(self, profissional_id: str, cnpj_bruto: str) -> RegistroMei:
        cnpj = normalizar_cnpj(cnpj_bruto)
        base = self.repo.obter(profissional_id) or RegistroMei(profissional_id)
        if not cnpj_valido(cnpj):
            registro = replace(
                base,
                cnpj=cnpj or None,
                mei_status=StatusMei.INVALIDO,
                mei_motivo=MOTIVO_DIGITO,
                mei_validado_em=self._agora(),
                razao_social=None,
            )
            self.repo.salvar(registro)
            return registro
        return self._validar(base, cnpj)

    def _validar(self, base: RegistroMei, cnpj: str) -> RegistroMei:
        try:
            dados = self.consulta.consultar(cnpj)
            status, motivo = avaliar(dados)
            registro = replace(
                base,
                cnpj=cnpj,
                mei_status=status,
                mei_motivo=motivo,
                mei_validado_em=self._agora(),
                razao_social=dados.razao_social,
            )
        except ConsultaIndisponivel:
            registro = replace(
                base,
                cnpj=cnpj,
                mei_status=StatusMei.PENDENTE,
                mei_motivo=MOTIVOS[StatusMei.PENDENTE],
                mei_validado_em=None,
            )
        self.repo.salvar(registro)
        return registro

    def liberado(self, profissional_id: str) -> bool:
        """Pode enviar orçamento e receber? Sem o bloqueio ligado, todos passam."""
        if not self.config.obrigatorio:
            return True
        return self.status(profissional_id).mei_status is StatusMei.VALIDO
