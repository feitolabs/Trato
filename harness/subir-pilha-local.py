"""Pilha LOCAL para testar o app de verdade, sem tocar no Supabase nem no Stripe reais.

Uso:  backend/.venv/Scripts/python harness/subir-pilha-local.py [--porta 8000]

O que sobe (tudo descartável, some ao fechar):
  * Postgres embutido (pgserver) com as migrations reais e os privilégios "reais" do Supabase;
  * o backend DE PRODUÇÃO (`criar_app_da_config`, TRATO_PERSISTENCIA=postgres, pagamento "fake");
  * um login compatível com o Supabase Auth (`/auth/v1/...`) que emite JWT HS256 que o backend valida.

Contas de teste (só valem neste servidor): cliente@teste.trato.local, profissional@teste.trato.local,
admin@teste.trato.local, financeiro@teste.trato.local. Senha de teste: veja SENHA_TESTE (valor público de mentira).

App no emulador Android (HTTP liberado só no manifest de debug):
  flutter build apk --debug --dart-define=TRATO_API_URL=http://10.0.2.2:8000 \
     --dart-define=SUPABASE_URL=http://10.0.2.2:8000 --dart-define=SUPABASE_ANON_KEY=anon-local
"""

from __future__ import annotations

import argparse
import os
import secrets
import sys
import tempfile
import time
import uuid
from pathlib import Path

import jwt
from fastapi import Request
from fastapi.responses import JSONResponse, Response

RAIZ = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(RAIZ / "backend" / "src"))
sys.path.insert(0, str(RAIZ / "backend"))

SENHA_TESTE = "senha-de-teste-local"  # valor público de mentira: só vale neste servidor
DOMINIO = "teste.trato.local"
CONTAS = {  # papel -> nome
    "cliente": "Cliente Teste",
    "profissional": "Profissional Teste",
    "admin": "Admin Teste",
    "financeiro": "Financeiro Teste",
}
CATEGORIAS = (  # as do piloto (decisão D16)
    ("Limpeza residencial", "limpeza-residencial", 30),
    ("Montagem de móveis", "montagem-de-moveis", 30),
    ("Pintura de interiores", "pintura-de-interiores", 90),
)
PARAMETROS = (  # valores de TESTE (não são decisão de taxa)
    ("adiantamento_bps", "bps", 0),
    ("prazo_pagamento_pendente_horas", "horas", 2),
    ("validade_pedido_horas", "horas", 48),
    ("prazo_confirmacao_cliente_horas", "horas", 48),
    ("tolerancia_comparecimento_horas", "horas", 1),
    ("prazo_resposta_disputa_horas", "horas", 48),
    ("prazo_decisao_disputa_dias_uteis", "dias_uteis", 5),
    ("prazo_congelar_disputa_horas", "horas", 72),
    ("garantia_retrabalho_dias_padrao", "dias", 30),
    ("prazo_retrabalho_atendimento_dias", "dias", 7),
)

CONTAS_AUTH: dict[str, dict] = {}  # email -> {id, senha}


# O Postgres local dos testes aplica só um subconjunto das migrations. O backend de produção usa
# as tabelas e colunas destas também (recusas de pedido, instrução de pagamento, notificações...).
MIGRATIONS_EXTRAS = (
    "notificacoes_dispositivos_agendador",
    "ordens_estorno",
    "pedido_recusas",
    "upload_destino_portfolio",
    "pagamentos_instrucao",
    "login_cpf_telefone",
    "admin_sugestoes_completas",
)


def aplicar_migrations_extras(banco_local) -> None:
    pasta = RAIZ / "supabase" / "migrations"
    with banco_local.admin() as con:  # o auth.users real tem estas colunas; o stub só tinha o id
        con.execute("alter table auth.users add column if not exists email text, add column if not exists phone text, "
            "add column if not exists raw_user_meta_data jsonb not null default '{}'::jsonb")
    for chave in MIGRATIONS_EXTRAS:
        arquivo = next(pasta.glob(f"*{chave}.sql"), None)
        if arquivo is None:
            print(f"  migration extra NÃO ENCONTRADA: {chave}", flush=True)
            continue
        try:
            with banco_local.admin() as con:
                con.execute(arquivo.read_text(encoding="utf-8"))
            print(f"  migration extra aplicada: {chave}", flush=True)
        except Exception as erro:  # noqa: BLE001 - segue sem ela e avisa
            print(f"  migration extra FALHOU ({chave}): {str(erro).splitlines()[0]}", flush=True)


