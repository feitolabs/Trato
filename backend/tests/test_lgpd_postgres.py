from datetime import datetime, timezone
import pytest
from trato.persistencia.conexao import Banco
from trato.persistencia.lgpd import criar_repositorios_lgpd_postgres
from trato.lgpd.repositorios import Consentimento, PedidoExclusao
import uuid

@pytest.fixture
def banco_local():
    banco = Banco("postgresql://postgres.ornaoshsvuszquntkqsk:servico-feito-liberado@aws-1-sa-east-1.pooler.supabase.com:5432/postgres")
    banco.abrir()
    yield banco
    banco.fechar()

def test_lgpd_repositorios_postgres(banco_local):
    repos = criar_repositorios_lgpd_postgres(banco_local)
    user_id = "1c2ccca9-6603-4561-8718-ce81b6fa6973"
    
    # 1. Test pendencias
    pendencias = repos.fonte.pendencias(user_id)
    assert isinstance(pendencias, list)
    
    # 2. Test exportar
    dados = repos.fonte.exportar(user_id)
    assert isinstance(dados, dict)
    assert "usuario" in dados
    
    # 3. Test consentimento
    agora = datetime.now(timezone.utc)
    c = Consentimento(
        usuario_id=user_id,
        finalidade="termos_uso",
        aceito=True,
        versao_texto="1.0",
        registrado_em=agora,
        ip="127.0.0.1"
    )
    repos.consentimentos.registrar(c)
    hist = repos.consentimentos.historico(user_id)
    assert any(h.finalidade == "termos_uso" for h in hist)

