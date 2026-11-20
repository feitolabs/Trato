"""Etapa B, rodada 2 (B4a): exclusividade de 48h. Serviço em memória com a mesma semântica das
funções SQL, rotas do profissional e do cliente e as regras do pedido `reservado`."""

from __future__ import annotations

import threading

import pytest
from conftest import AGORA, CLIENTE, OUTRO_PROFISSIONAL, PROFISSIONAL, cab

from trato.api.exclusividades import ExclusividadesEmMemoria
from trato.api.moedas import ConfigMoedas, LancamentoMoeda, MoedasEmMemoria, saldo_profissional
from trato.api.repositorios import DadosPedido, Orcamento
from trato.pedidos.estados import (
    Acao,
    Ator,
    EstadoInvalido,
    Papel,
    acoes_permitidas,
    transicionar,
)
from trato.pedidos.estados import Estado as E

PRO, OUTRO_PRO = PROFISSIONAL.id, OUTRO_PROFISSIONAL.id
URL = "/v1/profissional/exclusividades"


def _ligar(amb, saldo=300, outro_saldo=0, **cfg):
    amb.contexto.moedas = MoedasEmMemoria(ConfigMoedas(ativo=True, **cfg))
    for quem, valor in ((PRO, saldo), (OUTRO_PRO, outro_saldo)):
        if valor:
            amb.contexto.moedas.lancamentos_teste = True
            amb.contexto.moedas.lancar(
                LancamentoMoeda(
                    quem,
                    "bonus_avaliacao_profissional",
                    valor,
                    f"b:{quem}",
                    AGORA,
                    carteira="profissional",
                )
            )


def _pedido(amb, pid="ped-1", urgente=False, categoria="cat-1", estado=E.ABERTO):
    amb.semear_pedido(estado, id=pid)
    amb.contexto.pedidos._dados[pid] = DadosPedido(
        categoria, "cid", "Pintar", "Sala", urgente=urgente
    )
    return pid


def _pedir(amb, quem="t-prof", pid="ped-1", chave="k1"):
    return amb.cliente.post(
        URL, json={"pedido_id": pid, "chave_idempotencia": chave}, headers=cab(quem)
    )


def _responder(amb, eid, decisao, quem="t-cliente", pid="ped-1"):
    return amb.cliente.post(
        f"/v1/pedidos/{pid}/exclusividade/{eid}/responder",
        json={"decisao": decisao},
        headers=cab(quem),
    )


def _saldo(amb, quem=PRO):
    return saldo_profissional(amb.contexto.moedas, quem, amb.relogio.agora)


def _orcar(amb, quem="t-prof", pid="ped-1"):
    corpo = {
        "itens": [
            {
                "tipo": "horas",
                "descricao": "Pintura",
                "quantidade": 1,
                "valor_unitario_centavos": 10_000,
            }
        ]
    }
    return amb.cliente.post(f"/v1/pedidos/{pid}/orcamentos", json=corpo, headers=cab(quem))


# --- estados ----------------------------------------------------------------------------------------------


def test_estado_reservado_e_transicoes():
    from trato.pedidos.estados import Pedido

    sistema, cliente = Ator(Papel.SISTEMA, "s"), Ator(Papel.CLIENTE, CLIENTE.id)
    aberto = Pedido("p", CLIENTE.id, AGORA)
    reservado = transicionar(aberto, Acao.RESERVAR_EXCLUSIVIDADE, cliente, AGORA).pedido
    assert reservado.estado is E.RESERVADO and E.RESERVADO.nome == "Reservado"
    assert (
        transicionar(reservado, Acao.EXPIRAR_EXCLUSIVIDADE, sistema, AGORA).pedido.estado
        is E.ABERTO
    )
    assert (
        transicionar(reservado, Acao.CANCELAR, cliente, AGORA, _prova()).pedido.estado
        is E.CANCELADO
    )
    aceito = transicionar(reservado, Acao.ACEITAR_ORCAMENTO, cliente, AGORA, _aceite()).pedido
    assert aceito.estado is E.ORCAMENTO_ACEITO
    with pytest.raises(EstadoInvalido):
        transicionar(aberto, Acao.EXPIRAR_EXCLUSIVIDADE, sistema, AGORA)  # só reservado expira
    assert Acao.RESERVAR_EXCLUSIVIDADE not in acoes_permitidas(
        aberto, Papel.CLIENTE
    )  # rota própria


