"""Serviço recorrente: série de visitas (semanal, quinzenal ou mensal) de um serviço já concluído.

Decisões aprovadas (docs/decisoes-indicacao-e-recorrencia.md, 23/11/2026):
- nasce de um pedido CONCLUÍDO, por proposta de uma parte e aceite da outra (nunca no 1º pedido);
- NENHUMA cobrança automática: cada visita vira um pedido (com orçamento enviado) que o cliente
  aprova e paga sozinho, como qualquer pedido. O agendador gera a visita
  `antecedencia_geracao_horas`
  antes da data; sem pagamento até `limite_confirmacao_horas` antes, a visita expira e a agenda
  do profissional é liberada, sem punição;
- pular uma visita ou cancelar a série: qualquer parte, a qualquer momento, sem multa;
- reajuste: só o profissional propõe e só vale com o aceite do cliente (a visita usa sempre
  `valor_centavos`; `valor_proposto_centavos` nunca é cobrado antes do aceite).

Tudo em centavos inteiros. Transições de status são condicionais (`de -> para` atômico).
"""

from __future__ import annotations

import calendar
import logging
import threading
import uuid
from collections.abc import Callable
from dataclasses import dataclass, replace
from datetime import datetime, timedelta
from decimal import Decimal
from typing import Any, Protocol

from trato.financeiro import periodo

log = logging.getLogger("trato.recorrencias")

FREQUENCIAS = ("semanal", "quinzenal", "mensal")
ST_PROPOSTA, ST_ATIVA, ST_PAUSADA, ST_CANCELADA = "proposta", "ativa", "pausada", "cancelada"
V_AGENDADA, V_PAGA, V_PULADA, V_EXPIRADA, V_CANCELADA = (
    "agendada",
    "confirmada_paga",
    "pulada",
    "expirada",
    "cancelada",
)


@dataclass(frozen=True)
class ConfigRecorrencia:
    antecedencia_geracao_horas: int = 48  # a visita nasce 48 h antes
    limite_confirmacao_horas: int = 12  # sem pagar até 12 h antes, a visita expira
    valor_maximo_centavos: int = 50_000_000  # R$ 500.000,00, o mesmo teto do orçamento


@dataclass(frozen=True)
class Recorrencia:
    id: str
    cliente_id: str
    profissional_id: str
    pedido_origem_id: str
    categoria_id: str | None
    frequencia: str
    valor_centavos: int
    proxima_visita_em: datetime
    status: str
    proposto_por: str
    criado_em: datetime
    valor_proposto_centavos: int | None = None
    cancelado_por: str | None = None
    cancelado_em: datetime | None = None


@dataclass(frozen=True)
class Visita:
    id: str
    recorrencia_id: str
    data_prevista_em: datetime
    status: str
    criado_em: datetime
    pedido_id: str | None = None
    pulada_por: str | None = None


class JaExisteRecorrencia(Exception):
    """O pedido de origem já tem uma série em andamento (proposta, ativa ou pausada)."""


def somar_frequencia(data: datetime, frequencia: str) -> datetime:
    """A próxima data da série, mantendo a hora local de Brasília (mensal = mesmo dia do mês)."""
    if frequencia == "semanal":
        return data + timedelta(days=7)
    if frequencia == "quinzenal":
        return data + timedelta(days=14)
    local = data.astimezone(periodo.BRASILIA)
    mes0 = local.month  # 1..12
    ano = local.year + mes0 // 12
    mes = mes0 % 12 + 1
    dia = min(local.day, calendar.monthrange(ano, mes)[1])
    return local.replace(year=ano, month=mes, day=dia).astimezone(data.tzinfo)


def proxima_data_futura(data: datetime, frequencia: str, agora: datetime) -> datetime:
    """Ao retomar: a primeira data da série que ainda não passou."""
    while data <= agora:
        data = somar_frequencia(data, frequencia)
    return data


