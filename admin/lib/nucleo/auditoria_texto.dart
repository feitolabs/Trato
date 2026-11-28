import '../dados/modelos.dart';

/// Frase legível de uma entrada da auditoria (RF-AUD-02): "aprovou o profissional Marcos Vinícius Lima"
/// em vez de `verificacao.aprovada` e UUID. O código técnico continua no detalhe expansível.
String descreverAcao(EntradaAuditoria e) {
  final nome = (e.entidadeNome ?? '').trim();
  String com(String prefixo, [String sufixo = '']) => nome.isEmpty ? prefixo.trim() : '$prefixo $nome$sufixo'.trim();
  final d = e.detalhes;
  String texto(String? v) => v ?? '';

  return switch (e.acao) {
    'verificacao.aprovada' => com('aprovou o profissional'),
    'verificacao.recusada' => com('recusou o cadastro de'),
    'dado_pessoal.revelado' => com('revelou dados pessoais de'),
    'dado_pessoal.documento_revelado' => com('abriu um documento enviado por'),
    'usuario.status_alterado' =>
      com('alterou o status de', d['status'] == null ? '' : ' para ${texto(d['status'] as String?)}'),
    'usuario.inativar' => com('inativou a conta de'),
    'usuario.reativar' => com('reativou a conta de'),
    'indisponibilidade.registrada' => 'registrou uma falha da plataforma${_origemDaFalha(d['origem'] as String?)}',
    'indisponibilidade.encerrada' => 'encerrou uma falha da plataforma${_origemDaFalha(d['origem'] as String?)}',
    'forca_maior.decidido' =>
      '${nome.isEmpty ? 'decidiu solicitação de força maior' : 'decidiu solicitação de força maior do pedido $nome'}${_decisaoForcaMaior(d['decisao'] as String?)}',
    'checkout_sem_codigo.contato_manual' =>
      '${nome.isEmpty ? 'registrou contato manual de check-out sem código' : 'registrou contato manual de check-out sem código no pedido $nome'}${_canalDoContato(d['canal'] as String?)}',
    'profissional.selo_retirado' => com('retirou o selo de verificação de'),
    'profissional.selo_reconferencia_pedida' => com('pediu nova conferência de identidade de'),
    'profissional.selo_regularizado' => com('regularizou o selo de verificação de'),
    'categoria.criada' => com('criou a categoria'),
    'categoria.editada' => com('editou a categoria'),
    'categoria.ativada' => com('ativou a categoria'),
    'categoria.desativada' => com('desativou a categoria'),
    'categoria.excluida' => com('excluiu a categoria', d['nome'] == null ? '' : ' ${d['nome']}'),
    'cidade.criada' => com('cadastrou a cidade'),
    'cidade.ativada' => com('ativou a cidade'),
    'cidade.desativada' => com('desativou a cidade'),
    'cupom.criado' => com('criou o cupom'),
    'cupom.ativado' => com('ativou o cupom'),
    'cupom.desativado' => com('desativou o cupom'),
    'cupom.excluido' => com('excluiu o cupom', d['codigo'] == null ? '' : ' ${d['codigo']}'),
    'equipe.membro_adicionado' => com('concedeu acesso a', d['email'] == null ? '' : ' (${d['email']})'),
    'equipe.membro_atualizado' => com('alterou o acesso de'),
    'equipe.acesso_revogado' => com('revogou o acesso de'),
    'equipe.login' => 'entrou no painel',
    'equipe.logout' => 'saiu do painel',
    'config.rascunho_criado' => 'preparou uma mudança em Configurações',
    'config.enviada_para_aprovacao' => 'propôs uma mudança em Configurações',
    'config.aprovada' => 'aprovou uma mudança em Configurações',
    'config.publicada' => com('publicou a versão de configuração'),
    'config.reversao_proposta' => 'propôs reverter uma versão de Configurações',
    'financeiro.disputa_decidida' => com('decidiu a disputa de'),
    'disputa.pedido_informacao_solicitado' =>
      '${nome.isEmpty ? 'pediu informação adicional na disputa' : 'pediu informação adicional na disputa do pedido $nome'}${_papelDestinatarioInfo(d['destinatario_papel'] as String?)}',
    'disputa.pedido_informacao_encerrado_sem_resposta' => nome.isEmpty
        ? 'encerrou sem resposta um pedido de informação na disputa'
        : 'encerrou sem resposta um pedido de informação no pedido $nome',
    'financeiro.checkout_sem_codigo_decidido' =>
      '${nome.isEmpty ? 'decidiu o check-out sem código' : 'decidiu o check-out sem código do pedido $nome'}${_decisaoCheckout(d['decisao'] as String?)}',
    'pagamento.divergencia_conciliada' => 'conciliou uma divergência de pagamento',
    'risco.saque_travado' => com('registrou trava de saques na conta de'),
    'risco.saque_destravado' => com('removeu a trava de saques da conta de'),
    'risco.bloqueio_preventivo' => com('bloqueou preventivamente a conta de'),
    'risco.desbloqueio' => com('desbloqueou a conta de'),
    'risco.alerta_assumido' => 'assumiu um alerta de risco',
    'risco.alerta_resolvido' =>
      'resolveu um alerta de risco${d['resultado'] == null ? '' : ' (${d['resultado']})'}',
    'notificacao.campanha_disparada' => com('enviou a campanha'),
    'relatorio.exportado' => 'exportou ${_nomeRelatorio(texto(d['relatorio'] as String?))}',
    'moedas.conceder_compensacao' => com(
      'concedeu Tratinhos como compensação para',
      d['quantidade'] == null ? '' : ' (${d['quantidade']} na carteira ${_carteiraTratinhos(d['carteira'] as String?)})',
    ),
    'moedas.cancelar_fraude' => com(
      'cancelou Tratinhos por fraude de',
      _resumoCancelamentoFraude(d),
    ),
    'auditoria.cadeia_verificada' => 'verificou a cadeia de hash da auditoria',
    final outro => _legivel(outro) + (nome.isEmpty ? '' : ': $nome'),
  };
}

