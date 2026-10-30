"""Isolamento entre dois usuários no Supabase REAL (RLS + Storage). SÓ LEITURA.

Usa dois tokens (access_token) de duas contas de teste que o João já tem; o script NÃO cria conta nem
grava nada: só `GET` no PostgREST e no Storage. Variáveis (ver docs/roteiro-testes-reais.md):
  TRATO_TESTE_REAL=sim, SUPABASE_URL, SUPABASE_ANON_KEY, TRATO_JWT_A, TRATO_JWT_B,
  TRATO_PEDIDO_A (id de um pedido da conta A, que B não pode ver),
  opcionais: TRATO_MIDIA_A, TRATO_MENSAGEM_A, TRATO_STORAGE_PATH_A (bucket/caminho de um arquivo de A).
"""

from __future__ import annotations

from urllib.parse import quote

from teste_real_comum import encerrar, exigir_teste_real, http, json_de, registra, variavel

exigir_teste_real()
URL = variavel("SUPABASE_URL").rstrip("/")
ANON = variavel("SUPABASE_ANON_KEY")
JWT_A, JWT_B = variavel("TRATO_JWT_A"), variavel("TRATO_JWT_B")
PEDIDO_A = variavel("TRATO_PEDIDO_A")
MIDIA_A, MENSAGEM_A = variavel("TRATO_MIDIA_A", False), variavel("TRATO_MENSAGEM_A", False)
STORAGE_A = variavel("TRATO_STORAGE_PATH_A", False)


def consulta(jwt: str | None, caminho: str):
    cab = {"apikey": ANON, "Authorization": f"Bearer {jwt or ANON}"}
    status, corpo = http("GET", f"{URL}/rest/v1/{caminho}", cab)
    return status, json_de(corpo)


def vazio_ou_negado(jwt: str | None, caminho: str) -> tuple[bool, str]:
    status, dados = consulta(jwt, caminho)
    if status in (401, 403):
        return True, ""
    if isinstance(dados, dict) and dados.get("code") == "42501":  # permission denied
        return True, ""
    return status == 200 and dados == [], f"status={status} corpo={str(dados)[:120]}"


# Controle positivo: se A não enxerga o próprio pedido, o teste de B não prova nada.
status, dados = consulta(JWT_A, f"pedidos?id=eq.{quote(PEDIDO_A)}&select=id")
registra("A lê o próprio pedido (controle)", status == 200 and bool(dados), f"status={status}")

alvos = [
    ("pedido de A", f"pedidos?id=eq.{quote(PEDIDO_A)}&select=id"),
    ("endereço do pedido de A", f"pedidos_endereco?pedido_id=eq.{quote(PEDIDO_A)}&select=pedido_id"),
    ("histórico do pedido de A", f"pedido_historico?pedido_id=eq.{quote(PEDIDO_A)}&select=id"),
    ("contrato do pedido de A", f"contratos?pedido_id=eq.{quote(PEDIDO_A)}&select=id"),
    ("lançamentos do ledger (B não é parte)", "lancamentos?select=id&limit=5"),
    ("conversa do pedido de A", f"conversas?pedido_id=eq.{quote(PEDIDO_A)}&select=id"),
    ("mídias do pedido de A", f"midias?pedido_id=eq.{quote(PEDIDO_A)}&select=id"),
]
if MIDIA_A:
    alvos.append(("mídia de A por id", f"midias?id=eq.{quote(MIDIA_A)}&select=id"))
if MENSAGEM_A:
    alvos.append(("mensagem de A por id", f"mensagens?id=eq.{quote(MENSAGEM_A)}&select=id"))
for nome, caminho in alvos:
    ok, detalhe = vazio_ou_negado(JWT_B, caminho)
    registra(f"B não lê: {nome}", ok, detalhe)

# Sem login (só a chave anon): nada.
ok, detalhe = vazio_ou_negado(None, f"pedidos?id=eq.{quote(PEDIDO_A)}&select=id")
registra("anon (sem login) não lê o pedido de A", ok, detalhe)

# B2: colunas internas do dinheiro fora do alcance de qualquer usuário do app.
for tabela, coluna in (("lancamentos", "criado_por"), ("repasses", "provedor_transferencia_id"),
                       ("eventos_webhook", "payload")):
    status, dados = consulta(JWT_A, f"{tabela}?select={coluna}&limit=1")
    negado = status in (400, 401, 403) or (isinstance(dados, dict) and dados.get("code") == "42501")
    registra(f"A não lê a coluna interna {tabela}.{coluna}", negado, f"status={status}")

# A8: documentos de verificação não são legíveis direto pelo app.
status, dados = consulta(JWT_A, "verificacao_documentos?select=id&limit=1")
registra("A não lê verificacao_documentos direto", status in (401, 403) or dados == [] or
         (isinstance(dados, dict) and dados.get("code") == "42501"), f"status={status}")

# Storage: B tenta baixar um arquivo de A.
if STORAGE_A:
    cab = {"apikey": ANON, "Authorization": f"Bearer {JWT_B}"}
    status, _ = http("GET", f"{URL}/storage/v1/object/authenticated/{STORAGE_A}", cab)
    registra("B não baixa o arquivo de A no Storage", status in (400, 401, 403, 404), f"status={status}")
    cab = {"apikey": ANON, "Authorization": f"Bearer {JWT_A}"}
    status, _ = http("GET", f"{URL}/storage/v1/object/authenticated/{STORAGE_A}", cab)
    registra("A baixa o próprio arquivo (controle)", status == 200, f"status={status}")
else:
    registra("Storage: B não baixa o arquivo de A", None, "defina TRATO_STORAGE_PATH_A")

encerrar()
