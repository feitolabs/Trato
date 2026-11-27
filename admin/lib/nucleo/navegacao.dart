import 'package:flutter/widgets.dart';

/// Deixa uma tela pedir outra seção do menu. Quem abre uma rota por cima deve guardar a função
/// antes, porque a rota nova não enxerga este widget.
class NavegacaoPainel extends InheritedWidget {
  const NavegacaoPainel({super.key, required this.irPara, required super.child});

  final void Function(String idDaSecao) irPara;

  static void Function(String)? de(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<NavegacaoPainel>()?.irPara;

  @override
  bool updateShouldNotify(NavegacaoPainel antigo) => false;
}
