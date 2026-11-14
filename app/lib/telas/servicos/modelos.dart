import '../../componentes/componentes.dart';

/// Modelos do detalhe do serviço (pedido) do cliente. Só descrevem o que é mostrado: o estado,
/// os valores e a linha do tempo vêm do backend; nenhuma conta de dinheiro roda no app.

/// Ações que o cliente pode ter em cada estado do pedido.
enum AcaoServico {
  verOrcamentos('Ver orçamentos'),
  pagar('Pagar'),
  acompanhar('Acompanhar o serviço'),
  conversar('Conversar com o profissional'),
  avaliar('Avaliar o serviço'),
  verGarantia('Ver a garantia'),
  abrirProblema('Abrir um problema');

  const AcaoServico(this.rotulo);

  final String rotulo;
}

class LinhaValor {
  const LinhaValor(this.rotulo, this.centavos, {this.destaque = false});

  final String rotulo;
  final int centavos;
  final bool destaque;
}

class ProfissionalDoServico {
  const ProfissionalDoServico({
    required this.nome,
    required this.iniciais,
    this.id,
    this.verificacao,
  });

  final String? id;
  final String nome;
  final String iniciais;
  final String? verificacao;
}

class DetalheServico {
  const DetalheServico({
    required this.pedidoId,
    required this.numero,
    required this.titulo,
    required this.estadoApi,
    required this.statusTexto,
    required this.statusTipo,
    required this.abertoEm,
    required this.etapas,
    this.profissional,
    this.valores = const [],
    this.avisoValores,
    this.descricao,
    this.remoto = false,
    this.local,
    this.codigoConclusao,
  });

  /// Código que o cliente passa ao profissional para encerrar o serviço (só em andamento).
  final String? codigoConclusao;

  /// Serviço remoto (sem endereço). Presencial é o padrão.
  final bool remoto;

  /// Endereço do serviço por extenso (presencial), ou nulo se não há.
  final String? local;

  final String pedidoId;
  final String numero;
  final String titulo;

  /// Estado do backend (`aberto`, `orcamento_aceito`, `em_andamento`, `concluido`...).
  final String estadoApi;
  final String statusTexto;
  final TipoStatus statusTipo;

  /// Texto pronto: "Aberto em 27/10".
  final String abertoEm;
  final String? descricao;
  final List<EtapaLinhaDoTempo> etapas;

  /// Ausente enquanto o pedido ainda não tem profissional contratado.
  final ProfissionalDoServico? profissional;

  /// Valores como o backend informa (em centavos). Vazio enquanto não há contratação.
  final List<LinhaValor> valores;
  final String? avisoValores;

  /// Ações possíveis por estado. O backend continua sendo quem valida cada uma.
  List<AcaoServico> get acoes => switch (estadoApi) {
        'aberto' => const [AcaoServico.verOrcamentos],
        'orcamento_aceito' => const [AcaoServico.pagar, AcaoServico.verOrcamentos],
        'pago_e_retido' || 'agendado' => const [
            AcaoServico.acompanhar,
            AcaoServico.conversar,
          ],
        'em_andamento' || 'em_confirmacao' => const [
            AcaoServico.acompanhar,
            AcaoServico.conversar,
            AcaoServico.abrirProblema,
          ],
        'concluido' => const [
            AcaoServico.avaliar,
            AcaoServico.verGarantia,
            AcaoServico.abrirProblema,
          ],
        'em_disputa' || 'retrabalho' => const [AcaoServico.conversar, AcaoServico.verGarantia],
        _ => const [],
      };
}
