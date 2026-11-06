import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter/services.dart';

import 'auth/config_auth.dart';
import 'auth/ligacao_sessao.dart';
import 'auth/servico_auth.dart';
import 'auth/servico_auth_supabase.dart';
import 'telas/auth/login_tela.dart';
import 'telas/auth/nova_senha_tela.dart';
import 'dados/cliente_api.dart';
import 'dados/config.dart';
import 'dados/repositorios_trato.dart';
import 'dados/sessao.dart';
import 'dados/servico_upload.dart';
import 'dispositivo/dispositivo_real.dart';
import 'dispositivo/folha_cartao.dart';
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

const _defaultApiUrl = 'https://trato-wald.onrender.com';
const _defaultSupabaseUrl = 'https://ornaoshsvuszquntkqsk.supabase.co';
const _defaultSupabaseAnonKey = 'sb_publishable_GwIISqsEKuOu6iK4IBlRvQ__TVCCgj8';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // O app é só vertical. Android e iOS também travam isso no manifesto e no Info.plist.
  await SystemChrome.setPreferredOrientations(const [DeviceOrientation.portraitUp]);
  var config = ConfigTrato.doAmbiente();
  var configAuth = ConfigAuth.doAmbiente();

  // O app sempre usa a API e o Supabase reais; sem --dart-define cai nos endereços padrão.
  if (!config.usaApi) {
    config = const ConfigTrato(apiUrl: _defaultApiUrl);
  }
  if (!configAuth.supabaseConfigurado) {
    configAuth = ConfigAuth(
      supabaseUrl: configAuth.supabaseUrl.isNotEmpty ? configAuth.supabaseUrl : _defaultSupabaseUrl,
      supabaseAnonKey:
          configAuth.supabaseAnonKey.isNotEmpty ? configAuth.supabaseAnonKey : _defaultSupabaseAnonKey,
      googleWebClientId: configAuth.googleWebClientId,
      googleIosClientId: configAuth.googleIosClientId,
    );
  }
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
  // Link do e-mail de recuperação: o app abre direto na tela de senha nova.
  if (configAuth.supabaseConfigurado) {
    ServicoAuthPadrao.atual.recuperacaoDeSenha.listen((_) => _abrirNovaSenha());
  }
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
  RotasTrato.folhaCartao = FolhaCartaoStripe();
  runApp(const TratoApp());
}

/// Abre a tela de senha nova por cima de tudo. Se o link abriu o app agora (partida a frio), o
/// navegador ainda não existe: tenta de novo no próximo quadro.
void _abrirNovaSenha([int tentativa = 0]) {
  final navegador = navegadorTrato.currentState;
  if (navegador == null) {
    if (tentativa < 50) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _abrirNovaSenha(tentativa + 1));
    }
    return;
  }
  navegador.pushAndRemoveUntil(
    MaterialPageRoute<void>(builder: (_) => const NovaSenhaTela()),
    (_) => false,
  );
}

class TratoApp extends StatelessWidget {
  const TratoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Trato',
      // Português do Brasil também nos componentes do sistema (calendário, relógio, botões).
      locale: const Locale('pt', 'BR'),
      supportedLocales: const [Locale('pt', 'BR')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      navigatorKey: navegadorTrato,
      debugShowCheckedModeBanner: false,
      theme: TemaTrato.claro,
      builder: (context, filho) => EscalaFonteLimitada(child: filho!),
      home: _mostrarGaleria ? const GaleriaComponentes() : const SplashTela(),
    );
  }
}
