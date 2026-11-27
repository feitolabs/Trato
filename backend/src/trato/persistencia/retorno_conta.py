"""Impedimento de novo cadastro (HMAC-SHA256) e pedido de retorno de conta (Termos 20.9).

Tabelas: `public.conta_impedimentos_cadastro` e `public.conta_pedidos_retorno`
(migration 20261126213500_retorno_e_impedimento_conta.sql).
Nenhum dado pessoal em claro é salvo nos impedimentos; sem as tabelas, `disponivel()` é False
e as rotas respondem 503 limpo.
"""

# ruff: noqa: S608 - só trechos fixos de SQL são concatenados; valores vão por parâmetro

from __future__ import annotations

import hashlib
import hmac
import os
import threading
import uuid
from dataclasses import dataclass, replace
from datetime import datetime, timedelta
from typing import Any, Protocol

from trato.config import obter_config
from trato.persistencia.comum import como_uuid, exigir_uuid
from trato.persistencia.conexao import Banco
from trato.persistencia.erros import Duplicado, ErroPersistencia

PRAZO_RETORNO_PADRAO_DIAS = 90
_PEPPER_TESTE_MEMORIA = "trato-teste-impedimento-pepper-apenas-memoria"
TIPOS_IDENTIFICADOR = ("cpf", "email", "telefone")


def normalizar_identificador(tipo: str, valor: str | None) -> str | None:
    """Normaliza identificador antes do HMAC. Devolve None se vazio/inválido."""
    if not valor:
        return None
    if tipo == "cpf":
        digitos = "".join(c for c in valor if c.isdigit())
        return digitos if len(digitos) == 11 else None
    if tipo == "telefone":
        digitos = "".join(c for c in valor if c.isdigit())
        return digitos if len(digitos) >= 10 else None
    if tipo == "email":
        limpo = valor.strip().lower()
        return limpo if "@" in limpo and len(limpo) >= 3 else None
    return None


def obter_pepper_impedimento(*, exigir: bool = False) -> str | None:
    """Lê `CONTA_IMPEDIMENTO_PEPPER` do ambiente/config. Nunca usa segredo fixo em produção."""
    env_val = os.environ.get("CONTA_IMPEDIMENTO_PEPPER", "").strip()
    if env_val:
        return env_val
    cfg = obter_config()
    cfg_val = cfg.conta_impedimento_pepper.get_secret_value().strip()
    if cfg_val:
        return cfg_val
    if cfg.trato_persistencia.strip().lower() == "memoria" and cfg.trato_ambiente != "producao":
        return _PEPPER_TESTE_MEMORIA
    if exigir:
        raise RuntimeError(
            "CONTA_IMPEDIMENTO_PEPPER não configurado no ambiente para gravar impedimento."
        )
    return None


def calcular_hmac_identificador(tipo: str, valor: str, pepper: str) -> str | None:
    """HMAC-SHA256 em hex minúsculo (64 chars) do identificador normalizado."""
    norm = normalizar_identificador(tipo, valor)
    if norm is None:
        return None
    msg = f"{tipo}:{norm}".encode()
    return hmac.new(pepper.encode("utf-8"), msg, hashlib.sha256).hexdigest()


def hmacs_de_identificadores(
    *,
    cpf: str | None = None,
    email: str | None = None,
    telefone: str | None = None,
    exigir_pepper: bool = False,
) -> list[tuple[str, str]]:
    """Lista `(tipo_identificador, hmac_hex)` para os identificadores válidos informados."""
    pepper = obter_pepper_impedimento(exigir=exigir_pepper)
    if not pepper:
        return []
    saida: list[tuple[str, str]] = []
    for tipo, bruto in (("cpf", cpf), ("email", email), ("telefone", telefone)):
        if bruto:
            h = calcular_hmac_identificador(tipo, bruto, pepper)
            if h is not None:
                saida.append((tipo, h))
    return saida


