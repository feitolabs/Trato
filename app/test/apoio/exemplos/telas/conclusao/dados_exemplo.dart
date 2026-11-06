import 'package:trato/telas/conclusao/modelos.dart';

const resumoConclusaoExemplo = ResumoConclusao(
  numeroPedido: '#4821',
  nomeProfissional: 'Carlos',
  legendaFotoAntes: 'Antes · 14h08',
  legendaFotoDepois: 'Depois · 16h52',
  orcamentoCentavos: 38000,
  aditivoCentavos: 4500,
  codigo: '7305',
  avisoLiberacao: 'Confirmação automática em 48 horas, salvo disputa aberta. '
      'Ao confirmar, a garantia de 90 dias começa a contar.',
);

const dadosAvaliacaoExemplo = DadosAvaliacao(
  nomeProfissional: 'Carlos',
  valorLiberadoCentavos: 42500,
  criterios: ['Pontualidade', 'Qualidade', 'Limpeza', 'Comunicação', 'Preço justo'],
  gorjetasCentavos: [1000, 2000],
);

const dadosRelatoExemplo = DadosRelatoProblema(
  titulo: 'Vazamento na pia · Joana Ribeiro',
  valorCongeladoCentavos: 22000,
  motivos: [
    'O problema voltou ou não foi resolvido',
    'Qualidade abaixo do combinado',
    'Cobrança extra não combinada',
    'Dano no local',
    'Outro motivo',
  ],
  solucoes: ['Retrabalho sem custo', 'Reembolso parcial', 'Reembolso total'],
  prazoRespostaHoras: 48,
  nomeProfissional: 'A profissional',
);

final dadosGarantiaExemplo = DadosGarantia(
  titulo: 'Pintura da sala · Rafael Souza',
  diasTotal: 90,
  diasRestantes: 64,
  fimEm: DateTime(2026, 12, 31),
  cobre: 'Refazer o que está no orçamento: descascado, manchas, falhas',
  naoCobre: 'Não cobre: infiltração na parede e serviços fora do escopo',
  prazoAtendimentoDias: 7,
);
