// ignore_for_file: avoid_print

// Gera favicon e ícones do painel web (admin/web) a partir da logo do app.
// Rodar dentro de app/: dart run tool/gerar_icones_painel.dart

import 'dart:io';
import 'package:image/image.dart' as img;

void main() {
  final origem = File('assets/logo/trato_logo.png');
  final original = img.decodePng(origem.readAsBytesSync());
  if (original == null) {
    stderr.writeln('Erro ao decodificar ${origem.path}');
    exit(1);
  }

  void salvar(String caminho, int lado) {
    final r = img.copyResize(original, width: lado, height: lado, interpolation: img.Interpolation.average);
    File(caminho).writeAsBytesSync(img.encodePng(r));
    print('Gerado: $caminho (${lado}x$lado)');
  }

  const web = '../admin/web';
  salvar('$web/favicon.png', 64);
  salvar('$web/icons/Icon-192.png', 192);
  salvar('$web/icons/Icon-512.png', 512);
  // A logo já tem fundo cheio e o desenho dentro da zona segura: serve como maskable.
  salvar('$web/icons/Icon-maskable-192.png', 192);
  salvar('$web/icons/Icon-maskable-512.png', 512);
}
