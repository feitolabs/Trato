"""Proteção contra SMS pumping (D14: SMS só na confirmação do celular, uma vez por pessoa).

O Send SMS Hook do Supabase Auth chama `autorizar` ANTES de cada envio. Só envios autorizados
contam. Camadas: DDI permitido, intervalo mínimo crescente entre reenvios (backoff), limite por
número, por dispositivo, por IP e por faixa (números vizinhos, típico de pumping) e bloqueio
temporário ao estourar. Todo limite vem de `ConfigSeguranca`.
"""

from __future__ import annotations

import re
from dataclasses import dataclass

from trato.seguranca.estado import Seguranca

HORA = 3600
DIA = 86_400


@dataclass(frozen=True)
class DecisaoSms:
    permitido: bool
    motivo: str | None = None
    retry_apos_s: int = 0


def normalizar_telefone(bruto: str) -> str | None:
    """Só dígitos, formato E.164 sem o "+". `None` se não parece telefone."""
    digitos = re.sub(r"\D", "", bruto or "")
    if digitos.startswith("00"):
        digitos = digitos[2:]
    if not 10 <= len(digitos) <= 15:
        return None
    return digitos


class ProtecaoSms:
    def __init__(self, seg: Seguranca) -> None:
        self._s = seg
        self._c = seg.contadores
        self._cfg = seg.config

    def autorizar(
        self, telefone: str, dispositivo: str | None = None, ip: str | None = None
    ) -> DecisaoSms:
        cfg = self._cfg
        numero = normalizar_telefone(telefone)
        if numero is None:
            return self._negar("telefone_invalido", 0)
        if not any(numero.startswith(d) for d in cfg.sms_ddis_permitidos):
            return self._negar("pais_nao_permitido", 0)
        if numero.startswith("55") and len(numero) not in (12, 13):
            return self._negar("telefone_invalido", 0)

        h = self._s.hash_opaco
        k_num = f"sms:num:{h(numero)}"
        k_disp = f"sms:disp:{h(dispositivo)}" if dispositivo else None
        k_ip = f"sms:ip:{h(ip)}" if ip else None
        k_faixa = f"sms:faixa:{h(numero[: cfg.sms_faixa_digitos])}"
        k_disp_num = f"sms:dispnum:{h(dispositivo)}" if dispositivo else None

        for chave in (k_num, k_disp, k_ip, k_faixa):
            falta = self._c.bloqueado_por(chave) if chave else 0
            if falta:
                return self._negar("bloqueio_temporario", falta)

        # Backoff: o intervalo mínimo cresce a cada envio ao mesmo número.
        enviados_dia = self._c.quantos(k_num, DIA)
        ultimo = self._c.ultimo(k_num)
        if ultimo is not None and cfg.sms_backoff_base_s:
            espera = min(
                cfg.sms_backoff_base_s * cfg.sms_backoff_fator ** max(enviados_dia - 1, 0),
                cfg.sms_backoff_teto_s,
            )
            falta = int(ultimo + espera - self._c.agora()) + 1
            if falta > 0:
                return self._negar("reenvio_muito_rapido", falta)

        limites = (
            (k_num, HORA, cfg.sms_max_por_numero_hora, "limite_por_numero", False),
            (k_num, DIA, cfg.sms_max_por_numero_dia, "limite_por_numero", False),
            (k_disp, DIA, cfg.sms_max_por_dispositivo_dia, "limite_por_dispositivo", True),
            (k_ip, HORA, cfg.sms_max_por_ip_hora, "limite_por_ip", True),
            (k_faixa, HORA, cfg.sms_max_por_faixa_hora, "limite_por_faixa", True),
        )
        for chave, janela, maximo, motivo, suspeito in limites:
            if chave and self._c.quantos(chave, janela) >= maximo:
                return self._estourou(chave, motivo, janela, maximo, suspeito)

        # Muitos números diferentes no mesmo aparelho = padrão de abuso.
        if k_disp_num:
            h_num = h(numero)
            novo_para_o_aparelho = self._c.quantos(f"{k_disp_num}:{h_num}", DIA) == 0
            distintos = self._c.quantos(k_disp_num, DIA)
            if novo_para_o_aparelho and distintos >= cfg.sms_max_numeros_por_dispositivo_dia:
                return self._estourou(k_disp, "muitos_numeros_no_dispositivo", DIA, distintos, True)
            if novo_para_o_aparelho:
                self._c.adicionar(k_disp_num)
            self._c.adicionar(f"{k_disp_num}:{h_num}")

        for chave in (k_num, k_disp, k_ip, k_faixa):
            if chave:
                self._c.adicionar(chave)
        return DecisaoSms(True)

    def _negar(self, motivo: str, retry: int) -> DecisaoSms:
        self._s.auditar("antifraude.sms_negado", depois={"motivo": motivo, "retry_apos_s": retry})
        return DecisaoSms(False, motivo, retry)

    def _estourou(
        self, chave: str | None, motivo: str, janela: int, maximo: int, suspeito: bool
    ) -> DecisaoSms:
        retry = self._c.segundos_ate_liberar(chave or "", janela, maximo) if chave else 0
        bloqueio = self._cfg.sms_bloqueio_s
        if chave and bloqueio:
            novo = self._c.bloquear(chave, bloqueio)
            retry = max(retry, bloqueio)
            if novo:
                self._s.auditar(
                    "antifraude.sms_bloqueio_temporario",
                    depois={"motivo": motivo, "chave": chave.split(":")[1], "segundos": bloqueio},
                )
                if suspeito:
                    self._s.abrir_flag("sms_pumping", "media", (motivo,), detalhes={"chave": chave})
        return self._negar(motivo, retry)
