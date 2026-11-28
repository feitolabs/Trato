"""Versões em memória dos repositórios das rotas do app. Não são o armazenamento real."""

from __future__ import annotations

import itertools
from collections.abc import Callable, Sequence
from dataclasses import replace
from datetime import UTC, date, datetime, timedelta
from decimal import ROUND_HALF_UP, Decimal
from typing import Any

from trato.api.auth import PapelUsuario
from trato.api.repositorios_app import (
    Avaliacao,
    DocumentoVerificacao,
    NotaMaterial,
    PerfilDetalhe,
    RecusaPedido,
    Verificacao,
)
from trato.persistencia.conversas import Mensagem, Notificacao, mascarar_contatos
from trato.persistencia.erros import Duplicado, NaoEncontrado


class ConversasEmMemoria:
    def __init__(self, contratado: Callable[[str], bool] | None = None) -> None:
        self.contratado = contratado  # pedido_id -> já tem contrato? (o contexto liga)
        # (pedido_id, profissional_id) -> endereço e telefone passam nesta conversa? (o contexto
        # liga; sem isso vale `contratado`, usado em testes)
        self.contato_liberado: Callable[[str, str], bool] | None = None
        self._conversas: dict[tuple[str, str], str] = {}
        self._mensagens: dict[str, list[Mensagem]] = {}
        self._pedido_da_conversa: dict[str, str] = {}
        self._originais: dict[int, str] = {}
        self._ids = itertools.count(1)

    def abrir(self, pedido_id: str, profissional_id: str) -> str:
        chave = (pedido_id, profissional_id)
        if chave not in self._conversas:
            conversa = f"conv-{len(self._conversas) + 1}"
            self._conversas[chave] = conversa
            self._mensagens[conversa] = []
            self._pedido_da_conversa[conversa] = pedido_id
        return self._conversas[chave]

    def do_pedido(self, pedido_id: str) -> list[tuple[str, str]]:
        return [(c, prof) for (pid, prof), c in self._conversas.items() if pid == pedido_id]

    def enviar(self, conversa_id: str, autor_id: str, corpo: str) -> int:
        if conversa_id not in self._mensagens:
            raise NaoEncontrado("Conversa não encontrada ou encerrada.")
        liberado = self._liberado(conversa_id)
        exibido = mascarar_contatos(corpo, incluir_endereco=not liberado, liberar_telefone=liberado)
        nova = Mensagem(
            next(self._ids), autor_id, exibido, exibido != corpo, datetime.now(UTC), None
        )
        self._mensagens[conversa_id].append(nova)
        self._originais[nova.id] = corpo
        return nova.id

    def originais(self, conversa_id: str) -> dict[int, str]:
        return {
            m.id: self._originais.get(m.id, m.texto) for m in self._mensagens.get(conversa_id, ())
        }

    def listar(self, conversa_id: str) -> Sequence[Mensagem]:
        mensagens = self._mensagens.get(conversa_id, ())
        if self._liberado(conversa_id):
            return tuple(mensagens)
        saida = []
        for m in mensagens:  # deixou de valer (pedido cancelado): volta a esconder na leitura
            texto = mascarar_contatos(m.texto)
            saida.append(m if texto == m.texto else replace(m, texto=texto, mascarada=True))
        return tuple(saida)

    def _liberado(self, conversa_id: str) -> bool:
        if self.contato_liberado is None and self.contratado is None:
            return False
        for (pedido_id, profissional_id), conversa in self._conversas.items():
            if conversa == conversa_id:
                if self.contato_liberado is None:
                    return self.contratado(pedido_id)
                return self.contato_liberado(pedido_id, profissional_id)
        return False


class NotificacoesEmMemoria:
    def __init__(self) -> None:
        self._itens: dict[str, list[Notificacao]] = {}

    def criar(
        self,
        usuario_id: str,
        tipo: str,
        titulo: str,
        *,
        corpo: str | None = None,
        dados: dict[str, Any] | None = None,
        agora: datetime | None = None,
    ) -> str:
        lista = self._itens.setdefault(usuario_id, [])
        nova = Notificacao(
            f"not-{len(lista) + 1}-{usuario_id}",
            tipo,
            "app",
            titulo,
            corpo,
            dados or {},
            agora or datetime.now(UTC),
            None,
        )
        lista.append(nova)
        return nova.id

    def listar(self, usuario_id: str, apenas_nao_lidas: bool = False) -> Sequence[Notificacao]:
        itens = reversed(self._itens.get(usuario_id, ()))
        return tuple(n for n in itens if not apenas_nao_lidas or n.lida_em is None)


