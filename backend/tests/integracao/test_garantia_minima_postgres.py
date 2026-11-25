"""B43 no Postgres: o piso de garantia por categoria vem do slug."""

from __future__ import annotations

import pytest

from trato.garantias.config import garantia_minima_do_slug

pytestmark = pytest.mark.integracao


def test_config_do_banco_traz_o_piso_por_categoria(cenario):
    c = cenario
    with c.local.admin() as con:
        slug = con.execute(
            "select slug from public.categorias where id = %s", (c.categoria_id,)
        ).fetchone()[0]
    garantias = c.contexto.config.carregar().garantias
    assert garantias.minimo_da_categoria(c.categoria_id) == garantia_minima_do_slug(slug)
    assert garantias.minimo_da_categoria(c.categoria_id) >= 30
