import '../../componentes/componentes.dart';
import 'modelos.dart';

/// DADOS PROVISÓRIOS: textos do protótipo (telas 15, 16 e 17) para as telas rodarem
/// sem backend. Serão trocados pelos dados reais da API.
abstract final class DadosExemplo {
  static const pedidosEmAndamento = [
    PedidoResumo(
      titulo: 'Troca de tomadas e chuveiro',
      subtitulo: 'Carlos Mendes · hoje, 14h',
      statusTexto: 'Em execução · pagamento retido',
      statusTipo: TipoStatus.info,
    ),
    PedidoResumo(
      titulo: 'Instalar ventilador de teto',
      subtitulo: 'Pedido em 27/10 · fecha em 20 horas',
      statusTexto: '2 orçamentos recebidos',
      statusTipo: TipoStatus.info,
    ),
    PedidoResumo(
      titulo: 'Vazamento na pia',
      subtitulo: 'Joana Ribeiro · 22/10',
      statusTexto: 'Disputa aberta · valor congelado',
      statusTipo: TipoStatus.alerta,
    ),
  ];

  /// O protótipo não mostra a aba Finalizados preenchida; este item é inventado
  /// só para exercitar a aba (chip "Finalizado" vem do design-tokens).
  static const pedidosFinalizados = [
    PedidoResumo(
      titulo: 'Pintura da sala (exemplo)',
      subtitulo: 'Exemplo · 10/10',
      statusTexto: 'Finalizado',
      statusTipo: TipoStatus.sucesso,
    ),
  ];

  static const aditivo = Aditivo(
    titulo: 'Trocar disjuntor do chuveiro',
    valorCentavos: 4500,
    descricao: 'O disjuntor atual está derretido e não aguenta 220 V.',
  );

  static const pedidoEmExecucao = PedidoEmExecucao(
    numero: '#4821',
    titulo: 'Serviço em execução',
    aditivo: aditivo,
    fotos: ['[Check-in · 14h06]', '[Antes]'],
    etapas: [
      EtapaLinhaDoTempo(
        titulo: 'Contratado',
        detalhe: 'Ter, 27/10 · contrato digital gerado',
        estado: EstadoEtapa.feita,
      ),
      EtapaLinhaDoTempo(
        titulo: 'A caminho',
        detalhe: 'Qui, 29/10 · 13h40',
        estado: EstadoEtapa.feita,
      ),
      EtapaLinhaDoTempo(
        titulo: 'Chegou',
        detalhe: '14h06 · foto e local registrados',
        estado: EstadoEtapa.feita,
      ),
      EtapaLinhaDoTempo(
        titulo: 'Em execução',
        detalhe: 'Iniciado com o seu código às 14h10',
        estado: EstadoEtapa.atual,
      ),
      EtapaLinhaDoTempo(
        titulo: 'Finalizado',
        detalhe: 'Você confirma com o código de conclusão',
        estado: EstadoEtapa.futura,
      ),
    ],
  );

  static const conversa = ConversaPedido(
    nome: 'Carlos Mendes',
    iniciais: 'CM',
    numeroPedido: '#4821',
    situacao: 'em execução',
    respostasRapidas: [
      'Tudo certo',
      'Pode me mandar foto?',
      'Que horas termina?'
    ],
    mensagens: [
      MensagemChat(
        tipo: TipoMensagem.sistema,
        texto: 'Serviço iniciado com o seu código às 14h10.',
        hora: '14h10',
      ),
      MensagemChat(
        tipo: TipoMensagem.texto,
        texto: 'Boa tarde! Já estou trocando as tomadas da cozinha.',
        hora: '14h25',
      ),
      MensagemChat(tipo: TipoMensagem.foto, texto: '[Foto]', hora: '14h25'),
      MensagemChat(
        tipo: TipoMensagem.texto,
        texto:
            'O disjuntor do chuveiro está derretido. Enviei um aditivo de R\$ 45,00 '
            'para você aprovar.',
        hora: '15h02',
      ),
      MensagemChat(
        tipo: TipoMensagem.texto,
        texto: 'Vi aqui, vou olhar agora.',
        hora: '15h04',
        minha: true,
        lida: true,
      ),
    ],
  );
}
