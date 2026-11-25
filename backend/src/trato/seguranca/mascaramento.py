"""Mascaramento de contato no chat (F8.1): SEMPRE, antes e depois da contratação.

Depois da contratação o endereço passa (o profissional precisa dele); telefone, e-mail, perfil
(@usuário) e link continuam escondidos.

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

AVISO_MASCARA = "[contato oculto]"

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
# Dezena composta por extenso ("noventa e oito") vale 2 dígitos.
_DEZENAS = r"(?:vinte|trinta|quarenta|cinquenta|sessenta|setenta|oitenta|noventa)"
_UNIDADES = r"(?:um|dois|duas|tres|três|quatro|cinco|seis|sete|oito|nove)"
_COMPOSTA = rf"\b{_DEZENAS}\s+e\s+{_UNIDADES}\b"
_TOKEN = rf"(?:\d[️⃣]*|{_COMPOSTA}|\b(?:" + "|".join(_PALAVRAS_DIGITO) + r")\b)"
_SEP = r"[\s().\-_*•·]*"
_SEQUENCIA = re.compile(rf"[+(]?{_TOKEN}(?:{_SEP}{_TOKEN})*", re.IGNORECASE)
_CANAL = re.compile(
    r"(zap|whats|wpp|watsap|telegram|fone|telefone|celular|cel\b|contato|liga[rm]?\b|ligue|chama)",
    re.IGNORECASE,
)
# Um dígito (ou um número por extenso de 1 dígito) separado por vírgula, barra ou "|":
# "9,8,7,6,5,4,3,2,1" e "nove, oito, sete...". Exige 8 em sequência (lista de preços não casa).
_DIGITO_SOLTO = (
    r"(?:(?<!\d)\d(?!\d)|\b(?:zero|um|dois|duas|tres|três|quatro|cinco|seis|meia|sete|oito|nove)\b)"
)
_PICADO = re.compile(rf"{_DIGITO_SOLTO}(?:\s*[,/|;]\s*{_DIGITO_SOLTO}){{7,}}", re.IGNORECASE)
# Celular com barra ou "|" no lugar do traço: "98765/4321", "11/98765/4321".
_BARRA = re.compile(
    r"(?<!\d)(?:\d{2}\s*[/|]\s*)?9\d{3,4}\s*[/|]\s*\d{4}(?!\d)"
    r"|(?<!\d)\d{2}\s*[/|]\s*\d{4}\s*[/|]\s*\d{4}(?!\d)"
)
_MILHAR = re.compile(r"\d{1,3}(?:\.\d{3})+")
_DATA = re.compile(r"\d{1,2}[.\-]\d{1,2}[.\-]\d{2,4}")
_DECIMAL_DEPOIS = re.compile(r"\s?,\d{1,2}(?!\d)")

_EMAIL = re.compile(
    r"[\w.+-]{2,64}\s*(?:@|[(\[{]\s*(?:at|arroba)\s*[)\]}]|\barroba\b)\s*"
    r"[\w-]{1,63}(?:\s*(?:\.|[(\[{]\s*(?:dot|ponto)\s*[)\]}]|\bponto\b|\bdot\b)\s*"
    r"[\w-]{1,63}){1,6}"
    r"|[\w.+-]{2,64}\s+at\s+[\w-]{1,63}\s+dot\s+[\w-]{1,63}(?:\s+dot\s+[\w-]{1,63}){0,4}",
    re.IGNORECASE,
)
_PONTO_COM = re.compile(
    r"\b[\w-]{1,63}\s+(?:ponto|dot)\s+(?:com\s+(?:ponto\s+)?br\b|net\b|org\b|me\b|ly\b"
    r"|com(?=\s*(?:[.,;!?]|$)))",
    re.IGNORECASE,
)
_PERFIL = re.compile(
    r"\b(?:insta(?:gram)?|ig|telegram|tiktok|face(?:book)?|twitter|snap(?:chat)?|kwai)\b"
    # Espaços limitados e sem dois "espaço-estrela" seguidos: evita backtracking quadrático.
    r"(?:\s{0,3}(?P<sep>:|=|-|\bé\b|\beh\b)\s{0,3}|\s{0,3})@?(?P<alvo>[\w.]{3,30})",
    re.IGNORECASE,
)
# @usuário: 3+ caracteres com ao menos uma letra ("@10" não é perfil).
_ARROBA = re.compile(r"(?<![\w@.])@(?=[\d_.]*[A-Za-z])[A-Za-z0-9_.]{3,30}")
# Domínio escrito com espaço antes do ponto: "joaopintor . com . br".
_DOMINIO_ESPACADO = re.compile(
    r"\b[\w-]{2,63}\s+\.\s*(?:com|net|org)\b(?:\s*\.\s*br\b)?", re.IGNORECASE
)
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


def _valor_do_token(token: str) -> int:
    if token[0].isdigit():
        return 1
    return _PALAVRAS_DIGITO.get(token.lower(), 2)  # fora da tabela = dezena composta


def _contagem_digitos(trecho: str) -> int:
    return sum(
        _valor_do_token(token.group(0)) for token in re.finditer(_TOKEN, trecho, re.IGNORECASE)
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
    alvo = m.group("alvo").rstrip(".")  # ponto final da frase não conta
    sep = (m.group("sep") or "").lower()
    com_cara_de_usuario = bool(re.search(r"[._]|[A-Za-z]\d|\d[A-Za-z]", alvo))
    if (
        "@" in m.group(0)
        or com_cara_de_usuario
        or (sep in (":", "=") and len(alvo) >= 4)
        or (sep and len(alvo) >= 8)
    ):
        return AVISO_MASCARA
    return m.group(0)


def mascarar(
    texto: str, config: ConfigSeguranca | None = None, *, incluir_endereco: bool = True
) -> ResultadoMascara:
    """`incluir_endereco=False`: pedido já contratado (o endereço pode ser combinado)."""
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
    passo("link", _DOMINIO_ESPACADO)
    tlds = "|".join(re.escape(t) for t in config.mascara_tlds)
    link = re.compile(
        rf"(?:https?://|www\.)\S+|\b[\w-]{{1,63}}(?:\.[\w-]{{1,63}}){{0,5}}\.(?:{tlds})\b(?:/\S*)?(?![\w@])",
        re.IGNORECASE,
    )
    passo("link", link)
    passo("rede_social", _PERFIL, _perfil_suspeito)
    passo("rede_social", _ARROBA)
    passo("telefone", _PICADO)
    passo("telefone", _BARRA)
    atual, telefone = _mascarar_telefones(
        atual, config.mascara_min_digitos, config.mascara_min_digitos_com_canal
    )
    if telefone:
        categorias.add("telefone")
    if incluir_endereco:
        passo("endereco", _RUA)
        passo("endereco", _CEP)
    return ResultadoMascara(texto, atual, frozenset(categorias))


def mascarar_contatos(texto: str, *, incluir_endereco: bool = True) -> str:
    """Só o texto exibido (compatível com o uso antigo em `persistencia/conversas.py`)."""
    return mascarar(texto, incluir_endereco=incluir_endereco).exibido
