"""De onde vêm os pedidos monitorados (`Fonte`) e como cada ação é executada (`Executor`).

`FonteContexto` e `ExecutorContexto` usam o `Contexto` da API (memória ou Postgres). As regras
em si estão em `trato.rotinas.regras` e não são reescritas aqui.
"""

from __future__ import annotations

import logging
import threading
import uuid
from collections.abc import Callable
from contextlib import nullcontext
from dataclasses import fields, replace
from datetime import date, datetime, timedelta
from typing import Any, Protocol

from trato.api.contexto import Contexto
from trato.api.liberacao import Fatos, fatos_da_liberacao
from trato.api.medidas import desbloqueada_em
from trato.disputas import Estado as EstadoDisputa
from trato.financeiro.ledger import Lancamento, TipoLancamento, a_liberar, liberado
from trato.financeiro.periodo import BRASILIA
from trato.notificacoes.eventos import Evento
from trato.notificacoes.servico import ServicoNotificacoes
from trato.pagamentos.modelos import EstadoCobranca
from trato.pedidos.estados import Acao, Estado, Pedido, TransicaoInvalida, transicionar
from trato.persistencia.cancelamentos import EM_ANALISE, PROPOSTA
from trato.persistencia.conexao import Banco
from trato.rotinas.regras import (
    SISTEMA,
    AcaoRotina,
    ConfigRotinas,
    DisputaMonitorada,
    Lembrete,
    PedidoMonitorado,
    TipoAcaoRotina,
    planejar_avisos_expiracao,
    regra_de_liberacao,
)

log = logging.getLogger("trato.agendador")
_ENCERRADAS = (EstadoDisputa.DECIDIDA, EstadoDisputa.ACORDO)
_REABREM = (Acao.EXPIRAR_EXCLUSIVIDADE, Acao.EXPIRAR_PAGAMENTO)
# Estas mexem em dinheiro ou no contrato: rodam numa transação, com o pedido travado.
_COM_TRAVA = (Acao.REGISTRAR_AUSENCIA, Acao.CONCLUIR_POR_PRAZO, Acao.EXPIRAR_PAGAMENTO)
# Em memória não há trava de linha: este cadeado faz o papel dela na liberação.
_TRAVA_DA_LIBERACAO = threading.RLock()


class Adiada(Exception):
    """A ação não vale agora: nada foi feito e a chave não é marcada (tenta no próximo ciclo)."""


Carga = tuple[list[PedidoMonitorado], ConfigRotinas, frozenset[date]]


class Fonte(Protocol):
    def carregar(self, agora: datetime) -> Carga: ...


class Executor(Protocol):
    def executar(self, acao: AcaoRotina, agora: datetime) -> None:
        """Faz a ação. Precisa ser idempotente (rodar de novo não pode duplicar efeito)."""