def _prova():
    from trato.pedidos.estados import ProvaCancelamento

    return ProvaCancelamento("desisti")


def _aceite():
    from trato.pedidos.estados import ProvaAceite

    return ProvaAceite("orc-1", PRO)


# --- solicitar --------------------------------------------------------------------------------------------


def test_solicitar_ok_debita_100_e_a_chave_e_idempotente(amb):
    _ligar(amb, saldo=250)
    _pedido(amb)
    r = _pedir(amb)
    assert r.status_code == 201, r.text
    corpo = r.json()
    assert (corpo["status"], corpo["moedas_cobradas"], corpo["saldo_restante"]) == (
        "aguardando_cliente",
        100,
        150,
    )
    assert corpo["responder_ate"].startswith("2026-10-29T18:00")  # 6h depois de AGORA (12:00)
    assert _saldo(amb) == 150
    # Repetir a chave: 200 com a mesma oferta, sem cobrar de novo.
    de_novo = _pedir(amb)
    assert de_novo.status_code == 200 and de_novo.json()["id"] == corpo["id"]
    assert _saldo(amb) == 150
    # O pedido continua aberto enquanto aguarda o cliente.
    assert amb.contexto.pedidos.obter("ped-1").estado is E.ABERTO
    # Nada de orçamento de desconto da empresa.
    assert amb.contexto.moedas.orcamento_usado(AGORA.date().replace(day=1)) == 0


def test_saldo_menor_que_o_custo_da_409(amb):
    _ligar(amb, saldo=99)
    _pedido(amb)
    r = _pedir(amb)
    assert r.status_code == 409 and r.json()["codigo"] == "saldo_insuficiente"
    assert "detail" in r.json() and _saldo(amb) == 99


def test_quarta_simultanea_da_409_e_chave_de_outro_profissional_da_422(amb):
    _ligar(amb, saldo=1_000)
    for n in range(1, 5):
        _pedido(amb, f"ped-{n}")
    for n in range(1, 4):
        assert _pedir(amb, pid=f"ped-{n}", chave=f"k{n}").status_code == 201
    quarta = _pedir(amb, pid="ped-4", chave="k4")
    assert quarta.status_code == 409 and quarta.json()["codigo"] == "limite_simultaneas"
    # Chave já usada por outro profissional.
    _ligar_outro = amb.contexto.moedas
    _ligar_outro.lancar(
        LancamentoMoeda(
            OUTRO_PRO, "bonus_avaliacao_profissional", 500, "bo", AGORA, carteira="profissional"
        )
    )
    r = _pedir(amb, quem="t-outro-prof", pid="ped-4", chave="k1")
    assert r.status_code == 422 and r.json()["codigo"] == "chave_invalida"


def test_quatro_chamadas_simultaneas_so_tres_passam():
    # Direto no repositório: a trava garante o limite mesmo em corrida.
    class Pedidos:
        def obter(self, pid):
            from trato.pedidos.estados import Pedido

            return Pedido(pid, "cli-x", AGORA)

        def dados_do_pedido(self, pid):
            return None

    class Ctx:
        pedidos = Pedidos()
        moedas = MoedasEmMemoria(ConfigMoedas(ativo=True))

    Ctx.moedas.lancar(
        LancamentoMoeda(
            "pro", "bonus_avaliacao_profissional", 1_000, "b", AGORA, carteira="profissional"
        )
    )
    repo = ExclusividadesEmMemoria()
    repo.vincular(Ctx)
    resultados: list[str] = []
    largada = threading.Barrier(8)

    def tentar(n):
        largada.wait()
        resultados.append(repo.solicitar("pro", f"p{n}", f"k{n}", AGORA, 100, 3, 6, 30).resultado)

    fios = [threading.Thread(target=tentar, args=(n,)) for n in range(8)]
    for f in fios:
        f.start()
    for f in fios:
        f.join()
    assert resultados.count("ok") == 3 and resultados.count("limite_simultaneas") == 5
    assert Ctx.moedas.saldo("pro", AGORA, "profissional") == 700


