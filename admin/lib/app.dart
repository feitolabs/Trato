import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'dados/api_admin.dart';
import 'nucleo/escopo.dart';
import 'telas/login_tela.dart';
import 'telas/shell.dart';
import 'tema/tema.dart';

class PainelApp extends StatefulWidget {
  const PainelApp({super.key, required this.api, this.ambienteTeste = false});

  final ApiAdmin api;

  /// Mostra a faixa fixa que identifica o ambiente de teste (RNF-07).
  final bool ambienteTeste;

  @override
  State<PainelApp> createState() => _PainelAppState();
}

class _PainelAppState extends State<PainelApp> {
  final _sessao = Sessao();

  @override
  void dispose() {
    _sessao.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return EscopoAdmin(
      api: widget.api,
      sessao: _sessao,
      child: MaterialApp(
        title: 'Trato — Painel',
        debugShowCheckedModeBanner: false,
        theme: TemaTrato.claro,
        locale: const Locale('pt', 'BR'),
        supportedLocales: const [Locale('pt', 'BR')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        builder: (context, child) => EscalaFonteLimitada(child: child!),
        home: ListenableBuilder(
          listenable: _sessao,
          builder: (context, _) =>
              _sessao.logado ? ShellPainel(ambienteTeste: widget.ambienteTeste) : const LoginTela(),
        ),
      ),
    );
  }
}