class RepositorioRecorrencias(Protocol):
    def config(self) -> ConfigRecorrencia: ...

    def criar(self, rec: Recorrencia) -> Recorrencia:
        """Levanta `JaExisteRecorrencia` se o pedido de origem já tem série em andamento."""
        ...

    def obter(self, recorrencia_id: str) -> Recorrencia | None: ...

    def do_usuario(self, usuario_id: str) -> list[Recorrencia]:
        """Do cliente ou do profissional, mais recentes primeiro."""
        ...

    def mudar_status(
        self,
        recorrencia_id: str,
        de: tuple[str, ...],
        para: str,
        agora: datetime,
        por: str | None = None,
        proxima_visita_em: datetime | None = None,
    ) -> bool:
        """Transição condicional (só se o status atual estiver em `de`). False = já mudou."""
        ...

    def propor_reajuste(self, recorrencia_id: str, valor_centavos: int) -> bool:
        """Só em série ativa ou pausada e SEM outro reajuste esperando resposta."""
        ...

    def aceitar_reajuste(self, recorrencia_id: str, valor_centavos: int) -> bool:
        """Aceita o reajuste pendente SÓ se `valor_proposto_centavos == valor_centavos`:
        `valor_centavos` da série vira o proposto e a proposta zera (atômico)."""
        ...

    def recusar_reajuste(self, recorrencia_id: str) -> bool: ...

    def avancar(self, recorrencia_id: str, de_data: datetime, para_data: datetime) -> bool:
        """Anda a série SÓ se a próxima visita ainda for `de_data` (idempotente)."""
        ...

    def visitas(self, recorrencia_id: str) -> list[Visita]:
        """Mais recentes primeiro."""
        ...

    def obter_visita(self, visita_id: str) -> Visita | None: ...

    def reservar_visita(
        self, recorrencia_id: str, data: datetime, agora: datetime, status: str = V_AGENDADA
    ) -> Visita | None:
        """Cria a visita da data (único por série e data). None = já existia."""
        ...

    def vincular_pedido(self, visita_id: str, pedido_id: str) -> bool: ...

    def mudar_visita(
        self, visita_id: str, de: tuple[str, ...], para: str, por: str | None = None
    ) -> bool: ...

    def prontas_para_gerar(self, agora: datetime) -> list[Recorrencia]:
        """Séries ativas cuja próxima visita cai dentro da antecedência."""
        ...

    def visitas_abertas(self) -> list[Visita]:
        """Visitas ainda 'agendada' (para confirmar o pagamento ou expirar)."""
        ...

    def profissional_do_pedido_de_visita(self, pedido_id: str) -> str | None:
        """Se o pedido é de uma visita recorrente: o profissional da série; senão None."""
        ...


