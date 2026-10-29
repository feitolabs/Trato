"""Orquestra o fluxo de dinheiro do pedido (F4.10): cobrança, webhook, ledger, estorno.

Regras que valem aqui:
- O pedido só vira "pago e retido" depois de webhook ASSINADO do provedor (D13). A criação
  da cobrança não muda o estado do pedido.
- O ledger só espelha o que o provedor confirmou (caminho A, D15).
- Cada operação financeira tem chave de idempotência determinística.
- Taxa e prazos vêm da configuração; o contrato congela a taxa no aceite.

Nada aqui conhece HTTP; as rotas ficam em `api/rotas_pagamento.py`.
"""

from __future__ import annotations

import uuid
from collections.abc import Callable
from dataclasses import replace

from trato.api.contexto import Contexto
from trato.api.repositorios import EventoWebhook
from trato.financeiro.ledger import (
    CUSTODIA,
    Livro,
    a_liberar,
    estornar_pedido,
    liberar,
    registrar_cobranca,
    repartir_custodia,
)
from trato.pagamentos.custo import MeioPagamento
from trato.pagamentos.modelos import (
    Aditivo,
    CobrancaLocal,
    ConfigPagamento,
    EstadoAditivo,
    EstadoCobranca,
    RepositorioAditivos,
    RepositorioCobrancas,
    RepositorioTermos,
    TermosContrato,
)
from trato.pagamentos.provedor.base import (
    EventoProvedor,
    ProvedorPagamento,
    StatusCobranca,
    TipoEvento,
)
from trato.pagamentos.provedor.stripe_formato import TIPOS_STRIPE
from trato.pagamentos.taxa import calcular_taxa
from trato.pedidos import estados
from trato.pedidos.estados import Acao, Ator, Estado, Papel, Pedido, ProvaPagamento


class ErroFluxo(Exception):
    """Pedido de pagamento que não vale agora. `status` é o HTTP que a rota devolve."""

    def __init__(self, mensagem: str, status: int = 409) -> None:
        super().__init__(mensagem)
        self.status = status


class EventoForaDeOrdem(Exception):
    """O evento chegou cedo demais. Sem tratar, o provedor reenvia depois."""


_SISTEMA = Ator(Papel.SISTEMA, "webhook")