def semear(banco_local) -> None:
    with banco_local.admin() as con:
        ids = {}
        for papel, nome in CONTAS.items():
            uid = str(uuid.uuid4())
            ids[papel] = uid
            con.execute("insert into auth.users (id, email) values (%s, %s)", (uid, f"{papel}@{DOMINIO}"))
            con.execute("insert into public.usuarios (id, nome) values (%s, %s)", (uid, nome))
            CONTAS_AUTH[f"{papel}@{DOMINIO}"] = {"id": uid, "senha": SENHA_TESTE}
        con.execute(
            "insert into public.perfis_profissional (usuario_id, status, nivel_verificacao) "
            "values (%s, 'aprovado', 'verificado')",
            (ids["profissional"],),
        )
        con.execute("insert into public.equipe (usuario_id, papel) values (%s, 'administrador')", (ids["admin"],))
        con.execute("insert into public.equipe (usuario_id, papel) values (%s, 'financeiro')", (ids["financeiro"],))
        cidade = con.execute(
            "insert into public.cidades (nome, uf, ativa) values ('Belo Horizonte', 'MG', true) returning id"
        ).fetchone()[0]
        for nome, slug, garantia in CATEGORIAS:
            cat = con.execute(
                "insert into public.categorias (nome, slug, garantia_retrabalho_dias, ativa) "
                "values (%s, %s, %s, true) returning id",
                (nome, slug, garantia),
            ).fetchone()[0]
            con.execute(
                "insert into public.profissional_categorias (profissional_id, categoria_id) values (%s, %s)",
                (ids["profissional"], cat),
            )
        con.execute(
            "insert into public.profissional_regioes (profissional_id, cidade_id) values (%s, %s)",
            (ids["profissional"], cidade),
        )
        versao = con.execute(
            "insert into public.config_versoes (criada_por, motivo) values (%s, 'config de TESTE local') returning id",
            (ids["admin"],),
        ).fetchone()[0]
        for chave, unidade, valor in PARAMETROS:
            con.execute(
                "insert into public.config_definicoes (chave, descricao, unidade) values (%s, %s, %s) "
                "on conflict (chave) do nothing",
                (chave, chave, unidade),
            )
            con.execute(
                "insert into public.config_parametros (versao_id, chave, valor) values (%s, %s, %s)",
                (versao, chave, valor),
            )
        con.execute(
            "insert into public.config_faixas_taxa (versao_id, de_centavos, ate_centavos, taxa_bps) "
            "values (%s, 0, null, 750)",
            (versao,),
        )
        con.execute(
            "update public.config_versoes set status='aprovada', aprovada_por=%s where id=%s",
            (ids["financeiro"], versao),
        )
        con.execute("update public.config_versoes set status='vigente' where id=%s", (versao,))


def instalar_auth_local(app, segredo: str, emissor: str) -> None:
    """Login compatível com o Supabase Auth: o suficiente para o app e para o backend."""

    def _usuario(email: str, conta: dict) -> dict:
        return {
            "id": conta["id"], "aud": "authenticated", "role": "authenticated", "email": email,
            "email_confirmed_at": "2026-11-01T00:00:00Z", "phone": "", "app_metadata": {"provider": "email"},
            "user_metadata": {}, "identities": [], "created_at": "2026-11-01T00:00:00Z",
            "updated_at": "2026-11-01T00:00:00Z",
        }

    def _sessao(email: str, conta: dict) -> dict:
        agora = int(time.time())
        carga = {"sub": conta["id"], "aud": "authenticated", "role": "authenticated", "email": email,
                 "iss": emissor, "iat": agora, "exp": agora + 3600, "session_id": str(uuid.uuid4())}
        return {
            "access_token": jwt.encode(carga, segredo, "HS256"), "token_type": "bearer", "expires_in": 3600,
            "expires_at": agora + 3600, "refresh_token": f"r-{conta['id']}", "user": _usuario(email, conta),
        }

    @app.post("/auth/v1/token")
    async def token(request: Request):
        corpo = await request.json()
        if request.query_params.get("grant_type") == "refresh_token":
            for email, conta in CONTAS_AUTH.items():
                if corpo.get("refresh_token") == f"r-{conta['id']}":
                    return _sessao(email, conta)
            return JSONResponse({"error": "invalid_grant", "error_description": "Refresh inválido"}, 400)
        email = str(corpo.get("email", "")).strip().lower()
        conta = CONTAS_AUTH.get(email)
        if conta is None or conta["senha"] != corpo.get("password"):
            return JSONResponse({"error": "invalid_grant", "error_description": "Invalid login credentials"}, 400)
        return _sessao(email, conta)

    @app.post("/auth/v1/signup")
    async def signup(request: Request):
        corpo = await request.json()
        email = str(corpo.get("email", "")).strip().lower()
        if email in CONTAS_AUTH:
            return JSONResponse({"code": 422, "error_code": "user_already_exists", "msg": "User already registered"}, 422)
        conta = {"id": str(uuid.uuid4()), "senha": corpo.get("password", "")}
        app.state.banco_local_admin(conta["id"])
        CONTAS_AUTH[email] = conta
        return _sessao(email, conta)

    @app.get("/auth/v1/user")
    async def usuario(request: Request):
        try:
            carga = jwt.decode(request.headers.get("authorization", "")[7:], segredo, algorithms=["HS256"], audience="authenticated")
        except Exception:
            return JSONResponse({"msg": "invalid JWT"}, 401)
        for email, conta in CONTAS_AUTH.items():
            if conta["id"] == carga["sub"]:
                return _usuario(email, conta)
        return JSONResponse({"msg": "user not found"}, 404)

    @app.post("/auth/v1/logout")
    async def sair():
        return Response(status_code=204)


