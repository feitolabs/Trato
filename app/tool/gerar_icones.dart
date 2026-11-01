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

  final p0 = original.getPixel(0, 0);
  final r = p0.r.toInt();
  final g = p0.g.toInt();
  final b = p0.b.toInt();
  final hexColor = '#${r.toRadixString(16).padLeft(2, '0')}${g.toRadixString(16).padLeft(2, '0')}${b.toRadixString(16).padLeft(2, '0')}'.toUpperCase();
  print('Imagem carregada: ${original.width}x${original.height}. Cor de fundo: $hexColor (R=$r, G=$g, B=$b)');

  void salvarImagem(String caminho, img.Image imagem) {
    final codificada = img.encodePng(imagem);
    final arquivo = File(caminho);
    arquivo.parent.createSync(recursive: true);
    arquivo.writeAsBytesSync(codificada);
    print('Gerado: $caminho (${imagem.width}x${imagem.height})');
  }

  void salvar(String caminho, int largura, int altura) {
    final redimensionada = (largura == original.width && altura == original.height)
        ? original
        : img.copyResize(original, width: largura, height: altura, interpolation: img.Interpolation.linear);
    salvarImagem(caminho, redimensionada);
  }

  img.Image gerarCircular(int size) {
    final redim = img.copyResize(original, width: size, height: size, interpolation: img.Interpolation.linear);
    final circ = img.Image(width: size, height: size, numChannels: 4);
    final raio = size / 2.0;
    final raioSq = raio * raio;
    for (int y = 0; y < size; y++) {
      for (int x = 0; x < size; x++) {
        final dx = x - raio + 0.5;
        final dy = y - raio + 0.5;
        if (dx * dx + dy * dy <= raioSq) {
          circ.setPixel(x, y, redim.getPixel(x, y));
        } else {
          circ.setPixelRgba(x, y, 0, 0, 0, 0);
        }
      }
    }
    return circ;
  }

  img.Image gerarForeground(int canvasSize, int iconSize) {
    final fg = img.Image(width: canvasSize, height: canvasSize, numChannels: 4);
    img.fill(fg, color: img.ColorRgba8(r, g, b, 255));
    final logoReduzido = img.copyResize(original, width: iconSize, height: iconSize, interpolation: img.Interpolation.linear);
    final dx = (canvasSize - iconSize) ~/ 2;
    final dy = (canvasSize - iconSize) ~/ 2;
    img.compositeImage(fg, logoReduzido, dstX: dx, dstY: dy);
    return fg;
  }

  final androidRes = 'android/app/src/main/res';

  // 1. Android ícones padrão (legado)
  final densities = <String, int>{
    'mdpi': 48,
    'hdpi': 72,
    'xhdpi': 96,
    'xxhdpi': 144,
    'xxxhdpi': 192,
  };

  for (final entry in densities.entries) {
    salvar('$androidRes/mipmap-${entry.key}/ic_launcher.png', entry.value, entry.value);
    salvarImagem('$androidRes/mipmap-${entry.key}/ic_launcher_round.png', gerarCircular(entry.value));
  }

  // 2. Android adaptive icons (108dp base: safe-zone 72dp = 66.7%)
  final fgDensities = <String, int>{
    'mdpi': 108,
    'hdpi': 162,
    'xhdpi': 216,
    'xxhdpi': 324,
    'xxxhdpi': 432,
  };

  for (final entry in fgDensities.entries) {
    final canvasSize = entry.value;
    final iconSize = (canvasSize * (72.0 / 108.0)).round();
    salvarImagem('$androidRes/mipmap-${entry.key}/ic_launcher_foreground.png', gerarForeground(canvasSize, iconSize));
  }

  // 3. iOS AppIcon
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

  // 4. Asset do app
  salvar('assets/logo/trato_logo.png', 1024, 1024);

  print('Todos os ícones (padrão, circular e adaptativo) foram gerados com sucesso!');
}