def config_rotinas_da_api(
    contexto: Contexto, complemento: ConfigRotinas | None = None
) -> ConfigRotinas:
    """Monta a `ConfigRotinas` com o que a configuração publicada já tem.

    Liberação só com `prazo_liberacao_dias` publicado. `complemento` sobrepõe campo a campo
    (usado para o que a configuração não tem, como o limite de valor); campo `None` deixa a
    rotina daquele item desligada, como manda `trato.rotinas`.
    """
    api = contexto.config.carregar()
    prazos, disputas = api.prazos_pedido, api.disputas
    base = ConfigRotinas(
        validade_pedido=prazos.receber_orcamentos,
        prazo_pagamento=prazos.pagamento,
        tolerancia_comparecimento=prazos.tolerancia_comparecimento,
        prazo_confirmacao_cliente=prazos.confirmacao_cliente,
        prazo_resposta_disputa=None,
        prazo_decisao_disputa_dias_uteis=disputas.prazo_decisao_dias_uteis,
        janela_congelamento_repasse=None,
    )
    liberacao, congelamento = regra_de_liberacao(
        api.prazo_liberacao_dias, disputas.prazo_congelar_repasse_horas
    )
    resposta = timedelta(hours=disputas.prazo_resposta_horas)
    antes_de_confirmar = timedelta(hours=api.lembrete_confirmacao_antecedencia_horas)
    antes_de_responder = timedelta(hours=api.lembrete_resposta_disputa_antecedencia_horas)
    avisar_confirmacao = None
    if prazos.confirmacao_cliente is not None and antes_de_confirmar > timedelta(0):
        # Antecedência maior que a janela: o lembrete sai na metade dela.
        avisar_confirmacao = max(
            prazos.confirmacao_cliente - antes_de_confirmar, prazos.confirmacao_cliente / 2
        )
    base = replace(
        base,
        prazo_resposta_disputa=resposta,
        janela_congelamento_repasse=congelamento,
        prazo_liberacao=liberacao,
        liberacao_espera_congelamento=True,
        lembrete_confirmacao_apos=avisar_confirmacao,
        lembrete_resposta_disputa_antecedencia=(
            min(antes_de_responder, resposta / 2) if antes_de_responder > timedelta(0) else None
        ),
    )
    if complemento is None:
        return base
    extras = {
        c.name: getattr(complemento, c.name)
        for c in fields(complemento)
        if getattr(complemento, c.name) not in (None, False)
    }
    return replace(base, **extras)


def ids_ativos_memoria(contexto: Contexto) -> Callable[[], list[str]]:
    return lambda: sorted(getattr(contexto.pedidos, "_pedidos", {}))


def ids_ativos_postgres(banco: Banco, dias_concluidos: int = 60) -> Callable[[], list[str]]:
    """Pedidos em andamento + os concluídos há pouco (que ainda podem ter saldo a liberar)."""

    def ids() -> list[str]:
        with banco.transacao() as con:
            retidos = ""
            valores: list[Any] = [dias_concluidos]
            if con.execute(
                "select to_regclass('public.cancelamentos_pedido') is not null as tem"
            ).fetchone()["tem"]:  # cancelados com retenção de ausência a liberar
                retidos = (
                    " or (p.status = 'cancelado' and p.atualizado_em > now() - "
                    "make_interval(days => %s) and exists (select 1 from "
                    "public.cancelamentos_pedido k where k.pedido_id = p.id "
                    "and k.tipo = 'cliente_ausente' and k.status = 'confirmado' "
                    "and k.retencao_valor_centavos > 0))"
                )
                valores.append(dias_concluidos)
            linhas = con.execute(
                "select p.id from public.pedidos p where (p.status <> 'cancelado' and "  # noqa: S608
                "(p.status <> 'concluido' or p.atualizado_em > now() - "
                f"make_interval(days => %s))){retidos} order by p.criado_em",
                valores,
            ).fetchall()
        return [str(l["id"]) for l in linhas]  # noqa: E741

    return ids


def _aberto_desde(contexto: Contexto, pedido: Pedido) -> Pedido:
    """Pedido reaberto (fim da exclusividade ou do prazo de pagamento): a validade conta da
    reabertura."""
    if pedido.estado is not Estado.ABERTO:
        return pedido
    reaberturas = [e.em for e in contexto.pedidos.eventos(pedido.id) if e.acao in _REABREM]
    return replace(pedido, aberto_em=max(reaberturas)) if reaberturas else pedido


