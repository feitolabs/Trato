import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'dados/api_admin.dart';
import 'nucleo/escopo.dart';
import 'nucleo/recuperacao_senha.dart';
import 'telas/nova_senha_tela.dart';
import 'telas/login_tela.dart';
import 'telas/shell.dart';
import 'tema/tema.dart';

class PainelApp extends StatefulWidget {
  const PainelApp({super.key, required this.api, this.ambienteTeste = false, this.linkRecuperacao});

  /// Link de redefinição de senha com que o painel foi aberto (já lido da URL; o token fica só em memória).
  final LinkRecuperacao? linkRecuperacao;

  final ApiAdmin api;

  /// Mostra a faixa fixa que identifica o ambiente de teste (RNF-07).
  final bool ambienteTeste;

  @override
  State<PainelApp> createState() => _PainelAppState();
}

class _PainelAppState extends State<PainelApp> {
  final _sessao = Sessao();
  late LinkRecuperacao? _link = widget.linkRecuperacao;
  String? _avisoLogin;

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
          builder: (context, _) {
            final link = _link;
            if (link != null) {
              return NovaSenhaTela(
                link: link,
                aoConcluir: ({required bool definida}) => setState(() {
                  _link = null;
                  _avisoLogin = definida ? 'Senha definida. Entre com a nova senha.' : null;
                }),
              );
            }
            return _sessao.logado
                ? ShellPainel(ambienteTeste: widget.ambienteTeste)
                : LoginTela(aviso: _avisoLogin);
          },
        ),
      ),
    );
  }
}
