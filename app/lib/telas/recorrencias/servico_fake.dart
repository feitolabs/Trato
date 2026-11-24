import '../../dados/erros.dart';
import 'modelos.dart';

/// Demonstração e testes: guarda as séries na memória e imita as regras do backend de forma
/// simples (sem rede). Quem decide de verdade é sempre o backend.
class ServicoRecorrenciasFake implements ServicoRecorrencias {
  ServicoRecorrenciasFake({List<Recorrencia>? series, this.falharAoCarregar = false})
      : series = [...?series];

  final List<Recorrencia> series;
  final bool falharAoCarregar;

  /// Chamadas feitas, na ordem (`propor`, `aceitar:id`, `pular-visita:id:visita`...).
  final List<String> chamadas = [];

  /// Se preenchido, a próxima ação falha com esse erro (texto do backend).
  ErroTrato? erroNaProxima;

  int _indice(String id) {
    final i = series.indexWhere((s) => s.id == id);
    if (i < 0) throw const ErroTrato(TipoErro.naoEncontrado, 'Serviço recorrente não encontrado.');
    return i;
  }

  void _checar() {
    final e = erroNaProxima;
    if (e != null) {
      erroNaProxima = null;
      throw e;
    }
  }

  Recorrencia _trocar(
    String id, {
    String? status,
    int? valorCentavos,
    int? Function()? valorProposto,
    List<VisitaRecorrente>? visitas,
  }) {
    final i = _indice(id);
    final s = series[i];
    final nova = Recorrencia(
      id: s.id,
      status: status ?? s.status,
      frequencia: s.frequencia,
      valorCentavos: valorCentavos ?? s.valorCentavos,
      valorPropostoCentavos: valorProposto != null ? valorProposto() : s.valorPropostoCentavos,
      proximaVisita: s.proximaVisita,
      meuPapel: s.meuPapel,
      propostoPorMim: s.propostoPorMim,
      outraParteNome: s.outraParteNome,
      pedidoOrigemId: s.pedidoOrigemId,
      visitas: visitas ?? s.visitas,
    );
    series[i] = nova;
    return nova;
  }

  @override
  Future<List<Recorrencia>> listar() async {
    if (falharAoCarregar) throw ErroTrato.servidor;
    return List.of(series);
  }

  @override
  Future<Recorrencia> detalhe(String id) async {
    if (falharAoCarregar) throw ErroTrato.servidor;
    return series[_indice(id)];
  }

  @override
  Future<Recorrencia> propor(String pedidoOrigemId, PropostaRecorrencia proposta) async {
    chamadas.add('propor');
    _checar();
    final nova = Recorrencia(
      id: 'rec-${series.length + 1}',
      status: 'proposta',
      frequencia: proposta.frequencia.codigo,
      valorCentavos: proposta.valorCentavos ?? 12000,
      proximaVisita: proposta.proximaVisita,
      meuPapel: 'cliente',
      propostoPorMim: true,
      outraParteNome: 'Carlos M.',
      pedidoOrigemId: pedidoOrigemId,
    );
    series.insert(0, nova);
    return nova;
  }

  @override
  Future<Recorrencia> aceitar(String id) async {
    chamadas.add('aceitar:$id');
    _checar();
    return _trocar(id, status: 'ativa');
  }

  @override
  Future<Recorrencia> recusar(String id) async {
    chamadas.add('recusar:$id');
    _checar();
    return _trocar(id, status: 'cancelada');
  }

  @override
  Future<Recorrencia> pausar(String id) async {
    chamadas.add('pausar:$id');
    _checar();
    return _trocar(id, status: 'pausada');
  }

  @override
  Future<Recorrencia> retomar(String id) async {
    chamadas.add('retomar:$id');
    _checar();
    return _trocar(id, status: 'ativa');
  }

  @override
  Future<Recorrencia> cancelar(String id) async {
    chamadas.add('cancelar:$id');
    _checar();
    return _trocar(id, status: 'cancelada');
  }

  @override
  Future<Recorrencia> pularProxima(String id) async {
    chamadas.add('pular-proxima:$id');
    _checar();
    return series[_indice(id)];
  }

  @override
  Future<Recorrencia> pularVisita(String id, String visitaId) async {
    chamadas.add('pular-visita:$id:$visitaId');
    _checar();
    final s = series[_indice(id)];
    return _trocar(
      id,
      visitas: [
        for (final v in s.visitas)
          if (v.id == visitaId)
            VisitaRecorrente(
              id: v.id,
              dataPrevista: v.dataPrevista,
              status: 'pulada',
              pedidoId: v.pedidoId,
            )
          else
            v,
      ],
    );
  }

  @override
  Future<Recorrencia> proporReajuste(String id, int valorCentavos) async {
    chamadas.add('reajuste:$id:$valorCentavos');
    _checar();
    return _trocar(id, valorProposto: () => valorCentavos);
  }

  @override
  Future<Recorrencia> aceitarReajuste(String id, int valorCentavos) async {
    chamadas.add('reajuste-aceitar:$id:$valorCentavos');
    _checar();
    final s = series[_indice(id)];
    // Como o backend: o valor aceito precisa ser o proposto naquele momento.
    if (s.valorPropostoCentavos != valorCentavos) {
      throw const ErroTrato(
        TipoErro.recusado,
        'O valor do reajuste mudou. Confira o novo valor.',
        codigoHttp: 409,
      );
    }
    return _trocar(id, valorCentavos: s.valorPropostoCentavos, valorProposto: () => null);
  }

  @override
  Future<Recorrencia> recusarReajuste(String id) async {
    chamadas.add('reajuste-recusar:$id');
    _checar();
    return _trocar(id, valorProposto: () => null);
  }
}
