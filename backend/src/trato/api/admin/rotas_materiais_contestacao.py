"""Contestações de nota de material no painel (Termos 6.9).

Permissões:
- `materiais_contestacao_analisar` (`mediador`, `lider_suporte`, `seguranca`, `administrador`):
  listar, passar para `em_analise` e decidir (`procedente` | `parcial` | `improcedente`).
- `materiais_contestacao_aprovar` (`lider_suporte`, `administrador`):
  aprovar o efeito financeiro em 4 olhos (`aprovada_por != analista_id`), avançando
  `efeito_financeiro` para `pendente_financeiro` (idempotente, sem mover dinheiro duas vezes).
Todas as escritas e a abertura de anexos são auditadas; sem tabela, responde 503 limpo.
"""

from __future__ import annotations

import logging
from datetime import datetime
from typing import Any, Literal

from fastapi import APIRouter, Depends, HTTPException, Query, Request
from pydantic import BaseModel, ConfigDict, Field

from trato.api.admin.contexto import AdminContexto, Operador, exigir, obter_admin
from trato.api.admin.modelos import Pagina
from trato.api.admin.papeis import Permissao
from trato.api.ausencia_base import URL_SEGUNDOS, midia_do_pedido
from trato.api.contexto import Contexto, obter_contexto
from trato.persistencia.materiais_contestacao import ContestacaoNotaMaterial

router = APIRouter(
    prefix="/v1/admin/materiais/contestacoes",
    tags=["admin: contestações de nota de material"],
)
log = logging.getLogger(__name__)

StatusContestacao = Literal["aberta", "em_analise", "procedente", "parcial", "improcedente"]
StatusDecisao = Literal["procedente", "parcial", "improcedente"]


class DecidirContestacaoMaterialIn(BaseModel):
    model_config = ConfigDict(extra="forbid", str_strip_whitespace=True)

    status: StatusDecisao
    resposta: str = Field(min_length=10, max_length=4000)
    valor_reconhecido_centavos: int | None = Field(default=None, ge=0, strict=True)


class AprovarFinanceiroIn(BaseModel):
    model_config = ConfigDict(extra="forbid", str_strip_whitespace=True)

    motivo: str = Field(min_length=10, max_length=2000)


class ContestacaoMaterialAdminOut(BaseModel):
    id: str
    protocolo: str
    pedido_id: str
    nota_id: str
    item_id: str | None = None
    cliente_id: str
    motivo: str
    descricao: str
    anexos: list[str]
    valor_contestado_centavos: int
    aberta_em: datetime
    responder_ate: datetime
    status: StatusContestacao
    analista_id: str | None = None
    resposta: str | None = None
    valor_reconhecido_centavos: int | None = None
    decidida_em: datetime | None = None
    aprovada_por: str | None = None
    efeito_financeiro: str


def _out(c: ContestacaoNotaMaterial) -> ContestacaoMaterialAdminOut:
    return ContestacaoMaterialAdminOut(
        id=c.id,
        protocolo=c.protocolo,
        pedido_id=c.pedido_id,
        nota_id=c.nota_id,
        item_id=c.item_id,
        cliente_id=c.cliente_id,
        motivo=c.motivo,
        descricao=c.descricao,
        anexos=list(c.anexos),
        valor_contestado_centavos=c.valor_contestado_centavos,
        aberta_em=c.aberta_em,
        responder_ate=c.responder_ate,
        status=c.status,  # type: ignore[arg-type]
        analista_id=c.analista_id,
        resposta=c.resposta,
        valor_reconhecido_centavos=c.valor_reconhecido_centavos,
        decidida_em=c.decidida_em,
        aprovada_por=c.aprovada_por,
        efeito_financeiro=c.efeito_financeiro,
    )


def _exigir_tabela(contexto: Contexto) -> None:
    if not contexto.materiais_contestacao.disponivel():
        raise HTTPException(
            503,
            "Contestação de nota de material indisponível: tabela ainda não existe no banco.",
        )


@router.get(
    "",
    response_model=Pagina[ContestacaoMaterialAdminOut],
    summary="Listar contestações de nota de material",
)
def listar_contestacoes_admin(
    status: StatusContestacao | None = Query(None),
    pedido_id: str | None = Query(None),
    limite: int = Query(50, ge=1, le=200),
    deslocamento: int = Query(0, ge=0),
    _: Operador = Depends(exigir(Permissao.MATERIAIS_CONTESTACAO_ANALISAR)),
    contexto: Contexto = Depends(obter_contexto),
) -> Pagina[ContestacaoMaterialAdminOut]:
    _exigir_tabela(contexto)
    itens, total = contexto.materiais_contestacao.listar_admin(
        status, pedido_id, limite, deslocamento
    )
    return Pagina(
        itens=[_out(c) for c in itens],
        total=total,
        limite=limite,
        deslocamento=deslocamento,
    )


