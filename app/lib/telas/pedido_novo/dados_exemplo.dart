import 'modelos.dart';

/// DADOS PROVISÓRIOS, copiados do protótipo (tela 11). O protótipo mostra só a opção
/// marcada de "Prazo" e de "Quanto pensa gastar?"; as outras opções ainda não existem.
const formularioExemplo = FormularioPedido(
  categoria: 'Elétrica · Tomadas e chuveiro',
  servicos: [
    'Trocar tomada',
    'Instalar tomada nova',
    'Trocar chuveiro',
    'Trocar interruptor',
  ],
  servicosIniciais: {'Trocar tomada', 'Trocar chuveiro'},
  perguntaQuantidade: 'Quantas tomadas?',
  dicaQuantidade: 'Conte só as que vão ser trocadas',
  quantidadeInicial: 2,
  perguntaVoltagem: 'Voltagem do chuveiro',
  voltagens: ['220 V', '127 V', 'Não sei'],
  voltagemInicial: '220 V',
  descricaoInicial: 'Duas tomadas da cozinha esquentam e o chuveiro desarma o disjuntor. '
      'Apartamento no 8º andar, com elevador.',
  fotos: ['[Foto 1]', '[Foto 2]'],
  prazos: ['Até sexta, 30/10'],
  faixas: [FaixaPreco(minimoCentavos: 20000, maximoCentavos: 50000)],
  endereco: 'Casa · Savassi, Belo Horizonte',
  avisoEndereco: 'O endereço completo só aparece para o profissional que você contratar.',
  avisoPrazo: 'Você recebe até 5 orçamentos em 48 horas. Avisamos quando o prazo terminar.',
);
