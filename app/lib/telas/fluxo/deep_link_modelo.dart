/// Esquema próprio do app. O host `login-callback` é do Supabase (retorno do e-mail de login) e
/// nunca vira rota.
const esquemaDoApp = 'br.com.feitolabs.trato';

/// Telas que um link ou o toque numa notificação pode abrir. Só ABRE: nenhuma ação é executada.
enum DestinoApp {
  pedido,
  orcamentos,
  chat,
  recorrencia,
  disputa,
  retrabalho;

  /// O host do link (`br.com.feitolabs.trato://<host>/<id>`). `avaliacao` abre o mesmo destino
  /// que a notificação de avaliação: o pedido.
  static DestinoApp? doHost(String host) => switch (host) {
        'pedido' => pedido,
        'orcamentos' => orcamentos,
        'chat' => chat,
        'recorrencia' => recorrencia,
        'disputa' => disputa,
        'avaliacao' => pedido,
        _ => null,
      };
}

enum SituacaoLink { ignorado, valido, invalido }

/// O que um endereço recebido significa para o app.
class ResultadoLink {
  const ResultadoLink._(this.situacao, this.destino, this.id);

  /// Outro esquema, `login-callback` ou host desconhecido: o app não faz nada.
  static const ignorado = ResultadoLink._(SituacaoLink.ignorado, null, null);

  const ResultadoLink.valido(DestinoApp destino, String? id)
      : this._(SituacaoLink.valido, destino, id);

  /// Tipo conhecido, mas o id é inválido: mostra "não encontrado".
  const ResultadoLink.invalido(DestinoApp destino) : this._(SituacaoLink.invalido, destino, null);

  final SituacaoLink situacao;
  final DestinoApp? destino;
  final String? id;

  @override
  bool operator ==(Object other) =>
      other is ResultadoLink &&
      other.situacao == situacao &&
      other.destino == destino &&
      other.id == id;

  @override
  int get hashCode => Object.hash(situacao, destino, id);
}

final _formatoId = RegExp(r'^[A-Za-z0-9_-]{1,64}$');

/// Aceita o uuid do backend (e ids curtos de letras, números, "-" e "_"). Nada de "/", ".",
/// espaço ou texto longo: o id vai para a API e para a tela.
bool idDeLinkValido(String? id) => id != null && _formatoId.hasMatch(id);

/// Lê `br.com.feitolabs.trato://<tipo>/<id>`. Sem dado pessoal nem token: só o tipo e o id.
ResultadoLink interpretarLink(Uri uri) {
  if (uri.scheme.toLowerCase() != esquemaDoApp) return ResultadoLink.ignorado;
  final destino = DestinoApp.doHost(uri.host.toLowerCase());
  if (destino == null) return ResultadoLink.ignorado; // inclui login-callback
  final segmentos = uri.pathSegments.where((s) => s.isNotEmpty).toList();
  // A lista de recorrências abre sem id; todos os outros tipos pedem um id.
  if (segmentos.isEmpty && destino == DestinoApp.recorrencia) {
    return const ResultadoLink.valido(DestinoApp.recorrencia, null);
  }
  if (segmentos.length != 1 || !idDeLinkValido(segmentos.first)) {
    return ResultadoLink.invalido(destino);
  }
  return ResultadoLink.valido(destino, segmentos.first);
}

/// O destino de um link que chegou antes de dar para abrir (app frio ou sem login). Só em
/// memória: some ao abrir, ao sair da conta e ao fechar o app.
abstract final class LinkPendente {
  static ResultadoLink? _atual;

  static ResultadoLink? get atual => _atual;
  static void guardar(ResultadoLink r) => _atual = r;
  static void limpar() => _atual = null;

  /// Pega e esvazia.
  static ResultadoLink? retirar() {
    final r = _atual;
    _atual = null;
    return r;
  }
}
