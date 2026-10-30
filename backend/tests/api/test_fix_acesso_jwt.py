"""B1: o token só vale se o emissor (`iss`) é o do projeto; M11: criação no primeiro login."""

from __future__ import annotations

from datetime import UTC, datetime, timedelta

import jwt

from trato.api.auth import PapelUsuario
from trato.api.auth_supabase import ProvedorAuthSupabase
from trato.persistencia.usuarios import PerfilUsuario

SEGREDO = "segredo-de-teste-com-tamanho-suficiente-123456"
EMISSOR = "https://projeto-teste.supabase.test/auth/v1"
UID = "11111111-1111-1111-1111-111111111111"


class UsuariosFalso:
    def __init__(self, existente=True):
        self.perfis = (
            {UID: PerfilUsuario(UID, "Maria", "ativo", PapelUsuario.CLIENTE)} if existente else {}
        )
        self.criados: list[tuple[str, object]] = []

    def perfil(self, usuario_id):
        return self.perfis.get(usuario_id)

    def garantir(self, usuario_id, nome=None):
        self.criados.append((usuario_id, nome))
        self.perfis[usuario_id] = PerfilUsuario(usuario_id, "Novo", "ativo", PapelUsuario.CLIENTE)
        return self.perfis[usuario_id]


def _token(**extra):
    carga = {
        "sub": UID,
        "aud": "authenticated",
        "exp": datetime.now(UTC) + timedelta(hours=1),
        **extra,
    }
    return jwt.encode(carga, SEGREDO, "HS256")


def _auth(usuarios, **kw):
    return ProvedorAuthSupabase(usuarios, segredo_hs256=lambda: SEGREDO, **kw)


def test_emissor_certo_entra_errado_ou_ausente_nao():
    auth = _auth(UsuariosFalso(), emissor=EMISSOR)
    assert auth.autenticar(_token(iss=EMISSOR)) is not None
    assert auth.autenticar(_token(iss="https://outro-projeto.supabase.test/auth/v1")) is None
    assert auth.autenticar(_token()) is None  # sem iss


def test_sem_emissor_configurado_o_comportamento_antigo_continua():
    assert _auth(UsuariosFalso()).autenticar(_token()) is not None


def test_primeiro_login_chama_garantir_so_uma_vez_e_nao_para_anonimo():
    usuarios = UsuariosFalso(existente=False)
    auth = _auth(usuarios)
    assert auth.autenticar(_token(is_anonymous=True)) is None
    assert usuarios.criados == []
    usuario = auth.autenticar(_token(user_metadata={"full_name": "Maria", "papel": "equipe"}))
    assert usuario is not None and usuario.papel is PapelUsuario.CLIENTE
    assert usuarios.criados == [(UID, "Maria")]
    auth.autenticar(_token())  # já existe: não cria de novo
    assert len(usuarios.criados) == 1


def test_criacao_pode_ser_desligada():
    usuarios = UsuariosFalso(existente=False)
    assert _auth(usuarios, criar_no_primeiro_login=False).autenticar(_token()) is None
    assert usuarios.criados == []
