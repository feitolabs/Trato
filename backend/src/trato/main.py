"""API do Trato."""

from fastapi import FastAPI

from trato import __version__
from trato.api import instalar
from trato.config import obter_config

app = FastAPI(title="Trato API", version=__version__)
instalar(app)


@app.get("/saude")
def saude() -> dict[str, str | bool]:
    """Diz se a API está no ar. Não expõe nenhum segredo."""
    config = obter_config()
    return {
        "status": "ok",
        "app": "Trato",
        "versao": __version__,
        "ambiente": config.trato_ambiente,
        "supabase_configurado": bool(config.supabase_url),
        "stripe_modo_teste": config.stripe_em_modo_teste,
    }
