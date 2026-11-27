"""Medidas de conta e contestações (Termos 11.8 e 20; migration 20261125224600).

`usuarios.status` acompanha a medida mais grave em vigor. Sem as tabelas, `disponivel()` é
falso: ninguém fica impedido por aqui e as rotas novas respondem 503.
"""

# ruff: noqa: S608 - só nomes fixos de colunas e condições entram na f-string; valores por parâmetro

from __future__ import annotations

import threading
import uuid
from collections.abc import Sequence
from dataclasses import dataclass, replace
from datetime import datetime, timedelta
from typing import Any, Protocol

from psycopg.types.json import Jsonb

from trato.persistencia.auditoria import registrar_na_transacao
from trato.persistencia.comum import como_uuid
from trato.persistencia.conexao import Banco

# Aviso, trava de saque e remoção de conteúdo não impedem usar a conta.
IMPEDEM = ("restricao", "suspensao", "encerramento", "bloqueio_preventivo")
STATUS_IMPOSTO = {
    "suspensao": "bloqueado",
    "encerramento": "bloqueado",
    "bloqueio_preventivo": "bloqueado",
    "restricao": "restrito",
    "trava_saque": "restrito",
}
GRAVIDADE = {"ativo": 0, "restrito": 1, "bloqueado": 2}
JANELA_REPETIDA = timedelta(minutes=5)
# O agendador só devolve a conta de medida que terminou há pouco (não desfaz mudança antiga).
JANELA_DE_FIM = timedelta(days=7)
ABERTAS = ("aberta", "em_analise")
PRAZO_FRAUDE_PADRAO_DIAS = 30  # sem a configuração publicada (trava_fraude_prazo_maximo_dias)


@dataclass(frozen=True)
class Medida:
    usuario_id: str
    tipo: str
    motivo: str
    clausulas: tuple[str, ...]
    inicio_em: datetime
    efeito: str
    como_contestar: str
    origem: str = "analista"
    fim_em: datetime | None = None
    aplicada_por: str | None = None
    nota_interna: str | None = None
    detalhe_adiado: bool = False
    justificativa_adiamento: str | None = None
    avisado_em: datetime | None = None
    contestavel_ate: datetime | None = None
    revertida_em: datetime | None = None
    revertida_por: str | None = None
    infracao_grave: bool = False
    impedir_nova_conta: bool = False
    # 20.6: só a trava de saque por fraude retém, até o prejuízo apurado.
    motivo_fraude: bool = False
    limite_retencao_centavos: int | None = None
    protocolo: str | None = None
    id: str | None = None
    # 13.10: só em encerramento. `None`: ninguém informou (linha anterior ao campo ou painel
    # antigo, ou banco sem a coluna); a leitura favorece o usuário.
    sem_falta: bool | None = None

    def vigente(self, agora: datetime) -> bool:
        return (
            self.revertida_em is None
            and self.inicio_em <= agora
            and (self.fim_em is None or self.fim_em > agora)
        )


@dataclass(frozen=True)
class ContestacaoMedida:
    medida_id: str
    usuario_id: str
    versao: str
    canal: str
    aberta_em: datetime
    responder_ate: datetime
    status: str = "aberta"  # aberta | em_analise | mantida | alterada | revertida
    analista_id: str | None = None
    resposta: str | None = None
    mesmo_analista_justificativa: str | None = None
    decidida_em: datetime | None = None
    protocolo: str | None = None
    id: str | None = None
    # [{anexo_id, bucket, caminho, content_type, tamanho_bytes, sha256}]
    anexos: tuple[dict[str, Any], ...] = ()