def test_pedido_urgente_e_categoria_sem_exclusividade_da_422(amb):
    _ligar(amb)
    _pedido(amb, "ped-u", urgente=True)
    r = _pedir(amb, pid="ped-u")
    assert r.status_code == 422 and r.json()["codigo"] == "pedido_urgente"
    _pedido(amb, "ped-c", categoria="cat-chaveiro")
    amb.contexto.exclusividades.categorias_sem_exclusividade.add("cat-chaveiro")
    r = _pedir(amb, pid="ped-c", chave="k2")
    assert r.status_code == 422 and r.json()["codigo"] == "categoria_sem_exclusividade"
    assert _saldo(amb) == 300  # nada foi cobrado


def test_proprio_pedido_pedido_inexistente_e_fora_da_area(amb):
    _ligar(amb)
    amb.semear_pedido(E.ABERTO, cliente_id=PRO)  # o profissional é o cliente do pedido
    r = _pedir(amb)
    assert r.status_code == 422 and r.json()["codigo"] == "proprio_pedido"
    assert _pedir(amb, pid="nao-existe").status_code == 404
    _pedido(amb, "ped-2")
    amb.contexto.pedidos.listar_abertos = lambda *a, **k: ()  # não atende categoria/região
    r = _pedir(amb, pid="ped-2")
    assert r.status_code == 403 and r.json()["codigo"] == "fora_da_area"
    assert (
        amb.cliente.post(
            URL, json={"pedido_id": "ped-2", "chave_idempotencia": "x"}, headers=cab("t-cliente")
        ).status_code
        == 403
    )


def test_bloqueio_de_30_dias_depois_de_recusa(amb):
    _ligar(amb, saldo=500)
    _pedido(amb, "ped-1")
    _pedido(amb, "ped-2")
    eid = _pedir(amb, pid="ped-1").json()["id"]
    assert _responder(amb, eid, "recusar").status_code == 200
    r = _pedir(amb, pid="ped-2", chave="k2")
    assert r.status_code == 409 and r.json()["codigo"] == "bloqueado_recusa"
    amb.relogio.avancar(days=31)
    assert _pedir(amb, pid="ped-2", chave="k3").status_code == 201


def test_outro_profissional_no_mesmo_pedido_e_pedido_ja_com_oferta(amb):
    _ligar(amb, saldo=300, outro_saldo=300)
    _pedido(amb)
    assert _pedir(amb).status_code == 201
    r = _pedir(amb, quem="t-outro-prof", chave="k9")
    assert r.status_code == 409 and r.json()["codigo"] == "pedido_indisponivel"
    assert _saldo(amb, OUTRO_PRO) == 300


# --- responder ----------------------------------------------------------------------------------------------------


def test_recusar_estorna_integral_e_so_uma_vez(amb):
    _ligar(amb)
    _pedido(amb)
    eid = _pedir(amb).json()["id"]
    assert _saldo(amb) == 200
    r = _responder(amb, eid, "recusar")
    assert r.status_code == 200 and r.json()["status"] == "recusada"
    assert r.json()["outros_orcamentos_continuam_visiveis"] is True
    assert _saldo(amb) == 300
    again = _responder(amb, eid, "recusar")
    assert again.status_code == 409 and again.json()["codigo"] == "ja_respondida"
    assert _saldo(amb) == 300  # estorno uma vez só


