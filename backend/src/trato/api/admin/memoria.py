"""Repositórios administrativos em memória (testes rápidos e desenvolvimento)."""

from __future__ import annotations

import hashlib
import itertools
import threading
from collections.abc import Sequence
from dataclasses import dataclass, replace
from datetime import UTC, datetime
from typing import TYPE_CHECKING, Any

from trato.api.admin import config_regras as regras
from trato.api.admin.repositorios import (
    DadosPessoaisAdmin,
    DefinicaoConfig,
    EntradaAuditoria,
    FiltroAuditoria,
    MembroEquipe,
    PedidoResumoAdmin,
    UsuarioAdmin,
    VerificacaoAdmin,
    VersaoConfig,
)
from trato.persistencia.comum import para_json
from trato.persistencia.erros import NaoEncontrado, RegraDoBanco

if TYPE_CHECKING:
    from trato.api.contexto import Contexto


def _agora() -> datetime:
    return datetime.now(UTC)


class EquipeEmMemoria:
    def __init__(self, membros: Sequence[MembroEquipe] = ()) -> None:
        self._itens = {m.usuario_id: m for m in membros}

    def salvar(self, membro: MembroEquipe) -> None:
        self._itens[membro.usuario_id] = membro

    def obter(self, usuario_id: str) -> MembroEquipe | None:
        return self._itens.get(usuario_id)


class AuditoriaEmMemoria:
    """Mesma ideia do banco: só inclusão, com cadeia de hash para provar que nada saiu."""

    def __init__(self, agora=_agora) -> None:
        self._agora = agora
        self._linhas: list[dict[str, Any]] = []
        self._trava = threading.Lock()

    @staticmethod
    def _hash(linha: dict[str, Any], anterior: str | None) -> str:
        campos = (
            linha["id"], anterior or "", linha["ocorrida_em"].isoformat(), linha["ator_id"],
            linha["acao"], linha["entidade"], linha["entidade_id"], linha["antes"],
            linha["depois"], linha["motivo"],
        )  # fmt: skip
        return hashlib.sha256("|".join(str(c) for c in campos).encode()).hexdigest()

    def registrar(
        self,
        *,
        ator_id: str,
        acao: str,
        entidade: str | None = None,
        entidade_id: str | None = None,
        antes: Any = None,
        depois: Any = None,
        motivo: str | None = None,
    ) -> int:
        with self._trava:
            anterior = self._linhas[-1]["hash"] if self._linhas else None
            linha = {
                "id": len(self._linhas) + 1,
                "ocorrida_em": self._agora(),
                "ator_id": ator_id,
                "ator_tipo": "equipe",
                "acao": acao,
                "entidade": entidade,
                "entidade_id": entidade_id,
                "antes": para_json(antes),
                "depois": para_json(depois),
                "motivo": motivo,
                "hash_anterior": anterior,
            }
            linha["hash"] = self._hash(linha, anterior)
            self._linhas.append(linha)
            return int(linha["id"])

    def listar(
        self, filtro: FiltroAuditoria, limite: int, deslocamento: int
    ) -> tuple[Sequence[EntradaAuditoria], int]:
        achadas = [linha for linha in reversed(self._linhas) if self._casa(linha, filtro)]
        pagina = achadas[deslocamento : deslocamento + limite]
        return tuple(
            EntradaAuditoria(
                l["id"],
                l["ocorrida_em"],
                l["ator_id"],
                l["ator_tipo"],
                l["acao"],
                l["entidade"],
                l["entidade_id"],
                l["motivo"],
                l["antes"],
                l["depois"],
            )  # fmt: skip
            for l in pagina  # noqa: E741
        ), len(achadas)

    @staticmethod
    def _casa(linha: dict[str, Any], f: FiltroAuditoria) -> bool:
        return (
            (f.acao is None or linha["acao"].startswith(f.acao))
            and (f.ator_id is None or linha["ator_id"] == f.ator_id)
            and (f.entidade is None or linha["entidade"] == f.entidade)
            and (f.entidade_id is None or linha["entidade_id"] == f.entidade_id)
            and (f.desde is None or linha["ocorrida_em"] >= f.desde)
            and (f.ate is None or linha["ocorrida_em"] <= f.ate)
        )

    def verificar_cadeia(self) -> int | None:
        anterior = None
        for linha in self._linhas:
            if linha["hash_anterior"] != anterior or linha["hash"] != self._hash(linha, anterior):
                return int(linha["id"])
            anterior = linha["hash"]
        return None

    def adulterar_para_teste(self, linha_id: int, **campos: Any) -> None:
        """Só para os testes provarem que a verificação acusa alteração."""
        self._linhas[linha_id - 1].update(campos)


