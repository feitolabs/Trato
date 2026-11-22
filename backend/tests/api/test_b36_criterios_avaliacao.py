"""B36: critérios opcionais nas avaliações (validação, gravação, leitura e fallback sem coluna)."""

from __future__ import annotations

from contextlib import contextmanager
from datetime import UTC, datetime
from typing import Any

import psycopg
import pytest
from conftest import CLIENTE, PROFISSIONAL, cab
from test_profissional_upload import _aprovar, e2  # noqa: F401

from trato.api.auth import PapelUsuario
from trato.api.repositorios_app import Avaliacao, PerfilDetalhe
from trato.pedidos.estados import Estado as E
from trato.persistencia.dinheiro import AvaliacoesPostgres

_CRITERIOS_TODOS = {
    "pontualidade": 5,
    "qualidade": 4,
    "limpeza": 5,
    "comunicacao": 4,
    "preco_justo": 5,
}


def _concluir_pedido(amb: Any, pedido_id: str = "ped-1") -> None:
    amb.semear_pedido(E.CONCLUIDO, id=pedido_id)
    amb.contexto.usuarios.adicionar(PerfilDetalhe(CLIENTE.id, "Maria Silva", PapelUsuario.CLIENTE))
    amb.contexto.usuarios.adicionar(
        PerfilDetalhe(PROFISSIONAL.id, "Carlos Souza", PapelUsuario.PROFISSIONAL)
    )


def test_criterios_envio_contrato_e_leitura_perfis(e2: Any) -> None:  # noqa: F811
    _aprovar(e2)
    _concluir_pedido(e2.amb, "ped-1")
    r = e2.amb.cliente.post(
        "/v1/contratos/ped-1/avaliacao",
        json={"nota_geral": 5, "criterios": _CRITERIOS_TODOS},
        headers=cab("t-cliente"),
    )
    assert r.status_code == 201, r.text
    corpo = r.json()
    assert corpo["criterios"] == _CRITERIOS_TODOS

    salva = e2.amb.contexto.avaliacoes.obter("ped-1", "cliente_para_profissional")
    assert salva is not None and salva.criterios == _CRITERIOS_TODOS

    # Perfil público autenticado (visto pelo cliente e pelo próprio profissional)
    for token in ("t-cliente", "t-prof"):
        perfil = e2.get(f"/v1/profissionais/{PROFISSIONAL.id}", token)
        assert perfil.status_code == 200, perfil.text
        assert perfil.json()["avaliacoes"][0]["criterios"] == _CRITERIOS_TODOS

    # Perfil público sem login
    publico = e2.amb.cliente.get(f"/v1/publico/profissionais/{PROFISSIONAL.id}")
    assert publico.status_code == 200, publico.text
    assert publico.json()["avaliacoes_recentes"][0]["criterios"] == _CRITERIOS_TODOS


def test_criterios_opcional_ausente_ou_parcial_e_idempotencia(amb: Any) -> None:
    _concluir_pedido(amb, "ped-1")
    amb.semear_pedido(E.CONCLUIDO, id="ped-2")

    r_sem = amb.cliente.post(
        "/v1/contratos/ped-1/avaliacao",
        json={"nota_geral": 4},
        headers=cab("t-cliente"),
    )
    assert r_sem.status_code == 201, r_sem.text
    assert r_sem.json()["criterios"] is None

    parcial = {"pontualidade": 5, "limpeza": 4}
    r_parcial = amb.cliente.post(
        "/v1/contratos/ped-2/avaliacao",
        json={"nota_geral": 5, "criterios": parcial},
        headers=cab("t-cliente"),
    )
    assert r_parcial.status_code == 201, r_parcial.text
    assert r_parcial.json()["criterios"] == parcial

    # Duplo toque idempotente -> 200
    r_dup = amb.cliente.post(
        "/v1/contratos/ped-2/avaliacao",
        json={"nota_geral": 5, "criterios": parcial},
        headers=cab("t-cliente"),
    )
    assert r_dup.status_code == 200 and r_dup.json()["criterios"] == parcial

    # Critérios diferentes no mesmo contrato -> 409
    r_conf = amb.cliente.post(
        "/v1/contratos/ped-2/avaliacao",
        json={"nota_geral": 5, "criterios": {"pontualidade": 3}},
        headers=cab("t-cliente"),
    )
    assert r_conf.status_code == 409


@pytest.mark.parametrize(
    "criterios_invalido",
    [
        {"desconhecido": 5},
        {"pontualidade": 5, "extra": 4},
        {"pontualidade": 0},
        {"qualidade": 6},
        {"limpeza": -1},
        {"comunicacao": 4.5},
        {"preco_justo": True},
        {"pontualidade": "5"},
        ["pontualidade"],
    ],
)
def test_criterios_invalidos_retornam_422(amb: Any, criterios_invalido: Any) -> None:
    _concluir_pedido(amb, "ped-1")
    r = amb.cliente.post(
        "/v1/contratos/ped-1/avaliacao",
        json={"nota_geral": 5, "criterios": criterios_invalido},
        headers=cab("t-cliente"),
    )
    assert r.status_code == 422, r.text


