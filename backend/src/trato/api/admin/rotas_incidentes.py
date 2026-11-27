"""Incidentes de segurança no painel (Termos 9.3 a 9.6).

Ver: `incidentes_ver`; abrir, medir e mudar o andamento: `incidentes_tratar`; encerrar:
`incidentes_encerrar` (encerrar pode soltar o valor retido do pedido). A única medida que mexe
em pedido e dinheiro é `cancelar_pedido_reembolso` num incidente de pessoa diferente (9.5);
nenhuma suspende conta. Tudo é auditado, sem contato nem relato na trilha.
"""

from __future__ import annotations

from datetime import datetime, timedelta
from typing import Literal

from fastapi import APIRouter, Depends, HTTPException, Query, Response
from pydantic import BaseModel, ConfigDict, Field

from trato.api import pessoa_diferente
from trato.api.admin.contexto import AdminContexto, Operador, exigir, obter_admin
from trato.api.admin.modelos import Pagina
from trato.api.admin.papeis import Permissao
from trato.api.contexto import Contexto, obter_contexto
from trato.pedidos.estados import Estado
from trato.persistencia.incidentes import Incidente

router = APIRouter(prefix="/v1/admin/incidentes", tags=["admin: incidentes de segurança"])

Tipo = Literal[
    "furto_roubo",
    "agressao_ameaca_assedio",
    "acidente_dano",
    "pessoa_diferente",
    "comportamento_suspeito",
    "pagamento_por_fora",
    "outro",
]
Canal = Literal["app", "telefone", "whatsapp", "email", "painel"]
# `suspender_conta` fica fora: exige uma medida de conta (20.2 e 20.4).
TipoMedida = Literal[
    "bloquear_contato", "preservar_registros", "reter_valor", "cancelar_pedido_reembolso", "outro"
]
Status = Literal["aberto", "cautela_adotada", "em_apuracao", "encerrado"]


class AbrirIncidenteIn(BaseModel):
    model_config = ConfigDict(extra="forbid", str_strip_whitespace=True)

    tipo: Tipo
    descricao: str = Field(min_length=1, max_length=4000)
    contato: str = Field(min_length=1, max_length=320)
    canal: Canal
    pedido_id: str | None = Field(None, max_length=64)


class MedidaIn(BaseModel):
    model_config = ConfigDict(extra="forbid", str_strip_whitespace=True)

    tipo: TipoMedida
    descricao: str = Field(min_length=1, max_length=1000)


class StatusIn(BaseModel):
    model_config = ConfigDict(extra="forbid")

    status: Literal["cautela_adotada", "em_apuracao"]


class EncerrarIncidenteIn(BaseModel):
    model_config = ConfigDict(extra="forbid", str_strip_whitespace=True)

    desfecho: str = Field(min_length=10, max_length=4000)


class MedidaOut(BaseModel):
    id: str
    tipo: str
    descricao: str
    origem: str = Field(description="analista | automatica")
    aplicada_em: datetime


class IncidenteOut(BaseModel):
    id: str
    protocolo: str
    canal: str
    tipo: str
    descricao: str
    contato: str | None = None
    pedido_id: str | None = None
    status: Status
    aberto_em: datetime
    cautela_ate: datetime
    cautela_adotada_em: datetime | None = None
    cautela_atrasada: bool = Field(
        False, description="Passou o prazo de 24 h (9.6) sem a cautela adotada."
    )
    responsavel_id: str | None = None
    desfecho: str | None = None
    encerrado_em: datetime | None = None
    medidas: list[MedidaOut]


_CONFLITOS = {
    "encerrado": "Este incidente já está encerrado.",
    "sem_medida": "Registre uma medida antes de marcar a cautela como adotada.",
}


def _out(i: Incidente, agora: datetime) -> IncidenteOut:
    calculados = ("medidas", "cautela_atrasada")
    campos = {n: getattr(i, n) for n in IncidenteOut.model_fields if n not in calculados}
    medidas = [MedidaOut(**{n: getattr(m, n) for n in MedidaOut.model_fields}) for m in i.medidas]
    atrasada = i.status != "encerrado" and i.cautela_adotada_em is None and agora > i.cautela_ate
    return IncidenteOut(**campos, medidas=medidas, cautela_atrasada=atrasada)


