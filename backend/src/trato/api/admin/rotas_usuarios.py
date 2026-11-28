"""Busca e detalhe de usuários e pedidos. Dado pessoal só com motivo e auditoria."""

from __future__ import annotations

from datetime import date, datetime, timedelta
from functools import partial

from fastapi import APIRouter, Depends, HTTPException, Query
from pydantic import BaseModel, Field

from trato.api import medidas, pedidos_conta
from trato.api.admin.contexto import (
    AdminContexto,
    Operador,
    exigir,
    obter_admin,
    proteger_conta_da_equipe,
)
from trato.api.admin.modelos import (
    CategoriaProfissionalOut,
    ComMotivo,
    DadosPessoaisOut,
    DiagnosticoOut,
    EuOut,
    EventoPedidoOut,
    EventoUsuarioOut,
    ItemDiagnosticoOut,
    Pagina,
    PedidoDetalheOut,
    PedidoResumoOut,
    PessoaOut,
    UsuarioDetalheOut,
    UsuarioOut,
)
from trato.api.admin.mudanca_moedas import ACAO_AVISO
from trato.api.admin.papeis import Permissao, pode
from trato.api.admin.repositorios import FiltroAuditoria
from trato.api.admin.rotas_avisos_previos import antecedencia_dias
from trato.api.admin.rotas_medidas import campos_de_pedidos
from trato.api.contexto import Contexto, obter_contexto
from trato.financeiro import periodo
from trato.persistencia.comum import como_uuid

router = APIRouter(prefix="/v1/admin", tags=["admin: usuários e pedidos"])


@router.get("/eu", response_model=EuOut, summary="Quem sou eu (papel e alçada no painel)")
def eu(
    operador: Operador = Depends(exigir()),
    admin: AdminContexto = Depends(obter_admin),
) -> EuOut:
    conhecido = admin.usuarios.obter(operador.id)
    # Já vem limitada ao teto do papel (RP-02). Quem não tem alçada mostra "Sem alçada financeira".
    alcada = operador.membro.alcada_centavos or 0
    return EuOut(
        id=operador.id,
        papel=operador.membro.papel.value,
        nome=conhecido.nome if conhecido else None,
        alcada_centavos=alcada,
    )


def _usuario_out(u: object, extras: dict) -> UsuarioOut:
    saida = UsuarioOut.model_validate(u)
    c = extras.get(saida.id)
    if c is not None:
        saida.publico_id = c.publico_id
        saida.email_mascarado = c.email_mascarado
        saida.telefone_mascarado = c.telefone_mascarado
        saida.cidade = c.cidade
    return saida


# Só quem pode reativar a conta ou mexer em medidas e risco sabe da trava por fraude.
_VEEM_A_TRAVA = (Permissao.USUARIOS_STATUS, Permissao.MEDIDAS_APLICAR, Permissao.RISCO_VER)


def _marcar_trava(contexto: Contexto, operador: Operador, itens: list[UsuarioOut]) -> None:
    if not any(pode(operador.membro.papel, p) for p in _VEEM_A_TRAVA):
        return
    com_trava = contexto.medidas.usuarios_com_trava_fraude([u.id for u in itens], contexto.agora())
    for u in itens:
        u.trava_fraude_vigente = u.id.replace("-", "") in com_trava


@router.get("/usuarios", response_model=Pagina[UsuarioOut], summary="Buscar usuários")
def buscar_usuarios(
    q: str | None = Query(None, min_length=2, max_length=100, description="Nome ou id."),
    status: str | None = Query(None, pattern="^(ativo|restrito|bloqueado|inativo|anonimizado)$"),
    limite: int = Query(20, ge=1, le=100),
    deslocamento: int = Query(0, ge=0),
    operador: Operador = Depends(exigir(Permissao.USUARIOS_BUSCAR)),
    admin: AdminContexto = Depends(obter_admin),
    contexto: Contexto = Depends(obter_contexto),
) -> Pagina[UsuarioOut]:
    itens, total = admin.usuarios.buscar(q, status, limite, deslocamento)
    extras = admin.usuarios.complementos(itens)
    saidas = [_usuario_out(u, extras) for u in itens]
    _marcar_trava(contexto, operador, saidas)
    return Pagina(
        itens=saidas,
        total=total,
        limite=limite,
        deslocamento=deslocamento,
    )


