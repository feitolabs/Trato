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
    'pagamento.divergencia_conciliada' => 'conciliou uma divergência de pagamento',
    'risco.saque_travado' => com('travou os saques de'),
    'risco.saque_destravado' => com('destravou os saques de'),
    'risco.bloqueio_preventivo' => com('bloqueou preventivamente a conta de'),
    'risco.desbloqueio' => com('desbloqueou a conta de'),
    'risco.alerta_assumido' => 'assumiu um alerta de risco',
    'risco.alerta_resolvido' =>
      'resolveu um alerta de risco${d['resultado'] == null ? '' : ' (${d['resultado']})'}',
    'notificacao.campanha_disparada' => com('enviou a campanha'),
    'relatorio.exportado' => 'exportou ${_nomeRelatorio(texto(d['relatorio'] as String?))}',
    'auditoria.cadeia_verificada' => 'verificou a cadeia de hash da auditoria',
    final outro => _legivel(outro) + (nome.isEmpty ? '' : ': $nome'),
  };
}

String _nomeRelatorio(String tipo) => switch (tipo) {
      'financeiro' => 'Extrato Financeiro e Fiscal',
      'pedidos' => 'Relatório Geral de Pedidos',
      'repasses' => 'Relatório de Repasses (PIX)',
      'auditoria' => 'a trilha de auditoria',
      _ => 'um relatório',
    };

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
  ('pagamento.', 'Pagamentos'),
  ('usuario.', 'Usuários'),
  ('dado_pessoal.', 'Dados pessoais'),
  ('categoria.', 'Categorias'),
  ('cidade.', 'Cidades'),
  ('risco.', 'Risco e antifraude'),
  ('notificacao.', 'Notificações push'),
  ('cupom.', 'Cupons'),
  ('equipe.', 'Equipe'),
  ('config.', 'Configurações'),
  ('relatorio.', 'Relatórios'),
  ('auditoria.', 'Auditoria'),
];
