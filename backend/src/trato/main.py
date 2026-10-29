"""API do Trato."""

from trato import __version__
from trato.api.fabrica import criar_app_da_config
from trato.config import obter_config

# TRATO_PERSISTENCIA=memoria (padrão) | postgres: ver docs/api-persistencia.md.
app = criar_app_da_config()


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