class RepositorioMedidas(Protocol):
    def disponivel(self) -> bool: ...

    def impedida(self, usuario_id: str, agora: datetime) -> bool: ...

    def criar(self, medida: Medida) -> tuple[Medida, bool]: ...

    def obter(self, medida_id: str) -> Medida | None: ...

    def listar(
        self,
        usuario_id: str | None = None,
        tipo: str | None = None,
        vigentes_em: datetime | None = None,
        contestacao_aberta: bool = False,
        limite: int = 100,
        deslocamento: int = 0,
    ) -> tuple[list[Medida], int]: ...

    def terminadas(self, agora: datetime) -> list[Medida]: ...

    def mudar(self, medida_id: str, campos: dict[str, Any]) -> bool: ...

    def definir_status(self, usuario_id: str, de: Sequence[str], para: str) -> bool: ...

    def retencao_por_fraude(self, usuario_id: str, agora: datetime) -> int | None:
        """Limite da trava por fraude vigente mais recente (não somam). `None`: nada segura.
        Dentro de uma transação, trava a linha do usuário até o fim dela."""

    def prazo_maximo_trava_fraude_dias(self) -> int: ...

    def usuarios_com_trava_fraude(self, ids: Sequence[str], agora: datetime) -> set[str]:
        """Só leitura (não trava linhas): quais destes têm trava por fraude vigente. Ids sem
        hífen."""

    def conta_bloqueada_travada(self, usuario_id: str) -> bool:
        """`usuarios.status` é `bloqueado`? Dentro de uma transação, segura a conta até o
        fim dela. Vale mesmo sem as tabelas de medidas."""

    def contestacao(self, medida_id: str) -> ContestacaoMedida | None: ...

    def abrir_contestacao(self, item: ContestacaoMedida) -> tuple[ContestacaoMedida, bool]: ...

    def decidir_contestacao(self, item: ContestacaoMedida) -> bool:
        """Grava a decisão só se ainda estiver aberta."""


ANONIMIZADA = "[anonimizado]"
_ACAO_ANONIMIZAR = "dado_pessoal.anonimizacao_contestacao_medida"


def _arquivos(anexos: Any) -> list[tuple[str, str]]:
    return [(a.get("bucket") or "verificacao", a["caminho"]) for a in anexos if a.get("caminho")]


