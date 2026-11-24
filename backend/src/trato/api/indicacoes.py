"""Indique e Ganhe Tratinhos: código pessoal, vínculo único, gatilho no 1º serviço e liberação.

Decisões aprovadas (docs/decisoes-indicacao-e-recorrencia.md, 23/11/2026). Quem decide valores,
limites e prazos é o backend; nada disso vem do app.

Fluxo:
1. `cadastrado`: o indicado aplicou o código (uma vez só, antes do 1º pedido).
2. `aguardando_liberacao`: o 1º serviço dele (a partir de `valor_minimo_servico_centavos`, pago e
   concluído) aconteceu; os Tratinhos esperam `dias_liberacao` dias.
3. `liberado`: sem disputa, estorno ou cancelamento do pedido gatilho, os dois recebem (tipo
   `bonus_indicacao`, chave idempotente por indicação e lado, validade `validade_dias`).
   Com disputa aberta, procedente, estorno ou cancelamento: `cancelado`, ninguém recebe.

Limite mensal do indicador (Brasília): `limite_mensal_cliente` / `limite_mensal_profissional`
indicações recompensadas (aguardando + liberado, contadas pela data do gatilho). Passou do limite:
a indicação continua valendo para o INDICADO, mas o bônus do indicador fica 0 (registrado assim).

Os valores ficam em `ConfigIndicacao` (um lugar só). Sem tabela de configuração no banco ainda,
o padrão é o aprovado; trocar exige só `salvar_config`/futura tabela, nunca mexer nas regras.
"""

from __future__ import annotations

import hashlib
import logging
import threading
import uuid
from collections.abc import Callable, Iterable
from dataclasses import dataclass, replace
from datetime import datetime, timedelta
from typing import Any, Protocol

from trato.financeiro import periodo

log = logging.getLogger("trato.indicacoes")

TIPO_CLIENTE_CLIENTE = "cliente_cliente"
TIPO_PROFISSIONAL_CLIENTE = "profissional_cliente"
TIPO_PROFISSIONAL_PROFISSIONAL = "profissional_profissional"
TIPO_LANCAMENTO = "bonus_indicacao"

STATUS_CADASTRADO = "cadastrado"
STATUS_AGUARDANDO = "aguardando_liberacao"
STATUS_LIBERADO = "liberado"
STATUS_CANCELADO = "cancelado"
STATUS_BLOQUEADO_FRAUDE = "bloqueado_fraude"

# Sem 0/O e 1/I/L: o código é lido e digitado por gente.
ALFABETO_CODIGO = "ABCDEFGHJKMNPQRSTUVWXYZ23456789"
TAMANHO_CODIGO = 8


@dataclass(frozen=True)
class ConfigIndicacao:
    # (indicador, indicado) em Tratinhos por tipo de indicação.
    bonus_cliente_cliente: tuple[int, int] = (300, 300)
    bonus_profissional_cliente: tuple[int, int] = (150, 300)
    bonus_profissional_profissional: tuple[int, int] = (150, 100)
    valor_minimo_servico_centavos: int = 6_000
    dias_liberacao: int = 7
    validade_dias: int = 90
    limite_mensal_cliente: int = 3
    limite_mensal_profissional: int = 5

    def bonus_do_tipo(self, tipo: str) -> tuple[int, int]:
        return {
            TIPO_CLIENTE_CLIENTE: self.bonus_cliente_cliente,
            TIPO_PROFISSIONAL_CLIENTE: self.bonus_profissional_cliente,
            TIPO_PROFISSIONAL_PROFISSIONAL: self.bonus_profissional_profissional,
        }[tipo]

    def limite_do_tipo(self, tipo: str) -> int:
        if tipo == TIPO_CLIENTE_CLIENTE:
            return self.limite_mensal_cliente
        return self.limite_mensal_profissional


class JaIndicado(Exception):
    """Este usuário já usou um código de indicação."""


@dataclass(frozen=True)
class Indicacao:
    id: str
    indicador_id: str
    indicado_id: str
    codigo_usado: str
    tipo: str
    status: str
    criado_em: datetime
    bonus_indicador_tratinhos: int = 0
    bonus_indicado_tratinhos: int = 0
    pedido_gatilho_id: str | None = None
    liberacao_prevista_em: datetime | None = None
    liberado_em: datetime | None = None
    motivo_bloqueio: str = ""


def candidatos_de_codigo(usuario_id: str) -> Iterable[str]:
    """Códigos determinísticos do usuário: o 1º é sempre o mesmo; colisão passa para o próximo."""
    for n in range(64):
        resumo = hashlib.sha256(f"trato-indicacao:{usuario_id}:{n}".encode()).digest()
        yield "".join(ALFABETO_CODIGO[b % len(ALFABETO_CODIGO)] for b in resumo[:TAMANHO_CODIGO])


