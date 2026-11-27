import '../../dados/repositorios.dart' as dados;
import 'modelos.dart';

/// Traduz o tipo do backend (`orcamento.recebido`, `disputa.aberta`...) para o da tela, que
/// decide a tela de destino. Aceita também os nomes curtos usados na demonstração.
TipoNotificacao tipoDaNotificacao(String? tipo) {
  final t = tipo ?? '';
  if (t.startsWith('disputa')) return TipoNotificacao.disputa;
  if (t.startsWith('garantia') || t == 'retrabalho') return TipoNotificacao.retrabalho;
  if (t.startsWith('orcamento')) return TipoNotificacao.orcamento;
  if (t.startsWith('pagamento')) return TipoNotificacao.pagamento;
  if (t.startsWith('mensagem') || t.startsWith('chat')) return TipoNotificacao.mensagem;
  if (t.startsWith('agenda') ||
      t.startsWith('execucao') ||
      t.startsWith('avaliacao') ||
      t.startsWith('exclusividade') ||
      t == 'pedido' ||
      t.startsWith('pedido.')) {
    return TipoNotificacao.pedido;
  }
  return TipoNotificacao.sistema;
}

/// Liga a tela de notificações ao repositório de dados (modo demo ou API).
/// Listar e marcar como lida (`POST /v1/notificacoes/{id}/lida`).
class ServicoNotificacoesRepositorio implements ServicoNotificacoes {
  ServicoNotificacoesRepositorio(this._repositorio);

  final dados.RepositorioNotificacoes _repositorio;

  /// Ids ainda não lidos da última lista: "marcar todas" grava um a um.
  List<String> _pendentes = const [];

  @override
  Future<List<Notificacao>> listar() async {
    final itens = await _repositorio.listar();
    _pendentes = [for (final n in itens) if (!n.lida) n.id];
    return [
      for (final n in itens)
        Notificacao(
          id: n.id,
          tipo: tipoDaNotificacao(n.tipo),
          destinoId: n.destinoId,
          tela: n.tela,
          papel: n.papel,
          recorrenciaId: n.recorrenciaId,
          chamadoId: n.chamadoId,
          compensacaoId: n.compensacaoId,
          tipoApi: n.tipo,
          titulo: n.titulo,
          texto: n.texto,
          quando: n.quando,
          lida: n.lida,
        ),
    ];
  }

  /// A tela já mostra como lida na hora; se a gravação falhar, a notificação volta como não
  /// lida na próxima atualização (nada é perdido).
  @override
  Future<void> marcarLida(String id) async {
    _pendentes = [for (final p in _pendentes) if (p != id) p];
    try {
      await _repositorio.marcarLida(id);
    } on Object {
      // sem rede: tenta de novo da próxima vez que a pessoa abrir
    }
  }

  @override
  Future<void> marcarTodasLidas() async {
    final ids = _pendentes;
    _pendentes = const [];
    for (final id in ids) {
      try {
        await _repositorio.marcarLida(id);
      } on Object {
        // segue com as outras
      }
    }
  }
}
