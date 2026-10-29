"""Gera as tabelas Markdown de `docs/simulacao-margem.md`.

Os valores abaixo são HIPÓTESES de simulação, não configuração de produção:
- custos do provedor: ESTIMATIVAS até haver proposta comercial (P7);
- faixas e mínimo da regra progressiva: hipótese até o João decidir P2.

Uso (a partir de ``backend/``): ``PYTHONPATH=src python -m trato.margem.relatorio``.
"""

from __future__ import annotations

from trato.margem.regras import Faixa, RegraTaxa, TaxaProgressiva, TaxaUnica
from trato.margem.simulador import Metodo, PremissasCusto, simular_margem
from trato.pagamentos.custo import ConfigCustoPagamento, TaxaMeio

TICKETS = (8_000, 15_000, 30_000, 50_000, 100_000, 300_000)
METODOS = (Metodo.pix(), Metodo.cartao(1), Metodo.cartao(3), Metodo.cartao(6))

# ESTIMATIVAS (P7): Pix 1,19%; cartão 3,99% + R$ 0,39; adicional de parcelamento chutado.
CUSTO_PROVEDOR = ConfigCustoPagamento(
    pix=TaxaMeio(percentual_bps=119),
    cartao=TaxaMeio(percentual_bps=399, fixo_centavos=39),
    adicional_parcelamento_bps={3: 150, 6: 300},
)
# Hipóteses de risco e operação.
PREMISSAS = PremissasCusto(
    chargeback_bps_pix=0,
    chargeback_bps_cartao=50,  # 0,5% do ticket
    suporte_centavos=300,  # R$ 3,00 por serviço
    garantia_centavos=0,
    tributos_bps=0,
    incentivo_centavos=0,
)
REGRAS: dict[str, RegraTaxa] = {
    "5% fixa (mín. R$ 5,00)": TaxaUnica(500, minimo_centavos=500),
    "7,5% fixa (mín. R$ 5,00)": TaxaUnica(750, minimo_centavos=500),
    "Progressiva 7,5% / 5% / 3,5% (mín. R$ 5,00)": TaxaProgressiva(
        faixas=(Faixa(50_000, 750), Faixa(150_000, 500), Faixa(None, 350)),
        minimo_centavos=500,
    ),
}


def reais(centavos: int) -> str:
    sinal = "-" if centavos < 0 else ""
    inteiro, resto = divmod(abs(centavos), 100)
    return f"{sinal}R$ {inteiro:,}".replace(",", ".") + f",{resto:02d}"


def pct(bps: int | None) -> str:
    if bps is None:
        return "—"
    sinal = "-" if bps < 0 else ""
    inteiro, resto = divmod(abs(bps), 100)
    return f"{sinal}{inteiro},{resto:02d}%"


def gerar_tabelas() -> str:
    linhas: list[str] = []
    negativos: dict[str, dict[str, list[str]]] = {}
    for nome, regra in REGRAS.items():
        linhas += [
            f"### {nome}",
            "",
            "| Ticket | Método | Taxa Trato | Provedor (est.) | Líquido profissional "
            "| Margem Trato | Margem % da taxa |",
            "|---:|---|---:|---:|---:|---:|---:|",
        ]
        for ticket in TICKETS:
            for metodo in METODOS:
                r = simular_margem(ticket, metodo, regra, CUSTO_PROVEDOR, PREMISSAS)
                alerta = " ⚠️" if r.margem_negativa else ""
                linhas.append(
                    f"| {reais(ticket)} | {metodo.rotulo} | {reais(r.taxa_trato_centavos)} "
                    f"| {reais(r.custo_provedor_centavos)} "
                    f"| {reais(r.liquido_profissional_centavos)} "
                    f"| {reais(r.margem_centavos)}{alerta} | {pct(r.margem_bps_da_taxa)} |"
                )
                if r.margem_negativa:
                    negativos.setdefault(nome, {}).setdefault(metodo.rotulo, []).append(
                        reais(ticket)
                    )
        linhas.append("")
    linhas += ["### Onde a margem fica negativa", ""]
    for nome in REGRAS:
        casos = negativos.get(nome)
        if not casos:
            linhas.append(f"- **{nome}:** nenhum caso simulado.")
            continue
        detalhe = "; ".join(f"{rotulo}: {', '.join(t)}" for rotulo, t in casos.items())
        linhas.append(f"- **{nome}:** {detalhe}")
    return "\n".join(linhas) + "\n"


if __name__ == "__main__":
    print(gerar_tabelas())