def instalar_storage_local(app) -> None:
    """Storage de mentira (em memória), com a mesma API que o backend usa no Supabase:
    assinar envio, receber o arquivo, ler, gravar por cima e apagar."""
    arquivos: dict[tuple[str, str], bytes] = {}

    @app.post("/storage/v1/object/upload/sign/{bucket}/{caminho:path}")
    async def assinar_envio(bucket: str, caminho: str):
        return {"url": f"/object/upload/sign/{bucket}/{caminho}?token=token-local"}

    @app.post("/storage/v1/object/sign/{bucket}/{caminho:path}")
    async def assinar_leitura(bucket: str, caminho: str):
        return {"signedURL": f"/object/{bucket}/{caminho}?token=leitura-local"}

    @app.put("/storage/v1/object/upload/sign/{bucket}/{caminho:path}")
    async def receber_envio(bucket: str, caminho: str, request: Request):
        arquivos[(bucket, caminho)] = await request.body()
        return {"Key": f"{bucket}/{caminho}"}

    @app.put("/storage/v1/object/{bucket}/{caminho:path}")
    async def gravar(bucket: str, caminho: str, request: Request):
        arquivos[(bucket, caminho)] = await request.body()
        return {"Key": f"{bucket}/{caminho}"}

    @app.get("/storage/v1/object/{bucket}/{caminho:path}")
    async def ler(bucket: str, caminho: str):
        dados = arquivos.get((bucket, caminho))
        if dados is None:
            return JSONResponse({"error": "not_found", "message": "Object not found"}, 404)
        return Response(content=dados, media_type="application/octet-stream")

    @app.delete("/storage/v1/object/{bucket}/{caminho:path}")
    async def apagar(bucket: str, caminho: str):
        arquivos.pop((bucket, caminho), None)
        return Response(status_code=200)


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--porta", type=int, default=8000)
    ap.add_argument("--host", default="0.0.0.0")  # noqa: S104 (o emulador acessa por 10.0.2.2)
    args = ap.parse_args()

    from tests.integracao.pg_local import BancoLocal

    pasta = Path(tempfile.mkdtemp(prefix="trato_pilha_"))
    local = BancoLocal(pasta)
    aplicar_migrations_extras(local)
    semear(local)

    segredo = secrets.token_hex(32)
    os.environ.update({
        "TRATO_AMBIENTE": "desenvolvimento", "TRATO_PERSISTENCIA": "postgres",
        "DATABASE_URL": local.uri, "TRATO_BANCO_PAPEL": "service_role",
        "SUPABASE_JWT_SECRET": segredo, "SUPABASE_URL": f"http://127.0.0.1:{args.porta}",
        "TRATO_CODIGO_SEGREDO": secrets.token_hex(16), "TRATO_PROVEDOR_PAGAMENTO": "fake",
        # Valor de mentira: só liga o Storage local abaixo (o real nunca passa por aqui).
        "SUPABASE_SERVICE_ROLE_KEY": "chave-de-servico-local-de-teste",
    })
    os.chdir(pasta)  # nada de .env real por perto
    from trato.api.fabrica import criar_app_da_config

    app = criar_app_da_config()

    def criar_usuario_no_banco(uid: str) -> None:
        with local.admin() as con:
            con.execute("insert into auth.users (id) values (%s)", (uid,))

    app.state.banco_local_admin = criar_usuario_no_banco
    instalar_auth_local(app, segredo, f"http://127.0.0.1:{args.porta}/auth/v1")
    instalar_storage_local(app)

    print(f"Pilha LOCAL em http://127.0.0.1:{args.porta} (Postgres descartável em {pasta})", flush=True)
    print(f"Contas: <papel>@{DOMINIO} com a senha de teste do script ({', '.join(CONTAS)})", flush=True)
    import uvicorn

    uvicorn.run(app, host=args.host, port=args.porta, log_level="info")


if __name__ == "__main__":
    main()
