import 'package:trato/telas/nota_material/nota_material.dart';

/// PROVISÓRIO — só para teste e demonstração.
class ServicoNotaMaterialFake implements ServicoNotaMaterial {
  ServicoNotaMaterialFake({this.nota, this.falharAoCarregar = false, this.falharAoEnviar = false});

  final NotaMaterial? nota;
  final bool falharAoCarregar;
  final bool falharAoEnviar;
  final List<EnvioNota> enviados = [];

  @override
  Future<NotaMaterial?> carregar(String pedidoId) async {
    if (falharAoCarregar) throw Exception('falha de teste');
    return nota;
  }

  @override
  Future<void> enviar(EnvioNota envio) async {
    if (falharAoEnviar) throw Exception('falha de teste');
    enviados.add(envio);
  }
}

final notaMaterialExemplo = NotaMaterial(
  pedidoTitulo: 'Troca de tomadas e chuveiro',
  profissional: 'Carlos',
  enviadaEm: DateTime(2026, 10, 28),
  fotoNota: 'nota-123',
  itens: const [
    ItemNota(descricao: '2 tomadas 20 A', centavos: 4600),
    ItemNota(descricao: 'Resistência 220 V', centavos: 6400),
    ItemNota(descricao: 'Fita isolante', centavos: 900),
  ],
);