def test_aceitar_leva_o_pedido_a_reservado_e_bloqueia_terceiros(amb):
    _ligar(amb, saldo=300, outro_saldo=300)
    _pedido(amb)
    eid = _pedir(amb).json()["id"]
    r = _responder(amb, eid, "aceitar")
    assert r.status_code == 200, r.text
    corpo = r.json()
    assert (corpo["status"], corpo["pedido_estado"]) == ("ativa", "reservado")
    assert corpo["expira_em"].startswith("2026-10-31T12:00")  # +48h
    assert amb.contexto.pedidos.obter("ped-1").estado is E.RESERVADO
    # Terceiro não orça nem vê o pedido reservado.
    terceiro = _orcar(amb, "t-outro-prof")
    assert terceiro.status_code == 409 and "reservado" in terceiro.json()["detail"]
    assert amb.contexto.pedidos.listar_abertos(OUTRO_PRO) == ()
    # O profissional da exclusividade vê e orça.
    assert [p.id for p in amb.contexto.pedidos.listar_abertos(PRO)] == ["ped-1"]
    assert _orcar(amb, "t-prof").status_code == 201


def test_cliente_aceita_o_orcamento_do_exclusivo_conclui_sem_estorno(amb):
    _ligar(amb)
    _pedido(amb)
    eid = _pedir(amb).json()["id"]
    _responder(amb, eid, "aceitar")
    orcamento = _orcar(amb, "t-prof").json()
    r = amb.cliente.post(
        "/v1/pedidos/ped-1/acoes/aceitar_orcamento",
        json={"prova": {"orcamento_id": orcamento["id"]}},
        headers=cab("t-cliente"),
    )
    assert r.status_code == 200, r.text
    assert amb.contexto.pedidos.obter("ped-1").estado is E.ORCAMENTO_ACEITO
    assert amb.contexto.exclusividades.obter(eid).status == "concluida"
    assert _saldo(amb) == 200  # as 100 não voltam: o profissional atendeu


def test_cliente_aceita_outro_orcamento_com_exclusividade_ativa_devolve_as_moedas(amb):
    _ligar(amb, saldo=300, outro_saldo=300)
    _pedido(amb)
    eid = _pedir(amb).json()["id"]
    # Outro profissional já tinha orçado antes da exclusividade.
    amb.contexto.orcamentos.adicionar(Orcamento("orc-outro", "ped-1", OUTRO_PRO, 8_000, "cat-1"))
    _responder(amb, eid, "aceitar")
    r = amb.cliente.post(
        "/v1/pedidos/ped-1/acoes/aceitar_orcamento",
        json={"prova": {"orcamento_id": "orc-outro"}},
        headers=cab("t-cliente"),
    )
    assert r.status_code == 200, r.text
    assert amb.contexto.pedidos.obter("ped-1").estado is E.ORCAMENTO_ACEITO
    assert amb.contexto.exclusividades.obter(eid).status == "cancelada"
    assert _saldo(amb) == 300  # estorno integral


def test_aceitar_outro_orcamento_com_oferta_ainda_pendente_tambem_estorna(amb):
    _ligar(amb)
    _pedido(amb)
    eid = _pedir(amb).json()["id"]
    amb.contexto.orcamentos.adicionar(Orcamento("orc-outro", "ped-1", OUTRO_PRO, 8_000, "cat-1"))
    r = amb.cliente.post(
        "/v1/pedidos/ped-1/acoes/aceitar_orcamento",
        json={"prova": {"orcamento_id": "orc-outro"}},
        headers=cab("t-cliente"),
    )
    assert r.status_code == 200
    assert amb.contexto.exclusividades.obter(eid).status == "cancelada" and _saldo(amb) == 300


