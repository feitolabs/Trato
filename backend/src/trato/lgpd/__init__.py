"""LGPD: exportar dados, pedir exclusão (anonimização) e registrar consentimentos (F8.3)."""

from __future__ import annotations

from datetime import datetime, timedelta
from typing import TYPE_CHECKING

if TYPE_CHECKING:
    from fastapi import FastAPI

    from trato.seguranca.estado import Seguranca


def registrar_rotas(app: FastAPI, seg: Seguranca | None = None) -> FastAPI:
    """Liga as rotas de LGPD. Chamada por `trato.seguranca.registrar_rotas` (que passa `seg`);
    sozinha, usa a segurança já instalada no app."""
    from trato.api.cautela import registros_preservados
    from trato.api.contexto import Contexto
    from trato.config import obter_config
    from trato.financeiro.ledger import CUSTODIA, a_liberar
    from trato.lgpd.config import obter_config_lgpd
    from trato.lgpd.memoria import FonteDadosEmMemoria, criar_repositorios_memoria
    from trato.lgpd.rotas import router
    from trato.lgpd.servico import ServicoLgpd

    seg = seg or app.state.seguranca
    app.include_router(router)
    config = obter_config_lgpd()
    memoria: dict[str, ServicoLgpd] = {}

    def armazenamento(aplicativo: FastAPI):  # type: ignore[no-untyped-def]
        uploads = getattr(aplicativo.state, "servico_uploads", None)
        return getattr(uploads, "armazenamento", None)

    def guarda_de(contexto: Contexto | None):  # type: ignore[no-untyped-def]
        """13.10 e I.11: fim da guarda dos Tratinhos de quem o Trato encerrou sem falta. Na
        dúvida vale para o consumidor: sem resposta em `sem_falta`, guarda; não guarda a
        medida respondida como falta, a de infração grave ou a de fraude."""

        def ate(usuario_id: str, agora: datetime) -> datetime | None:
            if contexto is None:
                return None
            medidas, _ = contexto.medidas.listar(
                usuario_id=usuario_id, tipo="encerramento", limite=100
            )
            prazo = timedelta(days=config.tratinhos_guarda_encerramento_dias)
            fins = [
                m.inicio_em + prazo
                for m in medidas
                if m.revertida_em is None
                and m.sem_falta is not False
                and (m.sem_falta or not (m.infracao_grave or m.motivo_fraude))
                and m.inicio_em <= agora < m.inicio_em + prazo
            ]
            return max(fins, default=None)

        return ate

    def preservado_de(contexto: Contexto | None):  # type: ignore[no-untyped-def]
        return lambda usuario_id: (
            contexto is not None and registros_preservados(contexto, usuario_id)
        )

    def valores_em_memoria(aplicativo: FastAPI, contexto: Contexto):  # type: ignore[no-untyped-def]
        """Termos 4.8 e 20.7 no modo memória (no Postgres é a consulta de `persistencia/lgpd`)."""

        def pendencias(usuario_id: str) -> list[str]:
            como_cliente = contexto.pedidos.listar_do_usuario(usuario_id, True, limite=200)
            como_prof = contexto.pedidos.listar_do_usuario(usuario_id, False, limite=200)
            parados = {
                p.id
                for p in (*como_cliente, *como_prof)
                if contexto.ledger.saldo_da_conta(CUSTODIA, p.id) > 0
                or (
                    p.profissional_id
                    and contexto.ledger.saldo_da_conta(a_liberar(p.profissional_id), p.id) > 0
                )
            }
            achados = []
            if parados:
                achados.append(f"Valor retido ou a liberar em {len(parados)} pedido(s)")
            servico = getattr(aplicativo.state, "servico_pagamento", None)
            devolver = sum(len(servico.ordens.pendentes(p.id)) for p in como_cliente if servico)
            if devolver:
                achados.append(f"{devolver} reembolso(s) ainda não enviado(s)")
            return achados

        return pendencias

    def fabrica(aplicativo: FastAPI) -> ServicoLgpd | None:
        """Repositórios do contexto (`extras["lgpd"]`, Postgres) ou, só em modo memória, os de
        memória. Em modo Postgres sem adaptador responde 503 em vez de perder dado em silêncio."""
        contexto: Contexto | None = getattr(aplicativo.state, "contexto", None)
        moedas = getattr(contexto, "moedas", None)
        if contexto is not None and "lgpd" in contexto.extras:
            return ServicoLgpd(
                config,
                contexto.extras["lgpd"],
                seg,
                armazenamento(aplicativo),  # type: ignore[arg-type]
                moedas=moedas,
                tratinhos_guardados_ate=guarda_de(contexto),
                preservado=preservado_de(contexto),
            )
        if obter_config().trato_persistencia.strip().lower() != "memoria":
            return None
        if "servico" not in memoria:
            leitores = {}
            pendencias = None
            if contexto is not None:
                pendencias = valores_em_memoria(aplicativo, contexto)
                leitores = {
                    "pedidos_como_cliente": lambda u: [
                        vars(p) for p in contexto.pedidos.listar_do_usuario(u, True)
                    ],
                    "pedidos_como_profissional": lambda u: [
                        vars(p) for p in contexto.pedidos.listar_do_usuario(u, False)
                    ],
                }
            repos = criar_repositorios_memoria(
                FonteDadosEmMemoria(leitores=leitores, pendencias=pendencias)
            )
            memoria["servico"] = ServicoLgpd(
                config,
                repos,
                seg,
                armazenamento(aplicativo),
                moedas=moedas,
                tratinhos_guardados_ate=guarda_de(contexto),
                preservado=preservado_de(contexto),
            )
        return memoria["servico"]

    app.state.lgpd_fabrica = fabrica
    return app