def normalizar_email(email: str | None) -> str | None:
    """E-mail comparável: minúsculas, sem `+tag` e, no Gmail, sem pontos no usuário."""
    if not email or "@" not in email:
        return None
    usuario, _, dominio = email.strip().lower().rpartition("@")
    usuario = usuario.split("+", 1)[0]
    if dominio in ("gmail.com", "googlemail.com"):
        usuario = usuario.replace(".", "")
        dominio = "gmail.com"
    return f"{usuario}@{dominio}" if usuario else None


def normalizar_telefone(telefone: str | None) -> str | None:
    """Só dígitos, sem o 55 do país (10 ou 11 dígitos com DDD)."""
    digitos = "".join(c for c in (telefone or "") if c.isdigit())
    if digitos.startswith("55") and len(digitos) in (12, 13):
        digitos = digitos[2:]
    return digitos if len(digitos) >= 10 else None


def contato_repetido(contexto: Any, usuario_a: str, usuario_b: str) -> str | None:
    """`mesmo_telefone` ou `mesmo_email` se as duas contas dividem o contato; senão None.

    Antifraude leve: só compara o que existe. Sem dado (ou falha ao ler), não bloqueia.
    """
    try:
        a, b = contexto.conta.dados(usuario_a), contexto.conta.dados(usuario_b)
    except Exception:  # noqa: BLE001 - sem dados confiáveis, a indicação segue
        return None
    tel_a, tel_b = normalizar_telefone(a.telefone), normalizar_telefone(b.telefone)
    if tel_a and tel_a == tel_b:
        return "mesmo_telefone"
    mail_a, mail_b = normalizar_email(a.email), normalizar_email(b.email)
    if mail_a and mail_a == mail_b:
        return "mesmo_email"
    return None


def resolver_tipo(indicador_profissional: bool, indicado_profissional: bool) -> str | None:
    """O tipo da indicação, ou None se o par não é permitido (cliente indicando profissional)."""
    if indicador_profissional:
        return (
            TIPO_PROFISSIONAL_PROFISSIONAL if indicado_profissional else TIPO_PROFISSIONAL_CLIENTE
        )
    return None if indicado_profissional else TIPO_CLIENTE_CLIENTE


class RepositorioIndicacoes(Protocol):
    def config(self) -> ConfigIndicacao: ...

    def garantir_codigo(self, usuario_id: str, candidatos: Iterable[str]) -> str:
        """O código do usuário; cria o primeiro candidato livre se ele ainda não tem."""
        ...

    def usuario_do_codigo(self, codigo: str) -> str | None: ...

    def do_indicado(self, indicado_id: str) -> Indicacao | None: ...

    def criar(
        self,
        indicador_id: str,
        indicado_id: str,
        codigo: str,
        tipo: str,
        bonus_indicador: int,
        bonus_indicado: int,
        agora: datetime,
        status: str = STATUS_CADASTRADO,
        motivo_bloqueio: str = "",
    ) -> Indicacao:
        """Levanta `JaIndicado` se o indicado já tem indicação (unique)."""
        ...

    def do_indicador(self, indicador_id: str) -> list[Indicacao]:
        """Mais recentes primeiro."""
        ...

    def recompensadas_no_mes(
        self, indicador_id: str, inicio: datetime, fim: datetime, dias_liberacao: int
    ) -> int: ...

    def armar(
        self,
        indicacao_id: str,
        pedido_id: str,
        bonus_indicador: int,
        liberacao_prevista_em: datetime,
    ) -> bool:
        """cadastrado -> aguardando_liberacao (atômico). False se já não estava cadastrado."""
        ...

    def vencidas(self, agora: datetime) -> list[Indicacao]: ...

    def encerrar(self, indicacao_id: str, status: str, agora: datetime, motivo: str = "") -> bool:
        """aguardando_liberacao -> liberado|cancelado (atômico). False se já foi encerrada."""
        ...


