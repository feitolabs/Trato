import 'package:flutter/material.dart';

import 'dados/api_admin.dart';
import 'nucleo/escopo.dart';
import 'telas/login_tela.dart';
import 'telas/shell.dart';
import 'tema/tema.dart';

class PainelApp extends StatefulWidget {
  const PainelApp({super.key, required this.api});

  final ApiAdmin api;

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
        builder: (context, child) => EscalaFonteLimitada(child: child!),
        home: ListenableBuilder(
          listenable: _sessao,
          builder: (context, _) => _sessao.logado ? const ShellPainel() : const LoginTela(),
        ),
      ),
    );
  }
}
