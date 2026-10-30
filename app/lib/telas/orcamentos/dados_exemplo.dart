// ignore_for_file: prefer_const_constructors (DateTime não é constante)
import 'modelos.dart';

// DADOS PROVISÓRIOS, copiados do protótipo (telas 12 e 13). Onde o protótipo não mostra o
// valor (André Lopes e o detalhe da Joana e dele), vai o marcador "[...]" no mesmo estilo
// de "[Foto]" e "[Cliente]" do PDF.

const resumoPedidoExemplo = ResumoPedido(
  numero: '4821',
  titulo: 'Troca de tomadas e chuveiro',
  recebidos: 3,
  limite: 5,
  tempoRestante: '31 horas',
);

final orcamentosExemplo = [
  Orcamento(
    id: 'joana',
    profissional: 'Joana Ribeiro',
    iniciais: 'JR',
    verificacao: 'Verificado',
    totalCentavos: 34000,
    nota: 4.7,
    notaResumo: '4,7 · 22 avaliações',
    servicosResumo: '25 · 96% concluídos',
    servicosConcluidos: 25,
    quando: 'Sáb, 31/10 · 4 h',
    inicio: DateTime(2026, 10, 31, 9),
    garantia: '60 dias',
    observacao: 'Material por conta do cliente. Lista enviada no orçamento.',
  ),
  Orcamento(
    id: 'carlos',
    profissional: 'Carlos Mendes',
    iniciais: 'CM',
    verificacao: 'Verificado Plus',
    totalCentavos: 38000,
    nota: 4.9,
    notaResumo: '4,9 · 64 avaliações',
    servicosResumo: '71 · 98% concluídos',
    servicosConcluidos: 71,
    quando: 'Qui, 29/10 · 3 h',
    inicio: DateTime(2026, 10, 29, 14),
    garantia: '90 dias',
    observacao: 'Inclui material: 2 tomadas 20 A e resistência do chuveiro.',
    detalhe: DetalheOrcamento(
      validoAte: '31/10',
      itens: [
        ItemOrcamento(descricao: 'Deslocamento', centavos: 3000),
        ItemOrcamento(descricao: 'Mão de obra · 3 horas', centavos: 24000),
        ItemOrcamento(descricao: '2 tomadas 20 A', centavos: 4600),
        ItemOrcamento(descricao: 'Resistência de chuveiro 220 V', centavos: 6400),
      ],
      notaMaterial: 'Material fornecido pelo profissional, com nota.',
      agendaTitulo: 'Quinta, 29/10, das 14h às 17h',
      agendaDetalhe: 'Remarcação só com o seu aceite',
      garantiaTitulo: 'Garantia de 90 dias',
      garantiaDetalhe: 'Retrabalho dentro do prazo e mediação com prazo definido',
      foraDoEscopo:
          'Troca de fiação embutida. Se for preciso, o profissional propõe um aditivo e você aprova antes.',
      cancelamento:
          'Reembolso integral até 24 horas antes. Depois disso, o deslocamento de R\$ 30,00 fica com o profissional.',
    ),
  ),
  Orcamento(
    id: 'andre',
    profissional: 'André Lopes',
    iniciais: 'AL',
    verificacao: 'Verificado',
    totalCentavos: 45500,
    nota: 4.8,
    notaResumo: '4,8 · [n] avaliações',
    servicosResumo: '44 · [n]% concluídos',
    servicosConcluidos: 44,
    quando: '[Dia] · [n] h',
    inicio: DateTime(2026, 11, 1, 9),
    garantia: '[n] dias',
    observacao: '[Resumo do material enviado no orçamento.]',
  ),
];