class RecorrenciasEmMemoria:
    def __init__(self, config: ConfigRecorrencia | None = None) -> None:
        self._config = config or ConfigRecorrencia()
        self._recs: dict[str, Recorrencia] = {}
        self._vis: dict[str, Visita] = {}
        self._trava = threading.Lock()

    def config(self) -> ConfigRecorrencia:
        return self._config

    def salvar_config(self, config: ConfigRecorrencia) -> None:
        self._config = config

    def criar(self, rec: Recorrencia) -> Recorrencia:
        with self._trava:
            if any(
                r.pedido_origem_id == rec.pedido_origem_id and r.status != ST_CANCELADA
                for r in self._recs.values()
            ):
                raise JaExisteRecorrencia
            self._recs[rec.id] = rec
            return rec

    def obter(self, recorrencia_id: str) -> Recorrencia | None:
        return self._recs.get(recorrencia_id)

    def do_usuario(self, usuario_id: str) -> list[Recorrencia]:
        meus = [r for r in self._recs.values() if usuario_id in (r.cliente_id, r.profissional_id)]
        return sorted(meus, key=lambda r: r.criado_em, reverse=True)

    def mudar_status(
        self,
        recorrencia_id: str,
        de: tuple[str, ...],
        para: str,
        agora: datetime,
        por: str | None = None,
        proxima_visita_em: datetime | None = None,
    ) -> bool:
        with self._trava:
            atual = self._recs.get(recorrencia_id)
            if atual is None or atual.status not in de:
                return False
            novo = replace(atual, status=para)
            if para == ST_CANCELADA:
                novo = replace(novo, cancelado_por=por, cancelado_em=agora)
            if proxima_visita_em is not None:
                novo = replace(novo, proxima_visita_em=proxima_visita_em)
            self._recs[recorrencia_id] = novo
            return True

    def _alterar(self, recorrencia_id: str, quando: Callable[[Recorrencia], Recorrencia | None]):
        with self._trava:
            atual = self._recs.get(recorrencia_id)
            novo = quando(atual) if atual is not None else None
            if novo is None:
                return False
            self._recs[recorrencia_id] = novo
            return True

    def propor_reajuste(self, recorrencia_id: str, valor_centavos: int) -> bool:
        return self._alterar(
            recorrencia_id,
            lambda r: (
                replace(r, valor_proposto_centavos=valor_centavos)
                if r.status in (ST_ATIVA, ST_PAUSADA) and r.valor_proposto_centavos is None
                else None
            ),
        )

    def aceitar_reajuste(self, recorrencia_id: str, valor_centavos: int) -> bool:
        return self._alterar(
            recorrencia_id,
            lambda r: (
                replace(r, valor_centavos=r.valor_proposto_centavos, valor_proposto_centavos=None)
                if r.valor_proposto_centavos == valor_centavos
                and r.status in (ST_ATIVA, ST_PAUSADA)
                else None
            ),
        )

    def recusar_reajuste(self, recorrencia_id: str) -> bool:
        return self._alterar(
            recorrencia_id,
            lambda r: (
                replace(r, valor_proposto_centavos=None)
                if r.valor_proposto_centavos is not None
                else None
            ),
        )

    def avancar(self, recorrencia_id: str, de_data: datetime, para_data: datetime) -> bool:
        return self._alterar(
            recorrencia_id,
            lambda r: (
                replace(r, proxima_visita_em=para_data)
                if r.proxima_visita_em == de_data and r.status == ST_ATIVA
                else None
            ),
        )

    def visitas(self, recorrencia_id: str) -> list[Visita]:
        achadas = [v for v in self._vis.values() if v.recorrencia_id == recorrencia_id]
        return sorted(achadas, key=lambda v: v.data_prevista_em, reverse=True)

    def obter_visita(self, visita_id: str) -> Visita | None:
        return self._vis.get(visita_id)

    def reservar_visita(
        self, recorrencia_id: str, data: datetime, agora: datetime, status: str = V_AGENDADA
    ) -> Visita | None:
        with self._trava:
            if any(
                v.recorrencia_id == recorrencia_id and v.data_prevista_em == data
                for v in self._vis.values()
            ):
                return None
            nova = Visita(str(uuid.uuid4()), recorrencia_id, data, status, agora)
            self._vis[nova.id] = nova
            return nova

    def vincular_pedido(self, visita_id: str, pedido_id: str) -> bool:
        with self._trava:
            atual = self._vis.get(visita_id)
            if atual is None:
                return False
            self._vis[visita_id] = replace(atual, pedido_id=pedido_id)
            return True

    def mudar_visita(
        self, visita_id: str, de: tuple[str, ...], para: str, por: str | None = None
    ) -> bool:
        with self._trava:
            atual = self._vis.get(visita_id)
            if atual is None or atual.status not in de:
                return False
            self._vis[visita_id] = replace(
                atual, status=para, pulada_por=por if para == V_PULADA else atual.pulada_por
            )
            return True

    def prontas_para_gerar(self, agora: datetime) -> list[Recorrencia]:
        limite = agora + timedelta(hours=self._config.antecedencia_geracao_horas)
        return [
            r for r in self._recs.values() if r.status == ST_ATIVA and r.proxima_visita_em <= limite
        ]

    def visitas_abertas(self) -> list[Visita]:
        return [v for v in self._vis.values() if v.status == V_AGENDADA]

    def profissional_do_pedido_de_visita(self, pedido_id: str) -> str | None:
        for v in self._vis.values():
            if v.pedido_id == pedido_id:
                serie = self._recs.get(v.recorrencia_id)
                return serie.profissional_id if serie else None
        return None