def test_cancelar_o_pedido_estorna(amb):
    _ligar(amb)
    _pedido(amb)
    eid = _pedir(amb).json()["id"]
    _responder(amb, eid, "aceitar")
    r = amb.cliente.post(
        "/v1/pedidos/ped-1/acoes/cancelar",
        json={"prova": {"motivo": "desisti do serviço"}},
        headers=cab("t-cliente"),
    )
    assert r.status_code == 200, r.text
    assert amb.contexto.pedidos.obter("ped-1").estado is E.CANCELADO
    assert amb.contexto.exclusividades.obter(eid).status == "cancelada" and _saldo(amb) == 300


def test_resposta_com_prazo_vencido_expira_e_estorna(amb):
    _ligar(amb)
    _pedido(amb)
    eid = _pedir(amb).json()["id"]
    amb.relogio.avancar(hours=7)  # prazo de 6h
    r = _responder(amb, eid, "aceitar")
    assert r.status_code == 409 and r.json()["codigo"] == "prazo_vencido"
    assert amb.contexto.exclusividades.obter(eid).status == "expirada_sem_resposta"
    assert _saldo(amb) == 300 and amb.contexto.pedidos.obter("ped-1").estado is E.ABERTO
    # Já expirada pela rotina: continua prazo_vencido (não ja_respondida).
    assert _responder(amb, eid, "aceitar").json()["codigo"] == "prazo_vencido"


def test_aceite_com_pedido_que_deixou_de_estar_aberto_cancela_e_estorna(amb):
    _ligar(amb)
    _pedido(amb)
    eid = _pedir(amb).json()["id"]
    pedido = amb.contexto.pedidos.obter("ped-1")
    from dataclasses import replace

    amb.contexto.pedidos.salvar(replace(pedido, estado=E.CANCELADO))
    r = _responder(amb, eid, "aceitar")
    assert r.status_code == 409 and r.json()["codigo"] == "pedido_indisponivel"
    assert amb.contexto.exclusividades.obter(eid).status == "cancelada" and _saldo(amb) == 300


def test_so_o_dono_do_pedido_responde_e_decisao_invalida_da_422(amb):
    _ligar(amb)
    _pedido(amb)
    eid = _pedir(amb).json()["id"]
    assert _responder(amb, eid, "aceitar", quem="t-outro-cliente").status_code == 404
    assert _responder(amb, eid, "talvez").status_code == 422
    assert _responder(amb, "inexistente", "aceitar").status_code == 404


def test_expirar_sem_atendimento_reabre_o_pedido_sem_estorno(amb):
    _ligar(amb)
    _pedido(amb)
    eid = _pedir(amb).json()["id"]
    _responder(amb, eid, "aceitar")
    amb.relogio.avancar(hours=49)
    expiradas = amb.contexto.exclusividades.expirar(amb.relogio.agora)
    assert [(e.exclusividade_id, e.motivo) for e in expiradas] == [(eid, "sem_atendimento")]
    assert amb.contexto.pedidos.obter("ped-1").estado is E.ABERTO
    assert _saldo(amb) == 200  # perde as 100
    assert amb.contexto.exclusividades.expirar(amb.relogio.agora) == []  # idempotente


# --- leituras ----------------------------------------------------------------------------------------------------------


