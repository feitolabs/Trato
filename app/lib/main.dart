import 'package:flutter/material.dart';

import 'auth/config_auth.dart';
import 'auth/ligacao_sessao.dart';
import 'auth/servico_auth.dart';
import 'auth/servico_auth_supabase.dart';
import 'telas/auth/login_tela.dart';
import 'dados/config.dart';
import 'dados/repositorios_trato.dart';
import 'dados/sessao.dart';
import 'dispositivo/dispositivo_real.dart';
import 'galeria/galeria_componentes.dart';
import 'telas/fluxo/rotas.dart';
import 'telas/splash_tela.dart';
import 'tema/tema.dart';

/// `--dart-define=GALERIA=true` abre a vitrine de componentes no lugar da splash.
const _mostrarGaleria = bool.fromEnvironment('GALERIA');

/// Sessão do usuário. O serviço de login entrega o token aqui; o cliente HTTP o envia.
final sessaoTrato = SessaoTrato();

/// Navegador raiz: permite abrir o login por cima da tela em uso quando a sessão expira.
final navegadorTrato = GlobalKey<NavigatorState>();
var _loginDeSessaoAberto = false;

/// 401 da API: o token já foi limpo; encerra o login guardado e abre o login por cima da tela
/// atual (push, não troca), então o que a pessoa digitou continua lá embaixo.
void abrirLoginPorSessaoExpirada() {
  final nav = navegadorTrato.currentState;
  if (nav == null || _loginDeSessaoAberto) return;
  _loginDeSessaoAberto = true;
  ServicoAuthPadrao.atual.sair().catchError((_) {});
  nav
      .push(MaterialPageRoute<void>(builder: (_) => const LoginTela(sessaoExpirada: true)))
      .whenComplete(() => _loginDeSessaoAberto = false);
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Sem chaves do Supabase (SUPABASE_URL e SUPABASE_ANON_KEY por --dart-define), o login fica no
  // serviço de teste. Ver docs/login-configuracao.md. O token do login vai para a [sessaoTrato].
  final configAuth = ConfigAuth.doAmbiente();
  if (configAuth.supabaseConfigurado) {
    ServicoAuthPadrao.atual = await ServicoAuthSupabase.inicializar(configAuth);
  }
  // `--dart-define=TRATO_MODO=demo|api` (padrão demo) e `--dart-define=TRATO_API_URL=...`.
  LigacaoSessao(ServicoAuthPadrao.atual, sessaoTrato);
  sessaoTrato.aoExpirar = abrirLoginPorSessaoExpirada;
  RotasTrato.sessao = sessaoTrato;
  RotasTrato.dispositivo = dispositivoReal();
  RotasTrato.repos = RepositoriosTrato.deConfig(ConfigTrato.doAmbiente(), sessaoTrato);
  runApp(const TratoApp());
}

class TratoApp extends StatelessWidget {
  const TratoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Trato',
      navigatorKey: navegadorTrato,
      debugShowCheckedModeBanner: false,
      theme: TemaTrato.claro,
      builder: (context, filho) => EscalaFonteLimitada(child: filho!),
      home: _mostrarGaleria ? const GaleriaComponentes() : const SplashTela(),
    );
  }
}