@router.post(
    "/{contestacao_id}/analisar",
    response_model=ContestacaoMaterialAdminOut,
    summary="Passar contestação de nota de material para em_analise",
)
def analisar_contestacao(
    contestacao_id: str,
    operador: Operador = Depends(exigir(Permissao.MATERIAIS_CONTESTACAO_ANALISAR)),
    contexto: Contexto = Depends(obter_contexto),
    admin: AdminContexto = Depends(obter_admin),
) -> ContestacaoMaterialAdminOut:
    _exigir_tabela(contexto)
    cont, cod = contexto.materiais_contestacao.iniciar_analise(contestacao_id, operador.id)
    if cod == "nao_encontrada" or cont is None:
        raise HTTPException(404, "Contestação de nota de material não encontrada.")
    if cod == "ja_decidida":
        raise HTTPException(409, "Esta contestação já foi decidida.")
    if cod == "ok":
        admin.auditoria.registrar(
            ator_id=operador.id,
            acao="material.contestacao_em_analise",
            entidade="nota_material_contestacoes",
            entidade_id=cont.id,
            depois={"status": "em_analise", "protocolo": cont.protocolo},
            motivo=f"Análise iniciada para contestação {cont.protocolo}",
        )
    return _out(cont)


@router.post(
    "/{contestacao_id}/decidir",
    response_model=ContestacaoMaterialAdminOut,
    summary="Decidir contestação de nota de material (procedente, parcial ou improcedente)",
)
def decidir_contestacao(
    contestacao_id: str,
    corpo: DecidirContestacaoMaterialIn,
    operador: Operador = Depends(exigir(Permissao.MATERIAIS_CONTESTACAO_ANALISAR)),
    contexto: Contexto = Depends(obter_contexto),
    admin: AdminContexto = Depends(obter_admin),
) -> ContestacaoMaterialAdminOut:
    _exigir_tabela(contexto)
    atual = contexto.materiais_contestacao.obter(contestacao_id)
    if atual is None:
        raise HTTPException(404, "Contestação de nota de material não encontrada.")
    valor = corpo.valor_reconhecido_centavos
    if corpo.status == "procedente" and valor is None:
        valor = atual.valor_contestado_centavos
    if corpo.status == "improcedente" and valor is None:
        valor = 0

    cont, cod = contexto.materiais_contestacao.decidir(
        contestacao_id, corpo.status, operador.id, corpo.resposta, valor, contexto.agora()
    )
    if cod == "nao_encontrada" or cont is None:
        raise HTTPException(404, "Contestação de nota de material não encontrada.")
    if cod == "ja_decidida":
        raise HTTPException(409, "Esta contestação já foi decidida.")
    if cod == "valor_invalido":
        raise HTTPException(
            422,
            "Valor reconhecido inválido: procedente = todo o valor contestado; "
            "parcial = mais que zero e menos que o contestado; improcedente = zero.",
        )
    if cod == "ok":
        admin.auditoria.registrar(
            ator_id=operador.id,
            acao="material.contestacao_decidida",
            entidade="nota_material_contestacoes",
            entidade_id=cont.id,
            depois={
                "status": cont.status,
                "protocolo": cont.protocolo,
                "valor_reconhecido_centavos": cont.valor_reconhecido_centavos,
            },
            motivo=corpo.resposta,
        )
    return _out(cont)


@router.post(
    "/{contestacao_id}/aprovar-financeiro",
    response_model=ContestacaoMaterialAdminOut,
    summary="Aprovar efeito financeiro em 4 olhos (líder de suporte ou administrador)",
)
def aprovar_financeiro(
    contestacao_id: str,
    corpo: AprovarFinanceiroIn,
    operador: Operador = Depends(exigir(Permissao.MATERIAIS_CONTESTACAO_APROVAR)),
    contexto: Contexto = Depends(obter_contexto),
    admin: AdminContexto = Depends(obter_admin),
) -> ContestacaoMaterialAdminOut:
    _exigir_tabela(contexto)
    cont, cod = contexto.materiais_contestacao.aprovar_financeiro(contestacao_id, operador.id)
    if cod == "nao_encontrada" or cont is None:
        raise HTTPException(404, "Contestação de nota de material não encontrada.")
    if cod == "nao_elegivel":
        raise HTTPException(
            409, "Aprovação financeira só se aplica a contestação procedente ou parcial."
        )
    if cod == "mesma_pessoa":
        raise HTTPException(
            403, "Aprovação financeira exige segunda pessoa diferente do analista (4 olhos)."
        )
    if cod == "ok":
        admin.auditoria.registrar(
            ator_id=operador.id,
            acao="material.contestacao_financeiro_aprovado",
            entidade="nota_material_contestacoes",
            entidade_id=cont.id,
            depois={
                "protocolo": cont.protocolo,
                "efeito_financeiro": cont.efeito_financeiro,
                "valor_reconhecido_centavos": cont.valor_reconhecido_centavos,
            },
            motivo=corpo.motivo,
        )
    return _out(cont)


