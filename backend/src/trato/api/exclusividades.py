"""Exclusividade de 48h: o profissional gasta Tratinhos (da carteira dele) para ter prioridade num
pedido aberto; o cliente aceita ou recusa sem compromisso.

Dinheiro e concorrência ficam em funções SQL atômicas (`persistencia/exclusividades.py`); aqui
estão o contrato do repositório, a versão em memória com a MESMA semântica (testes e
desenvolvimento) e as regras de tradução do resultado em erro de API. Moeda de profissional nunca
vira desconto e nunca consome o orçamento de desconto da empresa.
"""

from __future__ import annotations

import threading
import uuid
from dataclasses import dataclass, replace
from datetime import datetime, timedelta
from typing import Any, Protocol

from trato.pedidos.estados import Estado

CARTEIRA = "profissional"
TIPO_USO = "exclusividade_uso"
TIPO_ESTORNO = "exclusividade_estorno"
EM_ANDAMENTO = ("aguardando_cliente", "ativa")
TEXTO_SEM_COMPROMISSO = "Sem compromisso"

# Resultado da função SQL -> (status HTTP, código estável, texto para o app).
ERROS_SOLICITAR: dict[str, tuple[int, str, str]] = {
    "saldo_insuficiente": (
        409,
        "saldo_insuficiente",
        "Você não tem Tratinhos suficientes para pedir prioridade neste pedido.",
    ),
    "limite_simultaneas": (
        409,
        "limite_simultaneas",
        "Você já atingiu o limite de prioridades ao mesmo tempo. Espere uma terminar.",
    ),
    "pedido_indisponivel": (
        409,
        "pedido_indisponivel",
        "Este pedido não está mais disponível para prioridade.",
    ),
    "bloqueado_recusa": (
        409,
        "bloqueado_recusa",
        "Este cliente recusou sua prioridade há pouco tempo. Tente de novo mais tarde.",
    ),
    "pedido_urgente": (
        422,
        "pedido_urgente",
        "Pedidos urgentes ficam fora da prioridade: todos os profissionais podem orçar.",
    ),
    "categoria_sem_exclusividade": (
        422,
        "categoria_sem_exclusividade",
        "Esta categoria de serviço não permite prioridade.",
    ),
    "proprio_pedido": (
        422,
        "proprio_pedido",
        "Você não pode pedir prioridade no seu próprio pedido.",
    ),
}


@dataclass(frozen=True)
class Exclusividade:
    id: str
    profissional_id: str
    cliente_id: str
    pedido_id: str
    status: str  # aguardando_cliente | ativa | recusada | expirada_sem_resposta | concluida | ...
    moedas_cobradas: int
    chave_idempotencia: str
    criada_em: datetime
    responder_ate: datetime | None = None
    respondida_em: datetime | None = None
    expira_em: datetime | None = None
    encerrada_em: datetime | None = None


@dataclass(frozen=True)
class ResultadoSolicitacao:
    resultado: str
    exclusividade_id: str | None = None
    responder_ate: datetime | None = None
    saldo_restante: int | None = None


@dataclass(frozen=True)
class ResultadoResposta:
    resultado: str  # ok | nao_encontrada | ja_respondida | prazo_vencido | pedido_indisponivel
    expira_em: datetime | None = None


@dataclass(frozen=True)
class Encerramento:
    exclusividade_id: str
    resultado: str  # concluida | cancelada
    profissional_id: str


@dataclass(frozen=True)
class Expirada:
    exclusividade_id: str
    motivo: str  # sem_resposta | sem_atendimento
    profissional_id: str
    cliente_id: str
    pedido_id: str


class RepositorioExclusividades(Protocol):
    def solicitar(
        self,
        profissional_id: str,
        pedido_id: str,
        chave: str,
        agora: datetime,
        custo: int,
        max_simultaneas: int,
        prazo_resposta_horas: int,
        bloqueio_recusa_dias: int,
    ) -> ResultadoSolicitacao: ...

    def responder(
        self,
        exclusividade_id: str,
        cliente_id: str,
        decisao: str,
        agora: datetime,
        duracao_horas: int,
    ) -> ResultadoResposta: ...

    def expirar(self, agora: datetime) -> list[Expirada]: ...

    def encerrar_por_pedido(
        self, pedido_id: str, profissional_aceito: str | None, agora: datetime
    ) -> list[Encerramento]: ...

    def obter(self, exclusividade_id: str) -> Exclusividade | None: ...

    def do_profissional(self, profissional_id: str) -> list[Exclusividade]: ...

    def em_andamento_do_pedido(self, pedido_id: str) -> Exclusividade | None: ...

    def profissional_ativo_do_pedido(self, pedido_id: str) -> str | None: ...