def _executar_9_5(contexto: Contexto, incidente_id: str) -> None:
    """Medida `cancelar_pedido_reembolso` de pessoa diferente: cancela de fato, uma vez só."""
    incidente = _obter(contexto, incidente_id)
    if incidente.tipo != pessoa_diferente.TIPO or incidente.pedido_id is None:
        return  # outros casos seguem só registrados
    if incidente.status == "encerrado":
        return  # o registro abaixo responde o conflito
    travar = getattr(contexto.pedidos, "travar", None)
    if travar is not None:
        travar(incidente.pedido_id)
    pedido = contexto.pedidos.obter(incidente.pedido_id)
    if pedido is None or pedido.estado is Estado.CANCELADO:
        return
    if pedido.estado not in pessoa_diferente.CANCELAVEIS:
        raise HTTPException(
            409,
            "O serviço já começou ou o pedido não está contratado: o cancelamento automático "
            "não vale. Decida pela disputa; o valor segue retido.",
        )
    pessoa_diferente.cancelar_com_reembolso_integral(contexto, pedido)


def _exigir_tabelas(contexto: Contexto) -> None:
    if not contexto.incidentes.disponivel():
        raise HTTPException(
            503, "Incidentes indisponíveis: as tabelas ainda não existem no banco de dados."
        )


def _obter(contexto: Contexto, incidente_id: str) -> Incidente:
    achado = contexto.incidentes.obter(incidente_id)
    if achado is None:
        raise HTTPException(404, "Incidente não encontrado.")
    return achado


def _auditar(
    admin: AdminContexto,
    operador: Operador,
    acao: str,
    incidente_id: str | None,
    motivo: str,
    **depois,
) -> None:
    admin.auditoria.registrar(
        ator_id=operador.id,
        acao=f"seguranca.incidente_{acao}",
        entidade="incidentes_seguranca",
        entidade_id=incidente_id,
        antes={},
        depois=depois,
        motivo=motivo,
    )


def _conferir(resultado: str) -> None:
    if resultado == "nao_encontrado":
        raise HTTPException(404, "Incidente não encontrado.")
    if resultado in _CONFLITOS:
        raise HTTPException(409, _CONFLITOS[resultado])


@router.get("", response_model=Pagina[IncidenteOut], summary="Fila de incidentes")
def fila(
    status: Status | None = None,
    pedido_id: str | None = Query(None, max_length=64),
    limite: int = Query(20, ge=1, le=100),
    deslocamento: int = Query(0, ge=0),
    operador: Operador = Depends(exigir(Permissao.INCIDENTES_VER)),
    admin: AdminContexto = Depends(obter_admin),
    contexto: Contexto = Depends(obter_contexto),
) -> Pagina[IncidenteOut]:
    _exigir_tabelas(contexto)
    itens, total = contexto.incidentes.listar(status, pedido_id or None, limite, deslocamento)
    _auditar(
        admin, operador, "lista_consultada", None, "Consulta da fila de incidentes.",
        quantidade=len(itens),
    )  # fmt: skip
    return Pagina(
        itens=[_out(i, contexto.agora()) for i in itens],
        total=total,
        limite=limite,
        deslocamento=deslocamento,
    )


@router.get("/{incidente_id}", response_model=IncidenteOut, summary="Incidente completo")
def ver(
    incidente_id: str,
    operador: Operador = Depends(exigir(Permissao.INCIDENTES_VER)),
    admin: AdminContexto = Depends(obter_admin),
    contexto: Contexto = Depends(obter_contexto),
) -> IncidenteOut:
    _exigir_tabelas(contexto)
    achado = _obter(contexto, incidente_id)
    _auditar(admin, operador, "consultado", achado.id, "Consulta do incidente.")
    return _out(achado, contexto.agora())