class _CursorFalso:
    def __init__(self, linhas: list[dict[str, Any]]) -> None:
        self._linhas = linhas

    def fetchone(self) -> dict[str, Any] | None:
        return self._linhas[0] if self._linhas else None

    def fetchall(self) -> list[dict[str, Any]]:
        return list(self._linhas)


class _BancoFalsoSemColuna:
    """Simula Postgres antes da migration da coluna `criterios` (UndefinedColumn)."""

    def __init__(self, *, tem_coluna_criterios: bool) -> None:
        self.tem_coluna_criterios = tem_coluna_criterios
        self.gravado: dict[str, Any] | None = None
        self.queries: list[str] = []

    @contextmanager
    def transacao(self) -> Any:
        yield self

    @contextmanager
    def transaction(self) -> Any:
        yield self

    def execute(self, sql: str, params: tuple[Any, ...] = ()) -> _CursorFalso:
        self.queries.append(sql)
        if "from public.contratos where pedido_id" in sql:
            return _CursorFalso(
                [
                    {
                        "id": "11111111-1111-1111-1111-111111111111",
                        "cliente_id": "22222222-2222-2222-2222-222222222222",
                        "profissional_id": "33333333-3333-3333-3333-333333333333",
                    }
                ]
            )
        if not self.tem_coluna_criterios and "criterios" in sql:
            raise psycopg.errors.UndefinedColumn('column "criterios" does not exist')
        if sql.startswith("insert into public.avaliacoes"):
            self.gravado = {"sql": sql, "params": params}
            return _CursorFalso([])
        linha = {
            "id": "44444444-4444-4444-4444-444444444444",
            "pedido_id": "55555555-5555-5555-5555-555555555555",
            "direcao": "cliente_para_profissional",
            "avaliador_id": "22222222-2222-2222-2222-222222222222",
            "avaliado_id": "33333333-3333-3333-3333-333333333333",
            "nota_geral": 5,
            "nota_decimal": 4.8,
            "comentario": "Excelente",
            "etiquetas": ["pontual"],
            "criada_em": datetime(2026, 11, 22, 12, 0, tzinfo=UTC),
            "resposta": None,
        }
        if self.tem_coluna_criterios:
            linha["criterios"] = {"pontualidade": 5, "qualidade": 4}
        return _CursorFalso([linha])


def test_postgres_fallback_gracioso_sem_coluna_criterios() -> None:
    banco = _BancoFalsoSemColuna(tem_coluna_criterios=False)
    repo = AvaliacoesPostgres(banco)  # type: ignore[arg-type]
    av = Avaliacao(
        pedido_id="55555555-5555-5555-5555-555555555555",
        direcao="cliente_para_profissional",
        avaliador_id="22222222-2222-2222-2222-222222222222",
        avaliado_id="33333333-3333-3333-3333-333333333333",
        nota_geral=5,
        nota_decimal=4.8,
        criterios={"pontualidade": 5, "qualidade": 4},
        comentario="Excelente",
        etiquetas=("pontual",),
        criada_em=datetime(2026, 11, 22, 12, 0, tzinfo=UTC),
    )

    repo.salvar(av)
    assert banco.gravado is not None
    assert "criterios" not in banco.gravado["sql"]

    obtida = repo.obter(av.pedido_id, av.direcao)
    assert obtida is not None and obtida.criterios is None

    por_id = repo.obter_por_id("44444444-4444-4444-4444-444444444444")
    assert por_id is not None and por_id.criterios is None

    recebidas = repo.recebidas(av.avaliado_id)
    assert len(recebidas) == 1 and recebidas[0].criterios is None


def test_postgres_com_coluna_criterios_persiste_e_le() -> None:
    banco = _BancoFalsoSemColuna(tem_coluna_criterios=True)
    repo = AvaliacoesPostgres(banco)  # type: ignore[arg-type]
    av = Avaliacao(
        pedido_id="55555555-5555-5555-5555-555555555555",
        direcao="cliente_para_profissional",
        avaliador_id="22222222-2222-2222-2222-222222222222",
        avaliado_id="33333333-3333-3333-3333-333333333333",
        nota_geral=5,
        nota_decimal=4.8,
        criterios={"pontualidade": 5, "qualidade": 4},
        comentario="Excelente",
        etiquetas=("pontual",),
        criada_em=datetime(2026, 11, 22, 12, 0, tzinfo=UTC),
    )

    repo.salvar(av)
    assert banco.gravado is not None
    assert "criterios" in banco.gravado["sql"]

    obtida = repo.obter(av.pedido_id, av.direcao)
    assert obtida is not None and obtida.criterios == {"pontualidade": 5, "qualidade": 4}
