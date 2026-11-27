import '../nucleo/navegador.dart';

typedef ArquivoEscolhido = ({String nome, String tipo, int tamanho, List<int> bytes});

/// Quem abre o seletor de arquivo. Trocável nos testes.
Future<ArquivoEscolhido?> Function(String aceita, int maximoBytes) seletorDeArquivo = escolherArquivoNativo;

/// Recusa na tela o que já se sabe que o servidor não aceita. Devolve null se pode enviar.
String? problemaDoArquivo(ArquivoEscolhido a, List<String> aceitos, {int? maximoBytes}) {
  if (!aceitos.contains(a.tipo)) {
    return 'Este tipo de arquivo não é aceito. Use ${aceitos.contains('application/pdf') ? 'foto (JPG, PNG, WebP) ou PDF' : 'foto (JPG, PNG ou WebP)'}.';
  }
  if (a.tamanho <= 0) return 'O arquivo está vazio.';
  if (maximoBytes != null && a.tamanho > maximoBytes) {
    return 'O arquivo passa de ${maximoBytes ~/ (1024 * 1024)} MB.';
  }
  if (a.nome.isEmpty || a.nome.length > 200) return 'O nome do arquivo precisa ter até 200 caracteres.';
  return null;
}