class MedidasEmMemoria:
    def anonimizar_contestacao(
        self, contestacao_id: str, operador_id: str, motivo: str
    ) -> tuple[str, list[tuple[str, str]]]:
        """(resultado, arquivos a remover). ok | ja_anonimizada | nao_encontrada |
        nao_decidida | analista_invalido | indisponivel"""
        with self._trava:
            for chave, c in self._contestacoes.items():
                if c.id != contestacao_id:
                    continue
                if c.status not in ("mantida", "alterada", "revertida"):
                    return "nao_decidida", []
                if c.versao == ANONIMIZADA and not c.anexos:
                    return "ja_anonimizada", []
                arquivos = _arquivos(c.anexos)
                self._apagados[contestacao_id] = arquivos
                self._contestacoes[chave] = replace(
                    c,
                    versao=ANONIMIZADA,
                    anexos=(),
                    resposta=ANONIMIZADA if c.resposta else None,
                    mesmo_analista_justificativa=(
                        ANONIMIZADA if c.mesmo_analista_justificativa else None
                    ),
                )
                return "ok", arquivos
        return "nao_encontrada", []

    def arquivos_anonimizados(self, contestacao_id: str) -> list[tuple[str, str]]:
        """Os caminhos guardados na anonimização, para repetir a remoção."""
        return list(self._apagados.get(contestacao_id, []))

    def __init__(self) -> None:
        self._apagados: dict[str, list[tuple[str, str]]] = {}
        self.impedidas: set[str] = set()  # atalho dos testes
        self.status: dict[str, str] = {}  # o `usuarios.status`; ausente = ativo
        self._itens: dict[str, Medida] = {}
        self._contestacoes: dict[str, ContestacaoMedida] = {}  # por medida
        self._trava = threading.RLock()

    def disponivel(self) -> bool:
        return True

    def impedida(self, usuario_id: str, agora: datetime) -> bool:
        return usuario_id in self.impedidas or any(
            m.usuario_id == usuario_id and m.tipo in IMPEDEM and m.vigente(agora)
            for m in self._itens.values()
        )

    def criar(self, medida: Medida) -> tuple[Medida, bool]:
        with self._trava:
            for m in self._itens.values():
                if (
                    (m.usuario_id, m.tipo, m.motivo, m.motivo_fraude, m.limite_retencao_centavos)
                    == (
                        medida.usuario_id,
                        medida.tipo,
                        medida.motivo,
                        medida.motivo_fraude,
                        medida.limite_retencao_centavos,
                    )
                    and m.vigente(medida.inicio_em)
                    and medida.inicio_em - m.inicio_em <= JANELA_REPETIDA
                ):
                    return m, False
            numero = len(self._itens) + 1
            nova = replace(
                medida,
                id=uuid.uuid4().hex,
                protocolo=f"MED-{medida.inicio_em.year}-{numero:06d}",
            )
            self._itens[nova.id] = nova
            return nova, True

    def obter(self, medida_id: str) -> Medida | None:
        return self._itens.get(medida_id)

    def listar(
        self,
        usuario_id: str | None = None,
        tipo: str | None = None,
        vigentes_em: datetime | None = None,
        contestacao_aberta: bool = False,
        limite: int = 100,
        deslocamento: int = 0,
    ) -> tuple[list[Medida], int]:
        def serve(m: Medida) -> bool:
            c = self._contestacoes.get(m.id or "")
            return (
                (usuario_id is None or m.usuario_id == usuario_id)
                and (tipo is None or m.tipo == tipo)
                and (vigentes_em is None or m.vigente(vigentes_em))
                and (not contestacao_aberta or (c is not None and c.status in ABERTAS))
            )

        achadas = [m for m in reversed(list(self._itens.values())) if serve(m)]
        return achadas[deslocamento : deslocamento + limite], len(achadas)

    def terminadas(self, agora: datetime) -> list[Medida]:
        return [
            m
            for m in self._itens.values()
            if m.revertida_em is None
            and m.fim_em is not None
            and agora - JANELA_DE_FIM < m.fim_em <= agora
        ]

    def mudar(self, medida_id: str, campos: dict[str, Any]) -> bool:
        with self._trava:
            atual = self._itens.get(medida_id)
            if atual is None or atual.revertida_em is not None:
                return False
            self._itens[medida_id] = replace(atual, **campos)
            return True

    def definir_status(self, usuario_id: str, de: Sequence[str], para: str) -> bool:
        with self._trava:
            atual = self.status.get(usuario_id, "ativo")
            if atual not in de or atual == para:
                return False
            self.status[usuario_id] = para
            return True

    def conta_bloqueada_travada(self, usuario_id: str) -> bool:
        with self._trava:
            return self.status.get(usuario_id) == "bloqueado"

    def retencao_por_fraude(self, usuario_id: str, agora: datetime) -> int | None:
        with self._trava:
            travas = [
                m
                for m in self._itens.values()
                if m.usuario_id == usuario_id
                and m.tipo == "trava_saque"
                and m.motivo_fraude
                and m.fim_em is not None
                and m.vigente(agora)
            ]
            if not travas:
                return None
            return max(travas, key=lambda m: (m.inicio_em, m.protocolo)).limite_retencao_centavos

    def prazo_maximo_trava_fraude_dias(self) -> int:
        return PRAZO_FRAUDE_PADRAO_DIAS

    def usuarios_com_trava_fraude(self, ids: Sequence[str], agora: datetime) -> set[str]:
        procurados = {i.replace("-", "") for i in ids}
        with self._trava:
            return {
                m.usuario_id.replace("-", "")
                for m in self._itens.values()
                if m.tipo == "trava_saque" and m.motivo_fraude and m.vigente(agora)
            } & procurados

    def contestacao(self, medida_id: str) -> ContestacaoMedida | None:
        return self._contestacoes.get(medida_id)

    def abrir_contestacao(self, item: ContestacaoMedida) -> tuple[ContestacaoMedida, bool]:
        with self._trava:
            atual = self._contestacoes.get(item.medida_id)
            if atual is not None:
                return atual, False
            numero = len(self._contestacoes) + 1
            novo = replace(
                item, id=uuid.uuid4().hex, protocolo=f"CMD-{item.aberta_em.year}-{numero:06d}"
            )
            self._contestacoes[item.medida_id] = novo
            return novo, True

    def decidir_contestacao(self, item: ContestacaoMedida) -> bool:
        with self._trava:
            atual = self._contestacoes.get(item.medida_id)
            if atual is None or atual.status not in ABERTAS:
                return False
            self._contestacoes[item.medida_id] = item
            return True


