"""Estados da disputa e transições. Imutável: cada transição devolve uma nova Disputa.

Fluxo:
  ABERTA --responder (profissional, até 48 h)--> EM_ANALISE
  ABERTA --encerrar_sem_resposta (sistema, após o prazo)--> EM_ANALISE
  EM_ANALISE --decidir (analista)--> DECIDIDA              (valor <= alçada)
  EM_ANALISE --decidir (analista)--> AGUARDANDO_APROVACAO  (valor > alçada)
  AGUARDANDO_APROVACAO --aprovar (outro analista)--> DECIDIDA
  DECIDIDA é final. O valor fica congelado em todos os estados anteriores.
"""

from __future__ import annotations

from dataclasses import dataclass, replace
from datetime import datetime
from enum import StrEnum

from trato.disputas.config import ConfigDisputa
from trato.disputas.erros import (
    AlcadaInvalida,
    PrazoExpirado,
    ResultadoInvalido,
    TransicaoInvalida,
)
from trato.disputas.prazos import Prazos, calcular_prazos, dentro_da_janela
from trato.disputas.resultado import Decisao, Divisao, dividir_valor


class Estado(StrEnum):
    ABERTA = "aberta"  # aguardando o profissional
    EM_ANALISE = "em_analise"  # aguardando o analista
    AGUARDANDO_APROVACAO = "aguardando_aprovacao"  # decisão acima da alçada
    DECIDIDA = "decidida"  # final


class Ator(StrEnum):
    CLIENTE = "cliente"
    PROFISSIONAL = "profissional"
    ANALISTA = "analista"
    SISTEMA = "sistema"


class Motivo(StrEnum):
    ABANDONO = "abandono"
    MAL_FEITO = "mal_feito"
    DANO = "dano"
    COBRANCA_EXTRA = "cobranca_extra"
    NAO_COMPARECEU = "nao_compareceu"
    DIFERENTE_DO_COMBINADO = "diferente_do_combinado"


@dataclass(frozen=True)
class Disputa:
    valor_congelado: int  # centavos
    motivo: Motivo
    aberta_em: datetime
    prazos: Prazos
    estado: Estado = Estado.ABERTA
    respondida_em: datetime | None = None
    sem_resposta: bool = False  # profissional não respondeu no prazo
    decisao: Decisao | None = None
    decidido_por: str | None = None
    decidido_em: datetime | None = None
    aprovado_por: str | None = None
    aprovado_em: datetime | None = None
    divisao: Divisao | None = None  # preenchida quando DECIDIDA
    # False = aberta depois da janela de congelamento: o repasse pode já ter sido liberado.
    # A reclamação continua valendo (suporte e análise); só o congelamento automático some.
    abertura_dentro_da_janela_de_congelamento: bool = True

    def _exigir(self, estado: Estado, ator: Ator, esperado: Ator) -> None:
        if ator is not esperado:
            raise TransicaoInvalida(f"{ator} não pode fazer esta operação (só {esperado})")
        if self.estado is not estado:
            raise TransicaoInvalida(f"operação inválida no estado {self.estado}")

    def responder(self, ator: Ator, agora: datetime) -> Disputa:
        """Profissional responde dentro do prazo."""
        self._exigir(Estado.ABERTA, ator, Ator.PROFISSIONAL)
        if agora > self.prazos.resposta_ate:
            raise PrazoExpirado("prazo de resposta do profissional encerrado")
        return replace(self, estado=Estado.EM_ANALISE, respondida_em=agora)

    def encerrar_sem_resposta(self, ator: Ator, agora: datetime) -> Disputa:
        """Sistema manda para análise quando o profissional não respondeu no prazo."""
        self._exigir(Estado.ABERTA, ator, Ator.SISTEMA)
        if agora <= self.prazos.resposta_ate:
            raise TransicaoInvalida("prazo de resposta ainda não venceu")
        return replace(self, estado=Estado.EM_ANALISE, sem_resposta=True)

    def decidir(
        self,
        ator: Ator,
        analista: str,
        decisao: Decisao,
        agora: datetime,
        teto_alcada: int,
    ) -> Disputa:
        """Analista decide. Acima do teto (valor congelado > teto_alcada) espera 2ª pessoa.

        Decidir depois de `prazos.decisao_ate` é permitido (veja `atrasada`)."""
        self._exigir(Estado.EM_ANALISE, ator, Ator.ANALISTA)
        if not analista:
            raise ResultadoInvalido("analista não informado")
        divisao = dividir_valor(self.valor_congelado, decisao)  # valida a decisão
        if self.valor_congelado > teto_alcada:
            return replace(
                self,
                estado=Estado.AGUARDANDO_APROVACAO,
                decisao=decisao,
                decidido_por=analista,
                decidido_em=agora,
            )
        return replace(
            self,
            estado=Estado.DECIDIDA,
            decisao=decisao,
            decidido_por=analista,
            decidido_em=agora,
            divisao=divisao,
        )

    def aprovar(self, ator: Ator, aprovador: str, agora: datetime) -> Disputa:
        """Segunda pessoa confirma a decisão acima da alçada."""
        self._exigir(Estado.AGUARDANDO_APROVACAO, ator, Ator.ANALISTA)
        if not aprovador or aprovador == self.decidido_por:
            raise AlcadaInvalida("aprovado_por deve ser diferente de decidido_por")
        if self.decisao is None:
            raise TransicaoInvalida("sem decisão para aprovar")
        return replace(
            self,
            estado=Estado.DECIDIDA,
            aprovado_por=aprovador,
            aprovado_em=agora,
            divisao=dividir_valor(self.valor_congelado, self.decisao),
        )

    def atrasada(self, agora: datetime) -> bool:
        """Prazo de decisão estourado sem decisão final."""
        return self.estado is not Estado.DECIDIDA and agora > self.prazos.decisao_ate


def abrir(
    ator: Ator,
    valor_congelado: int,
    motivo: Motivo,
    concluido_em: datetime,
    agora: datetime,
    config: ConfigDisputa,
) -> Disputa:
    """Cliente abre a disputa; o valor retido fica congelado.

    A janela de congelamento (`prazo_congelar_repasse_horas`) só diz se o repasse ainda está
    retido por padrão. Passar dela NÃO recusa a reclamação: isso seria renunciar a um direito
    do cliente por regra automática. Os prazos legais são só informativos (`prazos_legais`).
    """
    if ator is not Ator.CLIENTE:
        raise TransicaoInvalida(f"{ator} não pode abrir disputa (só cliente)")
    if isinstance(valor_congelado, bool) or not isinstance(valor_congelado, int):
        raise ResultadoInvalido("valor congelado deve ser inteiro (centavos)")
    if valor_congelado <= 0:
        raise ResultadoInvalido("valor congelado deve ser > 0")
    return Disputa(
        valor_congelado=valor_congelado,
        motivo=motivo,
        aberta_em=agora,
        prazos=calcular_prazos(agora, config),
        abertura_dentro_da_janela_de_congelamento=dentro_da_janela(concluido_em, agora, config),
    )
