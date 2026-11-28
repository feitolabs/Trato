"""Contexto injetável: tudo que as rotas usam e que muda entre teste e produção."""

from __future__ import annotations

from collections.abc import Callable, Iterator
from contextlib import AbstractContextManager, contextmanager, nullcontext
from contextvars import ContextVar
from dataclasses import dataclass, field, replace
from datetime import UTC, datetime
from typing import Any

from fastapi import Depends, HTTPException, Request
from fastapi.responses import JSONResponse
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer

from trato.api.auth import PapelUsuario, ProvedorAuth, Usuario
from trato.api.memoria_app import (
    AvaliacoesEmMemoria,
    ConversasEmMemoria,
    NotasMaterialEmMemoria,
    NotificacoesEmMemoria,
    RecusasEmMemoria,
    UsuariosEmMemoria,
    VerificacoesEmMemoria,
)
from trato.api.repositorios import (
    EventoWebhook,
    ProvedorConfig,
    RepositorioContratos,
    RepositorioDisputas,
    RepositorioEventosWebhook,
    RepositorioGarantias,
    RepositorioLedger,
    RepositorioOrcamentos,
    RepositorioPedidos,
    RepositorioRepasses,
)
from trato.api.repositorios_app import (
    RepositorioAvaliacoes,
    RepositorioConversas,
    RepositorioNotasMaterial,
    RepositorioNotificacoes,
    RepositorioRecusas,
    RepositorioUsuarios,
    RepositorioVerificacoes,
)
from trato.config import obter_config
from trato.pedidos.estados import Acao, Estado, Papel, Pedido
from trato.persistencia.ausencias import AusenciasEmMemoria
from trato.persistencia.avaliacoes_moderacao import ModeracaoAvaliacoesEmMemoria
from trato.persistencia.cancelamentos import CancelamentosEmMemoria
from trato.persistencia.chamados import ChamadosEmMemoria
from trato.persistencia.checkout_sem_codigo import CheckoutSemCodigoEmMemoria
from trato.persistencia.compensacoes import CompensacoesIndisponiveis
from trato.persistencia.contestacoes_decisao import ContestacoesDecisaoEmMemoria
from trato.persistencia.disputa_pedidos_info import DisputaPedidosInfoEmMemoria
from trato.persistencia.forca_maior import ForcaMaiorEmMemoria
from trato.persistencia.incidentes import IncidentesEmMemoria
from trato.persistencia.indisponibilidades import IndisponibilidadesEmMemoria
from trato.persistencia.lgpd_titular import LgpdTitularEmMemoria
from trato.persistencia.materiais_contestacao import ContestacaoMaterialEmMemoria
from trato.persistencia.medidas import MedidasEmMemoria
from trato.persistencia.pedido_guardas import PedidoGuardasEmMemoria
from trato.persistencia.retorno_conta import RetornoContaEmMemoria
from trato.persistencia.sac import SacEmMemoria
from trato.persistencia.selos import SelosEmMemoria


def agora_utc() -> datetime:
    return datetime.now(UTC)


def segredo_webhook_do_env() -> str:
    """O segredo do webhook vem do .env (STRIPE_WEBHOOK_SECRET), nunca do código."""
    return obter_config().stripe_webhook_secret.get_secret_value()


# Cada tipo de evento do Stripe ganha um manipulador que traduz o evento em ledger + transição
# do pedido. Os de pagamento vêm de `webhook_pagamento.py` (D13: "pago" só pelo webhook).
ManipuladorWebhook = Callable[[EventoWebhook, "Contexto"], None]
# Gancho após uma transição já gravada: (pedido antes, pedido depois, ação, contexto).
# Serve para efeitos financeiros que dependem da mudança (ex.: repartir a custódia ao concluir).
GanchoTransicao = Callable[[Pedido, Pedido, Acao, "Contexto"], None]


def _manipuladores_padrao() -> dict[str, ManipuladorWebhook]:
    from trato.api.webhook_pagamento import manipuladores_padrao

    return manipuladores_padrao()


