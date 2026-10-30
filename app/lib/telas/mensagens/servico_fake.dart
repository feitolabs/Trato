import 'dart:async';

import 'modelos.dart';

class ServicoMensagensFake implements ServicoMensagens {
  const ServicoMensagensFake({this.itens = exemplo, this.falhar = false, this.travar = false});

  final List<ConversaResumo> itens;
  final bool falhar;
  final bool travar;

  static const exemplo = [
    ConversaResumo(
      pedidoId: 'pedido-1',
      tituloPedido: 'Troca de tomadas e chuveiro',
      interlocutor: 'Carlos Menezes',
      iniciais: 'CM',
      ultimaMensagem: 'Posso passar amanhã às 9h?',
      quando: '10h20',
      naoLidas: 2,
    ),
    ConversaResumo(
      pedidoId: 'pedido-2',
      tituloPedido: 'Pintura da sala',
      interlocutor: 'Rafael Souza',
      iniciais: 'RS',
      ultimaMensagem: 'Obrigado! Qualquer coisa me chame.',
      quando: 'ontem',
    ),
  ];

  @override
  Future<List<ConversaResumo>> listar() {
    if (travar) return Completer<List<ConversaResumo>>().future;
    if (falhar) return Future.error(StateError('falha simulada'));
    return Future.value(itens);
  }
}
