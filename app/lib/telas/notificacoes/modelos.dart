import 'package:flutter/material.dart';

enum TipoNotificacao {
  pedido(Icons.build_outlined, 'Pedido'),
  orcamento(Icons.request_quote_outlined, 'Orçamento'),
  pagamento(Icons.account_balance_wallet_outlined, 'Pagamento'),
  mensagem(Icons.chat_bubble_outline, 'Mensagem'),
  disputa(Icons.gavel_outlined, 'Disputa'),
  retrabalho(Icons.handyman_outlined, 'Retrabalho'),
  sistema(Icons.info_outline, 'Aviso');

  const TipoNotificacao(this.icone, this.rotulo);

  final IconData icone;
  final String rotulo;
}

/// Uma notificação já pronta, como o backend devolve. [destinoId] é o id do pedido,
/// orçamento ou conversa que o toque deve abrir (quem liga as rotas decide a tela).
class Notificacao {
  const Notificacao({
    required this.id,
    required this.tipo,
    required this.titulo,
    required this.texto,
    required this.quando,
    this.lida = false,
    this.destinoId,
  });

  final String id;
  final TipoNotificacao tipo;
  final String titulo;
  final String texto;

  /// Texto pronto, ex.: "há 5 min" (formatado fora da tela).
  final String quando;
  final bool lida;
  final String? destinoId;

  Notificacao comoLida() => Notificacao(
        id: id,
        tipo: tipo,
        titulo: titulo,
        texto: texto,
        quando: quando,
        lida: true,
        destinoId: destinoId,
      );
}

/// Contrato com o backend. A tela só pede e mostra.
abstract interface class ServicoNotificacoes {
  Future<List<Notificacao>> listar();
  Future<void> marcarLida(String id);
  Future<void> marcarTodasLidas();
}
