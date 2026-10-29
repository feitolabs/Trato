import 'package:flutter/widgets.dart';

/// Modelos simples das telas do cliente. Provisórios: o formato real vem do backend.

String formatarNota(double nota) => nota.toStringAsFixed(1).replaceAll('.', ',');

String formatarDistancia(double km) => '${km.toStringAsFixed(1).replaceAll('.', ',')} km';

class Avaliacao {
  const Avaliacao({
    required this.cliente,
    required this.servico,
    required this.nota,
    required this.comentario,
    required this.detalhes,
  });

  final String cliente;
  final String servico;
  final double nota;
  final String comentario;

  /// Ex.: "Pontualidade 5 · Qualidade 5 · Limpeza 5".
  final String detalhes;
}

/// Dados que só aparecem na tela do perfil do profissional.
class DetalhePerfil {
  const DetalhePerfil({
    required this.noTratoDesde,
    required this.totalAvaliacoes,
    required this.taxaConclusao,
    required this.respondeEm,
    required this.verificacoes,
    required this.avaliacoes,
    this.fotosTrabalhos = 3,
  });

  final int noTratoDesde;
  final int totalAvaliacoes;
  final int taxaConclusao;
  final String respondeEm;
  final List<String> verificacoes;
  final List<Avaliacao> avaliacoes;
  final int fotosTrabalhos;
}

class Profissional {
  const Profissional({
    required this.nome,
    required this.iniciais,
    required this.verificacao,
    required this.especialidade,
    required this.servicosConcluidos,
    required this.nota,
    required this.distanciaKm,
    this.respostaCurta,
    this.atendeHoje = false,
    this.detalhe,
  });

  final String nome;
  final String iniciais;

  /// "Verificado" ou "Verificado Plus".
  final String verificacao;
  final String especialidade;
  final int servicosConcluidos;
  final double nota;
  final double distanciaKm;

  /// Ex.: "resp. em 1 h". Ausente quando o protótipo não mostra.
  final String? respostaCurta;
  final bool atendeHoje;
  final DetalhePerfil? detalhe;

  String get primeiroNome => nome.split(' ').first;
}

class CategoriaServico {
  const CategoriaServico(this.nome, this.icone);

  final String nome;
  final IconData icone;
}

class PedidoEmAndamento {
  const PedidoEmAndamento({
    required this.titulo,
    required this.situacao,
    required this.aviso,
  });

  final String titulo;
  final String situacao;
  final String aviso;
}

class ServicoRecente {
  const ServicoRecente({
    required this.titulo,
    required this.profissional,
    required this.data,
    required this.garantia,
  });

  final String titulo;
  final String profissional;
  final String data;
  final String garantia;
}
