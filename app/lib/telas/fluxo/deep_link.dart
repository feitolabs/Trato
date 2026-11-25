import 'dart:async';

import 'package:flutter/widgets.dart';

import '../../componentes/tela_nao_encontrada.dart';
import '../auth/login_tela.dart';
import 'deep_link_modelo.dart';
import 'navegacao_casca.dart';
import 'rotas.dart';

/// Recebe os links do tipo `br.com.feitolabs.trato://pedido/<id>` e abre a tela. Há um único
/// caminho de navegação: o mesmo de [RotasTrato.abrirDestino], que o toque numa notificação usa.
///
/// - App aberto e logado: abre na hora.
/// - App frio ou ainda sem a casca na tela: guarda o destino em memória e abre quando ela aparecer.
/// - Sem login: leva ao login; depois de entrar, abre o destino.
abstract final class DeepLinks {
  /// Quem entrega o navegador raiz (o `main.dart` liga).
  static NavigatorState? Function() navegador = () => null;

  static var _loginAberto = false;
  static String? _ultimo;
  static DateTime? _ultimoEm;

  /// Um endereço chegou. Devolve se é do app (e portanto já foi tratado, mesmo sendo ignorado).
  static bool receber(Uri uri, {DateTime Function()? agora}) {
    if (uri.scheme.toLowerCase() != esquemaDoApp) return false;
    _aceitar(interpretarLink(uri), uri.toString(), agora);
    return true;
  }

  /// O toque numa notificação push (app fechado, em segundo plano ou aberto) chegou. Vai pelo
  /// mesmo caminho do link: se ainda não há navegador ou a pessoa não entrou, espera.
  /// [inicial]: é a mensagem que ABRIU o app (app fechado). Ela tem prioridade sobre o endereço
  /// da partida: se esse endereço ainda espera para abrir, é descartado (o destino do push vence).
  static void receberPush(Map<String, dynamic> dados,
      {DateTime Function()? agora, bool inicial = false}) {
    try {
      final r = resultadoDoPush(dados);
      if (inicial && r.situacao != SituacaoLink.ignorado && _pendenteDaPartida) {
        LinkPendente.limpar();
      }
      _pendenteDaPartida = false;
      _aceitar(r, 'push:${r.destino}:${r.id}', agora);
    } on Object {
      // Dado estranho nunca derruba o app.
    }
  }

  static void _aceitar(ResultadoLink resultado, String chave, DateTime Function()? agora) {
    if (resultado.situacao == SituacaoLink.ignorado) return;
    // O sistema pode entregar o mesmo toque duas vezes (partida a frio): abre uma só.
    final t = (agora ?? DateTime.now)();
    if (_ultimo == chave && _ultimoEm != null && t.difference(_ultimoEm!).inSeconds < 2) {
      return;
    }
    _ultimo = chave;
    _ultimoEm = t;
    LinkPendente.guardar(resultado);
    processar();
  }

