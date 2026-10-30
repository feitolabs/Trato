import 'package:flutter_test/flutter_test.dart';
import 'package:trato_admin/dados/api_fake.dart';
import 'package:trato_admin/dados/modelos.dart';

void main() {
  test('segunda pessoa: quem decidiu não aprova, outra pessoa sim', () async {
    final api = ApiFake();
    await api.entrar('mediador@teste.local', 'senha-de-teste');
    final r = await api.decidirDisputa(
      'd-1',
      decisao: DecisaoDisputa.reembolsoTotal,
      justificativa: 'Serviço não entregue',
    );
    expect(r.status, StatusDisputa.aguardandoSegundaPessoa);
    await api.entrar('mediador@teste.local', 'senha-de-teste');
    expect(
      () => api.aprovarDisputa('d-1', justificativa: 'Confirmo a decisão'),
      throwsA(isA<ErroApi>()),
    );
    await api.entrar('lider_suporte@teste.local', 'senha-de-teste');
    final ok = await api.aprovarDisputa('d-1', justificativa: 'Confirmo a decisão');
    expect(ok.status, StatusDisputa.decidida);
  });
}
