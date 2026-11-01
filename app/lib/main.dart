import 'package:flutter/material.dart';

import 'auth/config_auth.dart';
import 'auth/ligacao_sessao.dart';
import 'auth/servico_auth.dart';
import 'auth/servico_auth_supabase.dart';
import 'telas/auth/login_tela.dart';
import 'dados/cliente_api.dart';
import 'dados/config.dart';
import 'dados/repositorios_trato.dart';
import 'dados/sessao.dart';
import 'dados/servico_upload.dart';
import 'dispositivo/dispositivo_real.dart';
import 'dispositivo/servico_camera_real.dart';
import 'dispositivo/servico_localizacao_real.dart';
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

/// 401 da API: o token já foi limpo; encerra o login guardado e troca a pilha para o login
/// (sem permitir voltar com o botão do Android para telas sem sessão).
void abrirLoginPorSessaoExpirada() {
  final nav = navegadorTrato.currentState;
  if (nav == null || _loginDeSessaoAberto) return;
  _loginDeSessaoAberto = true;
  ServicoAuthPadrao.atual.sair().catchError((_) {});
  nav
      .pushAndRemoveUntil(
        MaterialPageRoute<void>(builder: (_) => const LoginTela(sessaoExpirada: true)),
        (rota) => false,
      )
      .whenComplete(() => _loginDeSessaoAberto = false);
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // `--dart-define=TRATO_MODO=demo|api` (padrão demo) e `--dart-define=TRATO_API_URL=...`.
  final config = ConfigTrato.doAmbiente();
  // Sem chaves do Supabase (SUPABASE_URL e SUPABASE_ANON_KEY por --dart-define), o login fica no
  // serviço de teste. Ver docs/login-configuracao.md. O token do login vai para a [sessaoTrato].
  final configAuth = ConfigAuth.doAmbiente();
  if (configAuth.supabaseConfigurado) {
    ServicoAuthPadrao.atual = await ServicoAuthSupabase.inicializar(
      configAuth,
      // O CPF sai do Auth (não vai no token) e é conferido/gravado pela API do Trato.
      api: config.usaApi ? ClienteApi(urlBase: config.apiUrl, sessao: sessaoTrato) : null,
    );
  }
  LigacaoSessao(
    ServicoAuthPadrao.atual,
    sessaoTrato,
    // Primeiro login: GET /v1/me cria o usuário no backend (idempotente).
    // Só no modo api; em demo não chama nada.
    aoEntrar: () async {
      if (config.usaApi) await RotasTrato.repos.perfil.carregar();
    },
  );
  sessaoTrato.aoExpirar = abrirLoginPorSessaoExpirada;
  RotasTrato.sessao = sessaoTrato;
  RotasTrato.dispositivo = dispositivoReal(navegador: navegadorTrato);
  RotasTrato.repos = RepositoriosTrato.deConfig(
    config,
    sessaoTrato,
    criarUpload: ServicoUploadApi.new,
    camera: ServicoCameraReal(),
    localizacao: const ServicoLocalizacaoReal(),
  );
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
