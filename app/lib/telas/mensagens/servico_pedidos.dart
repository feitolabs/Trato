import '../../dados/repositorios.dart';
import '../profissional_inicio/modelos.dart';
import 'modelos.dart';

/// Lista de conversas montada a partir dos pedidos (modo `api`): há uma conversa por pedido já
/// contratado. O backend ainda não tem a rota da lista de conversas (`docs/app-divergencias.md`);
/// o texto do último recado e as não lidas ficam de fora até ela existir.
class ServicoMensagensDosPedidos implements ServicoMensagens {
  const ServicoMensagensDosPedidos(this._pedidos);

  final RepositorioPedidos _pedidos;

  static const _comConversa = {
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
    return [
      for (final p in [...todos.emAndamento, ...todos.finalizados])
        if (p.id != null && _comConversa.contains(p.estadoApi))
          ConversaResumo(
            pedidoId: p.id!,
            tituloPedido: p.titulo,
            interlocutor: 'Profissional',
            iniciais: 'PR',
            ultimaMensagem: 'Toque para abrir a conversa',
            quando: '',
          ),
    ];
  }
}

/// Conversas do profissional (modo `api`): só o atendimento de hoje, que vem do início.
class ServicoMensagensDoProfissional implements ServicoMensagens {
  const ServicoMensagensDoProfissional(this._profissional);

  final RepositorioProfissional _profissional;

  @override
  Future<List<ConversaResumo>> listar() async {
    final ProximoAtendimento? proximo = (await _profissional.inicio()).proximo;
    final id = proximo?.pedidoId;
    if (proximo == null || id == null) return const [];
    return [
      ConversaResumo(
        pedidoId: id,
        tituloPedido: proximo.titulo,
        interlocutor: 'Cliente',
        iniciais: 'CL',
        ultimaMensagem: 'Toque para abrir a conversa',
        quando: '',
      ),
    ];
  }
}
