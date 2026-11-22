"""B34 (Parte 1): aviso de pedido novo comum para até 20 profissionais elegíveis."""

from __future__ import annotations

from datetime import UTC, datetime

from conftest import cab
from test_profissional_upload import e2  # noqa: F401

from trato.api.auth import PapelUsuario
from trato.api.avisos import MAX_PROFISSIONAIS_AVISO_PEDIDO_NOVO, avisar_pedido_novo
from trato.api.repositorios_app import PerfilDetalhe
from trato.notificacoes import ligar_ao_contexto
from trato.notificacoes.canais import Canais, CanalApp
from trato.notificacoes.config import ConfigNotificacoes
from trato.notificacoes.eventos import MODELOS, Evento
from trato.notificacoes.repositorio import RepositorioEmMemoria
from trato.notificacoes.servico import ServicoNotificacoes
from trato.profissional.repositorio import PerfilProfissional, Regiao

AGORA = datetime(2026, 1, 1, tzinfo=UTC)

TITULO = "Novo pedido perto de você"
ENDERECO_PADRAO = {
    "logradouro": "Rua das Flores Segredo",
    "numero": "987",
    "bairro": "Centro",
    "cep": "01001-000",
}


def _ligar(e2):  # noqa: F811
    repo = RepositorioEmMemoria()
    notif = ServicoNotificacoes(repo, Canais(app=CanalApp()), ConfigNotificacoes(ativo=True))
    ligar_ao_contexto(e2.amb.cliente.app, e2.amb.contexto, notif)
    e2.amb.cliente.app.state.notificador = notif
    return repo, notif


def _add_prof(
    e2,  # noqa: F811
    uid: str,
    *,
    status_perfil: str = "aprovado",
    status_usuario: str = "ativo",
    categorias: tuple[str, ...] = ("cat-1",),
    cidades: tuple[str, ...] = ("cid-1",),
    nota: float | None = None,
    disponivel_agora: bool = False,
):
    e2.modulo.repo.salvar(
        PerfilProfissional(
            usuario_id=uid,
            status=status_perfil,
            bio=None,
            categorias=categorias,
            regioes=tuple(Regiao(c, None) for c in cidades),
            disponibilidade=(),
            portfolio=(),
            criado_em=AGORA,
            nivel_verificacao="verificado",
            disponivel_agora=disponivel_agora,
        )
    )
    e2.amb.contexto.usuarios.adicionar(
        PerfilDetalhe(
            uid, f"Prof {uid}", PapelUsuario.PROFISSIONAL, status=status_usuario, nota_publica=nota
        )
    )


def _abrir(e2, **extras):  # noqa: F811
    corpo = {
        "categoria_id": "cat-1",
        "cidade_id": "cid-1",
        "titulo": "Pintar parede da sala",
        "descricao": "Preciso pintar uma parede de 10m2.",
        "endereco": ENDERECO_PADRAO,
        **extras,
    }
    return e2.amb.cliente.post("/v1/pedidos", json=corpo, headers=cab("t-cliente"))


def _avisos(repo, usuario_id, titulo=TITULO):
    return [n for n in repo.listar(usuario_id, False, 50) if n.titulo == titulo]


def test_pedido_comum_avisa_elegiveis_e_exclui_inelegiveis(e2):  # noqa: F811
    repo, _ = _ligar(e2)
    e2.amb.contexto.usuarios.adicionar(
        PerfilDetalhe("cli-1", "Maria Privada", PapelUsuario.CLIENTE)
    )
    _add_prof(e2, "pro-ok", nota=4.8)
    _add_prof(e2, "pro-pendente", status_perfil="pendente", nota=5.0)
    _add_prof(e2, "pro-inativo", status_usuario="suspenso", nota=5.0)
    _add_prof(e2, "pro-outra-cat", categorias=("cat-2",), nota=5.0)
    _add_prof(e2, "pro-outra-cid", cidades=("cid-2",), nota=5.0)
    _add_prof(e2, "cli-1", nota=5.0)  # próprio cliente nunca recebe

    r = _abrir(e2)
    assert r.status_code == 201, r.text
    avisos = _avisos(repo, "pro-ok")
    assert len(avisos) == 1
    assert avisos[0].tipo == Evento.PEDIDO_NOVO.value
    assert MODELOS[Evento.PEDIDO_NOVO].tela == "pedido_aberto"
    texto = f"{avisos[0].titulo} {avisos[0].corpo}"
    assert "Centro" in texto
    # Sem dado pessoal do cliente nem endereço completo
    for proibido in ("Maria", "Privada", "Rua das Flores", "987", "01001-000"):
        assert proibido not in texto

    for excluido in ("pro-pendente", "pro-inativo", "pro-outra-cat", "pro-outra-cid", "cli-1"):
        assert _avisos(repo, excluido) == [], excluido


