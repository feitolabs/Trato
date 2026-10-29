import '../../componentes/componentes.dart';

/// Modelos simples das telas de pedidos. Só descrevem o que é mostrado:
/// quem decide status, aditivo e dinheiro é o backend.

/// Formata centavos como "R$ 45,00" (só exibição, sem regra de dinheiro).
String formatarReais(int centavos) {
  final inteiro = centavos ~/ 100;
  final resto = (centavos % 100).toString().padLeft(2, '0');
  final milhares = inteiro.toString().replaceAllMapped(
        RegExp(r'(\d)(?=(\d{3})+$)'),
        (m) => '${m[1]}.',
      );
  return 'R\$ $milhares,$resto';
}

class PedidoResumo {
  const PedidoResumo({
    required this.titulo,
    required this.subtitulo,
    required this.statusTexto,
    required this.statusTipo,
  });

  final String titulo;
  final String subtitulo;
  final String statusTexto;
  final TipoStatus statusTipo;
}

enum EstadoAditivo { aguardando, aprovado, recusado }

class Aditivo {
  const Aditivo({
    required this.titulo,
    required this.valorCentavos,
    required this.descricao,
    this.estado = EstadoAditivo.aguardando,
  });

  final String titulo;
  final int valorCentavos;
  final String descricao;
  final EstadoAditivo estado;

  Aditivo comEstado(EstadoAditivo novo) => Aditivo(
      titulo: titulo,
      valorCentavos: valorCentavos,
      descricao: descricao,
      estado: novo);
}

class PedidoEmExecucao {
  const PedidoEmExecucao({
    required this.numero,
    required this.titulo,
    required this.etapas,
    required this.fotos,
    this.aditivo,
  });

  final String numero;
  final String titulo;
  final List<EtapaLinhaDoTempo> etapas;

  /// Rótulos das fotos de check-in ("[Check-in · 14h06]", "[Antes]").
  final List<String> fotos;
  final Aditivo? aditivo;
}

enum TipoMensagem { texto, foto, sistema }

class MensagemChat {
  const MensagemChat({
    required this.tipo,
    required this.hora,
    this.texto,
    this.minha = false,
    this.lida = false,
  });

  final TipoMensagem tipo;
  final String hora;

  /// Texto da mensagem; na foto, o rótulo do espaço da foto.
  final String? texto;
  final bool minha;
  final bool lida;
}

class ConversaPedido {
  const ConversaPedido({
    required this.nome,
    required this.iniciais,
    required this.numeroPedido,
    required this.situacao,
    required this.mensagens,
    required this.respostasRapidas,
  });

  final String nome;
  final String iniciais;
  final String numeroPedido;
  final String situacao;
  final List<MensagemChat> mensagens;
  final List<String> respostasRapidas;
}
