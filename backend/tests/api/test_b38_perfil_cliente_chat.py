"""B38: cartão-resumo seguro (LGPD) do cliente para o profissional no chat do pedido."""

from __future__ import annotations

from datetime import UTC, datetime
from decimal import Decimal
from typing import Any

from conftest import CLIENTE, PROFISSIONAL, cab

from trato.api.auth import PapelUsuario
from trato.api.repositorios import ItemOrcamento
from trato.api.repositorios_app import Avaliacao, PerfilDetalhe
from trato.pedidos.estados import Estado as E


def _registrar_cliente(amb: Any, *, criado_em: datetime | None = None) -> None:
    amb.contexto.usuarios.adicionar(
        PerfilDetalhe(
            CLIENTE.id,
            "Maria Oliveira Souza",
            PapelUsuario.CLIENTE,
            criado_em=criado_em,
        )
    )
    amb.contexto.usuarios.emails[CLIENTE.id] = "maria.souza@exemplo.com"
    amb.contexto.usuarios.registrar_dados_privados(
        CLIENTE.id, cpf="12345678909", telefone="37999998888"
    )


def test_profissional_atribuido_ve_resumo_lgpd_com_avaliacoes_e_concluidos(amb: Any) -> None:
    _registrar_cliente(amb, criado_em=datetime(2026, 1, 15, 14, 0, tzinfo=UTC))
    amb.semear_pedido(E.EM_ANDAMENTO, id="ped-ativo")
    amb.semear_pedido(E.CONCLUIDO, id="ped-done-1")
    amb.semear_pedido(E.CONCLUIDO, id="ped-done-2")
    amb.semear_pedido(E.CANCELADO, id="ped-canc")

    # Duas avaliações recebidas pelo cliente (direção profissional_para_cliente)
    amb.contexto.avaliacoes.salvar(
        Avaliacao(
            pedido_id="ped-done-1",
            direcao="profissional_para_cliente",
            avaliador_id=PROFISSIONAL.id,
            avaliado_id=CLIENTE.id,
            nota_geral=5,
            comentario="Ótima cliente",
            etiquetas=(),
            criada_em=datetime(2026, 2, 10, 12, 0, tzinfo=UTC),
        )
    )
    amb.contexto.avaliacoes.salvar(
        Avaliacao(
            pedido_id="ped-done-2",
            direcao="profissional_para_cliente",
            avaliador_id=PROFISSIONAL.id,
            avaliado_id=CLIENTE.id,
            nota_geral=4,
            nota_decimal=4.5,
            comentario="Pontual",
            etiquetas=(),
            criada_em=datetime(2026, 3, 10, 12, 0, tzinfo=UTC),
        )
    )

    r = amb.cliente.get("/v1/pedidos/ped-ativo/perfil-cliente", headers=cab("t-prof"))
    assert r.status_code == 200, r.text
    corpo = r.json()
    assert corpo == {
        "nome": "Maria S.",
        "nota_media": 4.75,
        "total_avaliacoes": 2,
        "servicos_concluidos": 2,
        "membro_desde": "2026-01-15",
    }
    # Garantia LGPD: nenhum dado sensível nem sobrenome completo no payload
    texto = r.text
    for proibido in ("Oliveira", "Souza", "12345678909", "37999998888", "maria.souza@exemplo.com"):
        assert proibido not in texto


def test_cliente_sem_avaliacoes_retorna_null_e_zero(amb: Any) -> None:
    _registrar_cliente(amb, criado_em=None)
    amb.semear_pedido(E.EM_ANDAMENTO, id="ped-sem-av")

    r = amb.cliente.get("/v1/pedidos/ped-sem-av/perfil-cliente", headers=cab("t-prof"))
    assert r.status_code == 200, r.text
    assert r.json() == {
        "nome": "Maria S.",
        "nota_media": None,
        "total_avaliacoes": 0,
        "servicos_concluidos": 0,
        "membro_desde": None,
    }


def test_profissional_que_orcou_pedido_aberto_acessa_resumo(amb: Any) -> None:
    _registrar_cliente(amb)
    amb.semear_pedido(E.ABERTO, id="ped-aberto", profissional_id=None)
    amb.contexto.orcamentos.enviar(
        pedido_id="ped-aberto",
        profissional_id=PROFISSIONAL.id,
        itens=(ItemOrcamento("horas", "Visita", Decimal("1"), 10_000),),
        agora=amb.relogio(),
    )

    r = amb.cliente.get("/v1/pedidos/ped-aberto/perfil-cliente", headers=cab("t-prof"))
    assert r.status_code == 200, r.text
    assert r.json()["nome"] == "Maria S."


def test_autorizacao_bloqueia_terceiro_cliente_e_pedido_inexistente(amb: Any) -> None:
    _registrar_cliente(amb)
    amb.semear_pedido(E.EM_ANDAMENTO, id="ped-privado")

    # Outro profissional sem vínculo com pedido contratado -> 404
    r_outro = amb.cliente.get("/v1/pedidos/ped-privado/perfil-cliente", headers=cab("t-outro-prof"))
    assert r_outro.status_code in (403, 404)

    # Cliente não acessa rota de resumo para profissional -> 403
    r_cli = amb.cliente.get("/v1/pedidos/ped-privado/perfil-cliente", headers=cab("t-cliente"))
    assert r_cli.status_code == 403

    # Pedido inexistente -> 404
    r_404 = amb.cliente.get("/v1/pedidos/ped-nao-existe/perfil-cliente", headers=cab("t-prof"))
    assert r_404.status_code == 404