def test_pedido_direcionado_e_urgente_nao_disparam_pedido_novo(e2):  # noqa: F811
    repo, _ = _ligar(e2)
    _add_prof(e2, "pro-1", nota=4.9, disponivel_agora=True)
    _add_prof(e2, "pro-2", nota=4.5, disponivel_agora=False)

    r_dir = _abrir(e2, profissional_convidado_id="pro-1")
    assert r_dir.status_code == 201, r_dir.text
    assert _avisos(repo, "pro-1") == []
    assert _avisos(repo, "pro-2") == []
    assert len(_avisos(repo, "pro-1", "Pedido de orçamento direto para você")) == 1

    r_urg = _abrir(e2, urgente=True)
    assert r_urg.status_code == 201, r_urg.text
    assert _avisos(repo, "pro-1") == []
    assert _avisos(repo, "pro-2") == []


def test_limite_20_ordenado_por_nota_desc_com_desempate_estavel(e2):  # noqa: F811
    repo, _ = _ligar(e2)
    # 25 profissionais: notas de 2.5 a 4.9; os 20 melhores (pro-05..pro-24) devem receber.
    for i in range(25):
        _add_prof(e2, f"pro-{i:02d}", nota=round(2.5 + i * 0.1, 1))
    # Mais 2 empatados no topo com nota 5.0 para testar desempate estável por id
    _add_prof(e2, "pro-z-top", nota=5.0)
    _add_prof(e2, "pro-a-top", nota=5.0)

    r = _abrir(e2)
    assert r.status_code == 201, r.text
    notificados = [
        uid
        for uid in [f"pro-{i:02d}" for i in range(25)] + ["pro-z-top", "pro-a-top"]
        if _avisos(repo, uid)
    ]
    assert len(notificados) == MAX_PROFISSIONAIS_AVISO_PEDIDO_NOVO == 20
    assert "pro-a-top" in notificados and "pro-z-top" in notificados
    # Os 7 piores (pro-00..pro-06) ficam de fora
    for i in range(7):
        assert f"pro-{i:02d}" not in notificados


def test_idempotencia_e_respeito_a_preferencias(e2):  # noqa: F811
    repo, _ = _ligar(e2)
    _add_prof(e2, "pro-1", nota=4.9)
    _add_prof(e2, "pro-silenciado", nota=4.8)
    repo.salvar_preferencias("pro-silenciado", {"orcamentos": {"app": False}}, AGORA)

    r = _abrir(e2)
    assert r.status_code == 201, r.text
    pedido_id = r.json()["id"]
    assert len(_avisos(repo, "pro-1")) == 1
    assert _avisos(repo, "pro-silenciado") == []

    class _Req:
        def __init__(self, app):
            self.app = app

    # Chamar de novo para o mesmo pedido não duplica (idempotente por pedido+profissional)
    avisar_pedido_novo(
        _Req(e2.amb.cliente.app),
        e2.amb.contexto,
        pedido_id=pedido_id,
        categoria_id="cat-1",
        cidade_id="cid-1",
        bairro="Centro",
        cliente_id="cli-1",
    )
    assert len(_avisos(repo, "pro-1")) == 1


def test_falha_em_um_destinatario_nao_afeta_os_demais_nem_abertura(e2, monkeypatch):  # noqa: F811
    repo, _ = _ligar(e2)
    _add_prof(e2, "pro-1", nota=5.0)
    _add_prof(e2, "pro-2", nota=4.9)
    original = ServicoNotificacoes.notificar

    def quebra_um(self, evento, usuario_id, *a, **k):
        if evento is Evento.PEDIDO_NOVO and usuario_id == "pro-1":
            raise RuntimeError("falha simulada no pro-1")
        return original(self, evento, usuario_id, *a, **k)

    monkeypatch.setattr(ServicoNotificacoes, "notificar", quebra_um)
    r = _abrir(e2)
    assert r.status_code == 201, r.text
    assert _avisos(repo, "pro-1") == []
    assert len(_avisos(repo, "pro-2")) == 1