@router.get(
    "/usuarios/{usuario_id}",
    response_model=UsuarioDetalheOut,
    summary="Detalhe (contato mascarado, categorias e histórico)",
)
def detalhe_usuario(
    usuario_id: str,
    operador: Operador = Depends(exigir(Permissao.USUARIOS_BUSCAR)),
    admin: AdminContexto = Depends(obter_admin),
    contexto: Contexto = Depends(obter_contexto),
) -> UsuarioDetalheOut:
    achado = admin.usuarios.obter(usuario_id)
    if achado is None:
        raise HTTPException(404, "Usuário não encontrado.")
    base = _usuario_out(achado, admin.usuarios.complementos([achado]))
    _marcar_trava(contexto, operador, [base])
    return UsuarioDetalheOut(
        **base.model_dump(),
        categorias=[
            CategoriaProfissionalOut(
                categoria_id=c.categoria_id,
                nome=c.nome,
                ativa_no_perfil=c.ativa_no_perfil,
                ativa_na_plataforma=c.ativa_na_plataforma,
            )
            for c in admin.usuarios.categorias(usuario_id)
        ],
        historico=[
            EventoUsuarioOut(em=e.em, texto=e.texto)
            for e in admin.usuarios.historico(usuario_id, 20)
        ],
    )


@router.get(
    "/usuarios/{usuario_id}/diagnostico-pedido",
    response_model=DiagnosticoOut,
    summary="Por que este pedido não aparece para este profissional? (RN-01)",
)
def diagnostico_pedido(
    usuario_id: str,
    pedido: str = Query(..., min_length=2, max_length=60, description="Código PED-10482 ou id."),
    _: Operador = Depends(exigir(Permissao.USUARIOS_BUSCAR)),
    admin: AdminContexto = Depends(obter_admin),
) -> DiagnosticoOut:
    if admin.usuarios.obter(usuario_id) is None:
        raise HTTPException(404, "Usuário não encontrado.")
    d = admin.usuarios.diagnosticar(usuario_id, pedido)
    if d is None:
        raise HTTPException(404, "Pedido não encontrado.")
    return DiagnosticoOut(
        pedido_id=d.pedido_id,
        pedido_numero=d.pedido_numero,
        pedido_titulo=d.pedido_titulo,
        categoria=d.categoria,
        aparece=d.aparece,
        itens=[ItemDiagnosticoOut(ok=i.ok, titulo=i.titulo, detalhe=i.detalhe) for i in d.itens],
    )


class AlterarStatusUsuarioIn(BaseModel):
    status: str = Field(pattern="^(ativo|restrito|bloqueado)$")
    motivo: str = Field(min_length=10, max_length=500)
    motivo_usuario: str | None = Field(None, max_length=2000, description="O usuário lê (20.4).")
    clausulas: list[str] = Field(default_factory=list, max_length=20)