@router.post(
    "",
    response_model=IncidenteOut,
    status_code=201,
    summary="Registrar incidente",
    description="`200` devolve o mesmo incidente num toque repetido (5 minutos).",
)
def abrir(
    corpo: AbrirIncidenteIn,
    response: Response,
    operador: Operador = Depends(exigir(Permissao.INCIDENTES_TRATAR)),
    admin: AdminContexto = Depends(obter_admin),
    contexto: Contexto = Depends(obter_contexto),
) -> IncidenteOut:
    _exigir_tabelas(contexto)
    pedido_id = corpo.pedido_id or None
    if corpo.tipo == "pessoa_diferente" and pedido_id is None:
        raise HTTPException(422, "Informe o pedido em que apareceu uma pessoa diferente.")
    if pedido_id is not None and contexto.pedidos.obter(pedido_id) is None:
        raise HTTPException(404, "Pedido não encontrado.")
    horas = contexto.config.carregar().incidente_seguranca_cautela_horas
    agora = contexto.agora()
    travar = getattr(contexto.pedidos, "travar", None)
    with contexto.transacao():
        if pedido_id is not None and travar is not None:
            travar(pedido_id)  # não cruza com uma liberação em andamento
        incidente, novo = contexto.incidentes.abrir(
            Incidente(
                tipo=corpo.tipo,
                descricao=corpo.descricao,
                canal=corpo.canal,
                contato=corpo.contato,
                pedido_id=pedido_id,
                aberto_em=agora,
                cautela_ate=agora + timedelta(hours=horas),
            )
        )
        if novo:
            _auditar(
                admin, operador, "aberto", incidente.id, "Incidente registrado.",
                tipo=incidente.tipo, canal=incidente.canal, pedido_id=incidente.pedido_id,
            )  # fmt: skip
    if not novo:
        response.status_code = 200
    return _out(incidente, contexto.agora())


@router.post(
    "/{incidente_id}/medidas", response_model=IncidenteOut, summary="Registrar medida adotada"
)
def medida(
    incidente_id: str,
    corpo: MedidaIn,
    operador: Operador = Depends(exigir(Permissao.INCIDENTES_TRATAR)),
    admin: AdminContexto = Depends(obter_admin),
    contexto: Contexto = Depends(obter_contexto),
) -> IncidenteOut:
    _exigir_tabelas(contexto)
    with contexto.transacao():
        if corpo.tipo == "cancelar_pedido_reembolso":
            _executar_9_5(contexto, incidente_id)
        if corpo.tipo == "preservar_registros":
            # fila com a exclusão de conta, que trava os pedidos antes de checar a preservação
            alvo = _obter(contexto, incidente_id).pedido_id
            travar = getattr(contexto.pedidos, "travar", None)
            if alvo and travar is not None:
                travar(alvo)
        resultado = contexto.incidentes.registrar_medida(
            incidente_id, corpo.tipo, corpo.descricao, operador.id, contexto.agora()
        )
        _conferir(resultado)
        if resultado == "ok":
            _auditar(admin, operador, "medida", incidente_id, "Medida registrada.", tipo=corpo.tipo)
    return _out(_obter(contexto, incidente_id), contexto.agora())


@router.post("/{incidente_id}/status", response_model=IncidenteOut, summary="Mudar o andamento")
def andamento(
    incidente_id: str,
    corpo: StatusIn,
    operador: Operador = Depends(exigir(Permissao.INCIDENTES_TRATAR)),
    admin: AdminContexto = Depends(obter_admin),
    contexto: Contexto = Depends(obter_contexto),
) -> IncidenteOut:
    _exigir_tabelas(contexto)
    with contexto.transacao():
        resultado = contexto.incidentes.mudar_status(
            incidente_id, corpo.status, operador.id, contexto.agora()
        )
        _conferir(resultado)
        if resultado == "ok":
            _auditar(
                admin, operador, "andamento", incidente_id, "Andamento alterado.",
                status=corpo.status,
            )  # fmt: skip
    return _out(_obter(contexto, incidente_id), contexto.agora())


@router.post(
    "/{incidente_id}/encerrar", response_model=IncidenteOut, summary="Encerrar com desfecho"
)
def encerrar(
    incidente_id: str,
    corpo: EncerrarIncidenteIn,
    operador: Operador = Depends(exigir(Permissao.INCIDENTES_ENCERRAR)),
    admin: AdminContexto = Depends(obter_admin),
    contexto: Contexto = Depends(obter_contexto),
) -> IncidenteOut:
    _exigir_tabelas(contexto)
    with contexto.transacao():
        resultado = contexto.incidentes.encerrar(
            incidente_id, corpo.desfecho, operador.id, contexto.agora()
        )
        _conferir(resultado)
        if resultado == "ok":
            _auditar(
                admin, operador, "encerrado", incidente_id, corpo.desfecho[:500],
                status="encerrado",
            )  # fmt: skip
    return _out(_obter(contexto, incidente_id), contexto.agora())