class UsuariosEmMemoria:
    def __init__(self, perfis: Sequence[PerfilDetalhe] = ()) -> None:
        self._perfis = {p.id: p for p in perfis}
        self._cpfs: dict[str, str] = {}  # cpf (11 dígitos) -> usuario_id
        self._telefones: dict[str, str] = {}  # telefone (dígitos) -> usuario_id
        self.emails: dict[str, str] = {}  # usuario_id -> email
        self.verificacoes: dict[str, str] = {}  # profissional_id -> status (testes preenchem)
        self.selos: dict[str, datetime] = {}  # profissional_id -> data da verificação aprovada
        self.profissionais: set[str] = set()
        self.status_perfis: dict[str, str] = {}  # testes: recusado/suspenso (padrão em_analise)
        self.nascimentos: dict[str, date] = {}
        self.acessos: set[str] = set()  # contas que já entraram (`last_sign_in_at`)
        self.criadas_em: dict[str, datetime] = {}

    def adicionar(self, perfil: PerfilDetalhe) -> None:
        self._perfis[perfil.id] = perfil

    def ids_para_aviso(self, depois_de: str | None, limite: int) -> list[str]:
        return sorted(i for i in self._perfis if depois_de is None or i > depois_de)[:limite]

    # O contexto liga: quantas avaliações publicadas a pessoa recebeu (no Postgres, consulta).
    contar_avaliacoes: Callable[[str], int] | None = None

    def detalhe(self, usuario_id: str) -> PerfilDetalhe | None:
        achado = self._perfis.get(usuario_id)
        if achado is None or self.contar_avaliacoes is None:
            return achado
        total = self.contar_avaliacoes(usuario_id)
        return replace(achado, avaliacoes_total=total) if total else achado

    def garantir(self, usuario_id: str, nome: object = None) -> PerfilDetalhe | None:
        if usuario_id not in self._perfis:
            self._perfis[usuario_id] = PerfilDetalhe(
                usuario_id, nome if isinstance(nome, str) else None, PapelUsuario.CLIENTE
            )
        return self._perfis[usuario_id]

    def atualizar_nome(self, usuario_id: str, nome: str) -> None:
        atual = self.garantir(usuario_id)
        if atual is not None:
            self._perfis[usuario_id] = replace(atual, nome=nome)

    def selos_conferidos_em(self, ids: Sequence[str]) -> dict[str, datetime]:
        return {i: self.selos[i] for i in ids if i in self.selos}

    def status_verificacao(self, usuario_id: str) -> str | None:
        return self.verificacoes.get(usuario_id)

    def tem_perfil_profissional(self, usuario_id: str) -> bool:
        return usuario_id in self.profissionais

    def status_perfil_profissional(self, usuario_id: str) -> str | None:
        if usuario_id not in self.profissionais:
            return None
        return self.status_perfis.get(usuario_id, "em_analise")

    def cpf_disponivel(self, cpf: str) -> bool:
        return cpf not in self._cpfs

    def tem_cpf(self, usuario_id: str) -> bool:
        return usuario_id in self._cpfs.values()

    def cpf_do_usuario(self, usuario_id: str) -> str | None:
        return next((cpf for cpf, dono in self._cpfs.items() if dono == usuario_id), None)

    def registrar_dados_privados(
        self,
        usuario_id: str,
        cpf: str | None = None,
        telefone: str | None = None,
        data_nascimento: object | None = None,
    ) -> bool:
        novo = False
        if isinstance(data_nascimento, date):
            self.nascimentos.setdefault(usuario_id, data_nascimento)
        if cpf is not None:
            dono = self._cpfs.get(cpf)
            if dono is not None and dono != usuario_id:
                raise Duplicado("Este CPF já está cadastrado em outra conta.")
            if dono != usuario_id and usuario_id not in self._cpfs.values():
                self._cpfs[cpf] = usuario_id
                novo = True
        if telefone:
            digitos_tel = "".join(c for c in telefone if c.isdigit())
            if digitos_tel.startswith("55") and len(digitos_tel) in (12, 13):
                digitos_tel = digitos_tel[2:]
            if digitos_tel:
                self._telefones[digitos_tel] = usuario_id
        return novo

    def data_nascimento(self, usuario_id: str) -> date | None:
        return self.nascimentos.get(usuario_id)

    def pode_vincular_sem_sessao(
        self, usuario_id: str, email: str, agora: datetime, janela: timedelta
    ) -> bool:
        conhecido = self.emails.get(usuario_id)
        if conhecido is not None and conhecido != email.strip().lower():
            return False
        if usuario_id in self.acessos:
            return False
        return agora - self.criadas_em.setdefault(usuario_id, agora) <= janela

    def email_por_identificador(self, digitos: str) -> str | None:
        uid = self._cpfs.get(digitos)
        if uid is None:
            tel = digitos[2:] if digitos.startswith("55") and len(digitos) in (12, 13) else digitos
            uid = self._telefones.get(tel)
        return self.emails.get(uid) if uid else None

    def vincular_cadastro(
        self,
        usuario_id: str,
        email: str,
        nome: str,
        cpf: str | None = None,
        telefone: str | None = None,
        data_nascimento: object | None = None,
    ) -> bool:
        self.emails[usuario_id] = email.strip().lower()
        self.garantir(usuario_id, nome)
        return self.registrar_dados_privados(usuario_id, cpf, telefone, data_nascimento)