@router.post(
    "/usuarios/{usuario_id}/status",
    response_model=UsuarioOut,
    summary="Alterar status do usuário (ativo, restrito, bloqueado)",
)
def alterar_status_usuario(
    usuario_id: str,
    corpo: AlterarStatusUsuarioIn,
    operador: Operador = Depends(exigir(Permissao.USUARIOS_STATUS)),
    admin: AdminContexto = Depends(obter_admin),
    contexto: Contexto = Depends(obter_contexto),
) -> UsuarioOut:
    banco = contexto.extras.get("banco") if contexto.extras else None
    if banco is None:
        raise HTTPException(503, "Banco de dados não configurado.")
    uid = como_uuid(usuario_id)
    if uid is None:
        raise HTTPException(404, "Usuário não encontrado.")
    proteger_conta_da_equipe(admin, operador, str(uid))
    inicio = contexto.agora()
    with contexto.transacao(), banco.transacao() as con:
        usuario = con.execute(
            "SELECT id, nome, status FROM public.usuarios WHERE id = %s for update", (uid,)
        ).fetchone()
        if usuario is None:
            raise HTTPException(404, "Usuário não encontrado.")
        con.execute(
            "UPDATE public.usuarios SET status = %s, atualizado_em = now() WHERE id = %s",
            (corpo.status, uid),
        )
        admin.auditoria.registrar(
            ator_id=operador.id,
            acao="usuario.status_alterado",
            entidade="usuarios",
            entidade_id=str(uid),
            depois={"status": corpo.status, "nome": usuario["nome"]},
            motivo=corpo.motivo,
        )
        termina = {
            "ativo": ("suspensao", "encerramento", "bloqueio_preventivo", "restricao",
                      "trava_saque"),
            "restrito": ("suspensao", "encerramento", "bloqueio_preventivo"),
            "bloqueado": (),
        }[corpo.status]  # fmt: skip
        if corpo.status != usuario["status"]:
            medidas.espelhar_status(
                contexto,
                str(uid),
                operador.id,
                para=corpo.status,
                tipo="suspensao" if corpo.status == "bloqueado" else "restricao",
                termina=termina,
                motivo=corpo.motivo,
                motivo_usuario=corpo.motivo_usuario,
                clausulas=tuple(corpo.clausulas),
            )
            # 20.6: com a tabela de medidas, quem trata os pedidos é a medida criada acima.
            if corpo.status == "bloqueado" and not contexto.medidas.disponivel():
                contexto.depois_do_commit(partial(pedidos_conta.tratar_pedidos, contexto, str(uid)))
    achado = admin.usuarios.obter(usuario_id)
    saida = UsuarioOut.model_validate(achado)
    if corpo.status == "bloqueado" and usuario["status"] != "bloqueado":
        saida = saida.model_copy(update=campos_de_pedidos(contexto, str(uid), inicio))
    _marcar_trava(contexto, operador, [saida])
    return saida


@router.post(
    "/usuarios/{usuario_id}/dados-pessoais",
    response_model=DadosPessoaisOut,
    summary="Revelar dados pessoais (motivo obrigatório, vai para a auditoria)",
    description="É POST porque a leitura deixa rastro: `dado_pessoal.revelado` na auditoria.",
)
def revelar_dados_pessoais(
    usuario_id: str,
    corpo: ComMotivo,
    operador: Operador = Depends(exigir(Permissao.DADOS_PESSOAIS_REVELAR)),
    admin: AdminContexto = Depends(obter_admin),
) -> DadosPessoaisOut:
    dados = admin.usuarios.dados_pessoais(usuario_id, operador.id, corpo.motivo)
    if dados is None:
        raise HTTPException(404, "Usuário não encontrado.")
    return DadosPessoaisOut.model_validate(dados)


@router.get("/pedidos", response_model=Pagina[PedidoResumoOut], summary="Buscar pedidos")
def buscar_pedidos(
    q: str | None = Query(None, min_length=2, max_length=100, description="Título ou id."),
    estado: str | None = None,
    cliente_id: str | None = None,
    profissional_id: str | None = None,
    limite: int = Query(20, ge=1, le=100),
    deslocamento: int = Query(0, ge=0),
    _: Operador = Depends(exigir(Permissao.PEDIDOS_BUSCAR)),
    admin: AdminContexto = Depends(obter_admin),
) -> Pagina[PedidoResumoOut]:
    itens, total = admin.pedidos.buscar(
        q, estado, cliente_id, profissional_id, limite, deslocamento
    )
    return Pagina(
        itens=[PedidoResumoOut.model_validate(p) for p in itens],
        total=total,
        limite=limite,
        deslocamento=deslocamento,
    )