_APOS_COMMIT: ContextVar[list[Callable[[], None]] | None] = ContextVar(
    "trato_apos_commit", default=None
)


def _conta_em_memoria() -> Any:
    from trato.api.conta import ContaEmMemoria

    return ContaEmMemoria()


def _contestacoes_em_memoria() -> Any:
    from trato.financeiro.contestacoes import ContestacoesEmMemoria

    return ContestacoesEmMemoria()


def _fechamentos_em_memoria() -> Any:
    from trato.financeiro.fechamento import FechamentosEmMemoria

    return FechamentosEmMemoria()


def _repasses_em_memoria() -> RepositorioRepasses:
    from trato.api.memoria import RepassesEmMemoria

    return RepassesEmMemoria()


from trato.api.denuncias import DenunciasEmMemoria  # noqa: E402
from trato.api.exclusividades import ExclusividadesEmMemoria  # noqa: E402
from trato.api.indicacoes import IndicacoesEmMemoria, gancho_indicacoes  # noqa: E402
from trato.api.moedas import MoedasEmMemoria  # noqa: E402
from trato.api.reagendamentos import ReagendamentosEmMemoria  # noqa: E402
from trato.api.recorrencias import RecorrenciasEmMemoria  # noqa: E402
from trato.profissional.ranking import RankingEmMemoria  # noqa: E402


