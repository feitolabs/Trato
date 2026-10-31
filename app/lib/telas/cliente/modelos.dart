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
    this.bio,
    this.servicos = const [],
    this.trabalhos = const [],
  });

  /// Texto de apresentação escrito pelo profissional (já filtrado pelo backend).
  final String? bio;

  /// Serviços que o profissional oferece.
  final List<String> servicos;

  /// Legendas dos trabalhos do portfólio (as fotos vêm da URL assinada quando houver).
  final List<String> trabalhos;

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
    this.id,
    this.regiao,
    this.categoriaId,
    this.precoAPartirCentavos,
  });

  /// Id do profissional na API (nulo nos dados do protótipo).
  final String? id;

  /// Bairro ou região de atendimento, ex.: "Savassi e Funcionários".
  final String? regiao;
  final String? categoriaId;

  /// Referência de preço mostrada na lista; o valor do serviço é o do orçamento.
  final int? precoAPartirCentavos;

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
  const CategoriaServico(
    this.nome,
    this.icone, {
    this.id = '',
    this.servicos = const [],
    this.descricao = '',
  });

  /// Id da categoria no catálogo (vazio nos dados do protótipo).
  final String id;
  final String nome;
  final IconData icone;

  /// Serviços típicos da categoria, usados no Novo pedido.
  final List<String> servicos;
  final String descricao;
}

class PedidoEmAndamento {
  const PedidoEmAndamento({
    required this.titulo,
    required this.situacao,
    required this.aviso,
    this.pedidoId,
  });

  /// Id do pedido na API (nulo nos dados do protótipo).
  final String? pedidoId;

  final String titulo;
  final String situacao;
  final String aviso;
}

class ServicoRecente {
  const ServicoRecente({
    required this.titulo,
    required this.profissional,
    required this.data,
    this.garantia,
    this.pedidoId,
    this.statusTexto = 'Finalizado',
  });

  /// Situação do serviço mostrada no chip ("Finalizado", "Em execução"...).
  final String statusTexto;

  /// Id do pedido na API (nulo nos dados do protótipo).
  final String? pedidoId;

  final String titulo;
  final String profissional;
  final String data;

  /// Texto pronto da garantia; ausente quando o backend não informa.
  final String? garantia;
}

/// Tudo o que o Início do cliente mostra, já carregado do catálogo e dos pedidos.
class DadosInicio {
  const DadosInicio({
    required this.nome,
    required this.categorias,
    this.emAndamento,
    this.recentes = const [],
  });

  /// Primeiro nome do cliente.
  final String nome;

  /// Categorias ativas (a tela mostra as primeiras e o atalho "Ver todas").
  final List<CategoriaServico> categorias;
  final PedidoEmAndamento? emAndamento;
  final List<ServicoRecente> recentes;
}
