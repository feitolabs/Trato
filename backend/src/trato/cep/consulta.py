"""Consulta de CEP via HTTPS com fallback e cache em memória."""

from __future__ import annotations

import re
from collections import OrderedDict
from collections.abc import Callable
from dataclasses import dataclass
from typing import Any

import httpx

_DIGITOS = re.compile(r"\D")
_MAX_CACHE = 1024

BuscadorJson = Callable[[str], tuple[int, dict[str, Any] | None]]


class CepNaoEncontrado(Exception):
    """O CEP tem 8 dígitos, mas não existe na base postal."""


class CepIndisponivel(Exception):
    """Os provedores de CEP não responderam a tempo."""


@dataclass(frozen=True)
class EnderecoCep:
    """Endereço normalizado retornado para um CEP de 8 dígitos."""

    cep: str
    logradouro: str
    complemento: str
    bairro: str
    cidade: str
    uf: str


def normalizar_cep(bruto: str) -> str:
    """Remove pontuação e valida 8 dígitos."""
    digitos = _DIGITOS.sub("", bruto or "")
    if len(digitos) != 8:
        raise ValueError("Informe um CEP válido com 8 dígitos.")
    return digitos


def _buscar_httpx(url: str) -> tuple[int, dict[str, Any] | None]:
    with httpx.Client(timeout=4.0, follow_redirects=True) as cliente:
        resp = cliente.get(url, headers={"Accept": "application/json"})
    try:
        dados = resp.json() if resp.content else None
    except ValueError:
        dados = None
    return resp.status_code, dados if isinstance(dados, dict) else None


class ConsultaCep:
    """Consulta ViaCEP e recorre à BrasilAPI se o primeiro falhar ou ficar fora do ar."""

    def __init__(self, buscador: BuscadorJson | None = None) -> None:
        self._buscador = buscador or _buscar_httpx
        self._cache: OrderedDict[str, EnderecoCep] = OrderedDict()

    def consultar(self, bruto: str) -> EnderecoCep:
        cep = normalizar_cep(bruto)
        if cep in self._cache:
            self._cache.move_to_end(cep)
            return self._cache[cep]

        resultado = self._consultar_provedores(cep)
        self._cache[cep] = resultado
        if len(self._cache) > _MAX_CACHE:
            self._cache.popitem(last=False)
        return resultado

    def _consultar_provedores(self, cep: str) -> EnderecoCep:
        nao_encontrado = False
        houve_erro_rede = False

        for leitor in (self._viacep, self._brasilapi):
            try:
                achado = leitor(cep)
            except CepNaoEncontrado:
                nao_encontrado = True
                continue
            except Exception:
                houve_erro_rede = True
                continue
            if achado is not None:
                return achado

        if nao_encontrado and not houve_erro_rede:
            raise CepNaoEncontrado("CEP não encontrado.")
        if nao_encontrado:
            raise CepNaoEncontrado("CEP não encontrado.")
        raise CepIndisponivel(
            "Não foi possível consultar o CEP agora. Preencha o endereço manualmente."
        )

    def _viacep(self, cep: str) -> EnderecoCep | None:
        status, dados = self._buscador(f"https://viacep.com.br/ws/{cep}/json/")
        if status == 404:
            raise CepNaoEncontrado("CEP não encontrado.")
        if status != 200 or not dados:
            raise CepIndisponivel("ViaCEP indisponível.")
        if dados.get("erro") is True or str(dados.get("erro", "")).lower() == "true":
            raise CepNaoEncontrado("CEP não encontrado.")
        cidade = str(dados.get("localidade") or "").strip()
        uf = str(dados.get("uf") or "").strip().upper()
        if not cidade or len(uf) != 2:
            raise CepIndisponivel("Resposta incompleta do ViaCEP.")
        return EnderecoCep(
            cep=cep,
            logradouro=str(dados.get("logradouro") or "").strip(),
            complemento=str(dados.get("complemento") or "").strip(),
            bairro=str(dados.get("bairro") or "").strip(),
            cidade=cidade,
            uf=uf,
        )

    def _brasilapi(self, cep: str) -> EnderecoCep | None:
        status, dados = self._buscador(f"https://brasilapi.com.br/api/cep/v2/{cep}")
        if status == 404:
            raise CepNaoEncontrado("CEP não encontrado.")
        if status != 200 or not dados:
            raise CepIndisponivel("BrasilAPI indisponível.")
        cidade = str(dados.get("city") or "").strip()
        uf = str(dados.get("state") or "").strip().upper()
        if not cidade or len(uf) != 2:
            raise CepIndisponivel("Resposta incompleta da BrasilAPI.")
        return EnderecoCep(
            cep=cep,
            logradouro=str(dados.get("street") or "").strip(),
            complemento="",
            bairro=str(dados.get("neighborhood") or "").strip(),
            cidade=cidade,
            uf=uf,
        )
