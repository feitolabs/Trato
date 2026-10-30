"""Sobe o backend do Trato EM MEMÓRIA, com dados de exemplo, para o painel admin conversar de verdade.

Uso:  python harness/subir-backend-teste.py [--porta 8765] [--host 127.0.0.1]

- Nada de banco real, nenhuma chave real. O login é um Supabase Auth de mentira (`/auth/v1/token`)
  servido pelo próprio processo: e-mail `<papel>@teste.trato.local` + a senha de teste abaixo.
- Dados: uma conta de equipe por papel, 2 verificações pendentes, 2 disputas abertas (uma dentro da
  alçada do mediador, outra acima), pagamentos (um sem pedido = divergente), configuração vigente + um
  rascunho, e a auditoria que o próprio seed gera.
- Use o `ADMIN_SUPABASE_URL` igual a `ADMIN_API_URL` (o mesmo servidor responde as duas coisas).

Também é importado pelos testes (`backend/tests/integracao_painel/`): `montar()` devolve o app pronto.
"""

from __future__ import annotations

import argparse
import sys
from dataclasses import dataclass
from datetime import UTC, datetime, timedelta
from pathlib import Path

RAIZ = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(RAIZ / "backend" / "src"))

from fastapi import FastAPI, HTTPException, Request  # noqa: E402

from trato import disputas  # noqa: E402
from trato.api import Contexto, criar_app  # noqa: E402
from trato.api.admin import AdminContexto, instalar_admin  # noqa: E402
from trato.api.admin.memoria import (  # noqa: E402
    AuditoriaEmMemoria,
    ConfigAdminEmMemoria,
    EquipeEmMemoria,
    PedidosAdminEmMemoria,
    UsuariosAdminEmMemoria,
    VerificacoesAdminEmMemoria,
)
from trato.api.admin.papeis import PapelEquipe  # noqa: E402
from trato.api.admin.repositorios import (  # noqa: E402
    DadosPessoaisAdmin,
    DefinicaoConfig,
    DocumentoAdmin,
    FaixaTaxa,
    MembroEquipe,
    ParametroConfig,
    UsuarioAdmin,
    VerificacaoAdmin,
)
from trato.api.auth import PapelUsuario, ProvedorAuthFalso, Usuario  # noqa: E402
from trato.api.memoria import (  # noqa: E402
    ConfigEmMemoria,
    ContratosEmMemoria,
    DisputasEmMemoria,
    EventosWebhookEmMemoria,
    GarantiasEmMemoria,
    LedgerEmMemoria,
    OrcamentosEmMemoria,
    PedidosEmMemoria,
)
from trato.api.repositorios import ConfigApi, Contrato, EventoWebhook  # noqa: E402
from trato.disputas import ConfigDisputa  # noqa: E402
from trato.financeiro.ledger import registrar_cobranca  # noqa: E402
from trato.garantias import ConfigGarantia  # noqa: E402
from trato.pedidos.estados import (  # noqa: E402
    Acao,
    Ator,
    Estado,
    Evento,
    MotivoDisputa,
    Pedido,
    PrazosPedido,
    ProvaDisputa,
)
from trato.pedidos.estados import Papel as PapelPedido  # noqa: E402

DOMINIO = "teste.trato.local"
SENHA_TESTE = "senha-de-teste-local"  # valor público de mentira: só vale neste servidor
AGORA = datetime(2026, 10, 29, 12, 0, tzinfo=UTC)

# alçada em centavos por papel (vazia = 0, tudo vai para a segunda pessoa)
ALCADAS = {"mediador": 200_000, "lider_suporte": 500_000, "administrador": 10_000_000}

DEFINICOES = (
    DefinicaoConfig("adiantamento_bps", "Adiantamento", "bps", 0, 10_000, ("global",), True),
    DefinicaoConfig("prazo_resposta_disputa_horas", "Resposta", "horas", 1, 240),
    DefinicaoConfig("prazo_decisao_disputa_dias_uteis", "Decisão", "dias_uteis", 1, 30),
    DefinicaoConfig("prazo_congelar_disputa_horas", "Congelar", "horas", 1, 720),
)
BASE_PARAMETROS = (
    ParametroConfig("adiantamento_bps", 3000),
    ParametroConfig("prazo_resposta_disputa_horas", 48),
    ParametroConfig("prazo_decisao_disputa_dias_uteis", 5),
    ParametroConfig("prazo_congelar_disputa_horas", 72),
)
BASE_FAIXAS = (FaixaTaxa(0, 100_000, 750), FaixaTaxa(100_000, None, 600))  # valores de TESTE


class TaxaFalsa:
    def calcular(self, valor_centavos: int) -> int:
        return valor_centavos * 750 // 10_000


class AssinadorFalso:
    """URL assinada de mentira, curta, sem nenhum caminho do storage."""

    def __init__(self) -> None:
        self.chamadas: list[tuple[str, int]] = []

    def assinar(self, caminho: str, segundos: int) -> str:
        self.chamadas.append((caminho, segundos))
        return f"https://storage.exemplo.test/assinada?exp={segundos}&assinatura=abc"


