"""Teste ponta a ponta no Supabase REAL (dados `teste_*`, e-mails @example.test, Stripe em modo teste).

Uso (backend já no ar em 127.0.0.1:8000 com TRATO_PERSISTENCIA=postgres):
    python harness/teste_real_fluxo.py setup     # contagens iniciais + usuários + equipe + config de TESTE + pedido-base
    python harness/teste_real_fluxo.py fluxo     # pedido -> orçamento -> aceite -> cobrança -> webhook -> ledger -> idempotência
    python harness/teste_real_fluxo.py limpeza   # imprime o SQL de limpeza (NÃO executa nada)

Lê o `.env` da raiz; nunca imprime chaves, senhas nem tokens. Estado (ids) fica em TRATO_ESTADO_TESTE
(padrão: pasta temporária), fora do git.
"""

from __future__ import annotations

import hashlib
import hmac
import json
import os
import re
import secrets
import sys
import time
import uuid
from datetime import UTC, datetime
from decimal import Decimal
from pathlib import Path

RAIZ = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(RAIZ / "backend" / "src"))

import httpx  # noqa: E402
import psycopg  # noqa: E402

for linha in (RAIZ / ".env").read_text(encoding="utf-8").splitlines():
    m = re.match(r"^([A-Z0-9_]+)=(.*)$", linha.strip())
    if m:
        os.environ.setdefault(m[1], m[2].strip("\"'"))