class ServicoPagamento:
    def __init__(
        self,
        provedor: ProvedorPagamento,
        config: Callable[[], ConfigPagamento],
        cobrancas: RepositorioCobrancas,
        aditivos: RepositorioAditivos,
        termos: RepositorioTermos,
    ) -> None:
        self.provedor = provedor
        self.config = config
        self.cobrancas = cobrancas
        self.aditivos = aditivos
        self.termos = termos

    # --- ligação ao contexto da API ------------------------------------------------------

    def ligar(self, contexto: Contexto) -> None:
        """Registra os manipuladores de webhook e o gancho de transição no contexto."""
        contexto.segredo_webhook = self.provedor.segredo_webhook
        manipuladores = {
            TipoEvento.PAGAMENTO_CONFIRMADO: self._pagamento_confirmado,
            TipoEvento.PAGAMENTO_FALHOU: self._pagamento_falhou,
            TipoEvento.ESTORNO_CONFIRMADO: self._estorno_confirmado,
            TipoEvento.LIQUIDACAO: self._liquidacao,
        }
        for tipo_stripe, tipo in TIPOS_STRIPE.items():
            contexto.manipuladores_webhook[tipo_stripe] = self._manipulador(manipuladores[tipo])
        contexto.apos_transicao.append(self._apos_transicao)

    def _manipulador(self, funcao: Callable[[EventoProvedor, Contexto], None]):
        def manipular(evento: EventoWebhook, contexto: Contexto) -> None:
            traduzido = self.provedor.interpretar_evento(evento.payload)
            if traduzido is not None:
                funcao(traduzido, contexto)

        return manipular

    # --- cobrança --------------------------------------------------------------------------

    def cobrar(
        self,
        contexto: Contexto,
        pedido: Pedido,
        valor_centavos: int,
        meio: MeioPagamento,
        aditivo_id: str | None = None,
    ) -> CobrancaLocal:
        """Cria (ou devolve a pendente) a cobrança do pedido ou de um aditivo."""
        antigas = [c for c in self.cobrancas.do_pedido(pedido.id) if c.aditivo_id == aditivo_id]
        for antiga in antigas:
            if antiga.status is EstadoCobranca.AGUARDANDO:
                if antiga.meio is meio:
                    return antiga
                self.cobrancas.salvar(replace(antiga, status=EstadoCobranca.CANCELADA))
            elif antiga.status is EstadoCobranca.PAGA:
                raise ErroFluxo("Isto já foi pago.")
        chave = f"cob/{pedido.id}/{aditivo_id or 'principal'}/{len(antigas) + 1}"
        metadados = {"pedido_id": pedido.id}
        if aditivo_id:
            metadados["aditivo_id"] = aditivo_id
        criada = self.provedor.criar_cobranca(
            valor_centavos=valor_centavos,
            meio=meio,
            chave_idempotencia=chave,
            metadados=metadados,
        )
        local = CobrancaLocal(
            criada.id,
            pedido.id,
            criada.valor_centavos,
            meio,
            EstadoCobranca.AGUARDANDO,
            contexto.agora(),
            aditivo_id,
            criada.instrucao,
        )
        self.cobrancas.salvar(local)
        return local

    # --- aditivo -----------------------------------------------------------------------------

    def propor_aditivo(
        self, contexto: Contexto, pedido: Pedido, descricao: str, valor_centavos: int
    ) -> Aditivo:
        if pedido.estado is not Estado.EM_ANDAMENTO:
            raise ErroFluxo("Só dá para propor aditivo com o serviço em andamento.")
        aditivo = Aditivo(
            uuid.uuid4().hex,
            pedido.id,
            descricao,
            valor_centavos,
            EstadoAditivo.PROPOSTO,
            contexto.agora(),
        )
        self.aditivos.salvar(aditivo)
        return aditivo

    def aprovar_aditivo(
        self, contexto: Contexto, pedido: Pedido, aditivo_id: str, meio: MeioPagamento
    ) -> tuple[Aditivo, CobrancaLocal]:
        aditivo = self.aditivos.obter(aditivo_id)
        if aditivo is None or aditivo.pedido_id != pedido.id:
            raise ErroFluxo("Aditivo não encontrado.", 404)
        if aditivo.estado is not EstadoAditivo.PROPOSTO:
            raise ErroFluxo("Este aditivo já foi aprovado.")
        if pedido.estado is not Estado.EM_ANDAMENTO:
            raise ErroFluxo("Só dá para aprovar aditivo com o serviço em andamento.")
        aprovado = replace(aditivo, estado=EstadoAditivo.APROVADO, aprovado_em=contexto.agora())
        cobranca = self.cobrar(contexto, pedido, aprovado.valor_centavos, meio, aprovado.id)
        self.aditivos.salvar(aprovado)
        return aprovado, cobranca

    # --- webhooks ----------------------------------------------------------------------------

    def _pagamento_confirmado(self, evento: EventoProvedor, contexto: Contexto) -> None:
        cobranca = self.cobrancas.obter(evento.cobranca_id or "")
        if cobranca is None:
            raise EventoForaDeOrdem("Pagamento de uma cobrança que ainda não conheço.")
        if cobranca.status in (EstadoCobranca.PAGA, EstadoCobranca.DEVOLVIDA):
            return
        if evento.valor_centavos is not None and evento.valor_centavos != cobranca.valor_centavos:
            raise ErroFluxo("O valor pago não confere com a cobrança.", 422)
        agora = contexto.agora()
        pedido = contexto.pedidos.obter(cobranca.pedido_id)

        if cobranca.aditivo_id:
            aditivo = self.aditivos.obter(cobranca.aditivo_id)
            if aditivo is None or aditivo.estado is EstadoAditivo.PROPOSTO:
                return self._devolver_pagamento_orfao(cobranca)
            self.aditivos.salvar(replace(aditivo, estado=EstadoAditivo.PAGO))
        else:
            if pedido is None:
                return self._devolver_pagamento_orfao(cobranca)
            ja_confirmado = pedido.referencia_pagamento == cobranca.id
            outra_paga = any(
                c.status is EstadoCobranca.PAGA and c.aditivo_id is None and c.id != cobranca.id
                for c in self.cobrancas.do_pedido(pedido.id)
            )
            if not ja_confirmado and (pedido.estado is not Estado.ORCAMENTO_ACEITO or outra_paga):
                return self._devolver_pagamento_orfao(cobranca)
            if not ja_confirmado:
                transicao = estados.transicionar(
                    pedido,
                    Acao.CONFIRMAR_PAGAMENTO,
                    _SISTEMA,
                    agora,
                    ProvaPagamento(cobranca.id),
                )
                contexto.pedidos.salvar(transicao.pedido, transicao.evento)

        novos = self._planejar(
            contexto,
            cobranca.pedido_id,
            lambda livro: registrar_cobranca(
                livro, cobranca.pedido_id, cobranca.valor_centavos, f"cob/{cobranca.id}", agora
            ),
        )
        if novos:
            contexto.ledger.lancar_varios(novos)
        self.cobrancas.salvar(replace(cobranca, status=EstadoCobranca.PAGA, pago_em=agora))

    def _pagamento_falhou(self, evento: EventoProvedor, contexto: Contexto) -> None:
        cobranca = self.cobrancas.obter(evento.cobranca_id or "")
        # Falha que chega depois do pagamento (fora de ordem) não desfaz nada.
        if cobranca is not None and cobranca.status is EstadoCobranca.AGUARDANDO:
            self.cobrancas.salvar(replace(cobranca, status=EstadoCobranca.FALHOU))

    def _estorno_confirmado(self, evento: EventoProvedor, contexto: Contexto) -> None:
        """O ledger já foi estornado quando o Trato pediu; o webhook só confirma. Sem efeito."""

    def _liquidacao(self, evento: EventoProvedor, contexto: Contexto) -> None:
        cobranca = self.cobrancas.obter(evento.cobranca_id or "")
        pedido_id = evento.pedido_id or (cobranca.pedido_id if cobranca else None)
        pedido = contexto.pedidos.obter(pedido_id) if pedido_id else None
        if pedido is None or pedido.profissional_id is None:
            raise EventoForaDeOrdem("Liquidação de um pedido que não conheço.")
        if pedido.estado is not Estado.CONCLUIDO:
            raise EventoForaDeOrdem("Liquidação antes de o pedido concluir ou durante disputa.")
        conta = a_liberar(pedido.profissional_id)
        if contexto.ledger.saldo_da_conta(conta, pedido.id) <= 0:
            return
        agora = contexto.agora()
        novos = self._planejar(
            contexto,
            pedido.id,
            lambda livro: liberar(
                livro, pedido.id, pedido.profissional_id, f"liq/{evento.id}", agora
            ),
        )
        if novos:
            contexto.ledger.lancar_varios(novos)

    def _devolver_pagamento_orfao(self, cobranca: CobrancaLocal) -> None:
        """Pagou depois de o pedido cancelar/expirar: o dinheiro volta, sem passar pelo ledger."""
        self.provedor.estornar(cobranca.id, None, f"orfao/{cobranca.id}")
        self.cobrancas.salvar(replace(cobranca, status=EstadoCobranca.DEVOLVIDA))

    # --- depois de uma transição de estado ------------------------------------------------

    def _apos_transicao(
        self, antes: Pedido, depois: Pedido, acao: Acao, contexto: Contexto
    ) -> None:
        if acao is Acao.ACEITAR_ORCAMENTO:
            self.termos.salvar(TermosContrato(depois.id, self.config().taxa, contexto.agora()))
        elif depois.estado is Estado.CONCLUIDO and acao in (
            Acao.CONFIRMAR_CONCLUSAO,
            Acao.ENCERRAR_DISPUTA_POR_ACORDO,
        ):
            self.aplicar_dinheiro(contexto, depois, devolver_ao_cliente=0, repartir=True)
        elif depois.estado is Estado.CANCELADO and acao is Acao.CANCELAR:
            for c in self.cobrancas.do_pedido(depois.id):
                if c.status in (EstadoCobranca.AGUARDANDO, EstadoCobranca.FALHOU):
                    self.cobrancas.salvar(replace(c, status=EstadoCobranca.CANCELADA))
            retido = contexto.ledger.saldo_da_conta(CUSTODIA, depois.id)
            if retido > 0:
                self.aplicar_dinheiro(contexto, depois, devolver_ao_cliente=retido, repartir=False)

    # --- dinheiro ------------------------------------------------------------------------------

    def aplicar_dinheiro(
        self, contexto: Contexto, pedido: Pedido, *, devolver_ao_cliente: int, repartir: bool
    ) -> None:
        """Devolve `devolver_ao_cliente` ao cliente e/ou reparte o que resta na custódia.

        Primeiro valida tudo no ledger (nada é gravado se recusar), depois pede o estorno ao
        provedor, e só então grava no ledger.
        """
        agora = contexto.agora()
        n = len(contexto.ledger.lancamentos(pedido.id))
        chave = f"din/{pedido.id}/{n}"
        profissional = pedido.profissional_id or ""

        def operacao(livro: Livro) -> None:
            if devolver_ao_cliente > 0:
                estornar_pedido(livro, pedido.id, devolver_ao_cliente, f"{chave}/est", agora)
            restante = livro.saldo(CUSTODIA, pedido.id)
            if repartir and restante > 0:
                termos = self.termos.obter(pedido.id)
                taxa = calcular_taxa(restante, (termos.taxa if termos else self.config().taxa))
                repartir_custodia(livro, pedido.id, profissional, taxa, f"{chave}/rep", agora)

        novos = self._planejar(contexto, pedido.id, operacao)
        if devolver_ao_cliente > 0:
            self._estornar_no_provedor(pedido.id, devolver_ao_cliente, chave)
        if novos:
            contexto.ledger.lancar_varios(novos)

    def _estornar_no_provedor(self, pedido_id: str, valor: int, chave: str) -> None:
        falta = valor
        pagas = [c for c in self.cobrancas.do_pedido(pedido_id) if c.status is EstadoCobranca.PAGA]
        for cobranca in reversed(pagas):  # a mais nova primeiro (aditivo antes do principal)
            parte = min(falta, cobranca.valor_centavos - cobranca.estornado_centavos)
            if parte <= 0:
                continue
            self.provedor.estornar(cobranca.id, parte, f"{chave}/{cobranca.id}")
            self.cobrancas.salvar(
                replace(cobranca, estornado_centavos=cobranca.estornado_centavos + parte)
            )
            falta -= parte
            if falta == 0:
                return
        if falta:
            raise ErroFluxo("Não há pagamento confirmado suficiente para devolver.")

    @staticmethod
    def _planejar(contexto: Contexto, pedido_id: str, operacao: Callable[[Livro], object]):
        """Roda a operação num livro temporário com o histórico do pedido; devolve só o novo."""
        livro = Livro()
        antigos = contexto.ledger.lancamentos(pedido_id)
        if antigos:
            livro.lancar_varios(antigos)
        antes = len(livro.lancamentos)
        operacao(livro)
        return livro.lancamentos[antes:]


__all__ = ["ErroFluxo", "EventoForaDeOrdem", "ServicoPagamento", "StatusCobranca"]