@dataclass
class Contexto:
    auth: ProvedorAuth
    pedidos: RepositorioPedidos
    orcamentos: RepositorioOrcamentos
    contratos: RepositorioContratos
    ledger: RepositorioLedger
    disputas: RepositorioDisputas
    garantias: RepositorioGarantias
    eventos_webhook: RepositorioEventosWebhook
    config: ProvedorConfig
    agora: Callable[[], datetime] = agora_utc
    segredo_webhook: Callable[[], str] = segredo_webhook_do_env
    manipuladores_webhook: dict[str, ManipuladorWebhook] = field(
        default_factory=lambda: _manipuladores_padrao()
    )
    apos_transicao: list[GanchoTransicao] = field(default_factory=list)
    # Rotas do app. Em memória por padrão; a fábrica Postgres troca os que já têm tabela.
    conversas: RepositorioConversas = field(default_factory=ConversasEmMemoria)
    notificacoes: RepositorioNotificacoes = field(default_factory=NotificacoesEmMemoria)
    usuarios: RepositorioUsuarios = field(default_factory=UsuariosEmMemoria)
    verificacoes: RepositorioVerificacoes = field(default_factory=VerificacoesEmMemoria)
    avaliacoes: RepositorioAvaliacoes = field(default_factory=AvaliacoesEmMemoria)
    # Moedas do Trato (gamificação). Em memória por padrão; a fábrica Postgres troca.
    moedas: Any = field(default_factory=lambda: MoedasEmMemoria())
    # Exclusividade de 48h (funções SQL no Postgres; memória com a mesma semântica).
    exclusividades: Any = field(default_factory=lambda: ExclusividadesEmMemoria())
    # Propostas de nova janela do atendimento (tabela `reagendamentos`).
    reagendamentos: Any = field(default_factory=lambda: ReagendamentosEmMemoria())
    # Denúncias de perfil/chat: viram alertas na fila de risco (alertas_risco).
    denuncias: Any = field(default_factory=lambda: DenunciasEmMemoria())
    # Indique e Ganhe Tratinhos (tabelas `codigos_indicacao` e `indicacoes`).
    indicacoes: Any = field(default_factory=lambda: IndicacoesEmMemoria())
    # Serviço recorrente (tabelas recorrencias e recorrencia_visitas).
    recorrencias: Any = field(default_factory=lambda: RecorrenciasEmMemoria())
    # Pesos do ranking de profissionais na busca (tabela `ranking_config`).
    ranking: Any = field(default_factory=lambda: RankingEmMemoria())
    recusas: RepositorioRecusas = field(default_factory=RecusasEmMemoria)
    notas_material: RepositorioNotasMaterial = field(default_factory=NotasMaterialEmMemoria)
    # Dados pessoais, endereços, favoritos e contatos de confiança (`api/conta.py`).
    conta: Any = field(default_factory=lambda: _conta_em_memoria())
    repasses: RepositorioRepasses = field(default_factory=_repasses_em_memoria)
    # Contestações de cartão (chargeback) avisadas pelo provedor (`financeiro/contestacoes.py`).
    contestacoes: Any = field(default_factory=lambda: _contestacoes_em_memoria())
    # Desistência e consentimento de execução imediata (`persistencia/cancelamentos.py`).
    cancelamentos: Any = field(default_factory=lambda: CancelamentosEmMemoria())
    # Cliente ausente (`persistencia/ausencias.py`, Termos 7.6).
    ausencias: Any = field(default_factory=lambda: AusenciasEmMemoria())
    # Medidas de conta vigentes (`persistencia/medidas.py`).
    medidas: Any = field(default_factory=lambda: MedidasEmMemoria())
    # Contestações da ausência e vínculos de leitura de conversa (`persistencia/chamados.py`).
    chamados: Any = field(default_factory=lambda: ChamadosEmMemoria())
    # Incidentes de segurança (`persistencia/incidentes.py`, Termos 9.3 a 9.6).
    incidentes: Any = field(default_factory=lambda: IncidentesEmMemoria())
    # Janelas de indisponibilidade (`persistencia/indisponibilidades.py`, Termos 22.3).
    indisponibilidades: Any = field(default_factory=lambda: IndisponibilidadesEmMemoria())
    # Selo do profissional (`persistencia/selos.py`, Termos 10.3).
    selos: Any = field(default_factory=lambda: SelosEmMemoria())
    # Casos de check-out sem o Código Final (`persistencia/checkout_sem_codigo.py`, 5.7).
    checkout_sem_codigo: Any = field(default_factory=lambda: CheckoutSemCodigoEmMemoria())
    disputa_pedidos_info: Any = field(default_factory=lambda: DisputaPedidosInfoEmMemoria())
    forca_maior: Any = field(default_factory=lambda: ForcaMaiorEmMemoria())
    # Guarda de Pedido e retenção (`persistencia/pedido_guardas.py`, Termos 16.3).
    pedido_guardas: Any = field(default_factory=lambda: PedidoGuardasEmMemoria())
    materiais_contestacao: Any = field(default_factory=lambda: ContestacaoMaterialEmMemoria())
    retorno_conta: Any = field(default_factory=lambda: RetornoContaEmMemoria())
    lgpd_titular: Any = field(default_factory=lambda: LgpdTitularEmMemoria())
    avaliacoes_moderacao: Any = field(default_factory=lambda: ModeracaoAvaliacoesEmMemoria())
    # Chamados do atendimento (`persistencia/sac.py`).
    sac: Any = field(default_factory=lambda: SacEmMemoria())
    # Compensação em repasses (`persistencia/compensacoes.py`; regras no banco).
    compensacoes: Any = field(default_factory=lambda: CompensacoesIndisponiveis())
    # Contestação da decisão de disputa (`persistencia/contestacoes_decisao.py`).
    contestacoes_decisao: Any = field(default_factory=lambda: ContestacoesDecisaoEmMemoria())
    # Fechamentos mensais do financeiro (`financeiro/fechamento.py`): imutáveis depois de gravados.
    fechamentos: Any = field(default_factory=lambda: _fechamentos_em_memoria())
    # Transação do armazenamento (reentrante). Em memória não faz nada; no Postgres é
    # `Banco.transacao`. Use `contexto.transacao()`, que também roda os `depois_do_commit`.
    transacao_banco: Callable[[], AbstractContextManager[object]] = nullcontext
    # Só existem com persistência Postgres (a memória não os implementa).
    extras: dict[str, Any] = field(default_factory=dict)
    # Limite de tentativas do código de check-in/out (A1). Padrão: contadores em memória com a
    # configuração `TRATO_SEG_CODIGO_*` e o relógio do contexto.
    limite_codigo: Any = None

    @contextmanager
    def transacao(self) -> Iterator[None]:
        """Uma operação financeira (pedido + ledger + disputa + evento) numa única transação.

        Aninhada, entra na transação de fora. Ao confirmar a mais externa, roda o que foi pedido
        com `depois_do_commit` (ex.: chamar o provedor só depois de o ledger estar gravado).
        """
        if _APOS_COMMIT.get() is not None:
            with self.transacao_banco():
                yield
            return
        pendentes: list[Callable[[], None]] = []
        marca = _APOS_COMMIT.set(pendentes)
        try:
            with self.transacao_banco():
                yield
        finally:
            _APOS_COMMIT.reset(marca)
        for funcao in pendentes:  # só chega aqui se a transação confirmou
            funcao()

    def depois_do_commit(self, funcao: Callable[[], None]) -> None:
        """Roda `funcao` quando a transação de fora confirmar (ou já, se não houver transação)."""
        pendentes = _APOS_COMMIT.get()
        if pendentes is None:
            funcao()
        else:
            pendentes.append(funcao)

    def _contato_liberado(self, pedido_id: str, profissional_id: str) -> bool:
        """Termos 5.4 e 11.2: pagamento confirmado e conversa com o profissional contratado.
        Com o contato bloqueado entre as partes (9.6), nada passa, nem o já enviado."""
        from trato.api.cautela import contato_bloqueado
        from trato.persistencia.conversas import ESTADOS_COM_CONTATO

        contrato = self.contratos.obter_do_pedido(pedido_id)
        pedido = self.pedidos.obter(pedido_id)
        return (
            contrato is not None
            and pedido is not None
            and contrato.profissional_id == profissional_id
            and pedido.estado in ESTADOS_COM_CONTATO
            and not contato_bloqueado(self, pedido.cliente_id, profissional_id)
        )

    def _avaliacoes_publicadas(self, usuario_id: str) -> int:
        return sum(
            1
            for a in self.avaliacoes.recebidas(usuario_id)
            if a.direcao == "cliente_para_profissional"
        )

    def _nivel_do_perfil(self, usuario_id: str) -> str | None:
        detalhe = self.usuarios.detalhe(usuario_id)
        if detalhe is None or not self.usuarios.tem_perfil_profissional(usuario_id):
            return None
        return detalhe.nivel_verificacao or "basico"

    def _gravar_nivel_do_perfil(self, usuario_id: str, nivel: str) -> None:
        self.usuarios.adicionar(replace(self.usuarios.detalhe(usuario_id), nivel_verificacao=nivel))

    def __post_init__(self) -> None:
        from trato.api.regra_contratada import regras_do_aceite  # evita ciclo

        # Em memória, a retenção (9.6) enxerga os incidentes daqui; no Postgres é a tabela.
        ligar_incidentes = getattr(self.chamados, "ligar_incidentes", None)
        if ligar_incidentes is not None:
            ligar_incidentes(self.incidentes)
        # Ao concluir um pedido, arma a indicação do indicado (bônus de Indique e Ganhe).
        if gancho_indicacoes not in self.apos_transicao:
            self.apos_transicao.append(gancho_indicacoes)
        from trato.api.checkout_sem_codigo import gancho_checkout_sem_codigo  # evita ciclo

        if gancho_checkout_sem_codigo not in self.apos_transicao:
            self.apos_transicao.append(gancho_checkout_sem_codigo)
        if isinstance(self.checkout_sem_codigo, CheckoutSemCodigoEmMemoria):
            self.checkout_sem_codigo.pedidos = self.pedidos
        if isinstance(self.disputa_pedidos_info, DisputaPedidosInfoEmMemoria):
            self.disputa_pedidos_info.disputas = self.disputas
        # A versão em memória das exclusividades usa o livro de moedas e os pedidos daqui.
        vincular = getattr(self.exclusividades, "vincular", None)
        if vincular is not None:
            vincular(self)
        vincular_ret = getattr(self.retorno_conta, "vincular", None)
        if vincular_ret is not None:
            vincular_ret(self.medidas)
        vincular_av = getattr(self.avaliacoes_moderacao, "vincular", None)
        if vincular_av is not None:
            vincular_av(self.avaliacoes)
        ligar_visitas = getattr(self.pedidos, "vincular_visitas_recorrentes", None)
        if ligar_visitas is not None:
            ligar_visitas(lambda pid: self.recorrencias.profissional_do_pedido_de_visita(pid))
        ligar = getattr(self.pedidos, "vincular_exclusividades", None)
        if ligar is not None:
            ligar(lambda pid: self.exclusividades.profissional_ativo_do_pedido(pid))
        if self.limite_codigo is None:
            from trato.seguranca.config import obter_config_seguranca
            from trato.seguranca.contadores import Contadores
            from trato.seguranca.tentativas_codigo import LimiteCodigo

            self.limite_codigo = LimiteCodigo(
                obter_config_seguranca(),
                Contadores(lambda: self.agora().timestamp()),
                lambda: self.extras.get("auditoria"),
            )
        if hasattr(self.contratos, "regras_no_aceite"):
            self.contratos.regras_no_aceite = lambda: regras_do_aceite(self.config)
        if hasattr(self.usuarios, "contar_avaliacoes") and hasattr(self.avaliacoes, "recebidas"):
            self.usuarios.contar_avaliacoes = self._avaliacoes_publicadas
        if isinstance(self.selos, SelosEmMemoria):
            self.selos.ler_nivel = self._nivel_do_perfil
            self.selos.gravar_nivel = self._gravar_nivel_do_perfil
        # Antes da contratação a conversa mascara contatos: a memória pergunta ao repositório.
        if isinstance(self.conversas, ConversasEmMemoria) and self.conversas.contratado is None:
            self.conversas.contato_liberado = self._contato_liberado


