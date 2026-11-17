import 'package:flutter/widgets.dart';

/// Entrada de campo validável para rolagem automática até o primeiro erro.
class EntradaCampoErro {
  const EntradaCampoErro({
    required this.key,
    required this.temErro,
    this.focusNode,
  });

  final GlobalKey key;
  final FocusNode? focusNode;
  final bool Function() temErro;
}

/// Rola suavemente até o primeiro campo inválido de [entradas] e coloca o foco nele.
void focarPrimeiroErro(List<EntradaCampoErro> entradas) {
  WidgetsBinding.instance.addPostFrameCallback((_) {
    for (final entrada in entradas) {
      if (!entrada.temErro()) continue;
      final ctx = entrada.key.currentContext;
      if (ctx != null && ctx.mounted) {
        Scrollable.ensureVisible(
          ctx,
          duration: const Duration(milliseconds: 280),
          curve: Curves.easeOut,
          alignment: 0.22,
        );
      }
      if (entrada.focusNode != null && entrada.focusNode!.canRequestFocus) {
        entrada.focusNode!.requestFocus();
      }
      break;
    }
  });
}

/// Normaliza texto em português para busca e ordenação sem acento/caixa/pontuação.
String normalizarTextoBusca(String texto) {
  final semAcento = texto
      .toLowerCase()
      .replaceAll(RegExp('[áàâãä]'), 'a')
      .replaceAll(RegExp('[éèêë]'), 'e')
      .replaceAll(RegExp('[íìîï]'), 'i')
      .replaceAll(RegExp('[óòôõö]'), 'o')
      .replaceAll(RegExp('[úùûü]'), 'u')
      .replaceAll('ç', 'c');
  return semAcento.replaceAll(RegExp(r'[^0-9a-z]+'), ' ').trim();
}

/// Comparador alfabético PT-BR (insensível a acento e caixa).
int compararAlfabeticoPtBr(String a, String b) {
  final c = normalizarTextoBusca(a).compareTo(normalizarTextoBusca(b));
  return c != 0 ? c : a.toLowerCase().compareTo(b.toLowerCase());
}

