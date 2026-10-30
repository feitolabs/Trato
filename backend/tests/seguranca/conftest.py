from __future__ import annotations

import pytest
from ambiente_seg import Amb, montar


@pytest.fixture
def amb() -> Amb:
    return montar()
