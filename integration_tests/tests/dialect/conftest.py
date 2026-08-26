"""Session fixtures for Layer 3 dialect containers."""

from __future__ import annotations

import os

import pytest
from tests.dialect.helpers import seed_postgres, seed_spanner

os.environ.setdefault("SPANNER_EMULATOR_HOST", "localhost:9010")


@pytest.fixture(scope="session")
def dialect_postgres_seeded():
    seed_postgres()


@pytest.fixture(scope="session")
def spanner_emulator_seeded():
    seed_spanner()
