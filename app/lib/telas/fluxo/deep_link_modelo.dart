/// Esquema próprio do app. O host `login-callback` é do Supabase (retorno do e-mail de login) e
/// nunca vira rota.
const esquemaDoApp = 'br.com.feitolabs.trato';

/// Telas que um link ou o toque numa notificação pode abrir. Só ABRE: nenhuma ação é executada.
enum DestinoApp {
  pedido,

  /// Pedido ainda aberto (novo, direcionado, urgente): para o profissional é a tela de detalhe
  /// para orçar; para o cliente, o pedido.
  pedidoAberto,
  orcamentos,
  chat,
  recorrencia,
  disputa,
  retrabalho,

  /// Avaliação: abre o pedido; para o profissional de um serviço concluído, a tela de avaliar
  /// o cliente.
  avaliacao,
  indicacoes,

  /// "Falar com o Trato" (avisos do atendimento).
  suporte,

  /// Medidas da conta (avisos `conta.medida_*`).
  medidas,

  /// Central de privacidade (aviso de marketing, tela `privacidade`): é onde se revoga.
  privacidade,

  /// Selo do profissional (avisos `conta.selo_*`, tela `perfil`).
  selo,

  /// Compensações do profissional (avisos com `compensacao_id`).
  compensacoes,

  /// Contestação da decisão da disputa (avisos `disputa.contestada` e
  /// `disputa.contestacao_decidida`).
  contestacaoDecisao,

  /// Saldo de Tratinhos da carteira do aviso (`pagamento.tratinhos_vencendo`).
  tratinhos,

  /// Pedir revisão de uma avaliação ocultada; o id é o da avaliação.
  contestarOcultacao;

  /// O host do link (`br.com.feitolabs.trato://<host>/<id>`).
  static DestinoApp? doHost(String host) => switch (host) {
        'pedido' => pedido,
        'orcamentos' => orcamentos,
        'chat' => chat,
        'recorrencia' => recorrencia,
        'disputa' => disputa,
        'avaliacao' => avaliacao,
        _ => null,
      };
}

enum SituacaoLink { ignorado, valido, invalido }

/// O que um endereço recebido significa para o app.
class ResultadoLink {
  const ResultadoLink._(this.situacao, this.destino, this.id, this.papel);

  /// Outro esquema, `login-callback` ou host desconhecido: o app não faz nada.
  static const ignorado = ResultadoLink._(SituacaoLink.ignorado, null, null, null);

  const ResultadoLink.valido(DestinoApp destino, String? id, {String? papel})
      : this._(SituacaoLink.valido, destino, id, papel);

  /// Tipo conhecido, mas o id é inválido: mostra "não encontrado".
  const ResultadoLink.invalido(DestinoApp destino, {String? papel})
      : this._(SituacaoLink.invalido, destino, null, papel);

  final SituacaoLink situacao;
  final DestinoApp? destino;
  final String? id;

  /// `profissional` ou `cliente`, quando o push diz em que modo a tela deve abrir. Nulo = o
  /// modo em que o app está agora.
  final String? papel;

  @override
  bool operator ==(Object other) =>
      other is ResultadoLink &&
      other.situacao == situacao &&
      other.destino == destino &&
      other.id == id &&
      other.papel == papel;

