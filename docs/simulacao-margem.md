# Simulação de margem de contribuição por serviço (V2)

> **ATENÇÃO — são estimativas.** Os custos do provedor (Pix, cartão, parcelamento) são
> **ESTIMATIVAS** até haver proposta comercial (pendência **P7**). As faixas da regra progressiva
> e o mínimo de R$ 5,00 são **hipóteses** até o João decidir a **P2**. Chargeback, suporte e
> tributos também são hipóteses. Nada aqui é configuração de produção.

Código: `backend/src/trato/margem/`. Para regerar as tabelas, a partir de `backend/`:

```bash
PYTHONPATH=src python -m trato.margem.relatorio
```

## Como a margem é calculada

```
margem = taxa do Trato − custo do provedor − chargeback esperado − suporte
         − garantia/retrabalho − tributos − incentivo
```

- Tudo em centavos inteiros e percentuais em pontos-base (7,5% = 750). Sem `float`.
  Arredondamento meio para cima, uma vez por percentual.
- Premissa de P3 (opção A): o profissional recebe `ticket − taxa do Trato`; o custo do provedor
  sai da taxa do Trato.
- Regra de taxa: **taxa única %** com mínimo em centavos, **ou** **tabela progressiva** por faixas
  (modo marginal: cada faixa vale só para a fatia do ticket; há também o modo "faixa inteira").
- Tributos incidem sobre a taxa do Trato. Chargeback esperado incide sobre o ticket, por método.

## Premissas usadas nas tabelas (todas hipóteses)

| Item | Valor |
|---|---|
| Pix (provedor, estimativa) | 1,19% |
| Cartão à vista (provedor, estimativa) | 3,99% + R$ 0,39 |
| Adicional de parcelamento (estimativa) | 3x: +1,50 p.p.; 6x: +3,00 p.p. |
| Chargeback esperado | Pix 0%; cartão 0,5% do ticket |
| Suporte | R$ 3,00 por serviço |
| Garantia/retrabalho, tributos, incentivo | 0 (a definir) |
| Taxa mínima | R$ 5,00 em todas as regras |
| Progressiva | 7,5% até R$ 500; 5% de R$ 500 a R$ 1.500; 3,5% acima (marginal) |

## Resultado

Linhas com ⚠️ têm margem negativa.

### 5% fixa (mín. R$ 5,00)