  /// A casca (Início do cliente ou do profissional) acabou de aparecer: abre o que estava
  /// esperando.
  static void aoCascaPronta() {
    _loginAberto = false;
    if (LinkPendente.atual != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => processar(dePronta: true));
    }
  }

  static void processar({int tentativa = 0, bool dePronta = false}) {
    if (LinkPendente.atual == null) return;
    final nav = navegador();
    if (nav == null) {
      // Partida a frio: o navegador ainda não existe. Tenta de novo no próximo quadro.
      if (tentativa < 60) {
        WidgetsBinding.instance.addPostFrameCallback((_) => processar(tentativa: tentativa + 1, dePronta: dePronta));
      }
      return;
    }
    if (!RotasTrato.temSessao) {
      if (_loginAberto) return;
      _loginAberto = true;
      nav.pushAndRemoveUntil(
        PageRouteBuilder<void>(
          pageBuilder: (_, __, ___) => const LoginTela(),
          transitionDuration: Duration.zero,
        ),
        (_) => false,
      );
      return;
    }
    if (!ControladorCasca.ativa) return; // aoCascaPronta chama de novo
    if (_trocandoModo) return;
    final pendente = LinkPendente.atual;
    if (pendente == null) return;
    // O push diz em que modo a tela deve abrir (`papel`). Ausente = o modo de agora.
    final papel = pendente.papel;
    if (papel != null && (papel == 'profissional') != ControladorCasca.souProfissional) {
      if (_trocouModo) {
        // Já troquei de modo: espero a casca nova. Se ela chegou e ainda é a errada, desisto: não
        // abre no modo errado.
        if (dePronta) {
          _trocouModo = false;
          _limiteDaTroca?.cancel();
          _limiteDaTroca = null;
          LinkPendente.limpar();
        }
        return;
      }
      unawaited(_trocarModo(nav, paraProfissional: papel == 'profissional'));
      return;
    }
    _trocouModo = false;
    _limiteDaTroca?.cancel();
    _limiteDaTroca = null;
    _pendenteDaPartida = false;
    final link = LinkPendente.retirar();
    final contexto = nav.context;
    if (link == null || !contexto.mounted) return;
    RotasTrato.abrirLink(contexto, link);
  }

  static var _trocandoModo = false;
  static var _trocouModo = false;
  static Timer? _limiteDaTroca;

  /// Quanto esperar a casca do outro modo antes de abrir o destino mesmo assim.
  static Duration esperaDaTroca = const Duration(seconds: 6);

  static void _abrirSemEsperar(NavigatorState nav) {
    _limiteDaTroca = null;
    if (!_trocouModo) return;
    _trocouModo = false;
    final link = LinkPendente.retirar();
    if (link == null) return;
    final contexto = nav.context;
    if (contexto.mounted) RotasTrato.abrirLink(contexto, link);
  }

  /// Troca de cliente para profissional (ou o contrário) antes de abrir. Para profissional só se a
  /// conta tem perfil de profissional; sem ele o link é descartado e nenhuma tela de profissional
  /// abre. Ao trocar, a nova casca avisa ([aoCascaPronta]) e o destino abre nela.
  static Future<void> _trocarModo(NavigatorState nav, {required bool paraProfissional}) async {
    _trocandoModo = true;
    try {
      if (paraProfissional && !await RotasTrato.usuarioTemPerfilProfissional()) {
        LinkPendente.limpar();
        return;
      }
      final contexto = nav.context;
      if (!contexto.mounted) return;
      _trocouModo = true;
      // Se a casca do modo pedido não aparecer a tempo (verificação, rede lenta), abre o destino
      // mesmo assim, no modo que o push pediu (o `papel` manda; não o estado da casca).
      _limiteDaTroca?.cancel();
      _limiteDaTroca = Timer(esperaDaTroca, () => _abrirSemEsperar(nav));
      if (paraProfissional) {
        await RotasTrato.irParaProfissional(contexto);
      } else {
        RotasTrato.irParaCliente(contexto);
      }
    } on Object {
      LinkPendente.limpar();
      _trocouModo = false;
      _limiteDaTroca?.cancel();
      _limiteDaTroca = null;
    } finally {
      _trocandoModo = false;
    }
  }

  /// Ouve os links com o app aberto ou em segundo plano. Chame antes do `runApp`, para vir antes
  /// do tratamento padrão de rotas do Flutter.
  /// O toque numa notificação da CAIXA. Mesmo caminho do push: se o `papel` é o modo em que o app
  /// está (ou não veio), abre aqui; senão guarda o destino, troca de modo e abre na casca certa.
  static void abrirDaCaixa(BuildContext context, ResultadoLink r, {required bool profissional}) {
    final papel = r.papel;
    if (papel == null || (papel == 'profissional') == profissional) {
      RotasTrato.abrirLink(context, r, profissional: profissional);
      return;
    }
    LinkPendente.guardar(r);
    processar();
  }

  static var _ligado = false;

  static void ligar() {
    ControladorCasca.aoCascaPronta = aoCascaPronta;
    if (!_ligado) {
      _ligado = true;
      WidgetsBinding.instance.addObserver(_Ouvinte());
    }
    // Partida a frio: o endereço que abriu o app. Lido UMA vez por processo (consumido).
    if (_inicialLido) return;
    _inicialLido = true;
    final inicial = WidgetsBinding.instance.platformDispatcher.defaultRouteName;
    final uri = Uri.tryParse(inicial);
    if (uri != null) {
      receber(uri);
      _pendenteDaPartida = LinkPendente.atual != null;
    }
  }

  static var _inicialLido = false;

  /// O destino guardado veio do endereço da partida (não de um toque de push).
  static var _pendenteDaPartida = false;

  /// Só para testes: volta ao estado de um processo recém-iniciado.
  @visibleForTesting
  static void reiniciarParaTeste() {
    esquecer();
    _inicialLido = false;
    _pendenteDaPartida = false;
  }

  static void esquecer() {
    LinkPendente.limpar();
    _loginAberto = false;
    _trocouModo = false;
    _trocandoModo = false;
    _limiteDaTroca?.cancel();
    _limiteDaTroca = null;
    _ultimo = null;
  }
}

class _Ouvinte with WidgetsBindingObserver {
  @override
  Future<bool> didPushRouteInformation(RouteInformation informacao) async =>
      DeepLinks.receber(informacao.uri);
}

/// Quando o id do link não serve, a pessoa vê "não encontrado" (nunca erro nem tela branca).
Widget telaLinkInvalido(DestinoApp destino) => TelaNaoEncontrada(
      texto: switch (destino) {
        DestinoApp.orcamentos => TextosNaoEncontrado.orcamento,
        DestinoApp.chat => TextosNaoEncontrado.conversa,
        DestinoApp.recorrencia => TextosNaoEncontrado.recorrencia,
        _ => TextosNaoEncontrado.pedido,
      },
    );