class FonteContexto:
    def __init__(
        self,
        contexto: Contexto,
        ids_ativos: Callable[[], list[str]],
        complemento: ConfigRotinas | None = None,
    ) -> None:
        self._c = contexto
        self._ids = ids_ativos
        self._complemento = complemento

    def carregar(self, agora: datetime) -> Carga:
        c = self._c
        itens = []
        for pid in self._ids():
            pedido = c.pedidos.obter(pid)
            if pedido is None:
                continue
            contrato = c.contratos.obter_do_pedido(pid)
            disputa = c.disputas.obter(pid)
            saldo = (
                c.ledger.saldos_pedido(pid, pedido.profissional_id).a_liberar
                if pedido.profissional_id
                else 0
            )
            fatos = Fatos()
            aberta = bool(disputa and disputa.estado not in _ENCERRADAS)
            if pedido.estado in (Estado.CONCLUIDO, Estado.CANCELADO) and saldo > 0:
                fatos = fatos_da_liberacao(c, pedido)
                aberta = fatos.disputa_aberta if pedido.estado is Estado.CONCLUIDO else aberta
            itens.append(
                PedidoMonitorado(
                    _aberto_desde(c, pedido),
                    valor_servico_centavos=contrato.valor_centavos if contrato else 0,
                    orcamentos_recebidos=len(c.orcamentos.do_pedido(pid)),
                    saldo_a_liberar_centavos=saldo,
                    disputa=DisputaMonitorada(disputa.aberta_em, disputa.respondida_em is not None)
                    if disputa
                    else None,
                    disputa_aberta=aberta,
                    confirmado=fatos.confirmado,
                    contestar_ate=fatos.contestar_ate,
                    retencao_em=fatos.retencao_em,
                )
            )
        feriados = frozenset(c.config.carregar().disputas.feriados)
        return itens, config_rotinas_da_api(c, self._complemento), feriados


_LEMBRETE_PARA_EVENTO = {
    Lembrete.CONFIRMACAO_PENDENTE: (Evento.CONCLUSAO_PARA_CONFIRMAR, "cliente"),
    Lembrete.RESPOSTA_DISPUTA: (Evento.LEMBRETE_RESPOSTA_DISPUTA, "profissional"),
    Lembrete.ADITIVO_AGUARDANDO: (Evento.ADITIVO_PENDENTE, "cliente"),
    # DECISAO_DISPUTA é da equipe (sem destinatário individual): fica para o painel admin.
}


