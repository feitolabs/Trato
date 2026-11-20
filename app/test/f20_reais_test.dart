import 'package:flutter_test/flutter_test.dart';
import 'package:trato/telas/conclusao/apoio_conclusao.dart' as conclusao;
import 'package:trato/telas/pedidos/modelos.dart' as pedidos;
import 'package:trato/telas/profissional/dinheiro.dart';
import 'package:trato/telas/profissional_inicio/pecas_profissional.dart';

void main() {
  test('uma lógica só: os atalhos antigos devolvem o mesmo que Dinheiro.formatar', () {
    for (final c in [-123456789, -1025, -50, -1, 0, 5, 99, 100, 1025, 100000, 123456789]) {
      expect(pedidos.formatarReais(c), Dinheiro.formatar(c));
      expect(conclusao.formatarReais(c), Dinheiro.formatar(c));
    }
  });

  test('formatarCurto: sem centavos quando redondo, com sinal certo', () {
    expect(reaisCurto(20000), 'R\$ 200');
    expect(reaisCurto(1250), 'R\$ 12,50');
    expect(reaisCurto(150000), 'R\$ 1.500');
    expect(Dinheiro.formatarCurto(-1025), '-R\$ 10,25');
    expect(Dinheiro.formatarCurto(-1000), '-R\$ 10');
  });

  test('textos de campo (sem float): 2 casas ou sem zeros, sinal certo', () {
    expect(Dinheiro.paraCampo(1250), '12,50');
    expect(Dinheiro.paraCampo(1000), '10,00');
    expect(Dinheiro.paraCampo(5), '0,05');
    expect(Dinheiro.paraCampo(-1025), '-10,25');
    expect(Dinheiro.paraCampo(-50), '-0,50');
    expect(Dinheiro.paraCampoSemZeros(1000), '10');
    expect(Dinheiro.paraCampoSemZeros(1025), '10,25');
    expect(Dinheiro.paraCampoSemZeros(-1025), '-10,25');
  });
}
