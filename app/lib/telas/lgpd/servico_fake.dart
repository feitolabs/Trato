import 'dart:async';

import 'modelos.dart';

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

  static const exemplo = [
    Consentimento(
      id: 'dados_pedido',
      titulo: 'Dados para executar pedidos',
      descricao: 'Nome, endereço do serviço e conversa do pedido. Necessário para usar o app.',
      ativo: true,
      obrigatorio: true,
    ),
    Consentimento(
      id: 'localizacao',
      titulo: 'Localização',
      descricao: 'Mostrar profissionais perto de você e confirmar a chegada no local.',
      ativo: true,
    ),
    Consentimento(
      id: 'avisos',
      titulo: 'Avisos e novidades',
      descricao: 'Mensagens sobre novidades do Trato, por push ou WhatsApp.',
      ativo: false,
    ),
  ];

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
  Future<void> solicitarExportacao() async {
    if (falharAcao) throw StateError('falha simulada');
    exportacoes++;
  }

  @override
  Future<void> solicitarExclusao() async {
    if (falharAcao) throw StateError('falha simulada');
    exclusoes++;
  }
}
