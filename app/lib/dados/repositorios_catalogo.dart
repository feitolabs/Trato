import '../telas/agenda/modelos.dart';
import '../telas/cliente/modelos.dart';
import '../telas/pedido_novo/modelos.dart';
import '../telas/servicos/modelos.dart';

/// Portas de dados do catálogo, dos serviços do cliente e da agenda do profissional.
/// Quem filtra, ordena e decide é o backend; o app só pede e mostra.

/// Filtros da lista de profissionais de uma categoria.
class FiltroProfissionais {
  const FiltroProfissionais({
    this.bairro,
    this.precoMaxCentavos,
    this.notaMinima,
    this.soDisponiveisHoje = false,
  });

  final String? bairro;
  final int? precoMaxCentavos;
  final double? notaMinima;
  final bool soDisponiveisHoje;

  bool get vazio => ativos == 0;

  /// Quantos filtros estão ligados (para o contador do botão "Filtros").
  int get ativos => [
        if (bairro != null && bairro!.isNotEmpty) 1,
        if (precoMaxCentavos != null) 1,
        if (notaMinima != null) 1,
        if (soDisponiveisHoje) 1,
      ].length;
}

abstract interface class RepositorioCatalogo {
  /// Só as categorias ativas.
  Future<List<CategoriaServico>> categorias();

  Future<List<Profissional>> profissionais(String categoriaId, FiltroProfissionais filtro);

  /// Profissionais e serviços que combinam com [termo].
  Future<List<Profissional>> buscar(String termo);

  /// Perfil público completo (com [Profissional.detalhe]).
  Future<Profissional> perfil(String profissionalId);

  /// Perguntas do Novo pedido para a categoria.
  Future<FormularioPedido> formulario(String categoriaId);
}

abstract interface class RepositorioServicosCliente {
  /// Serviços do cliente, do mais recente ao mais antigo.
  Future<List<ServicoRecente>> recentes();

  /// O pedido que pede atenção agora (cartão do Início); nulo se não houver.
  Future<PedidoEmAndamento?> emAndamento();

  Future<DetalheServico> detalhe(String pedidoId);
}

abstract interface class RepositorioAgenda {
  Future<List<Agendamento>> listar();
}
