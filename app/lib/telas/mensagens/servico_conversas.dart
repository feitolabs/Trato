import '../../dados/cliente_api.dart';
import '../../dados/repositorios_api.dart' show RepositorioChatApi;
import '../comuns/formato_aparelho.dart';
import '../pedidos/modelos.dart' show ContrapropostaChat;
import 'modelos.dart';

/// Lista de conversas real (modo `api`): `GET /v1/conversas`. Traz TODAS as conversas da pessoa,
/// em qualquer estado do pedido (antes e depois de contratar), com a última mensagem e as não
/// lidas já calculadas pelo backend.
class ServicoConversasApi implements ServicoMensagens {
  ServicoConversasApi(this._api, {required this.comoProfissional});

  final ClienteApi _api;

  /// Quem vê é o profissional (o outro lado é o cliente).
  final bool comoProfissional;

  @override
  Future<List<ConversaResumo>> listar() async {
    final bruto = await _api.get('/v1/conversas');
    final itens = bruto is List ? bruto : const [];
    final rotuloPadrao = comoProfissional ? 'Cliente' : 'Profissional';
    final resumos = <ConversaResumo>[];
    for (final item in itens) {
      if (item is! Map) continue;
      final j = Map<String, dynamic>.from(item);
      final pedidoId = j['pedido_id'] as String?;
      if (pedidoId == null) continue;
      final nome = ((j['outra_parte_nome'] as String?) ?? '').trim();
      final titulo = ((j['titulo_pedido'] as String?) ?? '').trim();
      final outraId = j['outra_parte_id'] as String?;
      final quando = j['ultima_em'] as String?;
      resumos.add(
        ConversaResumo(
          pedidoId: pedidoId,
          tituloPedido: titulo.isEmpty ? 'Pedido ${_numero(pedidoId)}' : titulo,
          interlocutor: nome.isEmpty ? rotuloPadrao : nome,
          iniciais: _iniciais(nome.isEmpty ? rotuloPadrao : nome),
          ultimaMensagem: _previa(j['ultima_mensagem'] as String?, j['ultima_minha'] == true),
          quando: quando == null ? '' : _rotuloData(DateTime.parse(quando)),
          naoLidas: (j['nao_lidas'] as num?)?.toInt() ?? 0,
          outraParteId: outraId,
          profissionalId: comoProfissional ? null : outraId,
        ),
      );
    }
    return resumos;
  }

  static String _numero(String id) {
    final limpo = id.replaceAll('-', '');
    return '#${(limpo.length > 4 ? limpo.substring(0, 4) : limpo).toUpperCase()}';
  }

  static String _iniciais(String nome) {
    final partes = nome.split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (partes.isEmpty) return '#';
    final primeira = partes.first[0].toUpperCase();
    return partes.length == 1 ? primeira : '$primeira${partes.last[0].toUpperCase()}';
  }

  static String _previa(String? bruto, bool minha) {
    if (bruto == null || bruto.trim().isEmpty) return 'Toque para abrir a conversa';
    final (contra, texto) = ContrapropostaChat.ler(bruto);
    final corpo = contra != null
        ? 'Contraproposta'
        : RepositorioChatApi.ehMensagemFoto(bruto)
            ? '📷 Foto'
            : texto;
    return minha ? 'Você: $corpo' : corpo;
  }

  /// Hoje: a hora. Outro dia: dia e mês.
  static String _rotuloData(DateTime momento) {
    final local = momento.toLocal();
    final agora = DateTime.now();
    final hoje = local.year == agora.year && local.month == agora.month && local.day == agora.day;
    return hoje ? horaDoAparelho(local) : diaMesDoAparelho(local);
  }
}