  @override
  int get hashCode => Object.hash(situacao, destino, id, papel);
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

/// Lê o `data` de um push do backend (`evento`, `tela`, `pedido_id`, `recorrencia_id`, `link`...).
/// A tabela tela -> destino é a mesma da caixa de notificações: `orcamentos`; `pedido`;
/// `pedido_aberto` (pedido aberto, para o profissional orçar); `avaliacao`; `disputa`; `mensagens`
/// (o chat); `recorrencias`; `indique-e-ganhe`. A chave `papel` (`profissional` ou `cliente`)
/// diz em que modo abrir.
/// Qualquer outra tela, tela ausente ou valor que não seja texto: ignorado. A chave `link`
/// (esquema antigo) e todas as outras são descartadas: o app nunca abre URL vinda do push.
ResultadoLink resultadoDoPush(Map<String, dynamic> dados) {
  String? texto(String chave) {
    final v = dados[chave];
    if (v is! String) return null;
    final t = v.trim();
    return t.isEmpty ? null : t;
  }

  // Tratinhos perto de vencer: `tela: notificacoes`, mas o ponto certo é o saldo da carteira.
  if (texto('evento') == 'pagamento.tratinhos_vencendo') {
    final carteira = texto('carteira') ?? texto('papel');
    return ResultadoLink.valido(
      DestinoApp.tratinhos,
      null,
      papel: carteira == 'profissional' || carteira == 'cliente' ? carteira : null,
    );
  }
  // Avaliação ocultada (11.8): com o id da avaliação, abre o pedido de revisão; sem ele, segue
  // a tela do aviso (o pedido).
  final avaliacao = texto('avaliacao_id');
  if (texto('evento') == 'conta.avaliacao_ocultada' && idDeLinkValido(avaliacao)) {
    return ResultadoLink.valido(DestinoApp.contestarOcultacao, avaliacao,
        papel: switch (texto('papel')) {
          'profissional' => 'profissional',
          'cliente' => 'cliente',
          _ => null,
        });
  }
  // Termos 10.3: `tela: perfil` nos avisos do selo, que é só do profissional.
  if (texto('tela') == 'perfil' && (texto('evento') ?? '').startsWith('conta.selo_')) {
    return const ResultadoLink.valido(DestinoApp.selo, null, papel: 'profissional');
  }
  // Termos 5.7: check-out sem Código Final é sempre do cliente e abre o pedido, mesmo
  // quando vem só `pedido_id` (sem `tela` ou `papel`).
  if (texto('evento') == 'pagamento.checkout_sem_codigo') {
    final pedido = texto('pedido_id');
    if (pedido == null) return ResultadoLink.ignorado;
    return idDeLinkValido(pedido)
        ? ResultadoLink.valido(DestinoApp.pedido, pedido, papel: 'cliente')
        : const ResultadoLink.invalido(DestinoApp.pedido, papel: 'cliente');
  }
  final destino = switch (texto('tela')) {
    'orcamentos' => DestinoApp.orcamentos,
    'pedido' => DestinoApp.pedido,
    'pedido_aberto' => DestinoApp.pedidoAberto,
    'avaliacao' => DestinoApp.avaliacao,
    'disputa' => DestinoApp.disputa,
    'mensagens' => DestinoApp.chat,
    'recorrencias' => DestinoApp.recorrencia,
    'indique-e-ganhe' => DestinoApp.indicacoes,
    'suporte' => DestinoApp.suporte,
    'medidas' => DestinoApp.medidas,
    'privacidade' => DestinoApp.privacidade,
    _ => null,
  };
  if (destino == null) return ResultadoLink.ignorado;
  // Só estes dois valores contam; qualquer outro (ou ausente) = manter o modo atual.
  final papel = switch (texto('papel')) {
    'profissional' => 'profissional',
    'cliente' => 'cliente',
    _ => null,
  };
  // Aviso de compensação: o backend manda `tela: pedido` com o `compensacao_id`. A tela é só
  // do profissional; sem um id que sirva, abre a lista.
  final compensacao = texto('compensacao_id');
  if (destino == DestinoApp.pedido && compensacao != null) {
    return ResultadoLink.valido(
      DestinoApp.compensacoes,
      idDeLinkValido(compensacao) ? compensacao : null,
      papel: 'profissional',
    );
  }
  // Avisos da contestação da decisão: `tela: pedido`, mas o ponto certo é a contestação.
  final contestacao =
      const {'disputa.contestada', 'disputa.contestacao_decidida'}.contains(texto('evento'));
  if (destino == DestinoApp.pedido && contestacao) {
    final pedido = texto('pedido_id');
    if (pedido == null) return ResultadoLink.ignorado;
    return idDeLinkValido(pedido)
        ? ResultadoLink.valido(DestinoApp.contestacaoDecisao, pedido, papel: papel)
        : ResultadoLink.invalido(DestinoApp.contestacaoDecisao, papel: papel);
  }
  // Atendimento: o chamado do aviso (`chamado_id`); sem um id que sirva, a lista.
  if (destino == DestinoApp.suporte) {
    final chamado = texto('chamado_id');
    return ResultadoLink.valido(destino, idDeLinkValido(chamado) ? chamado : null, papel: papel);
  }
  // Telas sem id.
  if (destino == DestinoApp.indicacoes ||
      destino == DestinoApp.medidas ||
      destino == DestinoApp.privacidade) {
    return ResultadoLink.valido(destino, null, papel: papel);
  }
  // Recorrência: o id da série vem em `recorrencia_id`; sem ele, abre a lista.
  final bruto = destino == DestinoApp.recorrencia ? texto('recorrencia_id') : texto('pedido_id');
  if (bruto == null) {
    return destino == DestinoApp.recorrencia
        ? ResultadoLink.valido(DestinoApp.recorrencia, null, papel: papel)
        : ResultadoLink.ignorado; // sem id não há o que abrir
  }
  return idDeLinkValido(bruto)
      ? ResultadoLink.valido(destino, bruto, papel: papel)
      : ResultadoLink.invalido(destino, papel: papel);
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
