"""Termos 23.6: o pedido já contratado segue a regra do aceite (`contratos.regras_aplicadas`),
salvo se a vigente for mais favorável ao usuário. Só entram regras em que "mais favorável" não
prejudica o outro lado. Pisos e tetos legais são aplicados por quem usa o valor."""

from __future__ import annotations

from collections.abc import Mapping
from typing import Any, Literal

from trato.api.repositorios import Contrato

Sentido = Literal["maior", "menor"]
# Tetos que os Termos fixam: valem sobre o contratado e sobre o vigente.
TETOS = {"reagendamento_antecedencia_horas": 24}  # 7.5


def _congelado(contrato: Contrato | None, chave: str) -> int | None:
    """O valor publicado no momento do aceite; `None`: contrato sem regras ou sem a chave."""
    regras = getattr(contrato, "regras", None)
    parametros = regras.get("parametros") if isinstance(regras, Mapping) else None
    valor = parametros.get(chave) if isinstance(parametros, Mapping) else None
    if isinstance(valor, bool) or not isinstance(valor, int) or valor < 0:
        return None
    return valor


def regra_do_contrato(contrato: Contrato | None, chave: str, sentido: Sentido, vigente: int) -> int:
    """O mais favorável entre o contratado e o vigente. Sem o contratado: o vigente."""
    contratado = _congelado(contrato, chave)
    valor = vigente
    if contratado is not None:
        valor = max(contratado, vigente) if sentido == "maior" else min(contratado, vigente)
    return min(valor, TETOS[chave]) if chave in TETOS else valor


def dias_de_garantia(contexto: Any, contrato: Contrato | None) -> int | None:
    """`dias_contrato` para `abrir_garantia`: o prometido no orçamento; sem ele, o maior entre o
    padrão do aceite e o vigente da categoria. `None`: vale só a configuração vigente."""
    if contrato is None:
        return None
    if contrato.garantia_dias is not None and contrato.garantia_dias > 0:
        return contrato.garantia_dias
    chave = "garantia_retrabalho_dias_padrao"
    if _congelado(contrato, chave) is None:
        return None
    vigente = contexto.config.carregar().garantias.dias_da_categoria(contrato.categoria_id)
    return regra_do_contrato(contrato, chave, "maior", vigente)


def regras_do_aceite(config: Any) -> dict[str, Any]:
    """Só para o modo memória: o retrato que o Postgres grava em `regras_aplicadas`."""
    atual = config.carregar()
    parametros = {
        "arrependimento_dias": atual.arrependimento_dias,
        "ausencia_retencao_max_bps": atual.ausencia_retencao_max_bps,
        "garantia_retrabalho_dias_padrao": atual.garantias.garantia_dias_padrao,
    }
    horas = config.parametro_inteiro("reagendamento_antecedencia_horas")
    if horas is not None:
        parametros["reagendamento_antecedencia_horas"] = horas
    return {"parametros": parametros}
