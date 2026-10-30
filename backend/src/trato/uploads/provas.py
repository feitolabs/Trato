"""Confere a prova de check-in/check-out contra o que o servidor sabe.

O app manda o id de uma MÍDIA já registrada (foto enviada por `/v1/uploads`) e as coordenadas.
Aqui o servidor: confirma que a mídia existe, é deste pedido, é de quem faz a ação e tem a
finalidade certa; troca a hora da foto pela hora em que o servidor a recebeu; e calcula a
distância até o local do pedido (nunca confia em distância vinda do app).
"""

from __future__ import annotations

from dataclasses import replace

from trato.pedidos.estados import Acao, Foto, Pedido, ProvaCheckIn, ProvaCheckOut, ProvaInvalida
from trato.uploads.servico import ServicoUploads, distancia_metros


def _foto_do_servidor(
    servico: ServicoUploads, foto: Foto, pedido: Pedido, quem: str, finalidade: str
) -> Foto:
    midia = servico.repo.midia(foto.arquivo_id)
    if (
        midia is None
        or midia.pedido_id != pedido.id
        or midia.enviada_por != quem
        or midia.finalidade != finalidade
    ):
        raise ProvaInvalida("Envie a foto pelo app antes de confirmar.")
    return replace(foto, tirada_em=midia.criada_em)  # hora SEMPRE do servidor


def validar_prova_midia(
    servico: ServicoUploads, pedido: Pedido, usuario_id: str, acao: Acao, prova: object
) -> object:
    if acao is Acao.FAZER_CHECK_IN and isinstance(prova, ProvaCheckIn):
        foto = _foto_do_servidor(servico, prova.foto, pedido, usuario_id, "checkin")
        alvo = servico.local_do_pedido(pedido.id)
        if alvo is not None:
            metros = distancia_metros(
                prova.localizacao.latitude, prova.localizacao.longitude, alvo[0], alvo[1]
            )
            if metros > servico.config.checkin_distancia_max_m:
                raise ProvaInvalida("Você parece estar longe do local do serviço.")
        return replace(prova, foto=foto)
    if acao is Acao.FAZER_CHECK_OUT and isinstance(prova, ProvaCheckOut):
        foto = _foto_do_servidor(servico, prova.foto_final, pedido, usuario_id, "checkout")
        return replace(prova, foto_final=foto)
    return prova