| Ticket | Método | Taxa Trato | Provedor (est.) | Líquido profissional | Margem Trato | Margem % da taxa |
|---:|---|---:|---:|---:|---:|---:|
| R$ 80,00 | Pix | R$ 5,00 | R$ 0,95 | R$ 75,00 | R$ 1,05 | 21,00% |
| R$ 80,00 | Cartão à vista | R$ 5,00 | R$ 3,58 | R$ 75,00 | -R$ 1,98 ⚠️ | -39,60% |
| R$ 80,00 | Cartão 3x | R$ 5,00 | R$ 4,78 | R$ 75,00 | -R$ 3,18 ⚠️ | -63,60% |
| R$ 80,00 | Cartão 6x | R$ 5,00 | R$ 5,98 | R$ 75,00 | -R$ 4,38 ⚠️ | -87,60% |
| R$ 150,00 | Pix | R$ 7,50 | R$ 1,79 | R$ 142,50 | R$ 2,71 | 36,13% |
| R$ 150,00 | Cartão à vista | R$ 7,50 | R$ 6,38 | R$ 142,50 | -R$ 2,63 ⚠️ | -35,07% |
| R$ 150,00 | Cartão 3x | R$ 7,50 | R$ 8,63 | R$ 142,50 | -R$ 4,88 ⚠️ | -65,07% |
| R$ 150,00 | Cartão 6x | R$ 7,50 | R$ 10,88 | R$ 142,50 | -R$ 7,13 ⚠️ | -95,07% |
| R$ 300,00 | Pix | R$ 15,00 | R$ 3,57 | R$ 285,00 | R$ 8,43 | 56,20% |
| R$ 300,00 | Cartão à vista | R$ 15,00 | R$ 12,36 | R$ 285,00 | -R$ 1,86 ⚠️ | -12,40% |
| R$ 300,00 | Cartão 3x | R$ 15,00 | R$ 16,86 | R$ 285,00 | -R$ 6,36 ⚠️ | -42,40% |
| R$ 300,00 | Cartão 6x | R$ 15,00 | R$ 21,36 | R$ 285,00 | -R$ 10,86 ⚠️ | -72,40% |
| R$ 500,00 | Pix | R$ 25,00 | R$ 5,95 | R$ 475,00 | R$ 16,05 | 64,20% |
| R$ 500,00 | Cartão à vista | R$ 25,00 | R$ 20,34 | R$ 475,00 | -R$ 0,84 ⚠️ | -3,36% |
| R$ 500,00 | Cartão 3x | R$ 25,00 | R$ 27,84 | R$ 475,00 | -R$ 8,34 ⚠️ | -33,36% |
| R$ 500,00 | Cartão 6x | R$ 25,00 | R$ 35,34 | R$ 475,00 | -R$ 15,84 ⚠️ | -63,36% |
| R$ 1.000,00 | Pix | R$ 50,00 | R$ 11,90 | R$ 950,00 | R$ 35,10 | 70,20% |
| R$ 1.000,00 | Cartão à vista | R$ 50,00 | R$ 40,29 | R$ 950,00 | R$ 1,71 | 3,42% |
| R$ 1.000,00 | Cartão 3x | R$ 50,00 | R$ 55,29 | R$ 950,00 | -R$ 13,29 ⚠️ | -26,58% |
| R$ 1.000,00 | Cartão 6x | R$ 50,00 | R$ 70,29 | R$ 950,00 | -R$ 28,29 ⚠️ | -56,58% |
| R$ 3.000,00 | Pix | R$ 150,00 | R$ 35,70 | R$ 2.850,00 | R$ 111,30 | 74,20% |
| R$ 3.000,00 | Cartão à vista | R$ 150,00 | R$ 120,09 | R$ 2.850,00 | R$ 11,91 | 7,94% |
| R$ 3.000,00 | Cartão 3x | R$ 150,00 | R$ 165,09 | R$ 2.850,00 | -R$ 33,09 ⚠️ | -22,06% |
| R$ 3.000,00 | Cartão 6x | R$ 150,00 | R$ 210,09 | R$ 2.850,00 | -R$ 78,09 ⚠️ | -52,06% |

### 7,5% fixa (mín. R$ 5,00)

