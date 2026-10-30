import '../cliente/modelos.dart';

/// Contrato com o backend. A busca, o filtro e a ordem dos resultados são do backend.
abstract interface class ServicoBusca {
  /// Profissionais e serviços que combinam com [termo] (nome, serviço ou categoria).
  Future<List<Profissional>> buscar(String termo);
}
