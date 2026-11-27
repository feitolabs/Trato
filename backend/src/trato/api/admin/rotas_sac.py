"""Atendimento no painel (Termos 25). Ver: `suporte_ver`; registrar e responder: `sac_responder`.

A contestação da retenção por cliente ausente também é um chamado, mas só se encerra pela
decisão de outro analista (`/v1/admin/ausencias/{pedido_id}/contestacao/decisao`).
"""

from __future__ import annotations

from datetime import datetime
from typing import Literal

from fastapi import APIRouter, Depends, HTTPException, Query
from pydantic import AwareDatetime, BaseModel, ConfigDict, Field

from trato.api.admin.contexto import AdminContexto, Operador, exigir, obter_admin
from trato.api.admin.modelos import Pagina
from trato.api.admin.papeis import Permissao
from trato.api.avisos import avisar_partes
from trato.api.contexto import Contexto, obter_contexto
from trato.api.rotas_sac import (
    Categoria,
    confirmar_ao_usuario,
    eh_contestacao_de_retencao,
    exigir_tabelas,
    prazo_de_resposta,
)
from trato.financeiro import periodo
from trato.notificacoes.eventos import Evento
from trato.persistencia.chamados import ASSUNTO as ASSUNTO_CONTESTACAO
from trato.persistencia.sac import ENCERRADO, Chamado, Filtro, MensagemChamado

router = APIRouter(prefix="/v1/admin/chamados", tags=["admin: atendimento"])


class ContatoIn(BaseModel):
    model_config = ConfigDict(extra="forbid")

    canal: Literal["telefone", "email", "whatsapp", "painel"]
    categoria: Categoria
    assunto: str = Field(min_length=3, max_length=200)
    texto: str = Field(min_length=1, max_length=4000)
    usuario_id: str | None = Field(None, max_length=64)
    nome_contato: str | None = Field(None, max_length=200)
    contato: str | None = Field(None, max_length=320)
    pedido_id: str | None = Field(None, max_length=64)
    prioridade: Literal["baixa", "normal", "alta", "urgente"] = "normal"


class AssumirChamadoIn(BaseModel):
    model_config = ConfigDict(extra="forbid")

    substituir: bool = False


class RespostaIn(BaseModel):
    model_config = ConfigDict(extra="forbid")

    texto: str = Field(min_length=1, max_length=4000)
    interna: bool = False
    aguardar_usuario: bool = False


class PrazoIn(BaseModel):
    model_config = ConfigDict(extra="forbid")

    novo_prazo_ate: AwareDatetime
    motivo: str = Field(min_length=10, max_length=1000, description="O usuário lê este texto.")


class EncerrarIn(BaseModel):
    model_config = ConfigDict(extra="forbid")

    mensagem: str = Field(min_length=10, max_length=4000, description="Resposta final ao usuário.")


class ChamadoAdminOut(BaseModel):
    id: str
    protocolo: str
    assunto: str
    solicitante: str = Field(description="Nome ou contato; id da conta se não houver nome.")
    status: str
    aberto_em: datetime
    categoria: str
    canal: str
    prioridade: str
    usuario_id: str | None = None
    nome_contato: str | None = None
    contato: str | None = None
    pedido_id: str | None = None
    responsavel_id: str | None = None
    responsavel_nome: str | None = None
    contestacao_retencao: bool = False
    responder_ate: datetime
    novo_prazo_ate: datetime | None = None
    motivo_extensao: str | None = None
    primeira_resposta_em: datetime | None = None
    encerrado_em: datetime | None = None
    atrasado: bool = False


class MensagemAdminOut(BaseModel):
    id: str
    autor: str
    autor_id: str | None = None
    texto: str
    interna: bool
    criada_em: datetime


class ChamadoAdminDetalheOut(ChamadoAdminOut):
    mensagens: list[MensagemAdminOut]


def _nomes(admin: AdminContexto, chamados: list[Chamado]) -> dict[str, str]:
    ids = list({i for c in chamados for i in (c.usuario_id, c.responsavel_id) if i})
    if admin.usuarios is None or not ids:
        return {}
    achados = admin.usuarios.nomes(ids)
    return {str(k).replace("-", ""): v for k, v in achados.items()}  # com ou sem hífen