String _origemDaFalha(String? origem) => switch (origem) {
      'app' => ' (aplicativo)',
      'pagamento' => ' (pagamento)',
      _ => '',
    };

String _canalDoContato(String? canal) => switch (canal) {
      'telefone' => ' (Telefone)',
      'whatsapp' => ' (WhatsApp)',
      'email' => ' (E-mail)',
      'outro' => ' (Outro)',
      final c? when c.trim().isNotEmpty => ' ($c)',
      _ => '',
    };

String _decisaoCheckout(String? decisao) => switch (decisao) {
      'liberar' => ' (Liberar pagamento)',
      'estornar' => ' (Estornar ao cliente)',
      final v? when v.trim().isNotEmpty => ' ($v)',
      _ => '',
    };

String _papelDestinatarioInfo(String? papel) => switch (papel) {
      'cliente' => ' (Cliente)',
      'profissional' => ' (Profissional)',
      final v? when v.trim().isNotEmpty => ' ($v)',
      _ => '',
    };

String _decisaoForcaMaior(String? decisao) => switch (decisao) {
      'aprovado' => ' (Aprovado)',
      'recusado' => ' (Recusado)',
      final v? when v.trim().isNotEmpty => ' ($v)',
      _ => '',
    };

String _nomeRelatorio(String tipo) => switch (tipo) {
      'financeiro' => 'Extrato Financeiro e Fiscal',
      'pedidos' => 'Relatório Geral de Pedidos',
      'repasses' => 'Relatório de Repasses (PIX)',
      'auditoria' => 'a trilha de auditoria',
      _ => 'um relatório',
    };

String _carteiraTratinhos(String? carteira) => carteira == 'profissional' ? 'profissional' : 'cliente';

String _resumoCancelamentoFraude(Map<String, dynamic> d) {
  final partes = <String>[];
  final deb = d['quantidade_debitada'];
  if (deb is int && deb > 0) partes.add('$deb debitado(s)');
  final pend = d['pendentes_cancelados'];
  if (pend is int && pend > 0) partes.add('$pend pendente(s) cancelado(s)');
  if (partes.isEmpty) return '';
  final carteira = d['carteira'] as String?;
  final onde = carteira == null ? '' : ' na carteira ${_carteiraTratinhos(carteira)}';
  return ' (${partes.join(', ')}$onde)';
}

/// `algo.feito_aqui` -> "algo feito aqui" (último recurso, para uma ação que a tela ainda não conhece).
String _legivel(String acao) => acao.replaceAll('.', ' ').replaceAll('_', ' ');

/// Quem agiu, em texto: o nome; sem nome, "Sistema" ou o e-mail.
String descreverAtor(EntradaAuditoria e) {
  final n = e.atorNome?.trim();
  if (n != null && n.isNotEmpty) return n;
  return e.ator.contains('@') ? e.ator : 'Sistema';
}

/// O que cada filtro "Ação" casa: prefixo do código técnico.
const filtrosDeAcao = <(String, String)>[
  ('verificacao.', 'Verificação'),
  ('financeiro.', 'Disputas'),
  ('disputa.', 'Pedidos de informação'),
  ('pagamento.', 'Pagamentos'),
  ('usuario.', 'Usuários'),
  ('dado_pessoal.', 'Dados pessoais'),
  ('categoria.', 'Categorias'),
  ('cidade.', 'Cidades'),
  ('risco.', 'Risco e antifraude'),
  ('notificacao.', 'Notificações push'),
  ('cupom.', 'Cupons'),
  ('moedas.', 'Tratinhos'),
  ('profissional.selo', 'Selo do profissional'),
  ('indisponibilidade.', 'Falhas da plataforma'),
  ('forca_maior.', 'Força maior'),
  ('checkout_sem_codigo.', 'Check-out sem código'),
  ('equipe.', 'Equipe'),
  ('config.', 'Configurações'),
  ('relatorio.', 'Relatórios'),
  ('auditoria.', 'Auditoria'),
];