@dataclass(frozen=True)
class ImpedimentoCadastro:
    id: str
    medida_id: str
    tipo_identificador: str
    identificador_hmac: str
    criado_por: str
    criado_em: datetime
    revogado_em: datetime | None = None
    revogado_por: str | None = None
    motivo_revogacao: str | None = None


@dataclass(frozen=True)
class PedidoRetornoConta:
    id: str
    protocolo: str
    usuario_id: str
    medida_id: str
    justificativa_usuario: str
    canal: str
    status: str
    solicitado_em: datetime
    prazo_dias_aplicado: int
    elegivel_a_partir_de: datetime
    analista_id: str | None = None
    decisao_motivo: str | None = None
    risco_identificado: bool = False
    decidido_em: datetime | None = None


class RepositorioRetornoConta(Protocol):
    def disponivel(self) -> bool: ...

    def prazo_dias_vigente(self) -> int: ...

    def registrar_impedimento(
        self,
        medida_id: str,
        tipo_identificador: str,
        identificador_hmac: str,
        criado_por: str,
        agora: datetime,
    ) -> tuple[ImpedimentoCadastro, bool]: ...

    def esta_impedido(self, pares: list[tuple[str, str]]) -> bool: ...

    def listar_impedimentos(
        self,
        medida_id: str | None,
        apenas_ativos: bool,
        limite: int,
        deslocamento: int,
    ) -> tuple[list[ImpedimentoCadastro], int]: ...

    def revogar_impedimento(
        self, impedimento_id: str, operador_id: str, motivo: str, agora: datetime
    ) -> tuple[ImpedimentoCadastro | None, str]: ...

    def abrir_retorno(
        self,
        usuario_id: str,
        justificativa_usuario: str,
        canal: str,
        agora: datetime,
    ) -> tuple[PedidoRetornoConta | None, bool, str]: ...

    def listar_retornos_do_usuario(self, usuario_id: str) -> list[PedidoRetornoConta]: ...

    def listar_retornos_admin(
        self,
        status: str | None,
        usuario_id: str | None,
        limite: int,
        deslocamento: int,
    ) -> tuple[list[PedidoRetornoConta], int]: ...

    def iniciar_analise_retorno(
        self, retorno_id: str, analista_id: str
    ) -> tuple[PedidoRetornoConta | None, str]: ...

    def decidir_retorno(
        self,
        retorno_id: str,
        status_final: str,
        analista_id: str,
        decisao_motivo: str,
        risco_identificado: bool,
        agora: datetime,
    ) -> tuple[PedidoRetornoConta | None, str]: ...


