"""Orquestra o fluxo de dinheiro do pedido (F4.10): cobrança, webhook, ledger, estorno.

Regras que valem aqui:
- O pedido só vira "pago e retido" depois de webhook ASSINADO do provedor (D13). A criação
  da cobrança não muda o estado do pedido.
- O ledger só espelha o que o provedor confirmou (caminho A, D15).
- Cada operação financeira tem chave de idempotência determinística (de dado estável, nunca
  de contagem).
- Não há taxa do Trato (app 100% gratuito, 18/11/2026); prazos vêm da configuração.
- Estorno: a intenção vai para o ledger e para a fila de ordens ANTES de o provedor ser chamado;
  o provedor só é chamado depois do commit, com a chave da ordem, e a reconciliação reenvia o que
  ficou pendente (A7). Nunca dinheiro que saiu sem registro.
- Webhook com valor divergente ou destino desconhecido: guarda para revisão e responde 2xx
  (sem 422 em loop, M2).

Nada aqui conhece HTTP; as rotas ficam em `api/rotas_pagamento.py`.
"""

from __future__ import annotations

import hashlib
import uuid
from collections.abc import Callable
from dataclasses import replace

from trato.api.contexto import Contexto
from trato.api.moedas import debitar_uso_moedas, devolver_uso_moedas
from trato.api.repositorios import EventoWebhook
from trato.api.webhook_pagamento import EventoForaDeOrdem  # a rota do webhook responde 409
from trato.financeiro.contestacoes import (
    Contestacao,
    StatusContestacao,
    ler_disputa_stripe,
    mesclar,
)
from trato.financeiro.ledger import (
    CUSTODIA,
    LedgerErro,
    Livro,
    estornar_pedido,
    liberar,
    registrar_cobranca,
    repartir_custodia,
    separar_custo_parcelamento,
)
from trato.financeiro.repasses import repasse_dos_lancamentos
from trato.pagamentos.cupons import confirmar_uso_cupom
from trato.pagamentos.custo import MeioPagamento
from trato.pagamentos.memoria import OrdensEstornoEmMemoria
from trato.pagamentos.modelos import (
    Aditivo,
    CobrancaLocal,
    ConfigPagamento,
    EstadoAditivo,
    EstadoCobranca,
    OrdemEstorno,
    RepositorioAditivos,
    RepositorioCobrancas,
    RepositorioOrdensEstorno,
)
from trato.pagamentos.parcelamento import ParcelamentoIndisponivel
from trato.pagamentos.provedor.base import (
    EventoProvedor,
    ProvedorPagamento,
    StatusCobranca,
    TipoEvento,
)
from trato.pagamentos.provedor.stripe_formato import TIPOS_STRIPE
from trato.pagamentos.taxa import TotalPedido, montar_total
from trato.pedidos import estados
from trato.pedidos.estados import Acao, Ator, Estado, Papel, Pedido, ProvaPagamento


def _mesmo_id(a: str, b: str) -> bool:
    """Ids de pedido iguais mesmo em formatos diferentes (com ou sem hífen): o banco devolve o
    aditivo com o id em hex e a rota traz o do pedido com hífen."""
    return str(a).replace("-", "").lower() == str(b).replace("-", "").lower()


class ErroFluxo(Exception):
    """Pedido de pagamento que não vale agora. `status` é o HTTP que a rota devolve."""

    def __init__(self, mensagem: str, status: int = 409) -> None:
        super().__init__(mensagem)
        self.status = status


_SISTEMA = Ator(Papel.SISTEMA, "webhook")


