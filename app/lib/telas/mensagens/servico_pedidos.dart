import '../../dados/repositorios.dart';
import '../pedidos/modelos.dart';
import 'modelos.dart';

/// Lista de conversas montada a partir dos pedidos (modo `api`). Quando [chat] é informado,
/// busca a última mensagem real e quantidade de não lidas de cada pedido.
class ServicoMensagensDosPedidos implements ServicoMensagens {
  const ServicoMensagensDosPedidos(this._pedidos, {this.chat});

  final RepositorioPedidos _pedidos;
  final RepositorioChat? chat;

  static const _comConversa = {
    'orcamento_aceito',
    'pago_e_retido',
    'agendado',
    'em_andamento',
    'em_confirmacao',
    'concluido',
    'em_disputa',
    'retrabalho',
  };

  @override
  Future<List<ConversaResumo>> listar() async {
    final todos = await _pedidos.listar();
    final pedidosComChat = [
      for (final p in [...todos.emAndamento, ...todos.finalizados])
        if (p.id != null && _comConversa.contains(p.estadoApi)) p,
    ];
    final resumos = <ConversaResumo>[];
    for (final p in pedidosComChat) {
      var ultima = 'Toque para abrir a conversa';
      var quando = '';
      var naoLidas = 0;
      if (chat != null) {
        try {
          final conv = await chat!.conversa(p.id!);
          if (conv.mensagens.isNotEmpty) {
            final msg = conv.mensagens.last;
            ultima = msg.tipo == TipoMensagem.foto ? '📷 Foto' : (msg.texto ?? ultima);
            quando = msg.hora;
            naoLidas = conv.mensagens.where((m) => !m.minha && !m.lida).length;
          }
        } on Object {
          // Segue com resumo padrão do pedido.
        }
      }
      resumos.add(
        ConversaResumo(
          pedidoId: p.id!,
          tituloPedido: p.titulo,
          interlocutor: 'Profissional',
          iniciais: 'PR',
          ultimaMensagem: ultima,
          quando: quando,
          naoLidas: naoLidas,
        ),
      );
    }
    return resumos;
  }
}

/// Conversas do profissional (modo `api`): inclui o atendimento agendado/em andamento e os
/// pedidos abertos disponíveis para conversa.
class ServicoMensagensDoProfissional implements ServicoMensagens {
  const ServicoMensagensDoProfissional(this._profissional, {this.chat});

  final RepositorioProfissional _profissional;
  final RepositorioChat? chat;

  @override
  Future<List<ConversaResumo>> listar() async {
    final inicio = await _profissional.inicio();
    final resumos = <ConversaResumo>[];
    final proximo = inicio.proximo;
    final idProximo = proximo?.pedidoId;
    if (proximo != null && idProximo != null) {
      var ultima = 'Toque para abrir a conversa';
      var quando = proximo.quando;
      var naoLidas = 0;
      if (chat != null) {
        try {
          final conv = await chat!.conversa(idProximo);
          if (conv.mensagens.isNotEmpty) {
            final msg = conv.mensagens.last;
            ultima = msg.tipo == TipoMensagem.foto ? '📷 Foto' : (msg.texto ?? ultima);
            quando = msg.hora;
            naoLidas = conv.mensagens.where((m) => !m.minha && !m.lida).length;
          }
        } on Object {
          // Segue com o resumo padrão.
        }
      }
      resumos.add(
        ConversaResumo(
          pedidoId: idProximo,
          tituloPedido: proximo.titulo,
          interlocutor: 'Cliente',
          iniciais: 'CL',
          ultimaMensagem: ultima,
          quando: quando,
          naoLidas: naoLidas,
        ),
      );
    }
    for (final p in inicio.pedidos) {
      if (p.id == idProximo) continue;
      resumos.add(
        ConversaResumo(
          pedidoId: p.id,
          tituloPedido: p.titulo,
          interlocutor: p.bairro.isNotEmpty ? 'Cliente · ${p.bairro}' : 'Cliente',
          iniciais: 'CL',
          ultimaMensagem: 'Tire dúvidas antes de enviar orçamento',
          quando: p.prazo,
        ),
      );
    }
    return resumos;
  }
}
