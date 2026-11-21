// Modelos de orçamento. Provisórios. Valores em centavos inteiros; o app só exibe o que vier
// dos dados (total, itens, valores de cancelamento): nenhuma conta de dinheiro roda aqui.

class ItemOrcamento {
  const ItemOrcamento({
    required this.descricao,
    required this.centavos,
    this.quantidade,
    this.unitarioCentavos,
    this.porHora = false,
  });

  final String descricao;

  /// Total da linha (quantidade x valor unitário), como o backend calculou.
  final int centavos;

  /// Quantidade e valor unitário, para a tela mostrar a conta ("45 h × R\$ 15,00").
  final double? quantidade;
  final int? unitarioCentavos;

  /// Item cobrado por hora (horas trabalhadas ou deslocamento).
  final bool porHora;
}

/// Os quatro blocos de regras do detalhe: agenda, garantia, fora do escopo e cancelamento.
class DetalheOrcamento {
  const DetalheOrcamento({
    required this.validoAte,
    required this.itens,
    required this.notaMaterial,
    required this.agendaTitulo,
    required this.agendaDetalhe,
    this.totalHoras = '',
    this.horasDeslocamento = '',
    this.horasTrabalhadas = '',
    required this.garantiaTitulo,
    required this.garantiaDetalhe,
    required this.foraDoEscopo,
    required this.cancelamento,
    this.tiposDosItens = const [],
  });

  /// `tipo` de cada item do orçamento (`deslocamento`, `horas`, `material`, `outro`), como a API
  /// devolveu; é daqui que sai o "Inclui:". Vazio em servidor antigo ou dado de exemplo.
  final List<String> tiposDosItens;

  /// Ex.: "31/10" (a barra mostra "Válido até 31/10").
  final String validoAte;
  final List<ItemOrcamento> itens;

  /// Texto pronto do total de horas ("5,5 h"); vazio se o orçamento não é por hora.
  final String totalHoras;
  final String horasDeslocamento;
  final String horasTrabalhadas;
  final String notaMaterial;
  final String agendaTitulo;
  final String agendaDetalhe;
  final String garantiaTitulo;
  final String garantiaDetalhe;
  final String foraDoEscopo;
  final String cancelamento;
}

enum Ordenacao {
  menorValor('Menor valor'),
  maiorNota('Maior nota'),
  maisCedo('Mais cedo');

  const Ordenacao(this.rotulo);

  final String rotulo;
}

class Orcamento {
  const Orcamento({
    required this.id,
    required this.profissional,
    required this.iniciais,
    required this.verificacao,
    required this.totalCentavos,
    required this.nota,
    required this.notaResumo,
    required this.servicosResumo,
    required this.servicosConcluidos,
    required this.quando,
    required this.inicio,
    required this.garantia,
    required this.observacao,
    this.detalhe,
    this.aceito = false,
    this.profissionalId,
  });

  /// Id do profissional na API; com ele, o perfil público abre direto. Nulo nos dados de exemplo.
  final String? profissionalId;

  final String id;
  final String profissional;
  final String iniciais;
  final String verificacao;
  final int totalCentavos;

  /// Para ordenar por "Maior nota".
  final double nota;

  /// Textos prontos do cartão (vêm formatados do backend): "4,7 · 22 avaliações".
  final String notaResumo;
  final String servicosResumo;
  final int servicosConcluidos;

  /// "Sáb, 31/10 · 4 h".
  final String quando;

  /// Para ordenar por "Mais cedo".
  final DateTime inicio;
  final String garantia;
  final String observacao;

  /// Ausente quando o protótipo não traz a tela de detalhe desse orçamento.
  final DetalheOrcamento? detalhe;

  /// O orçamento que o cliente aceitou: é o contrato do serviço.
  final bool aceito;

  String get primeiroNome => profissional.split(' ').first;
}

/// Pedido ao qual os orçamentos pertencem (cabeçalho da lista).
class ResumoPedido {
  const ResumoPedido({
    required this.numero,
    required this.titulo,
    required this.recebidos,
    required this.limite,
    required this.tempoRestante,
  });

  final String numero;
  final String titulo;
  final int recebidos;
  final int limite;

  /// "31 horas".
  final String tempoRestante;
}

/// Rótulo de cada tipo de item, na ordem em que aparecem no "Inclui:".
const _rotuloPorTipo = {
  'deslocamento': 'Deslocamento',
  'horas': 'Mão de obra',
  'material': 'Material',
  'outro': 'Outros',
};

/// "Inclui:" do orçamento: só os tipos que existem, sempre na mesma ordem. Sem itens (ou sem
/// detalhe), "Valor combinado". Tipo que o app não conhece conta como "Outros".
String textoInclui(DetalheOrcamento? detalhe) {
  final tipos = detalhe?.tiposDosItens ?? const <String>[];
  final presentes = {
    for (final t in tipos) _rotuloPorTipo.containsKey(t) ? t : 'outro',
  };
  final rotulos = [
    for (final e in _rotuloPorTipo.entries)
      if (presentes.contains(e.key)) e.value,
  ];
  return rotulos.isEmpty ? 'Valor combinado' : rotulos.join(', ');
}

/// "Não inclui:" é o texto livre `fora_do_escopo`; vazio = "Nada informado".
String textoNaoInclui(DetalheOrcamento? detalhe) {
  final texto = (detalhe?.foraDoEscopo ?? '').trim();
  return texto.isEmpty ? 'Nada informado' : texto;
}

/// Texto quando o profissional ainda não tem nota.
const semAvaliacoes = 'Novo no Trato';

/// Linha de valor com nome e, se houver, a situação ("Aditivo · Pago").
class LinhaContrato {
  const LinhaContrato(this.rotulo, this.valor);

  final String rotulo;
  final String valor;
}

/// O que o contrato do serviço mostra além do orçamento aceito. Tudo vem do backend.
class DadosContrato {
  const DadosContrato({
    required this.numeroPedido,
    required this.titulo,
    required this.descricao,
    required this.local,
    this.cliente,
    this.contratadoEm,
    this.visita,
    this.respostas = const [],
    this.pagoCentavos,
    this.aditivos = const [],
    this.prazoRetrabalhoDias = 7,
  });

  /// "#02D8".
  final String numeroPedido;

  /// O que o cliente pediu e descreveu.
  final String titulo;
  final String descricao;

  /// Endereço por extenso, "Atendimento remoto" ou "Endereço não informado".
  final String local;
  final String? cliente;

  /// "14/11/2026" (data do aceite).
  final String? contratadoEm;

  /// "14/11 · 09:00" (visita marcada).
  final String? visita;

  /// Respostas às perguntas da categoria.
  final List<LinhaContrato> respostas;

  /// Quanto o cliente pagou (confirmado pelo parceiro). Nulo antes do pagamento.
  final int? pagoCentavos;

  /// Aditivos do contrato com a situação de cada um.
  final List<LinhaContrato> aditivos;
  final int prazoRetrabalhoDias;
}
