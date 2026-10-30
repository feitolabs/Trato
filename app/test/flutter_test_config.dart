import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

/// Configuração comum de todos os testes do app.
///
/// `TRATO_GOLDEN=ignorar` (só no CI) faz o teste golden NÃO falhar por diferença de pixel:
/// os goldens foram gerados no Windows e o Linux rasteriza as fontes de outro jeito.
/// A imagem continua sendo gerada e comparada (a diferença vai para o log), e a falta
/// do arquivo de referência continua sendo erro. Sem a variável, a comparação é exata.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  if (Platform.environment['TRATO_GOLDEN'] == 'ignorar') {
    final atual = goldenFileComparator;
    if (atual is LocalFileComparator) {
      goldenFileComparator = _ComparadorSoAviso(atual.basedir.resolve('_.dart'));
    }
  }
  await testMain();
}

class _ComparadorSoAviso extends LocalFileComparator {
  _ComparadorSoAviso(super.testFile);

  @override
  Future<bool> compare(Uint8List imageBytes, Uri golden) async {
    // Lança se o arquivo de referência não existe: isso continua falhando.
    final referencia = await getGoldenBytes(golden);
    final resultado = await GoldenFileComparator.compareLists(imageBytes, referencia);
    if (!resultado.passed) {
      // ignore: avoid_print
      print('GOLDEN IGNORADO (TRATO_GOLDEN=ignorar): $golden — ${resultado.error}');
    }
    return true;
  }
}