@dataclass
class Ambiente:
    app: FastAPI
    contexto: Contexto
    admin: AdminContexto
    assinador: AssinadorFalso


def email_de(papel: str) -> str:
    return f"{papel}@{DOMINIO}"


def token_de(papel: str) -> str:
    return f"t-{papel}"


def _semear_disputa(ctx: Contexto, pedido_id: str, valor: int, cliente: Usuario, prof: Usuario) -> None:
    pedido = Pedido(
        id=pedido_id,
        cliente_id=cliente.id,
        aberto_em=AGORA - timedelta(days=3),
        estado=Estado.EM_DISPUTA,
        profissional_id=prof.id,
        orcamento_id=f"orc-{pedido_id}",
        referencia_pagamento=f"pi_teste_{pedido_id}",
        codigo_inicio="1234",
        codigo_conclusao="9876",
        concluido_em=AGORA - timedelta(days=1),
        estado_antes_da_disputa=Estado.EM_CONFIRMACAO,
    )
    prova = ProvaDisputa(MotivoDisputa.MAL_FEITO, "Parede manchada")
    evento = Evento(
        pedido_id, Acao.ABRIR_DISPUTA, Estado.EM_CONFIRMACAO, Estado.EM_DISPUTA,
        Ator(PapelPedido.CLIENTE, cliente.id), AGORA - timedelta(hours=2), prova,
    )  # fmt: skip
    ctx.pedidos.salvar(pedido, evento)
    ctx.contratos.salvar(
        Contrato(pedido_id, f"orc-{pedido_id}", prof.id, valor, "pintura", taxa_bps_aplicada=750)
    )
    registrar_cobranca(ctx.ledger.livro, pedido_id, valor, f"cob-{pedido_id}", AGORA)
    ctx.eventos_webhook.registrar(
        EventoWebhook("stripe", f"evt_{pedido_id}", "payment.confirmed",
                      {"pedido_id": pedido_id, "referencia": f"pi_teste_{pedido_id}", "valor_centavos": valor},
                      AGORA - timedelta(days=2))
    )  # fmt: skip
    cfg = ctx.config.carregar().disputas
    d = disputas.abrir(
        disputas.Ator.CLIENTE, valor, disputas.Motivo.MAL_FEITO,
        AGORA - timedelta(days=1), AGORA - timedelta(hours=2), cfg,
    )  # fmt: skip
    d = d.responder(disputas.Ator.PROFISSIONAL, AGORA - timedelta(hours=1))
    ctx.disputas.salvar(pedido_id, d)


def _instalar_login_falso(app: FastAPI, papeis_por_email: dict[str, str]) -> None:
    """Supabase Auth de mentira: só o suficiente para `POST /auth/v1/token?grant_type=password`."""

    @app.post("/auth/v1/token", include_in_schema=False)
    async def token(request: Request) -> dict[str, object]:
        corpo = await request.json()
        papel = papeis_por_email.get(str(corpo.get("email", "")).strip().lower())
        if papel is None or corpo.get("password") != SENHA_TESTE:
            raise HTTPException(400, "invalid_grant")
        return {"access_token": token_de(papel), "token_type": "bearer", "expires_in": 3600}


