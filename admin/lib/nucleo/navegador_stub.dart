/// Fora do navegador (testes, desktop): não há URL do painel nem hash para limpar.
Uri urlAtual() => Uri.base;

/// Sem efeito fora do navegador.
void limparHash() {}

/// Fora do navegador não há onde salvar: devolve false (nada foi baixado).
bool salvarArquivo(List<int> bytes, String nome, String tipo) => false;
