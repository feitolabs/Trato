/// Fora do navegador (testes, desktop): não há URL do painel nem hash para limpar.
Uri urlAtual() => Uri.base;

/// Sem efeito fora do navegador.
void limparHash() {}

/// Fora do navegador não há onde salvar: devolve false (nada foi baixado).
bool salvarArquivo(List<int> bytes, String nome, String tipo) => false;

/// Fora do navegador não há seletor de arquivo.
Future<({String nome, String tipo, int tamanho, List<int> bytes})?> escolherArquivoNativo(
        String aceita, int maximoBytes) async =>
    null;

/// Fora do navegador não há aba para abrir.
bool abrirEmNovaAba(String url) => false;