@dataclass
class _Verificacao:
    dados: VerificacaoAdmin
    caminhos: dict[str, str]


class VerificacoesAdminEmMemoria:
    def __init__(self, auditoria: AuditoriaEmMemoria, agora=_agora) -> None:
        self._auditoria = auditoria
        self._agora = agora
        self._itens: dict[str, _Verificacao] = {}

    def adicionar(self, verificacao: VerificacaoAdmin, caminhos: dict[str, str] | None = None):
        self._itens[verificacao.id] = _Verificacao(verificacao, caminhos or {})

    def listar(
        self, status: Sequence[str], limite: int, deslocamento: int
    ) -> tuple[Sequence[VerificacaoAdmin], int]:
        achadas = sorted(
            (i.dados for i in self._itens.values() if i.dados.status in status),
            key=lambda v: v.enviada_em,
        )
        return tuple(achadas[deslocamento : deslocamento + limite]), len(achadas)

    def obter(self, verificacao_id: str) -> VerificacaoAdmin | None:
        item = self._itens.get(verificacao_id)
        return item.dados if item else None

    def caminho_do_documento(self, verificacao_id: str, documento_id: str) -> str | None:
        item = self._itens.get(verificacao_id)
        return item.caminhos.get(documento_id) if item else None

    def decidir(self, verificacao_id: str, analista_id: str, aprovar: bool, motivo: str) -> None:
        item = self._itens.get(verificacao_id)
        if item is None:
            raise NaoEncontrado("Verificação não encontrada.")
        antes = item.dados.status
        if antes not in ("enviada", "em_analise"):
            raise RegraDoBanco("Essa verificação já foi decidida.")
        novo = "aprovada" if aprovar else "recusada"
        item.dados = replace(
            item.dados,
            status=novo,
            decidida_em=self._agora(),
            motivo_recusa=None if aprovar else motivo,
        )
        self._auditoria.registrar(
            ator_id=analista_id,
            acao=f"verificacao.{novo}",
            entidade="verificacoes",
            entidade_id=verificacao_id,
            antes={"status": antes},
            depois={"status": novo},
            motivo=motivo,
        )


class UsuariosAdminEmMemoria:
    def __init__(self, auditoria: AuditoriaEmMemoria) -> None:
        self._auditoria = auditoria
        self._itens: dict[str, UsuarioAdmin] = {}
        self._privados: dict[str, DadosPessoaisAdmin] = {}

    def adicionar(self, usuario: UsuarioAdmin, privados: DadosPessoaisAdmin | None = None) -> None:
        self._itens[usuario.id] = usuario
        if privados is not None:
            self._privados[usuario.id] = privados

    def buscar(
        self, termo: str | None, status: str | None, limite: int, deslocamento: int
    ) -> tuple[Sequence[UsuarioAdmin], int]:
        achados = [
            u
            for u in self._itens.values()
            if (status is None or u.status == status)
            and (termo is None or termo.lower() in u.nome.lower() or termo == u.id)
        ]
        achados.sort(key=lambda u: u.nome.lower())
        return tuple(achados[deslocamento : deslocamento + limite]), len(achados)

    def obter(self, usuario_id: str) -> UsuarioAdmin | None:
        return self._itens.get(usuario_id)

    def nomes(self, ids: Sequence[str]) -> dict[str, str]:
        return {i: self._itens[i].nome for i in ids if i in self._itens}

    def dados_pessoais(
        self, usuario_id: str, ator_id: str, motivo: str
    ) -> DadosPessoaisAdmin | None:
        dados = self._privados.get(usuario_id)
        if usuario_id not in self._itens:
            return None
        self._auditoria.registrar(
            ator_id=ator_id,
            acao="dado_pessoal.revelado",
            entidade="usuarios_privados",
            entidade_id=usuario_id,
            depois={"campos": ["cpf", "telefone", "data_nascimento"]},
            motivo=motivo,
        )
        return dados or DadosPessoaisAdmin(None, None, None, None, None)


