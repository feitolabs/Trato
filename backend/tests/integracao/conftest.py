"""Fixtures da integração: Postgres local (pgserver) com as migrations F3.2, F3.3, F3.4 e F3.7.

Se o pgserver não estiver instalado (ou não subir), todos os testes desta pasta são pulados.
"""

from __future__ import annotations

import secrets
import uuid
from dataclasses import dataclass
from datetime import UTC, datetime, timedelta

import pytest

pytest.importorskip("pgserver", reason="pgserver não instalado: integração com Postgres pulada")
pytest.importorskip("psycopg")

import jwt  # noqa: E402
from fastapi.testclient import TestClient  # noqa: E402
from pydantic import SecretStr  # noqa: E402

from trato.api import criar_app  # noqa: E402
from trato.api.contexto import Contexto  # noqa: E402
from trato.api.fabrica import criar_contexto_postgres  # noqa: E402
from trato.config import Config  # noqa: E402
from trato.persistencia.conexao import Banco  # noqa: E402

from .pg_local import BancoLocal  # noqa: E402

# Parâmetros de teste da configuração versionada (chave, unidade, valor).
PARAMETROS = (
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
FAIXAS = ((0, 100_000, 750), (100_000, None, 600))  # (de, até, bps) - valores de TESTE


@dataclass
class Cenario:
    local: BancoLocal
    banco: Banco
    contexto: Contexto
    cliente: TestClient
    segredo_jwt: str
    ids: dict[str, str]
    categoria_id: str
    cidade_id: str
    pergunta_id: str

    def token(self, quem: str, **extra: object) -> dict[str, str]:
        carga = {
            "sub": self.ids[quem],
            "aud": "authenticated",
            "exp": datetime.now(UTC) + timedelta(hours=1),
            **extra,
        }
        return {"Authorization": f"Bearer {jwt.encode(carga, self.segredo_jwt, 'HS256')}"}


def _semear(con, ids: dict[str, str]) -> tuple[str, str, str]:
    for nome in ids:
        con.execute("insert into auth.users (id) values (%s)", (ids[nome],))
        con.execute("insert into public.usuarios (id, nome) values (%s, %s)", (ids[nome], nome))
    for nome in ("profissional", "profissional2"):
        con.execute("insert into public.perfis_profissional (usuario_id) values (%s)", (ids[nome],))
        con.execute(
            "update public.perfis_profissional set status = 'aprovado', "
            "nivel_verificacao = 'verificado' where usuario_id = %s",
            (ids[nome],),
        )
    for nome, papel in (("equipe1", "administrador"), ("equipe2", "financeiro")):
        con.execute(
            "insert into public.equipe (usuario_id, papel) values (%s, %s)", (ids[nome], papel)
        )
    cidade = con.execute(
        "insert into public.cidades (nome, uf, ativa) values ('Cidade Teste', 'MG', true) "
        "returning id"
    ).fetchone()[0]
    categoria = con.execute(
        "insert into public.categorias (nome, slug, garantia_retrabalho_dias) "
        "values ('Pintura', 'pintura', 90) returning id"
    ).fetchone()[0]
    pergunta = con.execute(
        "insert into public.categoria_perguntas (categoria_id, texto, tipo) "
        "values (%s, 'Quantos cômodos?', 'numero') returning id",
        (categoria,),
    ).fetchone()[0]
    # Configuração versionada vigente (valores de TESTE, só neste banco descartável).
    versao = con.execute(
        "insert into public.config_versoes (criada_por, motivo) values (%s, 'teste') returning id",
        (ids["equipe1"],),
    ).fetchone()[0]
    for chave, unidade, valor in (*PARAMETROS, ("taxa_faixa_teste", "bps", 0)):
        con.execute(
            "insert into public.config_definicoes (chave, descricao, unidade) values (%s, %s, %s)",
            (chave, chave, unidade),
        )
        if chave != "taxa_faixa_teste":
            con.execute(
                "insert into public.config_parametros (versao_id, chave, valor) "
                "values (%s, %s, %s)",
                (versao, chave, valor),
            )
    for de, ate, bps in FAIXAS:
        con.execute(
            "insert into public.config_faixas_taxa "
            "(versao_id, de_centavos, ate_centavos, taxa_bps) "
            "values (%s, %s, %s, %s)",
            (versao, de, ate, bps),
        )
    con.execute(
        "update public.config_versoes set status = 'aprovada', aprovada_por = %s where id = %s",
        (ids["equipe2"], versao),
    )
    con.execute("update public.config_versoes set status = 'vigente' where id = %s", (versao,))
    return str(categoria), str(cidade), str(pergunta)


@pytest.fixture(scope="session")
def cenario(tmp_path_factory) -> Cenario:
    try:
        local = BancoLocal(tmp_path_factory.mktemp("pg"))
    except Exception as erro:  # noqa: BLE001 - qualquer falha ao subir o Postgres = pular
        pytest.skip(f"Postgres local indisponível: {erro}")
    ids = {
        n: str(uuid.uuid4())
        for n in (
            "cliente", "cliente2", "profissional", "profissional2", "equipe1", "equipe2"
        )
    }  # fmt: skip
    with local.admin() as con:
        categoria, cidade, pergunta = _semear(con, ids)

    segredo_jwt = secrets.token_hex(32)
    config = Config(
        _env_file=None,
        trato_codigo_segredo=SecretStr(secrets.token_hex(16)),
        supabase_jwt_secret=SecretStr(segredo_jwt),
    )
    banco = Banco(local.uri, papel="service_role")
    contexto = criar_contexto_postgres(banco, config)
    cliente = TestClient(criar_app(contexto))
    yield Cenario(local, banco, contexto, cliente, segredo_jwt, ids, categoria, cidade, pergunta)
    banco.fechar()
    local.fechar()
