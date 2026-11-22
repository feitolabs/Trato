import 'package:flutter_test/flutter_test.dart';
import 'package:trato/telas/orcamentos/modelos.dart';

DetalheOrcamento _detalhe({List<String> tipos = const [], String fora = ''}) => DetalheOrcamento(
      validoAte: '31/10',
      itens: const [ItemOrcamento(descricao: 'Tinta', centavos: 4000)],
      notaMaterial: '',
      agendaTitulo: '',
      agendaDetalhe: '',
      garantiaTitulo: '',
      garantiaDetalhe: '',
      foraDoEscopo: fora,
      cancelamento: '',
      tiposDosItens: tipos,
    );

void main() {
  group('F53 · Inclui mostra Material listado com Demais materiais em Fora do escopo', () {
    test('item de material + Demais materiais (case-insensitive) mostra Material listado em Inclui',
        () {
      final d1 = _detalhe(tipos: ['horas', 'material'], fora: 'Demais materiais');
      expect(textoInclui(d1), 'Mão de obra, Material listado');
      expect(textoNaoInclui(d1), 'Demais materiais');

      final d2 = _detalhe(
        tipos: ['deslocamento', 'material'],
        fora: 'Limpeza, demais materiais',
      );
      expect(textoInclui(d2), 'Deslocamento, Material listado');
      expect(textoNaoInclui(d2), 'Limpeza, demais materiais');
    });

    test('item de material + Material literal continua virando Material listado e Demais materiais',
        () {
      final d = _detalhe(tipos: ['horas', 'material'], fora: 'Material');
      expect(textoInclui(d), 'Mão de obra, Material listado');
      expect(textoNaoInclui(d), 'Demais materiais');
    });

    test('sem item de material em Inclui, nada muda', () {
      final d1 = _detalhe(tipos: ['horas'], fora: 'Demais materiais');
      expect(textoInclui(d1), 'Mão de obra');
      expect(textoNaoInclui(d1), 'Demais materiais');

      final d2 = _detalhe(tipos: ['horas'], fora: 'Material');
      expect(textoInclui(d2), 'Mão de obra');
      expect(textoNaoInclui(d2), 'Material');
    });
  });
}
