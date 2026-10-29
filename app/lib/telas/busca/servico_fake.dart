import 'dart:async';

import '../cliente/dados_exemplo.dart';
import '../cliente/modelos.dart';
import 'modelos.dart';

class ServicoBuscaFake implements ServicoBusca {
  const ServicoBuscaFake({this.falhar = false, this.travar = false});

  final bool falhar;
  final bool travar;

  /// Filtro simples só para os testes e o modo sem backend.
  @override
  Future<List<Profissional>> buscar(String termo) {
    if (travar) return Completer<List<Profissional>>().future;
    if (falhar) return Future.error(StateError('falha simulada'));
    final t = termo.toLowerCase();
    return Future.value([
      for (final p in profissionais)
        if (p.nome.toLowerCase().contains(t) || p.especialidade.toLowerCase().contains(t)) p,
    ]);
  }
}
