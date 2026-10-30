"""Contorno da plataforma: sinais de que a conversa quer sair do Trato (levar para o WhatsApp,
pagar por fora, fugir da taxa). Gera pontuação e motivos; quem decide é a equipe (só flag)."""

from __future__ import annotations

import re
import unicodedata
from dataclasses import dataclass

from trato.seguranca.config import ConfigSeguranca

# (motivo, peso, padrão sobre o texto sem acento e em minúsculas)
_SINAIS: tuple[tuple[str, int, re.Pattern[str]], ...] = (
    ("canal_externo", 1, re.compile(r"\b(zap|zapzap|whats\w*|wpp|watsap|telegram|insta\w*)\b")),
    (
        "pedido_de_contato",
        1,
        re.compile(
            r"\b(passa|manda|me da|deixa)\b.{0,20}\b(numero|contato|telefone|fone|celular)\b"
        ),
    ),
    (
        "fora_da_plataforma",
        2,
        re.compile(
            r"\b(por fora|fora (do|da|de) (app|aplicativo|plataforma|trato)"
            r"|sem (passar|usar) (pelo|pela|o|a) (app|aplicativo|plataforma|trato))\b"
        ),
    ),
    (
        "fugir_da_taxa",
        2,
        re.compile(
            r"\b(sem (a )?taxa|sem (a )?comissao|evit\w+ (a )?(taxa|comissao)"
            r"|(fugir|driblar|economizar) (da |a )?(taxa|comissao))\b"
        ),
    ),
    (
        "pagamento_direto",
        2,
        re.compile(
            r"\b(pag\w+ (direto|na mao|em dinheiro|por pix)|pix (direto|pra mim|para mim)"
            r"|(me )?paga direto|acerta direto)\b"
        ),
    ),
)


@dataclass(frozen=True)
class SinalContorno:
    pontuacao: int
    motivos: tuple[str, ...]
    sinalizar: bool


def _normalizar(texto: str) -> str:
    base = unicodedata.normalize("NFKD", texto.lower())
    return "".join(c for c in base if not unicodedata.combining(c))


def avaliar_contorno(
    texto: str, categorias_mascara: frozenset[str], config: ConfigSeguranca
) -> SinalContorno:
    limpo = _normalizar(texto)
    pontos = 0
    motivos: list[str] = []
    for motivo, peso, padrao in _SINAIS:
        if padrao.search(limpo):
            pontos += peso
            motivos.append(motivo)
    if categorias_mascara & {"telefone", "email", "link", "rede_social"}:
        pontos += 2
        motivos.append("contato_escondido_pelo_mascaramento")
    return SinalContorno(pontos, tuple(motivos), pontos >= config.contorno_limiar)