def _out(contexto: Contexto, c: Chamado, nomes: dict[str, str]) -> ChamadoAdminOut:
    campos = {
        n: getattr(c, n)
        for n in ChamadoAdminOut.model_fields
        if n
        not in (
            "solicitante",
            "aberto_em",
            "atrasado",
            "responsavel_nome",
            "contestacao_retencao",
        )
    }
    return ChamadoAdminOut(
        **campos,
        responsavel_nome=nomes.get((c.responsavel_id or "").replace("-", "")),
        contestacao_retencao=eh_contestacao_de_retencao(c),
        solicitante=nomes.get((c.usuario_id or "").replace("-", ""))
        or c.nome_contato
        or c.contato
        or c.usuario_id
        or "",
        aberto_em=c.criado_em,
        atrasado=c.status not in (ENCERRADO, "respondido") and c.prazo < contexto.agora(),
    )


def _obter(contexto: Contexto, chamado_id: str) -> Chamado:
    exigir_tabelas(contexto)
    chamado = contexto.sac.obter(chamado_id)
    if chamado is None:
        raise HTTPException(404, "Chamado não encontrado.")
    return chamado


def _detalhe(contexto: Contexto, admin: AdminContexto, chamado_id: str) -> ChamadoAdminDetalheOut:
    c = _obter(contexto, chamado_id)
    return ChamadoAdminDetalheOut(
        **_out(contexto, c, _nomes(admin, [c])).model_dump(),
        mensagens=[
            MensagemAdminOut(
                id=m.id or "",
                autor=m.autor_tipo,
                autor_id=m.autor_id,
                texto=m.texto,
                interna=m.interna,
                criada_em=m.criada_em,
            )
            for m in contexto.sac.mensagens(chamado_id, com_internas=True)
        ],
    )


def _auditar(
    admin: AdminContexto, operador: Operador, acao: str, chamado_id: str, motivo: str, **depois
) -> None:
    admin.auditoria.registrar(
        ator_id=operador.id,
        acao=f"suporte.chamado_{acao}",
        entidade="chamados",
        entidade_id=chamado_id,
        antes={},
        depois=depois,
        motivo=motivo,
    )


def _avisar(contexto: Contexto, c: Chamado, evento: Evento, chave: str, corpo: str) -> None:
    avisar_partes(
        contexto,
        evento,
        (c.usuario_id,),
        pedido_id=c.pedido_id,
        chave=f"sac:{c.id}:{chave}",
        corpo=f"Protocolo {c.protocolo}: {corpo}",
        dados={"chamado_id": c.id},
    )


@router.get("", response_model=Pagina[ChamadoAdminOut], summary="Fila de chamados")
def fila(
    status: str | None = Query(
        None, pattern="^(aberto|em_atendimento|aguardando_usuario|respondido|encerrado)$"
    ),
    categoria: Categoria | None = None,
    prioridade: str | None = Query(None, pattern="^(baixa|normal|alta|urgente)$"),
    responsavel_id: str | None = None,
    pedido_id: str | None = None,
    protocolo: str | None = Query(None, max_length=40),
    atrasados: bool = False,
    limite: int = Query(20, ge=1, le=100),
    deslocamento: int = Query(0, ge=0),
    _: Operador = Depends(exigir(Permissao.SUPORTE_VER)),
    admin: AdminContexto = Depends(obter_admin),
    contexto: Contexto = Depends(obter_contexto),
) -> Pagina[ChamadoAdminOut]:
    exigir_tabelas(contexto)
    filtro = Filtro(
        status=status,
        categoria=categoria,
        prioridade=prioridade,
        responsavel_id=responsavel_id,
        pedido_id=pedido_id,
        protocolo=protocolo,
        atrasados_em=contexto.agora() if atrasados else None,
    )
    itens, total = contexto.sac.listar(filtro, limite, deslocamento)
    nomes = _nomes(admin, itens)
    return Pagina(
        itens=[_out(contexto, c, nomes) for c in itens],
        total=total,
        limite=limite,
        deslocamento=deslocamento,
    )


@router.get("/{chamado_id}", response_model=ChamadoAdminDetalheOut, summary="Chamado completo")
def ver(
    chamado_id: str,
    _: Operador = Depends(exigir(Permissao.SUPORTE_VER)),
    admin: AdminContexto = Depends(obter_admin),
    contexto: Contexto = Depends(obter_contexto),
) -> ChamadoAdminDetalheOut:
    return _detalhe(contexto, admin, chamado_id)