def test_lista_do_profissional_e_oferta_do_cliente(amb):
    _ligar(amb)
    _pedido(amb)
    vazio = amb.cliente.get(URL, headers=cab("t-prof")).json()
    assert (
        vazio["itens"],
        vazio["ativas_ou_pendentes"],
        vazio["limite_maximo"],
        vazio["saldo_profissional"],
    ) == ([], 0, 3, 300)
    assert (
        amb.cliente.get("/v1/pedidos/ped-1/exclusividade", headers=cab("t-cliente")).json() is None
    )
    eid = _pedir(amb).json()["id"]
    lista = amb.cliente.get(URL, headers=cab("t-prof")).json()
    assert [i["id"] for i in lista["itens"]] == [eid]
    assert (lista["ativas_ou_pendentes"], lista["saldo_profissional"]) == (1, 200)
    oferta = amb.cliente.get("/v1/pedidos/ped-1/exclusividade", headers=cab("t-cliente")).json()
    assert oferta["id"] == eid and oferta["status"] == "aguardando_cliente"
    assert oferta["texto"] == "Sem compromisso" and oferta["profissional_id"] == PRO
    assert {"profissional_nome", "nota_publica", "responder_ate", "expira_em"} <= set(oferta)
    assert (
        amb.cliente.get(
            "/v1/pedidos/ped-1/exclusividade", headers=cab("t-outro-cliente")
        ).status_code
        == 404
    )
    assert amb.cliente.get(URL, headers=cab("t-cliente")).status_code == 403  # só profissional


def test_aceitar_acao_reservar_nao_passa_pela_rota_generica(amb):
    _pedido(amb)
    r = amb.cliente.post("/v1/pedidos/ped-1/acoes/reservar_exclusividade", headers=cab("t-cliente"))
    assert r.status_code == 400 and "responder" in r.json()["detail"]
    r = amb.cliente.post("/v1/pedidos/ped-1/acoes/expirar_exclusividade", headers=cab("t-cliente"))
    assert r.status_code == 403


# --- Postgres (banco falso): parâmetros e linhas das 4 funções ----------------------------------------------


def test_postgres_chama_as_4_funcoes_com_a_assinatura_do_contrato():
    import uuid
    from contextlib import contextmanager

    from trato.persistencia.exclusividades import ExclusividadesPostgres

    pro, cli, ped, exc = (uuid.uuid4() for _ in range(4))
    chamadas: list[tuple[str, tuple]] = []

    class Con:
        def __init__(self):
            self.linhas: list = []

        def execute(self, sql, params=()):
            chamadas.append((sql, tuple(params)))
            if "exclusividade_solicitar" in sql:
                self.linhas = [
                    {
                        "resultado": "ok",
                        "exclusividade_id": exc,
                        "responder_ate": AGORA,
                        "saldo_restante": 7,
                    }
                ]
            elif "exclusividade_responder" in sql:
                self.linhas = [{"resultado": "ok", "expira_em": AGORA}]
            elif "exclusividade_expirar" in sql:
                self.linhas = [
                    {
                        "exclusividade_id": exc,
                        "motivo": "sem_resposta",
                        "profissional_id": pro,
                        "cliente_id": cli,
                        "pedido_id": ped,
                    }
                ]
            else:
                self.linhas = [
                    {"exclusividade_id": exc, "resultado": "cancelada", "profissional_id": pro}
                ]
            return self

        def fetchone(self):
            return self.linhas[0]

        def fetchall(self):
            return self.linhas

    class Banco:
        @contextmanager
        def transacao(self):
            yield Con()

    repo = ExclusividadesPostgres(Banco())
    r = repo.solicitar(str(pro), str(ped), "k", AGORA, 100, 3, 6, 30)
    assert (r.resultado, r.exclusividade_id, r.saldo_restante) == ("ok", exc.hex, 7)
    assert chamadas[-1][1] == (str(pro), str(ped), "k", AGORA, 100, 3, 6, 30)
    assert repo.responder(str(exc), str(cli), "aceitar", AGORA, 48).resultado == "ok"
    assert chamadas[-1][1] == (str(exc), str(cli), "aceitar", AGORA, 48)
    expiradas = repo.expirar(AGORA)
    assert [(e.exclusividade_id, e.motivo) for e in expiradas] == [(exc.hex, "sem_resposta")]
    enc = repo.encerrar_por_pedido(str(ped), None, AGORA)  # cancelamento: profissional aceito nulo
    assert [(e.resultado, e.profissional_id) for e in enc] == [("cancelada", pro.hex)]
    assert chamadas[-1][1] == (str(ped), None, AGORA)
