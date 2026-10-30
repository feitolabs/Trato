"""Embrulho do repositório de conversas: depois de gravar a mensagem, procura sinais de contorno
da plataforma e abre FLAG para revisão humana. A mensagem em si nunca é bloqueada nem alterada
aqui (o mascaramento acontece no próprio repositório)."""

from __future__ import annotations

from dataclasses import replace
from typing import Any

from trato.seguranca.contorno import avaliar_contorno
from trato.seguranca.estado import Seguranca
from trato.seguranca.mascaramento import mascarar


class ConversasVigiadas:
    def __init__(self, interno: Any, seg: Seguranca) -> None:
        self._interno = interno
        self._seg = seg

    def __getattr__(self, nome: str) -> Any:
        return getattr(self._interno, nome)

    def enviar(self, conversa_id: str, autor_id: str, corpo: str) -> int:
        nova = self._interno.enviar(conversa_id, autor_id, corpo)
        try:
            self._avaliar(conversa_id, autor_id, corpo, nova)
        except Exception:  # noqa: BLE001 - antifraude nunca impede a mensagem de existir
            import logging

            logging.getLogger("trato.seguranca").exception("falha na avaliação de contorno")
        return nova

    def _avaliar(self, conversa_id: str, autor_id: str, corpo: str, mensagem_id: int) -> None:
        seg = self._seg
        masc = mascarar(corpo, seg.config)
        categorias = masc.categorias
        if categorias:
            # Só conta o contato escondido se o repositório de fato escondeu (pedido sem contrato).
            gravada = next(
                (m for m in self._interno.listar(conversa_id) if m.id == mensagem_id), None
            )
            if gravada is None or not gravada.mascarada:
                categorias = frozenset()
        sinal = avaliar_contorno(corpo, categorias, seg.config)
        if not sinal.sinalizar:
            return
        seg.auditar(
            "antifraude.contorno_plataforma",
            ator_id=autor_id,
            ator_tipo="sistema",
            depois={
                "pontuacao": sinal.pontuacao,
                "motivos": sinal.motivos,
                "mensagem_id": mensagem_id,
            },
        )
        aberta = next(
            (
                f
                for f in seg.flags.listar("aberta")
                if f.tipo == "contorno_plataforma" and f.usuario_id == autor_id
            ),
            None,
        )
        if aberta is None:
            seg.abrir_flag(
                "contorno_plataforma",
                "media",
                sinal.motivos,
                usuario_id=autor_id,
                detalhes={"ocorrencias": 1, "ultima_mensagem_id": mensagem_id},
            )
        else:
            detalhes = {
                **aberta.detalhes,
                "ocorrencias": int(aberta.detalhes.get("ocorrencias", 1)) + 1,
                "ultima_mensagem_id": mensagem_id,
            }
            motivos = tuple(dict.fromkeys((*aberta.motivos, *sinal.motivos)))
            seg.flags.atualizar(replace(aberta, detalhes=detalhes, motivos=motivos))
