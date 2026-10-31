"""O script `harness/teste_real_webhook.py` roda contra a API em memória e confere as recusas e o reenvio.

Garante que o roteiro do João funciona antes de ele usar as chaves reais.
"""

import runpy
import sys
from datetime import UTC, datetime
from pathlib import Path

from conftest import SEGREDO_WEBHOOK

HARNESS = Path(__file__).resolve().parents[3] / "harness"


def test_script_de_webhook_passa_contra_a_api_em_memoria(amb, monkeypatch, capsys):
    amb.contexto.agora = lambda: datetime.now(UTC)  # o script assina com a hora de verdade
    monkeypatch.syspath_prepend(str(HARNESS))
    import teste_real_comum

    def http_local(metodo, url, cabecalhos=None, corpo=None):
        caminho = "/" + url.split("://", 1)[1].split("/", 1)[1]
        r = amb.cliente.request(metodo, caminho, content=corpo, headers=cabecalhos or {})
        return r.status_code, r.content

    monkeypatch.setattr(teste_real_comum, "http", http_local)
    monkeypatch.setenv("TRATO_TESTE_REAL", "sim")
    monkeypatch.setenv("STRIPE_WEBHOOK_SECRET", SEGREDO_WEBHOOK)
    monkeypatch.setenv("TRATO_API_URL", "http://local")
    monkeypatch.setenv("TRATO_PERSISTENCIA", "memoria")
    sys.modules.pop("teste_real_webhook", None)

    try:
        runpy.run_path(str(HARNESS / "teste_real_webhook.py"), run_name="__main__")
    except SystemExit as saida:
        codigo = saida.code
    saida_texto = capsys.readouterr().out

    assert codigo == 0, saida_texto
    assert saida_texto.count("OK ") >= 6
    assert "0 FALHOU" in saida_texto
