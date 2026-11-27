"""Regras da contestação da decisão de disputa (Termos 8.7).

Cada parte contesta uma vez, em dias úteis a contar da decisão. Outro analista decide; quando a
nova decisão muda o valor do reembolso, uma segunda pessoa aprova e o efeito fica
`pendente_financeiro`. Nada aqui move dinheiro, muda a disputa ou o pedido.
"""

from __future__ import annotations

from collections.abc import Callable
from dataclasses import dataclass, replace
from datetime import datetime, time
from typing import Any

from fastapi.responses import JSONResponse

from trato.api.avisos import avisar_partes
from trato.api.contexto import Contexto
from trato.disputas import (
    Decisao,
    Disputa,
    Estado,
    Resultado,
    ResultadoInvalido,
    dividir_valor,
)
from trato.financeiro import periodo
from trato.notificacoes.eventos import Evento
from trato.pedidos.estados import Acao, Pedido
from trato.persistencia import contestacoes_decisao as dados
from trato.persistencia.contestacoes_decisao import ContestacaoDecisao
from trato.rotinas.dias_uteis import somar_dias_uteis

_ERROS = {
    "indisponivel": (
        503,
        "A contestação da decisão ainda não está disponível. Fale com o atendimento.",
    ),
    "sem_decisao": (409, "Só dá para contestar uma disputa já decidida."),
    "prazo_encerrado": (409, "O prazo para contestar esta decisão terminou."),
    "ja_contestada": (409, "Esta parte já contestou a decisão."),
    "nao_e_parte": (422, "Quem contesta precisa ser o cliente ou o profissional do pedido."),
    "chamado_invalido": (422, "Informe um chamado desta parte, aberto depois da decisão."),
    "nao_encontrada": (404, "Contestação não encontrada."),
    "pedido_nao_encontrado": (404, "Pedido não encontrado."),
    "mudou": (409, "Esta contestação já mudou. Atualize e confira."),
    "analista_impedido": (403, "Quem decidiu, aprovou ou é parte da disputa não pode analisar."),
    "segunda_pessoa": (403, "A aprovação precisa ser de outra pessoa."),
    "alcada": (403, "O valor da disputa está acima da alçada de quem aprova."),
    "decisao_invalida": (422, "Confira a nova decisão e o valor do reembolso."),
    "sem_mudanca": (422, "A nova decisão é igual à que vale hoje: use 'mantida'."),
    "resultado_incoerente": (
        422,
        "Use 'revertida' só quando tudo muda de lado (liberar tudo e reembolso total); "
        "nos outros casos, 'alterada'.",
    ),
}


class Recusa(Exception):
    def __init__(self, codigo: str) -> None:
        super().__init__(codigo)
        self.codigo = codigo

    def resposta(self) -> JSONResponse:
        status, mensagem = _ERROS[self.codigo]
        return JSONResponse(status_code=status, content={"detail": mensagem, "codigo": self.codigo})


@dataclass(frozen=True)
class Decidida:
    """A disputa decidida que pode ser contestada."""

    pedido: Pedido
    disputa: Disputa
    disputa_id: str
    decidida_em: datetime
    contestar_ate: datetime


def exigir_tabelas(contexto: Contexto) -> None:
    if not contexto.contestacoes_decisao.disponivel():
        raise Recusa("indisponivel")


def _fim_do_prazo(contexto: Contexto, inicio: datetime, dias: int) -> datetime:
    feriados = contexto.config.carregar().disputas.feriados
    dia = somar_dias_uteis(inicio.astimezone(periodo.BRASILIA).date(), dias, feriados)
    return datetime.combine(dia, time.max, periodo.BRASILIA)


def decisao_da_disputa(contexto: Contexto, pedido: Pedido) -> Decidida | None:
    disputa = contexto.disputas.obter(pedido.id)
    if disputa is None or disputa.estado is not Estado.DECIDIDA or disputa.decisao is None:
        return None
    disputa_id = contexto.contestacoes_decisao.disputa_id(pedido.id, disputa.aberta_em)
    # O prazo conta de quando a decisão valeu (e as partes foram avisadas). Acima da alçada isso
    # é a aprovação, que está no histórico do pedido.
    efetivadas = [
        e.em
        for e in contexto.pedidos.eventos(pedido.id)
        if e.acao is Acao.DECIDIR_DISPUTA and e.em >= disputa.aberta_em
    ]
    marcos = efetivadas or [m for m in (disputa.decidido_em, disputa.aprovado_em) if m]
    if disputa_id is None or not marcos:
        return None
    em = max(marcos)
    prazo = contexto.config.carregar().disputa_contestacao_prazo_dias_uteis
    return Decidida(pedido, disputa, disputa_id, em, _fim_do_prazo(contexto, em, max(5, prazo)))


def reembolso(disputa: Disputa, resultado: str, parcial: int | None) -> int:
    if resultado == Resultado.REEMBOLSO_TOTAL.value:
        return disputa.valor_congelado
    if resultado == Resultado.REEMBOLSO_PARCIAL.value:
        return parcial or 0
    return 0


