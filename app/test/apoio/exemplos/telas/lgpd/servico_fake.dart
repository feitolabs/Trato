import 'dart:async';

import 'package:trato/telas/lgpd/modelos.dart';

class ServicoPrivacidadeFake implements ServicoPrivacidade {
  ServicoPrivacidadeFake({
    List<Consentimento>? itens,
    this.falhar = false,
    this.falharAcao = false,
    this.travar = false,
  }) : _itens = [...(itens ?? exemplo)];

  final List<Consentimento> _itens;

  /// Falha ao carregar.
  final bool falhar;

  /// Falha ao exportar ou excluir.
  final bool falharAcao;
  final bool travar;

  var exportacoes = 0;
  var exclusoes = 0;
  final alteracoes = <String, bool>{};

  static const exemplo = consentimentosPadrao;

  @override
  Future<List<Consentimento>> consentimentos() {
    if (travar) return Completer<List<Consentimento>>().future;
    if (falhar) return Future.error(StateError('falha simulada'));
    return Future.value([..._itens]);
  }

  @override
  Future<void> alterarConsentimento(String id, {required bool ativo}) async {
    if (falharAcao) throw StateError('falha simulada');
    alteracoes[id] = ativo;
  }

  @override
  Future<String?> solicitarExportacao() async {
    if (falharAcao) throw StateError('falha simulada');
    exportacoes++;
    return '{"usuario":"exemplo"}';
  }

  @override
  Future<void> solicitarExclusao() async {
    if (falharAcao) throw StateError('falha simulada');
    exclusoes++;
  }
}