SEM_REMOTO = (
    "O Trato não aceita serviço remoto: o serviço é feito no imóvel informado no pedido "
    "(Termos 3.7)."
)

# --- Rotinas do agendador -----------------------------------------------------------------


def _pedido_da_visita(contexto: Any, rec: Recorrencia, visita: Visita, agora: datetime) -> str:
    """Cria o pedido da visita e envia o orçamento do profissional (valor da série).

    O cliente aprova (aceita o orçamento) e paga como em qualquer pedido: nada é cobrado aqui.
    """
    from trato.api.repositorios import ItemOrcamento
    from trato.pedidos import estados
    from trato.pedidos.estados import Ator, Papel

    dados = contexto.pedidos.dados_do_pedido(rec.pedido_origem_id)
    pedido = estados.abrir_pedido(uuid.uuid4().hex, Ator(Papel.CLIENTE, rec.cliente_id), agora)
    if dados is not None:
        dia = visita.data_prevista_em.astimezone(periodo.BRASILIA)
        dados = replace(
            dados,
            titulo=f"Visita recorrente: {dados.titulo}"[:120],
            prazo_desejado=dia.date(),
            profissional_convidado_id=rec.profissional_id,
        )
    gravado = contexto.pedidos.salvar(pedido, None, dados)
    contexto.extras.setdefault("pedidos_convidados", {})[gravado.id] = rec.profissional_id
    contexto.orcamentos.enviar(
        pedido_id=gravado.id,
        profissional_id=rec.profissional_id,
        itens=[ItemOrcamento("outro", "Visita recorrente", Decimal(1), rec.valor_centavos)],
        agora=agora,
    )
    return gravado.id


def _partes_aptas(contexto: Any, rec: Recorrencia) -> bool:
    """Profissional ativo e aprovado (perfil de profissional) e cliente ativo."""
    from trato.api.auth import PapelUsuario

    profissional = contexto.usuarios.detalhe(rec.profissional_id)
    cliente = contexto.usuarios.detalhe(rec.cliente_id)
    return (
        profissional is not None
        and profissional.status == "ativo"
        and profissional.papel is PapelUsuario.PROFISSIONAL
        and cliente is not None
        and cliente.status == "ativo"
    )


def origem_remota(contexto: Any, rec: Recorrencia) -> bool:
    origem = contexto.pedidos.obter(rec.pedido_origem_id)
    return origem is not None and origem.remoto


def gerar_visitas(
    contexto: Any,
    agora: datetime,
    avisar: Callable[[Recorrencia, Visita], None] | None = None,
    avisar_remota: Callable[[Recorrencia], None] | None = None,
) -> int:
    """Rotina: cria a visita (e o pedido dela) das séries ativas na antecedência configurada.

    Idempotente: a visita é única por série e data (índice no banco) e a série só anda se a
    próxima data ainda for a mesma. Uma série que falhar não impede as outras.
    """
    repo = contexto.recorrencias
    criadas = 0
    for rec in repo.prontas_para_gerar(agora):
        if origem_remota(contexto, rec):  # Termos 3.7: não nasce visita remota nova
            if repo.mudar_status(rec.id, (ST_ATIVA,), ST_PAUSADA, agora):
                log.warning("Recorrência %s pausada: origem remota", rec.id)
                if avisar_remota is not None:
                    avisar_remota(rec)
            continue
        if not _partes_aptas(contexto, rec):
            # Profissional fora (inativo ou sem aprovação) ou cliente inativo: sem visita nova;
            # a série pausa e quem voltar a ficar apto a retoma pelo app.
            if repo.mudar_status(rec.id, (ST_ATIVA,), ST_PAUSADA, agora):
                log.warning("Recorrência %s pausada: parte inativa ou não aprovada", rec.id)
            continue
        data = rec.proxima_visita_em
        try:
            with contexto.transacao():
                visita = repo.reservar_visita(rec.id, data, agora)
                if visita is None:  # já gerada (ciclo repetido ou outra instância)
                    repo.avancar(rec.id, data, somar_frequencia(data, rec.frequencia))
                    continue
                visita_id = visita.id
                pedido_id = _pedido_da_visita(contexto, rec, visita, agora)
                repo.vincular_pedido(visita_id, pedido_id)
                repo.avancar(rec.id, data, somar_frequencia(data, rec.frequencia))
        except Exception:  # noqa: BLE001 - uma série ruim não derruba as outras
            log.exception("Falha ao gerar a visita da recorrência %s", rec.id)
            continue
        criadas += 1
        if avisar is not None:
            avisar(rec, replace(visita, pedido_id=pedido_id))
    return criadas