class ServicoPagamento:
    def __init__(
        self,
        provedor: ProvedorPagamento,
        config: Callable[[], ConfigPagamento],
        cobrancas: RepositorioCobrancas,
        aditivos: RepositorioAditivos,
        ordens: RepositorioOrdensEstorno | None = None,
    ) -> None:
        self.provedor = provedor
        self.config = config
        self.cobrancas = cobrancas
        self.aditivos = aditivos
        self.ordens = ordens if ordens is not None else OrdensEstornoEmMemoria()

    # --- ligação ao contexto da API ------------------------------------------------------

    def ligar(self, contexto: Contexto) -> None:
        """Registra os manipuladores de webhook e o gancho de transição no contexto."""
        contexto.segredo_webhook = self.provedor.segredo_webhook
        manipuladores = {
            TipoEvento.PAGAMENTO_CONFIRMADO: self._pagamento_confirmado,
            TipoEvento.PAGAMENTO_FALHOU: self._pagamento_falhou,
            TipoEvento.ESTORNO_CONFIRMADO: self._estorno_confirmado,
            TipoEvento.LIQUIDACAO: self._liquidacao,
            TipoEvento.CONTESTACAO: self._contestacao,
            TipoEvento.REPASSE_FALHOU: self._repasse_falhou,
        }
        for tipo_stripe, tipo in TIPOS_STRIPE.items():
            contexto.manipuladores_webhook[tipo_stripe] = self._manipulador(manipuladores[tipo])
        contexto.apos_transicao.append(self._apos_transicao)

    def _manipulador(self, funcao: Callable[[EventoProvedor, Contexto, EventoWebhook], None]):
        def manipular(evento: EventoWebhook, contexto: Contexto) -> None:
            traduzido = self.provedor.interpretar_evento(evento.payload)
            if traduzido is not None:
                funcao(traduzido, contexto, evento)

        return manipular

    # --- cobrança --------------------------------------------------------------------------

    def total_a_cobrar(
        self,
        contexto: Contexto,
        pedido: Pedido,
        servico_centavos: int,
        aditivo_id: str | None = None,
        parcelas: int = 1,
    ) -> TotalPedido:
        """Quanto cobrar do cliente por `servico_centavos`: o serviço (+ custo do parcelado).

        Não há taxa do Trato: o profissional recebe o serviço inteiro.
        """
        total = montar_total(servico_centavos)
        if parcelas == 1:
            return total
        try:
            custo = self.config().parcelamento.custo_centavos(total.servico_centavos, parcelas)
        except ParcelamentoIndisponivel as erro:
            raise ErroFluxo(str(erro), 422) from erro
        return replace(
            total,
            custo_parcelamento_centavos=custo,
            cobrado_centavos=total.cobrado_centavos + custo,
        )

    def cobrar(
        self,
        contexto: Contexto,
        pedido: Pedido,
        servico_centavos: int,
        meio: MeioPagamento,
        aditivo_id: str | None = None,
        parcelas: int = 1,
        cliente_externo: str | None = None,
        cupom_codigo: str | None = None,
        desconto_centavos: int = 0,
        moedas_usadas: int = 0,
    ) -> CobrancaLocal:
        """Cria (ou devolve a pendente) a cobrança do pedido ou de um aditivo.

        `servico_centavos` é o valor do serviço; a cobrança sai por esse valor (+ o custo repassado
        do parcelado). Parcelado só no cartão e só com o custo na tabela.
        """
        if isinstance(parcelas, bool) or not isinstance(parcelas, int) or parcelas < 1:
            raise ErroFluxo("Número de parcelas inválido.", 422)
        if parcelas > 1 and meio is not MeioPagamento.CARTAO:
            raise ErroFluxo("Só o cartão pode ser parcelado.", 422)
        cupom_norm = cupom_codigo.strip().upper() if cupom_codigo and cupom_codigo.strip() else None
        moedas = max(0, int(moedas_usadas))
        desconto = max(0, int(desconto_centavos)) if (cupom_norm or moedas) else 0
        antigas = [c for c in self.cobrancas.do_pedido(pedido.id) if c.aditivo_id == aditivo_id]
        for antiga in antigas:
            if antiga.status is EstadoCobranca.PAGA:
                raise ErroFluxo("Isto já foi pago.")
        total = self.total_a_cobrar(contexto, pedido, servico_centavos, aditivo_id, parcelas)
        for antiga in antigas:
            if antiga.status is EstadoCobranca.AGUARDANDO:
                if (
                    antiga.meio is meio
                    and antiga.parcelas == parcelas
                    and antiga.valor_centavos == total.cobrado_centavos
                    and (antiga.cupom_codigo or None) == cupom_norm
                    and antiga.moedas_usadas == moedas
                ):
                    return antiga
                self.cobrancas.salvar(replace(antiga, status=EstadoCobranca.CANCELADA))
        # A chave leva o que define a cobrança (meio, valor, parcelas, cliente, cupom): o Stripe
        # recusa a MESMA chave com parâmetros diferentes ("Keys for idempotent requests can only be
        # used with the same parameters").
        assinatura = hashlib.sha256(
            f"{meio.value}|{total.cobrado_centavos}|{parcelas}|{cliente_externo or ''}|"
            f"{cupom_norm or ''}|{moedas}".encode()
        ).hexdigest()[:10]
        chave = f"cob/{pedido.id}/{aditivo_id or 'principal'}/{len(antigas) + 1}/{assinatura}"
        metadados = {"pedido_id": pedido.id}
        if aditivo_id:
            metadados["aditivo_id"] = aditivo_id
        if cupom_norm:
            metadados["cupom"] = cupom_norm
        if moedas:
            metadados["moedas"] = str(moedas)
        criada = self.provedor.criar_cobranca(
            valor_centavos=total.cobrado_centavos,
            meio=meio,
            chave_idempotencia=chave,
            metadados=metadados,
            parcelas=parcelas,
            cliente_externo=cliente_externo,
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
            parcelas=parcelas,
            servico_centavos=servico_centavos,
            cupom_codigo=cupom_norm,
            desconto_centavos=desconto,
            moedas_usadas=moedas,
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
        self,
        contexto: Contexto,
        pedido: Pedido,
        aditivo_id: str,
        meio: MeioPagamento,
        cliente_externo: str | None = None,
    ) -> tuple[Aditivo, CobrancaLocal]:
        aditivo = self.aditivos.obter(aditivo_id)
        if aditivo is None or not _mesmo_id(aditivo.pedido_id, pedido.id):
            raise ErroFluxo("Aditivo não encontrado.", 404)
        if aditivo.estado is not EstadoAditivo.PROPOSTO:
            raise ErroFluxo("Este aditivo já foi aprovado.")
        if pedido.estado is not Estado.EM_ANDAMENTO:
            raise ErroFluxo("Só dá para aprovar aditivo com o serviço em andamento.")
        aprovado = replace(aditivo, estado=EstadoAditivo.APROVADO, aprovado_em=contexto.agora())
        # Uma transação só: o banco exige o aditivo aprovado antes de aceitar a cobrança dele, e
        # se a cobrança falhar a aprovação volta junto (o cliente pode tentar de novo).
        with contexto.transacao():
            self.aditivos.salvar(aprovado)
            cobranca = self.cobrar(
                contexto,
                pedido,
                aprovado.valor_centavos,
                meio,
                aprovado.id,
                cliente_externo=cliente_externo,
            )
        return aprovado, cobranca

    def recusar_aditivo(self, contexto: Contexto, pedido: Pedido, aditivo_id: str) -> Aditivo:
        aditivo = self.aditivos.obter(aditivo_id)
        if aditivo is None or not _mesmo_id(aditivo.pedido_id, pedido.id):
            raise ErroFluxo("Aditivo não encontrado.", 404)
        if aditivo.estado is not EstadoAditivo.PROPOSTO:
            raise ErroFluxo("Este aditivo já foi decidido.")
        recusado = replace(aditivo, estado=EstadoAditivo.RECUSADO)
        self.aditivos.salvar(recusado)
        return recusado

    # --- webhooks ----------------------------------------------------------------------------

    def _pagamento_confirmado(
        self, evento: EventoProvedor, contexto: Contexto, bruto: EventoWebhook
    ) -> None:
        cobranca = self.cobrancas.obter(evento.cobranca_id or "")
        if cobranca is None:
            raise EventoForaDeOrdem("Pagamento de uma cobrança que ainda não conheço.")
        if cobranca.status in (EstadoCobranca.PAGA, EstadoCobranca.DEVOLVIDA):
            return
        # M1/M2: o valor pago tem de ser inteiro e igual ao da cobrança. Se não for, nada vira
        # pago: o evento fica guardado para o financeiro e o provedor recebe 2xx (sem reenvio).
        if evento.valor_centavos is None or evento.valor_centavos != cobranca.valor_centavos:
            contexto.eventos_webhook.marcar_revisao(
                bruto,
                f"valor pago {evento.valor_centavos} diferente da cobrança "
                f"{cobranca.valor_centavos} ({cobranca.id})",
            )
            return
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

        # O custo do parcelado sai da custódia já na confirmação. O serviço fica retido inteiro: a
        # taxa só é descontada do profissional na conclusão, e reembolso devolve o valor todo.
        servico = self._servico_da_cobranca(contexto, cobranca)
        custo_parcelamento = cobranca.valor_centavos - servico

        def lancar(livro: Livro) -> None:
            registrar_cobranca(
                livro,
                cobranca.pedido_id,
                cobranca.valor_centavos,
                f"cob/{cobranca.id}",
                agora,
                bruto.evento_id,
            )
            if custo_parcelamento > 0:
                separar_custo_parcelamento(
                    livro,
                    cobranca.pedido_id,
                    custo_parcelamento,
                    f"cob/{cobranca.id}",
                    agora,
                    bruto.evento_id,
                )

        novos = self._planejar(contexto, cobranca.pedido_id, lancar)
        if novos:
            contexto.ledger.lancar_varios(novos)
        self.cobrancas.salvar(replace(cobranca, status=EstadoCobranca.PAGA, pago_em=agora))
        if cobranca.moedas_usadas > 0 and pedido is not None:
            debitar_uso_moedas(
                contexto.moedas,
                usuario_id=pedido.cliente_id,
                cobranca_id=cobranca.id,
                pedido_id=cobranca.pedido_id,
                moedas=cobranca.moedas_usadas,
                agora=agora,
            )
        if cobranca.cupom_codigo:
            confirmar_uso_cupom(
                contexto,
                cobranca.cupom_codigo,
                usuario_id=pedido.cliente_id if pedido is not None else None,
                cobranca_id=cobranca.id,
                pedido_id=cobranca.pedido_id,
                desconto_centavos=cobranca.desconto_centavos,
                confirmado_em=agora,
            )

    def _pagamento_falhou(
        self, evento: EventoProvedor, contexto: Contexto, bruto: EventoWebhook
    ) -> None:
        cobranca = self.cobrancas.obter(evento.cobranca_id or "")
        # Falha que chega depois do pagamento (fora de ordem) não desfaz nada.
        if cobranca is not None and cobranca.status is EstadoCobranca.AGUARDANDO:
            self.cobrancas.salvar(replace(cobranca, status=EstadoCobranca.FALHOU))

    def _estorno_confirmado(
        self, evento: EventoProvedor, contexto: Contexto, bruto: EventoWebhook
    ) -> None:
        """`charge.refunded`: concilia o total devolvido pelo provedor com o que o Trato pediu.

        Até o valor que o Trato mandou devolver (ordens de estorno) é só confirmação. O que
        passar disso foi reembolso feito por fora (painel do provedor): entra no ledger como
        estorno e o evento fica marcado para o financeiro (M3). Sem como lançar (ex.: o valor
        já foi liberado), fica só o alerta.
        """
        cobranca = self.cobrancas.obter(evento.cobranca_id or "")
        if cobranca is None:
            contexto.eventos_webhook.marcar_revisao(bruto, "estorno de cobrança desconhecida")
            return
        total = evento.valor_centavos
        if total is None:
            contexto.eventos_webhook.marcar_revisao(bruto, "estorno sem valor inteiro")
            return
        por_fora = total - cobranca.estornado_centavos
        if por_fora <= 0:
            return  # o que o Trato mandou devolver: nada a fazer
        pedido = contexto.pedidos.obter(cobranca.pedido_id)
        motivo = f"reembolso de {por_fora} centavos feito por fora do Trato ({cobranca.id})"
        if pedido is None:
            contexto.eventos_webhook.marcar_revisao(bruto, motivo)
            return
        try:
            novos = self._planejar(
                contexto,
                pedido.id,
                lambda livro: estornar_pedido(
                    livro,
                    pedido.id,
                    por_fora,
                    f"conc/{bruto.evento_id}",
                    contexto.agora(),
                    bruto.evento_id,
                ),
            )
            if novos:
                contexto.ledger.lancar_varios(novos)
        except LedgerErro as erro:
            contexto.eventos_webhook.marcar_revisao(bruto, f"{motivo}; não foi lançado: {erro}")
            return
        devolvido = cobranca.estornado_centavos + por_fora
        situacao = (
            EstadoCobranca.DEVOLVIDA if devolvido >= cobranca.valor_centavos else cobranca.status
        )
        depois = replace(cobranca, estornado_centavos=devolvido, status=situacao)
        self.cobrancas.salvar(depois)
        self._devolver_moedas(contexto, depois)
        contexto.eventos_webhook.marcar_revisao(bruto, f"{motivo}; conciliado no ledger")

    def _liquidacao(self, evento: EventoProvedor, contexto: Contexto, bruto: EventoWebhook) -> None:
        """`payout.paid`: libera SÓ o repasse a que o aviso se refere (M5).

        O repasse é achado pelo id da transferência no provedor (ou, na primeira vez, pelo
        `repasse_id` que o Trato pôs nos metadados ao pedir a transferência). O valor tem de ser
        o líquido do repasse. Sem repasse, ou com valor diferente, o evento vai para revisão.
        """
        repasses = contexto.repasses
        repasse = repasses.por_transferencia(evento.objeto_id) if evento.objeto_id else None
        if repasse is None:
            candidato = repasses.obter(evento.metadados.get("repasse_id", ""))
            if candidato is not None and candidato.provedor_transferencia_id is None:
                repasse = candidato
        if repasse is None:
            contexto.eventos_webhook.marcar_revisao(bruto, "liquidação sem repasse correspondente")
            return
        if evento.valor_centavos != repasse.valor_liquido_centavos:
            contexto.eventos_webhook.marcar_revisao(
                bruto,
                f"liquidação de {evento.valor_centavos} centavos; o repasse {repasse.id} "
                f"é de {repasse.valor_liquido_centavos}",
            )
            return
        if repasse.status == "liberado":
            return
        pedido = contexto.pedidos.obter(repasse.pedido_id)
        if pedido is None or pedido.profissional_id != repasse.profissional_id:
            contexto.eventos_webhook.marcar_revisao(bruto, "liquidação de pedido desconhecido")
            return
        if pedido.estado is not Estado.CONCLUIDO:
            raise EventoForaDeOrdem("Liquidação antes de o pedido concluir ou durante disputa.")
        if contexto.contestacoes.abertas_do_pedido(pedido.id):
            # O provedor já pagou (o espelho registra), mas o financeiro precisa saber: se a
            # contestação for perdida, o valor sai do Trato e não do profissional.
            contexto.eventos_webhook.marcar_revisao(
                bruto, f"repasse liberado com contestação de cartão aberta no pedido {pedido.id}"
            )
        agora = contexto.agora()
        novos = self._planejar(
            contexto,
            pedido.id,
            lambda livro: liberar(
                livro,
                pedido.id,
                repasse.profissional_id,
                f"liq/{repasse.id}",
                agora,
                repasse.valor_liquido_centavos,
                bruto.evento_id,
            ),
        )
        gravados = contexto.ledger.lancar_varios(novos) if novos else ()
        if evento.objeto_id:
            repasses.vincular_transferencia(repasse.id, evento.objeto_id)
        if gravados:
            repasses.marcar_liberado(repasse.id, gravados[0].id, agora)

    def _contestacao(
        self, evento: EventoProvedor, contexto: Contexto, bruto: EventoWebhook
    ) -> None:
        """`charge.dispute.*`: registra a contestação e, quando PERDIDA, espelha no ledger.

        Perdida = o banco do cliente devolveu o valor a ele: o mesmo efeito de um reembolso feito
        por fora (estorno do pedido, a taxa não volta). Sem como lançar (ex.: o valor já foi
        liberado ao profissional), fica o alerta para o financeiro. Aberta, em análise, ganha ou
        encerrada só atualizam o registro: o dinheiro não muda no espelho.
        """
        dados = bruto.payload.get("data")
        objeto = dados.get("object") if isinstance(dados, dict) else None
        nova = ler_disputa_stripe(objeto if isinstance(objeto, dict) else {}, contexto.agora())
        if nova is None:
            contexto.eventos_webhook.marcar_revisao(bruto, "contestação sem id, valor ou status")
            return
        cobranca = self.cobrancas.obter(nova.cobranca_id or "")
        if cobranca is not None:
            nova = replace(nova, pedido_id=cobranca.pedido_id)
        antiga = contexto.contestacoes.obter(nova.provedor_contestacao_id)
        atual = mesclar(antiga, nova)
        contexto.contestacoes.salvar(atual)
        if cobranca is None:
            contexto.eventos_webhook.marcar_revisao(bruto, "contestação de cobrança desconhecida")
            return
        ja_perdida = antiga is not None and antiga.status is StatusContestacao.PERDIDA
        if atual.status is StatusContestacao.PERDIDA and not ja_perdida:
            self._contestacao_perdida(atual, cobranca, contexto, bruto)

    def _contestacao_perdida(
        self,
        contestacao: Contestacao,
        cobranca: CobrancaLocal,
        contexto: Contexto,
        bruto: EventoWebhook,
    ) -> None:
        valor = contestacao.valor_centavos
        resta = cobranca.valor_centavos - cobranca.estornado_centavos
        motivo = (
            f"contestação {contestacao.provedor_contestacao_id} perdida: {valor} centavos "
            f"voltaram ao cliente ({cobranca.id})"
        )
        if valor > resta:
            contexto.eventos_webhook.marcar_revisao(
                bruto, f"{motivo}; não foi lançado: só restavam {resta} centavos na cobrança"
            )
            return
        try:
            novos = self._planejar(
                contexto,
                cobranca.pedido_id,
                lambda livro: estornar_pedido(
                    livro,
                    cobranca.pedido_id,
                    valor,
                    f"contest/{contestacao.provedor_contestacao_id}",
                    contexto.agora(),
                    bruto.evento_id,
                ),
            )
            if novos:
                contexto.ledger.lancar_varios(novos)
        except LedgerErro as erro:
            contexto.eventos_webhook.marcar_revisao(bruto, f"{motivo}; não foi lançado: {erro}")
            return
        devolvido = cobranca.estornado_centavos + valor
        situacao = (
            EstadoCobranca.DEVOLVIDA if devolvido >= cobranca.valor_centavos else cobranca.status
        )
        depois = replace(cobranca, estornado_centavos=devolvido, status=situacao)
        self.cobrancas.salvar(depois)
        self._devolver_moedas(contexto, depois)

    def _repasse_falhou(
        self, evento: EventoProvedor, contexto: Contexto, bruto: EventoWebhook
    ) -> None:
        """`transfer.reversed` / `payout.failed`: o dinheiro não chegou ao profissional.

        O espelho não muda sozinho (o que já foi liberado continua liberado até o financeiro
        decidir): o evento fica em revisão, com o motivo do provedor e o repasse achado.
        """
        repasses = contexto.repasses
        repasse = repasses.por_transferencia(evento.objeto_id) if evento.objeto_id else None
        if repasse is None:
            repasse = repasses.obter(evento.metadados.get("repasse_id", ""))
        dados = bruto.payload.get("data")
        objeto = dados.get("object") if isinstance(dados, dict) else {}
        objeto = objeto if isinstance(objeto, dict) else {}
        causa = str(objeto.get("failure_message") or objeto.get("failure_code") or "sem motivo")
        causa = causa.rstrip(". ")
        onde = (
            f"repasse {repasse.id} do pedido {repasse.pedido_id}"
            if repasse is not None
            else "sem repasse correspondente"
        )
        contexto.eventos_webhook.marcar_revisao(
            bruto, f"repasse falhou ({bruto.tipo}): {causa}; {onde}"
        )

    def _devolver_pagamento_orfao(self, cobranca: CobrancaLocal) -> None:
        """Pagou depois de o pedido cancelar/expirar: o dinheiro volta, sem passar pelo ledger."""
        self.provedor.estornar(cobranca.id, None, f"orfao/{cobranca.id}")
        self.cobrancas.salvar(replace(cobranca, status=EstadoCobranca.DEVOLVIDA))

    # --- depois de uma transição de estado ------------------------------------------------

    def _apos_transicao(
        self, antes: Pedido, depois: Pedido, acao: Acao, contexto: Contexto
    ) -> None:
        if depois.estado is Estado.CONCLUIDO and acao in (
            Acao.CONFIRMAR_CONCLUSAO,
            Acao.ENCERRAR_DISPUTA_POR_ACORDO,
        ):
            self.aplicar_dinheiro(
                contexto,
                depois,
                operacao="conclusao",
                devolver_ao_cliente=0,
                repartir=True,
                gatilho="confirmacao_cliente",
            )
        elif depois.estado is Estado.CANCELADO and acao is Acao.CANCELAR:
            for c in self.cobrancas.do_pedido(depois.id):
                if c.status in (EstadoCobranca.AGUARDANDO, EstadoCobranca.FALHOU):
                    self.cobrancas.salvar(replace(c, status=EstadoCobranca.CANCELADA))
            retido = contexto.ledger.saldo_da_conta(CUSTODIA, depois.id)
            if retido > 0:
                self.aplicar_dinheiro(
                    contexto,
                    depois,
                    operacao="cancelamento",
                    devolver_ao_cliente=retido,
                    repartir=False,
                    gatilho="confirmacao_cliente",
                )

    # --- dinheiro ------------------------------------------------------------------------------

    def _servico_da_cobranca(self, contexto: Contexto, cobranca: CobrancaLocal) -> int:
        """O valor do serviço dentro da cobrança: o guardado nela, ou o do contrato/aditivo.
        Nunca passa do valor cobrado (o resto é taxa e custo de parcelamento)."""
        if cobranca.servico_centavos is not None:
            servico = cobranca.servico_centavos
        elif cobranca.aditivo_id:
            aditivo = self.aditivos.obter(cobranca.aditivo_id)
            servico = aditivo.valor_centavos if aditivo else cobranca.valor_centavos
        else:
            contrato = contexto.contratos.obter_do_pedido(cobranca.pedido_id)
            servico = contrato.valor_centavos if contrato else cobranca.valor_centavos
        return min(servico, cobranca.valor_centavos)

    def aplicar_dinheiro(
        self,
        contexto: Contexto,
        pedido: Pedido,
        *,
        operacao: str,
        devolver_ao_cliente: int,
        repartir: bool,
        gatilho: str = "decisao_disputa",
    ) -> None:
        """Devolve `devolver_ao_cliente` ao cliente e/ou reparte o que resta na custódia.

        `operacao` identifica a operação de forma estável (ex.: `conclusao`, `disputa`): a chave
        de idempotência sai dela, então repetir a chamada nunca duplica nada.

        Ordem (A7): 1) valida tudo no ledger e nas cobranças, sem gravar; 2) numa transação grava
        a INTENÇÃO (ledger, ordens de estorno, repasse); 3) só depois do commit chama o provedor,
        com a chave da ordem. Se o ledger falha, nada saiu; se o provedor falha, a ordem fica
        pendente e `reenviar_estornos` completa.
        """
        chave = f"din/{pedido.id}/{operacao}"
        ja_feito = any(
            i.chave.startswith(f"{chave}/") for i in contexto.ledger.lancamentos(pedido.id)
        )
        if not ja_feito:
            self._registrar_intencao(
                contexto, pedido, chave, devolver_ao_cliente, repartir, gatilho
            )
        contexto.depois_do_commit(lambda: self.reenviar_estornos(pedido.id))

    def _registrar_intencao(
        self,
        contexto: Contexto,
        pedido: Pedido,
        chave: str,
        devolver_ao_cliente: int,
        repartir: bool,
        gatilho: str,
    ) -> None:
        agora = contexto.agora()
        profissional = pedido.profissional_id or ""

        def operacao(livro: Livro) -> None:
            if devolver_ao_cliente > 0:
                estornar_pedido(livro, pedido.id, devolver_ao_cliente, f"{chave}/est", agora)
            restante = livro.saldo(CUSTODIA, pedido.id)
            if repartir and restante > 0:
                repartir_custodia(livro, pedido.id, profissional, 0, f"{chave}/rep", agora)

        novos = self._planejar(contexto, pedido.id, operacao)
        ordens = self._ordens_de_estorno(pedido.id, devolver_ao_cliente, chave, agora)
        with contexto.transacao():
            if novos:
                contexto.ledger.lancar_varios(novos)  # a intenção entra no ledger primeiro
            for cobranca, ordem in ordens:
                self.cobrancas.salvar(cobranca)
                self.ordens.salvar(ordem)
                self._devolver_moedas(contexto, cobranca)
            if repartir:
                repasse = repasse_dos_lancamentos(
                    pedido.id, profissional, novos, gatilho, f"{chave}/repasse"
                )
                if repasse is not None:
                    contexto.repasses.criar(repasse)

    def _devolver_moedas(self, contexto: Contexto, cobranca: CobrancaLocal) -> None:
        """Estorno TOTAL da cobrança devolve as moedas que ela usou (parcial não devolve)."""
        if cobranca.moedas_usadas <= 0 or cobranca.estornado_centavos < cobranca.valor_centavos:
            return
        pedido = contexto.pedidos.obter(cobranca.pedido_id)
        if pedido is None:
            return
        devolver_uso_moedas(
            contexto.moedas,
            usuario_id=pedido.cliente_id,
            cobranca_id=cobranca.id,
            pedido_id=cobranca.pedido_id,
            moedas=cobranca.moedas_usadas,
            agora=contexto.agora(),
        )

    def _ordens_de_estorno(
        self, pedido_id: str, valor: int, chave: str, agora
    ) -> list[tuple[CobrancaLocal, OrdemEstorno]]:
        """Divide o valor a devolver entre as cobranças pagas (a mais nova primeiro), sem gravar."""
        if valor <= 0:
            return []
        falta = valor
        saida: list[tuple[CobrancaLocal, OrdemEstorno]] = []
        pagas = [c for c in self.cobrancas.do_pedido(pedido_id) if c.status is EstadoCobranca.PAGA]
        for cobranca in reversed(pagas):  # aditivo antes do principal
            parte = min(falta, cobranca.valor_centavos - cobranca.estornado_centavos)
            if parte <= 0:
                continue
            ordem = OrdemEstorno(f"{chave}/{cobranca.id}", pedido_id, cobranca.id, parte, agora)
            atualizada = replace(cobranca, estornado_centavos=cobranca.estornado_centavos + parte)
            saida.append((atualizada, ordem))
            falta -= parte
            if falta == 0:
                return saida
        raise ErroFluxo("Não há pagamento confirmado suficiente para devolver.")

    def reenviar_estornos(self, pedido_id: str | None = None) -> int:
        """Manda ao provedor as ordens de estorno pendentes (a chave da ordem é a idempotência
        dele). Falha do provedor não perde nada: a ordem continua pendente. Serve também de
        rotina de reconciliação. Devolve quantas foram confirmadas."""
        confirmadas = 0
        for ordem in self.ordens.pendentes(pedido_id):
            try:
                feito = self.provedor.estornar(ordem.cobranca_id, ordem.valor_centavos, ordem.chave)
            except Exception:  # noqa: BLE001, S112 - qualquer falha deixa a ordem pendente
                continue
            self.ordens.salvar(replace(ordem, estado="enviada", provedor_estorno_id=feito.id))
            confirmadas += 1
        return confirmadas

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
