"""TERMOS-BE-53 no Postgres local: pagamento confirmado pelo webhook libera os documentos."""

from __future__ import annotations

import pytest

from .test_ausencia_reembolso_postgres import pago_e_agendado
from .test_pagamento_postgres import migrations_novas, pg  # noqa: F401

pytestmark = pytest.mark.integracao


def test_documentos_da_contratacao_com_pagamento_real_no_postgres(pg):  # noqa: F811
    http = pg.pagto[0]
    pid, cobranca_id, _ = pago_e_agendado(pg)
    base = f"/v1/pedidos/{pid}/contratacao"
    r = http.get(base, headers=pg.token("cliente"))
    assert r.status_code == 200, r.text
    comprovante = http.get(f"{base}/comprovante.pdf", headers=pg.token("cliente"))
    assert comprovante.status_code == 200, comprovante.text
    assert cobranca_id.encode() in comprovante.content and b"Pix" in comprovante.content
    assert http.get(f"{base}/comprovante.pdf", headers=pg.token("profissional")).status_code == 403
