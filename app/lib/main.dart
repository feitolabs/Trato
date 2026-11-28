import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter/services.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

import 'auth/config_auth.dart';
import 'auth/ligacao_sessao.dart';
import 'auth/servico_auth.dart';
import 'auth/servico_auth_supabase.dart';
import 'telas/auth/login_tela.dart';
import 'telas/auth/nova_senha_tela.dart';
import 'dados/aparelho_do_acesso.dart';
import 'dados/cliente_api.dart';
import 'componentes/banner_sem_conexao.dart';
import 'dados/cache_leitura.dart';
import 'dados/config.dart';
import 'dados/monitor_conexao.dart';
import 'dados/fila_offline.dart';
import 'dados/fila_offline_arquivo.dart';
import 'dados/repositorios_trato.dart';
import 'dados/sessao.dart';
import 'dados/servico_upload.dart';
import 'dispositivo/dispositivo_real.dart';
import 'dispositivo/folha_cartao.dart';
import 'dispositivo/servico_camera_real.dart';
import 'dados/sessao_expirada.dart';
import 'dispositivo/servico_localizacao_real.dart';
import 'dispositivo/servico_push_firebase.dart';
import 'dispositivo/toque_push.dart';
import 'galeria/galeria_componentes.dart';
import 'telas/comuns/aviso_push.dart';
import 'telas/fluxo/deep_link.dart';
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