def obter_contexto(request: Request) -> Contexto:
    contexto = getattr(request.app.state, "contexto", None)
    if contexto is None:
        raise HTTPException(503, "API ainda sem os repositórios ligados.")
    return contexto


_bearer = HTTPBearer(auto_error=False, description="Token do usuário (provedor de auth).")
bearer_opcional = _bearer  # rotas em que o login é opcional


class ContaBloqueada(HTTPException):
    """Termos 20.5. É 403, e não 401: o app não pode tentar renovar o token e sair da conta
    antes de chegar à Ajuda. Só o atendimento e as medidas continuam abertos ao bloqueado."""

    codigo = "conta_bloqueada"

    def __init__(self) -> None:
        super().__init__(
            403,
            "Sua conta está bloqueada. Você ainda pode falar com o atendimento e ver ou "
            "contestar a medida.",
        )


class ContaInativa(HTTPException):
    """Termos 4.9: conta inativada após aviso prévio de 30 dias. Bloqueia uso normal, mas
    permite reativação gratuita pelo próprio usuário (`POST /v1/me/reativar`) e atendimento."""

    codigo = "conta_inativa"

    def __init__(self) -> None:
        super().__init__(
            403,
            "Sua conta está inativa por falta de uso. Você pode reativá-la gratuitamente pelo "
            "aplicativo ou pelo atendimento (Termos 4.9).",
        )