def decisao_vigente(disputa: Disputa, itens: list[ContestacaoDecisao]) -> tuple[str, int]:
    """(resultado, reembolso) que vale hoje: a última contestação que mudou, ou a original."""
    mudaram = [c for c in itens if c.status in ("alterada", "revertida") and c.nova_decisao]
    if mudaram:
        ultima = max(mudaram, key=lambda c: c.decidida_em or c.aberta_em)
        assert ultima.nova_decisao is not None  # noqa: S101 - filtrado acima
        return ultima.nova_decisao, reembolso(
            disputa, ultima.nova_decisao, ultima.novo_valor_reembolso_centavos
        )
    assert disputa.decisao is not None  # noqa: S101 - só disputas decididas chegam aqui
    divisao = dividir_valor(disputa.valor_congelado, disputa.decisao)
    return disputa.decisao.resultado.value, divisao.para_cliente


def _tipo_de_mudanca(disputa: Disputa, atual: tuple[str, int], nova: str, valor: int) -> str:
    """A tabela não guarda a intenção enquanto espera aprovação: o tipo sai das decisões."""
    if (nova, valor) == atual or (nova == atual[0] and nova != "reembolso_parcial"):
        raise Recusa("sem_mudanca")
    extremos = {Resultado.LIBERAR_TUDO.value, Resultado.REEMBOLSO_TOTAL.value}
    return "revertida" if {atual[0], nova} == extremos else "alterada"


# --- abrir ----------------------------------------------------------------------------------------


def abrir(
    contexto: Contexto,
    decidida: Decidida,
    contestante_id: str,
    o_que_faltou: str,
    anexos: tuple[str, ...],
    canal: str,
    aberta_em: datetime,
    auditar: Callable[[ContestacaoDecisao], None] | None = None,
) -> tuple[ContestacaoDecisao, bool]:
    """(contestação, criada). Repetir o mesmo conteúdo devolve a que já existe."""
    pedido = decidida.pedido
    if contestante_id not in (pedido.cliente_id, pedido.profissional_id):
        raise Recusa("nao_e_parte")
    repo = contexto.contestacoes_decisao
    resposta_dias = contexto.config.carregar().disputa_contestacao_resposta_dias_uteis
    with contexto.transacao(), repo.exclusivo(decidida.disputa_id):
        anterior = next(
            (c for c in repo.da_disputa(decidida.disputa_id) if c.contestante_id == contestante_id),
            None,
        )
        if anterior is not None:
            if (anterior.o_que_faltou, anterior.anexos, anterior.canal) == (
                o_que_faltou,
                anexos,
                canal,
            ):
                return anterior, False
            raise Recusa("ja_contestada")
        if aberta_em > decidida.contestar_ate:
            raise Recusa("prazo_encerrado")
        item, criada = repo.inserir(
            ContestacaoDecisao(
                disputa_id=decidida.disputa_id,
                pedido_id=pedido.id,
                contestante_id=contestante_id,
                o_que_faltou=o_que_faltou,
                anexos=anexos,
                canal=canal,
                aberta_em=aberta_em,
                contestar_ate=decidida.contestar_ate,
                responder_ate=_fim_do_prazo(contexto, aberta_em, min(10, resposta_dias)),
            )
        )
        if auditar is not None:
            auditar(item)
        avisar_partes(
            contexto,
            Evento.DISPUTA_CONTESTADA,
            (pedido.cliente_id, pedido.profissional_id),
            pedido_id=pedido.id,
            chave=f"{item.id}:aberta",
        )
    return item, criada


# --- decidir e aprovar ----------------------------------------------------------------------------

_AVISOS = {
    "mantida": "A contestação foi analisada e a decisão foi mantida. Veja o motivo no pedido.",
    "alterada": "A contestação foi analisada e a decisão foi alterada. Veja o motivo no pedido.",
    "revertida": "A contestação foi analisada e a decisão foi revertida. Veja o motivo no pedido.",
}


def _avisar_decisao(contexto: Contexto, pedido: Pedido, item: ContestacaoDecisao) -> None:
    avisar_partes(
        contexto,
        Evento.DISPUTA_CONTESTACAO_DECIDIDA,
        (pedido.cliente_id, pedido.profissional_id),
        pedido_id=pedido.id,
        chave=f"{item.id}:decidida",
        corpo=_AVISOS[item.status],
    )


def _carregar(contexto: Contexto, contestacao_id: str) -> tuple[ContestacaoDecisao, Pedido, Any]:
    item = contexto.contestacoes_decisao.obter(contestacao_id)
    pedido = contexto.pedidos.obter(item.pedido_id) if item else None
    disputa = contexto.disputas.obter(item.pedido_id) if item else None
    if item is None or pedido is None or disputa is None or disputa.decisao is None:
        raise Recusa("nao_encontrada")
    return item, pedido, disputa