@router.post(
    "",
    response_model=ChamadoAdminDetalheOut,
    status_code=201,
    summary="Registrar contato recebido por telefone, e-mail ou WhatsApp",
)
def registrar_contato(
    corpo: ContatoIn,
    operador: Operador = Depends(exigir(Permissao.SAC_RESPONDER)),
    admin: AdminContexto = Depends(obter_admin),
    contexto: Contexto = Depends(obter_contexto),
) -> ChamadoAdminDetalheOut:
    exigir_tabelas(contexto)
    contato = (corpo.contato or "").strip() or None
    if not corpo.usuario_id and not contato:
        raise HTTPException(422, "Informe a conta do usuário ou um contato.")
    if corpo.assunto.strip().casefold() == ASSUNTO_CONTESTACAO.casefold():
        raise HTTPException(422, "Este assunto é reservado à contestação feita no pedido.")
    if corpo.usuario_id and contexto.usuarios.detalhe(corpo.usuario_id) is None:
        raise HTTPException(404, "Usuário não encontrado.")
    if corpo.pedido_id and contexto.pedidos.obter(corpo.pedido_id) is None:
        raise HTTPException(404, "Pedido não encontrado.")
    agora = contexto.agora()
    with contexto.transacao():
        chamado, novo = contexto.sac.abrir(
            Chamado(
                categoria=corpo.categoria,
                assunto=corpo.assunto.strip(),
                canal=corpo.canal,
                criado_em=agora,
                responder_ate=prazo_de_resposta(contexto, corpo.categoria, agora),
                usuario_id=corpo.usuario_id,
                nome_contato=corpo.nome_contato,
                contato=contato,
                pedido_id=corpo.pedido_id,
                prioridade=corpo.prioridade,
            ),
            MensagemChamado("equipe", corpo.texto.strip(), agora, autor_id=operador.id),
        )
        if novo:
            _auditar(admin, operador, "registrado", chamado.id or "", "Contato registrado.")
            confirmar_ao_usuario(contexto, chamado)
    return _detalhe(contexto, admin, chamado.id or "")


@router.post(
    "/{chamado_id}/assumir", response_model=ChamadoAdminDetalheOut, summary="Assumir o chamado"
)
def assumir(
    chamado_id: str,
    corpo: AssumirChamadoIn | None = None,
    operador: Operador = Depends(exigir(Permissao.SAC_RESPONDER)),
    admin: AdminContexto = Depends(obter_admin),
    contexto: Contexto = Depends(obter_contexto),
) -> ChamadoAdminDetalheOut:
    chamado = _obter(contexto, chamado_id)
    substituir = bool(corpo and corpo.substituir)
    with contexto.transacao():
        if not contexto.sac.mudar(
            chamado_id,
            {"responsavel_id": operador.id, "status": "em_atendimento"},
            so_responsavel=None if substituir else (None, operador.id),
        ):
            raise HTTPException(
                409, "O chamado está encerrado ou outra pessoa já assumiu (use substituir)."
            )
        if chamado.responsavel_id != operador.id:
            _auditar(
                admin, operador, "assumido", chamado_id, "Atendimento assumido.",
                responsavel_anterior=chamado.responsavel_id,
            )  # fmt: skip
    return _detalhe(contexto, admin, chamado_id)


