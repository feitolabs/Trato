"""Erros das regras de disputa."""


class DisputaErro(Exception):
    """Base de todos os erros de disputa."""


class TransicaoInvalida(DisputaErro):
    """Estado atual ou ator não permite a operação."""


class PrazoExpirado(DisputaErro):
    """A operação veio depois do prazo."""


class ResultadoInvalido(DisputaErro):
    """Decisão inconsistente (ex.: parcial sem percentual, valor maior que o congelado)."""


class AlcadaInvalida(DisputaErro):
    """Decisão acima da alçada sem segunda pessoa válida."""
