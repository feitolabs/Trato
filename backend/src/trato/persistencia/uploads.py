"""Persistência de solicitações de upload e mídias no Postgres.

Grava em `public.upload_solicitacoes` e `public.midias`. Mantém suporte transparente a
documentos e fallback em memória caso IDs sintéticos não-UUID sejam utilizados em testes.
"""

from __future__ import annotations

import logging
import uuid

from trato.persistencia.comum import como_uuid
from trato.persistencia.conexao import Banco
from trato.uploads.servico import DocumentoGuardado, Midia, Solicitacao, UploadsEmMemoria

logger = logging.getLogger(__name__)


def _para_hex(val: object) -> str:
    try:
        return uuid.UUID(str(val)).hex
    except ValueError:
        return str(val)


class UploadsPostgres:
    def __init__(self, banco: Banco) -> None:
        self._banco = banco
        self._memoria = UploadsEmMemoria()

    def salvar_solicitacao(self, s: Solicitacao) -> None:
        dono_id = como_uuid(s.dono_id)
        pedido_id = como_uuid(s.pedido_id) if s.pedido_id else None
        sol_id = como_uuid(s.id)
        registro_id = como_uuid(s.registro_id) if s.registro_id else None

        if not dono_id or not sol_id:
            self._memoria.salvar_solicitacao(s)
            return

        try:
            with self._banco.transacao() as con:
                # Remove tentativa pendente anterior no mesmo caminho para evitar colisão
                # na constraint unique.
                con.execute(
                    """
                    delete from public.upload_solicitacoes
                    where bucket = %s and caminho = %s and id <> %s and status = 'pendente'
                    """,
                    (s.bucket, s.caminho, sol_id),
                )
                con.execute(
                    """
                    insert into public.upload_solicitacoes (
                        id, dono_id, destino, pedido_id, tipo_documento,
                        bucket, caminho, content_type, tamanho_bytes, status, registro_id, criada_em
                    ) values (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s)
                    on conflict (id) do update set
                        status = excluded.status,
                        registro_id = excluded.registro_id
                    """,
                    (
                        sol_id,
                        dono_id,
                        s.destino,
                        pedido_id,
                        s.tipo_documento,
                        s.bucket,
                        s.caminho,
                        s.content_type,
                        s.tamanho_bytes,
                        s.status,
                        registro_id,
                        s.criada_em,
                    ),
                )
        except Exception as err:
            logger.warning("Falha ao salvar solicitacao de upload no banco: %s", err)
            self._memoria.salvar_solicitacao(s)

    def solicitacao(self, solicitacao_id: str) -> Solicitacao | None:
        sol_id = como_uuid(solicitacao_id)
        if not sol_id:
            return self._memoria.solicitacao(solicitacao_id)

        try:
            with self._banco.transacao() as con:
                row = con.execute(
                    """
                    select id, dono_id, destino, pedido_id, tipo_documento,
                           bucket, caminho, content_type, tamanho_bytes, status,
                           registro_id, criada_em
                    from public.upload_solicitacoes
                    where id = %s
                    """,
                    (sol_id,),
                ).fetchone()
                if row:
                    return Solicitacao(
                        id=_para_hex(row["id"]),
                        dono_id=str(row["dono_id"]),
                        destino=row["destino"],
                        bucket=row["bucket"],
                        caminho=row["caminho"],
                        content_type=row["content_type"],
                        tamanho_bytes=row["tamanho_bytes"],
                        criada_em=row["criada_em"],
                        pedido_id=str(row["pedido_id"]) if row["pedido_id"] else None,
                        tipo_documento=row["tipo_documento"],
                        status=row["status"],
                        registro_id=_para_hex(row["registro_id"]) if row["registro_id"] else None,
                    )
        except Exception as err:
            logger.debug("Falha ao buscar solicitacao de upload no banco: %s", err)

        return self._memoria.solicitacao(solicitacao_id)

    def salvar_midia(self, m: Midia) -> None:
        midia_id = como_uuid(m.id)
        pedido_id = como_uuid(m.pedido_id)
        enviada_por = como_uuid(m.enviada_por)

        if not midia_id or not pedido_id or not enviada_por:
            self._memoria.salvar_midia(m)
            return

        try:
            with self._banco.transacao() as con:
                con.execute(
                    """
                    insert into public.midias (
                        id, pedido_id, enviada_por, finalidade, bucket,
                        storage_path, mime, tamanho_bytes, sha256, capturada_em,
                        lat, lng, criado_em
                    ) values (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s)
                    on conflict (id) do nothing
                    """,
                    (
                        midia_id,
                        pedido_id,
                        enviada_por,
                        m.finalidade,
                        m.bucket,
                        m.storage_path,
                        m.mime,
                        m.tamanho_bytes,
                        m.sha256,
                        m.criada_em,
                        m.lat,
                        m.lng,
                        m.criada_em,
                    ),
                )
        except Exception:
            self._memoria.salvar_midia(m)

    def midia(self, midia_id: str) -> Midia | None:
        m_id = como_uuid(midia_id)
        if not m_id:
            return self._memoria.midia(midia_id)

        try:
            with self._banco.transacao() as con:
                row = con.execute(
                    """
                    select id, pedido_id, enviada_por, finalidade, bucket,
                           storage_path, mime, tamanho_bytes, sha256,
                           criado_em, lat, lng
                    from public.midias
                    where id = %s
                    """,
                    (m_id,),
                ).fetchone()
                if row:
                    return Midia(
                        id=_para_hex(row["id"]),
                        pedido_id=str(row["pedido_id"]),
                        enviada_por=str(row["enviada_por"]),
                        finalidade=row["finalidade"],
                        bucket=row["bucket"],
                        storage_path=row["storage_path"],
                        mime=row["mime"] or "application/octet-stream",
                        tamanho_bytes=row["tamanho_bytes"] or 0,
                        sha256=row["sha256"] or "",
                        criada_em=row["criado_em"],
                        lat=row["lat"],
                        lng=row["lng"],
                    )
        except Exception as err:
            logger.debug("Falha ao buscar midia no banco: %s", err)

        return self._memoria.midia(midia_id)

    @property
    def documentos(self) -> dict[str, DocumentoGuardado]:
        return self._memoria.documentos

    def salvar_documento(self, d: DocumentoGuardado) -> None:
        self._memoria.salvar_documento(d)

    def documento_por_caminho(self, caminho: str) -> DocumentoGuardado | None:
        return self._memoria.documento_por_caminho(caminho)

    def documento_por_id(self, doc_id: str) -> DocumentoGuardado | None:
        return self._memoria.documentos.get(doc_id)
