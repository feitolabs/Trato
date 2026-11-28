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

from trato.api.moedas_saldo import parcelas_do_gasto
from trato.api.validade import orcamento_vencido
from trato.disputas.indisponibilidade import prorrogar
from trato.pedidos.estados import Acao, Ator, Estado, Evento, Papel

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
    # Quem pagou: "cliente" (Termos 13.6) ou "profissional" (forma antiga, em encerramento).
    pagador: str = "profissional"
    orcamento_id: str | None = None
    motivo_encerramento: str | None = None
    estornada: bool = False
    estornada_em: datetime | None = None


@dataclass(frozen=True)
class ResultadoCliente:
    # ok | ja_existe | nao_encontrado | pedido_indisponivel | orcamento_invalido |
    # profissional_indisponivel | saldo_insuficiente | indisponivel
    resultado: str
    exclusividade_id: str | None = None
    expira_em: datetime | None = None
    saldo_restante: int | None = None


@dataclass(frozen=True)
class ResultadoDevolucao:
    # ok | ja_devolvida | nao_encontrada | ja_encerrada | prazo_vencido | analista_invalido |
    # nao_elegivel | indisponivel
    resultado: str
    devolvido: int = 0


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

    def prazo_de_resposta(self, item: Exclusividade) -> datetime | None:
        """22.3 (só 'app'): `responder_ate` prorrogado. `None`: suspenso por falha ativa."""
        if item.responder_ate is None:
            return None
        falhas = [
            (j.inicio_em, j.fim_em)
            for j in self._contexto.indisponibilidades.listar(desde=item.criada_em)
            if j.origem == "app"
        ]
        return prorrogar(item.criada_em, item.responder_ate - item.criada_em, falhas)

    def _passou_o_prazo(self, item: Exclusividade, agora: datetime) -> bool:
        limite = self.prazo_de_resposta(item)
        return limite is not None and limite < agora

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
            if self._passou_o_prazo(item, agora):
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
                if item.pagador == "cliente":
                    continue
                if item.status == "aguardando_cliente" and self._passou_o_prazo(item, agora):
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
                if item.pagador == "cliente":
                    continue
                if profissional_aceito is not None and profissional_aceito == item.profissional_id:
                    self._mudar(item, status="concluida", encerrada_em=agora)
                    return [Encerramento(item.id, "concluida", item.profissional_id)]
                self._mudar(item, status="cancelada", encerrada_em=agora)
                self._estornar(item, agora)
                return [Encerramento(item.id, "cancelada", item.profissional_id)]
        return []

    # --- paga pelo cliente (mesma semântica das funções `exclusividade_cliente_*`) ---------------

    def cliente_disponivel(self) -> bool:
        return True

    def saldo_livre(self, cliente_id: str, agora: datetime) -> int:
        moedas = self._contexto.moedas
        presas = sum(r.moedas for r in moedas.reservas_abertas_do_usuario(cliente_id))
        return max(int(moedas.saldo(cliente_id, agora, "cliente")) - presas, 0)

    def do_pedido_cliente(self, pedido_id: str) -> Exclusividade | None:
        minhas = [
            i for i in self._itens.values() if i.pedido_id == pedido_id and i.pagador == "cliente"
        ]
        return minhas[-1] if minhas else None

    def listar_cliente(
        self,
        pedido_id: str | None = None,
        cliente_id: str | None = None,
        status: str | None = None,
        limite: int = 20,
        deslocamento: int = 0,
    ) -> tuple[list[Exclusividade], int]:
        achadas = [
            i
            for i in reversed(list(self._itens.values()))
            if i.pagador == "cliente"
            and pedido_id in (None, i.pedido_id)
            and cliente_id in (None, i.cliente_id)
            and status in (None, i.status)
        ]
        return achadas[deslocamento : deslocamento + limite], len(achadas)

    def _lancar_cliente(
        self, item: Exclusividade, tipo: str, quantidade: int, chave: str, agora, expira=None
    ) -> None:
        from trato.api.moedas import LancamentoMoeda

        self._contexto.moedas.lancar(
            LancamentoMoeda(
                usuario_id=item.cliente_id,
                tipo=tipo,
                quantidade=quantidade,
                chave_idempotencia=chave,
                criada_em=agora,
                referencia_id=item.id,
                parceiro_id=item.profissional_id,
                carteira="cliente",
                expira_em=expira,
            )
        )

    def _transicao_pedido(
        self, pedido_id: str, de: Estado, para: Estado, acao: Acao, agora
    ) -> None:
        pedido = self._contexto.pedidos.obter(pedido_id)
        if pedido is None or pedido.estado is not de:
            return
        ator = Ator(Papel.SISTEMA, "exclusividade")
        evento = Evento(pedido_id, acao, de, para, ator, agora, None)
        self._contexto.pedidos.salvar(replace(pedido, estado=para), evento)

    def solicitar_cliente(
        self,
        cliente_id: str,
        pedido_id: str,
        profissional_id: str | None,
        orcamento_id: str | None,
        chave: str,
        agora: datetime,
        exigir_mei: bool,
        apto: Any,
    ) -> ResultadoCliente:
        """`apto(profissional_id)`: a regra de quem pode orçar (no banco, dentro da função)."""
        cfg = self._contexto.moedas.config()
        with self._trava, self._contexto.moedas.trava(f"exclusividade:{cliente_id}"):
            saldo = self.saldo_livre(cliente_id, agora)

            def nega(resultado: str) -> ResultadoCliente:
                return ResultadoCliente(resultado, saldo_restante=saldo)

            if chave in self._por_chave:
                antiga = self._itens[self._por_chave[chave]]
                if (antiga.pagador, antiga.cliente_id, antiga.pedido_id) != (
                    "cliente",
                    cliente_id,
                    pedido_id,
                ):
                    raise ValueError("chave de idempotência já usada em outra exclusividade")
                return ResultadoCliente("ja_existe", antiga.id, antiga.expira_em, saldo)
            pedido = self._contexto.pedidos.obter(pedido_id)
            if pedido is None or pedido.cliente_id != cliente_id:
                return nega("nao_encontrado")
            if pedido.estado is not Estado.ABERTO or any(
                i.pedido_id == pedido_id and i.status in EM_ANDAMENTO for i in self._itens.values()
            ):
                return nega("pedido_indisponivel")
            if orcamento_id is not None:
                orcamento = self._contexto.orcamentos.obter(orcamento_id)
                if (
                    orcamento is None
                    or orcamento.pedido_id != pedido_id
                    or profissional_id not in (None, orcamento.profissional_id)
                ):
                    return nega("orcamento_invalido")
                if orcamento_vencido(self._contexto, orcamento_id, agora):  # 5.2 e 22.3
                    return nega("orcamento_invalido")
                profissional_id = orcamento.profissional_id
            if not profissional_id or not apto(profissional_id):
                return nega("profissional_indisponivel")
            custo = cfg.exclusividade_custo_moedas
            if saldo < custo:
                return nega("saldo_insuficiente")
            novo = Exclusividade(
                id=uuid.uuid4().hex,
                profissional_id=profissional_id,
                cliente_id=cliente_id,
                pedido_id=pedido_id,
                status="ativa",
                moedas_cobradas=custo,
                chave_idempotencia=chave,
                criada_em=agora,
                responder_ate=agora,
                expira_em=agora + timedelta(hours=cfg.exclusividade_duracao_horas),
                pagador="cliente",
                orcamento_id=orcamento_id,
            )
            self._itens[novo.id] = novo
            self._por_chave[chave] = novo.id
            self._lancar_cliente(novo, TIPO_USO, -custo, f"exclusividade-uso:{novo.id}", agora)
            self._transicao_pedido(
                pedido_id, Estado.ABERTO, Estado.RESERVADO, Acao.RESERVAR_EXCLUSIVIDADE, agora
            )
            return ResultadoCliente("ok", novo.id, novo.expira_em, saldo - custo)

    def _vencer(self, item: Exclusividade, agora: datetime) -> None:
        self._mudar(
            item,
            status="expirada_sem_contratacao",
            motivo_encerramento="prazo_expirado_sem_contratacao",
            encerrada_em=agora,
        )
        self._transicao_pedido(
            item.pedido_id, Estado.RESERVADO, Estado.ABERTO, Acao.EXPIRAR_EXCLUSIVIDADE, agora
        )

    def _devolver(self, item: Exclusividade, motivo: str, agora: datetime) -> int:
        """Devolve na validade original; o que já venceu volta como crédito de 30 dias (13.8)."""
        uso = f"exclusividade-uso:{item.id}"
        base = f"exclusividade-estorno:{item.id}"
        parcelas = parcelas_do_gasto(
            self._contexto.moedas.lancamentos_da_carteira(item.cliente_id, "cliente"), uso
        )
        falta, indice = item.moedas_cobradas, 0
        for parcela in parcelas:
            parte = min(parcela.quantidade, falta)
            if parte <= 0:
                break
            indice += 1
            expira = parcela.expira_em
            if expira is not None and expira <= agora:
                expira = agora + timedelta(days=30)
            chave = base if indice == 1 else f"{base}:{indice}"
            self._lancar_cliente(item, TIPO_ESTORNO, parte, chave, agora, expira)
            falta -= parte
        if falta > 0:
            chave = base if indice == 0 else f"{base}:{indice + 1}"
            self._lancar_cliente(
                item, TIPO_ESTORNO, falta, chave, agora, agora + timedelta(days=30)
            )
        ativa = item.status == "ativa"
        self._mudar(
            item,
            status="cancelada",
            motivo_encerramento=motivo,
            estornada=True,
            estornada_em=agora,
            encerrada_em=item.encerrada_em or agora,
        )
        if ativa:
            self._transicao_pedido(
                item.pedido_id, Estado.RESERVADO, Estado.ABERTO, Acao.EXPIRAR_EXCLUSIVIDADE, agora
            )
        return item.moedas_cobradas

    def desistir_cliente(
        self, exclusividade_id: str, profissional_id: str, agora: datetime
    ) -> ResultadoDevolucao:
        with self._trava:
            item = self._itens.get(exclusividade_id)
            if item is None or item.pagador != "cliente" or item.profissional_id != profissional_id:
                return ResultadoDevolucao("nao_encontrada")
            if item.estornada:
                return ResultadoDevolucao("ja_devolvida", item.moedas_cobradas)
            if item.status != "ativa":
                return ResultadoDevolucao("ja_encerrada")
            if item.expira_em <= agora:
                self._vencer(item, agora)
                return ResultadoDevolucao("prazo_vencido")
            return ResultadoDevolucao("ok", self._devolver(item, "desistencia_profissional", agora))

    def falha_trato(
        self, exclusividade_id: str, analista_id: str, motivo: str, agora: datetime
    ) -> ResultadoDevolucao:
        with self._trava:
            item = self._itens.get(exclusividade_id)
            if item is None or item.pagador != "cliente":
                return ResultadoDevolucao("nao_encontrada")
            if item.estornada:
                return ResultadoDevolucao("ja_devolvida", item.moedas_cobradas)
            if item.status == "concluida":
                return ResultadoDevolucao("nao_elegivel")
            return ResultadoDevolucao("ok", self._devolver(item, "falha_trato", agora))

    def contratar_cliente(
        self, pedido_id: str, profissional_id: str | None, agora: datetime
    ) -> list[Encerramento]:
        """Contratação confirmada (ou pedido cancelado, sem profissional): nunca devolve."""
        with self._trava:
            item = self.do_pedido_cliente(pedido_id)
            if item is None or item.status != "ativa":
                return []
            if item.expira_em <= agora:
                status, motivo = "expirada_sem_contratacao", "prazo_expirado_sem_contratacao"
                resultado = "expirada"
            elif profissional_id == item.profissional_id:
                status, motivo, resultado = "concluida", "contratacao_realizada", "concluida"
            else:
                status, motivo, resultado = "cancelada", "cancelamento_cliente", "cancelada"
            self._mudar(item, status=status, motivo_encerramento=motivo, encerrada_em=agora)
            return [Encerramento(item.id, resultado, item.profissional_id)]

    def expirar_cliente(self, agora: datetime) -> list[Expirada]:
        saida: list[Expirada] = []
        with self._trava:
            for item in list(self._itens.values()):
                if item.pagador == "cliente" and item.status == "ativa" and item.expira_em <= agora:
                    self._vencer(item, agora)
                    saida.append(
                        Expirada(
                            item.id,
                            "sem_contratacao",
                            item.profissional_id,
                            item.cliente_id,
                            item.pedido_id,
                        )
                    )
        return saida

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


def encerrar_na_contratacao(contexto: Any, pedido_id: str, profissional_id: str | None) -> None:
    """Pagamento confirmado (ou pedido cancelado: sem profissional) encerra a exclusividade do
    cliente, na mesma transação da mudança do pedido. Sem a função no banco, nada acontece."""
    contexto.exclusividades.contratar_cliente(pedido_id, profissional_id, contexto.agora())


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
