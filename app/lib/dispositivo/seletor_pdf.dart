/// Escolha de um PDF no aparelho (seletor de arquivos do sistema), para a contestação de medida.
library;

import 'package:file_selector/file_selector.dart';

import '../telas/medidas/modelos.dart';

/// O arquivo passa do limite: nem é lido para a memória.
class PdfGrandeDemais implements Exception {
  const PdfGrandeDemais(this.nome);

  final String nome;
}

const _pdf = XTypeGroup(
  label: 'PDF',
  extensions: ['pdf'],
  mimeTypes: ['application/pdf'],
  // O iOS escolhe pelo identificador do tipo.
  uniformTypeIdentifiers: ['com.adobe.pdf'],
);

/// Nulo: a pessoa fechou o seletor sem escolher.
Future<ProvaEscolhida?> escolherPdfDoAparelho() async {
  final arquivo = await openFile(acceptedTypeGroups: const [_pdf]);
  if (arquivo == null) return null;
  if (await arquivo.length() > tamanhoMaximoDaProva) throw PdfGrandeDemais(arquivo.name);
  return ProvaEscolhida(nome: arquivo.name, bytes: await arquivo.readAsBytes());
}