_COLUNAS = (
    "id, protocolo, usuario_id, tipo, motivo_usuario, nota_interna, clausulas, inicio_em, "
    "fim_em, efeito_pedidos_valores, como_contestar, detalhe_adiado, justificativa_adiamento, "
    "avisado_em, contestavel_ate, origem, aplicada_por, revertida_em, revertida_por"
)
_MUTAVEIS = frozenset({"fim_em", "revertida_em", "revertida_por", "sem_falta"})
# Marca, na trilha, o encerramento cuja resposta "sem falta?" foi NÃO (a coluna nasce falsa nas
# linhas antigas, que não podem ser confundidas com essa resposta).
_ACAO_COM_FALTA = "medida.encerramento_com_falta"
_COLUNAS_C = (
    "id, protocolo, medida_id, usuario_id, versao_usuario, canal, aberta_em, responder_ate, "
    "status, analista_id, resposta, mesmo_analista_justificativa, decidida_em, anexos"
)


def _id(valor: Any) -> str | None:
    return None if valor is None else str(valor)


def _medida(x: dict[str, Any]) -> Medida:
    return Medida(
        usuario_id=str(x["usuario_id"]),
        tipo=x["tipo"],
        motivo=x["motivo_usuario"],
        clausulas=tuple(x["clausulas"]),
        inicio_em=x["inicio_em"],
        efeito=x["efeito_pedidos_valores"],
        como_contestar=x["como_contestar"],
        origem=x["origem"],
        fim_em=x["fim_em"],
        aplicada_por=_id(x["aplicada_por"]),
        nota_interna=x["nota_interna"],
        detalhe_adiado=x["detalhe_adiado"],
        justificativa_adiamento=x["justificativa_adiamento"],
        avisado_em=x["avisado_em"],
        contestavel_ate=x["contestavel_ate"],
        revertida_em=x["revertida_em"],
        revertida_por=_id(x["revertida_por"]),
        infracao_grave=bool(x.get("infracao_grave", False)),
        impedir_nova_conta=bool(x.get("impedir_nova_conta", False)),
        motivo_fraude=bool(x.get("motivo_fraude", False)),
        limite_retencao_centavos=x.get("limite_retencao_centavos"),
        sem_falta=x.get("sem_falta"),
        protocolo=x["protocolo"],
        id=str(x["id"]),
    )


def _contestacao(x: dict[str, Any]) -> ContestacaoMedida:
    return ContestacaoMedida(
        medida_id=str(x["medida_id"]),
        usuario_id=str(x["usuario_id"]),
        versao=x["versao_usuario"],
        canal=x["canal"],
        aberta_em=x["aberta_em"],
        responder_ate=x["responder_ate"],
        status=x["status"],
        analista_id=_id(x["analista_id"]),
        resposta=x["resposta"],
        mesmo_analista_justificativa=x["mesmo_analista_justificativa"],
        decidida_em=x["decidida_em"],
        protocolo=x["protocolo"],
        id=str(x["id"]),
        anexos=tuple(x["anexos"]),
    )


