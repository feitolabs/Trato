"""Avisos (notificações) disparados por rotas do app: mensagem nova e orçamento recebido.

Aviso é secundário: se falhar, a ação que o gerou (mensagem, orçamento) já está gravada e segue.
O texto da mensagem nunca vai na notificação (pode ter dado pessoal).
"""

from __future__ import annotations

import logging
import uuid
from collections.abc import Collection, Sequence
from datetime import UTC, datetime, timedelta
from zoneinfo import ZoneInfo

from fastapi import Request

from trato.api.contexto import Contexto
from trato.api.exclusividades import Encerramento, Exclusividade
from trato.api.visibilidade import pedido_visivel_ao_profissional
from trato.notificacoes.eventos import Evento
from trato.profissional.nota import minimo_de_avaliacoes

log = logging.getLogger("trato.notificacoes")
_FUSO_BR = ZoneInfo("America/Sao_Paulo")
JANELA_A_CAMINHO_MINUTOS = 10  # não repete o aviso "a caminho" do mesmo pedido nesse intervalo


def servicos_de_notificacao(request: Request, contexto: Contexto):  # type: ignore[no-untyped-def]
    """(ServicoNotificacoes, ServicoMensagens) deste app (montados uma vez)."""
    from trato.notificacoes.rotas import _servicos  # import tardio: evita ciclo

    return _servicos(request, contexto)


def avisar_mensagem_nova(
    request: Request,
    contexto: Contexto,
    *,
    conversa_id: str,
    pedido_id: str,
    autor_id: str,
    destinatario_id: str,
    mensagem_id: int,
) -> None:
    """Avisa quem recebeu. Várias mensagens seguidas, ainda sem leitura, geram um aviso só."""
    try:
        anteriores = list(contexto.conversas.listar(conversa_id))
        if len(anteriores) >= 2:
            anterior = anteriores[-2]
            if anterior.autor_id == autor_id and anterior.lida_em is None:
                return
        servico, _ = servicos_de_notificacao(request, contexto)
        servico.notificar(
            Evento.MENSAGEM_NOVA,
            destinatario_id,
            chave=f"{conversa_id}:{mensagem_id}",
            pedido_id=pedido_id,
            dados={
                "conversa_id": conversa_id,
                "profissional_id": _profissional(contexto, pedido_id, autor_id, destinatario_id),
            },
        )
    except Exception:  # noqa: BLE001 - aviso é secundário
        log.exception("Aviso de mensagem nova falhou")


def _profissional(contexto: Contexto, pedido_id: str, autor_id: str, destinatario_id: str) -> str:
    """Quem é o profissional da conversa (o cliente precisa dele para abrir o chat certo)."""
    pedido = contexto.pedidos.obter(pedido_id)
    if pedido is not None and autor_id == pedido.cliente_id:
        return destinatario_id
    return autor_id


def avisar_evento(
    request: Request,
    contexto: Contexto,
    evento: Evento,
    usuario_id: str,
    *,
    pedido_id: str,
    chave: str,
    corpo: str | None = None,
) -> None:
    """Aviso simples de um evento do pedido (NOT-1). Uma vez por `chave`; nunca levanta."""
    try:
        servico, _ = servicos_de_notificacao(request, contexto)
        servico.notificar(evento, usuario_id, chave=chave, pedido_id=pedido_id, corpo=corpo)
    except Exception:  # noqa: BLE001 - aviso é secundário
        log.exception("Aviso %s falhou", evento.value)


def avisar_orcamentos_nao_escolhidos(
    request: Request,
    contexto: Contexto,
    *,
    pedido_id: str,
    perdedores: Sequence[tuple[str, str]],
    vencedor_orcamento_id: str | None,
    vencedor_profissional_id: str | None,
) -> None:
    """Avisa quem perdeu porque o cliente ACEITOU outro orçamento (a recusa individual tem o
    seu próprio evento). Uma vez por orçamento (chave pedido+orçamento); falha de um aviso não
    impede os outros nem desfaz o aceite, que já foi confirmado."""
    for orcamento_id, profissional_id in perdedores:
        if orcamento_id == vencedor_orcamento_id or profissional_id == vencedor_profissional_id:
            continue
        avisar_evento(
            request,
            contexto,
            Evento.ORCAMENTO_NAO_ESCOLHIDO,
            profissional_id,
            pedido_id=pedido_id,
            chave=f"{pedido_id}:{orcamento_id}",
        )


