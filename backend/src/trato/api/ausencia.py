"""Cliente ausente (Termos 7.6).

1. O profissional registra a chegada (`/ausencia/chegada`); a falta automática dele fica bloqueada.
2. Depois da espera (20 min, configuração) sem resposta do cliente, registra "Cliente ausente" pela
   ação de sempre (`/acoes/registrar_cliente_ausente`): o cliente é avisado e tem 24 h.
3. O cliente justifica com texto e anexos; o analista decide (`api/admin/rotas_ausencias.py`).
"""

from __future__ import annotations

from contextlib import suppress
from dataclasses import replace
from datetime import timedelta

from fastapi import APIRouter, Depends, HTTPException, Request
from pydantic import BaseModel, ConfigDict, Field

from trato.api.ausencia_base import (
    AnexoOut,
    AusenciaOut,
    anexos_do_caso,
    caso_de,
    contestar_ate,
    do_pedido,
    justificativa_ate,
    midia_do_pedido,
    pode_registrar_em,
    revisao_de,
    saida,
    sem_dados_do_cliente,
    uma_por_vez,
)
from trato.api.auth import PapelUsuario, Usuario
from trato.api.avisos import avisar_partes
from trato.api.cautela import exigir_contato_livre
from trato.api.contexto import (
    Contexto,
    exigir_papel,
    obter_contexto,
    usuario_do_proprio_pedido,
)
from trato.api.modelos import ClienteAusenteIn, FotoIn
from trato.api.servicos import ator_de, carregar_pedido
from trato.disputas.prazos import adicionar_dias_uteis
from trato.notificacoes.eventos import Evento
from trato.pedidos import estados
from trato.pedidos.estados import Acao, Estado, Pedido
from trato.persistencia.ausencias import (
    AGUARDANDO_ESPERA,
    AGUARDANDO_JUSTIFICATIVA,
    EM_ANALISE,
    PENDENTES,
    Ausencia,
)
from trato.persistencia.cancelamentos import PROPOSTA
from trato.persistencia.chamados import Revisao
from trato.uploads.provas import validar_prova_midia

router = APIRouter(prefix="/v1/pedidos", tags=["cliente ausente"])


class JustificativaIn(BaseModel):
    model_config = ConfigDict(extra="forbid")

    texto: str = Field(min_length=1, max_length=2000)
    anexos: list[FotoIn] = Field(default_factory=list, max_length=10)


# --- usado pela ação `registrar_cliente_ausente` (rotas_pedidos) ----------------------------------