async def tratar_conta_bloqueada(_: Request, erro: ContaBloqueada) -> JSONResponse:
    return JSONResponse(
        status_code=erro.status_code, content={"detail": erro.detail, "codigo": erro.codigo}
    )


async def tratar_conta_inativa(_: Request, erro: ContaInativa) -> JSONResponse:
    return JSONResponse(
        status_code=erro.status_code, content={"detail": erro.detail, "codigo": erro.codigo}
    )


def usuario_atual(
    request: Request,
    credenciais: HTTPAuthorizationCredentials | None = Depends(_bearer),
    contexto: Contexto = Depends(obter_contexto),
) -> Usuario:
    # Só o cabeçalho Authorization vale: token na URL vaza em histórico, log e referer.
    token = credenciais.credentials if credenciais else None
    usuario = contexto.auth.autenticar(token) if token else None
    if usuario is None:
        inativa = getattr(contexto.auth, "conta_inativa", None)
        if token and inativa is not None and inativa(token):
            raise ContaInativa
        bloqueada = getattr(contexto.auth, "conta_bloqueada", None)
        if token and bloqueada is not None and bloqueada(token):
            raise ContaBloqueada
        raise HTTPException(
            401, "Faça login para continuar.", headers={"WWW-Authenticate": "Bearer"}
        )
    _registrar_acesso(request, contexto, usuario.id)
    return usuario


