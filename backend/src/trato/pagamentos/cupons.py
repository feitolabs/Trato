"""Validação, aplicação e contabilização segura de cupons (Postgres + memória)."""

from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime
from typing import Any

from trato.api.contexto import Contexto
from trato.persistencia.comum import como_uuid


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
                "SELECT codigo, tipo, valor, valor_minimo_centavos, limite_usos, "
                "limite_por_usuario, usos_atuais, valido_desde, valido_ate, ativo "
                "FROM public.cupons WHERE codigo = %s",
                (codigo,),
            ).fetchone()
            return dict(linha) if linha is not None else None
    cupons = contexto.extras.get("cupons") if contexto.extras else None
    if not isinstance(cupons, dict):
        return None
    achado = cupons.get(codigo)
    return dict(achado) if isinstance(achado, dict) else None


def _usos_do_usuario(contexto: Contexto, codigo: str, usuario_id: str) -> int:
    banco = contexto.extras.get("banco") if contexto.extras else None
    if banco is not None:
        uid = como_uuid(usuario_id)
        if uid is None:
            return 0
        with banco.transacao() as con:
            linha = con.execute(
                "SELECT count(*) AS total FROM public.cupom_usos "
                "WHERE cupom_codigo = %s AND usuario_id = %s",
                (codigo, uid),
            ).fetchone()
            return int(linha["total"] or 0) if linha is not None else 0
    usos = contexto.extras.get("cupom_usos") if contexto.extras else None
    if not isinstance(usos, dict):
        return 0
    return sum(
        1
        for item in usos.values()
        if isinstance(item, dict)
        and item.get("cupom_codigo") == codigo
        and item.get("usuario_id") == usuario_id
    )


def validar_e_calcular_cupom(
    contexto: Contexto,
    codigo_bruto: str,
    servico_centavos: int,
    usuario_id: str | None = None,
) -> CupomAplicado:
    """Valida vigência, limite total, limite por usuário e valor mínimo."""
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

    limite_por_usuario = dados.get("limite_por_usuario")
    if limite_por_usuario is not None and usuario_id:
        if _usos_do_usuario(contexto, codigo, usuario_id) >= int(limite_por_usuario):
            raise ValueError("Você já atingiu o limite de usos deste cupom.")

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


def registrar_uso_cupom(contexto: Contexto, codigo_bruto: str) -> bool:
    """Incrementa atomicamente `usos_atuais`, respeitando `limite_usos`."""
    codigo = codigo_bruto.strip().upper()
    if not codigo:
        return False
    banco = contexto.extras.get("banco") if contexto.extras else None
    if banco is not None:
        with banco.transacao() as con:
            atualizado = con.execute(
                "UPDATE public.cupons SET usos_atuais = usos_atuais + 1, "
                "atualizado_em = now() WHERE codigo = %s "
                "AND (limite_usos IS NULL OR usos_atuais < limite_usos) "
                "RETURNING codigo",
                (codigo,),
            ).fetchone()
            return atualizado is not None
    cupons = contexto.extras.get("cupons")
    if isinstance(cupons, dict) and codigo in cupons and isinstance(cupons[codigo], dict):
        cup = cupons[codigo]
        limite = cup.get("limite_usos")
        atual = int(cup.get("usos_atuais") or 0)
        if limite is not None and atual >= int(limite):
            return False
        cup["usos_atuais"] = atual + 1
        return True
    return False


def confirmar_uso_cupom(
    contexto: Contexto,
    codigo_bruto: str,
    *,
    usuario_id: str | None,
    cobranca_id: str,
    pedido_id: str,
    desconto_centavos: int = 0,
    confirmado_em: datetime | None = None,
) -> bool:
    """Contabiliza uso de cupom somente após webhook confirmado e de forma idempotente."""
    codigo = codigo_bruto.strip().upper()
    if not codigo or not cobranca_id:
        return False
    quando = confirmado_em or contexto.agora()
    banco = contexto.extras.get("banco") if contexto.extras else None
    if banco is not None:
        uid = como_uuid(usuario_id) if usuario_id else None
        pid = como_uuid(pedido_id)
        if uid is None or pid is None:
            return registrar_uso_cupom(contexto, codigo)
        with banco.transacao() as con:
            existe = con.execute(
                "SELECT 1 FROM public.cupons WHERE codigo = %s", (codigo,)
            ).fetchone()
            if existe is None:
                return False
            gravado = con.execute(
                "INSERT INTO public.cupom_usos "
                "(cupom_codigo, usuario_id, cobranca_id, pedido_id, desconto_centavos, "
                "confirmado_em) VALUES (%s, %s, %s, %s, %s, %s) "
                "ON CONFLICT (cobranca_id) DO NOTHING RETURNING id",
                (codigo, uid, cobranca_id, pid, max(0, int(desconto_centavos)), quando),
            ).fetchone()
            if gravado is None:
                return False
            atualizado = con.execute(
                "UPDATE public.cupons SET usos_atuais = usos_atuais + 1, "
                "atualizado_em = now() WHERE codigo = %s "
                "AND (limite_usos IS NULL OR usos_atuais < limite_usos) "
                "RETURNING codigo",
                (codigo,),
            ).fetchone()
            if atualizado is None:
                con.execute(
                    "DELETE FROM public.cupom_usos WHERE cobranca_id = %s",
                    (cobranca_id,),
                )
                return False
            return True

    usos = contexto.extras.setdefault("cupom_usos", {})
    if isinstance(usos, dict) and cobranca_id in usos:
        return False
    if not registrar_uso_cupom(contexto, codigo):
        return False
    if isinstance(usos, dict):
        usos[cobranca_id] = {
            "cupom_codigo": codigo,
            "usuario_id": usuario_id or "",
            "cobranca_id": cobranca_id,
            "pedido_id": pedido_id,
            "desconto_centavos": max(0, int(desconto_centavos)),
            "confirmado_em": quando,
        }
    return True


def custo_cupons_do_mes(contexto: Contexto, inicio: datetime, fim: datetime) -> int:
    """Soma o desconto efetivo concedido por cupons em pagamentos confirmados no período."""
    banco = contexto.extras.get("banco") if contexto.extras else None
    if banco is not None:
        with banco.transacao() as con:
            linha = con.execute(
                "SELECT coalesce(sum(desconto_centavos), 0) AS total "
                "FROM public.cupom_usos "
                "WHERE confirmado_em >= %s AND confirmado_em < %s",
                (inicio, fim),
            ).fetchone()
            return int(linha["total"] or 0) if linha is not None else 0
    usos = contexto.extras.get("cupom_usos") if contexto.extras else None
    if not isinstance(usos, dict):
        return 0
    total = 0
    for item in usos.values():
        if not isinstance(item, dict):
            continue
        quando = _para_datetime(item.get("confirmado_em"))
        if quando is not None and inicio <= quando < fim:
            total += int(item.get("desconto_centavos") or 0)
    return total