class RetornoContaEmMemoria:
    def __init__(
        self, *, disponivel: bool = True, prazo_dias: int = PRAZO_RETORNO_PADRAO_DIAS
    ) -> None:
        self._disponivel = disponivel
        self._prazo_dias = prazo_dias
        self._medidas: Any = None
        self._impedimentos: dict[str, ImpedimentoCadastro] = {}
        self._retornos: dict[str, PedidoRetornoConta] = {}
        self._seq_imp = 0
        self._seq_ret = 0
        self._trava = threading.Lock()

    def vincular(self, medidas: Any) -> None:
        self._medidas = medidas

    def disponivel(self) -> bool:
        return self._disponivel

    def prazo_dias_vigente(self) -> int:
        return self._prazo_dias

    def registrar_impedimento(
        self,
        medida_id: str,
        tipo_identificador: str,
        identificador_hmac: str,
        criado_por: str,
        agora: datetime,
    ) -> tuple[ImpedimentoCadastro, bool]:
        with self._trava:
            existente = next(
                (
                    i
                    for i in self._impedimentos.values()
                    if i.tipo_identificador == tipo_identificador
                    and i.identificador_hmac == identificador_hmac
                    and i.revogado_em is None
                ),
                None,
            )
            if existente is not None:
                return existente, False
            self._seq_imp += 1
            novo = ImpedimentoCadastro(
                id=f"imp-{self._seq_imp}",
                medida_id=medida_id,
                tipo_identificador=tipo_identificador,
                identificador_hmac=identificador_hmac,
                criado_por=criado_por,
                criado_em=agora,
            )
            self._impedimentos[novo.id] = novo
            return novo, True

    def esta_impedido(self, pares: list[tuple[str, str]]) -> bool:
        if not self._disponivel or not pares:
            return False
        alvo = set(pares)
        with self._trava:
            return any(
                (i.tipo_identificador, i.identificador_hmac) in alvo and i.revogado_em is None
                for i in self._impedimentos.values()
            )

    def listar_impedimentos(
        self,
        medida_id: str | None,
        apenas_ativos: bool,
        limite: int,
        deslocamento: int,
    ) -> tuple[list[ImpedimentoCadastro], int]:
        with self._trava:
            itens = [
                i
                for i in self._impedimentos.values()
                if (medida_id is None or i.medida_id == medida_id)
                and (not apenas_ativos or i.revogado_em is None)
            ]
            itens.sort(key=lambda i: (i.criado_em, i.id), reverse=True)
            return itens[deslocamento : deslocamento + limite], len(itens)

    def revogar_impedimento(
        self, impedimento_id: str, operador_id: str, motivo: str, agora: datetime
    ) -> tuple[ImpedimentoCadastro | None, str]:
        with self._trava:
            atual = self._impedimentos.get(impedimento_id)
            if atual is None:
                return None, "nao_encontrado"
            if atual.revogado_em is not None:
                return atual, "ja_revogado"
            rev = replace(
                atual, revogado_em=agora, revogado_por=operador_id, motivo_revogacao=motivo
            )
            self._impedimentos[impedimento_id] = rev
            return rev, "ok"

    def abrir_retorno(
        self,
        usuario_id: str,
        justificativa_usuario: str,
        canal: str,
        agora: datetime,
    ) -> tuple[PedidoRetornoConta | None, bool, str]:
        with self._trava:
            existente = next(
                (
                    r
                    for r in self._retornos.values()
                    if r.usuario_id == usuario_id and r.status in ("aberto", "em_analise")
                ),
                None,
            )
            if existente is not None:
                return existente, False, "ja_aberto"

            medidas_usr = (
                self._medidas.listar(usuario_id=usuario_id, tipo="encerramento")[0]
                if self._medidas is not None
                else []
            )
            ativas = [m for m in medidas_usr if m.revertida_em is None]
            if not ativas:
                return None, False, "sem_encerramento"
            if any(m.infracao_grave for m in ativas):
                return None, False, "infracao_grave"

            medida = sorted(ativas, key=lambda m: m.inicio_em, reverse=True)[0]
            prazo = self._prazo_dias
            elegivel = medida.inicio_em + timedelta(days=prazo)
            if agora < elegivel:
                return None, False, "prazo_nao_cumprido"

            self._seq_ret += 1
            novo = PedidoRetornoConta(
                id=f"ret-{self._seq_ret}",
                protocolo=f"RET-{agora.year}-{self._seq_ret:06d}",
                usuario_id=usuario_id,
                medida_id=medida.id or "",
                justificativa_usuario=justificativa_usuario,
                canal=canal,
                status="aberto",
                solicitado_em=agora,
                prazo_dias_aplicado=prazo,
                elegivel_a_partir_de=elegivel,
            )
            self._retornos[novo.id] = novo
            return novo, True, "ok"

    def listar_retornos_do_usuario(self, usuario_id: str) -> list[PedidoRetornoConta]:
        with self._trava:
            return sorted(
                (r for r in self._retornos.values() if r.usuario_id == usuario_id),
                key=lambda r: (r.solicitado_em, r.id),
                reverse=True,
            )

    def listar_retornos_admin(
        self,
        status: str | None,
        usuario_id: str | None,
        limite: int,
        deslocamento: int,
    ) -> tuple[list[PedidoRetornoConta], int]:
        with self._trava:
            itens = [
                r
                for r in self._retornos.values()
                if (status is None or r.status == status)
                and (usuario_id is None or r.usuario_id == usuario_id)
            ]
            itens.sort(key=lambda r: (r.solicitado_em, r.id))
            return itens[deslocamento : deslocamento + limite], len(itens)

    def iniciar_analise_retorno(
        self, retorno_id: str, analista_id: str
    ) -> tuple[PedidoRetornoConta | None, str]:
        with self._trava:
            atual = self._retornos.get(retorno_id)
            if atual is None:
                return None, "nao_encontrado"
            if atual.status in ("aprovado", "recusado"):
                return atual, "ja_decidido"
            if atual.status == "em_analise":
                return atual, "repetido"
            nova = replace(atual, status="em_analise", analista_id=analista_id)
            self._retornos[retorno_id] = nova
            return nova, "ok"

    def decidir_retorno(
        self,
        retorno_id: str,
        status_final: str,
        analista_id: str,
        decisao_motivo: str,
        risco_identificado: bool,
        agora: datetime,
    ) -> tuple[PedidoRetornoConta | None, str]:
        with self._trava:
            atual = self._retornos.get(retorno_id)
            if atual is None:
                return None, "nao_encontrado"
            if atual.status in ("aprovado", "recusado"):
                if (
                    atual.status == status_final
                    and atual.decisao_motivo == decisao_motivo
                    and atual.risco_identificado == risco_identificado
                ):
                    return atual, "repetido"
                return atual, "ja_decidido"
            if status_final == "aprovado" and risco_identificado:
                return atual, "risco_impede_aprovacao"
            nova = replace(
                atual,
                status=status_final,
                analista_id=analista_id,
                decisao_motivo=decisao_motivo,
                risco_identificado=risco_identificado,
                decidido_em=agora,
            )
            self._retornos[retorno_id] = nova
            return nova, "ok"