class VerificacoesEmMemoria:
    def __init__(self) -> None:
        self._itens: list[Verificacao] = []

    def enviar(
        self,
        profissional_id: str,
        nivel: str,
        documentos: Sequence[DocumentoVerificacao],
        agora: datetime,
    ) -> Verificacao:
        nova = Verificacao(
            f"ver-{len(self._itens) + 1}", profissional_id, nivel, "enviada", agora,
            tuple(documentos),
        )  # fmt: skip
        self._itens.append(nova)
        return nova

    def da_pessoa(self, profissional_id: str) -> Sequence[Verificacao]:
        return tuple(v for v in reversed(self._itens) if v.profissional_id == profissional_id)


def calcular_nota_publica(
    avaliacoes: Sequence[Avaliacao],
    *,
    recentes_quantidade: int = 5,
    recentes_peso: int = 2,
) -> float | None:
    """Espelho em memória de `public.nota_publica_profissional` (migration 20261127061100, 12.3):
    as N avaliações publicadas mais recentes pesam P; as demais pesam 1; 2 casas (half-up)."""
    validas = [
        a
        for a in avaliacoes
        if a.direcao == "cliente_para_profissional" and a.status == "publicada"
    ]
    if not validas:
        return None
    ordenadas = sorted(validas, key=lambda a: (a.criada_em, a.id or ""), reverse=True)
    soma = Decimal(0)
    pesos = Decimal(0)
    for pos, av in enumerate(ordenadas, start=1):
        nota = (
            Decimal(str(av.nota_decimal)) if av.nota_decimal is not None else Decimal(av.nota_geral)
        )
        peso = Decimal(recentes_peso if pos <= recentes_quantidade else 1)
        soma += nota * peso
        pesos += peso
    if pesos == 0:
        return None
    return float((soma / pesos).quantize(Decimal("0.01"), rounding=ROUND_HALF_UP))


class AvaliacoesEmMemoria:
    def __init__(self, *, recentes_quantidade: int = 5, recentes_peso: int = 2) -> None:
        self._itens: dict[tuple[str, str], Avaliacao] = {}
        self._seq = 0
        self.recentes_quantidade = recentes_quantidade
        self.recentes_peso = recentes_peso

    def obter(self, pedido_id: str, direcao: str) -> Avaliacao | None:
        return self._itens.get((pedido_id, direcao))

    def obter_por_id(self, avaliacao_id: str) -> Avaliacao | None:
        return next((a for a in self._itens.values() if a.id == avaliacao_id), None)

    def salvar(self, avaliacao: Avaliacao) -> None:
        chave = (avaliacao.pedido_id, avaliacao.direcao)
        if avaliacao.id is None:
            self._seq += 1
            avaliacao = replace(avaliacao, id=f"av-{self._seq}")
        self._itens[chave] = avaliacao

    def responder(self, avaliacao_id: str, resposta: str) -> Avaliacao | None:
        achada = self.obter_por_id(avaliacao_id)
        if achada is None or achada.resposta is not None:
            return None
        atualizada = replace(achada, resposta=resposta)
        self._itens[(achada.pedido_id, achada.direcao)] = atualizada
        return atualizada

    def definir_status(self, avaliacao_id: str, status: str) -> Avaliacao | None:
        achada = self.obter_por_id(avaliacao_id)
        if achada is None:
            return None
        atualizada = replace(achada, status=status)
        self._itens[(achada.pedido_id, achada.direcao)] = atualizada
        return atualizada

    def recebidas(self, avaliado_id: str) -> Sequence[Avaliacao]:
        achadas = [
            a
            for a in self._itens.values()
            if a.avaliado_id == avaliado_id and a.status == "publicada"
        ]
        return tuple(sorted(achadas, key=lambda a: a.criada_em, reverse=True))

    def media_recebida(self, avaliado_id: str) -> float | None:
        """Nota pública (12.3): peso nas N recentes, como `nota_publica_profissional`."""
        recebidas = [a for a in self._itens.values() if a.avaliado_id == avaliado_id]
        return calcular_nota_publica(
            recebidas,
            recentes_quantidade=self.recentes_quantidade,
            recentes_peso=self.recentes_peso,
        )


class RecusasEmMemoria:
    def __init__(self) -> None:
        self._itens: dict[tuple[str, str], RecusaPedido] = {}

    def recusar(self, recusa: RecusaPedido) -> None:
        self._itens.setdefault((recusa.pedido_id, recusa.profissional_id), recusa)

    def do_profissional(self, profissional_id: str) -> Sequence[RecusaPedido]:
        return tuple(r for (_, p), r in self._itens.items() if p == profissional_id)


class NotasMaterialEmMemoria:
    def __init__(self) -> None:
        self._itens: list[NotaMaterial] = []

    def registrar(self, nota: NotaMaterial) -> NotaMaterial:
        if not nota.id:
            nota = replace(nota, id=f"nm-{len(self._itens) + 1}")
        if not nota.item_ids:
            nota = replace(
                nota, item_ids=tuple(f"{nota.id}-i{n}" for n in range(1, len(nota.itens) + 1))
            )
        self._itens.append(nota)
        return nota

    def do_pedido(self, pedido_id: str) -> Sequence[NotaMaterial]:
        return tuple(n for n in self._itens if n.pedido_id == pedido_id)
