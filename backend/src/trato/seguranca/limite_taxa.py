"""Limite de taxa (rate limiting) por IP, usuário e rota, com as regras vindas da configuração."""

from __future__ import annotations

from dataclasses import dataclass

from trato.seguranca.config import RegraLimite
from trato.seguranca.contadores import Contadores


@dataclass(frozen=True)
class DecisaoLimite:
    permitido: bool
    retry_apos_s: int = 0
    regra: str | None = None
    chave: str | None = None  # opaca: nome da regra + escopo, sem IP nem token
    novo_bloqueio: bool = False


PERMITIDO = DecisaoLimite(True)


def _casa(regra: RegraLimite, metodo: str, caminho: str) -> bool:
    if not caminho.startswith(regra.prefixo):
        return False
    return not regra.metodos or metodo.upper() in {m.upper() for m in regra.metodos}


class LimitadorTaxa:
    def __init__(self, regras: list[RegraLimite], contadores: Contadores) -> None:
        self._regras = regras
        self._c = contadores

    def checar(self, metodo: str, caminho: str, ip: str, usuario: str | None) -> DecisaoLimite:
        aplicaveis: list[tuple[RegraLimite, str]] = []
        for regra in self._regras:
            if not _casa(regra, metodo, caminho):
                continue
            sujeito = ip if regra.escopo == "ip" else usuario
            if sujeito:  # regra por usuário não vale para quem não mandou token
                aplicaveis.append((regra, f"rl:{regra.nome}:{regra.escopo}:{sujeito}"))
        for regra, chave in aplicaveis:
            opaca = f"{regra.nome}:{regra.escopo}"
            falta = self._c.bloqueado_por(chave)
            if falta:
                return DecisaoLimite(False, falta, regra.nome, opaca)
            if self._c.quantos(chave, regra.janela_s) >= regra.maximo:
                novo = False
                retry = self._c.segundos_ate_liberar(chave, regra.janela_s, regra.maximo)
                if regra.bloqueio_s:
                    novo = self._c.bloquear(chave, regra.bloqueio_s)
                    retry = max(retry, regra.bloqueio_s)
                return DecisaoLimite(False, retry, regra.nome, opaca, novo)
        for _, chave in aplicaveis:
            self._c.adicionar(chave)
        return PERMITIDO