class RetornoContaPostgres:
    _COLS_IMP = (
        "id, medida_id, tipo_identificador, identificador_hmac, criado_por, criado_em, "
        "revogado_em, revogado_por, motivo_revogacao"
    )
    _COLS_RET = (
        "id, protocolo, usuario_id, medida_id, justificativa_usuario, canal, status, "
        "solicitado_em, prazo_dias_aplicado, elegivel_a_partir_de, analista_id, "
        "decisao_motivo, risco_identificado, decidido_em"
    )

    def __init__(self, banco: Banco) -> None:
        self._banco = banco

    @staticmethod
    def _imp(l: dict[str, Any]) -> ImpedimentoCadastro:  # noqa: E741
        return ImpedimentoCadastro(
            id=str(l["id"]),
            medida_id=str(l["medida_id"]),
            tipo_identificador=l["tipo_identificador"],
            identificador_hmac=l["identificador_hmac"],
            criado_por=str(l["criado_por"]),
            criado_em=l["criado_em"],
            revogado_em=l["revogado_em"],
            revogado_por=str(l["revogado_por"]) if l["revogado_por"] else None,
            motivo_revogacao=l["motivo_revogacao"],
        )

    @staticmethod
    def _ret(l: dict[str, Any]) -> PedidoRetornoConta:  # noqa: E741
        return PedidoRetornoConta(
            id=str(l["id"]),
            protocolo=l["protocolo"],
            usuario_id=str(l["usuario_id"]),
            medida_id=str(l["medida_id"]),
            justificativa_usuario=l["justificativa_usuario"],
            canal=l["canal"],
            status=l["status"],
            solicitado_em=l["solicitado_em"],
            prazo_dias_aplicado=int(l["prazo_dias_aplicado"]),
            elegivel_a_partir_de=l["elegivel_a_partir_de"],
            analista_id=str(l["analista_id"]) if l["analista_id"] else None,
            decisao_motivo=l["decisao_motivo"],
            risco_identificado=bool(l["risco_identificado"]),
            decidido_em=l["decidido_em"],
        )

    def disponivel(self) -> bool:
        try:
            with self._banco.transacao() as con:
                l = con.execute(  # noqa: E741
                    "select to_regclass('public.conta_impedimentos_cadastro') as i, "
                    "to_regclass('public.conta_pedidos_retorno') as r"
                ).fetchone()
            return bool(l and l["i"] and l["r"])
        except Exception:  # noqa: BLE001
            return False

    def prazo_dias_vigente(self) -> int:
        try:
            with self._banco.transacao() as con:
                l = con.execute(  # noqa: E741
                    "select public.conta_retorno_prazo_dias_vigente() as d"
                ).fetchone()
            return int(l["d"]) if l and l["d"] is not None else PRAZO_RETORNO_PADRAO_DIAS
        except Exception:  # noqa: BLE001
            return PRAZO_RETORNO_PADRAO_DIAS

    def registrar_impedimento(
        self,
        medida_id: str,
        tipo_identificador: str,
        identificador_hmac: str,
        criado_por: str,
        agora: datetime,
    ) -> tuple[ImpedimentoCadastro, bool]:
        mid = exigir_uuid(medida_id, "medida")
        op_id = exigir_uuid(criado_por, "operador")
        try:
            with self._banco.transacao() as con:
                existente = con.execute(
                    f"select {self._COLS_IMP} from public.conta_impedimentos_cadastro "
                    "where tipo_identificador = %s and identificador_hmac = %s "
                    "and revogado_em is null limit 1",
                    (tipo_identificador, identificador_hmac),
                ).fetchone()
                if existente is not None:
                    return self._imp(existente), False
                nova = con.execute(
                    "insert into public.conta_impedimentos_cadastro "
                    "(medida_id, tipo_identificador, identificador_hmac, criado_por, criado_em) "
                    f"values (%s, %s, %s, %s, %s) returning {self._COLS_IMP}",
                    (mid, tipo_identificador, identificador_hmac, op_id, agora),
                ).fetchone()
            return self._imp(nova), True
        except Duplicado:
            with self._banco.transacao() as con:
                existente = con.execute(
                    f"select {self._COLS_IMP} from public.conta_impedimentos_cadastro "
                    "where tipo_identificador = %s and identificador_hmac = %s "
                    "and revogado_em is null limit 1",
                    (tipo_identificador, identificador_hmac),
                ).fetchone()
            assert existente is not None  # noqa: S101
            return self._imp(existente), False

    def esta_impedido(self, pares: list[tuple[str, str]]) -> bool:
        if not pares:
            return False
        try:
            with self._banco.transacao() as con:
                if not con.execute(
                    "select to_regclass('public.conta_impedimentos_cadastro') is not null as ok"
                ).fetchone()["ok"]:
                    return False
                for tipo, h in pares:
                    achado = con.execute(
                        "select 1 from public.conta_impedimentos_cadastro "
                        "where tipo_identificador = %s and identificador_hmac = %s "
                        "and revogado_em is null limit 1",
                        (tipo, h),
                    ).fetchone()
                    if achado is not None:
                        return True
            return False
        except Exception:  # noqa: BLE001 - tabela ausente em ambiente sem migration
            return False

    def listar_impedimentos(
        self,
        medida_id: str | None,
        apenas_ativos: bool,
        limite: int,
        deslocamento: int,
    ) -> tuple[list[ImpedimentoCadastro], int]:
        filtros: list[str] = []
        params: list[Any] = []
        if medida_id is not None:
            mid = como_uuid(medida_id)
            if mid is None:
                return [], 0
            filtros.append("medida_id = %s")
            params.append(mid)
        if apenas_ativos:
            filtros.append("revogado_em is null")
        where = f"where {' and '.join(filtros)}" if filtros else ""
        with self._banco.transacao() as con:
            tot = con.execute(
                f"select count(*) as n from public.conta_impedimentos_cadastro {where}",
                tuple(params),
            ).fetchone()
            linhas = con.execute(
                f"select {self._COLS_IMP} from public.conta_impedimentos_cadastro {where} "
                "order by criado_em desc, id desc limit %s offset %s",
                (*params, limite, deslocamento),
            ).fetchall()
        return [self._imp(l) for l in linhas], int(tot["n"]) if tot else 0  # noqa: E741

    def revogar_impedimento(
        self, impedimento_id: str, operador_id: str, motivo: str, agora: datetime
    ) -> tuple[ImpedimentoCadastro | None, str]:
        iid = como_uuid(impedimento_id)
        if iid is None:
            return None, "nao_encontrado"
        op_id = exigir_uuid(operador_id, "operador")
        with self._banco.transacao() as con:
            atual = con.execute(
                f"select {self._COLS_IMP} from public.conta_impedimentos_cadastro "
                "where id = %s for update",
                (iid,),
            ).fetchone()
            if atual is None:
                return None, "nao_encontrado"
            if atual["revogado_em"] is not None:
                return self._imp(atual), "ja_revogado"
            rev = con.execute(
                "update public.conta_impedimentos_cadastro "
                "set revogado_em = %s, revogado_por = %s, motivo_revogacao = %s "
                f"where id = %s returning {self._COLS_IMP}",
                (agora, op_id, motivo, iid),
            ).fetchone()
        return self._imp(rev), "ok"

    def abrir_retorno(
        self,
        usuario_id: str,
        justificativa_usuario: str,
        canal: str,
        agora: datetime,
    ) -> tuple[PedidoRetornoConta | None, bool, str]:
        uid = exigir_uuid(usuario_id, "usuario")
        with self._banco.transacao() as con:
            existente = con.execute(
                f"select {self._COLS_RET} from public.conta_pedidos_retorno "
                "where usuario_id = %s and status in ('aberto', 'em_analise') limit 1",
                (uid,),
            ).fetchone()
            if existente is not None:
                return self._ret(existente), False, "ja_aberto"

            medidas = con.execute(
                "select id, inicio_em, infracao_grave from public.medidas_conta "
                "where usuario_id = %s and tipo = 'encerramento' and revertida_em is null "
                "order by inicio_em desc",
                (uid,),
            ).fetchall()
            if not medidas:
                return None, False, "sem_encerramento"
            if any(m["infracao_grave"] for m in medidas):
                return None, False, "infracao_grave"

            medida = medidas[0]
            prazo = int(
                con.execute("select public.conta_retorno_prazo_dias_vigente() as d").fetchone()["d"]
            )
            elegivel = medida["inicio_em"] + timedelta(days=prazo)
            if agora < elegivel:
                return None, False, "prazo_nao_cumprido"

            nova = con.execute(
                "insert into public.conta_pedidos_retorno "
                "(id, usuario_id, medida_id, justificativa_usuario, canal, solicitado_em, "
                "prazo_dias_aplicado, elegivel_a_partir_de) "
                f"values (%s, %s, %s, %s, %s, %s, %s, %s) returning {self._COLS_RET}",
                (
                    uuid.uuid4(),
                    uid,
                    medida["id"],
                    justificativa_usuario,
                    canal,
                    agora,
                    prazo,
                    elegivel,
                ),
            ).fetchone()
        return self._ret(nova), True, "ok"

    def listar_retornos_do_usuario(self, usuario_id: str) -> list[PedidoRetornoConta]:
        uid = como_uuid(usuario_id)
        if uid is None:
            return []
        with self._banco.transacao() as con:
            linhas = con.execute(
                f"select {self._COLS_RET} from public.conta_pedidos_retorno "
                "where usuario_id = %s order by solicitado_em desc, id desc",
                (uid,),
            ).fetchall()
        return [self._ret(l) for l in linhas]  # noqa: E741

    def listar_retornos_admin(
        self,
        status: str | None,
        usuario_id: str | None,
        limite: int,
        deslocamento: int,
    ) -> tuple[list[PedidoRetornoConta], int]:
        filtros: list[str] = []
        params: list[Any] = []
        if status is not None:
            filtros.append("status = %s")
            params.append(status)
        if usuario_id is not None:
            uid = como_uuid(usuario_id)
            if uid is None:
                return [], 0
            filtros.append("usuario_id = %s")
            params.append(uid)
        where = f"where {' and '.join(filtros)}" if filtros else ""
        with self._banco.transacao() as con:
            tot = con.execute(
                f"select count(*) as n from public.conta_pedidos_retorno {where}",
                tuple(params),
            ).fetchone()
            linhas = con.execute(
                f"select {self._COLS_RET} from public.conta_pedidos_retorno {where} "
                "order by solicitado_em asc, id asc limit %s offset %s",
                (*params, limite, deslocamento),
            ).fetchall()
        return [self._ret(l) for l in linhas], int(tot["n"]) if tot else 0  # noqa: E741

    def iniciar_analise_retorno(
        self, retorno_id: str, analista_id: str
    ) -> tuple[PedidoRetornoConta | None, str]:
        rid = como_uuid(retorno_id)
        if rid is None:
            return None, "nao_encontrado"
        op_id = exigir_uuid(analista_id, "analista")
        with self._banco.transacao() as con:
            atual = con.execute(
                f"select {self._COLS_RET} from public.conta_pedidos_retorno "
                "where id = %s for update",
                (rid,),
            ).fetchone()
            if atual is None:
                return None, "nao_encontrado"
            if atual["status"] in ("aprovado", "recusado"):
                return self._ret(atual), "ja_decidido"
            if atual["status"] == "em_analise":
                return self._ret(atual), "repetido"
            nova = con.execute(
                "update public.conta_pedidos_retorno set status = 'em_analise', analista_id = %s "
                f"where id = %s returning {self._COLS_RET}",
                (op_id, rid),
            ).fetchone()
        return self._ret(nova), "ok"

    def decidir_retorno(
        self,
        retorno_id: str,
        status_final: str,
        analista_id: str,
        decisao_motivo: str,
        risco_identificado: bool,
        agora: datetime,
    ) -> tuple[PedidoRetornoConta | None, str]:
        rid = como_uuid(retorno_id)
        if rid is None:
            return None, "nao_encontrado"
        op_id = exigir_uuid(analista_id, "analista")
        try:
            with self._banco.transacao() as con:
                atual = con.execute(
                    f"select {self._COLS_RET} from public.conta_pedidos_retorno "
                    "where id = %s for update",
                    (rid,),
                ).fetchone()
                if atual is None:
                    return None, "nao_encontrado"
                if atual["status"] in ("aprovado", "recusado"):
                    if (
                        atual["status"] == status_final
                        and atual["decisao_motivo"] == decisao_motivo
                        and bool(atual["risco_identificado"]) == risco_identificado
                    ):
                        return self._ret(atual), "repetido"
                    return self._ret(atual), "ja_decidido"
                if status_final == "aprovado" and risco_identificado:
                    return self._ret(atual), "risco_impede_aprovacao"
                nova = con.execute(
                    "update public.conta_pedidos_retorno "
                    "set status = %s, analista_id = %s, decisao_motivo = %s, "
                    "risco_identificado = %s, decidido_em = %s "
                    f"where id = %s returning {self._COLS_RET}",
                    (status_final, op_id, decisao_motivo, risco_identificado, agora, rid),
                ).fetchone()
            return self._ret(nova), "ok"
        except ErroPersistencia:
            return None, "ja_decidido"
