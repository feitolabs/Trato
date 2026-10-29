"""Persistência real (Postgres/Supabase). Os repositórios em memória continuam para testes."""

from trato.persistencia.conexao import Banco

__all__ = ["Banco"]