class ExecutorContexto:
    def __init__(
        self,
        contexto: Contexto,
        notificacoes: ServicoNotificacoes | None = None,
        cobrancas: Any = None,
        provedor: Any = None,
        pagamento: Any = None,
        estorno_idade_minima: timedelta = timedelta(seconds=120),
    ) -> None:
        self._pagamento = pagamento  # `ServicoPagamento` (reenvio de estornos)
        self._estorno_idade_minima = estorno_idade_minima
        self._c = contexto
        self._notif = notificacoes
        self._cobrancas = cobrancas  # repositório de cobranças (expiração de reservas)
        self._provedor = provedor  # para cancelar no provedor a cobrança expirada

    def _pedido_estornado_ou_cancelado(self, pedido_id: str) -> bool:
        """Pedido cancelado, ou com cobrança devolvida por inteiro (estorno total)."""
        pedido = self._c.pedidos.obter(pedido_id)
        if pedido is not None and pedido.estado is Estado.CANCELADO:
            return True
        if self._cobrancas is None:
            return False
        return any(
            c.status is EstadoCobranca.DEVOLVIDA and not c.contrato_encerrado
            for c in self._cobrancas.do_pedido(pedido_id)
        )

    def expirar_reservas_moedas(self, agora: datetime) -> int:
        """Expira as reservas de desconto vencidas e cancela as cobranças pendentes delas.

        Devolve quantas cobranças foram canceladas. Sem repositório de cobranças, não faz nada.
        """
        if self._cobrancas is None:
            return 0
        from trato.api.moedas import expirar_reservas_moedas

        return expirar_reservas_moedas(self._c.moedas, self._cobrancas, agora, self._provedor)

    def expirar_exclusividades(self, agora: datetime) -> int:
        """Expira ofertas sem resposta (estorna) e exclusividades de 48h vencidas (reabre).

        Idempotente: só as linhas recém-expiradas pela função SQL/memória geram avisos, cada
        um com chave única por `(exclusividade_id, motivo)`. Falha ao notificar é logada e
        nunca desfaz o estorno nem impede os demais avisos.
        """
        expiradas = self._c.exclusividades.expirar(agora)
        do_cliente = self._c.exclusividades.expirar_cliente(agora)
        for item in do_cliente if self._notif is not None else []:
            for destino in (item.cliente_id, item.profissional_id):
                try:
                    self._notif.notificar(
                        Evento.EXCLUSIVIDADE_CLIENTE_FIM,
                        destino,
                        chave=f"{item.exclusividade_id}:fim",
                        pedido_id=item.pedido_id,
                        dados={"exclusividade_id": item.exclusividade_id},
                    )
                except Exception:  # noqa: BLE001 - aviso é secundário
                    log.exception("Aviso do fim da exclusividade falhou")
        if self._notif is not None:
            for item in expiradas:
                avisos = planejar_avisos_expiracao(
                    item.exclusividade_id,
                    item.motivo,
                    item.profissional_id,
                    item.cliente_id,
                    item.pedido_id,
                )
                for aviso in avisos:
                    try:
                        self._notif.notificar(
                            Evento(aviso.evento),
                            aviso.destinatario_id,
                            chave=aviso.chave,
                            pedido_id=aviso.pedido_id,
                            dados={"exclusividade_id": item.exclusividade_id},
                        )
                    except Exception:  # noqa: BLE001 - aviso é secundário ao estorno/reabertura
                        log.exception(
                            "Aviso de expiração de exclusividade falhou (%s)",
                            item.exclusividade_id,
                        )
        return len(expiradas) + len(do_cliente)

    def encerrar_medidas(self, agora: datetime) -> int:
        """Medida de conta com prazo vencido devolve a conta (Termos 20)."""
        from trato.api.cautela import avisar_cautela_atrasada
        from trato.api.medidas import encerrar_vencidas

        try:  # 9.6: o aviso do prazo não pode derrubar a rotina das medidas
            avisar_cautela_atrasada(self._c, self._notif, agora)
        except Exception:  # noqa: BLE001
            log.exception("Rotina do prazo de cautela falhou")
        return encerrar_vencidas(self._c, agora)

    def liberar_bonus_moedas(self, agora: datetime) -> int:
        """Libera (ou cancela) os bônus de moedas pendentes vencidos. Devolve quantos liberou.

        A disputa do pedido decide: aberta segura o bônus; decidida sem nada para o cliente
        (perdida) cancela; sem disputa ou ganha libera. Idempotente pela chave do lançamento.
        """
        from trato.api.moedas import (
            TIPO_BONUS_PROFISSIONAL,
            PendenteMoeda,
            liberar_bonus_pendentes,
        )

        def situacao(pend: PendenteMoeda) -> str:
            if not pend.pedido_id:
                return "nenhuma"
            try:
                chave = uuid.UUID(pend.pedido_id).hex  # o pedido é guardado como hex
            except ValueError:
                chave = pend.pedido_id
            do_profissional = pend.tipo_lancamento == TIPO_BONUS_PROFISSIONAL
            if do_profissional and self._pedido_estornado_ou_cancelado(chave):
                return "estornado"  # nada a liberar: o serviço foi desfeito
            disputa = self._c.disputas.obter(chave)
            if disputa is None:
                return "nenhuma"
            if disputa.estado not in _ENCERRADAS:
                return "aberta"
            divisao = disputa.divisao
            if divisao is None or divisao.retido != 0:
                return "nenhuma"
            # Perdeu quem avaliou: o cliente não recebeu nada (bônus do cliente) ou o
            # profissional não recebeu nada, p.ex. reembolso total (bônus do profissional).
            perdeu = (
                divisao.para_profissional == 0 if do_profissional else divisao.para_cliente == 0
            )
            return "perdida" if perdeu else "nenhuma"

        return liberar_bonus_pendentes(
            self._c.moedas, agora=agora, situacao_disputa=situacao
        ).liberados

    def liberar_indicacoes(self, agora: datetime) -> int:
        """Libera (ou cancela) as indicações do Indique e Ganhe cujo prazo venceu.

        Cancela se o pedido gatilho teve disputa aberta ou decidida em favor do cliente, estorno
        ou cancelamento. Idempotente (chave por indicação e lado). Devolve quantas liberou.
        """
        from trato.api.indicacoes import liberar_vencidas

        c = self._c

        def situacao(pedido_id: str) -> str:
            if self._pedido_estornado_ou_cancelado(pedido_id):
                return "estornado"
            pedido = c.pedidos.obter(pedido_id)
            if pedido is not None and pedido.profissional_id:
                if c.ledger.saldos_pedido(pedido_id, pedido.profissional_id).cliente_pagou <= 0:
                    return "estornado"  # tudo devolvido ao cliente
            disputa = c.disputas.obter(pedido_id)
            if disputa is None:
                return "nenhuma"
            if disputa.estado not in _ENCERRADAS:
                return "aberta"
            divisao = disputa.divisao
            if divisao is not None and divisao.para_cliente > 0:
                return "procedente"
            return "nenhuma"

        def avisar(ind: Any, usuario_id: str, quantidade: int, lado: str) -> None:
            if self._notif is None:
                return
            try:
                self._notif.notificar(
                    Evento.INDICACAO_LIBERADA,
                    usuario_id,
                    chave=f"indicacao:{ind.id}:{lado}",
                    corpo=f"Você ganhou {quantidade} Tratinhos pela indicação.",
                )
            except Exception:  # noqa: BLE001 - aviso é secundário ao crédito
                log.exception("Aviso de indicação liberada falhou (%s)", ind.id)

        return liberar_vencidas(c, agora, situacao, avisar)

    def gerar_visitas_recorrentes(self, agora: datetime) -> int:
        """Gera a próxima visita (e o pedido dela) das séries recorrentes ativas.

        Não cobra nada: o cliente aprova o orçamento e paga a visita. Sem pagamento até o limite
        configurado, a visita expira e a agenda do profissional é liberada. Devolve quantas
        visitas gerou.
        """
        from trato.api.recorrencias import (
            SEM_REMOTO,
            cancelar_pedido_da_visita,
            fechar_visitas,
            gerar_visitas,
        )

        c = self._c

        def avisar(rec: Any, visita: Any) -> None:
            if self._notif is None:
                return
            try:
                self._notif.notificar(
                    Evento.RECORRENCIA_VISITA,
                    rec.cliente_id,
                    chave=f"recorrencia:{rec.id}:visita:{visita.id}",
                    pedido_id=visita.pedido_id,
                )
            except Exception:  # noqa: BLE001 - aviso é secundário à geração
                log.exception("Aviso de visita recorrente falhou (%s)", visita.id)

        def avisar_remota(rec: Any) -> None:
            if self._notif is None:
                return
            for destino in (rec.cliente_id, rec.profissional_id):
                try:
                    self._notif.notificar(
                        Evento.RECORRENCIA_ATUALIZADA,
                        destino,
                        chave=f"recorrencia:{rec.id}:remota",
                        corpo=f"O serviço recorrente foi pausado e não gera novas visitas. "
                        f"{SEM_REMOTO} As visitas já criadas continuam.",
                        dados={"recorrencia_id": rec.id},
                    )
                except Exception:  # noqa: BLE001 - aviso é secundário
                    log.exception("Aviso de série remota falhou (%s)", rec.id)

        geradas = gerar_visitas(c, agora, avisar, avisar_remota)
        _, expiradas = fechar_visitas(c, agora, lambda r, p: cancelar_pedido_da_visita(c, r, p))
        if expiradas:
            log.info("Visitas recorrentes expiradas por falta de pagamento: %s", expiradas)
        return geradas

    def reenviar_estornos(self, agora: datetime) -> int:
        """Termos 6.10: confere no provedor e reenvia as ordens pendentes."""
        if self._pagamento is None:
            return 0
        return self._pagamento.reenviar_estornos(criadas_ate=agora - self._estorno_idade_minima)

    def executar(self, acao: AcaoRotina, agora: datetime) -> None:
        if acao.tipo is TipoAcaoRotina.TRANSICIONAR:
            self._transicionar(acao, agora)
        elif acao.tipo is TipoAcaoRotina.LIBERAR_SALDO:
            self._liberar(acao, agora)
        elif acao.tipo is TipoAcaoRotina.LEMBRETE:
            self._lembrar(acao)

    def _transicionar(self, acao: AcaoRotina, agora: datetime) -> None:
        if acao.acao not in _COM_TRAVA:
            self._aplicar_transicao(acao, agora)
            return
        # Mexe em dinheiro (estorno ao cliente ou repasse): o pedido e o lançamento gravam juntos
        # ou nada grava (o próximo ciclo tenta de novo); o provedor só é chamado depois do
        # commit. A trava vem ANTES da leitura: uma chegada registrada pelo profissional ou uma
        # remarcação gravada no meio do caminho é vista e a ausência deixa de valer.
        reaberta: tuple[Pedido, datetime, datetime] | None = None
        with self._c.transacao():
            travar = getattr(self._c.pedidos, "travar", None)
            if travar is not None:
                travar(acao.pedido_id)
            if acao.acao is Acao.EXPIRAR_PAGAMENTO:
                self._expirar_pagamento(acao, agora)
                return
            if acao.acao is Acao.CONCLUIR_POR_PRAZO:
                disputa = self._c.disputas.obter(acao.pedido_id)
                if disputa is not None and disputa.estado not in _ENCERRADAS:
                    return  # Termos 5.8: com relato aberto nada conclui sozinho
                pedido = self._c.pedidos.obter(acao.pedido_id)
                # Termos 20.6 e 20.10: o silêncio de quem está bloqueado não confirma. A leitura
                # trava a conta até o fim da transação (bloqueio e rotina não se cruzam).
                if pedido is not None and self._c.medidas.conta_bloqueada_travada(
                    pedido.cliente_id
                ):
                    raise Adiada("cliente_bloqueado")  # sem marcar: tenta no próximo ciclo
                if pedido is not None:
                    janela = self._janela_reaberta(pedido, agora)
                    if janela is not None and agora < janela[1]:
                        reaberta = (pedido, *janela)
            if reaberta is None and acao.acao is Acao.REGISTRAR_AUSENCIA:
                pedido = self._c.pedidos.obter(acao.pedido_id)
                if pedido is not None and pedido.janela is not None:
                    if self._c.ausencias.obter(pedido.id, pedido.janela.inicio) is not None:
                        return  # Termos 7.6: o profissional registrou a chegada
            if reaberta is None:
                self._aplicar_transicao(acao, agora)
        if reaberta is not None:
            self._avisar_janela_reaberta(*reaberta)  # fora da transação: nada foi gravado
            raise Adiada("janela_reaberta")

    def _janela_reaberta(self, pedido: Pedido, agora: datetime) -> tuple[datetime, datetime] | None:
        """Termos 20.6 e 20.10: se a conta do cliente esteve bloqueada depois do check-out, a
        janela de confirmação recomeça no desbloqueio. Devolve `(desbloqueio, fim)`."""
        prazo = self._c.config.carregar().prazos_pedido.confirmacao_cliente
        if pedido.estado is not Estado.EM_CONFIRMACAO or not pedido.check_out_em or not prazo:
            return None
        if pedido.check_out_sem_codigo:  # nunca conclui por prazo: não há janela a reabrir
            return None
        desde = desbloqueada_em(self._c, pedido.cliente_id, pedido.check_out_em, agora)
        return (desde, desde + prazo) if desde is not None else None

    def _avisar_janela_reaberta(self, pedido: Pedido, desde: datetime, fim: datetime) -> None:
        if self._notif is None:
            return
        quando = fim.astimezone(BRASILIA)
        try:
            self._notif.notificar(
                Evento.CONCLUSAO_PARA_CONFIRMAR,
                pedido.cliente_id,
                chave=f"{pedido.id}:janela_reaberta:{int(desde.timestamp())}",
                pedido_id=pedido.id,
                corpo=f"Sua conta foi liberada e o prazo para confirmar recomeçou: termina em "
                f"{quando:%d/%m às %H:%M}. Confirme o serviço ou relate um problema.",
            )
        except Exception:  # noqa: BLE001 - aviso é secundário
            log.exception("Aviso da janela reaberta falhou (%s)", pedido.id)

    def _expirar_pagamento(self, acao: AcaoRotina, agora: datetime) -> None:
        """Termos 5.2 e 6.3 (pedido já travado): reabre o pedido e, na mesma transação, encerra
        o contrato sem dinheiro, para o cliente poder aceitar outro orçamento. Contrato com
        dinheiro nunca é cancelado: nada muda e o caso fica para a equipe."""
        c = self._c
        com_dinheiro = bool(c.ledger.lancamentos(acao.pedido_id)) or (
            self._cobrancas is not None
            and any(
                x.status is EstadoCobranca.PAGA and not x.contrato_encerrado
                for x in self._cobrancas.do_pedido(acao.pedido_id)
            )
        )
        if com_dinheiro:
            raise Adiada("pagamento_recebido")
        if not self._aplicar_transicao(acao, agora):
            return
        if c.contratos.encerrar_por_pagamento_expirado(acao.pedido_id) and self._cobrancas:
            self._cobrancas.encerrar_contrato(acao.pedido_id)

    def _aplicar_transicao(self, acao: AcaoRotina, agora: datetime) -> bool:
        c = self._c
        antes = c.pedidos.obter(acao.pedido_id)
        if antes is None or acao.acao is None:
            return False
        base = _aberto_desde(c, antes) if acao.acao is Acao.EXPIRAR_PEDIDO else antes
        try:
            t = transicionar(
                base, acao.acao, SISTEMA, agora, prazos=c.config.carregar().prazos_pedido
            )
            t = replace(t, pedido=replace(t.pedido, aberto_em=antes.aberto_em))
        except TransicaoInvalida:
            return False  # outra instância ou o usuário já mudou o pedido: nada a fazer
        depois = c.pedidos.salvar(t.pedido, t.evento)
        for gancho in c.apos_transicao:
            gancho(antes, depois, acao.acao, c)
        return True

    def _impedimento(self, acao: AcaoRotina, agora: datetime) -> str | None:
        """Por que o saldo não pode sair agora (lido com o pedido travado)."""
        c = self._c
        pedido = c.pedidos.obter(acao.pedido_id)
        if pedido is None or pedido.estado not in (Estado.CONCLUIDO, Estado.CANCELADO):
            return "pedido_nao_concluido"
        if pedido.profissional_id != acao.profissional_id:
            return "profissional_mudou"
        fatos = fatos_da_liberacao(c, pedido)
        if pedido.estado is Estado.CANCELADO:
            if fatos.retencao_em is None:
                return "pedido_cancelado"
            disputa = c.disputas.obter(pedido.id)
            if disputa is not None and disputa.estado not in _ENCERRADAS:
                return "disputa_aberta"
        if fatos.disputa_aberta:
            return "disputa_aberta"
        if fatos.relato:
            return "relato_de_seguranca"  # 8.8 e 9.6: retido até a análise terminar
        if fatos.contestacao_pendente:
            return "decisao_contestada"  # 5.8 e 8.7: o caso ainda corre
        if fatos.prazo_desconhecido or (
            fatos.contestar_ate is not None and agora <= fatos.contestar_ate
        ):
            return "prazo_de_contestacao"
        if c.contestacoes.abertas_do_pedido(pedido.id):
            return "contestacao_de_cartao"
        caso = c.cancelamentos.do_pedido(pedido.id)
        if caso is not None and caso.status in (EM_ANALISE, PROPOSTA):
            return "retencao_em_aberto"
        saldo = c.ledger.saldos_pedido(pedido.id, pedido.profissional_id).a_liberar
        if saldo != acao.valor_centavos:
            return "saldo_mudou"
        if self._liberavel(acao, agora) <= 0:
            return "retencao_por_fraude"  # 20.6: volta sozinha ao reverter ou vencer
        return None

    def _liberavel(self, acao: AcaoRotina, agora: datetime) -> int:
        """Quanto deste saldo pode sair. Com trava por fraude vigente, fica 'a liberar' (somando
        todos os pedidos do profissional) no máximo o limite; o que passa dele sai. A leitura
        trava a linha do profissional até o fim da transação."""
        limite = self._c.medidas.retencao_por_fraude(acao.profissional_id, agora)
        if limite is None:
            return acao.valor_centavos
        total = self._c.ledger.saldo_da_conta(a_liberar(acao.profissional_id))
        return max(0, min(acao.valor_centavos, total - limite))

    def _liberar(self, acao: AcaoRotina, agora: datetime) -> None:
        if not acao.profissional_id or not acao.valor_centavos:
            return
        travar = getattr(self._c.pedidos, "travar", None)
        # Liberação e compensação (8.6) juntas: tudo ou nada, antes de qualquer saque. A trava
        # do pedido vem antes das leituras: disputa aberta no meio do caminho é vista.
        with _TRAVA_DA_LIBERACAO if travar is None else nullcontext(), self._c.transacao():
            if travar is not None:
                travar(acao.pedido_id)
            if any(i.chave == acao.chave for i in self._c.ledger.lancamentos(acao.pedido_id)):
                return  # já liberada (e compensada) nesta mesma chave
            motivo = self._impedimento(acao, agora)
            if motivo is not None:
                raise Adiada(motivo)
            valor = self._liberavel(acao, agora)  # parcial quando o saldo passa do limite retido
            (liberacao,) = self._c.ledger.lancar_varios(
                [
                    Lancamento(
                        acao.chave,
                        acao.pedido_id,
                        TipoLancamento.REPASSE,
                        a_liberar(acao.profissional_id),
                        liberado(acao.profissional_id),
                        valor,
                        agora,
                    )  # fmt: skip
                ]
            )
            self._c.compensacoes.aplicar(acao.pedido_id, f"repasse:{liberacao.id}")

    def _lembrar(self, acao: AcaoRotina) -> None:
        alvo = _LEMBRETE_PARA_EVENTO.get(acao.lembrete) if acao.lembrete else None
        pedido: Pedido | None = self._c.pedidos.obter(acao.pedido_id)
        if alvo is None or pedido is None or self._notif is None:
            return
        evento, quem = alvo
        usuario = pedido.cliente_id if quem == "cliente" else pedido.profissional_id
        corpo = None
        if acao.lembrete is Lembrete.CONFIRMACAO_PENDENTE:
            prazo = self._c.config.carregar().prazos_pedido.confirmacao_cliente
            if pedido.check_out_em and prazo:
                janela = self._janela_reaberta(pedido, self._c.agora())
                limite = janela[1] if janela else pedido.check_out_em + prazo
                fim = limite.astimezone(BRASILIA)
                corpo = (
                    f"A janela de confirmação termina em {fim:%d/%m às %H:%M}. "
                    "Confirme o serviço ou relate um problema."
                )
        if usuario:
            self._notif.notificar(
                evento, usuario, chave=acao.chave, pedido_id=pedido.id, corpo=corpo
            )