class ExclusividadesEmMemoria:
    """Mesma semântica das funções SQL (ordem das checagens, estorno por status, idempotência).

    Usa o livro de moedas e os pedidos do `Contexto` (ligados por `vincular`). Tudo sob uma trava:
    a checagem e o débito do saldo são um passo só, como a função do banco.
    """

    def __init__(self) -> None:
        self._itens: dict[str, Exclusividade] = {}
        self._por_chave: dict[str, str] = {}
        self._trava = threading.RLock()
        self._contexto: Any = None
        self.categorias_sem_exclusividade: set[str] = set()  # `categorias.permite_exclusividade`

    def vincular(self, contexto: Any) -> None:
        self._contexto = contexto

    # --- livro -------------------------------------------------------------------------------

    def _saldo(self, profissional_id: str, agora: datetime) -> int:
        return int(self._contexto.moedas.saldo(profissional_id, agora, CARTEIRA))

    def _lancar(self, item: Exclusividade, tipo: str, quantidade: int, chave: str, agora: datetime):
        from trato.api.moedas import LancamentoMoeda

        self._contexto.moedas.lancar(
            LancamentoMoeda(
                usuario_id=item.profissional_id,
                tipo=tipo,
                quantidade=quantidade,
                chave_idempotencia=chave,
                criada_em=agora,
                referencia_id=item.id,
                parceiro_id=item.cliente_id,
                carteira=CARTEIRA,
            )
        )

    def _estornar(self, item: Exclusividade, agora: datetime) -> None:
        self._lancar(
            item, TIPO_ESTORNO, item.moedas_cobradas, f"exclusividade-estorno:{item.id}", agora
        )

    def _mudar(self, item: Exclusividade, **campos: Any) -> Exclusividade:
        novo = replace(item, **campos)
        self._itens[item.id] = novo
        return novo

    def _pedido_para(self, pedido_id: str, estado: Estado) -> None:
        pedido = self._contexto.pedidos.obter(pedido_id)
        if pedido is not None:
            self._contexto.pedidos.salvar(replace(pedido, estado=estado))

    # --- funções --------------------------------------------------------------------------------

    def solicitar(
        self,
        profissional_id: str,
        pedido_id: str,
        chave: str,
        agora: datetime,
        custo: int,
        max_simultaneas: int,
        prazo_resposta_horas: int,
        bloqueio_recusa_dias: int,
    ) -> ResultadoSolicitacao:
        with self._trava:
            if chave in self._por_chave:
                existente = self._itens[self._por_chave[chave]]
                if existente.profissional_id != profissional_id:
                    raise ValueError("chave de idempotência de outro profissional")
                return ResultadoSolicitacao(
                    "ja_existe",
                    existente.id,
                    existente.responder_ate,
                    self._saldo(profissional_id, agora),
                )
            saldo = self._saldo(profissional_id, agora)

            def nega(resultado: str) -> ResultadoSolicitacao:  # nada muda; devolve o saldo atual
                return ResultadoSolicitacao(resultado, saldo_restante=saldo)

            # Mesma ordem da função SQL: proprio_pedido, pedido_indisponivel, urgente, categoria,
            # bloqueio, limite, saldo.
            pedido = self._contexto.pedidos.obter(pedido_id)
            if pedido is not None and profissional_id == pedido.cliente_id:
                return nega("proprio_pedido")
            if (
                pedido is None
                or pedido.estado is not Estado.ABERTO
                or any(
                    i.pedido_id == pedido_id and i.status in EM_ANDAMENTO
                    for i in self._itens.values()
                )
            ):
                return nega("pedido_indisponivel")
            dados = self._contexto.pedidos.dados_do_pedido(pedido_id)
            if dados is not None and dados.urgente:
                return nega("pedido_urgente")
            if dados is not None and dados.categoria_id in self.categorias_sem_exclusividade:
                return nega("categoria_sem_exclusividade")
            do_profissional = [
                i for i in self._itens.values() if i.profissional_id == profissional_id
            ]
            limite = agora - timedelta(days=bloqueio_recusa_dias)
            if any(
                i.cliente_id == pedido.cliente_id
                and i.status == "recusada"
                and i.encerrada_em is not None
                and i.encerrada_em > limite
                for i in do_profissional
            ):
                return nega("bloqueado_recusa")
            if sum(1 for i in do_profissional if i.status in EM_ANDAMENTO) >= max_simultaneas:
                return nega("limite_simultaneas")
            if saldo < custo:
                return nega("saldo_insuficiente")
            novo = Exclusividade(
                id=uuid.uuid4().hex,
                profissional_id=profissional_id,
                cliente_id=pedido.cliente_id,
                pedido_id=pedido_id,
                status="aguardando_cliente",
                moedas_cobradas=custo,
                chave_idempotencia=chave,
                criada_em=agora,
                responder_ate=agora + timedelta(hours=prazo_resposta_horas),
            )
            self._itens[novo.id] = novo
            self._por_chave[chave] = novo.id
            self._lancar(novo, TIPO_USO, -custo, f"exclusividade-uso:{novo.id}", agora)
            return ResultadoSolicitacao(
                "ok", novo.id, novo.responder_ate, self._saldo(profissional_id, agora)
            )

    def responder(
        self,
        exclusividade_id: str,
        cliente_id: str,
        decisao: str,
        agora: datetime,
        duracao_horas: int,
    ) -> ResultadoResposta:
        with self._trava:
            item = self._itens.get(exclusividade_id)
            if item is None or item.cliente_id != cliente_id:
                return ResultadoResposta("nao_encontrada")
            if decisao not in ("aceitar", "recusar"):
                raise ValueError("decisão inválida")
            if item.status == "expirada_sem_resposta":
                return ResultadoResposta("prazo_vencido")  # a rotina já expirou e estornou
            if item.status != "aguardando_cliente":
                return ResultadoResposta("ja_respondida")
            if item.responder_ate is not None and item.responder_ate < agora:
                self._mudar(item, status="expirada_sem_resposta", encerrada_em=agora)
                self._estornar(item, agora)
                return ResultadoResposta("prazo_vencido")
            if decisao == "recusar":
                self._mudar(item, status="recusada", respondida_em=agora, encerrada_em=agora)
                self._estornar(item, agora)
                return ResultadoResposta("ok")
            pedido = self._contexto.pedidos.obter(item.pedido_id)
            if pedido is None or pedido.estado is not Estado.ABERTO:
                self._mudar(item, status="cancelada", encerrada_em=agora)
                self._estornar(item, agora)
                return ResultadoResposta("pedido_indisponivel")
            expira = agora + timedelta(hours=duracao_horas)
            self._mudar(item, status="ativa", respondida_em=agora, expira_em=expira)
            self._pedido_para(item.pedido_id, Estado.RESERVADO)
            return ResultadoResposta("ok", expira)

    def expirar(self, agora: datetime) -> list[Expirada]:
        saida: list[Expirada] = []
        with self._trava:
            for item in list(self._itens.values()):
                if (
                    item.status == "aguardando_cliente"
                    and item.responder_ate
                    and item.responder_ate < agora
                ):
                    self._mudar(item, status="expirada_sem_resposta", encerrada_em=agora)
                    self._estornar(item, agora)
                    motivo = "sem_resposta"
                elif item.status == "ativa" and item.expira_em and item.expira_em < agora:
                    self._mudar(item, status="expirada_sem_atendimento", encerrada_em=agora)
                    self._pedido_para(item.pedido_id, Estado.ABERTO)  # reservado -> aberto
                    motivo = "sem_atendimento"
                else:
                    continue
                saida.append(
                    Expirada(item.id, motivo, item.profissional_id, item.cliente_id, item.pedido_id)
                )
        return saida

    def encerrar_por_pedido(
        self, pedido_id: str, profissional_aceito: str | None, agora: datetime
    ) -> list[Encerramento]:
        with self._trava:
            for item in list(self._itens.values()):
                if item.pedido_id != pedido_id or item.status not in EM_ANDAMENTO:
                    continue
                if profissional_aceito is not None and profissional_aceito == item.profissional_id:
                    self._mudar(item, status="concluida", encerrada_em=agora)
                    return [Encerramento(item.id, "concluida", item.profissional_id)]
                self._mudar(item, status="cancelada", encerrada_em=agora)
                self._estornar(item, agora)
                return [Encerramento(item.id, "cancelada", item.profissional_id)]
        return []

    # --- leitura --------------------------------------------------------------------------------

    def obter(self, exclusividade_id: str) -> Exclusividade | None:
        return self._itens.get(exclusividade_id)

    def do_profissional(self, profissional_id: str) -> list[Exclusividade]:
        meus = [i for i in self._itens.values() if i.profissional_id == profissional_id]
        return sorted(meus, key=lambda i: i.criada_em, reverse=True)

    def em_andamento_do_pedido(self, pedido_id: str) -> Exclusividade | None:
        return next(
            (
                i
                for i in self._itens.values()
                if i.pedido_id == pedido_id and i.status in EM_ANDAMENTO
            ),
            None,
        )

    def profissional_ativo_do_pedido(self, pedido_id: str) -> str | None:
        item = self.em_andamento_do_pedido(pedido_id)
        return item.profissional_id if item is not None and item.status == "ativa" else None


def profissional_exclusivo(contexto: Any, pedido_id: str) -> str | None:
    """Quem tem a exclusividade ATIVA do pedido (ou None). Nunca levanta: sem o armazenamento
    novo, ninguém é exclusivo e o pedido se comporta como antes."""
    try:
        return contexto.exclusividades.profissional_ativo_do_pedido(pedido_id)
    except Exception:  # noqa: BLE001 - tabela ainda não existe: sem exclusividade
        return None


def encerrar_exclusividade_do_pedido(
    contexto: Any, pedido_id: str, profissional_aceito: str | None
) -> list[Encerramento]:
    """Aceitar orçamento ou cancelar o pedido: encerra a exclusividade (estorna se não foi o
    profissional dela). Falha do armazenamento é registrada e não impede a ação do cliente."""
    try:
        return contexto.exclusividades.encerrar_por_pedido(
            pedido_id, profissional_aceito, contexto.agora()
        )
    except Exception:  # noqa: BLE001 - a ação do cliente vale; a rotina de expiração recolhe
        import logging

        logging.getLogger("trato.exclusividades").warning(
            "encerrar exclusividade do pedido %s falhou", pedido_id, exc_info=True
        )
        return []