| Ticket | Método | Taxa Trato | Provedor (est.) | Líquido profissional | Margem Trato | Margem % da taxa |
|---:|---|---:|---:|---:|---:|---:|
| R$ 80,00 | Pix | R$ 6,00 | R$ 0,95 | R$ 74,00 | R$ 2,05 | 34,17% |
| R$ 80,00 | Cartão à vista | R$ 6,00 | R$ 3,58 | R$ 74,00 | -R$ 0,98 ⚠️ | -16,33% |
| R$ 80,00 | Cartão 3x | R$ 6,00 | R$ 4,78 | R$ 74,00 | -R$ 2,18 ⚠️ | -36,33% |
| R$ 80,00 | Cartão 6x | R$ 6,00 | R$ 5,98 | R$ 74,00 | -R$ 3,38 ⚠️ | -56,33% |
| R$ 150,00 | Pix | R$ 11,25 | R$ 1,79 | R$ 138,75 | R$ 6,46 | 57,42% |
| R$ 150,00 | Cartão à vista | R$ 11,25 | R$ 6,38 | R$ 138,75 | R$ 1,12 | 9,96% |
| R$ 150,00 | Cartão 3x | R$ 11,25 | R$ 8,63 | R$ 138,75 | -R$ 1,13 ⚠️ | -10,04% |
| R$ 150,00 | Cartão 6x | R$ 11,25 | R$ 10,88 | R$ 138,75 | -R$ 3,38 ⚠️ | -30,04% |
| R$ 300,00 | Pix | R$ 22,50 | R$ 3,57 | R$ 277,50 | R$ 15,93 | 70,80% |
| R$ 300,00 | Cartão à vista | R$ 22,50 | R$ 12,36 | R$ 277,50 | R$ 5,64 | 25,07% |
| R$ 300,00 | Cartão 3x | R$ 22,50 | R$ 16,86 | R$ 277,50 | R$ 1,14 | 5,07% |
| R$ 300,00 | Cartão 6x | R$ 22,50 | R$ 21,36 | R$ 277,50 | -R$ 3,36 ⚠️ | -14,93% |
| R$ 500,00 | Pix | R$ 37,50 | R$ 5,95 | R$ 462,50 | R$ 28,55 | 76,13% |
| R$ 500,00 | Cartão à vista | R$ 37,50 | R$ 20,34 | R$ 462,50 | R$ 11,66 | 31,09% |
| R$ 500,00 | Cartão 3x | R$ 37,50 | R$ 27,84 | R$ 462,50 | R$ 4,16 | 11,09% |
| R$ 500,00 | Cartão 6x | R$ 37,50 | R$ 35,34 | R$ 462,50 | -R$ 3,34 ⚠️ | -8,91% |
| R$ 1.000,00 | Pix | R$ 75,00 | R$ 11,90 | R$ 925,00 | R$ 60,10 | 80,13% |
| R$ 1.000,00 | Cartão à vista | R$ 75,00 | R$ 40,29 | R$ 925,00 | R$ 26,71 | 35,61% |
| R$ 1.000,00 | Cartão 3x | R$ 75,00 | R$ 55,29 | R$ 925,00 | R$ 11,71 | 15,61% |
| R$ 1.000,00 | Cartão 6x | R$ 75,00 | R$ 70,29 | R$ 925,00 | -R$ 3,29 ⚠️ | -4,39% |
| R$ 3.000,00 | Pix | R$ 225,00 | R$ 35,70 | R$ 2.775,00 | R$ 186,30 | 82,80% |
| R$ 3.000,00 | Cartão à vista | R$ 225,00 | R$ 120,09 | R$ 2.775,00 | R$ 86,91 | 38,63% |
| R$ 3.000,00 | Cartão 3x | R$ 225,00 | R$ 165,09 | R$ 2.775,00 | R$ 41,91 | 18,63% |
| R$ 3.000,00 | Cartão 6x | R$ 225,00 | R$ 210,09 | R$ 2.775,00 | -R$ 3,09 ⚠️ | -1,37% |

### Progressiva 7,5% / 5% / 3,5% (mín. R$ 5,00)

| Ticket | Método | Taxa Trato | Provedor (est.) | Líquido profissional | Margem Trato | Margem % da taxa |
|---:|---|---:|---:|---:|---:|---:|
| R$ 80,00 | Pix | R$ 6,00 | R$ 0,95 | R$ 74,00 | R$ 2,05 | 34,17% |
| R$ 80,00 | Cartão à vista | R$ 6,00 | R$ 3,58 | R$ 74,00 | -R$ 0,98 ⚠️ | -16,33% |
| R$ 80,00 | Cartão 3x | R$ 6,00 | R$ 4,78 | R$ 74,00 | -R$ 2,18 ⚠️ | -36,33% |
| R$ 80,00 | Cartão 6x | R$ 6,00 | R$ 5,98 | R$ 74,00 | -R$ 3,38 ⚠️ | -56,33% |
| R$ 150,00 | Pix | R$ 11,25 | R$ 1,79 | R$ 138,75 | R$ 6,46 | 57,42% |
| R$ 150,00 | Cartão à vista | R$ 11,25 | R$ 6,38 | R$ 138,75 | R$ 1,12 | 9,96% |
| R$ 150,00 | Cartão 3x | R$ 11,25 | R$ 8,63 | R$ 138,75 | -R$ 1,13 ⚠️ | -10,04% |
| R$ 150,00 | Cartão 6x | R$ 11,25 | R$ 10,88 | R$ 138,75 | -R$ 3,38 ⚠️ | -30,04% |
| R$ 300,00 | Pix | R$ 22,50 | R$ 3,57 | R$ 277,50 | R$ 15,93 | 70,80% |
| R$ 300,00 | Cartão à vista | R$ 22,50 | R$ 12,36 | R$ 277,50 | R$ 5,64 | 25,07% |
| R$ 300,00 | Cartão 3x | R$ 22,50 | R$ 16,86 | R$ 277,50 | R$ 1,14 | 5,07% |
| R$ 300,00 | Cartão 6x | R$ 22,50 | R$ 21,36 | R$ 277,50 | -R$ 3,36 ⚠️ | -14,93% |
| R$ 500,00 | Pix | R$ 37,50 | R$ 5,95 | R$ 462,50 | R$ 28,55 | 76,13% |
| R$ 500,00 | Cartão à vista | R$ 37,50 | R$ 20,34 | R$ 462,50 | R$ 11,66 | 31,09% |
| R$ 500,00 | Cartão 3x | R$ 37,50 | R$ 27,84 | R$ 462,50 | R$ 4,16 | 11,09% |
| R$ 500,00 | Cartão 6x | R$ 37,50 | R$ 35,34 | R$ 462,50 | -R$ 3,34 ⚠️ | -8,91% |
| R$ 1.000,00 | Pix | R$ 62,50 | R$ 11,90 | R$ 937,50 | R$ 47,60 | 76,16% |
| R$ 1.000,00 | Cartão à vista | R$ 62,50 | R$ 40,29 | R$ 937,50 | R$ 14,21 | 22,74% |
| R$ 1.000,00 | Cartão 3x | R$ 62,50 | R$ 55,29 | R$ 937,50 | -R$ 0,79 ⚠️ | -1,26% |
| R$ 1.000,00 | Cartão 6x | R$ 62,50 | R$ 70,29 | R$ 937,50 | -R$ 15,79 ⚠️ | -25,26% |
| R$ 3.000,00 | Pix | R$ 140,00 | R$ 35,70 | R$ 2.860,00 | R$ 101,30 | 72,36% |
| R$ 3.000,00 | Cartão à vista | R$ 140,00 | R$ 120,09 | R$ 2.860,00 | R$ 1,91 | 1,36% |
| R$ 3.000,00 | Cartão 3x | R$ 140,00 | R$ 165,09 | R$ 2.860,00 | -R$ 43,09 ⚠️ | -30,78% |
| R$ 3.000,00 | Cartão 6x | R$ 140,00 | R$ 210,09 | R$ 2.860,00 | -R$ 88,09 ⚠️ | -62,92% |