def avisar_orcamento_recebido(
    request: Request,
    contexto: Contexto,
    *,
    pedido_id: str,
    cliente_id: str,
    orcamento_id: str,
) -> None:
    try:
        servico, _ = servicos_de_notificacao(request, contexto)
        servico.notificar(
            Evento.ORCAMENTO_RECEBIDO, cliente_id, chave=orcamento_id, pedido_id=pedido_id
        )
    except Exception:  # noqa: BLE001 - aviso é secundário
        log.exception("Aviso de orçamento recebido falhou")


def avisar_pedido_direcionado(
    request: Request,
    contexto: Contexto,
    *,
    pedido_id: str,
    profissional_id: str,
    titulo_pedido: str,
) -> None:
    try:
        servico, _ = servicos_de_notificacao(request, contexto)
        servico.notificar(
            Evento.PEDIDO_DIRECIONADO,
            profissional_id,
            chave=f"{pedido_id}:{profissional_id}",
            pedido_id=pedido_id,
            dados={"titulo": titulo_pedido},
        )
    except Exception:  # noqa: BLE001 - aviso é secundário
        log.exception("Aviso de pedido direcionado falhou")


def _eh_uuid(valor: str | None) -> bool:
    if not valor:
        return False
    try:
        uuid.UUID(valor)
        return True
    except ValueError:
        return False


MAX_PROFISSIONAIS_AVISO_PEDIDO_NOVO = 20


def _corpo_pedido_novo(
    modulo: object,
    *,
    categoria_id: str | None,
    cidade_id: str | None,
    bairro: str | None,
    remoto: bool,
) -> str | None:
    """Corpo curto só com categoria e cidade/bairro (ou Remoto). Nunca dado pessoal/endereço."""
    cat_nome: str | None = None
    cid_nome: str | None = None
    catalogo = getattr(modulo, "catalogo", None)
    if catalogo is not None:
        try:
            if categoria_id:
                cat_nome = next(
                    (
                        c.nome
                        for c in catalogo.categorias_publicas()
                        if c.id == categoria_id or getattr(c, "slug", None) == categoria_id
                    ),
                    None,
                )
            if cidade_id and not remoto:
                cid_nome = next(
                    (c.nome for c in catalogo.cidades_publicas() if c.id == cidade_id),
                    None,
                )
        except Exception:  # noqa: BLE001 - fallback para texto padrão do modelo
            log.debug("Catálogo indisponível para montar corpo de pedido novo", exc_info=True)
    bairro_limpo = (bairro or "").strip() or None
    if remoto:
        local = "Remoto"
    elif bairro_limpo and cid_nome:
        local = f"{bairro_limpo}, {cid_nome}"
    else:
        local = cid_nome or bairro_limpo
    partes = [p for p in (cat_nome, local) if p]
    return " · ".join(partes) if partes else None


def avisar_pedido_novo(
    request: Request,
    contexto: Contexto,
    *,
    pedido_id: str,
    categoria_id: str | None,
    cidade_id: str | None,
    bairro: str | None,
    cliente_id: str,
    remoto: bool = False,
    convidado_id: str | None = None,
    ja_notificados: Collection[str] = (),
    limite: int = MAX_PROFISSIONAIS_AVISO_PEDIDO_NOVO,
) -> None:
    """Avisa até `limite` profissionais elegíveis quando um pedido comum é aberto (após commit).

    Idempotente por `(pedido, profissional)`. Falha na leitura ou em um destinatário nunca
    desfaz a abertura do pedido nem impede os demais avisos."""
    if not categoria_id:
        return
    try:
        modulo = getattr(request.app.state, "modulo_profissional", None)
        if modulo is None or not hasattr(modulo.repo, "listar_elegiveis_para_pedido"):
            return
        excluir = tuple(dict.fromkeys(u for u in (cliente_id, convidado_id, *ja_notificados) if u))
        elegiveis = modulo.repo.listar_elegiveis_para_pedido(
            categoria_id,
            cidade_id,
            remoto=remoto,
            excluir_usuario_ids=excluir,
            limite=limite,
            detalhe=contexto.usuarios.detalhe,
            nota_minimo_avaliacoes=minimo_de_avaliacoes(contexto.config),
        )
        if not elegiveis:
            return
        servico, _ = servicos_de_notificacao(request, contexto)
        corpo = _corpo_pedido_novo(
            modulo,
            categoria_id=categoria_id,
            cidade_id=cidade_id,
            bairro=bairro,
            remoto=remoto,
        )
    except Exception:  # noqa: BLE001 - aviso é secundário
        log.exception("Leitura de elegíveis para aviso de pedido novo falhou")
        return
    for profissional_id in elegiveis:
        try:
            servico.notificar(
                Evento.PEDIDO_NOVO,
                profissional_id,
                chave=f"{pedido_id}:{profissional_id}",
                pedido_id=pedido_id,
                corpo=corpo,
            )
        except Exception:  # noqa: BLE001 - falha de um não bloqueia os outros
            log.exception("Aviso de pedido novo falhou para %s", profissional_id)


