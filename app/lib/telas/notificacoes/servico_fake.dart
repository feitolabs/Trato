import 'dart:async';

import 'modelos.dart';

/// Serviço de mentira para testes e para rodar o app sem backend.
class ServicoNotificacoesFake implements ServicoNotificacoes {
  ServicoNotificacoesFake({List<Notificacao>? itens, this.falhar = false, this.travar = false})
      : _itens = [...(itens ?? exemplo)];

  final List<Notificacao> _itens;
  final bool falhar;

  /// Nunca responde: mostra o estado "carregando".
  final bool travar;
  final marcadas = <String>[];

  static const exemplo = [
    Notificacao(
      id: 'n1',
      tipo: TipoNotificacao.orcamento,
      titulo: 'Novo orçamento recebido',
      texto: 'Carlos Menezes enviou um orçamento para "Troca de tomadas e chuveiro".',
      quando: 'há 5 min',
      destinoId: 'pedido-1',
    ),
    Notificacao(
      id: 'n2',
      tipo: TipoNotificacao.mensagem,
      titulo: 'Mensagem de Carlos Menezes',
      texto: 'Posso passar amanhã às 9h?',
      quando: 'há 1 h',
      destinoId: 'pedido-1',
    ),
    Notificacao(
      id: 'n3',
      tipo: TipoNotificacao.pagamento,
      titulo: 'Pagamento confirmado pelo provedor',
      texto: 'O pagamento do pedido "Pintura da sala" foi confirmado.',
      quando: 'ontem',
      lida: true,
      destinoId: 'pedido-2',
    ),
    Notificacao(
      id: 'n4',
      tipo: TipoNotificacao.sistema,
      titulo: 'Atualizamos os termos de uso',
      texto: 'Veja o que mudou na Central de privacidade.',
      quando: 'há 3 dias',
      lida: true,
    ),
  ];

  @override
  Future<List<Notificacao>> listar() {
    if (travar) return Completer<List<Notificacao>>().future;
    if (falhar) return Future.error(StateError('falha simulada'));
    return Future.value([..._itens]);
  }

  @override
  Future<void> marcarLida(String id) async {
    marcadas.add(id);
  }

  @override
  Future<void> marcarTodasLidas() async {
    marcadas.add('todas');
  }
}