@router.get("/pedidos/{pedido_id}", response_model=PedidoDetalheOut, summary="Detalhe do pedido")
def detalhe_pedido(
    pedido_id: str,
    _: Operador = Depends(exigir(Permissao.PEDIDOS_BUSCAR)),
    admin: AdminContexto = Depends(obter_admin),
    contexto: Contexto = Depends(obter_contexto),
) -> PedidoDetalheOut:
    """Nunca devolve os códigos de início/conclusão nem o endereço."""
    pedido = contexto.pedidos.obter(pedido_id)
    if pedido is None:
        raise HTTPException(404, "Pedido não encontrado.")
    contrato = contexto.contratos.obter_do_pedido(pedido.id)
    ids = [i for i in (pedido.cliente_id, pedido.profissional_id) if i]
    nomes = admin.usuarios.nomes(ids)
    return PedidoDetalheOut(
        id=pedido.id,
        estado=pedido.estado.value,
        cliente=PessoaOut(id=pedido.cliente_id, nome=nomes.get(pedido.cliente_id)),
        profissional=PessoaOut(
            id=pedido.profissional_id, nome=nomes.get(pedido.profissional_id or "")
        ),
        aberto_em=pedido.aberto_em,
        concluido_em=pedido.concluido_em,
        valor_contrato_centavos=contrato.valor_centavos if contrato else None,
        pagamento_confirmado=pedido.referencia_pagamento is not None,
        tem_disputa=contexto.disputas.obter(pedido.id) is not None,
        eventos=[
            EventoPedidoOut(
                acao=e.acao.value,
                de=e.de.value,
                para=e.para.value,
                ator_papel=e.ator.papel.value,
                ator_id=e.ator.id,
                em=e.em,
            )
            for e in contexto.pedidos.eventos(pedido.id)
        ],
    )


# --- Conta inativa (Termos 4.9): inativar após aviso prévio >= 30 dias e reativar ---------------


def _aviso_inatividade_cumprido(admin: AdminContexto, contexto: Contexto, usuario_id: str) -> bool:
    dias = antecedencia_dias(contexto, "inatividade")
    agora = contexto.agora()
    hoje = agora.astimezone(periodo.BRASILIA).date()
    entradas, _ = admin.auditoria.listar(
        FiltroAuditoria(acao=ACAO_AVISO, entidade="aviso_previo", entidade_id=usuario_id),
        50,
        0,
    )
    for entrada in entradas:
        depois = entrada.depois if isinstance(entrada.depois, dict) else {}
        if depois.get("tipo") != "inatividade":
            continue
        if depois.get("usuario_id") not in (None, usuario_id):
            continue
        if int(depois.get("falhas") or 0) > 0:
            continue
        emitido_raw = depois.get("emitido_em")
        emitido = (
            datetime.fromisoformat(emitido_raw)
            if isinstance(emitido_raw, str)
            else entrada.ocorrida_em
        )
        vigencia_raw = depois.get("vigencia")
        vigencia = date.fromisoformat(vigencia_raw) if isinstance(vigencia_raw, str) else None
        if agora >= emitido + timedelta(days=dias) and (vigencia is None or hoje >= vigencia):
            return True
    return False


