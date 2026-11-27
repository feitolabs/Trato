/// Termos 5.2 e 6.3: orçamento vencido. Quem decide é o servidor (409 `orcamento_vencido`); o app
/// mostra o aviso junto da ação e não tenta de novo sozinho.
library;

import '../../dados/erros.dart';
import 'formato_aparelho.dart';

const textoOrcamentoVencido =
    'Este orçamento venceu e perdeu o efeito. Peça um novo ao profissional.';

/// "Orçamento válido até 30/11/2026, 14:30."
String textoOrcamentoValidoAte(DateTime ate) {
  final d = ate.toLocal();
  String dois(int n) => n.toString().padLeft(2, '0');
  return 'Orçamento válido até ${dois(d.day)}/${dois(d.month)}/${d.year}, ${horaDoAparelho(ate)}.';
}

bool ehOrcamentoVencido(Object erro) => erro is ErroTrato && erro.codigo == 'orcamento_vencido';
