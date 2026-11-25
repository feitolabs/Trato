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
  static void receberPush(Map<String, dynamic> dados, {DateTime Function()? agora}) {
    try {
      final r = resultadoDoPush(dados);
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
      WidgetsBinding.instance.addPostFrameCallback((_) => processar());
    }
  }

  static void processar([int tentativa = 0]) {
    if (LinkPendente.atual == null) return;
    final nav = navegador();
    if (nav == null) {
      // Partida a frio: o navegador ainda não existe. Tenta de novo no próximo quadro.
      if (tentativa < 60) {
        WidgetsBinding.instance.addPostFrameCallback((_) => processar(tentativa + 1));
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
    final link = LinkPendente.retirar();
    final contexto = nav.context;
    if (link == null || !contexto.mounted) return;
    RotasTrato.abrirLink(contexto, link);
  }

  /// Ouve os links com o app aberto ou em segundo plano. Chame antes do `runApp`, para vir antes
  /// do tratamento padrão de rotas do Flutter.
  static var _ligado = false;

  static void ligar() {
    ControladorCasca.aoCascaPronta = aoCascaPronta;
    if (!_ligado) {
      _ligado = true;
      WidgetsBinding.instance.addObserver(_Ouvinte());
    }
    // Partida a frio: o endereço que abriu o app.
    final inicial = WidgetsBinding.instance.platformDispatcher.defaultRouteName;
    final uri = Uri.tryParse(inicial);
    if (uri != null) receber(uri);
  }

  static void esquecer() {
    LinkPendente.limpar();
    _loginAberto = false;
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
