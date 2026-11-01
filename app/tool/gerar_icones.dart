// ignore_for_file: avoid_print

import 'dart:io';
import 'package:image/image.dart' as img;

void main() {
  final origem = File(r'C:\Empresas\Feito Labs\Apps\Trato\image\logo\trato-feito-icone-loja-1024.png');
  if (!origem.existsSync()) {
    stderr.writeln('Arquivo não encontrado: ${origem.path}');
    exit(1);
  }

  final bytes = origem.readAsBytesSync();
  final original = img.decodePng(bytes);
  if (original == null) {
    stderr.writeln('Erro ao decodificar PNG original.');
    exit(1);
  }

  print('Imagem original carregada: ${original.width}x${original.height}');

  void salvar(String caminho, int largura, int altura) {
    final redimensionada = (largura == original.width && altura == original.height)
        ? original
        : img.copyResize(original, width: largura, height: altura, interpolation: img.Interpolation.linear);
    final codificada = img.encodePng(redimensionada);
    final arquivo = File(caminho);
    arquivo.parent.createSync(recursive: true);
    arquivo.writeAsBytesSync(codificada);
    print('Gerado: $caminho (${largura}x$altura)');
  }

  // 1. Android mipmaps
  final androidRes = 'android/app/src/main/res';
  salvar('$androidRes/mipmap-mdpi/ic_launcher.png', 48, 48);
  salvar('$androidRes/mipmap-hdpi/ic_launcher.png', 72, 72);
  salvar('$androidRes/mipmap-xhdpi/ic_launcher.png', 96, 96);
  salvar('$androidRes/mipmap-xxhdpi/ic_launcher.png', 144, 144);
  salvar('$androidRes/mipmap-xxxhdpi/ic_launcher.png', 192, 192);

  // 2. iOS AppIcon
  final iosIcons = 'ios/Runner/Assets.xcassets/AppIcon.appiconset';
  salvar('$iosIcons/Icon-App-20x20@1x.png', 20, 20);
  salvar('$iosIcons/Icon-App-20x20@2x.png', 40, 40);
  salvar('$iosIcons/Icon-App-20x20@3x.png', 60, 60);
  salvar('$iosIcons/Icon-App-29x29@1x.png', 29, 29);
  salvar('$iosIcons/Icon-App-29x29@2x.png', 58, 58);
  salvar('$iosIcons/Icon-App-29x29@3x.png', 87, 87);
  salvar('$iosIcons/Icon-App-40x40@1x.png', 40, 40);
  salvar('$iosIcons/Icon-App-40x40@2x.png', 80, 80);
  salvar('$iosIcons/Icon-App-40x40@3x.png', 120, 120);
  salvar('$iosIcons/Icon-App-60x60@2x.png', 120, 120);
  salvar('$iosIcons/Icon-App-60x60@3x.png', 180, 180);
  salvar('$iosIcons/Icon-App-76x76@1x.png', 76, 76);
  salvar('$iosIcons/Icon-App-76x76@2x.png', 152, 152);
  salvar('$iosIcons/Icon-App-83.5x83.5@2x.png', 167, 167);
  salvar('$iosIcons/Icon-App-1024x1024@1x.png', 1024, 1024);

  // 3. Asset do app
  salvar('assets/logo/trato_logo.png', 1024, 1024);

  print('Todos os ícones foram gerados com sucesso!');
}