def usuario_para_reativacao(
    request: Request,
    credenciais: HTTPAuthorizationCredentials | None = Depends(_bearer),
    contexto: Contexto = Depends(obter_contexto),
) -> Usuario:
    """Aceita conta ativa ou inativa (4.9) de cliente/profissional; bloqueada continua 403."""
    token = credenciais.credentials if credenciais else None
    bloqueada = getattr(contexto.auth, "conta_bloqueada", None)
    if token and bloqueada is not None and bloqueada(token):
        raise ContaBloqueada
    entrar = getattr(contexto.auth, "autenticar_para_suporte", contexto.auth.autenticar)
    usuario = entrar(token) if token else None
    if usuario is None:
        raise HTTPException(
            401, "Faça login para continuar.", headers={"WWW-Authenticate": "Bearer"}
        )
    if usuario.papel not in (PapelUsuario.CLIENTE, PapelUsuario.PROFISSIONAL):
        raise HTTPException(403, "A equipe não usa reativação pelo aplicativo.")
    _registrar_acesso(request, contexto, usuario.id)
    return usuario


def _registrar_acesso(request: Request, contexto: Contexto, usuario_id: str) -> None:
    from trato.api.acessos import registrar  # import tardio: evita ciclo

    registrar(request, contexto, usuario_id)


def usuario_do_suporte(
    request: Request,
    credenciais: HTTPAuthorizationCredentials | None = Depends(_bearer),
    contexto: Contexto = Depends(obter_contexto),
) -> Usuario:
    """Como o login normal, mas aceita conta bloqueada ou suspensa (20.5)."""
    token = credenciais.credentials if credenciais else None
    entrar = getattr(contexto.auth, "autenticar_para_suporte", contexto.auth.autenticar)
    usuario = entrar(token) if token else None
    if usuario is None:
        raise HTTPException(
            401, "Faça login para continuar.", headers={"WWW-Authenticate": "Bearer"}
        )
    if usuario.papel not in (PapelUsuario.CLIENTE, PapelUsuario.PROFISSIONAL):
        raise HTTPException(403, "A equipe atende pelo painel.")
    _registrar_acesso(request, contexto, usuario.id)
    return usuario


# Pedido já contratado (pagamento confirmado, Termos 6.3). Antes disso, e no cancelado, o
# bloqueado não entra.
ESTADOS_CONTRATADOS = frozenset(
    {
        Estado.PAGO_E_RETIDO,
        Estado.AGENDADO,
        Estado.EM_ANDAMENTO,
        Estado.EM_CONFIRMACAO,
        Estado.EM_DISPUTA,
        Estado.RETRABALHO,
        Estado.CONCLUIDO,
    }
)


def usuario_do_pedido_contratado(
    request: Request,
    credenciais: HTTPAuthorizationCredentials | None = Depends(_bearer),
    contexto: Contexto = Depends(obter_contexto),
) -> Usuario:
    """Login normal. A conta bloqueada só passa como CLIENTE de pedido já contratado: lista,
    detalhe, disputa e, entre as ações, `confirmar_conclusao`. Todo o resto segue 403
    `conta_bloqueada` (inclusive pedido de outra pessoa, sem revelar se existe). Use apenas
    nessas rotas."""
    try:
        return usuario_atual(request, credenciais, contexto)
    except ContaBloqueada:
        entrar = getattr(contexto.auth, "autenticar_para_suporte", None)
        usuario = entrar(credenciais.credentials) if entrar and credenciais else None
        if usuario is None or usuario.papel is PapelUsuario.EQUIPE:
            raise
        acao = request.path_params.get("acao")
        if acao is not None and acao != Acao.CONFIRMAR_CONCLUSAO.value:
            raise
        pedido_id = request.path_params.get("pedido_id")
        if pedido_id is None:  # lista "Meus pedidos", sempre como cliente
            if request.query_params.get("como") not in (None, "", "cliente"):
                raise
            pedidos = contexto.pedidos.listar_do_usuario(usuario.id, True)
        else:
            pedidos = [contexto.pedidos.obter(pedido_id)]
        if not any(bloqueado_pode_no_pedido(p, usuario.id) for p in pedidos):
            raise
        _registrar_acesso(request, contexto, usuario.id)
        return replace(usuario, bloqueado=True)


