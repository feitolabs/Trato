import 'package:flutter/widgets.dart';

import '../dados/api_admin.dart';
import '../dados/modelos.dart';
import 'papeis.dart';

/// Estado do login. Guarda só quem entrou; a senha nunca fica aqui.
class Sessao extends ChangeNotifier {
  UsuarioEquipe? _usuario;

  UsuarioEquipe? get usuario => _usuario;
  bool get logado => _usuario != null;

  void entrou(UsuarioEquipe usuario) {
    _usuario = usuario;
    notifyListeners();
  }

  void saiu() {
    _usuario = null;
    notifyListeners();
  }
}

/// Entrega a API e a sessão para as telas.
class EscopoAdmin extends InheritedNotifier<Sessao> {
  const EscopoAdmin({super.key, required this.api, required Sessao sessao, required super.child})
      : super(notifier: sessao);

  final ApiAdmin api;

  static EscopoAdmin of(BuildContext context) {
    final escopo = context.dependOnInheritedWidgetOfExactType<EscopoAdmin>();
    assert(escopo != null, 'EscopoAdmin não encontrado');
    return escopo!;
  }
}

extension EscopoContexto on BuildContext {
  ApiAdmin get api => EscopoAdmin.of(this).api;
  Sessao get sessao => EscopoAdmin.of(this).notifier!;
  UsuarioEquipe? get eu => sessao.usuario;

  /// O papel logado tem a permissão? Esconde menu e botão; o backend confere de novo.
  bool pode(Permissao permissao) => eu?.papel.pode(permissao) ?? false;
}