def avisar_pedido_urgente(
    request: Request,
    contexto: Contexto,
    *,
    pedido_id: str,
    categoria_id: str | None,
    cliente_id: str,
    titulo_pedido: str,
) -> None:
    """Notifica profissionais elegíveis com o modo 'Disponível agora' ativo."""
    try:
        modulo = getattr(request.app.state, "modulo_profissional", None)
        if modulo is None or not hasattr(modulo.repo, "listar_disponiveis_agora"):
            return
        disponiveis = modulo.repo.listar_disponiveis_agora()
        if not disponiveis:
            return
        servico, _ = servicos_de_notificacao(request, contexto)
        for perfil in disponiveis:
            if perfil.usuario_id == cliente_id:
                continue
            if categoria_id and categoria_id not in perfil.categorias:
                # No Postgres `perfil.categorias` guarda UUIDs e `DadosPedido.categoria_id` pode
                # chegar como slug na API; nesses casos, a visibilidade resolve a elegibilidade.
                misto_slug_uuid = not _eh_uuid(categoria_id) and any(
                    _eh_uuid(c) for c in perfil.categorias
                )
                if not misto_slug_uuid:
                    continue
            if pedido_visivel_ao_profissional(contexto, pedido_id, perfil.usuario_id) is None:
                continue
            servico.notificar(
                Evento.PEDIDO_URGENTE,
                perfil.usuario_id,
                chave=f"urgente:{pedido_id}:{perfil.usuario_id}",
                pedido_id=pedido_id,
                dados={"titulo": titulo_pedido},
            )
    except Exception:  # noqa: BLE001 - aviso é secundário
        log.exception("Aviso de pedido urgente falhou")


def avisar_check_in_sem_codigo(
    request: Request,
    contexto: Contexto,
    *,
    pedido_id: str,
    cliente_id: str,
) -> None:
    """Avisa o cliente que o profissional iniciou o serviço usando o Plano B (sem código)."""
    try:
        servico, _ = servicos_de_notificacao(request, contexto)
        servico.notificar(
            Evento.CHECK_IN_SEM_CODIGO,
            cliente_id,
            chave=f"check-in-sem-codigo:{pedido_id}",
            pedido_id=pedido_id,
        )
    except Exception:  # noqa: BLE001 - aviso é secundário
        log.exception("Aviso de check-in sem código falhou")


def avisar_a_caminho(
    request: Request,
    contexto: Contexto,
    *,
    pedido_id: str,
    cliente_id: str,
    eta_minutos: int | None,
    agora: datetime,
) -> bool:
    """Avisa o cliente que o profissional saiu. Uma vez por pedido a cada 10 minutos.

    Devolve `True` se enviou agora; `False` se já houve aviso nos últimos 10 minutos (ou se o
    envio falhou: aviso é secundário e não derruba a rota).
    """
    try:
        servico, _ = servicos_de_notificacao(request, contexto)
        recentes = servico.repo.listar(cliente_id, False, 200)
        limite = agora - timedelta(minutes=JANELA_A_CAMINHO_MINUTOS)
        if any(
            n.tipo == Evento.A_CAMINHO.value
            and n.dados.get("pedido_id") == pedido_id
            and n.criada_em > limite
            for n in recentes
        ):
            return False
        corpo = "Seu profissional avisou que está a caminho."
        if eta_minutos is not None:
            hora = agora.astimezone(_FUSO_BR).strftime("%H:%M")
            corpo = (
                f"Seu profissional avisou que está a caminho às {hora} "
                f"(previsão informada: cerca de {eta_minutos} min)."
            )
        servico.notificar(
            Evento.A_CAMINHO,
            cliente_id,
            chave=f"a-caminho:{pedido_id}:{int(agora.timestamp())}",
            pedido_id=pedido_id,
            corpo=corpo,
        )
        return True
    except Exception:  # noqa: BLE001 - aviso é secundário
        log.exception("Aviso de a caminho falhou")
        return False