class PedidosAdminEmMemoria:
    """Busca nos pedidos do `PedidosEmMemoria` (acessa o dicionário interno dele de propósito)."""

    def __init__(self, contexto: Contexto, usuarios: UsuariosAdminEmMemoria) -> None:
        self._contexto = contexto
        self._usuarios = usuarios

    def buscar(
        self,
        termo: str | None,
        estado: str | None,
        cliente_id: str | None,
        profissional_id: str | None,
        limite: int,
        deslocamento: int,
    ) -> tuple[Sequence[PedidoResumoAdmin], int]:
        pedidos = getattr(self._contexto.pedidos, "_pedidos", {})
        dados = getattr(self._contexto.pedidos, "_dados", {})
        saida = []
        for p in pedidos.values():
            titulo = dados[p.id].titulo if p.id in dados else "Pedido"
            if estado and p.estado.value != estado:
                continue
            if cliente_id and p.cliente_id != cliente_id:
                continue
            if profissional_id and p.profissional_id != profissional_id:
                continue
            if termo and termo != p.id and termo.lower() not in titulo.lower():
                continue
            contrato = self._contexto.contratos.obter_do_pedido(p.id)
            nome = self._usuarios.nomes([p.cliente_id]).get(p.cliente_id, "")
            saida.append(
                PedidoResumoAdmin(
                    p.id,
                    titulo,
                    p.estado.value,
                    p.cliente_id,
                    nome,
                    p.profissional_id,
                    contrato.valor_centavos if contrato else None,
                    p.aberto_em,
                )  # fmt: skip
            )
        saida.sort(key=lambda r: r.criado_em or _agora(), reverse=True)
        return tuple(saida[deslocamento : deslocamento + limite]), len(saida)


