import 'package:flutter/material.dart';

import 'modelos.dart';

/// DADOS PROVISÓRIOS, copiados do protótipo (telas 8, 9 e 10).
/// Servem só para as telas existirem antes do backend. Trocar pela API quando ela existir.

const nomeDoCliente = 'Mariana';
const bairroDaBusca = 'Savassi';

const categorias = [
  CategoriaServico('Elétrica', Icons.bolt),
  CategoriaServico('Hidráulica', Icons.water_drop_outlined),
  CategoriaServico('Pintura', Icons.format_paint_outlined),
  CategoriaServico('Montagem', Icons.inventory_2_outlined),
  CategoriaServico('Limpeza', Icons.auto_awesome_outlined),
  CategoriaServico('Ar-cond.', Icons.ac_unit),
  CategoriaServico('Chaveiro', Icons.vpn_key_outlined),
  CategoriaServico('Ver todas', Icons.grid_view),
];

const pedidoEmAndamento = PedidoEmAndamento(
  titulo: 'Troca de tomadas e chuveiro',
  situacao: 'Recebendo orçamentos por mais 31 horas',
  aviso: '3 orçamentos novos',
);

const servicosRecentes = [
  ServicoRecente(
    titulo: 'Pintura da sala',
    profissional: 'Rafael Souza',
    data: '02/10/2026',
    garantia: 'Garantia ativa até 31/12/2026',
  ),
];

const profissionais = [
  Profissional(
    nome: 'Carlos Mendes',
    iniciais: 'CM',
    verificacao: 'Verificado Plus',
    especialidade: 'Elétrica',
    servicosConcluidos: 71,
    nota: 4.9,
    distanciaKm: 2.1,
    respostaCurta: 'resp. em 1 h',
    atendeHoje: true,
    detalhe: DetalhePerfil(
      noTratoDesde: 2025,
      totalAvaliacoes: 64,
      taxaConclusao: 98,
      respondeEm: '~1 hora',
      verificacoes: [
        'Documento e selfie com prova de vida',
        'Certidão de antecedentes',
        'Curso NR-10, válido até 03/2027',
      ],
      avaliacoes: [
        Avaliacao(
          cliente: '[Cliente]',
          servico: 'troca de chuveiro',
          nota: 5.0,
          comentario: '[Comentário real da avaliação aparece aqui.]',
          detalhes: 'Pontualidade 5 · Qualidade 5 · Limpeza 5',
        ),
      ],
    ),
  ),
  Profissional(
    nome: 'André Lopes',
    iniciais: 'AL',
    verificacao: 'Verificado',
    especialidade: 'Elétrica',
    servicosConcluidos: 44,
    nota: 4.8,
    distanciaKm: 3.4,
    respostaCurta: 'resp. em 2 h',
  ),
  Profissional(
    nome: 'Joana Ribeiro',
    iniciais: 'JR',
    verificacao: 'Verificado',
    especialidade: 'Elétrica e hidráulica',
    servicosConcluidos: 25,
    nota: 4.7,
    distanciaKm: 4.0,
  ),
];