const _defaultApiUrl = 'https://trato.fly.dev';
const _defaultSupabaseUrl = 'https://ornaoshsvuszquntkqsk.supabase.co';
const _defaultSupabaseAnonKey = 'sb_publishable_GwIISqsEKuOu6iK4IBlRvQ__TVCCgj8';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // O app é só vertical. Android e iOS também travam isso no manifesto e no Info.plist.
  await SystemChrome.setPreferredOrientations(const [DeviceOrientation.portraitUp]);
  await ControladorTema.instancia.carregar();
  final firebaseOk = await inicializarFirebaseComSeguranca();
  if (firebaseOk) {
    // Push com o app fechado ou em segundo plano: só não quebrar (a bandeja é do sistema).
    FirebaseMessaging.onBackgroundMessage(tratarPushEmSegundoPlano);
  }
  var config = ConfigTrato.doAmbiente();
  var configAuth = ConfigAuth.doAmbiente();

  // O app sempre usa a API e o Supabase reais; sem --dart-define cai nos endereços padrão.
  if (!config.usaApi) {
    config = const ConfigTrato(apiUrl: _defaultApiUrl);
  }
  if (!configAuth.supabaseConfigurado) {
    configAuth = ConfigAuth(
      supabaseUrl: configAuth.supabaseUrl.isNotEmpty ? configAuth.supabaseUrl : _defaultSupabaseUrl,
      supabaseAnonKey: configAuth.supabaseAnonKey.isNotEmpty
          ? configAuth.supabaseAnonKey
          : _defaultSupabaseAnonKey,
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
  // Termos 14.3: identificação do aparelho nas chamadas com sessão.
  sessaoTrato.cabecalhosDoAparelho = await carregarCabecalhosDoAparelho();
  sessaoTrato.enviarAcesso = ClienteApi(urlBase: config.apiUrl, sessao: sessaoTrato).enviarAcesso;
  sessaoTrato.aoExpirar = abrirLoginPorSessaoExpirada;
  // 403 `conta_bloqueada`: tela de bloqueio, sem logout. Sair da conta esquece o bloqueio.
  sessaoTrato.aoBloquear =
      (mensagem) => RotasTrato.contaFoiBloqueada(() => navegadorTrato.currentState, mensagem);
  sessaoTrato.aoInativar =
      (mensagem) => RotasTrato.contaFoiInativada(() => navegadorTrato.currentState, mensagem);
  sessaoTrato.aoSair.add(() async {
    RotasTrato.esquecerBloqueio();
    RotasTrato.esquecerInatividade();
  });
  abrirLoginPorSessaoExpiradaHook = abrirLoginPorSessaoExpirada;
  RotasTrato.sessao = sessaoTrato;
  RotasTrato.dispositivo = dispositivoReal(navegador: navegadorTrato);
  RotasTrato.push = ServicoPushFirebase();
  // Abriu o app sem ninguém logada: não sobra leitura guardada de uma conta anterior.
  final cacheLeitura = CacheLeitura(CacheArquivo(), usuarioId: () => sessaoTrato.usuarioId);
  await cacheLeitura.limparSeSemSessao(temSessao: ServicoAuthPadrao.atual.sessaoAtual != null);
  RotasTrato.repos = RepositoriosTrato.deConfig(
    config,
    sessaoTrato,
    cache: cacheLeitura,
    criarUpload: ServicoUploadApi.new,
    camera: ServicoCameraReal(),
    localizacao: const ServicoLocalizacaoReal(),
    fila: await _abrirFilaOffline(),
  );
  RotasTrato.folhaCartao = FolhaCartaoStripe();
  // Sem internet, testa a rede de tempos em tempos; ao voltar, recarrega as telas com dados novos.
  final sondaApi = ClienteApi(urlBase: config.apiUrl, sessao: sessaoTrato);
  MonitorConexao(
    sonda: () => sondaApi.get('/v1/config/publica'),
    aoReconectar: () => RotasTrato.pedidosMudaram.value++,
  );
  LigacaoSessao(
    ServicoAuthPadrao.atual,
    sessaoTrato,
    // Primeiro login: GET /v1/me cria o usuário no backend (idempotente).
    // Só no modo api; em demo não chama nada.
    aoEntrar: () async {
      if (config.usaApi) {
        try {
          await RotasTrato.repos.perfil.carregar();
        } on Object {
          // Rede instável no perfil não impede tentar registrar o push.
        }
        await RotasTrato.sincronizarPush();
      }
    },
  );
  // Link do e-mail de recuperação: o app abre direto na tela de senha nova.
  if (configAuth.supabaseConfigurado) {
    ServicoAuthPadrao.atual.recuperacaoDeSenha.listen((_) => _abrirNovaSenha());
  }
  // Links br.com.feitolabs.trato://pedido/<id> etc. (o login-callback fica com o supabase_flutter).
  DeepLinks.navegador = () => navegadorTrato.currentState;
  DeepLinks.ligar();
  // Toque na notificação push (app fechado, em segundo plano) e aviso com o app aberto.
  unawaited(ServicoToquePush().ligar(
    aoToque: (m) => DeepLinks.receberPush(m.dados),
    // A mensagem que abriu o app tem prioridade sobre qualquer endereço da partida.
    aoInicial: (m) => DeepLinks.receberPush(m.dados, inicial: true),
    aoChegar: AvisoPush.mostrar,
  ));
  runApp(TratoApp(
    // Termos 4.1: sem data de nascimento, completar o cadastro antes de usar o app.
    portao: (filho) => RotasTrato.portaoCadastro(filho, () => navegadorTrato.currentContext),
  ));
}

/// Fila de check-in/check-out sem internet, guardada no aparelho. Se o armazenamento falhar, o
/// app segue sem fila (o check-in só funciona com internet) em vez de não abrir.
Future<FilaOffline?> _abrirFilaOffline() async {
  try {
    return await FilaOfflineArquivo.abrir();
  } on Object {
    return null;
  }
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
  const TratoApp({super.key, this.themeMode, this.portao});

  final ThemeMode? themeMode;

  /// Envolve o navegador inteiro (o `main` liga o portão do cadastro).
  final Widget Function(Widget filho)? portao;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: ControladorTema.instancia,
      builder: (context, _) => MaterialApp(
        title: 'Trato',
        // Português do Brasil também nos componentes do sistema (calendário, relógio, botões).
        locale: const Locale('pt', 'BR'),
        supportedLocales: const [Locale('pt', 'BR')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        navigatorKey: navegadorTrato,
        debugShowCheckedModeBanner: false,
        theme: TemaTrato.claro,
        darkTheme: TemaTrato.escuro,
        themeMode: themeMode ?? ControladorTema.instancia.modo,
        builder: (context, filho) => EscalaFonteLimitada(
          // Faixa de "sem conexão" no topo, empurrando o app para baixo (não cobre a AppBar).
          child: MoldeConexao(
            aoTentarNovamente: () => RotasTrato.pedidosMudaram.value++,
            child: portao?.call(filho!) ?? filho!,
          ),
        ),
        // Com deep link ligado, o Android entrega o endereço do link como rota inicial. O app
        // sempre começa pela tela inicial; quem abre o destino é o DeepLinks.
        onGenerateInitialRoutes: (_) => [
          MaterialPageRoute<void>(
            builder: (_) => _mostrarGaleria ? const GaleriaComponentes() : const SplashTela(),
          ),
        ],
        onUnknownRoute: (_) => MaterialPageRoute<void>(
          builder: (_) => _mostrarGaleria ? const GaleriaComponentes() : const SplashTela(),
        ),
      ),
    );
  }
}
