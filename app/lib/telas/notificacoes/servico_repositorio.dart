import '../../dados/repositorios.dart' as dados;
import 'modelos.dart';

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
            tipo: TipoNotificacao.sistema,
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