class IndicacoesEmMemoria:
    def __init__(self, config: ConfigIndicacao | None = None) -> None:
        self._config = config or ConfigIndicacao()
        self._codigos: dict[str, str] = {}  # usuario_id -> codigo
        self._por_codigo: dict[str, str] = {}
        self._itens: dict[str, Indicacao] = {}
        self._trava = threading.Lock()

    def config(self) -> ConfigIndicacao:
        return self._config

    def salvar_config(self, config: ConfigIndicacao) -> None:
        self._config = config

    def garantir_codigo(self, usuario_id: str, candidatos: Iterable[str]) -> str:
        with self._trava:
            if usuario_id in self._codigos:
                return self._codigos[usuario_id]
            for candidato in candidatos:
                if candidato not in self._por_codigo:
                    self._codigos[usuario_id] = candidato
                    self._por_codigo[candidato] = usuario_id
                    return candidato
        raise RuntimeError("Sem código de indicação livre.")

    def usuario_do_codigo(self, codigo: str) -> str | None:
        return self._por_codigo.get(codigo)

    def do_indicado(self, indicado_id: str) -> Indicacao | None:
        return next((i for i in self._itens.values() if i.indicado_id == indicado_id), None)

    def criar(
        self,
        indicador_id: str,
        indicado_id: str,
        codigo: str,
        tipo: str,
        bonus_indicador: int,
        bonus_indicado: int,
        agora: datetime,
        status: str = STATUS_CADASTRADO,
        motivo_bloqueio: str = "",
    ) -> Indicacao:
        with self._trava:
            if self.do_indicado(indicado_id) is not None:
                raise JaIndicado
            nova = Indicacao(
                id=str(uuid.uuid4()),
                indicador_id=indicador_id,
                indicado_id=indicado_id,
                codigo_usado=codigo,
                tipo=tipo,
                status=status,
                criado_em=agora,
                bonus_indicador_tratinhos=bonus_indicador,
                bonus_indicado_tratinhos=bonus_indicado,
                motivo_bloqueio=motivo_bloqueio,
            )
            self._itens[nova.id] = nova
            return nova

    def do_indicador(self, indicador_id: str) -> list[Indicacao]:
        achadas = [i for i in self._itens.values() if i.indicador_id == indicador_id]
        return sorted(achadas, key=lambda i: i.criado_em, reverse=True)

    def recompensadas_no_mes(
        self, indicador_id: str, inicio: datetime, fim: datetime, dias_liberacao: int
    ) -> int:
        espera = timedelta(days=dias_liberacao)
        return sum(
            1
            for i in self._itens.values()
            if i.indicador_id == indicador_id
            and i.status in (STATUS_AGUARDANDO, STATUS_LIBERADO)
            and i.liberacao_prevista_em is not None
            and inicio <= i.liberacao_prevista_em - espera < fim
        )

    def armar(
        self,
        indicacao_id: str,
        pedido_id: str,
        bonus_indicador: int,
        liberacao_prevista_em: datetime,
    ) -> bool:
        with self._trava:
            atual = self._itens.get(indicacao_id)
            if atual is None or atual.status != STATUS_CADASTRADO:
                return False
            self._itens[indicacao_id] = replace(
                atual,
                status=STATUS_AGUARDANDO,
                pedido_gatilho_id=pedido_id,
                bonus_indicador_tratinhos=bonus_indicador,
                liberacao_prevista_em=liberacao_prevista_em,
            )
            return True

    def vencidas(self, agora: datetime) -> list[Indicacao]:
        return [
            i
            for i in self._itens.values()
            if i.status == STATUS_AGUARDANDO
            and i.liberacao_prevista_em is not None
            and i.liberacao_prevista_em <= agora
        ]

    def encerrar(self, indicacao_id: str, status: str, agora: datetime, motivo: str = "") -> bool:
        with self._trava:
            atual = self._itens.get(indicacao_id)
            if atual is None or atual.status != STATUS_AGUARDANDO:
                return False
            self._itens[indicacao_id] = replace(
                atual,
                status=status,
                liberado_em=agora if status == STATUS_LIBERADO else None,
                motivo_bloqueio=motivo,
            )
            return True


# --- Regras que usam o contexto (gatilho e liberação) -----------------------------------------


def _carteira(tipo: str, lado: str) -> str:
    """Carteira em que o bônus cai: do profissional ou do cliente."""
    profissional = tipo == TIPO_PROFISSIONAL_PROFISSIONAL or (
        tipo == TIPO_PROFISSIONAL_CLIENTE and lado == "indicador"
    )
    return "profissional" if profissional else "cliente"


def _abertura_do_mes(agora: datetime) -> tuple[datetime, datetime]:
    return periodo.mes(*periodo.mes_de(agora))