@router.post(
    "/{chamado_id}/mensagens",
    response_model=ChamadoAdminDetalheOut,
    summary="Responder (ao usuário ou nota interna)",
)
def responder(
    chamado_id: str,
    corpo: RespostaIn,
    operador: Operador = Depends(exigir(Permissao.SAC_RESPONDER)),
    admin: AdminContexto = Depends(obter_admin),
    contexto: Contexto = Depends(obter_contexto),
) -> ChamadoAdminDetalheOut:
    chamado = _obter(contexto, chamado_id)
    texto = corpo.texto.strip()
    if not texto:
        raise HTTPException(422, "Escreva a mensagem.")
    anteriores = contexto.sac.mensagens(chamado_id, com_internas=True)
    ultima = anteriores[-1] if anteriores else None
    repetida = ultima is not None and (ultima.autor_id, ultima.texto, ultima.interna) == (
        operador.id,
        texto,
        corpo.interna,
    )
    if not repetida:
        agora = contexto.agora()
        campos = {}
        if not corpo.interna:
            campos = {
                "status": "aguardando_usuario" if corpo.aguardar_usuario else "respondido",
                "primeira_resposta_em": chamado.primeira_resposta_em or agora,
            }
        mensagem = MensagemChamado(
            "equipe", texto, agora, autor_id=operador.id, interna=corpo.interna
        )
        if not contexto.sac.mudar(chamado_id, campos, mensagem):
            raise HTTPException(409, "Este chamado está encerrado.")
        if not corpo.interna:
            _avisar(
                contexto,
                chamado,
                Evento.SAC_RESPOSTA,
                f"resposta:{len(anteriores)}",
                "há uma resposta do atendimento. Veja no aplicativo.",
            )
    elif chamado.status == ENCERRADO:
        raise HTTPException(409, "Este chamado está encerrado.")
    return _detalhe(contexto, admin, chamado_id)


@router.post(
    "/{chamado_id}/prazo",
    response_model=ChamadoAdminDetalheOut,
    summary="Informar novo prazo e o motivo (25.4)",
)
def novo_prazo(
    chamado_id: str,
    corpo: PrazoIn,
    operador: Operador = Depends(exigir(Permissao.SAC_RESPONDER)),
    admin: AdminContexto = Depends(obter_admin),
    contexto: Contexto = Depends(obter_contexto),
) -> ChamadoAdminDetalheOut:
    chamado = _obter(contexto, chamado_id)
    motivo = corpo.motivo.strip()
    if len(motivo) < 10:
        raise HTTPException(422, "Explique o motivo ao usuário.")
    ate = corpo.novo_prazo_ate
    if chamado.novo_prazo_ate == ate and chamado.motivo_extensao == motivo:
        return _detalhe(contexto, admin, chamado_id)
    agora = contexto.agora()
    if ate <= max(chamado.prazo, agora):
        raise HTTPException(422, "O novo prazo precisa ser depois do atual.")
    texto = f"Novo prazo de resposta: {ate.astimezone(periodo.BRASILIA):%d/%m/%Y}. {motivo}"
    with contexto.transacao():
        if not contexto.sac.mudar(
            chamado_id,
            {"novo_prazo_ate": ate, "motivo_extensao": motivo},
            MensagemChamado("sistema", texto, agora),
        ):
            raise HTTPException(409, "Este chamado está encerrado.")
        _auditar(admin, operador, "prazo", chamado_id, motivo, novo_prazo_ate=ate.isoformat())
        _avisar(contexto, chamado, Evento.SAC_PRAZO, f"prazo:{int(ate.timestamp())}", texto)
    return _detalhe(contexto, admin, chamado_id)


@router.post(
    "/{chamado_id}/encerrar", response_model=ChamadoAdminDetalheOut, summary="Encerrar o chamado"
)
def encerrar(
    chamado_id: str,
    corpo: EncerrarIn,
    operador: Operador = Depends(exigir(Permissao.SAC_RESPONDER)),
    admin: AdminContexto = Depends(obter_admin),
    contexto: Contexto = Depends(obter_contexto),
) -> ChamadoAdminDetalheOut:
    chamado = _obter(contexto, chamado_id)
    if chamado.categoria == "contestacao" and chamado.assunto == ASSUNTO_CONTESTACAO:
        raise HTTPException(
            409, "Esta contestação se encerra pela decisão de outro analista, no caso de ausência."
        )
    mensagem = corpo.mensagem.strip()
    if len(mensagem) < 10:
        raise HTTPException(422, "Escreva a resposta final ao usuário.")
    agora = contexto.agora()
    with contexto.transacao():
        if not contexto.sac.mudar(
            chamado_id,
            {
                "status": ENCERRADO,
                "encerrado_em": agora,
                "primeira_resposta_em": chamado.primeira_resposta_em or agora,
            },
            MensagemChamado("equipe", mensagem, agora, autor_id=operador.id),
        ):
            raise HTTPException(409, "Este chamado já está encerrado.")
        _auditar(admin, operador, "encerrado", chamado_id, mensagem[:500])
        _avisar(contexto, chamado, Evento.SAC_RESPOSTA, "encerrado", "o atendimento foi encerrado.")
    return _detalhe(contexto, admin, chamado_id)
