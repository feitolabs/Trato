# Imagem do backend do Trato para o Fly.io (região gru, São Paulo).
# Contexto de build: esta pasta (backend/). Nenhum segredo entra na imagem:
# tudo vem de variáveis de ambiente (`fly secrets set`) na hora de rodar.
FROM python:3.11-slim

ENV PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    PIP_NO_CACHE_DIR=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1

WORKDIR /app

COPY pyproject.toml ./
COPY src ./src
RUN pip install .

# Sem root dentro do contêiner.
RUN useradd --system --no-create-home trato
USER trato

# O Fly encaminha para esta porta (internal_port no fly.toml).
EXPOSE 8080

# `trato.main:app` = API completa: segurança (limite de taxa, HSTS, LGPD) e /saude.
CMD ["uvicorn", "trato.main:app", "--host", "0.0.0.0", "--port", "8080"]
