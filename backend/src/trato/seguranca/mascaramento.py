"""Mascaramento de contato no chat (F8.1): antes e depois da contratação.

Depois da contratação passam o endereço e, na conversa com o profissional contratado (pagamento
confirmado, Termos 11.2), o telefone; e-mail, perfil (@usuário), link e número em mensagem que
fala em pagamento por fora continuam escondidos.

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
    r"(zap|whats|wpp|watsap|telegram|fone|telefone|celular|cel\b|\btel\b|contato|liga[rm]?\b"
    r"|ligue|chama)",
    re.IGNORECASE,
)
# "número" só vale como canal quando o número vem logo depois ("meu número é 9 9 8 8"): senão
# "o número do apto é 1203" viraria contato. E, com ele, um bloco único de dígitos ("1203") passa.
_CANAL_NUMERO = re.compile(
    r"\bn[uú]mero(?:\s+d[oe]s?\s+\w+)?\s*(?:é|eh|e|:|=|-)?\s*$", re.IGNORECASE
)
# Itens de uma sequência: número (grupo de dígitos), dezena composta ou número por extenso.
_ITEM = re.compile(rf"\d+|{_COMPOSTA}|\b(?:" + "|".join(_PALAVRAS_DIGITO) + r")\b", re.IGNORECASE)
# Sequência de numerais ISOLADOS (um dígito ou um número por extenso por vez) com este total de
# dígitos esconde mesmo sem "zap"/"fone": "9 9 8 8 7 7", "nove nove oito oito sete sete".
# Com "zap", "fone", "ligar", "chamar", "número" bastam 4 (config `mascara_min_digitos_com_canal`).
# Limite aceito: quem divide o número em várias mensagens não é pego aqui; só o aviso fixo ajuda.
_MINIMO_ISOLADOS = 6
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
_CEP_NUMERO = re.compile(r"\d{5}-\d{3}")
_DECIMAL_DEPOIS = re.compile(r"\s?,\d{1,2}(?!\d)")
# Com o telefone liberado, estes continuam escondidos: mais dígitos que um telefone com +55
# (CNPJ, cartão) e CPF formatado.
_MAXIMO_DIGITOS_TELEFONE = 13
_CPF_FORMATADO = re.compile(r"\d{3}\.\d{3}\.\d{3}-\d{2}")

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
    r"\b(?:insta(?:gram)?|i\s?g|telegram|tiktok|face(?:book)?|twitter|snap(?:chat)?|kwai"
    r"|zap|wpp|whats(?:app)?|watsap)\b"
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


def _digitos_do_item(item: str) -> int:
    if item[0].isdigit():
        return len(item)
    return _PALAVRAS_DIGITO.get(item.lower(), 2)  # fora da tabela = dezena composta


def _itens(trecho: str) -> list[str]:
    return [i.group(0) for i in _ITEM.finditer(trecho)]


def _maior_bloco_isolado(trecho: str) -> int:
    """Maior soma de dígitos de itens consecutivos que são 1 dígito ou número por extenso.
    Número de vários dígitos escritos juntos ("150", "2026") quebra o bloco: preço, medida e
    data não contam. Linear no tamanho do trecho."""
    melhor = atual = 0
    for item in _itens(trecho):
        if item[0].isdigit() and len(item) > 1:
            atual = 0
            continue
        atual += _digitos_do_item(item)
        melhor = max(melhor, atual)
    return melhor


def _eh_dinheiro_ou_data(texto: str, ini: int, fim: int) -> bool:
    trecho = texto[ini:fim].strip("+() ")
    if "$" in texto[max(0, ini - 4) : ini]:
        return True
    if _MILHAR.fullmatch(trecho) or _DATA.fullmatch(trecho) or _CEP_NUMERO.fullmatch(trecho):
        return True  # CEP (5-3) não é telefone; antes da contratação a regra de endereço o esconde
    return bool(_DECIMAL_DEPOIS.match(texto, fim)) and "," in texto[fim : fim + 4]


def _mascarar_telefones(
    texto: str, minimo: int, minimo_canal: int, liberar_telefone: bool = False
) -> tuple[str, bool]:
    achou = False

    def trocar(m: re.Match[str]) -> str:
        nonlocal achou
        digitos = _contagem_digitos(m.group(0))
        antes = texto[max(0, m.start() - 30) : m.start()]
        itens = _itens(m.group(0))
        com_canal = bool(_CANAL.search(antes))
        if not com_canal and _CANAL_NUMERO.search(antes) and len(itens) > 1:
            com_canal = True  # só número separado em partes; "número 1203" é endereço/pedido
        limite = minimo_canal if com_canal else minimo
        isolados = _maior_bloco_isolado(m.group(0)) >= _MINIMO_ISOLADOS
        if (digitos < limite and not isolados) or _eh_dinheiro_ou_data(texto, m.start(), m.end()):
            return m.group(0)
        if (
            liberar_telefone
            and digitos <= _MAXIMO_DIGITOS_TELEFONE
            and not _CPF_FORMATADO.search(m.group(0))
        ):
            return m.group(0)
        achou = True
        return AVISO_MASCARA

    return _SEQUENCIA.sub(trocar, texto), achou


# Palavras de frase que podem vir depois do nome da rede ("o ig caiu hoje", "na insta de ontem").
# Lista curta de propósito: o que NÃO está aqui, logo depois do nome de uma rede, é tratado como
# nome de usuário. Limite conhecido: "face externa" ou "zap lento" fora desta lista é escondido.
_PALAVRAS_DE_FRASE = frozenset(
    "de da do dos das para pra que e a o um uma caiu ontem hoje está esta tá ta no na em com foi "
    "vai tem não nao sim mas já ja é eh era ser fica ficou estava funciona funcionou parou travou "
    "deu dá amanhã amanha agora depois antes aqui lá la mais também tambem mesmo ainda quando se "
    "meu minha seu sua os as nos nas ao aos".split()
)


def _perfil_suspeito(m: re.Match[str]) -> str:
    alvo = m.group("alvo").rstrip(".")  # ponto final da frase não conta
    sep = (m.group("sep") or "").lower()
    baixo = alvo.lower()
    if baixo in _PALAVRAS_DIGITO or not re.search(r"[^\W\d_]", alvo):
        return m.group(0)  # número por extenso ou só dígitos: é telefone, a regra de dígitos cuida
    com_cara_de_usuario = bool(re.search(r"[._]|[A-Za-z]\d|\d[A-Za-z]", alvo))
    if "@" in m.group(0) or com_cara_de_usuario:
        return AVISO_MASCARA
    if sep in ("é", "eh"):  # "meu insta é joaopintor": exige nome longo (senão "o insta é bom")
        return AVISO_MASCARA if len(alvo) >= 8 else m.group(0)
    if baixo in _PALAVRAS_DE_FRASE:
        return m.group(0)
    return AVISO_MASCARA


def mascarar(
    texto: str,
    config: ConfigSeguranca | None = None,
    *,
    incluir_endereco: bool = True,
    liberar_telefone: bool = False,
) -> ResultadoMascara:
    """`incluir_endereco=False`: pedido já contratado (o endereço pode ser combinado).
    `liberar_telefone=True`: o telefone passa (quem chama confere a contratação)."""
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
    if not liberar_telefone:
        passo("telefone", _PICADO)
        passo("telefone", _BARRA)
    atual, telefone = _mascarar_telefones(
        atual,
        config.mascara_min_digitos,
        config.mascara_min_digitos_com_canal,
        liberar_telefone,
    )
    if telefone:
        categorias.add("telefone")
    if incluir_endereco:
        passo("endereco", _RUA)
        passo("endereco", _CEP)
    return ResultadoMascara(texto, atual, frozenset(categorias))


def mascarar_contatos(
    texto: str, *, incluir_endereco: bool = True, liberar_telefone: bool = False
) -> str:
    """Só o texto exibido (compatível com o uso antigo em `persistencia/conversas.py`)."""
    return mascarar(
        texto, incluir_endereco=incluir_endereco, liberar_telefone=liberar_telefone
    ).exibido
