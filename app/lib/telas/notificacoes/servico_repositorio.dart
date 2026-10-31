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
      t == 'pedido') {
    return TipoNotificacao.pedido;
  }
  return TipoNotificacao.sistema;
}

/// Liga a tela de notificações ao repositório de dados (modo demo ou API).
/// O repositório só lista; marcar como lida ainda não existe na API, então é local.
class ServicoNotificacoesRepositorio implements ServicoNotificacoes {
  ServicoNotificacoesRepositorio(this._repositorio);

  final dados.RepositorioNotificacoes _repositorio;

  @override
  Future<List<Notificacao>> listar() async => [
        for (final n in await _repositorio.listar())
          Notificacao(
            id: n.id,
            tipo: tipoDaNotificacao(n.tipo),
            destinoId: n.destinoId,
            titulo: n.titulo,
            texto: n.texto,
            quando: n.quando,
            lida: n.lida,
          ),
      ];

  @override
  Future<void> marcarLida(String id) async {}

  @override
  Future<void> marcarTodasLidas() async {}
}