### Onde a margem fica negativa

- **5% fixa (mín. R$ 5,00):** Cartão à vista: R$ 80,00, R$ 150,00, R$ 300,00, R$ 500,00; Cartão 3x: R$ 80,00, R$ 150,00, R$ 300,00, R$ 500,00, R$ 1.000,00, R$ 3.000,00; Cartão 6x: R$ 80,00, R$ 150,00, R$ 300,00, R$ 500,00, R$ 1.000,00, R$ 3.000,00
- **7,5% fixa (mín. R$ 5,00):** Cartão à vista: R$ 80,00; Cartão 3x: R$ 80,00, R$ 150,00; Cartão 6x: R$ 80,00, R$ 150,00, R$ 300,00, R$ 500,00, R$ 1.000,00, R$ 3.000,00
- **Progressiva 7,5% / 5% / 3,5% (mín. R$ 5,00):** Cartão à vista: R$ 80,00; Cartão 3x: R$ 80,00, R$ 150,00, R$ 1.000,00, R$ 3.000,00; Cartão 6x: R$ 80,00, R$ 150,00, R$ 300,00, R$ 500,00, R$ 1.000,00, R$ 3.000,00


## Leitura

- **Pix nunca fica negativo** nas três regras e em todos os tickets simulados.
- **Cartão parcelado é o risco.** Em 6x a margem é negativa em todos os tickets, mesmo com 7,5%.
  Em 3x, a 5% fixa é negativa em todos os tickets; a 7,5% só até R$ 150.
- **5% fixa** perde dinheiro no cartão (inclusive à vista) até R$ 500.
- **Progressiva:** tira receita dos tickets altos. Em R$ 1.000 e R$ 3.000 no cartão 3x a margem
  fica negativa, e à vista em R$ 3.000 sobra só ~R$ 1,91. Com o custo percentual do cartão, ticket
  alto exige taxa que cubra o provedor.
- **Tickets baixos (R$ 80):** o custo fixo do cartão e o suporte comem a taxa em qualquer regra.

Pergunta em aberto para o João: o parcelado deve ter acréscimo ao cliente (opção C da P3), limite
de parcelas ou taxa maior? Antes de decidir a tabela progressiva (D2), confirmar os custos reais
na proposta do provedor (P7).
