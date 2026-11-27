import 'package:flutter/material.dart';

import '../nucleo/escopo.dart';

/// Para modais que mostram dado pessoal: se a sessão cair (sair ou inatividade), o conteúdo é
/// apagado e o modal sai da tela, em vez de ficar por cima do login.
mixin SomeComASessao<T extends StatefulWidget> on State<T> {
  bool _removendo = false;

  /// Apaga o que foi carregado.
  void limparSigiloso();

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (context.sessao.logado || _removendo) return;
    _removendo = true;
    limparSigiloso();
    final rota = ModalRoute.of(context);
    final navegador = Navigator.of(context);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (rota != null && rota.isActive) navegador.removeRoute(rota);
    });
  }
}