def _atualizar_status_inatividade(
    admin: AdminContexto,
    contexto: Contexto,
    operador: Operador,
    usuario_id: str,
    *,
    de_permitidos: tuple[str, ...],
    para: str,
    acao: str,
    motivo: str,
    erro_estado: str,
) -> UsuarioOut:
    proteger_conta_da_equipe(admin, operador, usuario_id)
    banco = contexto.extras.get("banco") if contexto.extras else None
    if banco is not None:
        uid = como_uuid(usuario_id)
        if uid is None:
            raise HTTPException(404, "Usuário não encontrado.")
        with contexto.transacao(), banco.transacao() as con:
            usuario = con.execute(
                "SELECT id, nome, status FROM public.usuarios WHERE id = %s for update", (uid,)
            ).fetchone()
            if usuario is None:
                raise HTTPException(404, "Usuário não encontrado.")
            if usuario["status"] not in de_permitidos:
                raise HTTPException(409, erro_estado)
            con.execute(
                "UPDATE public.usuarios SET status = %s, atualizado_em = now() WHERE id = %s",
                (para, uid),
            )
            admin.auditoria.registrar(
                ator_id=operador.id,
                acao=acao,
                entidade="usuarios",
                entidade_id=str(uid),
                antes={"status": usuario["status"]},
                depois={"status": para, "nome": usuario["nome"]},
                motivo=motivo,
            )
    else:
        atual = admin.usuarios.obter(usuario_id)
        if atual is None:
            raise HTTPException(404, "Usuário não encontrado.")
        if atual.status not in de_permitidos:
            raise HTTPException(409, erro_estado)
        definir = getattr(admin.usuarios, "definir_status", None)
        if definir is not None:
            definir(usuario_id, para)
        definir_auth = getattr(contexto.auth, "definir_inativo", None)
        if definir_auth is not None:
            definir_auth(usuario_id, para == "inativo")
        admin.auditoria.registrar(
            ator_id=operador.id,
            acao=acao,
            entidade="usuarios",
            entidade_id=usuario_id,
            antes={"status": atual.status},
            depois={"status": para, "nome": atual.nome},
            motivo=motivo,
        )
    achado = admin.usuarios.obter(usuario_id)
    saida = UsuarioOut.model_validate(achado)
    _marcar_trava(contexto, operador, [saida])
    return saida


@router.post(
    "/usuarios/{usuario_id}/inativar",
    response_model=UsuarioOut,
    summary="Inativar conta após aviso prévio de 30 dias (Termos 4.9)",
    responses={409: {"description": "Sem aviso prévio cumprido (>= 30 dias) ou status inválido."}},
)
def inativar_usuario(
    usuario_id: str,
    corpo: ComMotivo,
    operador: Operador = Depends(exigir(Permissao.USUARIOS_STATUS)),
    admin: AdminContexto = Depends(obter_admin),
    contexto: Contexto = Depends(obter_contexto),
) -> UsuarioOut:
    if not _aviso_inatividade_cumprido(admin, contexto, usuario_id):
        raise HTTPException(
            409,
            "É obrigatório enviar aviso prévio de inatividade com pelo menos 30 dias de "
            "antecedência antes de inativar a conta (Termos 4.9).",
        )
    return _atualizar_status_inatividade(
        admin,
        contexto,
        operador,
        usuario_id,
        de_permitidos=("ativo", "restrito"),
        para="inativo",
        acao="usuario.inativar",
        motivo=corpo.motivo,
        erro_estado="Só contas ativas ou restritas podem ser inativadas.",
    )


@router.post(
    "/usuarios/{usuario_id}/reativar",
    response_model=UsuarioOut,
    summary="Reativar conta inativa gratuitamente (Termos 4.9)",
    responses={409: {"description": "A conta não está inativa."}},
)
def reativar_usuario(
    usuario_id: str,
    corpo: ComMotivo,
    operador: Operador = Depends(exigir(Permissao.USUARIOS_STATUS)),
    admin: AdminContexto = Depends(obter_admin),
    contexto: Contexto = Depends(obter_contexto),
) -> UsuarioOut:
    return _atualizar_status_inatividade(
        admin,
        contexto,
        operador,
        usuario_id,
        de_permitidos=("inativo",),
        para="ativo",
        acao="usuario.reativar",
        motivo=corpo.motivo,
        erro_estado="Só contas inativas podem ser reativadas por esta rota.",
    )