def cancelar_pedido_da_visita(contexto: Any, rec: Recorrencia, pedido: Any) -> bool:
    """Libera a agenda: cancela o pedido da visita se ele ainda não foi pago. Nunca levanta."""
    from trato.pedidos import estados
    from trato.pedidos.estados import Acao, Ator, Estado, Papel, ProvaCancelamento

    if pedido.estado not in (Estado.ABERTO, Estado.RESERVADO, Estado.ORCAMENTO_ACEITO):
        return False
    try:
        transicao = estados.transicionar(
            pedido,
            Acao.CANCELAR,
            Ator(Papel.CLIENTE, rec.cliente_id),
            contexto.agora(),
            ProvaCancelamento("Visita do serviço recorrente cancelada."),
            contexto.config.carregar().prazos_pedido,
        )
        contexto.pedidos.salvar(transicao.pedido, transicao.evento)
    except Exception:  # noqa: BLE001 - o pedido sobra aberto, mas a visita já saiu da agenda
        log.warning("não cancelei o pedido da visita %s", pedido.id, exc_info=True)
        return False
    return True


_ESTADOS_DE_PEDIDO_NAO_PAGO = ("aberto", "reservado", "orcamento_aceito", "aguardando_confirmacao")


def fechar_visitas(
    contexto: Any, agora: datetime, cancelar_pedido: Callable[[Any, Any], None] | None = None
) -> tuple[int, int]:
    """Rotina: visita paga vira `confirmada_paga`; sem pagamento a tempo, `expirada`.

    Devolve (confirmadas, expiradas). Expirar libera a agenda: o pedido aberto da visita é
    cancelado (quando possível) e ninguém é punido.
    """
    repo = contexto.recorrencias
    cfg = repo.config()
    confirmadas = expiradas = 0
    for visita in repo.visitas_abertas():
        rec = repo.obter(visita.recorrencia_id)
        pedido = contexto.pedidos.obter(visita.pedido_id) if visita.pedido_id else None
        if pedido is not None and pedido.estado.value not in (
            *_ESTADOS_DE_PEDIDO_NAO_PAGO,
            "cancelado",
        ):
            confirmadas += int(repo.mudar_visita(visita.id, (V_AGENDADA,), V_PAGA))
            continue
        limite = visita.data_prevista_em - timedelta(hours=cfg.limite_confirmacao_horas)
        if agora < limite and (pedido is None or pedido.estado.value != "cancelado"):
            continue
        if repo.mudar_visita(visita.id, (V_AGENDADA,), V_EXPIRADA):
            expiradas += 1
            if pedido is not None and cancelar_pedido is not None and rec is not None:
                try:
                    cancelar_pedido(rec, pedido)
                except Exception:  # noqa: BLE001 - a visita já expirou; o pedido sobra aberto
                    log.exception("Não consegui cancelar o pedido da visita %s", visita.id)
    return confirmadas, expiradas