def acionar_gatilho(contexto: Any, pedido: Any, agora: datetime) -> list[Indicacao]:
    """Pedido concluído: arma as indicações cujo indicado acabou de fazer o 1º serviço válido."""
    repo = contexto.indicacoes
    cfg = repo.config()
    contrato = contexto.contratos.obter_do_pedido(pedido.id)
    if contrato is None or contrato.valor_centavos < cfg.valor_minimo_servico_centavos:
        return []
    if not pedido.profissional_id:
        return []
    if contexto.ledger.saldos_pedido(pedido.id, pedido.profissional_id).cliente_pagou <= 0:
        return []  # sem pagamento confirmado não há gatilho
    candidatas: list[Indicacao] = []
    como_cliente = repo.do_indicado(pedido.cliente_id)
    if como_cliente is not None and como_cliente.tipo != TIPO_PROFISSIONAL_PROFISSIONAL:
        candidatas.append(como_cliente)
    como_profissional = repo.do_indicado(pedido.profissional_id)
    if como_profissional is not None and como_profissional.tipo == TIPO_PROFISSIONAL_PROFISSIONAL:
        candidatas.append(como_profissional)
    inicio, fim = _abertura_do_mes(agora)
    armadas: list[Indicacao] = []
    for indicacao in candidatas:
        if indicacao.status != STATUS_CADASTRADO:
            continue
        ja = repo.recompensadas_no_mes(indicacao.indicador_id, inicio, fim, cfg.dias_liberacao)
        bonus_indicador = (
            indicacao.bonus_indicador_tratinhos if ja < cfg.limite_do_tipo(indicacao.tipo) else 0
        )
        previsao = agora + timedelta(days=cfg.dias_liberacao)
        if repo.armar(indicacao.id, pedido.id, bonus_indicador, previsao):
            armadas.append(
                replace(
                    indicacao,
                    status=STATUS_AGUARDANDO,
                    pedido_gatilho_id=pedido.id,
                    bonus_indicador_tratinhos=bonus_indicador,
                    liberacao_prevista_em=previsao,
                )
            )
    return armadas


def gancho_indicacoes(antes: Any, depois: Any, acao: Any, contexto: Any) -> None:
    """`Contexto.apos_transicao`: ao concluir o pedido, arma a indicação. Nunca derruba a rota."""
    try:
        from trato.pedidos.estados import Estado

        if depois.estado is Estado.CONCLUIDO and antes.estado is not Estado.CONCLUIDO:
            acionar_gatilho(contexto, depois, contexto.agora())
    except Exception:  # noqa: BLE001 - bônus é secundário à conclusão do serviço
        log.warning("gatilho de indicação falhou", exc_info=True)


def liberar_vencidas(
    contexto: Any,
    agora: datetime,
    situacao_pedido: Callable[[str], str],
    avisar: Callable[[Indicacao, str, int, str], None] | None = None,
) -> int:
    """Rotina: libera (ou cancela) as indicações cujo prazo venceu. Devolve quantas liberou.

    `situacao_pedido(pedido_gatilho_id)`: `nenhuma` | `aberta` | `procedente` | `estornado`.
    Qualquer coisa diferente de `nenhuma` cancela. Idempotente: o lançamento tem chave fixa por
    indicação e lado, e `encerrar` só vale uma vez, então repetir o ciclo nunca credita de novo.
    Com a gamificação de moedas desligada (`ativo = False`) nada é creditado e a indicação espera.
    """
    from trato.api.moedas import LancamentoMoeda

    repo, moedas = contexto.indicacoes, contexto.moedas
    cfg = repo.config()
    if not moedas.config().ativo:
        return 0
    liberadas = 0
    for ind in repo.vencidas(agora):
        situacao = situacao_pedido(ind.pedido_gatilho_id) if ind.pedido_gatilho_id else "estornado"
        if situacao != "nenhuma":
            repo.encerrar(ind.id, STATUS_CANCELADO, agora, f"pedido_gatilho:{situacao}")
            continue
        expira = agora + timedelta(days=cfg.validade_dias)
        lados = (
            ("indicador", ind.indicador_id, ind.bonus_indicador_tratinhos),
            ("indicado", ind.indicado_id, ind.bonus_indicado_tratinhos),
        )
        with contexto.transacao():
            for lado, usuario_id, quantidade in lados:
                if quantidade <= 0:
                    continue
                moedas.lancar(
                    LancamentoMoeda(
                        usuario_id=usuario_id,
                        tipo=TIPO_LANCAMENTO,
                        quantidade=quantidade,
                        chave_idempotencia=f"indicacao:{ind.id}:{lado}",
                        criada_em=agora,
                        referencia_id=ind.pedido_gatilho_id,
                        parceiro_id=ind.indicado_id if lado == "indicador" else ind.indicador_id,
                        expira_em=expira,
                        carteira=_carteira(ind.tipo, lado),
                    )
                )
            if not repo.encerrar(ind.id, STATUS_LIBERADO, agora):
                continue
        liberadas += 1
        if avisar is not None:
            for lado, usuario_id, quantidade in lados:
                if quantidade > 0:
                    avisar(ind, usuario_id, quantidade, lado)
    return liberadas