class AbrirAnexosMaterialIn(BaseModel):
    model_config = ConfigDict(extra="forbid", str_strip_whitespace=True)

    motivo: str = Field(min_length=10, max_length=2000)
    arquivo_id: str | None = Field(
        default=None,
        min_length=1,
        max_length=64,
        description="Para renovar o link de um só. Precisa ser desta contestação.",
    )


class AnexoMaterialOut(BaseModel):
    tipo: Literal["nota_material", "contestacao"]
    arquivo_id: str | None = None
    enviado_por: Literal["cliente", "profissional"]
    url: str | None = Field(default=None, description="Nulo: o arquivo não pode ser aberto.")
    content_type: str | None = None
    expira_em_segundos: int | None = None


def _mesmo_id(a: object, b: object) -> bool:
    return str(a).replace("-", "") == str(b).replace("-", "")


def _midia_da_nota(servico: Any, nota: Any) -> Any:
    """A foto da nota, só se passou pela conferência de envio do servidor (tem `sha256`).

    Caminho solto mandado pelo app não é assinado: poderia apontar para arquivo de outra pessoa.
    """
    return next(
        (
            m
            for m in servico.repo.midias_do_pedido(nota.pedido_id, ("nota_material",))
            if m.storage_path == nota.foto_storage_path
            and _mesmo_id(m.enviada_por, nota.profissional_id)
            and m.sha256
        ),
        None,
    )


@router.post(
    "/{contestacao_id}/anexos",
    response_model=list[AnexoMaterialOut],
    summary="Abrir a nota de material e as provas da contestação (acesso auditado)",
    description="É POST para o motivo ir no corpo (não fica em log de URL).",
)
def abrir_anexos_da_contestacao(
    contestacao_id: str,
    corpo: AbrirAnexosMaterialIn,
    request: Request,
    operador: Operador = Depends(exigir(Permissao.MATERIAIS_CONTESTACAO_ANALISAR)),
    contexto: Contexto = Depends(obter_contexto),
    admin: AdminContexto = Depends(obter_admin),
) -> list[AnexoMaterialOut]:
    _exigir_tabela(contexto)
    cont = contexto.materiais_contestacao.obter(contestacao_id)
    if cont is None:
        raise HTTPException(404, "Contestação de nota de material não encontrada.")
    servico = getattr(request.app.state, "servico_uploads", None)
    if servico is None:
        raise HTTPException(503, "O envio de arquivos não está disponível.")

    # (tipo, arquivo_id, quem enviou, mídia conferida ou None)
    achados: list[tuple[str, str | None, str, Any]] = []
    nota = next(
        (n for n in contexto.notas_material.do_pedido(cont.pedido_id) if n.id == cont.nota_id),
        None,
    )
    if nota is not None:
        midia = _midia_da_nota(servico, nota)
        achados.append(("nota_material", midia.id if midia else None, "profissional", midia))
    for arquivo in cont.anexos:
        midia = midia_do_pedido(servico, arquivo, cont.pedido_id)
        if midia is not None and not _mesmo_id(midia.enviada_por, cont.cliente_id):
            midia = None
        achados.append(("contestacao", arquivo, "cliente", midia))

    if corpo.arquivo_id is not None:
        achados = [a for a in achados if a[1] is not None and _mesmo_id(a[1], corpo.arquivo_id)]
        if not achados:
            raise HTTPException(404, "Este arquivo não é desta contestação.")

    saida: list[AnexoMaterialOut] = []
    falhas = 0
    for tipo, arquivo, quem, midia in achados:
        url = None
        if midia is not None:
            try:
                url = servico.armazenamento.url_leitura(
                    midia.bucket, midia.storage_path, URL_SEGUNDOS
                )
            except Exception:  # noqa: BLE001 - falha do armazenamento não vira 500
                log.warning("falha ao assinar anexo da contestação %s", cont.protocolo)
                falhas += 1
        saida.append(
            AnexoMaterialOut(
                tipo=tipo,  # type: ignore[arg-type]
                arquivo_id=arquivo,
                enviado_por=quem,  # type: ignore[arg-type]
                url=url,
                content_type=midia.mime if midia else None,
                expira_em_segundos=URL_SEGUNDOS if url else None,
            )
        )
    if falhas and not any(a.url for a in saida):
        raise HTTPException(503, "Não foi possível abrir os arquivos agora. Tente de novo.")
    with contexto.transacao():  # os links só saem depois de a auditoria gravar quais foram
        admin.auditoria.registrar(
            ator_id=operador.id,
            acao="dado_pessoal.material_contestacao_anexos_vistos",
            entidade="nota_material_contestacoes",
            entidade_id=cont.id,
            antes={},
            depois={
                "protocolo": cont.protocolo,
                "arquivos": [a.arquivo_id for a in saida if a.url],
            },
            motivo=corpo.motivo,
        )
    return saida
