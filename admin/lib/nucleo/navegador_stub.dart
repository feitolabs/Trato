/// Fora do navegador (testes, desktop): não há URL do painel nem hash para limpar.
Uri urlAtual() => Uri.base;

/// Sem efeito fora do navegador.
void limparHash() {}
