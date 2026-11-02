"""CLI administrativa do Trato para gestão segura da equipe e auditoria.

Permite:
- Aplicar o seed dos fundadores (João Vitor, Emanoel, Gabriel).
- Listar membros da equipe e respectivos papéis e alçadas.
- Ativar/desativar membros da equipe.
- Verificar a integridade criptográfica da cadeia de auditoria SHA-256.
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

from trato.persistencia.conexao import Banco


def aplicar_seed_fundadores(banco: Banco) -> None:
    caminho_sql = (
        Path(__file__).resolve().parents[3] / "supabase" / "seeds" / "seed_admin_fundadores.sql"
    )
    if not caminho_sql.exists():
        print(f"Erro: Arquivo {caminho_sql} não encontrado.", file=sys.stderr)
        sys.exit(1)

    sql = caminho_sql.read_text(encoding="utf-8")
    with banco.transacao() as con:
        con.execute(sql)
    print("Seed dos administradores fundadores aplicado com sucesso!")
    print("- João Vitor Cardoso (administrador)")
    print("- Emanoel Cabral (administrador)")
    print("- Gabriel Victor (administrador)")


def listar_equipe(banco: Banco) -> None:
    with banco.transacao() as con:
        linhas = con.execute(
            "select e.usuario_id, u.nome, e.papel, e.ativo, e.alcada_centavos, e.criado_em "
            "from public.equipe e "
            "left join public.usuarios u on u.id = e.usuario_id "
            "order by e.criado_em"
        ).fetchall()
    if not linhas:
        print("Nenhum membro na equipe.")
        return
    print(f"{'Nome':<25} | {'Papel':<15} | {'Ativo':<6} | {'Alçada':<12} | ID")
    print("-" * 80)
    for row in linhas:
        nome = row["nome"] or "(sem nome)"
        alcada = f"R$ {row['alcada_centavos'] / 100:.2f}" if row["alcada_centavos"] else "Ilimitada"
        print(
            f"{nome:<25} | {row['papel']:<15} | {str(row['ativo']):<6} | "
            f"{alcada:<12} | {row['usuario_id']}"
        )


def verificar_auditoria(banco: Banco) -> None:
    with banco.transacao() as con:
        primeira_falha = con.execute(
            "select public.verificar_cadeia_auditoria() as primeira_falha"
        ).fetchone()["primeira_falha"]
    if primeira_falha is None:
        print("Trilha de auditoria 100% íntegra (cadeia SHA-256 intacta).")
    else:
        print(
            f"Alerta: quebra de integridade na cadeia de auditoria no registro {primeira_falha}!",
            file=sys.stderr,
        )
        sys.exit(1)


def main() -> None:
    parser = argparse.ArgumentParser(description="CLI de Gestão Administrativa do Trato")
    sub = parser.add_subparsers(dest="comando", required=True)

    sub.add_parser("seed-fundadores", help="Cadastra ou atualiza os 3 administradores fundadores")
    sub.add_parser("listar", help="Lista todos os membros da equipe cadastrados")
    sub.add_parser(
        "verificar-auditoria", help="Confere a integridade criptográfica da cadeia de auditoria"
    )

    args = parser.parse_args()
    banco = Banco()

    if args.comando == "seed-fundadores":
        aplicar_seed_fundadores(banco)
    elif args.comando == "listar":
        listar_equipe(banco)
    elif args.comando == "verificar-auditoria":
        verificar_auditoria(banco)


if __name__ == "__main__":
    main()