def _impedido(pedido: Pedido, disputa: Disputa, operador_id: str) -> bool:
    return operador_id in (
        disputa.decidido_por,
        disputa.aprovado_por,
        pedido.cliente_id,
        pedido.profissional_id,
    )


def _gravar(contexto: Contexto, novo: ContestacaoDecisao, status_esperado: str) -> None:
    if not contexto.contestacoes_decisao.atualizar(novo, status_esperado):
        raise Recusa("mudou")


def decidir(
    contexto: Contexto,
    contestacao_id: str,
    operador_id: str,
    resultado: str,
    resposta: str,
    nova_decisao: str | None,
    valor: int | None,
    auditar: Callable[[ContestacaoDecisao, ContestacaoDecisao], None],
) -> ContestacaoDecisao:
    repo = contexto.contestacoes_decisao
    disputa_id = _carregar(contexto, contestacao_id)[0].disputa_id
    with contexto.transacao(), repo.exclusivo(disputa_id):
        item, pedido, disputa = _carregar(contexto, contestacao_id)
        if _impedido(pedido, disputa, operador_id):
            raise Recusa("analista_impedido")
        if item.status not in (dados.ABERTA, dados.EM_ANALISE):
            repetida = (
                item.analista_id == operador_id
                and item.resposta == resposta
                and item.nova_decisao == nova_decisao
                and item.novo_valor_reembolso_centavos == valor
                and (item.status == dados.AGUARDANDO_APROVACAO) == (resultado != item.status)
            )
            if repetida:
                return item
            raise Recusa("mudou")
        dinheiro = False
        if resultado == "mantida":
            if nova_decisao is not None or valor is not None:
                raise Recusa("decisao_invalida")
        else:
            if nova_decisao is None or (nova_decisao == "reembolso_parcial") != (valor is not None):
                raise Recusa("decisao_invalida")
            try:
                dividir_valor(
                    disputa.valor_congelado,
                    Decisao(Resultado(nova_decisao), valor_cliente_centavos=valor),
                )
            except (ResultadoInvalido, ValueError) as erro:
                raise Recusa("decisao_invalida") from erro
            atual = decisao_vigente(disputa, repo.da_disputa(disputa_id))
            novo_reembolso = reembolso(disputa, nova_decisao, valor)
            if _tipo_de_mudanca(disputa, atual, nova_decisao, novo_reembolso) != resultado:
                raise Recusa("resultado_incoerente")
            dinheiro = novo_reembolso != atual[1]
        novo = replace(
            item,
            status=dados.AGUARDANDO_APROVACAO if dinheiro else resultado,
            analista_id=operador_id,
            resposta=resposta,
            nova_decisao=nova_decisao,
            novo_valor_reembolso_centavos=valor,
            decidida_em=None if dinheiro else contexto.agora(),
        )
        _gravar(contexto, novo, item.status)
        auditar(item, novo)
        if not dinheiro:
            _avisar_decisao(contexto, pedido, novo)
    return novo


def aprovar(
    contexto: Contexto,
    contestacao_id: str,
    operador_id: str,
    aprovada: bool,
    alcada_centavos: int | None,
    auditar: Callable[[ContestacaoDecisao, ContestacaoDecisao], None],
) -> ContestacaoDecisao:
    """`alcada_centavos` nulo: sem limite (administrador). `aprovada` falso devolve à análise."""
    repo = contexto.contestacoes_decisao
    disputa_id = _carregar(contexto, contestacao_id)[0].disputa_id
    with contexto.transacao(), repo.exclusivo(disputa_id):
        item, pedido, disputa = _carregar(contexto, contestacao_id)
        if _impedido(pedido, disputa, operador_id):
            raise Recusa("analista_impedido")
        if operador_id == item.analista_id:
            raise Recusa("segunda_pessoa")
        if item.status != dados.AGUARDANDO_APROVACAO:
            if aprovada and item.aprovada_por == operador_id:
                return item  # reenvio
            raise Recusa("mudou")
        if not aprovada:
            novo = replace(
                item,
                status=dados.EM_ANALISE,
                resposta=None,
                nova_decisao=None,
                novo_valor_reembolso_centavos=None,
            )
            _gravar(contexto, novo, item.status)
            auditar(item, novo)
            return novo
        if alcada_centavos is not None and alcada_centavos < disputa.valor_congelado:
            raise Recusa("alcada")
        assert item.nova_decisao is not None  # noqa: S101 - quem espera aprovação tem decisão
        atual = decisao_vigente(disputa, repo.da_disputa(disputa_id))
        valor = reembolso(disputa, item.nova_decisao, item.novo_valor_reembolso_centavos)
        tipo = _tipo_de_mudanca(disputa, atual, item.nova_decisao, valor)
        novo = replace(
            item,
            status=tipo,
            aprovada_por=operador_id,
            decidida_em=contexto.agora(),
            efeito_financeiro="pendente_financeiro" if valor != atual[1] else "nenhum",
        )
        _gravar(contexto, novo, item.status)
        auditar(item, novo)
        _avisar_decisao(contexto, pedido, novo)
    return novo
