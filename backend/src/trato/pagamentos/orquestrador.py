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
import logging
import threading
import uuid
from collections.abc import Callable, Sequence
from contextlib import nullcontext
from dataclasses import dataclass, replace
from datetime import datetime
from functools import partial

from trato.api.avisos import avisar_partes
from trato.api.contexto import Contexto
from trato.api.exclusividades import encerrar_na_contratacao
from trato.api.liberacao import relato_de_seguranca
from trato.api.moedas import (
    chave_reserva,
    confirmar_reserva_desconto,
    debitar_uso_moedas,
    devolver_reserva_desconto,
    devolver_uso_moedas,
    reabrir_reserva_desconto,
    reservar_desconto,
    situacao_reserva,
)
from trato.api.repositorios import Contrato, EventoWebhook
from trato.api.validade import (
    OrcamentoVencido,
    momento_da_confirmacao,
    orcamento_vencido,
)
from trato.api.webhook_pagamento import EventoForaDeOrdem  # a rota do webhook responde 409
from trato.disputas import Disputa, Resultado
from trato.financeiro.contestacoes import (
    Contestacao,
    StatusContestacao,
    ler_disputa_stripe,
    mesclar,
)
from trato.financeiro.extrato_profissional import reais
from trato.financeiro.ledger import (
    CUSTODIA,
    SUFIXO_PARCELAMENTO,
    LedgerErro,
    Livro,
    custo_parcelamento_em_aberto,
    estornar_material,
    estornar_pedido,
    liberar,
    reembolso_total_com_custo,
    registrar_cobranca,
    repartir_custodia,
    separar_custo_parcelamento,
)
from trato.financeiro.repasses import repasse_dos_lancamentos
from trato.notificacoes.eventos import Evento
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
    EstornoProvedor,
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


# Em memória não há trava de linha: este cadeado faz o papel dela no aditivo.
_TRAVA_DO_ADITIVO = threading.RLock()


@dataclass(frozen=True)
class PlanoEstornoMaterial:
    retido_centavos: int  # sai do que ainda não foi liberado
    liberado_centavos: int  # vira dívida do profissional (compensação)
    custo_centavos: int  # custo do parcelamento proporcional
    partes: tuple[tuple[str, int], ...]  # (cobrança, valor da ordem de estorno)

    @property
    def total_centavos(self) -> int:
        return self.retido_centavos + self.liberado_centavos + self.custo_centavos


class ErroFluxo(Exception):
    """Pedido de pagamento que não vale agora. `status` é o HTTP que a rota devolve."""

    def __init__(self, mensagem: str, status: int = 409) -> None:
        super().__init__(mensagem)
        self.status = status


_SISTEMA = Ator(Papel.SISTEMA, "webhook")

# Ações que cancelam o pedido devolvendo ao cliente TUDO o que está retido, com o nome estável da
# operação (entra na chave de idempotência do estorno). Termos 7.7: ausência do profissional
# devolve o valor inteiro, como o cancelamento.
META_EXECUCAO = "execucao_imediata"  # Termos 7.3: caixa marcada pelo cliente nesta cobrança
_CANCELAM_COM_REEMBOLSO = {
    Acao.CANCELAR: "cancelamento",
    Acao.REGISTRAR_AUSENCIA: "ausencia",
    Acao.CANCELAR_ARREPENDIMENTO: "arrependimento",
    Acao.CANCELAR_PESSOA_DIFERENTE: "pessoa_diferente",
    Acao.CANCELAR_MEDIDA_CONTA: "medida_conta",  # Termos 20.6
}


