"""Regras do ciclo de vida da configuração versionada (puras, sem banco).

rascunho -> aguardando_aprovacao -> aprovada -> vigente -> substituida | revertida

O banco repete as regras que ele consegue garantir (versão aprovada imutável, uma só vigente,
`criada_por <> aprovada_por`, faixas sem sobreposição, mínimo/máximo). Aqui ficam as que ele não
consegue (faixas sem buraco) e as mensagens claras antes de o banco recusar.
"""

from __future__ import annotations

from collections.abc import Sequence
from datetime import datetime

from trato.api.admin.repositorios import DefinicaoConfig, FaixaTaxa, ParametroConfig, VersaoConfig
from trato.disputas import AlcadaInvalida
from trato.persistencia.config import CHAVES_DISPUTA
from trato.persistencia.erros import DadosInvalidos, RegraDoBanco

ESCOPOS = ("global", "cidade", "categoria", "nivel")
# O resto do backend responde 503 sem estas chaves: uma versão sem elas não pode virar vigente.
CHAVES_OBRIGATORIAS = ("adiantamento_bps", *CHAVES_DISPUTA)
EDITAVEIS = ("rascunho", "aguardando_aprovacao")


def _chave_escopo(item: ParametroConfig | FaixaTaxa) -> tuple[str, str | None, str | None]:
    return (item.escopo_tipo, item.escopo_id, item.escopo_texto)


def _validar_escopo(item: ParametroConfig | FaixaTaxa) -> None:
    tipo = item.escopo_tipo
    if tipo not in ESCOPOS:
        raise DadosInvalidos(f"Escopo inválido: {tipo}.")
    if tipo == "global":
        ok = item.escopo_id is None and item.escopo_texto is None
    elif tipo in ("cidade", "categoria"):
        ok = item.escopo_id is not None and item.escopo_texto is None
    else:
        ok = item.escopo_id is None and item.escopo_texto is not None
    if not ok:
        raise DadosInvalidos(f"O escopo '{tipo}' veio com os campos de escopo errados.")


def validar_itens(
    definicoes: Sequence[DefinicaoConfig],
    parametros: Sequence[ParametroConfig],
    faixas: Sequence[FaixaTaxa],
) -> None:
    """Valida o conteúdo de um rascunho (o que o banco também valida, com mensagem clara)."""
    por_chave = {d.chave: d for d in definicoes}
    vistos = set()
    for p in parametros:
        definicao = por_chave.get(p.chave)
        if definicao is None:
            raise DadosInvalidos(f"O parâmetro '{p.chave}' não existe no catálogo.")
        _validar_escopo(p)
        if p.escopo_tipo not in definicao.escopos_permitidos:
            raise DadosInvalidos(f"O parâmetro '{p.chave}' não aceita o escopo '{p.escopo_tipo}'.")
        if definicao.minimo is not None and p.valor < definicao.minimo:
            raise DadosInvalidos(f"'{p.chave}' abaixo do mínimo ({definicao.minimo}).")
        if definicao.maximo is not None and p.valor > definicao.maximo:
            raise DadosInvalidos(f"'{p.chave}' acima do máximo ({definicao.maximo}).")
        repetido = (p.chave, *_chave_escopo(p))
        if repetido in vistos:
            raise DadosInvalidos(f"O parâmetro '{p.chave}' aparece duas vezes no mesmo escopo.")
        vistos.add(repetido)
    for f in faixas:
        _validar_escopo(f)
        if f.de_centavos < 0 or not 0 <= f.taxa_bps <= 10_000:
            raise DadosInvalidos("Faixa de taxa com valor ou percentual fora do permitido.")
        if f.ate_centavos is not None and f.ate_centavos <= f.de_centavos:
            raise DadosInvalidos("Faixa de taxa: 'ate' deve ser maior que 'de'.")
    _sem_sobreposicao(faixas)


def _sem_sobreposicao(faixas: Sequence[FaixaTaxa]) -> None:
    por_escopo: dict[tuple[str, str | None, str | None], list[FaixaTaxa]] = {}
    for f in faixas:
        por_escopo.setdefault(_chave_escopo(f), []).append(f)
    for grupo in por_escopo.values():
        grupo.sort(key=lambda f: f.de_centavos)
        for a, b in zip(grupo, grupo[1:], strict=False):
            if a.ate_centavos is None or a.ate_centavos > b.de_centavos:
                raise DadosInvalidos("As faixas de taxa se sobrepõem.")


def mesclar(
    base_parametros: Sequence[ParametroConfig],
    base_faixas: Sequence[FaixaTaxa],
    parametros: Sequence[ParametroConfig],
    faixas: Sequence[FaixaTaxa],
) -> tuple[list[ParametroConfig], list[FaixaTaxa]]:
    """Rascunho a partir da versão vigente: o que veio troca o da base; faixas novas substituem
    todas as da base."""
    trocadas = {(p.chave, *_chave_escopo(p)) for p in parametros}
    herdados = [p for p in base_parametros if (p.chave, *_chave_escopo(p)) not in trocadas]
    return [*herdados, *parametros], list(faixas) if faixas else list(base_faixas)


def validar_publicavel(versao: VersaoConfig) -> None:
    """Pronta para valer: tem o que o backend exige e as faixas de taxa fecham."""
    globais = {p.chave for p in versao.parametros if p.escopo_tipo == "global"}
    faltam = [c for c in CHAVES_OBRIGATORIAS if c not in globais]
    if faltam:
        raise DadosInvalidos(f"Faltam parâmetros globais obrigatórios: {', '.join(faltam)}.")
    if not any(f.escopo_tipo == "global" for f in versao.faixas):
        raise DadosInvalidos("Faltam as faixas de taxa globais.")
    validar_faixas_completas(versao.faixas)


def validar_faixas_completas(faixas: Sequence[FaixaTaxa]) -> None:
    """Por escopo: começa em 0, sem sobreposição, sem buraco, e a última não tem teto."""
    por_escopo: dict[tuple[str, str | None, str | None], list[FaixaTaxa]] = {}
    for f in faixas:
        por_escopo.setdefault(_chave_escopo(f), []).append(f)
    for grupo in por_escopo.values():
        grupo.sort(key=lambda f: f.de_centavos)
        esperado = 0
        for f in grupo:
            if f.de_centavos != esperado:
                raise DadosInvalidos("As faixas de taxa têm buraco ou se sobrepõem.")
            if f.ate_centavos is None:
                esperado = -1
                continue
            if esperado == -1:
                raise DadosInvalidos("Há faixa depois da faixa sem teto.")
            esperado = f.ate_centavos
        if esperado != -1:
            raise DadosInvalidos("A última faixa de taxa deve ficar sem teto.")


def exigir_status(versao: VersaoConfig, *permitidos: str) -> None:
    if versao.status not in permitidos:
        raise RegraDoBanco(
            f"A versão {versao.numero} está '{versao.status}': esta operação só vale em "
            f"{' ou '.join(permitidos)}."
        )


def exigir_outra_pessoa(versao: VersaoConfig, aprovador_id: str) -> None:
    if aprovador_id == versao.criada_por:
        raise AlcadaInvalida("Quem propôs a versão não pode aprová-la: precisa de outra pessoa.")


def exigir_vigencia_chegou(versao: VersaoConfig, agora: datetime) -> None:
    if versao.vigente_desde is not None and versao.vigente_desde > agora:
        raise RegraDoBanco("A data de início de vigência dessa versão ainda não chegou.")