API = os.environ.get("TRATO_API_URL", "http://127.0.0.1:8000")
SUPA = os.environ["SUPABASE_URL"].rstrip("/")
ESTADO = Path(os.environ.get("TRATO_ESTADO_TESTE", Path(os.environ.get("TEMP", ".")) / "trato_teste_real.json"))
PAPEIS = {
    "cliente": "teste_cliente",
    "profissional": "teste_profissional",
    "admin": "teste_admin",
    "financeiro": "teste_financeiro",
}
PARAMETROS = (  # valores de TESTE (não são decisão do João)
    ("adiantamento_bps", "bps", 3000),
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
FAIXAS = ((0, None, 750),)  # TESTE: 7,5% para qualquer valor

resultados: list[tuple[str, bool, str]] = []


def ok(nome: str, condicao: bool, detalhe: str = "") -> None:
    resultados.append((nome, bool(condicao), detalhe))
    print(f"{'OK    ' if condicao else 'FALHOU'} {nome}{(' — ' + detalhe) if detalhe else ''}")


def banco():
    return psycopg.connect(os.environ["DATABASE_URL"], connect_timeout=20)


def tabelas_publicas(con) -> dict[str, int]:
    nomes = [r[0] for r in con.execute("select tablename from pg_tables where schemaname='public' order by 1")]
    return {n: con.execute(f'select count(*) from public."{n}"').fetchone()[0] for n in nomes}


def admin_auth(metodo: str, caminho: str, **kw) -> httpx.Response:
    chave = os.environ["SUPABASE_SERVICE_ROLE_KEY"]
    return httpx.request(metodo, f"{SUPA}/auth/v1{caminho}", headers={"apikey": chave, "Authorization": f"Bearer {chave}"}, timeout=30, **kw)


def setup() -> None:
    if ESTADO.exists():
        sys.exit(f"Já existe estado de teste em {ESTADO}. Rode `limpeza` antes de refazer.")
    estado: dict = {"iniciado_em": datetime.now(UTC).isoformat(), "usuarios": {}, "senhas": {}}
    with banco() as con:
        estado["contagens_antes"] = tabelas_publicas(con)
    ESTADO.write_text(json.dumps(estado), encoding="utf-8")  # grava já: se algo falhar, a limpeza sabe o que existe
    for papel, nome in PAPEIS.items():
        senha = secrets.token_urlsafe(24)
        r = admin_auth("POST", "/admin/users", json={"email": f"{nome}@example.test", "password": senha, "email_confirm": True,
                                                       "user_metadata": {"teste": True}})
        r.raise_for_status()
        estado["usuarios"][papel] = r.json()["id"]
        estado["senhas"][papel] = senha
        ESTADO.write_text(json.dumps(estado), encoding="utf-8")
    ids = estado["usuarios"]
    with banco() as con, con.transaction():
        for papel, nome in PAPEIS.items():
            con.execute("insert into public.usuarios (id, nome) values (%s, %s)", (ids[papel], nome))
        con.execute("insert into public.perfis_profissional (usuario_id) values (%s)", (ids["profissional"],))
        con.execute("update public.perfis_profissional set status='aprovado', nivel_verificacao='verificado' where usuario_id=%s", (ids["profissional"],))
        con.execute("insert into public.equipe (usuario_id, papel) values (%s,'administrador')", (ids["admin"],))
        con.execute("insert into public.equipe (usuario_id, papel) values (%s,'financeiro')", (ids["financeiro"],))
        cidade = con.execute("insert into public.cidades (nome, uf, ativa) values ('teste_Cidade','MG',true) returning id").fetchone()[0]
        cat = con.execute("insert into public.categorias (nome, slug, garantia_retrabalho_dias) values ('teste_Pintura','teste-pintura',90) returning id").fetchone()[0]
        perg = con.execute("insert into public.categoria_perguntas (categoria_id, texto, tipo) values (%s,'teste_Quantos cômodos?','numero') returning id", (cat,)).fetchone()[0]
        versao = con.execute("insert into public.config_versoes (criada_por, motivo) values (%s,'teste_ config de TESTE do fluxo real (nao e decisao de taxa)') returning id", (ids["admin"],)).fetchone()[0]
        for chave, unidade, valor in PARAMETROS:
            con.execute("insert into public.config_definicoes (chave, descricao, unidade) values (%s,%s,%s) on conflict (chave) do nothing", (chave, f"teste_ {chave}", unidade))
            con.execute("insert into public.config_parametros (versao_id, chave, valor) values (%s,%s,%s)", (versao, chave, valor))
        for de, ate, bps in FAIXAS:
            con.execute("insert into public.config_faixas_taxa (versao_id, de_centavos, ate_centavos, taxa_bps) values (%s,%s,%s,%s)", (versao, de, ate, bps))
        con.execute("update public.config_versoes set status='aprovada', aprovada_por=%s where id=%s", (ids["financeiro"], versao))
        con.execute("update public.config_versoes set status='vigente' where id=%s", (versao,))
    estado |= {"cidade": str(cidade), "categoria": str(cat), "pergunta": str(perg), "versao": str(versao)}
    ESTADO.write_text(json.dumps(estado), encoding="utf-8")
    print("setup concluído: 4 usuários, equipe, cidade/categoria de teste e config de teste vigente.")


def token(estado: dict, papel: str) -> dict[str, str]:
    r = httpx.post(f"{SUPA}/auth/v1/token?grant_type=password", headers={"apikey": os.environ["SUPABASE_ANON_KEY"]},
                   json={"email": f"{PAPEIS[papel]}@example.test", "password": estado["senhas"][papel]}, timeout=30)
    r.raise_for_status()
    return {"Authorization": f"Bearer {r.json()['access_token']}"}


def assinar(corpo: bytes, segredo: str, quando: int | None = None) -> str:
    t = quando or int(time.time())
    v1 = hmac.new(segredo.encode(), f"{t}.".encode() + corpo, hashlib.sha256).hexdigest()
    return f"t={t},v1={v1}"


def fluxo() -> None:
    estado = json.loads(ESTADO.read_text(encoding="utf-8"))
    ids = estado["usuarios"]
    cliente, prof = token(estado, "cliente"), token(estado, "profissional")
    c = httpx.Client(base_url=API, timeout=60)
    r = c.get("/v1/me", headers=cliente)
    ok("login real (Supabase Auth) + GET /v1/me", r.status_code == 200, f"status {r.status_code}")
    r = c.post("/v1/pedidos", headers=cliente, json={
        "categoria_id": estado["categoria"], "cidade_id": estado["cidade"], "titulo": "teste_ Pintar a sala",
        "descricao": "teste_ pedido do fluxo real", "bairro": "Centro",
        "respostas": [{"pergunta_id": estado["pergunta"], "resposta": 3}],
        "endereco": {"logradouro": "Rua A", "numero": "10", "lat": -19.9, "lng": -43.9}})
    ok("cliente cria pedido", r.status_code == 201, f"status {r.status_code} {'' if r.status_code == 201 else r.text[:200]}")
    if r.status_code != 201:
        return
    pedido = r.json()["id"]
    estado.setdefault("pedidos", []).append(pedido)
    ESTADO.write_text(json.dumps(estado), encoding="utf-8")

    from trato.api.fabrica import criar_contexto_postgres
    from trato.config import obter_config
    from trato.persistencia.conexao import Banco
    from trato.persistencia.orcamentos import ItemOrcamento

    cfg = obter_config()
    ctx = criar_contexto_postgres(Banco(cfg.database_url.get_secret_value(), papel=cfg.trato_banco_papel), cfg)
    orc = ctx.orcamentos.enviar(pedido_id=pedido, profissional_id=ids["profissional"], agora=datetime.now(UTC), prazo_execucao_dias=5, garantia_dias=90,
                                itens=[ItemOrcamento("horas", "teste_ Mão de obra", Decimal("1"), 10_000)])
    r = c.get(f"/v1/pedidos/{pedido}/orcamentos", headers=cliente)
    ok("cliente vê o orçamento (valor 10000 centavos)", r.status_code == 200 and r.json()[0]["valor_centavos"] == 10_000, f"status {r.status_code}")
    r = c.post("/v1/orcamentos/resumo", headers=prof, json={"valor_centavos": 10_000})
    ok("resumo de taxa vem do backend (7,5% = 750)", r.status_code == 200 and r.json().get("taxa_centavos") == 750, r.text[:120])
    r = c.post(f"/v1/pedidos/{pedido}/acoes/aceitar_orcamento", headers=cliente, json={"prova": {"orcamento_id": orc}})
    ok("cliente aceita o orçamento", r.status_code == 200, f"status {r.status_code} {'' if r.status_code == 200 else r.text[:200]}")
    r = c.post(f"/v1/contratos/{pedido}/cobranca", headers=cliente, json={"meio": "cartao"})
    ok("cobrança criada no Stripe (PaymentIntent de teste)", r.status_code == 201, f"status {r.status_code} {'' if r.status_code == 201 else r.text[:200]}")
    if r.status_code != 201:
        return
    pi = r.json()["cobranca_id"]
    estado["pi"] = pi
    ESTADO.write_text(json.dumps(estado), encoding="utf-8")
    r2 = c.post(f"/v1/contratos/{pedido}/cobranca", headers=cliente, json={"meio": "cartao"})
    ok("repetir a cobrança devolve a mesma (idempotente)", r2.status_code in (200, 201) and r2.json().get("cobranca_id") == pi)
    r = c.get(f"/v1/contratos/{pedido}/pagamento", headers=cliente)
    ok("D13: antes do webhook, pago = false", r.status_code == 200 and r.json()["pago"] is False, str(r.json().get("estado_pagamento")))

    sk = os.environ["STRIPE_SECRET_KEY"]
    r = httpx.post(f"https://api.stripe.com/v1/payment_intents/{pi}/confirm", auth=(sk, ""), timeout=60,
                   data={"payment_method": "pm_card_visa", "return_url": "https://example.test/retorno"})
    ok("Stripe: cartão 4242 confirmado (pm_card_visa)", r.status_code == 200 and r.json().get("status") == "succeeded", f"status Stripe {r.json().get('status')}")
    valor = r.json().get("amount_received") or r.json().get("amount")
    # Se o `stripe listen` estiver rodando, o webhook real chega sozinho. Espera até 15 s.
    pago = False
    for _ in range(15):
        pago = c.get(f"/v1/contratos/{pedido}/pagamento", headers=cliente).json()["pago"]
        if pago:
            break
        time.sleep(1)
    estado["webhook_real"] = pago
    if not pago:
        print("AVISO: webhook real não chegou (stripe listen fora do ar?). Usando evento assinado localmente com o segredo do .env.")
        evt = {"id": f"evt_teste_{uuid.uuid4().hex[:16]}", "type": "payment_intent.succeeded",
               "data": {"object": {"id": pi, "amount": valor, "amount_received": valor, "metadata": {"pedido_id": pedido}}}}
        corpo = json.dumps(evt).encode()
        r = c.post("/v1/webhooks/stripe", content=corpo, headers={"Stripe-Signature": assinar(corpo, os.environ["STRIPE_WEBHOOK_SECRET"]), "Content-Type": "application/json"})
        ok("webhook assinado localmente aceito (200)", r.status_code == 200, r.text[:120])
        r = c.post("/v1/webhooks/stripe", content=corpo, headers={"Stripe-Signature": assinar(corpo, os.environ["STRIPE_WEBHOOK_SECRET"]), "Content-Type": "application/json"})
        ok("reenvio do mesmo evento é duplicado e não repete efeito", r.status_code == 200 and r.json().get("duplicado") is True, r.text[:120])
    r = c.get(f"/v1/contratos/{pedido}/pagamento", headers=cliente)
    ok("depois do webhook, pago = true", r.status_code == 200 and r.json()["pago"] is True, str(r.json().get("estado_pagamento")))
    with banco() as con:
        n = con.execute("select count(*), coalesce(sum(p.valor_centavos) filter (where p.sentido='debito'),0) from public.lancamentos l "
                        "join public.partidas p on p.lancamento_id=l.id join public.contratos k on k.id=l.contrato_id where k.pedido_id=%s", (pedido,)).fetchone()
        ok("ledger espelhou a entrada (partidas dobradas)", n[0] >= 2, f"{n[0]} partida(s), débitos somam {n[1]} centavos")
        ev = con.execute("select count(*) from public.eventos_webhook").fetchone()[0]
        ok("eventos_webhook guardou o evento", ev >= 1, f"{ev} linha(s)")
    antes = n[0]
    if not estado["webhook_real"]:
        with banco() as con:
            depois = con.execute("select count(*) from public.lancamentos l join public.contratos k on k.id=l.contrato_id where k.pedido_id=%s", (pedido,)).fetchone()[0]
        ok("idempotência: lançamentos não duplicaram após o reenvio", depois == antes, f"{antes} -> {depois}")
    falhas = [x for x in resultados if not x[1]]
    print(f"\n{len(resultados) - len(falhas)} OK, {len(falhas)} FALHOU")
    sys.exit(1 if falhas else 0)


def reenvio() -> None:
    """Reenvia (com assinatura local) o último evento guardado e confere que nada se repete."""
    c = httpx.Client(base_url=API, timeout=60)
    with banco() as con:
        evt = con.execute("select payload from public.eventos_webhook order by recebido_em desc limit 1").fetchone()[0]
        antes = tuple(con.execute(f"select count(*) from public.{t}").fetchone()[0] for t in ("eventos_webhook", "lancamentos", "partidas", "pagamentos"))
    corpo = json.dumps(evt).encode()
    r = c.post("/v1/webhooks/stripe", content=corpo, headers={"Stripe-Signature": assinar(corpo, os.environ["STRIPE_WEBHOOK_SECRET"]), "Content-Type": "application/json"})
    ok("reenvio do mesmo evento: 200 e duplicado", r.status_code == 200 and r.json().get("duplicado") is True, r.text[:100])
    with banco() as con:
        depois = tuple(con.execute(f"select count(*) from public.{t}").fetchone()[0] for t in ("eventos_webhook", "lancamentos", "partidas", "pagamentos"))
    ok("idempotência: eventos, lançamentos, partidas e pagamentos não mudaram", antes == depois, f"{antes} -> {depois}")
    r = c.post("/v1/webhooks/stripe", content=corpo, headers={"Stripe-Signature": assinar(corpo, "whsec_errado"), "Content-Type": "application/json"})
    ok("assinatura errada é recusada (400)", r.status_code == 400)
    sys.exit(1 if any(not x[1] for x in resultados) else 0)


SEMENTES = ("contas_ledger", "categorias", "categoria_perguntas", "cidades")  # existiam antes do teste: não se apagam inteiras


def limpeza() -> None:
    estado = json.loads(ESTADO.read_text(encoding="utf-8"))
    antes = estado["contagens_antes"]
    tabelas = [t for t, n in antes.items() if t not in SEMENTES and n == 0]
    print("-- LIMPEZA do teste real. Rode no SQL Editor do Supabase (dono do banco). NADA aqui roda sozinho.")
    print("-- Estado antes do teste: todas estas tabelas tinham 0 linhas. Seeds (contas_ledger, categorias, cidades) ficam.")
    print("-- Ledger, config e eventos_webhook são imutáveis por gatilho: replica desliga gatilhos e FKs só nesta transação.")
    print("begin;")
    print("set local session_replication_role = replica;")
    print("delete from public.categoria_perguntas where texto like 'teste\\_%';")
    print("delete from public.categorias where slug like 'teste-%';")
    print("delete from public.cidades where nome like 'teste\\_%';")
    for t in tabelas:
        print(f'delete from public."{t}";')
    print("delete from auth.users where email like 'teste\\_%@example.test';")
    print("commit;")
    print("-- Conferir: select count(*) de cada tabela acima deve voltar 0; contas_ledger 4, categorias 3, cidades 1.")


if __name__ == "__main__":
    {"setup": setup, "fluxo": fluxo, "reenvio": reenvio, "limpeza": limpeza}.get(sys.argv[1] if len(sys.argv) > 1 else "", lambda: sys.exit(__doc__))()