def _aditivo_pago_a_tempo(pedido: Pedido, confirmado_em: datetime) -> bool:
    """Termos 6.8: pago com o serviço em andamento, ou antes do check-out (aviso atrasado) e
    com a confirmação ainda aberta, onde o valor ainda entra na repartição."""
    if pedido.estado is Estado.EM_ANDAMENTO:
        return True
    return (
        pedido.estado is Estado.EM_CONFIRMACAO
        and pedido.check_out_em is not None
        and confirmado_em <= pedido.check_out_em
    )


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
        self._contexto: Contexto | None = None  # `ligar` preenche (revisões e contestações)

    # --- ligação ao contexto da API ------------------------------------------------------

    def ligar(self, contexto: Contexto) -> None:
        """Registra os manipuladores de webhook e o gancho de transição no contexto."""
        self._contexto = contexto
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
        execucao_imediata: bool = False,
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
        contrato = None
        if aditivo_id is None:  # Termos 6.3: vencido não ganha cobrança (nem reaproveita)
            contrato = contexto.contratos.obter_do_pedido(pedido.id)
            if contrato is not None and orcamento_vencido(
                contexto, contrato.orcamento_id, contexto.agora()
            ):
                raise OrcamentoVencido
        total = self.total_a_cobrar(contexto, pedido, servico_centavos, aditivo_id, parcelas)
        for antiga in antigas:
            if antiga.status is EstadoCobranca.AGUARDANDO and not antiga.contrato_encerrado:
                reserva_ativa = (
                    antiga.moedas_usadas <= 0
                    or situacao_reserva(contexto.moedas, cobranca_id=antiga.id) != "devolvida"
                )
                if (
                    reserva_ativa
                    and antiga.meio is meio
                    and antiga.parcelas == parcelas
                    and antiga.valor_centavos == total.cobrado_centavos
                    and (antiga.cupom_codigo or None) == cupom_norm
                    and antiga.moedas_usadas == moedas
                    and self._escolheu_execucao(antiga.id) == execucao_imediata
                ):
                    return antiga
                self.cobrancas.salvar(replace(antiga, status=EstadoCobranca.CANCELADA))
                self._liberar_reserva(contexto, antiga)
                # Substituída não pode continuar pagável (melhor esforço; se pagar, volta).
                contexto.depois_do_commit(partial(self._cancelar_no_provedor, antiga.id))
        # A chave leva o que define a cobrança (meio, valor, parcelas, cliente, cupom): o Stripe
        # recusa a MESMA chave com parâmetros diferentes ("Keys for idempotent requests can only be
        # used with the same parameters").
        # Só o Pix COM moedas reservadas vence junto com a reserva (reserva_minutos); sem moedas
        # nada muda (vale o padrão do provedor).
        expira_pix = (
            contexto.moedas.config().reserva_minutos * 60
            if moedas > 0 and meio is MeioPagamento.PIX
            else None
        )
        assinatura = hashlib.sha256(
            f"{meio.value}|{total.cobrado_centavos}|{parcelas}|{cliente_externo or ''}|"
            f"{cupom_norm or ''}|{moedas}|{expira_pix or ''}"
            f"{'|execucao' if execucao_imediata else ''}"
            # Contrato novo no mesmo pedido nunca recebe do provedor a cobrança do antigo.
            f"{'|' + contrato.orcamento_id if contrato else ''}".encode()
        ).hexdigest()[:10]
        chave = f"cob/{pedido.id}/{aditivo_id or 'principal'}/{len(antigas) + 1}/{assinatura}"
        metadados = {"pedido_id": pedido.id}
        if aditivo_id:
            metadados["aditivo_id"] = aditivo_id
        if cupom_norm:
            metadados["cupom"] = cupom_norm
        if moedas:
            metadados["moedas"] = str(moedas)
        if execucao_imediata:
            metadados[META_EXECUCAO] = "1"
        criada = self.provedor.criar_cobranca(
            valor_centavos=total.cobrado_centavos,
            meio=meio,
            chave_idempotencia=chave,
            metadados=metadados,
            parcelas=parcelas,
            cliente_externo=cliente_externo,
            **({"expira_em_segundos": expira_pix} if expira_pix is not None else {}),
        )
        # Reserva ATÔMICA (orçamento do mês e do dia, teto do cliente e saldo livre) com a cobrança
        # como chave. Só agora o id dela existe. Se negar, levanta `DescontoMoedasIndisponivel`:
        # quem chama refaz a cobrança sem moedas (a cobrança criada aqui nunca foi salva nem
        # entregue ao cliente: fica sem pagar no provedor e expira lá).
        if moedas > 0:
            reservar_desconto(
                contexto.moedas,
                cobranca_id=criada.id,
                moedas=moedas,
                usuario_id=pedido.cliente_id,
                agora=contexto.agora(),
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
        try:
            self._gravar_cobranca(contexto, pedido, local, contrato)
        except Exception:
            if moedas > 0:  # a cobrança não foi gravada: a reserva volta
                devolver_reserva_desconto(contexto.moedas, cobranca_id=criada.id)
            raise
        return local

    def _gravar_cobranca(
        self,
        contexto: Contexto,
        pedido: Pedido,
        cobranca: CobrancaLocal,
        contrato: Contrato | None,
    ) -> None:
        """Grava a cobrança principal com o pedido travado, só se o contrato dela ainda for o
        vigente: o prazo de pagamento pode vencer enquanto o provedor responde."""
        if contrato is None:
            self.cobrancas.salvar(cobranca)
            return
        try:
            with contexto.transacao():
                travar = getattr(contexto.pedidos, "travar", None)
                if travar is not None:
                    travar(pedido.id)
                atual = contexto.contratos.obter_do_pedido(pedido.id)
                agora_no = contexto.pedidos.obter(pedido.id)
                if (
                    atual is None
                    or atual.orcamento_id != contrato.orcamento_id
                    or agora_no is None
                    or (
                        agora_no.estado is not pedido.estado
                        and agora_no.estado in (Estado.ABERTO, Estado.CANCELADO)
                    )
                ):
                    raise ErroFluxo("O prazo deste pagamento acabou. Aceite um orçamento de novo.")
                self.cobrancas.salvar(cobranca)
        except ErroFluxo:
            self._cancelar_no_provedor(cobranca.id)  # nunca foi entregue ao cliente
            raise

    def reservas_pendentes_do_pedido(self, pedido_id: str) -> set[str]:
        """Chaves de reserva das cobranças com moedas ainda sem pagar deste pedido.

        A simulação e a nova cobrança não as contam contra o cliente: elas serão
        reaproveitadas ou trocadas (e a troca devolve a reserva antes de reservar de novo)."""
        return {
            chave_reserva(c.id)
            for c in self.cobrancas.do_pedido(pedido_id)
            if c.status is EstadoCobranca.AGUARDANDO and c.moedas_usadas > 0
        }

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
        travar = getattr(contexto.pedidos, "travar", None)
        # Uma transação só: o banco exige o aditivo aprovado antes de aceitar a cobrança dele, e
        # se a cobrança falhar a aprovação volta junto (o cliente pode tentar de novo). O estado
        # do aditivo é lido DEPOIS da trava: duas aprovações não criam duas cobranças.
        with _TRAVA_DO_ADITIVO if travar is None else nullcontext(), contexto.transacao():
            if travar is not None:  # check-out ao mesmo tempo: quem chega depois vê o estado
                travar(pedido.id)
            aditivo = self.aditivos.obter(aditivo_id)
            if aditivo is None or not _mesmo_id(aditivo.pedido_id, pedido.id):
                raise ErroFluxo("Aditivo não encontrado.", 404)
            if aditivo.estado is not EstadoAditivo.PROPOSTO:
                raise ErroFluxo("Este aditivo já foi aprovado.")
            atual = contexto.pedidos.obter(pedido.id)
            if atual is None or atual.estado is not Estado.EM_ANDAMENTO:
                raise ErroFluxo("Só dá para aprovar aditivo com o serviço em andamento.")
            aprovado = replace(aditivo, estado=EstadoAditivo.APROVADO, aprovado_em=contexto.agora())
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
        travar = getattr(contexto.pedidos, "travar", None)
        with _TRAVA_DO_ADITIVO if travar is None else nullcontext(), contexto.transacao():
            if travar is not None:  # a mesma fila da aprovação
                travar(pedido.id)
            aditivo = self.aditivos.obter(aditivo_id)
            if aditivo is None or not _mesmo_id(aditivo.pedido_id, pedido.id):
                raise ErroFluxo("Aditivo não encontrado.", 404)
            if aditivo.estado is not EstadoAditivo.PROPOSTO:
                raise ErroFluxo("Este aditivo já foi decidido.")
            recusado = replace(aditivo, estado=EstadoAditivo.RECUSADO)
            self.aditivos.salvar(recusado)
        return recusado

    def _escolheu_execucao(self, cobranca_id: str) -> bool | None:
        """O que a cobrança pendente levou (guardado no provedor). None: não deu para saber, e
        então ela não é reaproveitada."""
        try:
            return self.provedor.consultar_cobranca(cobranca_id).metadados.get(META_EXECUCAO) == "1"
        except Exception:  # noqa: BLE001 - provedor fora: cria outra com a escolha atual
            return None

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
        # A trava do pedido põe este pagamento e um cancelamento em fila: sem ela o valor poderia
        # entrar em custódia de um pedido que acabou de ser cancelado.
        travar = getattr(contexto.pedidos, "travar", None)
        if travar is not None:
            travar(cobranca.pedido_id)
            cobranca = self.cobrancas.obter(cobranca.id) or cobranca
            if cobranca.status in (EstadoCobranca.PAGA, EstadoCobranca.DEVOLVIDA):
                return
        if cobranca.contrato_encerrado:
            # O contrato é o DESTA cobrança, nunca o que o pedido tem agora: pagamento atrasado
            # do contrato que caiu não contrata o novo. Volta inteiro e o financeiro vê.
            self._devolver_pagamento_orfao(cobranca)
            contexto.eventos_webhook.marcar_revisao(
                bruto,
                f"pagamento de contrato cancelado por falta de pagamento no prazo "
                f"({cobranca.id}): devolvido por inteiro",
            )
            return
        pedido = contexto.pedidos.obter(cobranca.pedido_id)

        if cobranca.aditivo_id:
            aditivo = self.aditivos.obter(cobranca.aditivo_id)
            if (
                aditivo is None
                or aditivo.estado is EstadoAditivo.PROPOSTO
                or pedido is None
                or pedido.estado is Estado.CANCELADO
            ):
                return self._devolver_pagamento_orfao(cobranca)
            # Um aditivo se paga uma vez. "Já pago" sai das cobranças (no banco, pago e
            # aprovado são o mesmo status do aditivo), lidas com o pedido travado.
            outra_do_aditivo = any(
                c.status is EstadoCobranca.PAGA
                and c.id != cobranca.id
                and c.aditivo_id
                and _mesmo_id(c.aditivo_id, cobranca.aditivo_id)
                for c in self.cobrancas.do_pedido(cobranca.pedido_id)
            )
            if aditivo.estado is EstadoAditivo.RECUSADO or outra_do_aditivo:
                return self._devolver_aditivo_repetido(contexto, cobranca, bruto)
            if not _aditivo_pago_a_tempo(pedido, momento_da_confirmacao(evento.bruto, agora)):
                self._devolver_pagamento_orfao(cobranca)
                contexto.eventos_webhook.marcar_revisao(
                    bruto,
                    f"aditivo pago fora da execução do serviço (Termos 6.8) ({cobranca.id}): "
                    "devolvido por inteiro",
                )
                return
            # Última barreira, no banco (20261127185000): grava antes de tocar no livro. Se
            # outro pagamento do aditivo já vale, este volta; o evento conclui, sem reenvio.
            gravar = getattr(self.cobrancas, "confirmar_de_aditivo", None)
            paga = replace(cobranca, status=EstadoCobranca.PAGA, pago_em=agora)
            if gravar is not None and not gravar(paga):
                return self._devolver_aditivo_repetido(contexto, cobranca, bruto)
            self.aditivos.salvar(replace(aditivo, estado=EstadoAditivo.PAGO))
            self._avisar_aditivo_pago(contexto, cobranca, aditivo.id)
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
                # Termos 5.2 e 6.3: confirmado depois da validade não contrata; volta inteiro.
                contrato = contexto.contratos.obter_do_pedido(pedido.id)
                if contrato is not None and orcamento_vencido(
                    contexto, contrato.orcamento_id, momento_da_confirmacao(evento.bruto, agora)
                ):
                    return self._devolver_pagamento_orfao(cobranca)
                transicao = estados.transicionar(
                    pedido,
                    Acao.CONFIRMAR_PAGAMENTO,
                    _SISTEMA,
                    agora,
                    ProvaPagamento(cobranca.id),
                )
                gravado = contexto.pedidos.salvar(transicao.pedido, transicao.evento)
                # Contratação (13.6) e o pedido expresso de execução (7.3), que é a escolha
                # feita NESTA cobrança paga: tudo na mesma transação do pedido.
                encerrar_na_contratacao(contexto, gravado.id, gravado.profissional_id)
                if evento.metadados.get(META_EXECUCAO) == "1":
                    contexto.cancelamentos.registrar_consentimento(gravado.id, agora)
                # Avisos (cliente e profissional). Não repete o gancho do dinheiro: este caminho
                # já lança a cobrança logo abaixo. Falha de aviso nunca derruba o webhook.
                for gancho in contexto.apos_transicao:
                    if gancho == self._apos_transicao:
                        continue
                    try:
                        gancho(pedido, gravado, Acao.CONFIRMAR_PAGAMENTO, contexto)
                    except Exception:  # noqa: BLE001 - aviso é secundário
                        logging.getLogger("trato.pagamentos").exception(
                            "Gancho pós-pagamento falhou"
                        )

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
            self._moedas_do_pagamento(contexto, cobranca, pedido, agora, bruto)
        if cobranca.cupom_codigo:
            confirmar_uso_cupom(
                contexto,
                cobranca.cupom_codigo,
                usuario_id=pedido.cliente_id if pedido is not None else None,
                cobranca_id=cobranca.id,
                pedido_id=cobranca.pedido_id,
                desconto_centavos=cobranca.desconto_centavos,
                confirmado_em=agora,
                forcar_limite_usuario=True,  # desconto já dado: o uso nunca se perde
            )

    def _devolver_aditivo_repetido(
        self, contexto: Contexto, cobranca: CobrancaLocal, bruto: EventoWebhook
    ) -> None:
        """Devolve por inteiro (chave `orfao/<cobrança>`: no provedor, uma vez só) e marca
        para a equipe conferir."""
        logging.getLogger("trato.pagamentos").warning(
            "Pagamento repetido ou de aditivo recusado devolvido (%s)", cobranca.id
        )
        self._devolver_pagamento_orfao(cobranca)
        contexto.eventos_webhook.marcar_revisao(
            bruto,
            f"segunda cobrança de aditivo pago, ou aditivo recusado ({cobranca.id}): "
            "devolvido por inteiro",
        )

    @staticmethod
    def _avisar_aditivo_pago(contexto: Contexto, cobranca: CobrancaLocal, aditivo_id: str) -> None:
        """Avisa o profissional (uma vez por aditivo). Aviso é secundário: nunca derruba o
        webhook nem toca no dinheiro."""
        try:
            notificador = contexto.extras.get("notificador") if contexto.extras else None
            pedido = contexto.pedidos.obter(cobranca.pedido_id)
            if notificador is None or pedido is None or not pedido.profissional_id:
                return
            notificador.notificar(
                Evento.ADITIVO_PAGO,
                pedido.profissional_id,
                chave=f"aditivo-pago:{aditivo_id}",
                pedido_id=pedido.id,
            )
        except Exception:  # noqa: BLE001 - aviso é secundário
            logging.getLogger("trato.pagamentos").exception("Aviso de aditivo pago falhou")

    def _moedas_do_pagamento(
        self,
        contexto: Contexto,
        cobranca: CobrancaLocal,
        pedido: Pedido,
        agora: datetime,
        bruto: EventoWebhook,
    ) -> None:
        """Pagamento confirmado com moedas: debita o 'uso' e só DEPOIS confirma a reserva.

        Ordem: débito primeiro (idempotente por `uso:<cobrança>`), confirmação depois. Se a
        confirmação falhar no meio, a reserva continua 'reservada' e a expiração a recolhe; as
        moedas já saíram, então nunca há moeda de graça. Rede de segurança (webhook tardio): se a
        reserva não está 'reservada'/'confirmada' (expirou ou nunca existiu), tenta reservar de novo
        a mesma cobrança; se não couber (a função do banco não reabre reserva 'devolvida'), NÃO
        debita em silêncio: o evento vai para revisão com alerta e o pagamento segue normal (o
        cliente pagou o valor com desconto; o financeiro decide).
        """
        situacao = situacao_reserva(contexto.moedas, cobranca_id=cobranca.id)
        chave_confirmacao = cobranca.id
        if situacao not in ("reservada", "confirmada"):
            reaberta = situacao != "indisponivel" and reabrir_reserva_desconto(
                contexto.moedas,
                cobranca_id=cobranca.id,
                moedas=cobranca.moedas_usadas,
                usuario_id=pedido.cliente_id,
                agora=agora,
            )
            if not reaberta and situacao == "devolvida":
                chave_reabertura = f"reabertura:{cobranca.id}"
                sit_reabertura = situacao_reserva(contexto.moedas, cobranca_id=chave_reabertura)
                if sit_reabertura in ("reservada", "confirmada"):
                    reaberta = True
                    chave_confirmacao = chave_reabertura
                elif sit_reabertura != "indisponivel":
                    reaberta = reabrir_reserva_desconto(
                        contexto.moedas,
                        cobranca_id=chave_reabertura,
                        moedas=cobranca.moedas_usadas,
                        usuario_id=pedido.cliente_id,
                        agora=agora,
                    )
                    if reaberta:
                        chave_confirmacao = chave_reabertura
            if not reaberta:
                contexto.eventos_webhook.marcar_revisao(
                    bruto,
                    f"pagamento com desconto de {cobranca.moedas_usadas} moedas sem reserva válida "
                    f"({cobranca.id}; reserva: {situacao or 'inexistente'}): moedas NÃO debitadas",
                )
                return
        debitar_uso_moedas(
            contexto.moedas,
            usuario_id=pedido.cliente_id,
            cobranca_id=cobranca.id,
            pedido_id=cobranca.pedido_id,
            moedas=cobranca.moedas_usadas,
            agora=agora,
        )
        confirmar_reserva_desconto(contexto.moedas, cobranca_id=chave_confirmacao)

    def _pagamento_falhou(
        self, evento: EventoProvedor, contexto: Contexto, bruto: EventoWebhook
    ) -> None:
        cobranca = self.cobrancas.obter(evento.cobranca_id or "")
        # Falha que chega depois do pagamento (fora de ordem) não desfaz nada.
        if cobranca is not None and cobranca.status is EstadoCobranca.AGUARDANDO:
            self.cobrancas.salvar(replace(cobranca, status=EstadoCobranca.FALHOU))
            self._liberar_reserva(contexto, cobranca)  # só na 1ª vez: depois ela já não aguarda
            if cobranca.moedas_usadas > 0:
                try:
                    self.provedor.cancelar_cobranca(cobranca.id)
                except Exception:  # noqa: BLE001 - melhor esforço; cobrança já marcada FALHOU
                    logging.getLogger("trato.pagamentos").warning(
                        "cancelar cobrança %s no provedor após falha falhou",
                        cobranca.id,
                        exc_info=True,
                    )

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
        # Mesma fila do pagamento: o aviso que chega antes de a devolução ser gravada espera.
        travar = getattr(contexto.pedidos, "travar", None)
        if travar is not None:
            travar(cobranca.pedido_id)
            cobranca = self.cobrancas.obter(cobranca.id) or cobranca
        if cobranca.status is EstadoCobranca.DEVOLVIDA:
            return  # tudo já voltou: nada mais sai do livro por esta cobrança
        if cobranca.status is not EstadoCobranca.PAGA:
            return self._estorno_fora_do_livro(cobranca, total, contexto, bruto)
        por_fora = total - cobranca.estornado_centavos
        if por_fora <= 0:
            return  # o que o Trato mandou devolver: nada a fazer
        pedido = contexto.pedidos.obter(cobranca.pedido_id)
        motivo = f"reembolso de {por_fora} centavos feito por fora do Trato ({cobranca.id})"
        if pedido is None:
            contexto.eventos_webhook.marcar_revisao(bruto, motivo)
            return
        self._avisar_estorno(pedido.id, f"fora:{cobranca.id}:{total}", por_fora)
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

    def _estorno_fora_do_livro(
        self, cobranca: CobrancaLocal, total: int, contexto: Contexto, bruto: EventoWebhook
    ) -> None:
        """Estorno de cobrança que nunca entrou no livro (órfã ainda não gravada, trocada ou sem
        pagamento processado). Nada sai da custódia: ela é de OUTRA cobrança."""
        if total < cobranca.valor_centavos:
            # Parte devolvida antes de o pagamento ser tratado: o provedor reenvia depois.
            raise EventoForaDeOrdem("Estorno parcial antes de o pagamento ser processado.")
        nosso = any(
            e.chave == f"orfao/{cobranca.id}"
            for e in self.provedor.estornos_da_cobranca(cobranca.id)
        )
        self._marcar_devolvida(contexto, cobranca)
        if not nosso:
            contexto.eventos_webhook.marcar_revisao(
                bruto,
                f"reembolso de {total} centavos feito por fora do Trato em cobrança que não "
                f"entrou no livro ({cobranca.id}); nada lançado",
            )

    def _marcar_devolvida(self, contexto: Contexto | None, cobranca: CobrancaLocal) -> None:
        self.cobrancas.salvar(
            replace(
                cobranca,
                status=EstadoCobranca.DEVOLVIDA,
                estornado_centavos=cobranca.valor_centavos,
            )
        )
        if contexto is not None:
            self._liberar_reserva(contexto, cobranca)

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
        if relato_de_seguranca(contexto, pedido.id):
            contexto.eventos_webhook.marcar_revisao(
                bruto, f"repasse liberado com relato de segurança aberto no pedido {pedido.id}"
            )
        agora = contexto.agora()
        try:
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
        except LedgerErro as erro:
            # Ex.: parte do valor já voltou ao cliente ou já foi liberada, e o registro de
            # repasse (imutável) ainda diz o valor antigo. Nada é lançado; 2xx, sem reenvio.
            contexto.eventos_webhook.marcar_revisao(
                bruto, f"repasse {repasse.id} não foi lançado: {erro}"
            )
            return
        gravados = contexto.ledger.lancar_varios(novos) if novos else ()
        if contexto.compensacoes.listar(
            profissional_id=repasse.profissional_id, status="aberta", limite=1
        )[1]:
            # Aqui o provedor JÁ pagou: não dá para descontar antes. O financeiro precisa ver.
            contexto.eventos_webhook.marcar_revisao(
                bruto, f"repasse {repasse.id} pago com compensação aberta: nada foi descontado"
            )
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
        if cobranca.status is EstadoCobranca.DEVOLVIDA and cobranca.aditivo_id:
            # Contestou a cobrança já devolvida enquanto outra do mesmo aditivo vale: risco de
            # o dinheiro voltar duas vezes. A contestação fica gravada e a equipe confere.
            if any(
                c.status is EstadoCobranca.PAGA
                and c.aditivo_id
                and _mesmo_id(c.aditivo_id, cobranca.aditivo_id)
                for c in self.cobrancas.do_pedido(cobranca.pedido_id)
            ):
                contexto.eventos_webhook.marcar_revisao(
                    bruto,
                    f"contestação {atual.provedor_contestacao_id} de cobrança de aditivo já "
                    f"devolvida, com outra paga ({cobranca.id}): conferir",
                )
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
        # Só cobrança que está no livro tem o que estornar (a órfã nunca entrou).
        resta = (
            cobranca.valor_centavos - cobranca.estornado_centavos
            if cobranca.status is EstadoCobranca.PAGA
            else 0
        )
        motivo = (
            f"contestação {contestacao.provedor_contestacao_id} perdida: {valor} centavos "
            f"voltaram ao cliente ({cobranca.id})"
        )
        parte = min(valor, resta)
        if parte <= 0:
            contexto.eventos_webhook.marcar_revisao(
                bruto, f"{motivo}; não foi lançado: não restava nada na cobrança"
            )
            return
        # No ledger entra o que é do serviço (o custo do parcelado não volta por aqui).
        no_ledger = min(parte, self._servico_da_cobranca(contexto, cobranca))
        # O ledger usa o id como está no pedido; o da cobrança vem sem hífen do banco e, usado
        # direto, não acharia nenhum lançamento.
        pedido = contexto.pedidos.obter(cobranca.pedido_id)
        pedido_id = pedido.id if pedido is not None else cobranca.pedido_id
        try:
            novos = self._planejar(
                contexto,
                pedido_id,
                lambda livro: estornar_pedido(
                    livro,
                    pedido_id,
                    no_ledger,
                    f"contest/{contestacao.provedor_contestacao_id}",
                    contexto.agora(),
                    bruto.evento_id,
                ),
            )
            if novos:
                contexto.ledger.lancar_varios(novos)
            if no_ledger != valor:
                contexto.eventos_webhook.marcar_revisao(
                    bruto, f"{motivo}; no ledger entraram {no_ledger} centavos"
                )
        except LedgerErro as erro:
            contexto.eventos_webhook.marcar_revisao(bruto, f"{motivo}; não foi lançado: {erro}")
        # Com ou sem lançamento, o dinheiro voltou ao cliente: a cobrança lembra (Termos 6.11).
        devolvido = cobranca.estornado_centavos + parte
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
        # Grava o quanto voltou: o `charge.refunded` deste estorno não é reembolso por fora.
        self._marcar_devolvida(self._contexto, cobranca)
        self._avisar_estorno(cobranca.pedido_id, f"orfao/{cobranca.id}", cobranca.valor_centavos)

    def _cancelar_no_provedor(self, cobranca_id: str) -> None:
        """Melhor esforço: se falhar e o cliente pagar depois, o pagamento volta como órfão."""
        try:
            self.provedor.cancelar_cobranca(cobranca_id)
        except Exception:  # noqa: BLE001 - a cobrança já está cancelada no Trato
            logging.getLogger("trato.pagamentos").warning(
                "cancelar cobrança %s no provedor falhou", cobranca_id, exc_info=True
            )

    # --- depois de uma transição de estado ------------------------------------------------

    def _apos_transicao(
        self, antes: Pedido, depois: Pedido, acao: Acao, contexto: Contexto
    ) -> None:
        if depois.estado is Estado.CONCLUIDO and acao in (
            Acao.CONFIRMAR_CONCLUSAO,
            Acao.ENCERRAR_DISPUTA_POR_ACORDO,
            Acao.CONCLUIR_POR_PRAZO,  # Termos 5.8: o silêncio do cliente vale como confirmação
        ):
            self.aplicar_dinheiro(
                contexto,
                depois,
                operacao="conclusao",
                devolver_ao_cliente=0,
                repartir=True,
                gatilho="prazo" if acao is Acao.CONCLUIR_POR_PRAZO else "confirmacao_cliente",
            )
        if acao is Acao.FAZER_CHECK_OUT or depois.estado in (
            Estado.CONCLUIDO,
            Estado.RETRABALHO,
        ):  # 6.8: acabada a execução, aditivo sem pagar não é mais cobrado
            self._cancelar_cobrancas_abertas(contexto, depois.id, so_aditivos=True)
        if acao is Acao.EXPIRAR_PAGAMENTO:
            self._cancelar_cobrancas_abertas(contexto, depois.id)
        elif depois.estado is Estado.CANCELADO and (
            acao in _CANCELAM_COM_REEMBOLSO or acao is Acao.CANCELAR_CLIENTE_AUSENTE
        ):
            self._cancelar_cobrancas_abertas(contexto, depois.id)
            if acao is Acao.CANCELAR_CLIENTE_AUSENTE:
                return  # o valor sai da decisão do analista (7.6), com ou sem retenção
            retido = contexto.ledger.saldo_da_conta(CUSTODIA, depois.id)
            # Termos 7.2, 7.4 e 7.7: cancelamento (sempre antes do check-in) e ausência do
            # profissional devolvem o valor pago, com o custo do parcelamento.
            livro = Livro()
            antigos = contexto.ledger.lancamentos(depois.id)
            if antigos:
                livro.lancar_varios(antigos)
            custo = custo_parcelamento_em_aberto(livro, depois.id)
            if retido + custo > 0:
                self.aplicar_dinheiro(
                    contexto,
                    depois,
                    operacao=_CANCELAM_COM_REEMBOLSO[acao],
                    devolver_ao_cliente=retido + custo,
                    repartir=False,
                    gatilho="confirmacao_cliente",
                    incluir_custo=custo > 0,
                )

    def _cancelar_cobrancas_abertas(
        self, contexto: Contexto, pedido_id: str, so_aditivos: bool = False
    ) -> None:
        """Cobranças sem pagar deixam de valer, no Trato já e no provedor depois do commit."""
        for c in self.cobrancas.do_pedido(pedido_id):
            if c.contrato_encerrado or (so_aditivos and not c.aditivo_id):
                continue
            if c.status in (EstadoCobranca.AGUARDANDO, EstadoCobranca.FALHOU):
                self.cobrancas.salvar(replace(c, status=EstadoCobranca.CANCELADA))
                self._liberar_reserva(contexto, c)  # idempotente: FALHOU já devolveu
                contexto.depois_do_commit(partial(self._cancelar_no_provedor, c.id))

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

    def dinheiro_da_disputa(self, contexto: Contexto, pedido: Pedido, disputa: Disputa) -> None:
        """O dinheiro de uma decisão final (Termos 6.10, 6.11 e 8.6): estorno ao cliente com
        ordem ao provedor e, se o pedido conclui, a parte do profissional. Chamado só por
        `api/decisao_disputa.py`, dentro da transação da decisão."""
        divisao, decisao = disputa.divisao, disputa.decisao
        if divisao is None or decisao is None:
            raise ErroFluxo("A disputa ainda não tem decisão final.")
        devolver, com_custo, total = divisao.para_cliente, False, None
        if decisao.resultado is Resultado.REEMBOLSO_TOTAL:  # 6.10: o valor pago, com o parcelado
            total = reembolso_total_com_custo(
                contexto.ledger.lancamentos(pedido.id), pedido.id, pedido.profissional_id
            )
        if total is not None:
            devolver, com_custo = total, True
        elif devolver > 0:
            # 6.11: o que já voltou ao cliente depois de aberta a disputa (emissora ou estorno
            # por fora) conta na parte dele.
            saldos = contexto.ledger.saldos_pedido(pedido.id, pedido.profissional_id)
            sumiu = disputa.valor_congelado - (saldos.retido + saldos.a_liberar)
            pela_emissora = sum(
                c.valor_centavos
                for c in contexto.contestacoes.perdidas_do_pedido(pedido.id)
                if c.encerrada_em is None or c.encerrada_em >= disputa.aberta_em
            )
            devolver = max(0, devolver - max(sumiu, pela_emissora, 0))
        self.aplicar_dinheiro(
            contexto,
            pedido,
            operacao=f"disputa/{int(disputa.aberta_em.timestamp())}",
            devolver_ao_cliente=devolver,
            repartir=pedido.estado is Estado.CONCLUIDO,
            gatilho="decisao_disputa",
            incluir_custo=com_custo,
        )

    def aplicar_dinheiro(
        self,
        contexto: Contexto,
        pedido: Pedido,
        *,
        operacao: str,
        devolver_ao_cliente: int,
        repartir: bool,
        gatilho: str = "decisao_disputa",
        incluir_custo: bool = False,
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
                contexto, pedido, chave, devolver_ao_cliente, repartir, gatilho, incluir_custo
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
        incluir_custo: bool = False,
    ) -> None:
        agora = contexto.agora()
        profissional = pedido.profissional_id or ""
        if devolver_ao_cliente > 0 and contexto.contestacoes.perdidas_do_pedido(pedido.id):
            # Termos 6.11: o que o banco já devolveu na contestação não é estornado de novo.
            sobra = sum(
                c.valor_centavos - c.estornado_centavos
                for c in self.cobrancas.do_pedido(pedido.id)
                if c.status is EstadoCobranca.PAGA
            )
            if sobra < devolver_ao_cliente:
                # Já não é o reembolso inteiro: o custo do parcelado não entra nesta conta.
                incluir_custo = False
                saldos = contexto.ledger.saldos_pedido(pedido.id, pedido.profissional_id)
                devolver_ao_cliente = min(sobra, saldos.retido + saldos.a_liberar)

        def operacao(livro: Livro) -> None:
            if devolver_ao_cliente > 0:
                estornar_pedido(
                    livro,
                    pedido.id,
                    devolver_ao_cliente,
                    f"{chave}/est",
                    agora,
                    incluir_custo=incluir_custo,
                )
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

    # --- material contestado (Termos 6.9) ---------------------------------------------------

    def planejar_estorno_material(
        self, contexto: Contexto, pedido: Pedido, reconhecido: int
    ) -> PlanoEstornoMaterial | None:
        """Quanto sai de onde para devolver `reconhecido`, sem gravar. Chamar com o pedido e o
        contrato travados. `None`: o que foi pago no app (e ainda não voltou) não cobre o valor.

        O custo do parcelamento volta na proporção do que se devolve de cada cobrança (a mais
        nova primeiro), arredondado meio para cima, sem passar do que sobra dela."""
        livro = Livro()
        antigos = contexto.ledger.lancamentos(pedido.id)
        if antigos:
            livro.lancar_varios(antigos)
        saldos = livro.saldos_pedido(pedido.id, pedido.profissional_id)
        retido = min(reconhecido, max(saldos.retido, 0) + max(saldos.a_liberar, 0))
        custo_em_aberto = max(custo_parcelamento_em_aberto(livro, pedido.id), 0)
        falta, custo_total = reconhecido, 0
        partes: list[tuple[str, int]] = []
        pagas = [c for c in self.cobrancas.do_pedido(pedido.id) if c.status is EstadoCobranca.PAGA]
        for cobranca in reversed(pagas):
            entrada = livro.da_chave(f"cob/{cobranca.id}")
            if entrada is None or entrada.credito != CUSTODIA:  # gorjeta ou fora do livro
                continue
            taxa = livro.da_chave(f"cob/{cobranca.id}{SUFIXO_PARCELAMENTO}")
            custo = taxa.valor if taxa else 0
            servico = cobranca.valor_centavos - custo
            sobra = cobranca.valor_centavos - cobranca.estornado_centavos
            if servico <= 0 or sobra <= 0:
                continue
            parte = min(falta, servico, sobra * servico // cobranca.valor_centavos)
            if parte <= 0:
                continue
            parte_custo = min(
                (parte * custo + servico // 2) // servico,
                sobra - parte,
                custo_em_aberto - custo_total,
            )
            partes.append((cobranca.id, parte + parte_custo))
            custo_total += parte_custo
            falta -= parte
            if falta == 0:
                break
        if falta > 0:
            return None
        return PlanoEstornoMaterial(retido, reconhecido - retido, custo_total, tuple(partes))

    def gravar_estorno_material(
        self,
        contexto: Contexto,
        pedido: Pedido,
        plano: PlanoEstornoMaterial,
        chave: str,
    ) -> None:
        """Livro (parte retida e custo) e ordens de estorno, na transação em curso: quem chama
        confirma no banco DEPOIS, e qualquer recusa desfaz tudo. O provedor só é chamado
        depois do commit."""
        agora = contexto.agora()
        novos = self._planejar(
            contexto,
            pedido.id,
            lambda livro: estornar_material(
                livro,
                pedido.id,
                pedido.profissional_id or "",
                plano.retido_centavos,
                plano.custo_centavos,
                f"{chave}/est",
                agora,
            ),
        )
        with contexto.transacao():
            if novos:
                contexto.ledger.lancar_varios(novos)
            for cobranca_id, valor in plano.partes:
                cobranca = self.cobrancas.obter(cobranca_id)
                if cobranca is None:
                    raise ErroFluxo("Cobrança do estorno não encontrada.")
                atualizada = replace(
                    cobranca, estornado_centavos=cobranca.estornado_centavos + valor
                )
                self.cobrancas.salvar(atualizada)
                self.ordens.salvar(
                    OrdemEstorno(f"{chave}/{cobranca_id}", pedido.id, cobranca_id, valor, agora)
                )
                self._devolver_moedas(contexto, atualizada)
        contexto.depois_do_commit(lambda: self.reenviar_estornos(pedido.id))

    def ordenar_estorno_compensado(
        self, contexto: Contexto, pedido_id: str, valor: int, divida_id: str
    ) -> None:
        """Ordem de estorno da dívida de compensação (o livro já foi lançado pelo banco, na
        transação em curso). O provedor só é chamado depois do commit, com a chave da ordem."""
        ordens = self._ordens_de_estorno(pedido_id, valor, f"comp/{divida_id}", contexto.agora())
        with contexto.transacao():
            for cobranca, ordem in ordens:
                self.cobrancas.salvar(cobranca)
                self.ordens.salvar(ordem)
                self._devolver_moedas(contexto, cobranca)
        contexto.depois_do_commit(lambda: self.reenviar_estornos(pedido_id))

    def _devolver_moedas(self, contexto: Contexto, cobranca: CobrancaLocal) -> None:
        """Devolve as moedas na proporção do que já voltou ao cliente (Termos 13.8). A base é o
        valor do serviço (o custo do parcelado não conta). Devolvido tudo, volta também a
        reserva."""
        if cobranca.moedas_usadas <= 0 or cobranca.estornado_centavos <= 0:
            return
        pedido = contexto.pedidos.obter(cobranca.pedido_id)
        if pedido is None:
            return
        base = self._servico_da_cobranca(contexto, cobranca)
        devolver_uso_moedas(
            contexto.moedas,
            usuario_id=pedido.cliente_id,
            cobranca_id=cobranca.id,
            pedido_id=cobranca.pedido_id,
            moedas=cobranca.moedas_usadas,
            agora=contexto.agora(),
            devolvido_centavos=cobranca.estornado_centavos,
            base_centavos=base,
        )
        if cobranca.estornado_centavos >= base:
            self._liberar_reserva(contexto, cobranca)  # idempotente por status da reserva

    def _liberar_reserva(self, contexto: Contexto, cobranca: CobrancaLocal) -> None:
        """Devolve a reserva de moedas desta cobrança (mês, dia e saldo) pelo valor GRAVADO nela,
        inclusive a reaberta por pagamento tardio.

        Estorno total, falha, cancelamento e troca de cobrança passam por aqui; a segunda chamada
        não faz nada."""
        if cobranca.moedas_usadas > 0:
            devolver_reserva_desconto(contexto.moedas, cobranca_id=cobranca.id)
            devolver_reserva_desconto(contexto.moedas, cobranca_id=f"reabertura:{cobranca.id}")

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

    def reenviar_estornos(
        self, pedido_id: str | None = None, *, criadas_ate: datetime | None = None
    ) -> int:
        """Manda ao provedor as ordens de estorno pendentes, CONSULTANDO antes o que ele já tem:
        resposta perdida ou chave de idempotência vencida nunca viram um segundo estorno. Na
        dúvida a ordem continua pendente e vai para revisão. `criadas_ate` deixa de fora as
        ordens novas demais (o envio logo após o commit pode estar em andamento). Falha não perde
        nada: a ordem continua pendente. Devolve quantas foram confirmadas."""
        confirmadas = 0
        for ordem in self.ordens.pendentes(pedido_id):
            if criadas_ate is not None and ordem.criada_em > criadas_ate:
                continue
            try:
                confirmadas += self._enviar_ordem(ordem)
            except Exception:  # noqa: BLE001 - qualquer falha deixa a ordem pendente
                logging.getLogger("trato.pagamentos").warning(
                    "ordem de estorno %s continua pendente", ordem.chave, exc_info=True
                )
        return confirmadas

    def _enviar_ordem(self, ordem: OrdemEstorno) -> int:
        no_provedor = self.provedor.estornos_da_cobranca(ordem.cobranca_id)
        desta = [e for e in no_provedor if e.chave == ordem.chave]
        if desta:
            feito = desta[0]
            if len(desta) > 1 or feito.falhou or feito.valor_centavos != ordem.valor_centavos:
                self._revisar_ordem(ordem, "o estorno no provedor falhou, repetiu ou diverge")
                return 0
        else:
            duvida = self._duvida_antes_de_enviar(ordem, no_provedor)
            if duvida:
                self._revisar_ordem(ordem, duvida)
                return 0
            feito = self.provedor.estornar(ordem.cobranca_id, ordem.valor_centavos, ordem.chave)
        self.ordens.salvar(
            replace(
                ordem,
                estado="enviada",
                provedor_estorno_id=feito.id,
                enviada_em=self._contexto.agora() if self._contexto else None,
            )
        )
        self._avisar_estorno(ordem.pedido_id, ordem.chave, ordem.valor_centavos)
        return 1

    def _avisar_estorno(self, pedido_id: str, chave: str, valor_centavos: int) -> None:
        """Termos 15.2: o cliente é avisado de cada estorno, uma vez, depois de gravado."""
        contexto = self._contexto
        if contexto is None:
            return

        def avisar() -> None:
            try:
                pedido = contexto.pedidos.obter(pedido_id)
            except Exception:  # noqa: BLE001 - aviso é secundário
                logging.getLogger("trato.pagamentos").exception("Aviso de estorno falhou")
                return
            if pedido is None:
                return
            avisar_partes(
                contexto,
                Evento.ESTORNO_SOLICITADO,
                (pedido.cliente_id,),
                pedido_id=pedido.id,
                chave=f"estorno:{chave}",
                corpo=f"Pedimos ao parceiro de pagamento o estorno de {reais(valor_centavos)}. "
                "O prazo para aparecer depende da forma de pagamento.",
            )

        contexto.depois_do_commit(avisar)

    def _duvida_antes_de_enviar(
        self, ordem: OrdemEstorno, no_provedor: Sequence[EstornoProvedor]
    ) -> str | None:
        validos = [e for e in no_provedor if not e.falhou]
        conhecidos = {o.provedor_estorno_id for o in self.ordens.do_pedido(ordem.pedido_id)}
        if any(e.chave is None and e.id not in conhecidos for e in validos):
            return "há estorno no provedor que não é de nenhuma ordem (feito por fora ou antigo)"
        cobranca = self.cobrancas.obter(ordem.cobranca_id)
        if cobranca is None:
            return "cobrança da ordem não encontrada"
        contestado = 0
        if self._contexto is not None:
            contestado = sum(
                c.valor_centavos
                for c in self._contexto.contestacoes.perdidas_do_pedido(ordem.pedido_id)
                if c.cobranca_id == ordem.cobranca_id
            )
        devolvido = sum(e.valor_centavos for e in validos)
        if devolvido + contestado + ordem.valor_centavos > cobranca.valor_centavos:
            return "passaria do valor da cobrança (estorno ou contestação já devolveu)"
        return None

    def _revisar_ordem(self, ordem: OrdemEstorno, motivo: str) -> None:
        """Guarda a ordem na fila de revisão do financeiro (uma vez), junto dos eventos do
        provedor. A ordem segue pendente e é conferida de novo nos próximos ciclos."""
        logging.getLogger("trato.pagamentos").warning(
            "ordem de estorno %s para revisão: %s", ordem.chave, motivo
        )
        contexto = self._contexto
        if contexto is None:
            return
        evento_id = f"trato-revisao:{ordem.chave}"
        if any(e.evento_id == evento_id for e, _ in contexto.eventos_webhook.em_revisao()):
            return
        evento = EventoWebhook(
            "stripe",
            evento_id,
            "trato.ordem_estorno.revisao",
            {  # no formato de um evento do provedor: o painel acha o pedido
                "data": {
                    "object": {
                        "amount": ordem.valor_centavos,
                        "metadata": {
                            "pedido_id": ordem.pedido_id,
                            "cobranca_id": ordem.cobranca_id,
                        },
                    }
                }
            },
            contexto.agora(),
        )
        with contexto.transacao():
            contexto.eventos_webhook.registrar(evento)
            contexto.eventos_webhook.marcar_revisao(evento, f"{motivo} ({ordem.chave})")

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
