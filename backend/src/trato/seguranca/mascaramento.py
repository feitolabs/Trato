"""Mascaramento de contato no chat antes da contratação (F8.1).

O texto original fica guardado (`corpo`, evidência para disputa); o que o outro lado lê é o
`corpo_exibido`, com `mascarada = verdadeiro` quando algo foi escondido. Esconde telefone (inclusive
com espaços, pontos, números por extenso e emojis de teclado), e-mail (inclusive "arroba"/"ponto"),
links, perfis de rede social e endereço. Conversa normal (preço, medida, data, hora) passa.
Detalhes e limites conhecidos: `docs/backend-seguranca.md`.
"""

from __future__ import annotations

import re
from dataclasses import dataclass, field

from trato.seguranca.config import ConfigSeguranca, obter_config_seguranca

AVISO_MASCARA = "[contato oculto até a contratação]"

# Palavra -> quantos dígitos ela vale ("onze" = 2). Números por extenso também formam telefone.
_PALAVRAS_DIGITO = {
    **dict.fromkeys(
        ("zero", "um", "dois", "duas", "tres", "três", "quatro", "cinco", "seis", "meia",
         "sete", "oito", "nove"), 1),
    **dict.fromkeys(
        ("dez", "onze", "doze", "treze", "catorze", "quatorze", "quinze", "dezesseis",
         "dezessete", "dezoito", "dezenove", "vinte", "trinta", "quarenta", "cinquenta",
         "sessenta", "setenta", "oitenta", "noventa"), 2),
}  # fmt: skip
_TOKEN = r"(?:\d[️⃣]*|\b(?:" + "|".join(_PALAVRAS_DIGITO) + r")\b)"
_SEP = r"[\s().\-_*•·]*"
_SEQUENCIA = re.compile(rf"[+(]?{_TOKEN}(?:{_SEP}{_TOKEN})*", re.IGNORECASE)
_CANAL = re.compile(
    r"(zap|whats|wpp|watsap|telegram|fone|telefone|celular|cel\b|contato|liga[rm]?\b|ligue|chama)",
    re.IGNORECASE,
)
_MILHAR = re.compile(r"\d{1,3}(?:\.\d{3})+")
_DATA = re.compile(r"\d{1,2}[.\-]\d{1,2}[.\-]\d{2,4}")
_DECIMAL_DEPOIS = re.compile(r"\s?,\d{1,2}(?!\d)")

_EMAIL = re.compile(
    r"[\w.+-]{2,64}\s*(?:@|\(\s*at\s*\)|\[\s*at\s*\]|\{\s*at\s*\}|\barroba\b)\s*"
    r"[\w-]{1,63}(?:\s*(?:\.|\(\s*dot\s*\)|\[\s*dot\s*\]|\bponto\b|\bdot\b)\s*[\w-]{1,63}){1,6}"
    r"|[\w.+-]{2,64}\s+at\s+[\w-]{1,63}\s+dot\s+[\w-]{1,63}(?:\s+dot\s+[\w-]{1,63}){0,4}",
    re.IGNORECASE,
)
_PONTO_COM = re.compile(
    r"\b[\w-]{1,63}\s+(?:ponto|dot)\s+(?:com\s+(?:ponto\s+)?br\b|net\b|org\b|me\b|ly\b"
    r"|com(?=\s*(?:[.,;!?]|$)))",
    re.IGNORECASE,
)
_PERFIL = re.compile(
    r"\b(?:insta(?:gram)?|telegram|tiktok|face(?:book)?|twitter|snap(?:chat)?|kwai)\b"
    r"\s*(?::|=|-|é|eh)\s*@?([\w.]{4,30})",
    re.IGNORECASE,
)
_ARROBA = re.compile(r"(?<![\w@.])@[A-Za-z0-9_.]{4,30}")
_RUA = re.compile(
    r"\b(?:rua|r\.|avenida|av\.?|travessa|tv\.|alameda|rodovia|estrada|pra[çc]a|largo|quadra|qd)\s+"
    r"[^\n,;:]{2,50}?,?\s*(?:n[ºo°.]*\s*)?\d{1,5}\b",
    re.IGNORECASE,
)
_CEP = re.compile(r"\b\d{5}-\d{3}\b|\bcep\s*:?\s*\d{5}-?\d{3}\b", re.IGNORECASE)


@dataclass(frozen=True)
class ResultadoMascara:
    original: str
    exibido: str
    categorias: frozenset[str] = field(default_factory=frozenset)

    @property
    def mascarada(self) -> bool:
        return self.exibido != self.original


def _contagem_digitos(trecho: str) -> int:
    return sum(
        1 if token.group(0)[0].isdigit() else _PALAVRAS_DIGITO[token.group(0).lower()]
        for token in re.finditer(_TOKEN, trecho, re.IGNORECASE)
    )


def _eh_dinheiro_ou_data(texto: str, ini: int, fim: int) -> bool:
    trecho = texto[ini:fim].strip("+() ")
    if "$" in texto[max(0, ini - 4) : ini]:
        return True
    if _MILHAR.fullmatch(trecho) or _DATA.fullmatch(trecho):
        return True
    return bool(_DECIMAL_DEPOIS.match(texto, fim)) and "," in texto[fim : fim + 4]


def _mascarar_telefones(texto: str, minimo: int, minimo_canal: int) -> tuple[str, bool]:
    achou = False

    def trocar(m: re.Match[str]) -> str:
        nonlocal achou
        digitos = _contagem_digitos(m.group(0))
        antes = texto[max(0, m.start() - 30) : m.start()]
        limite = minimo_canal if _CANAL.search(antes) else minimo
        if digitos < limite or _eh_dinheiro_ou_data(texto, m.start(), m.end()):
            return m.group(0)
        achou = True
        return AVISO_MASCARA

    return _SEQUENCIA.sub(trocar, texto), achou


def _perfil_suspeito(m: re.Match[str]) -> str:
    alvo = m.group(1)
    if "@" in m.group(0) or re.search(r"[._\d]", alvo) or len(alvo) >= 8:
        return AVISO_MASCARA
    return m.group(0)


def mascarar(texto: str, config: ConfigSeguranca | None = None) -> ResultadoMascara:
    config = config or obter_config_seguranca()
    atual = texto
    categorias: set[str] = set()

    def passo(nome: str, padrao: re.Pattern[str], repl: str | object = AVISO_MASCARA) -> None:
        nonlocal atual
        novo = padrao.sub(repl, atual)  # type: ignore[arg-type]
        if novo != atual:
            categorias.add(nome)
            atual = novo

    passo("email", _EMAIL)
    passo("link", _PONTO_COM)
    tlds = "|".join(re.escape(t) for t in config.mascara_tlds)
    link = re.compile(
        rf"(?:https?://|www\.)\S+|\b[\w-]{{1,63}}(?:\.[\w-]{{1,63}}){{0,5}}\.(?:{tlds})\b(?:/\S*)?(?![\w@])",
        re.IGNORECASE,
    )
    passo("link", link)
    passo("rede_social", _PERFIL, _perfil_suspeito)
    passo("rede_social", _ARROBA)
    atual, telefone = _mascarar_telefones(
        atual, config.mascara_min_digitos, config.mascara_min_digitos_com_canal
    )
    if telefone:
        categorias.add("telefone")
    passo("endereco", _RUA)
    passo("endereco", _CEP)
    return ResultadoMascara(texto, atual, frozenset(categorias))


def mascarar_contatos(texto: str) -> str:
    """Só o texto exibido (compatível com o uso antigo em `persistencia/conversas.py`)."""
    return mascarar(texto).exibido