class MedidasPostgres:
    def anonimizar_contestacao(
        self, contestacao_id: str, operador_id: str, motivo: str
    ) -> tuple[str, list[tuple[str, str]]]:
        cid, operador = como_uuid(contestacao_id), como_uuid(operador_id)
        with self._banco.transacao() as con:
            if not con.execute(
                "select to_regprocedure('public.anonimizar_contestacao_medida(uuid,uuid,text)') "
                "is not null as tem"
            ).fetchone()["tem"]:
                return "indisponivel", []
            if cid is None:
                return "nao_encontrada", []
            if operador is None:
                return "analista_invalido", []
            linhas = con.execute(
                "select resultado, bucket, caminho "
                "from public.anonimizar_contestacao_medida(%s, %s, %s)",
                (cid, operador, motivo),
            ).fetchall()
        arquivos = [(x["bucket"], x["caminho"]) for x in linhas if x["caminho"]]
        return str(linhas[0]["resultado"]), arquivos

    def arquivos_anonimizados(self, contestacao_id: str) -> list[tuple[str, str]]:
        cid = como_uuid(contestacao_id)
        if cid is None:
            return []
        with self._banco.transacao() as con:
            linhas = con.execute(
                "select depois from public.auditoria where acao = %s and entidade_id = %s "
                "order by id",
                (_ACAO_ANONIMIZAR, cid),
            ).fetchall()
        return [a for x in linhas for a in _arquivos((x["depois"] or {}).get("arquivos", []))]

    def __init__(self, banco: Banco) -> None:
        self._banco = banco

    @staticmethod
    def _tem(con: Any) -> bool:
        return con.execute(
            "select to_regclass('public.medidas_conta') is not null "
            "and to_regclass('public.medida_contestacoes') is not null as tem"
        ).fetchone()["tem"]

    def disponivel(self) -> bool:
        with self._banco.transacao() as con:
            return self._tem(con)

    def impedida(self, usuario_id: str, agora: datetime) -> bool:
        uid = como_uuid(usuario_id)
        if uid is None:
            return False
        with self._banco.transacao() as con:
            if not self._tem(con):
                return False
            return (
                con.execute(
                    "select 1 from public.medidas_conta where usuario_id = %s "
                    "and tipo = any(%s) and revertida_em is null and inicio_em <= %s "
                    "and (fim_em is null or fim_em > %s) limit 1",
                    (uid, list(IMPEDEM), agora, agora),
                ).fetchone()
                is not None
            )

    @staticmethod
    def _tem_fraude(con: Any) -> bool:
        return (
            con.execute(
                "select 1 from information_schema.columns where table_schema = 'public' "
                "and table_name = 'medidas_conta' and column_name = 'motivo_fraude'"
            ).fetchone()
            is not None
        )

    def _colunas(self, con: Any) -> str:
        extra = ", motivo_fraude, limite_retencao_centavos" if self._tem_fraude(con) else ""
        if con.execute(
            "select 1 from information_schema.columns where table_schema = 'public' "
            "and table_name = 'medidas_conta' and column_name = 'infracao_grave'"
        ).fetchone():
            extra += ", infracao_grave, impedir_nova_conta"
        if self._tem_sem_falta(con):
            extra += ", sem_falta"
        return _COLUNAS + extra

    @staticmethod
    def _tem_sem_falta(con: Any) -> bool:
        return (
            con.execute(
                "select 1 from information_schema.columns where table_schema = 'public' "
                "and table_name = 'medidas_conta' and column_name = 'sem_falta'"
            ).fetchone()
            is not None
        )

    @staticmethod
    def _ler(con: Any, linha: Any) -> Medida:
        medida = _medida(linha)
        if medida.sem_falta is False and (
            medida.tipo != "encerramento"
            or con.execute(
                "select 1 from public.auditoria where acao = %s and entidade_id = %s limit 1",
                (_ACAO_COM_FALTA, como_uuid(medida.id)),
            ).fetchone()
            is None
        ):
            return replace(medida, sem_falta=None)
        return medida

    @staticmethod
    def _travar_usuario(con: Any, uid: Any) -> None:
        # Não barra as chaves estrangeiras; põe em fila liberações e a criação da trava.
        con.execute("select 1 from public.usuarios where id = %s for no key update", (uid,))

    def retencao_por_fraude(self, usuario_id: str, agora: datetime) -> int | None:
        uid = como_uuid(usuario_id)
        if uid is None:
            return None
        with self._banco.transacao() as con:
            if not self._tem_fraude(con):
                return None
            self._travar_usuario(con, uid)
            linha = con.execute(
                "select limite_retencao_centavos as limite from public.medidas_conta "
                "where usuario_id = %s and tipo = 'trava_saque' and motivo_fraude "
                "and revertida_em is null and inicio_em <= %s and fim_em > %s "
                "order by criado_em desc, protocolo desc limit 1",
                (uid, agora, agora),
            ).fetchone()
        return None if linha is None else int(linha["limite"])

    def prazo_maximo_trava_fraude_dias(self) -> int:
        with self._banco.transacao() as con:
            tem = con.execute(
                "select to_regprocedure('public.trava_fraude_prazo_maximo_dias_vigente()') "
                "is not null as tem"
            ).fetchone()["tem"]
            if not tem:
                return PRAZO_FRAUDE_PADRAO_DIAS
            return int(
                con.execute(
                    "select public.trava_fraude_prazo_maximo_dias_vigente() as dias"
                ).fetchone()["dias"]
            )

    def usuarios_com_trava_fraude(self, ids: Sequence[str], agora: datetime) -> set[str]:
        validos = [str(u) for u in (como_uuid(i) for i in ids) if u is not None]
        if not validos:
            return set()
        with self._banco.transacao() as con:
            if not self._tem_fraude(con):
                return set()
            linhas = con.execute(
                "select distinct usuario_id from public.medidas_conta "
                "where usuario_id = any(%s::uuid[]) and tipo = 'trava_saque' and motivo_fraude "
                "and revertida_em is null and inicio_em <= %s and fim_em > %s",
                (validos, agora, agora),
            ).fetchall()
        return {str(x["usuario_id"]).replace("-", "") for x in linhas}

    def criar(self, medida: Medida) -> tuple[Medida, bool]:
        uid = como_uuid(medida.usuario_id)
        quem = como_uuid(medida.aplicada_por) if medida.aplicada_por else None
        with self._banco.transacao() as con:
            if medida.tipo == "trava_saque":  # antes da trava abaixo: mesma ordem da rota de risco
                self._travar_usuario(con, uid)
            con.execute("select pg_advisory_xact_lock(hashtextextended(%s, 11))", (str(uid),))
            fraude = self._tem_fraude(con)
            colunas = self._colunas(con)
            mesma, valores = "", []
            if fraude:
                mesma = (
                    "and motivo_fraude = %s "
                    "and limite_retencao_centavos is not distinct from %s::bigint "
                )
                valores = [medida.motivo_fraude, medida.limite_retencao_centavos]
            repetida = con.execute(
                f"select {colunas} from public.medidas_conta where usuario_id = %s and "
                f"tipo = %s and motivo_usuario = %s {mesma}and revertida_em is null and "
                "(fim_em is null or fim_em > %s) and inicio_em >= %s limit 1",
                (uid, medida.tipo, medida.motivo, *valores, medida.inicio_em,
                 medida.inicio_em - JANELA_REPETIDA),
            ).fetchone()  # fmt: skip
            if repetida is not None:
                return self._ler(con, repetida), False
            novos = {
                "usuario_id": uid,
                "tipo": medida.tipo,
                "motivo_usuario": medida.motivo,
                "nota_interna": medida.nota_interna,
                "clausulas": list(medida.clausulas),
                "inicio_em": medida.inicio_em,
                "fim_em": medida.fim_em,
                "efeito_pedidos_valores": medida.efeito,
                "como_contestar": medida.como_contestar,
                "detalhe_adiado": medida.detalhe_adiado,
                "justificativa_adiamento": medida.justificativa_adiamento,
                "avisado_em": medida.avisado_em,
                "contestavel_ate": medida.contestavel_ate,
                "origem": medida.origem,
                "aplicada_por": quem,
                "criado_em": medida.inicio_em,
            }
            devolver = colunas
            tem_209 = con.execute(
                "select 1 from information_schema.columns where table_schema = 'public' "
                "and table_name = 'medidas_conta' and column_name = 'infracao_grave' limit 1"
            ).fetchone()
            if tem_209 is not None:
                novos["infracao_grave"] = medida.infracao_grave
                novos["impedir_nova_conta"] = medida.impedir_nova_conta
            if fraude:  # sem as colunas, a trava é gravada e não segura nada
                novos["motivo_fraude"] = medida.motivo_fraude
                novos["limite_retencao_centavos"] = medida.limite_retencao_centavos
            if medida.tipo == "encerramento" and self._tem_sem_falta(con):
                novos["sem_falta"] = bool(medida.sem_falta)
            marcas = ", ".join(["%s"] * len(novos))
            linha = con.execute(
                f"insert into public.medidas_conta ({', '.join(novos)}) values ({marcas}) "
                f"returning {devolver}",
                list(novos.values()),
            ).fetchone()
            if "sem_falta" in novos and medida.sem_falta is False:
                registrar_na_transacao(
                    con,
                    ator_id=medida.aplicada_por,
                    ator_tipo="equipe" if medida.aplicada_por else "sistema",
                    acao=_ACAO_COM_FALTA,
                    entidade="medidas_conta",
                    entidade_id=str(linha["id"]),
                    depois={"sem_falta": False},
                    motivo="Encerramento informado como por falta do usuário (13.10).",
                )
            criada = self._ler(con, linha)
        return criada, True

    def obter(self, medida_id: str) -> Medida | None:
        mid = como_uuid(medida_id)
        if mid is None:
            return None
        with self._banco.transacao() as con:
            linha = con.execute(
                f"select {self._colunas(con)} from public.medidas_conta where id = %s", (mid,)
            ).fetchone()
            return self._ler(con, linha) if linha else None

    def listar(
        self,
        usuario_id: str | None = None,
        tipo: str | None = None,
        vigentes_em: datetime | None = None,
        contestacao_aberta: bool = False,
        limite: int = 100,
        deslocamento: int = 0,
    ) -> tuple[list[Medida], int]:
        condicoes, valores = ["true"], []
        if usuario_id is not None:
            if como_uuid(usuario_id) is None:
                return [], 0
            condicoes.append("m.usuario_id = %s")
            valores.append(como_uuid(usuario_id))
        if tipo is not None:
            condicoes.append("m.tipo = %s")
            valores.append(tipo)
        if vigentes_em is not None:
            condicoes.append(
                "m.revertida_em is null and m.inicio_em <= %s "
                "and (m.fim_em is null or m.fim_em > %s)"
            )
            valores += [vigentes_em, vigentes_em]
        if contestacao_aberta:
            condicoes.append(
                "exists (select 1 from public.medida_contestacoes c where c.medida_id = m.id "
                "and c.status in ('aberta', 'em_analise'))"
            )
        onde = " and ".join(condicoes)
        with self._banco.transacao() as con:
            if not self._tem(con):
                return [], 0
            total = con.execute(
                f"select count(*) as n from public.medidas_conta m where {onde}", valores
            ).fetchone()["n"]
            linhas = con.execute(
                f"select {self._colunas(con)} from public.medidas_conta m where {onde} "
                "order by inicio_em desc, protocolo desc limit %s offset %s",
                [*valores, limite, deslocamento],
            ).fetchall()
            return [self._ler(con, x) for x in linhas], int(total)

    def terminadas(self, agora: datetime) -> list[Medida]:
        with self._banco.transacao() as con:
            if not self._tem(con):
                return []
            linhas = con.execute(
                f"select {_COLUNAS} from public.medidas_conta where revertida_em is null "
                "and fim_em is not null and fim_em <= %s and fim_em > %s order by fim_em",
                (agora, agora - JANELA_DE_FIM),
            ).fetchall()
        return [_medida(x) for x in linhas]

    def mudar(self, medida_id: str, campos: dict[str, Any]) -> bool:
        mid = como_uuid(medida_id)
        if mid is None or not campos or set(campos) - _MUTAVEIS:
            return False
        if campos.get("revertida_por"):
            campos = campos | {"revertida_por": como_uuid(campos["revertida_por"])}
        trocas = ", ".join(f"{nome} = %s" for nome in campos)
        with self._banco.transacao() as con:
            cursor = con.execute(
                f"update public.medidas_conta set {trocas} where id = %s and revertida_em is null",
                [*campos.values(), mid],
            )
            return cursor.rowcount == 1

    def conta_bloqueada_travada(self, usuario_id: str) -> bool:
        uid = como_uuid(usuario_id)
        if uid is None:
            return False
        with self._banco.transacao() as con:
            linha = con.execute(
                "select status from public.usuarios where id = %s for share", (uid,)
            ).fetchone()
        return linha is not None and linha["status"] == "bloqueado"

    def definir_status(self, usuario_id: str, de: Sequence[str], para: str) -> bool:
        uid = como_uuid(usuario_id)
        if uid is None:
            return False
        with self._banco.transacao() as con:
            cursor = con.execute(
                "update public.usuarios set status = %s, atualizado_em = now() "
                "where id = %s and status = any(%s) and status <> %s",
                (para, uid, list(de), para),
            )
            return cursor.rowcount == 1

    def contestacao(self, medida_id: str) -> ContestacaoMedida | None:
        mid = como_uuid(medida_id)
        if mid is None:
            return None
        with self._banco.transacao() as con:
            linha = con.execute(
                f"select {_COLUNAS_C} from public.medida_contestacoes where medida_id = %s",
                (mid,),
            ).fetchone()
        return _contestacao(linha) if linha else None

    def abrir_contestacao(self, item: ContestacaoMedida) -> tuple[ContestacaoMedida, bool]:
        with self._banco.transacao() as con:
            linha = con.execute(
                "insert into public.medida_contestacoes (medida_id, usuario_id, "
                "versao_usuario, anexos, canal, aberta_em, responder_ate) values "
                "(%s, %s, %s, %s, %s, %s, %s) on conflict (medida_id) do nothing "
                f"returning {_COLUNAS_C}",
                (como_uuid(item.medida_id), como_uuid(item.usuario_id), item.versao,
                 Jsonb(list(item.anexos)), item.canal, item.aberta_em, item.responder_ate),
            ).fetchone()  # fmt: skip
        if linha is not None:
            return _contestacao(linha), True
        atual = self.contestacao(item.medida_id)
        assert atual is not None  # noqa: S101 - o conflito diz que existe
        return atual, False

    def decidir_contestacao(self, item: ContestacaoMedida) -> bool:
        with self._banco.transacao() as con:
            cursor = con.execute(
                "update public.medida_contestacoes set status = %s, analista_id = %s, "
                "resposta = %s, mesmo_analista_justificativa = %s, decidida_em = %s "
                "where medida_id = %s and status in ('aberta', 'em_analise')",
                (item.status, como_uuid(item.analista_id or ""), item.resposta,
                 item.mesmo_analista_justificativa, item.decidida_em,
                 como_uuid(item.medida_id)),
            )  # fmt: skip
            return cursor.rowcount == 1
