# Backend do Trato (Python + FastAPI)

Toda regra de dinheiro (estados do pedido, taxa, retenção, liberação, disputa) roda aqui.

## Rodar

```bash
cd backend
py -3.11 -m venv .venv
.venv/Scripts/python -m pip install -e ".[dev]"
.venv/Scripts/python -m uvicorn trato.main:app --reload
```

Abra http://127.0.0.1:8000/saude. As variáveis vêm do `.env` na raiz (modelo em `.env.example`).

## Testes

```bash
.venv/Scripts/python -m pytest -q
```
