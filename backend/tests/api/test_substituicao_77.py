"""BE-SUBSTITUICAO-77 (Termos 7.7): pedido de substituição após falta/cancelamento do profissional
e lista de faltas repetidas no painel."""

from __future__ import annotations

from datetime import timedelta

from conftest import AGORA, OUTRO_PROFISSIONAL, PROFISSIONAL, cab

from trato.api.repositorios import DadosPedido, EnderecoPedido
from trato.pedidos.estados import Estado as E
from trato.pedidos.estados import Janela
from trato.persistencia.cancelamentos import Cancelamento


def _semear_agendado_com_dados(amb, pid: str = "ped-orig") -> None:
    amb.semear_pedido(
        E.AGENDADO,
        id=pid,
        janela=Janela(AGORA + timedelta(hours=2), AGORA + timedelta(hours=4)),
    )
    amb.contexto.pedidos.salvar(
        amb.contexto.pedidos.obter(pid),
        None,
        DadosPedido(
            titulo="Troca de chuveiro",
            descricao="Instalar chuveiro elétrico novo no banheiro social.",
            categoria_id="eletrica",
            cidade_id="bh",
            bairro="Savassi",
            endereco=EnderecoPedido(
                cep="30130010",
                logradouro="Rua Pernambuco",
                numero="100",
                bairro="Savassi",
            ),
            profissional_convidado_id=PROFISSIONAL.id,
        ),
    )


def test_substituir_pedido_cancelado_pelo_profissional_e_bloqueios(amb):
    _semear_agendado_com_dados(amb, "ped-orig")

    # Pedido ainda agendado -> 409
    assert amb.cliente.post("/v1/pedidos/ped-orig/substituir", headers=cab("t-cliente")).status_code == 409

    # Profissional cancela
    r_can = amb.cliente.post(
        "/v1/pedidos/ped-orig/acoes/cancelar",
        json={"prova": {"motivo": "Imprevisto pessoal, não conseguirei atender."}},
        headers=cab("t-prof"),
    )
    assert r_can.status_code == 200, r_can.text

    # Outro cliente ou o profissional não podem substituir -> 403
    assert amb.cliente.post("/v1/pedidos/ped-orig/substituir", headers=cab("t-outro-cliente")).status_code == 403
    assert amb.cliente.post("/v1/pedidos/ped-orig/substituir", headers=cab("t-prof")).status_code == 403

    # Cliente dono cria pedido de substituição -> 201 com vínculo e dados copiados
    r_sub = amb.cliente.post("/v1/pedidos/ped-orig/substituir", headers=cab("t-cliente"))
    assert r_sub.status_code == 201, r_sub.text
    novo = r_sub.json()
    assert novo["estado"] == "aberto"
    assert novo["substitui_pedido_id"] == "ped-orig"
    copiado = amb.contexto.pedidos.dados_do_pedido(novo["id"])
    assert copiado is not None
    assert copiado.titulo == "Troca de chuveiro"
    assert copiado.categoria_id == "eletrica"
    assert copiado.cidade_id == "bh"
    assert copiado.endereco is not None and copiado.endereco.cep == "30130010"
    assert copiado.profissional_convidado_id is None

    # Já substituído -> 409
    assert amb.cliente.post("/v1/pedidos/ped-orig/substituir", headers=cab("t-cliente")).status_code == 409
    # Cancelamento do profissional foi gravado automaticamente em cancelamentos_pedido
    reg = amb.contexto.cancelamentos.do_pedido("ped-orig")
    assert reg is not None and reg.tipo == "cancelamento_profissional"

    # Pedido cancelado pelo próprio cliente NÃO pode ser substituído -> 409
    _semear_agendado_com_dados(amb, "ped-cli")
    assert (
        amb.cliente.post(
            "/v1/pedidos/ped-cli/acoes/cancelar",
            json={"prova": {"motivo": "Mudei de ideia."}},
            headers=cab("t-cliente"),
        ).status_code
        == 200
    )
    assert amb.cliente.post("/v1/pedidos/ped-cli/substituir", headers=cab("t-cliente")).status_code == 409


def test_admin_faltas_repetidas_filtra_periodo_minimo_e_permissao(amb):
    agora = amb.relogio.agora
    # Profissional 1: 2 cancelamentos recentes + 1 antigo (fora de 90 dias)
    for i, dias in enumerate((5, 20, 120)):
        amb.contexto.cancelamentos.registrar(
            Cancelamento(
                pedido_id=f"p-a-{i}",
                solicitado_por=PROFISSIONAL.id,
                tipo="cancelamento_profissional",
                status="cancelado_sem_retencao",
                recebido_em=agora - timedelta(days=dias),
                papel="profissional",
            )
        )
    # Outro profissional: apenas 1 cancelamento recente (abaixo do mínimo 2)
    amb.contexto.cancelamentos.registrar(
        Cancelamento(
            pedido_id="p-b-1",
            solicitado_por=OUTRO_PROFISSIONAL.id,
            tipo="cancelamento_profissional",
            status="cancelado_sem_retencao",
            recebido_em=agora - timedelta(days=3),
            papel="profissional",
        )
    )
    # Cancelamento de cliente não entra
    amb.contexto.cancelamentos.registrar(
        Cancelamento(
            pedido_id="p-c-1",
            solicitado_por=PROFISSIONAL.id,
            tipo="cancelamento_cliente",
            status="cancelado_sem_retencao",
            recebido_em=agora - timedelta(days=1),
            papel="cliente",
        )
    )

    # Sem permissão -> 403
    assert amb.cliente.get("/v1/admin/profissionais/faltas-repetidas", headers=cab("t-cliente")).status_code == 403
    assert amb.cliente.get("/v1/admin/profissionais/faltas-repetidas", headers=cab("t-n1")).status_code == 403

    r = amb.cliente.get("/v1/admin/profissionais/faltas-repetidas?dias=90&minimo=2", headers=cab("t-mediador"))
    assert r.status_code == 200, r.text
    itens = r.json()
    assert len(itens) == 1
    assert itens[0]["profissional_id"] == PROFISSIONAL.id
    assert itens[0]["total_cancelamentos"] == 2
    assert itens[0]["periodo_dias"] == 90