def _hora_local(instante: datetime | None) -> str:
    if instante is None:
        return "o fim do prazo"
    com_fuso = instante if instante.tzinfo is not None else instante.replace(tzinfo=UTC)
    return com_fuso.astimezone(_FUSO_BR).strftime("%H:%M")


def avisar_exclusividade_oferta(
    request: Request,
    contexto: Contexto,
    *,
    exclusividade: Exclusividade,
) -> None:
    """Avisa o cliente sobre a oferta de prioridade (sem compromisso)."""
    try:
        servico, _ = servicos_de_notificacao(request, contexto)
        ate = contexto.exclusividades.prazo_de_resposta(exclusividade)
        prazo = (
            f"Você tem até {_hora_local(ate)} para responder."
            if ate is not None
            else "O prazo para responder está suspenso enquanto o aplicativo está instável."
        )
        servico.notificar(
            Evento.EXCLUSIVIDADE_OFERTA,
            exclusividade.cliente_id,
            chave=exclusividade.id,
            pedido_id=exclusividade.pedido_id,
            corpo=(
                f"Um profissional quer fazer seu serviço com prioridade. Sem compromisso. {prazo}"
            ),
            dados={"exclusividade_id": exclusividade.id},
        )
    except Exception:  # noqa: BLE001 - aviso é secundário
        log.exception("Aviso de oferta de exclusividade falhou")


def avisar_exclusividade_resposta(
    request: Request,
    contexto: Contexto,
    *,
    exclusividade: Exclusividade,
    decisao: str,
) -> None:
    """Avisa o profissional que o cliente aceitou ou recusou a prioridade."""
    try:
        servico, _ = servicos_de_notificacao(request, contexto)
        if decisao == "aceitar":
            servico.notificar(
                Evento.EXCLUSIVIDADE_ACEITA,
                exclusividade.profissional_id,
                chave=exclusividade.id,
                pedido_id=exclusividade.pedido_id,
                dados={"exclusividade_id": exclusividade.id},
            )
            return
        servico.notificar(
            Evento.EXCLUSIVIDADE_RECUSADA,
            exclusividade.profissional_id,
            chave=exclusividade.id,
            pedido_id=exclusividade.pedido_id,
            corpo=(
                "O cliente preferiu ver outros orçamentos. "
                f"Seus {exclusividade.moedas_cobradas} Tratinhos voltaram."
            ),
            dados={"exclusividade_id": exclusividade.id},
        )
    except Exception:  # noqa: BLE001 - aviso é secundário
        log.exception("Aviso de resposta da exclusividade falhou")


def avisar_exclusividade_encerrada(
    request: Request,
    contexto: Contexto,
    *,
    encerramento: Encerramento,
    pedido_id: str,
    moedas_cobradas: int = 100,
) -> None:
    """Avisa o profissional quando a prioridade é cancelada com estorno por mudança no pedido."""
    if encerramento.resultado != "cancelada":
        return
    try:
        servico, _ = servicos_de_notificacao(request, contexto)
        servico.notificar(
            Evento.EXCLUSIVIDADE_CANCELADA,
            encerramento.profissional_id,
            chave=encerramento.exclusividade_id,
            pedido_id=pedido_id,
            corpo=(
                "O pedido mudou antes do fim da prioridade que você ganhou avaliando. "
                f"Seus {moedas_cobradas} Tratinhos voltaram."
            ),
            dados={"exclusividade_id": encerramento.exclusividade_id},
        )
    except Exception:  # noqa: BLE001 - aviso é secundário
        log.exception("Aviso de encerramento da exclusividade falhou")


def avisar_partes(
    contexto: Contexto,
    evento: Evento,
    usuarios: Sequence[str | None],
    *,
    pedido_id: str,
    chave: str,
    corpo: str | None = None,
    dados: dict[str, str | None] | None = None,
) -> None:
    """Avisos obrigatórios (Termos 15.2) fora das transições. Usa o serviço montado com o app;
    sem ele não há o que fazer. Aviso nunca desfaz nem derruba o que já foi gravado."""
    notificador = contexto.extras.get("notificador")
    if notificador is None:
        return

    def enviar() -> None:
        for usuario in usuarios:
            if not usuario:
                continue
            try:
                notificador.notificar(
                    evento,
                    usuario,
                    chave=chave,
                    pedido_id=pedido_id,
                    corpo=corpo,
                    dados=dados,
                )
            except Exception:  # noqa: BLE001 - aviso é secundário
                log.exception("Aviso %s falhou", evento.value)

    contexto.depois_do_commit(enviar)
