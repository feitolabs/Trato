/// Dados de exemplo das telas 23 e 24 do protótipo.
/// PROVISÓRIO: copiados do protótipo, saem quando o backend ligar.
library;

import 'modelos.dart';

const pedidoTomadasExemplo = PedidoAberto(
  id: 'ped-tomadas',
  titulo: 'Troca de tomadas e chuveiro',
  bairro: 'Savassi',
  distanciaKm: 2.1,
  prazo: 'até sexta, 30/10',
  orcaram: 3,
  limiteOrcamentos: 5,
  faixaMinCentavos: 20000,
  faixaMaxCentavos: 50000,
);

const inicioProfissionalExemplo = InicioProfissional(
  nome: 'Carlos',
  disponivelAgora: true,
  proximo: ProximoAtendimento(
    quando: 'Hoje · 14h',
    titulo: 'Troca de tomadas e chuveiro',
    endereco: 'Rua Antônio de Albuquerque, Savassi',
  ),
  carteira: ResumoCarteira(retidoCentavos: 42500, paraSacarCentavos: 71250),
  pedidos: [
    pedidoTomadasExemplo,
    PedidoAberto(
      id: 'ped-disjuntor',
      titulo: 'Disjuntor desarmando',
      bairro: 'Funcionários',
      distanciaKm: 1.4,
      prazo: 'hoje',
      orcaram: 1,
      limiteOrcamentos: 5,
      urgente: true,
    ),
    PedidoAberto(
      id: 'ped-luminarias',
      titulo: 'Instalar 4 luminárias',
      bairro: 'Lourdes',
      distanciaKm: 3.8,
      prazo: 'próxima semana',
      orcaram: 0,
      limiteOrcamentos: 5,
      faixaMinCentavos: 15000,
      faixaMaxCentavos: 30000,
    ),
  ],
);

const detalhePedidoExemplo = DetalhePedido(
  pedido: pedidoTomadasExemplo,
  fechaEm: 'Fecha em 31 horas',
  clienteResumo: 'Mariana · nota 4,8 como cliente · 6 serviços',
  legendasFotos: ['[Foto 1]', '[Foto 2]'],
  descricao: 'Duas tomadas da cozinha esquentam e o chuveiro desarma o disjuntor. '
      'Apartamento no 8º andar, com elevador.',
  linhas: [
    LinhaDetalhe('Serviços', 'Trocar tomada, trocar chuveiro'),
    LinhaDetalhe('Tomadas', '2'),
    LinhaDetalhe('Chuveiro', '220 V'),
  ],
);