def bloqueado_pode_no_pedido(pedido: Pedido | None, usuario_id: str) -> bool:
    """Pedido do próprio cliente que chegou a ser contratado (inclusive o cancelado depois do
    pagamento, como no reembolso total decidido na disputa)."""
    return (
        pedido is not None
        and pedido.cliente_id == usuario_id
        and (
            pedido.estado in ESTADOS_CONTRATADOS
            or (pedido.estado is Estado.CANCELADO and pedido.referencia_pagamento is not None)
        )
    )


def usuario_ou_bloqueado(
    request: Request,
    credenciais: HTTPAuthorizationCredentials | None = Depends(_bearer),
    contexto: Contexto = Depends(obter_contexto),
) -> Usuario:
    """Cliente ou profissional. Conta bloqueada volta com `bloqueado=True` e a rota é OBRIGADA
    a conferir o pedido (`bloqueado_pode_no_pedido`) antes de qualquer efeito."""
    try:
        usuario = usuario_atual(request, credenciais, contexto)
    except ContaBloqueada:
        entrar = getattr(contexto.auth, "autenticar_para_suporte", None)
        usuario = entrar(credenciais.credentials) if entrar and credenciais else None
        if usuario is None or usuario.papel is PapelUsuario.EQUIPE:
            raise
        _registrar_acesso(request, contexto, usuario.id)
        return replace(usuario, bloqueado=True)
    if usuario.papel not in (PapelUsuario.CLIENTE, PapelUsuario.PROFISSIONAL):
        raise HTTPException(403, "Seu perfil não pode fazer isso.")
    return usuario


def usuario_do_proprio_pedido(
    request: Request,
    usuario: Usuario = Depends(usuario_ou_bloqueado),
    contexto: Contexto = Depends(obter_contexto),
) -> Usuario:
    """Ausência (7.6) e contestação da decisão (8.7): o cliente bloqueado age só no próprio
    pedido contratado (20.6 e 20.10). Use apenas em rotas com `{pedido_id}`."""
    if usuario.bloqueado and not bloqueado_pode_no_pedido(
        contexto.pedidos.obter(request.path_params.get("pedido_id", "")), usuario.id
    ):
        raise ContaBloqueada
    return usuario


def exigir_papel(*papeis: PapelUsuario) -> Callable[[Usuario], Usuario]:
    def dependencia(
        usuario: Usuario = Depends(usuario_atual),
        contexto: Contexto = Depends(obter_contexto),
    ) -> Usuario:
        if usuario.papel not in papeis:
            # Cadastro de profissional ainda não aprovado: o sistema o trata como cliente até lá.
            if (
                PapelUsuario.PROFISSIONAL in papeis
                and usuario.papel is PapelUsuario.CLIENTE
                and contexto.usuarios.tem_perfil_profissional(usuario.id)
            ):
                raise HTTPException(
                    403,
                    "Seu cadastro de profissional ainda está em análise. Você verá os pedidos e "
                    "poderá enviar orçamentos assim que for aprovado.",
                )
            raise HTTPException(403, "Seu perfil não pode fazer isso.")
        return usuario

    return dependencia


_PAPEL_DAS_REGRAS = {
    PapelUsuario.CLIENTE: Papel.CLIENTE,
    PapelUsuario.PROFISSIONAL: Papel.PROFISSIONAL,
    PapelUsuario.EQUIPE: Papel.MEDIADOR,
}


def papel_das_regras(usuario: Usuario) -> Papel:
    """Papel usado pela máquina de estados (a equipe age como mediador)."""
    return _PAPEL_DAS_REGRAS[usuario.papel]
