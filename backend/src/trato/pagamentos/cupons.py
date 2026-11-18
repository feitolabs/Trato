"""Validação e aplicação de cupons de desconto no checkout (Postgres + memória)."""

from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime
from typing import Any

from trato.api.contexto import Contexto


@dataclass(frozen=True)
class CupomAplicado:
    codigo: str
    tipo: str
    valor: int
    desconto_centavos: int
    servico_com_desconto_centavos: int


def _para_datetime(valor: Any) -> datetime | None:
    if valor is None or isinstance(valor, datetime):
        return valor
    if isinstance(valor, str) and valor.strip():
        return datetime.fromisoformat(valor.strip().replace("Z", "+00:00"))
    return None


def _buscar_cupom(contexto: Contexto, codigo: str) -> dict[str, Any] | None:
    banco = contexto.extras.get("banco") if contexto.extras else None
    if banco is not None:
        with banco.transacao() as con:
            linha = con.execute(
                "SELECT codigo, tipo, valor, valor_minimo_centavos, limite_usos, usos_atuais, "
                "valido_desde, valido_ate, ativo FROM public.cupons WHERE codigo = %s",
                (codigo,),
            ).fetchone()
            return dict(linha) if linha is not None else None
    cupons = contexto.extras.get("cupons") if contexto.extras else None
    if not isinstance(cupons, dict):
        return None
    achado = cupons.get(codigo)
    return dict(achado) if isinstance(achado, dict) else None


def validar_e_calcular_cupom(
    contexto: Contexto, codigo_bruto: str, servico_centavos: int
) -> CupomAplicado:
    """Valida regras de vigência, limite de usos e valor mínimo e devolve o novo valor."""
    codigo = codigo_bruto.strip().upper()
    if not codigo:
        raise ValueError("Informe um código de cupom.")
    dados = _buscar_cupom(contexto, codigo)
    if dados is None:
        raise ValueError("Cupom não encontrado ou inválido.")
    if not bool(dados.get("ativo", True)):
        raise ValueError("Este cupom está inativo.")

    agora = contexto.agora()
    valido_desde = _para_datetime(dados.get("valido_desde"))
    if valido_desde is not None and agora < valido_desde:
        raise ValueError("Este cupom ainda não entrou em vigor.")
    valido_ate = _para_datetime(dados.get("valido_ate"))
    if valido_ate is not None and agora > valido_ate:
        raise ValueError("Este cupom expirou.")

    limite_usos = dados.get("limite_usos")
    usos_atuais = int(dados.get("usos_atuais") or 0)
    if limite_usos is not None and usos_atuais >= int(limite_usos):
        raise ValueError("Este cupom atingiu o limite de usos.")

    minimo = int(dados.get("valor_minimo_centavos") or 0)
    if servico_centavos < minimo:
        reais = f"{minimo // 100:,}".replace(",", ".") + f",{minimo % 100:02d}"
        raise ValueError(f"Este cupom exige valor mínimo de serviço de R$ {reais}.")

    tipo = str(dados.get("tipo") or dados.get("tipo_desconto") or "percentual")
    bruto_valor = dados.get("valor")
    if bruto_valor is None:
        bruto_valor = dados.get("valor_desconto")
    valor = int(bruto_valor or 0)
    if valor <= 0:
        raise ValueError("Cupom com desconto inválido.")

    if tipo == "percentual":
        desconto_bruto = (servico_centavos * valor) // 100
    elif tipo in ("fixo", "valor_fixo"):
        desconto_bruto = valor
    else:
        raise ValueError("Tipo de desconto desconhecido.")

    piso = 100 if servico_centavos >= 100 else 0
    servico_com_desconto = max(piso, servico_centavos - desconto_bruto)
    desconto_efetivo = servico_centavos - servico_com_desconto
    return CupomAplicado(
        codigo=codigo,
        tipo=tipo,
        valor=valor,
        desconto_centavos=desconto_efetivo,
        servico_com_desconto_centavos=servico_com_desconto,
    )


def registrar_uso_cupom(contexto: Contexto, codigo_bruto: str) -> None:
    """Incrementa o contador de usos quando a cobrança com cupom é criada."""
    codigo = codigo_bruto.strip().upper()
    if not codigo:
        return
    banco = contexto.extras.get("banco") if contexto.extras else None
    if banco is not None:
        with banco.transacao() as con:
            con.execute(
                "UPDATE public.cupons SET usos_atuais = usos_atuais + 1, "
                "atualizado_em = now() WHERE codigo = %s",
                (codigo,),
            )
        return
    cupons = contexto.extras.get("cupons")
    if isinstance(cupons, dict) and codigo in cupons and isinstance(cupons[codigo], dict):
        cupons[codigo]["usos_atuais"] = int(cupons[codigo].get("usos_atuais") or 0) + 1