def montar() -> Ambiente:
    relogio = lambda: AGORA  # noqa: E731 - relógio fixo: prazos de exemplo previsíveis
    config = ConfigApi(
        prazos_pedido=PrazosPedido(
            receber_orcamentos=timedelta(days=3),
            pagamento=timedelta(hours=24),
            tolerancia_comparecimento=timedelta(hours=1),
            confirmacao_cliente=timedelta(days=7),
        ),
        disputas=ConfigDisputa(
            prazo_resposta_horas=48, prazo_decisao_dias_uteis=5, prazo_congelar_repasse_horas=72
        ),
        garantias=ConfigGarantia(garantia_dias_padrao=30, prazo_atendimento_dias=7),
    )
    membros = [
        MembroEquipe(f"eq-{p.value}", p, alcada_centavos=ALCADAS.get(p.value)) for p in PapelEquipe
    ]
    membros.append(MembroEquipe("eq-administrador2", PapelEquipe.ADMINISTRADOR, alcada_centavos=10_000_000))
    papeis_por_email = {email_de(m.usuario_id.removeprefix("eq-")): m.usuario_id.removeprefix("eq-") for m in membros}
    cliente, cliente2 = Usuario("cli-1", PapelUsuario.CLIENTE), Usuario("cli-2", PapelUsuario.CLIENTE)
    prof, prof2 = Usuario("pro-1", PapelUsuario.PROFISSIONAL), Usuario("pro-2", PapelUsuario.PROFISSIONAL)
    tokens = {
        token_de(m.usuario_id.removeprefix("eq-")): Usuario(m.usuario_id, PapelUsuario.EQUIPE)
        for m in membros
    }
    contexto = Contexto(
        auth=ProvedorAuthFalso(tokens),
        pedidos=PedidosEmMemoria(),
        orcamentos=OrcamentosEmMemoria(),
        contratos=ContratosEmMemoria(),
        ledger=LedgerEmMemoria(),
        disputas=DisputasEmMemoria(),
        garantias=GarantiasEmMemoria(),
        eventos_webhook=EventosWebhookEmMemoria(),
        config=ConfigEmMemoria(config),
        agora=relogio,
        taxa=TaxaFalsa(),
    )
    auditoria = AuditoriaEmMemoria(relogio)
    usuarios = UsuariosAdminEmMemoria(auditoria)
    usuarios.adicionar(
        UsuarioAdmin("cli-1", "Maria Cliente", "ativo", "cliente"),
        DadosPessoaisAdmin("123.456.789-09", "+5531999990000", "1990-01-01", None, None),
    )
    usuarios.adicionar(UsuarioAdmin("cli-2", "Carlos Cliente", "ativo", "cliente"))
    usuarios.adicionar(UsuarioAdmin("pro-1", "João Pintor", "ativo", "profissional"))
    usuarios.adicionar(UsuarioAdmin("pro-2", "Ana Eletricista", "ativo", "profissional"))
    verificacoes = VerificacoesAdminEmMemoria(auditoria, relogio)
    for vid, pid, nome, cpf in (
        ("ver-1", "pro-1", "João Pintor", "***.***.***-09"),
        ("ver-2", "pro-2", "Ana Eletricista", "***.***.***-55"),
    ):
        verificacoes.adicionar(
            VerificacaoAdmin(
                vid, pid, nome, "verificado", "enviada", AGORA - timedelta(days=1), cpf_mascarado=cpf,
                documentos=(DocumentoAdmin(f"{vid}-d1", "documento_frente"), DocumentoAdmin(f"{vid}-d2", "selfie")),
            ),  # fmt: skip
            {f"{vid}-d1": f"bucket-privado/{vid}/frente.jpg", f"{vid}-d2": f"bucket-privado/{vid}/selfie.jpg"},
        )
    config_admin = ConfigAdminEmMemoria(auditoria, DEFINICOES, relogio)
    base = config_admin.criar_rascunho("eq-financeiro", "Versão inicial de exemplo", BASE_PARAMETROS, BASE_FAIXAS, None, False)
    config_admin.enviar_para_aprovacao(base.id, "eq-financeiro", "Pronta")
    config_admin.aprovar(base.id, "eq-administrador", "Conferi")
    config_admin.publicar(base.id, "eq-administrador", "No ar", AGORA)
    proposta = tuple(
        ParametroConfig(p.chave, 24 if p.chave == "prazo_resposta_disputa_horas" else p.valor)
        for p in BASE_PARAMETROS
    )
    config_admin.criar_rascunho("eq-financeiro", "Rascunho: prazo de resposta menor", proposta, BASE_FAIXAS, None, False)
    assinador = AssinadorFalso()
    admin = AdminContexto(
        equipe=EquipeEmMemoria(membros),
        verificacoes=verificacoes,
        usuarios=usuarios,
        pedidos=PedidosAdminEmMemoria(contexto, usuarios),
        config=config_admin,
        auditoria=auditoria,
        assinador=assinador,
    )
    _semear_disputa(contexto, "ped-1", 100_000, cliente, prof)  # dentro da alçada do mediador
    _semear_disputa(contexto, "ped-2", 300_000, cliente2, prof2)  # acima: pede segunda pessoa
    registrar_cobranca(contexto.ledger.livro, "ped-orfao", 5_000, "cob-orfao", AGORA)  # divergente
    app = criar_app(contexto)
    instalar_admin(app, admin)
    _instalar_login_falso(app, papeis_por_email)
    # O painel (Flutter Web) roda em outra porta: sem CORS o navegador bloqueia. Só origens locais.
    from starlette.middleware.cors import CORSMiddleware

    app.add_middleware(
        CORSMiddleware,
        allow_origins=[f"http://{h}:{p}" for h in ("127.0.0.1", "localhost") for p in (8080, 8081)],
        allow_methods=["GET", "POST", "DELETE", "OPTIONS"],
        allow_headers=["Authorization", "Content-Type", "apikey"],
    )
    return Ambiente(app, contexto, admin, assinador)


def main() -> None:
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("--porta", type=int, default=8765)
    p.add_argument("--host", default="127.0.0.1")
    args = p.parse_args()
    import uvicorn

    url = f"http://{args.host}:{args.porta}"
    print(f"Backend de TESTE (memória, sem chaves reais) em {url}")
    print(f"Painel: --dart-define=ADMIN_MODO=api --dart-define=ADMIN_API_URL={url} "
          f"--dart-define=ADMIN_SUPABASE_URL={url} --dart-define=ADMIN_SUPABASE_ANON_KEY=anon-de-teste")
    print(f"Contas: <papel>@{DOMINIO}  senha de teste: {SENHA_TESTE}", flush=True)
    uvicorn.run(montar().app, host=args.host, port=args.porta, log_level="warning")


if __name__ == "__main__":
    main()