def conferir_espera(contexto: Contexto, pedido: Pedido) -> Ausencia | None:
    """Com chegada registrada, só vale depois da espera e sem resposta do cliente. Sem a tabela
    (ou sem chegada, com a exigência desligada) o registro antigo segue, sem prazo nem efeito."""
    if not contexto.ausencias.disponivel():
        return None
    item = do_pedido(contexto, pedido)
    if item is None:
        if contexto.config.carregar().ausencia_exigir_chegada:
            raise HTTPException(409, "Registre a sua chegada e espere antes de marcar a ausência.")
        return None
    libera = pode_registrar_em(item)
    if contexto.agora() < libera:
        faltam = int((libera - contexto.agora()).total_seconds() // 60) + 1
        raise HTTPException(409, f"Espere mais {faltam} min pelo cliente antes de registrar.")
    conversa = contexto.conversas.abrir(pedido.id, pedido.profissional_id)
    if any(
        m.autor_id == pedido.cliente_id and m.enviada_em >= item.chegada_em
        for m in contexto.conversas.listar(conversa)
    ):
        raise HTTPException(
            409, "O cliente respondeu depois da sua chegada. Combinem pelo chat ou remarquem."
        )
    return item


def abrir_justificativa(contexto: Contexto, item: Ausencia) -> None:
    """Dentro da transação do registro: começa o prazo e avisa o cliente (app e e-mail)."""
    agora = contexto.agora()
    ate = agora + timedelta(hours=item.prazo_horas)
    novo = replace(
        item,
        status=AGUARDANDO_JUSTIFICATIVA,
        registrada_em=agora,
        avisado_em=agora,
        justificativa_ate=ate,
    )
    if contexto.ausencias.mudar(novo, (AGUARDANDO_ESPERA,)):
        avisar_partes(
            contexto,
            Evento.AUSENCIA_JUSTIFICAR,
            (item.cliente_id,),
            pedido_id=item.pedido_id,
            chave=f"{item.pedido_id}:ausencia:{int(item.janela_inicio.timestamp())}",
            corpo=f"O profissional registrou que você não estava no local. Você tem "
            f"{item.prazo_horas} horas para justificar no pedido, com texto e anexos.",
        )


def barrar_cancelamento(contexto: Contexto, pedido: Pedido, dentro_dos_7_dias: bool) -> None:
    """Fora do arrependimento, o cliente não troca a análise da ausência por um cancelamento
    comum (7.6). Dentro dos 7 dias o direito é integral e passa."""
    if dentro_dos_7_dias:
        return
    item = do_pedido(contexto, pedido)
    if item is not None and item.status in PENDENTES:
        raise HTTPException(
            409,
            "Há um registro de cliente ausente neste pedido em análise. Envie a sua "
            "justificativa; o analista decide o cancelamento.",
        )


# --- rotas ----------------------------------------------------------------------------------------


def _anexos_do_autor(
    request: Request, pedido: Pedido, usuario: Usuario, anexos: list[FotoIn]
) -> tuple[str, ...]:
    """Só vale arquivo enviado por esta pessoa, para este pedido."""
    servico = getattr(request.app.state, "servico_uploads", None)
    ids = tuple(f.arquivo_id for f in anexos)
    if servico is not None:
        for arquivo in ids:
            midia = midia_do_pedido(servico, arquivo, pedido.id)
            if midia is None or str(midia.enviada_por).replace("-", "") != usuario.id.replace(
                "-", ""
            ):
                raise HTTPException(422, "Envie o arquivo pelo app, neste pedido.")
    return ids


def _pedido_e_registro(
    contexto: Contexto, pedido_id: str, usuario: Usuario
) -> tuple[Pedido, Ausencia]:
    pedido = carregar_pedido(contexto, pedido_id, usuario)
    item = do_pedido(contexto, pedido)
    if item is None:
        raise HTTPException(404, "Este agendamento não tem registro de chegada.")
    return pedido, item


@router.post(
    "/{pedido_id}/ausencia/chegada",
    response_model=AusenciaOut,
    summary="Profissional: cheguei ao local",
    description="Mesma prova do 'cliente ausente' (foto e local). Repetir devolve a primeira.",
)
def registrar_chegada(
    pedido_id: str,
    corpo: ClienteAusenteIn,
    request: Request,
    usuario: Usuario = Depends(exigir_papel(PapelUsuario.PROFISSIONAL)),
    contexto: Contexto = Depends(obter_contexto),
) -> AusenciaOut:
    pedido = carregar_pedido(contexto, pedido_id, usuario)
    if pedido.profissional_id != usuario.id:
        raise HTTPException(403, "Só o profissional do pedido registra a chegada.")
    if not contexto.ausencias.disponivel():
        raise HTTPException(503, "O registro de chegada ainda não está disponível.")
    with uma_por_vez(contexto, pedido_id):
        pedido = carregar_pedido(contexto, pedido_id, usuario)
        item = do_pedido(contexto, pedido)
        if item is not None and pedido.estado is Estado.AGENDADO:
            return sem_dados_do_cliente(saida(contexto, item))
        prova = corpo.para_regra()
        servico_uploads = getattr(request.app.state, "servico_uploads", None)
        if servico_uploads is not None:
            prova = validar_prova_midia(
                servico_uploads, pedido, usuario.id, Acao.REGISTRAR_CLIENTE_AUSENTE, prova
            )
        agora = contexto.agora()
        cfg = contexto.config.carregar()
        # Ensaio da regra de estado (quem, quando e prova), sem gravar a ausência.
        estados.transicionar(
            pedido,
            Acao.REGISTRAR_CLIENTE_AUSENTE,
            ator_de(usuario, pedido),
            agora,
            prova,
            cfg.prazos_pedido,
        )
        item = contexto.ausencias.abrir(
            Ausencia(
                pedido_id=pedido.id,
                cliente_id=pedido.cliente_id,
                profissional_id=usuario.id,
                janela_inicio=pedido.janela.inicio,
                chegada_em=agora,
                espera_minutos=max(20, cfg.ausencia_espera_minutos),
                prazo_horas=max(24, cfg.ausencia_justificativa_horas),
                # Só a foto conferida pelo serviço de envio; serviço remoto não tem foto.
                foto_chegada=prova.foto.arquivo_id
                if servico_uploads is not None and prova.foto is not None and not pedido.remoto
                else None,
            )
        )
        with suppress(Exception):
            # 9.6: com o contato bloqueado a chegada vale como prova, mas não vira mensagem
            exigir_contato_livre(contexto, pedido, usuario.id)
            conversa = contexto.conversas.abrir(pedido.id, usuario.id)
            contexto.conversas.enviar(
                conversa,
                usuario.id,
                f"Cheguei ao local. Vou aguardar {item.espera_minutos} minutos.",
            )
        avisar_partes(
            contexto,
            Evento.PROFISSIONAL_CHEGOU,
            (pedido.cliente_id,),
            pedido_id=pedido.id,
            chave=f"{pedido.id}:chegada:{int(item.janela_inicio.timestamp())}",
        )
    return sem_dados_do_cliente(saida(contexto, item))


@router.get("/{pedido_id}/ausencia", response_model=AusenciaOut, summary="Ver o caso de ausência")
def ver_ausencia(
    pedido_id: str,
    usuario: Usuario = Depends(usuario_do_proprio_pedido),
    contexto: Contexto = Depends(obter_contexto),
) -> AusenciaOut:
    pedido, item = _pedido_e_registro(contexto, pedido_id, usuario)
    if usuario.id == pedido.cliente_id:
        return saida(contexto, item)
    return sem_dados_do_cliente(saida(contexto, item))


@router.post(
    "/{pedido_id}/ausencia/justificativa",
    response_model=AusenciaOut,
    summary="Cliente: justificar a ausência (até 24 h)",
)
def justificar(
    pedido_id: str,
    corpo: JustificativaIn,
    request: Request,
    usuario: Usuario = Depends(usuario_do_proprio_pedido),
    contexto: Contexto = Depends(obter_contexto),
) -> AusenciaOut:
    pedido = carregar_pedido(contexto, pedido_id, usuario)
    if pedido.cliente_id != usuario.id:
        raise HTTPException(403, "Só o cliente do pedido justifica a ausência.")
    texto = corpo.texto.strip()
    if not texto:
        raise HTTPException(422, "Escreva a justificativa.")
    ids = _anexos_do_autor(request, pedido, usuario, corpo.anexos)
    with uma_por_vez(contexto, pedido_id):
        pedido, item = _pedido_e_registro(contexto, pedido_id, usuario)
        if item.texto is not None:
            if (item.texto, item.anexos) == (texto, ids):
                return saida(contexto, item)
            raise HTTPException(409, "A justificativa já foi enviada e não pode ser trocada.")
        agora = contexto.agora()
        if item.status != AGUARDANDO_JUSTIFICATIVA or pedido.estado is not Estado.AGENDADO:
            raise HTTPException(409, "Este caso não está esperando justificativa.")
        if agora > justificativa_ate(contexto, item):
            raise HTTPException(409, "O prazo para justificar terminou.")
        novo = replace(item, status=EM_ANALISE, texto=texto, anexos=ids, justificativa_em=agora)
        if not contexto.ausencias.mudar(novo, (AGUARDANDO_JUSTIFICATIVA,)):
            raise HTTPException(409, "O caso mudou. Atualize e confira.")
    return saida(contexto, novo)


@router.get(
    "/{pedido_id}/ausencia/anexos",
    response_model=list[AnexoOut],
    summary="Provas do caso com link curto (o profissional vê só as que enviou)",
)
def ver_anexos(
    pedido_id: str,
    request: Request,
    usuario: Usuario = Depends(usuario_do_proprio_pedido),
    contexto: Contexto = Depends(obter_contexto),
) -> list[AnexoOut]:
    pedido, item = _pedido_e_registro(contexto, pedido_id, usuario)
    if usuario.id not in (pedido.cliente_id, pedido.profissional_id):
        raise HTTPException(404, "Pedido não encontrado.")
    servico = getattr(request.app.state, "servico_uploads", None)
    if servico is None:
        raise HTTPException(503, "O envio de arquivos não está disponível.")
    achados = anexos_do_caso(contexto, servico, pedido, item)
    if usuario.id == pedido.cliente_id:
        return achados  # o cliente vê a prova antes da cobrança
    return [a for a in achados if a.enviado_por == "profissional"]


@router.post(
    "/{pedido_id}/ausencia/contestacao",
    response_model=AusenciaOut,
    summary="Cliente: contestar a retenção (5 dias úteis)",
    description="Enquanto aberta, nada é cobrado; outro analista responde em 10 dias úteis.",
)
def contestar(
    pedido_id: str,
    corpo: JustificativaIn,
    request: Request,
    usuario: Usuario = Depends(usuario_do_proprio_pedido),
    contexto: Contexto = Depends(obter_contexto),
) -> AusenciaOut:
    pedido = carregar_pedido(contexto, pedido_id, usuario)
    if pedido.cliente_id != usuario.id:
        raise HTTPException(403, "Só o cliente do pedido contesta.")
    texto = corpo.texto.strip()
    if not texto:
        raise HTTPException(422, "Conte o que a análise não considerou.")
    ids = _anexos_do_autor(request, pedido, usuario, corpo.anexos)
    if not contexto.chamados.disponivel():
        raise HTTPException(503, "A contestação pelo app está indisponível. Fale com o suporte.")
    with uma_por_vez(contexto, pedido_id):
        pedido, item = _pedido_e_registro(contexto, pedido_id, usuario)
        caso = caso_de(contexto, pedido.id)
        anterior = revisao_de(contexto, caso)
        if anterior is not None:
            if (anterior.texto, anterior.anexos) == (texto, ids):
                return saida(contexto, item)
            raise HTTPException(409, "A decisão já foi contestada uma vez.")
        if (
            caso is None
            or caso.status != PROPOSTA
            or not caso.retencao_centavos
            or pedido.estado is not Estado.AGENDADO
        ):
            raise HTTPException(409, "Não há retenção para contestar.")
        agora = contexto.agora()
        if agora > contestar_ate(contexto, caso.retencao_mostrada_em):
            raise HTTPException(409, "O prazo para contestar terminou.")
        cfg = contexto.config.carregar()
        revisao = contexto.chamados.abrir_revisao(
            Revisao(
                pedido_id=pedido.id,
                cliente_id=usuario.id,
                texto=texto,
                anexos=ids,
                aberta_em=agora,
                responder_ate=adicionar_dias_uteis(
                    agora, cfg.ausencia_revisao_dias_uteis, cfg.disputas.feriados
                ),
            )
        )
        contexto.cancelamentos.contestar_retencao(pedido.id, agora)
        avisar_partes(
            contexto,
            Evento.AUSENCIA_DECIDIDA,
            (pedido.cliente_id, pedido.profissional_id),
            pedido_id=pedido.id,
            chave=f"{pedido.id}:contestacao:{revisao.id}",
            corpo="A retenção foi contestada. Nada é cobrado até outro analista responder.",
        )
    return saida(contexto, item)