class ConfigAdminEmMemoria:
    def __init__(
        self,
        auditoria: AuditoriaEmMemoria,
        definicoes: Sequence[DefinicaoConfig] = (),
        agora=_agora,
    ) -> None:
        self._auditoria = auditoria
        self._definicoes = tuple(definicoes)
        self._agora = agora
        self._versoes: dict[str, VersaoConfig] = {}
        self._contador = itertools.count(1)

    def definicoes(self) -> Sequence[DefinicaoConfig]:
        return self._definicoes

    def versoes(self) -> Sequence[VersaoConfig]:
        todas = sorted(self._versoes.values(), key=lambda v: v.numero, reverse=True)
        return tuple(replace(v, parametros=(), faixas=()) for v in todas)

    def versao(self, versao_id: str) -> VersaoConfig | None:
        return self._versoes.get(versao_id)

    def vigente(self) -> VersaoConfig | None:
        return next((v for v in self._versoes.values() if v.status == "vigente"), None)

    def _obter(self, versao_id: str) -> VersaoConfig:
        versao = self._versoes.get(versao_id)
        if versao is None:
            raise NaoEncontrado("Versão de configuração não encontrada.")
        return versao

    def _registrar(self, ator: str, acao: str, antes: str | None, versao: VersaoConfig, motivo):
        self._auditoria.registrar(
            ator_id=ator,
            acao=acao,
            entidade="config_versoes",
            entidade_id=versao.id,
            antes={"status": antes} if antes else None,
            depois={"status": versao.status, "numero": versao.numero},
            motivo=motivo,
        )

    def _nova(self, autor, motivo, parametros, faixas, vigente_desde, revertida_de, status):
        regras.validar_itens(self._definicoes, parametros, faixas)
        numero = next(self._contador)
        versao = VersaoConfig(
            id=f"cfg-{numero}",
            numero=numero,
            status=status,
            motivo=motivo,
            criada_por=autor,
            vigente_desde=vigente_desde,
            revertida_de=revertida_de,
            criado_em=self._agora(),
            parametros=tuple(parametros),
            faixas=tuple(faixas),
        )
        self._versoes[versao.id] = versao
        return versao

    def criar_rascunho(
        self, autor_id, motivo, parametros, faixas, vigente_desde, partir_da_vigente
    ) -> VersaoConfig:
        if partir_da_vigente and (base := self.vigente()) is not None:
            parametros, faixas = regras.mesclar(base.parametros, base.faixas, parametros, faixas)
        versao = self._nova(autor_id, motivo, parametros, faixas, vigente_desde, None, "rascunho")
        self._registrar(autor_id, "config.rascunho_criado", None, versao, motivo)
        return versao

    def enviar_para_aprovacao(self, versao_id, autor_id, motivo) -> VersaoConfig:
        versao = self._obter(versao_id)
        regras.exigir_status(versao, "rascunho")
        regras.validar_publicavel(versao)
        novo = replace(versao, status="aguardando_aprovacao")
        self._versoes[versao_id] = novo
        self._registrar(autor_id, "config.enviada_para_aprovacao", versao.status, novo, motivo)
        return novo

    def aprovar(self, versao_id, aprovador_id, motivo) -> VersaoConfig:
        versao = self._obter(versao_id)
        regras.exigir_status(versao, "aguardando_aprovacao")
        regras.exigir_outra_pessoa(versao, aprovador_id)
        novo = replace(
            versao,
            status="aprovada",
            aprovada_por=aprovador_id,
            vigente_desde=versao.vigente_desde or self._agora(),
        )
        self._versoes[versao_id] = novo
        self._registrar(aprovador_id, "config.aprovada", versao.status, novo, motivo)
        return novo

    def publicar(self, versao_id, autor_id, motivo, agora) -> VersaoConfig:
        versao = self._obter(versao_id)
        regras.exigir_status(versao, "aprovada")
        regras.exigir_vigencia_chegou(versao, agora)
        regras.validar_publicavel(versao)
        atual = self.vigente()
        if atual is not None:
            fim = "revertida" if versao.revertida_de else "substituida"
            self._versoes[atual.id] = replace(atual, status=fim)
        novo = replace(versao, status="vigente")
        self._versoes[versao_id] = novo
        self._registrar(autor_id, "config.publicada", versao.status, novo, motivo)
        return novo

    def reverter(self, versao_alvo_id, autor_id, motivo) -> VersaoConfig:
        alvo = self._obter(versao_alvo_id)
        if alvo.status not in ("vigente", "substituida", "revertida"):
            raise RegraDoBanco("Só dá para reverter para uma versão que já valeu.")
        versao = self._nova(
            autor_id, motivo, alvo.parametros, alvo.faixas, None, alvo.id, "aguardando_aprovacao"
        )
        self._registrar(autor_id, "config.reversao_proposta", None, versao, motivo)
        return versao

    def descartar_rascunho(self, versao_id, autor_id, motivo) -> None:
        versao = self._obter(versao_id)
        regras.exigir_status(versao, "rascunho", "aguardando_aprovacao")
        del self._versoes[versao_id]
        self._registrar(autor_id, "config.rascunho_descartado", versao.status, versao, motivo)
