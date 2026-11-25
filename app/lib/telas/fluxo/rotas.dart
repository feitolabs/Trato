import 'dart:async';
import 'dart:io' show Directory, File, Platform;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../agenda/modelos.dart' show EstadoAgendamento;
import '../../componentes/componentes.dart';
import '../../dados/carregador.dart';
import '../auth/criar_conta_tela.dart';
import '../pedido_novo/modelos.dart' show RascunhoPedido;
import '../../dados/erros.dart';
import '../../dados/config_publica.dart';
import '../../dados/relogio_de_atualizacao.dart';
import '../../dispositivo/mapa.dart';
import '../../dispositivo/servico_push.dart';
import '../../dispositivo/servico_push_firebase.dart';
import '../../dados/repositorios.dart';
import '../../dispositivo/folha_cartao.dart';
import '../orcamentos/folha_contraproposta.dart';
import '../../auth/servico_auth.dart';
import '../../dados/repositorios_trato.dart';
import '../../dados/sessao.dart';
import '../auth/login_tela.dart';
import '../onboarding/escolha_perfil_tela.dart' show PerfilUso;
import '../onboarding/tour_perfil_tela.dart';
import '../../tema/tema.dart';
import '../../dispositivo/check_in_dispositivo.dart';
import '../../dispositivo/dispositivo.dart';
import '../../dispositivo/permissao.dart';
import '../aditivo/aditivo.dart';
import '../aditivo/criar_aditivo_tela.dart';
import '../aditivo/responder_aditivo_tela.dart';
import '../busca/busca_profissionais_tela.dart';
import '../busca/modelos.dart';
import '../../dados/repositorios_catalogo.dart';
import '../agenda/agenda_tela.dart';
import '../catalogo/avaliacoes_profissional_tela.dart';
import '../catalogo/categoria_tela.dart';
import '../catalogo/todas_categorias_tela.dart';
import '../cliente/inicio_tela.dart';
import '../cliente/modelos.dart' show CategoriaServico, DadosInicio, Profissional;
import '../legal/texto_legal_tela.dart';
import '../mensagens/modelos.dart' show ConversaResumo, ServicoMensagens;
import '../mensagens/servico_conversas.dart' show ServicoConversasApi;
import '../mensagens/servico_estado.dart';
import '../mensagens/servico_pedidos.dart';
import '../orcamentos/modelos.dart' show DadosContrato, Orcamento;
import '../pedido_novo/modelos.dart' show FormularioPedido;
import '../servicos/servicos_recentes_tela.dart';
import '../cliente/perfil_profissional_tela.dart';
import '../disputa_profissional/atender_retrabalho_tela.dart';
import '../disputa_profissional/disputa.dart';
import '../disputa_profissional/responder_disputa_tela.dart';
import '../nota_material/enviar_nota_tela.dart';
import '../nota_material/nota_material.dart';
import '../nota_material/ver_nota_tela.dart';
import '../ajuda/ajuda_tela.dart';
import '../ajuda/servico_ajuda_local.dart';
import '../comuns/botao_de_confianca.dart';
import '../comuns/convite.dart';
import '../comuns/denuncia_folha.dart';
import '../indicacoes/indique_e_ganhe_tela.dart';
import '../indicacoes/modelos.dart';
import '../indicacoes/servico_fake.dart';
import '../recorrencias/modelos.dart';
import '../recorrencias/repetir_servico_folha.dart';
import '../recorrencias/servico_fake.dart';
import '../recorrencias/servicos_recorrentes_tela.dart';
import '../comuns/desconto_moedas.dart' show textoTratinhosPendentes;
import '../comuns/foco_rolagem.dart';
import '../comuns/moedas_ganhas_tela.dart';
import '../comuns/sucesso_acao_tela.dart';
import '../conta/dados_pessoais_tela.dart';
import '../comuns/relatar_bug.dart';
import '../conta/enderecos_tela.dart';
import '../conta/favoritos_contatos_telas.dart';
import '../conta/modelos.dart';
import '../conta/seguranca_conta_tela.dart';
import 'navegacao_casca.dart';
import '../../dados/modelos_api.dart' show PedidoApi;
import '../../dispositivo/abrir_email.dart';
import '../conta/servico_fake.dart';
import '../lgpd/central_privacidade_tela.dart';
import '../lgpd/modelos.dart' show CancelamentoExclusao;
import '../mensagens/mensagens_tela.dart';
import '../perfil_publico/avaliacoes_recebidas_tela.dart';
import '../perfil_publico/perfil_publico_tela.dart';
import 'deep_link.dart';
import 'deep_link_modelo.dart';
import '../profissional_mei/mei.dart';
import '../profissional_mei/meu_cnpj_tela.dart';
import '../profissional_cadastro/cadastro.dart';
import '../profissional_cadastro/cadastro_profissional_tela.dart';
import '../verificacao/verificacao.dart'
    show ServicoVerificacao, SituacaoVerificacao, StatusVerificacao;
import '../verificacao/verificacao_tela.dart';
import '../carteira/carteira_tela.dart';
import '../carteira/conta_recebimento_tela.dart';
import '../carteira/modelos.dart';
import '../cliente/casca_cliente_tela.dart';
import '../carteira/avaliar_cliente_tela.dart';
import '../configuracoes/configuracoes_tela.dart';
import '../carteira/detalhe_valores_tela.dart';
import '../conclusao/avaliacao_tela.dart';
import '../conclusao/conclusao_tela.dart';
import '../conclusao/modelos.dart';
import '../conclusao/garantia_tela.dart';
import '../conclusao/relatar_problema_tela.dart';
import '../notificacoes/modelos.dart';
import '../notificacoes/modelos.dart' as notif;
import '../profissional_inicio/detalhe_pedido_tela.dart';
import '../notificacoes/notificacoes_tela.dart';
import '../notificacoes/preferencias_notificacoes_tela.dart';
import '../notificacoes/servico_repositorio.dart';
import '../orcamentos/detalhe_orcamento_tela.dart';
import '../orcamentos/orcamentos_recebidos_tela.dart';
import '../pagamento/aguardando_pagamento_tela.dart';
import '../pagamento/modelos.dart';
import '../pagamento/pagamento_tela.dart';
import '../pedido_novo/novo_pedido_tela.dart';
import '../perfil_cliente/modelos.dart';
import '../perfil_cliente/perfil_cliente_tela.dart';
import '../pedidos/chat_pedido_tela.dart';
import '../pedidos/modelos.dart';
import '../pedidos/pedido_aberto_tela.dart';
import '../pedidos/atendimento.dart';
import '../pedidos/pedido_execucao_tela.dart';
import '../pedidos/reagendamento.dart';
import '../pedidos/seus_pedidos_tela.dart';
import '../profissional/calculadora_orcamento_tela.dart';
import '../profissional/dinheiro.dart';
import '../profissional/check_in_tela.dart';
import '../profissional/check_out_tela.dart';
import '../profissional/detalhe_orcamento_enviado_tela.dart';
import '../profissional/servico_check_in.dart';
import '../profissional_inicio/casca_profissional_tela.dart';
import '../profissional_inicio/modelos.dart';
import '../../dados/paralelo.dart';

/// Liga as telas entre si e aos dados. As telas não se conhecem e não conhecem a rede: quem
/// sabe para onde cada botão vai, e de onde vêm os dados, é este arquivo. Os repositórios
/// (API ou demonstração) vêm de [repos], configurado no `main.dart`.
abstract final class RotasTrato {
  /// Repositórios da API. O `main.dart` liga na abertura do app.
  static late RepositoriosTrato repos;

  /// Folha de cartão do provedor. O `main` liga a real; nos testes não abre nada.
  static FolhaCartao folhaCartao = FolhaCartaoFake();

  @visibleForTesting
  static Future<String> Function(List<int> bytes, String arquivo)? salvarPdfParaTeste;

  /// Compartilhamento do arquivo salvo (os testes trocam pelo falso).
  @visibleForTesting
  static CompartilharArquivo compartilharArquivo = compartilharArquivoNoAparelho;

  /// Canal nativo de push (FCM / APNs). Nos testes fica falso/silencioso.
  static ServicoPush push = ServicoPushFirebase();
  static StreamSubscription<TokenPushDispositivo>? _subPush;

  /// Registra o token de push do aparelho no backend após autenticar.
  static Future<void> sincronizarPush() async {
    if (!repos.modoApi || !temSessao) return;
    _subPush ??= push.aoAtualizarToken.listen((t) {
      if (!repos.modoApi || !temSessao) return;
      push.ultimoTokenRegistrado = t.token;
      repos.notificacoes.registrarDispositivo(t.token, t.plataforma).catchError((_) {});
    });
    try {
      final atual = await push.obterToken();
      if (atual != null) {
        push.ultimoTokenRegistrado = atual.token;
        await repos.notificacoes.registrarDispositivo(atual.token, atual.plataforma);
      }
    } on Object {
      // Sem push nativo configurado (ex.: navegador/desktop/teste): segue normalmente.
    }
  }

  /// Limpa a inscrição de atualização de token entre testes.
  @visibleForTesting
  static Future<void> resetarPushParaTeste() async {
    await _subPush?.cancel();
    _subPush = null;
  }

  /// Permissões de câmera e GPS (usadas no check-in e check-out).
  static ServicoPermissao permissao = const ServicoPermissaoReal();

  /// Contadores de não lidas exibidos nos badges das abas e do sino.
  static final ValueNotifier<int> mensagensNaoLidas = ValueNotifier<int>(0);
  static final ValueNotifier<int> notificacoesNaoLidas = ValueNotifier<int>(0);

  static Future<int> _contarNotificacoesNaoLidas() async {
    try {
      final lista = await repos.notificacoes.listar();
      final total = lista.where((n) => !n.lida).length;
      notificacoesNaoLidas.value = total;
      return total;
    } on Object {
      return notificacoesNaoLidas.value;
    }
  }

  static void _atualizarMensagensNaoLidasEmSegundoPlano({
    required bool profissional,
  }) {
    final servico = profissional
        ? (repos.mensagensProfissional ??
            ServicoMensagensDoProfissional(repos.profissional, chat: repos.chat))
        : _servicoMensagens;
    unawaited(() async {
      try {
        final lista = await servico.listar();
        mensagensNaoLidas.value = lista.fold<int>(0, (soma, item) => soma + item.naoLidas);
      } on Object {
        // Atualização de badge em segundo plano não bloqueia a tela.
      }
    }());
  }

  /// Câmera, GPS e envio de arquivos. O `main.dart` liga o real.
  static late DispositivoTrato dispositivo;

  /// Rascunho preenchido antes do login/cadastro, concluído logo após autenticar.
  static RascunhoPedido? rascunhoPendente;

  /// Verdadeiro quando o usuário pulou o onboarding sem entrar, ou em modo API sem sessão.
  static bool modoVisitante = false;

  static bool get emModoVisitante => modoVisitante || (repos.modoApi && !temSessao);

  /// Nota de materiais, aditivo e disputa vêm sempre da API (`repos`).
  static ServicoNotaMaterial get servicoNota => repos.notaMaterial!;
  static ServicoAditivo get servicoAditivo => repos.aditivo!;
  static ServicoDisputaProfissional get servicoDisputa => repos.disputaProfissional!;

  /// Busca por texto: pede ao catálogo (modo `api`: demonstração até a rota de busca existir).
  static ServicoBusca get servicoBusca => _ServicoBuscaCatalogo(repos.catalogo);

  /// Lista de conversas da aba Mensagens. No modo `api` vem de `GET /v1/conversas` (todas as
  /// conversas, antes e depois de contratar); na demonstração, a lista montada dos pedidos.
  static ServicoMensagens get _servicoMensagens =>
      repos.mensagens ?? ServicoMensagensDosPedidos(repos.pedidos, chat: repos.chat);

  /// Intervalo da atualização automática das telas. Só no modo `api` (na demonstração e nos
  /// testes os dados não mudam sozinhos e não há por que manter relógios ligados).
  static Duration? get _intervalo => repos.modoApi ? RelogioDeAtualizacao.intervaloPadrao : null;

  /// Sessão do cliente HTTP, para o "Sair" limpar o token. O `main.dart` liga.
  static SessaoTrato? sessao;

  /// Há login guardado (a splash pula o onboarding)?
  static bool get temSessao => ServicoAuthPadrao.atual.sessaoAtual != null;

  /// Sem id de pedido (não deveria acontecer com dado da API): a chamada falha com erro claro.
  static const _semId = '';

  /// Avisa a lista de pedidos que ela precisa recarregar (criou pedido, mexeu num pedido).
  static final ValueNotifier<int> pedidosMudaram = ValueNotifier<int>(0);

  static Future<T?> _abrir<T>(BuildContext context, Widget tela) => Navigator.of(context)
      .push(MaterialPageRoute<T>(builder: (_) => tela))
      .whenComplete(() => pedidosMudaram.value++);

  static void _voltarAoInicio(
    BuildContext context, {
    int aba = 0,
    NavigatorState? nav,
  }) {
    final navigator = nav ?? Navigator.maybeOf(context);
    navigator?.popUntil((rota) => rota.isFirst);
    ControladorCasca.selecionarAba(aba);
    pedidosMudaram.value++;
  }

  static Future<T?> _abrirSucesso<T>(
    BuildContext context,
    Widget Function(BuildContext ctxSucesso) construtor, {
    bool substituirAtual = false,
  }) {
    final nav = Navigator.of(context);
    final rota = MaterialPageRoute<T>(
      builder: (ctxSucesso) => construtor(ctxSucesso),
    );
    return (substituirAtual ? nav.pushReplacement<T, void>(rota) : nav.push<T>(rota))
        .whenComplete(() => pedidosMudaram.value++);
  }

  static void _aviso(BuildContext context, Object erro) {
    final texto = erro is ErroTrato
        // Ação que precisa do servidor (pagar, cancelar, aceitar...): sem internet, aviso humano.
        ? (erro.tipo == TipoErro.semInternet ? avisoAcaoSemInternet : erro.mensagem)
        : erro is ErroFolhaCartao
            ? erro.mensagem
            : 'Algo deu errado. Tente de novo.';
    _mostrarToast(context, texto, icone: Icons.error_outline);
  }

  /// Aviso de ação que só funciona com internet (pagamento, cancelamento, aceite de orçamento).
  static const avisoAcaoSemInternet = 'Sem internet. Conecte-se para concluir esta ação.';

  static void _avisoSimples(BuildContext context, String texto) {
    _mostrarToast(context, texto, icone: Icons.info_outline);
  }

  static void _mostrarToast(
    BuildContext context,
    String texto, {
    required IconData icone,
  }) {
    final cor = Theme.of(context).snackBarTheme.closeIconColor ?? CoresTrato.toastTexto;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Row(
            children: [
              Icon(icone, size: 20, color: cor),
              const SizedBox(width: EspacosTrato.x3),
              Expanded(child: Text(texto)),
            ],
          ),
        ),
      );
  }

  /// Faz uma chamada e, se der erro, avisa em português simples. Devolve se deu certo.
  static Future<bool> _tentar(BuildContext context, Future<void> Function() acao) async {
    try {
      await acao();
      return true;
    } on Object catch (erro) {
      if (context.mounted) _aviso(context, erro);
      return false;
    }
  }

  /// Depois do login ou do cadastro de cliente: casca do cliente, sem voltar às telas de acesso.
  static void irParaCliente(BuildContext context) {
    final pendente = rascunhoPendente;
    if (pendente != null) {
      rascunhoPendente = null;
      unawaited(_enviarRascunhoPendente(context, pendente));
      return;
    }
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute<void>(builder: (_) => const CascaClienteTela()),
      (rota) => false,
    );
  }

  static Future<void> _enviarRascunhoPendente(
    BuildContext context,
    RascunhoPedido rascunho,
  ) async {
    try {
      await repos.pedidos.criar(rascunho);
      pedidosMudaram.value++;
      if (!context.mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute<void>(
          builder: (ctxSucesso) => SucessoAcaoTela(
            titulo: 'Pedido enviado!',
            subtitulo:
                'Os profissionais de ${rascunho.modalidade.name == 'remoto' ? 'qualquer região' : 'sua região'} foram notificados e você já pode acompanhar os orçamentos.',
            textoBotaoPrimario: 'Ver pedidos',
            aoTocarPrimario: () => Navigator.of(ctxSucesso).pushAndRemoveUntil(
              MaterialPageRoute<void>(builder: (_) => const CascaClienteTela(abaInicial: 2)),
              (rota) => false,
            ),
            textoBotaoSecundario: 'Voltar ao início',
            aoVoltarInicio: () => Navigator.of(ctxSucesso).pushAndRemoveUntil(
              MaterialPageRoute<void>(builder: (_) => const CascaClienteTela()),
              (rota) => false,
            ),
          ),
        ),
        (rota) => false,
      );
    } on Object catch (erro) {
      if (!context.mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute<void>(builder: (_) => const CascaClienteTela()),
        (rota) => false,
      );
      _aviso(context, erro);
    }
  }

  /// Depois do cadastro (com sessão aberta): cliente vai à casca; profissional ao cadastro dele.
  static void irParaDepoisDoCadastro(BuildContext context, PerfilUso perfil) {
    modoVisitante = false;
    if (perfil == PerfilUso.cliente) {
      irParaCliente(context);
    } else {
      irParaProfissional(context);
    }
  }

  /// Entra na casca certa para o perfil do usuário: profissional ou cliente (padrão).
  static void irParaInicio(BuildContext context, [SessaoAuth? quem]) {
    modoVisitante = false;
    final s = quem ?? ServicoAuthPadrao.atual.sessaoAtual;
    if (s != null && s.ehProfissional) {
      if (repos.modoApi) {
        unawaited(irParaProfissional(context));
      } else {
        _entrarNaCascaProfissional(context);
      }
    } else {
      irParaCliente(context);
    }
  }

  /// Sair da conta: remove o token de push, encerra o login, limpa o token e volta ao login.
  static Future<void> sair(BuildContext context) async {
    final navegador = Navigator.of(context);
    final tokenPush = push.ultimoTokenRegistrado;
    if (tokenPush != null && repos.modoApi && temSessao) {
      try {
        await repos.notificacoes.removerDispositivo(tokenPush);
      } on Object {
        // Sem rede ou já expirado: segue com o logout local.
      }
      push.ultimoTokenRegistrado = null;
    }
    try {
      await ServicoAuthPadrao.atual.sair();
    } on Object {
      // Mesmo sem rede, o token local é descartado abaixo.
    }
    PerfilClienteTela.limparFotoSessao();
    PerfilPublicoTela.limparFotoSessao();
    await sessao?.sair(); // espera apagar o cache de leitura antes de voltar ao login
    DeepLinks.esquecer(); // um link guardado é de quem saiu: não abre para a próxima pessoa
    navegador.pushAndRemoveUntil(
      MaterialPageRoute<void>(builder: (_) => const LoginTela()),
      (rota) => false,
    );
  }

  /// Perfil público de quem enviou o orçamento. Com o id do profissional (API), abre direto;
  /// sem ele, procura pelo nome no catálogo.
  static Future<void> abrirPerfilDoOrcamento(BuildContext context, Orcamento o) async {
    if (o.profissionalId != null) {
      abrirPerfil(
        context,
        Profissional(
          id: o.profissionalId,
          nome: o.profissional,
          iniciais: o.iniciais,
          verificacao: o.verificacao,
          especialidade: '',
          servicosConcluidos: o.servicosConcluidos,
          nota: o.nota,
          distanciaKm: 0,
        ),
      );
      return;
    }
    await abrirPerfilProfissional(context, o.profissional);
  }

  /// Procura o profissional pelo nome no catálogo; sem perfil, avisa em vez de abrir tela vazia.
  static Future<void> abrirPerfilProfissional(BuildContext context, String nome) async {
    var achados = <Profissional>[];
    final ok = await _tentar(context, () async => achados = await repos.catalogo.buscar(nome));
    if (!ok) return;
    final p = achados.where((x) => x.nome == nome).firstOrNull;
    if (p == null) {
      if (context.mounted) _avisoSimples(context, _perfilIndisponivel);
      return;
    }
    if (context.mounted) abrirPerfil(context, p);
  }

  /// Perfil público de [p] (da busca, da categoria, do orçamento ou do serviço). Sem os dados
  /// completos, busca pelo id no catálogo.
  static void abrirPerfil(BuildContext context, Profissional p) => _abrir<void>(
        context,
        Carregador<Profissional>(
          textoNaoEncontrado: TextosNaoEncontrado.perfil,
          carregar: () async =>
              p.detalhe != null || p.id == null ? p : await repos.catalogo.perfil(p.id!),
          vazio: (perfil) => perfil.detalhe == null,
          tituloVazio: 'Perfil indisponível',
          textoVazio: 'Este perfil ainda não tem as informações completas.',
          construir: (context, perfil) {
            final meuId = ServicoAuthPadrao.atual.sessaoAtual?.id;
            final ehProprio = meuId != null && perfil.id == meuId;
            return PerfilProfissionalTela(
              profissional: perfil,
              aoPedirOrcamento: ehProprio ? null : (x) => _pedirOrcamentoA(context, x),
              aoVerAvaliacoes: (x) => _abrir<void>(
                context,
                AvaliacoesProfissionalTela(profissional: x),
              ),
              favoritoAtual: perfil.id == null || ehProprio
                  ? null
                  : () async =>
                      (await _conta.favoritos()).any((f) => f.profissionalId == perfil.id),
              aoMudarFavorito: perfil.id == null || ehProprio
                  ? null
                  : (v) => v ? _conta.favoritar(perfil.id!) : _conta.desfavoritar(perfil.id!),
              aoDenunciar: perfil.id == null || ehProprio
                  ? null
                  : () => denunciar(context, alvoTipo: 'perfil', denunciadoId: perfil.id!),
            );
          },
        ),
      );

  /// "Pedir orçamento" no perfil: abre o Novo pedido na categoria do profissional (direcionado a ele).
  static Future<void> _pedirOrcamentoA(BuildContext context, Profissional p) async {
    CategoriaServico? categoria;
    final ok = await _tentar(context, () async {
      final todas = await repos.catalogo.categorias();
      if (p.categoriaId != null) {
        categoria = todas.where((c) => c.id == p.categoriaId).firstOrNull;
      }
      if (categoria == null && p.especialidade.trim().isNotEmpty) {
        final esp = p.especialidade.toLowerCase();
        categoria = todas.where((c) => esp.contains(c.nome.toLowerCase())).firstOrNull;
      }
    });
    if (!ok || !context.mounted) return;
    abrirNovoPedido(
      context,
      categoria: categoria,
      profissionalConvidado: p,
    );
  }

  // --- Cliente: catálogo, serviços, notificações, termos ------------------------------

  /// Novo pedido. Sem [categoria], o cliente escolhe uma antes (passo 1).
  static void abrirNovoPedido(
    BuildContext context, {
    CategoriaServico? categoria,
    Profissional? profissionalConvidado,
    List<CategoriaServico>? categoriasPermitidas,
  }) =>
      _abrir<void>(
        context,
        categoria == null
            ? _escolherCategoria(
                profissionalConvidado: profissionalConvidado,
                categoriasPermitidas: categoriasPermitidas,
              )
            : _novoPedido(categoria, profissionalConvidado: profissionalConvidado),
      );

  /// "Chamar de novo": o pedido vai para este profissional, só nas categorias em que ele atua.
  /// Com uma só, abre direto; sem a informação da API (servidor antigo), mostra todas.
  static Future<void> chamarDeNovo(BuildContext context, FavoritoConta f) async {
    final convidado = Profissional(
      id: f.profissionalId,
      nome: f.nome ?? 'Profissional',
      iniciais: (f.nome ?? 'P').substring(0, 1).toUpperCase(),
      verificacao: '',
      especialidade: '',
      servicosConcluidos: f.servicos ?? 0,
      nota: f.nota ?? 0,
      distanciaKm: 0,
    );
    List<CategoriaServico>? dele;
    final ok = await _tentar(context, () async {
      final todas = await repos.catalogo.categorias();
      final perfil = await repos.catalogo.perfil(f.profissionalId);
      final ids = perfil.categoriasIds.toSet();
      final filtradas = todas.where((c) => ids.contains(c.id)).toList();
      dele = filtradas.isEmpty ? null : filtradas;
    });
    if (!ok || !context.mounted) return;
    final lista = dele;
    if (lista != null && lista.length == 1) {
      abrirNovoPedido(context, categoria: lista.first, profissionalConvidado: convidado);
    } else {
      abrirNovoPedido(context, profissionalConvidado: convidado, categoriasPermitidas: lista);
    }
  }

  static Widget _escolherCategoria({
    Profissional? profissionalConvidado,
    List<CategoriaServico>? categoriasPermitidas,
  }) =>
      Builder(
        builder: (context) => TodasCategoriasTela(
          titulo: 'Que serviço você precisa?',
          carregar: categoriasPermitidas == null
              ? repos.catalogo.categorias
              : () async => categoriasPermitidas,
          aoEscolher: (c) => Navigator.of(context).pushReplacement(
            MaterialPageRoute<void>(
              builder: (_) => _novoPedido(
                c,
                profissionalConvidado: profissionalConvidado,
              ),
            ),
          ),
        ),
      );

  static void abrirTodasCategorias(BuildContext context) => _abrir<void>(
        context,
        Builder(
          builder: (context) => TodasCategoriasTela(
            carregar: repos.catalogo.categorias,
            aoEscolher: (c) => abrirCategoria(context, c),
          ),
        ),
      );

  static void abrirCategoria(BuildContext context, CategoriaServico categoria) => _abrir<void>(
        context,
        Builder(
          builder: (context) => CategoriaTela(
            categoria: categoria,
            carregar: (filtro) => repos.catalogo.profissionais(categoria.id, filtro),
            aoAbrirProfissional: (p) => abrirPerfil(context, p),
            aoPedirOrcamento: (_) => abrirNovoPedido(context, categoria: categoria),
          ),
        ),
      );

  static void abrirServicos(BuildContext context) => _abrir<void>(
        context,
        Builder(
          builder: (context) => ServicosRecentesTela(
            carregar: repos.servicos.recentes,
            aoAbrir: (s) => abrirServico(context, s.pedidoId ?? _semId),
          ),
        ),
      );

  /// Acompanhamento do pedido: a MESMA tela para quem vem da lista e da notificação.
  static void abrirServico(BuildContext context, String pedidoId) =>
      _abrir<void>(context, _pedidoEmExecucao(pedidoId));

  /// Denuncia um perfil (`alvoTipo: 'perfil'`) ou a conversa de um pedido (`'chat'`, com [pedidoId]):
  /// abre a folha de motivo + detalhes e envia (`POST /v1/denuncias`). Avisa ao concluir.
  static Future<void> denunciar(
    BuildContext context, {
    required String alvoTipo,
    required String denunciadoId,
    String? pedidoId,
  }) async {
    final enviou = await mostrarFolhaDenuncia(
      context,
      enviar: (motivo, detalhes) => _conta.enviarDenuncia(
        alvoTipo: alvoTipo,
        denunciadoId: denunciadoId,
        pedidoId: pedidoId,
        motivo: motivo.codigo,
        detalhes: detalhes,
      ),
    );
    if (enviou == true && context.mounted) _avisoSimples(context, avisoDenunciaEnviada);
  }

  /// Pede o motivo, confirma e cancela. Quem decide se pode e cuida de eventuais devoluções é
  /// o atendimento e processamento do app; em caso de recusa, a pessoa vê o motivo.
  static Future<void> _cancelarPedido(BuildContext context, String pedidoId) async {
    final motivo = await showDialog<String>(
      context: context,
      builder: (_) => const _DialogoCancelarPedido(),
    );
    if (motivo == null || motivo.isEmpty || !context.mounted) return;
    final ok = await _tentar(context, () => repos.pedidos.cancelar(pedidoId, motivo));
    if (!ok || !context.mounted) return;
    pedidosMudaram.value++;
    await _abrirSucesso<void>(
      context,
      (ctxSucesso) => SucessoAcaoTela(
        titulo: 'Pedido cancelado',
        subtitulo:
            'O cancelamento foi registrado. Se houve pagamento, o estorno segue automaticamente.',
        aoVoltarInicio: () => _voltarAoInicio(ctxSucesso),
      ),
      substituirAtual: Navigator.of(context).canPop(),
    );
  }

  /// Notificações. [profissional] muda para onde o toque leva (disputa e retrabalho abrem as
  /// telas do profissional; o cliente vê o serviço).
  static Future<void> abrirNotificacoes(BuildContext context, {bool profissional = false}) async {
    await _abrir<void>(context, _notificacoes(profissional: profissional));
    pedidosMudaram.value++;
  }

  /// Termos de uso e política de privacidade (rascunhos; a tela avisa que serão revisados).
  static void abrirTermos(BuildContext context) => _abrir<void>(
        context,
        Builder(
          builder: (context) => TermosEPoliticaTela(aoAbrir: (t) => abrirTextoLegal(context, t)),
        ),
      );

  static void abrirTextoLegal(BuildContext context, TextoLegal texto) =>
      _abrir<void>(context, TextoLegalTela.de(texto));

  /// Aba "Início" do cliente: carrega nome, categorias, pedido em andamento e serviços recentes.
  static Widget abaInicio({required VoidCallback aoBuscar}) => Carregador<DadosInicio>(
        carregar: _carregarInicio,
        atualizarQuando: pedidosMudaram,
        atualizarACada: _intervalo,
        construir: (context, dados) => InicioTela(
          aoBuscar: aoBuscar,
          dados: dados,
          aoAbrirNotificacoes: temSessao
              ? () => abrirNotificacoes(context)
              : () => _abrir<void>(context, const LoginTela()),
          aoNovoPedido: () => abrirNovoPedido(context),
          aoAbrirPedidoEmAndamento: (p) => abrirServico(context, p.pedidoId ?? _semId),
          aoAbrirCategoria: (c) => abrirCategoria(context, c),
          aoVerTodasCategorias: () => abrirTodasCategorias(context),
        ),
      );

  static Future<DadosInicio> _carregarInicio() async {
    if (emModoVisitante) {
      final categorias = await repos.catalogo.categorias();
      return DadosInicio(nome: '', categorias: categorias);
    }
    // Em paralelo: a tela espera a mais lenta, não a soma das chamadas.
    _atualizarMensagensNaoLidasEmSegundoPlano(profissional: false);
    final ((perfil, categorias), (andamento, (recentes, naoLidas))) = await emParalelo2(
      emParalelo2(repos.perfil.carregar(), repos.catalogo.categorias()),
      emParalelo2(
        repos.servicos.emAndamento(),
        emParalelo2(repos.servicos.recentes(), _contarNotificacoesNaoLidas()),
      ),
    );
    final recentesFiltrados = [
      for (final r in recentes)
        // Pelo id quando há (títulos se repetem); pelo título só sem id (dados de exemplo).
        if (andamento == null ||
            (andamento.pedidoId != null
                ? r.pedidoId != andamento.pedidoId
                : r.titulo != andamento.titulo))
          r,
    ];
    return DadosInicio(
      nome: perfil.nome.trim().split(' ').first,
      categorias: categorias,
      emAndamento: andamento,
      recentes: recentesFiltrados,
      notificacoesNaoLidas: naoLidas,
    );
  }

  static const _perfilIndisponivel = 'Perfil indisponível por enquanto.';

  /// Ao tocar em "Usar como profissional" no perfil do cliente: exibe o tour de 4 páginas do
  /// profissional na 1ª vez (gravado em [PreferenciaTourPerfil]) antes de entrar no modo profissional.
  static Future<void> abrirModoProfissionalComTour(BuildContext context) async {
    final jaViu = await PreferenciaTourPerfil.visto(PerfilUso.profissional);
    if (!context.mounted) return;
    if (!jaViu) {
      await _abrir<void>(
        context,
        Builder(
          builder: (tourCtx) => TourPerfilTela(
            perfil: PerfilUso.profissional,
            registrarVisto: true,
            aoConcluir: () {
              if (tourCtx.mounted) irParaProfissional(tourCtx);
            },
          ),
        ),
      );
      return;
    }
    await irParaProfissional(context);
  }

  /// Depois do cadastro de profissional (e em "Usar como profissional"): casca do profissional.
  static Future<void> irParaProfissional(BuildContext context) async {
    final tem = repos.modoApi
        ? (await repos.perfilPublico?.temPerfilProfissional() ?? false)
        : ((ServicoAuthPadrao.atual.sessaoAtual?.ehProfissional == true) ||
            (await repos.perfilPublico?.temPerfilProfissional() ?? false));
    if (tem && context.mounted) {
      if (repos.modoApi && repos.verificacao != null) {
        SituacaoVerificacao? sit;
        try {
          sit = await repos.verificacao!.carregarSituacao();
        } on Object {
          sit = null;
        }
        if (!context.mounted) return;
        if (sit != null &&
            (sit.status == StatusVerificacao.naoEnviada ||
                sit.status == StatusVerificacao.pendente)) {
          await _abrir<void>(
            context,
            Builder(
              builder: (ctxVerif) => VerificacaoTela(
                servico: repos.verificacao!,
                obrigatoria: true,
                aoCapturarDocumento: repos.capturaVerificacao?.documento ?? _fotografar,
                aoCapturarSelfie: repos.capturaVerificacao?.selfie ?? _fotografar,
                aoVoltarCliente: () => irParaCliente(ctxVerif),
                aoConcluir: () {
                  if (ctxVerif.mounted) _entrarNaCascaProfissional(ctxVerif);
                },
              ),
            ),
          );
          return;
        }
      }
      _entrarNaCascaProfissional(context);
      return;
    }
    if (context.mounted) {
      _abrirCadastroProfissional(context);
    }
  }

  /// Foto pela câmera; devolve só a referência (o upload é do backend, por URL assinada).
  static Future<String?> _fotografar() => dispositivo.fotografarEEnviar();

  /// Foto de PERFIL: tira, mostra na hora e envia ao backend (outros usuários passam a ver).
  static Future<String?> _fotografarPerfil() async {
    final local = await dispositivo.camera.fotografar();
    if (local == null) return null;
    try {
      await repos.perfil.enviarFoto(local);
    } on Object catch (_) {
      // sem rede: a foto aparece só neste aparelho até enviar de novo
    }
    return local;
  }

  static Future<List<String>> _selecionarFotos() => dispositivo.fotografarMultiplasEEnviar();

  static void _entrarNaCascaProfissional(BuildContext context) {
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute<void>(builder: (_) => _cascaProfissional()),
      (rota) => false,
    );
  }

  /// Cadastro → verificação (documento e selfie) → casca do profissional.
  static void _abrirCadastroProfissional(BuildContext context) => _abrir<void>(
        context,
        Builder(
          builder: (context) => CadastroProfissionalTela(
            nomeInicial: repos.perfil.nomeSalvo ?? ServicoAuthPadrao.atual.sessaoAtual?.nome ?? '',
            servico: repos.cadastroProfissional!,
            servicoCep: repos.cep,
            aoAdicionarFoto: _fotografar,
            aoAdicionarFotos: _selecionarFotos,
            aoConcluir: () => _abrir<void>(
              context,
              Builder(
                builder: (ctxVerif) => VerificacaoTela(
                  servico: repos.verificacao!,
                  obrigatoria: true,
                  aoCapturarDocumento: repos.capturaVerificacao?.documento ?? _fotografar,
                  aoCapturarSelfie: repos.capturaVerificacao?.selfie ?? _fotografar,
                  aoVoltarCliente: () => irParaCliente(ctxVerif),
                  aoConcluir: () {
                    if (ctxVerif.mounted) _entrarNaCascaProfissional(ctxVerif);
                  },
                ),
              ),
            ),
          ),
        ),
      );

  /// "Editar cadastro" de quem já é profissional: formulário preenchido com o que está salvo;
  /// salvou, mostra confirmação e volta atualizado. A verificação não se repete por editar.
  static Future<void> _editarCadastroProfissional(BuildContext context) => _abrir<void>(
        context,
        Builder(
          builder: (tela) => CadastroProfissionalTela(
            edicao: true,
            nomeInicial: repos.perfil.nomeSalvo ?? ServicoAuthPadrao.atual.sessaoAtual?.nome ?? '',
            servico: _ServicoCadastroEdicao(
              repos.cadastroProfissional!,
              repos.verificacao,
            ),
            servicoCep: repos.cep,
            aoAdicionarFoto: _fotografar,
            aoAdicionarFotos: _selecionarFotos,
            aoConcluir: () {
              pedidosMudaram.value++;
              _abrirSucesso<void>(
                tela,
                (ctxSucesso) => SucessoAcaoTela(
                  titulo: 'Cadastro atualizado!',
                  subtitulo: 'Suas informações já estão atualizadas para os clientes.',
                  textoBotaoPrimario: 'Voltar ao perfil',
                  aoTocarPrimario: () => Navigator.of(ctxSucesso).pop(),
                  textoBotaoSecundario: 'Voltar ao início',
                  aoVoltarInicio: () => _voltarAoInicio(ctxSucesso),
                ),
                substituirAtual: true,
              );
            },
          ),
        ),
      );

  // --- Profissional ------------------------------------------------------------------

  @visibleForTesting
  static Widget cascaProfissionalParaTeste({int abaInicial = 0}) =>
      _cascaProfissional(abaInicial: abaInicial);

  static Future<InicioProfissional> _carregarInicioProfissional() async {
    _atualizarMensagensNaoLidasEmSegundoPlano(profissional: true);
    final (inicio, naoLidas) = await emParalelo2(
      repos.profissional.inicio(),
      _contarNotificacoesNaoLidas(),
    );
    return inicio.comNotificacoesNaoLidas(naoLidas);
  }

  static Widget _cascaProfissional({int abaInicial = 0}) => Carregador<InicioProfissional>(
        carregar: _carregarInicioProfissional,
        construir: (context, inicio) => CascaProfissionalTela(
          abaInicial: abaInicial,
          inicio: inicio,
          carregarDetalhe: (pedido) => repos.profissional.detalhe(pedido.id),
          pedirExclusividade: (pedido, chave) =>
              repos.profissional.solicitarExclusividade(pedido.id, chave),
          recusarPedido: (pedido, motivo) => _tentar(
            context,
            () => repos.profissional.recusar(pedido.id, motivo),
          ),
          abaCarteira: _abaCarteira(),
          abaPerfil: _abaPerfilProfissional(),
          abaAgenda: _abaAgenda(),
          carregarPrimeirosPassos: repos.primeirosPassos?.carregar,
          aoAbrirContaRecebimento: () async {
            final conta = await repos.profissional
                .obterContaRecebimento()
                .catchError((_) => const ContaRecebimento(cadastrada: false));
            if (context.mounted) await _abrirContaRecebimento(context, conta);
          },
          abaConversas: Builder(
            builder: (context) => ListaConversas(
              // O estado real do pedido (Concluído, Cancelado) no rótulo de cada conversa.
              servico: ServicoMensagensComEstado(
                repos.mensagensProfissional ??
                    ServicoMensagensDoProfissional(repos.profissional, chat: repos.chat),
                repos.profissional.estadosDosPedidos,
              ),
              textoVazio: 'Quando um cliente conversar com você sobre um pedido, aparece aqui.',
              atualizarACada: _intervalo,
              atualizarQuando: pedidosMudaram,
              aoContarNaoLidas: (n) => mensagensNaoLidas.value = n,
              aoAbrirConversa: (c) => _abrirConversa(
                context,
                c,
                repos.mensagensProfissional ?? _servicoMensagens,
                comoProfissional: true,
              ),
            ),
          ),
          carregarPedidos: repos.profissional.pedidosAbertos,
          recarregarInicio: _carregarInicioProfissional,
          aoAlterarDisponivel: repos.profissional.alterarDisponivelAgora,
          aoAbrirOrcamentoEnviado: (o) => _abrirDetalheOrcamentoEnviado(context, o),
          atualizarACada: _intervalo,
          atualizarQuando: pedidosMudaram,
          aoAbrirMapa: abrirNoMapa,
          aoAbrirFinalizado: (c) => _abrir<void>(context, _pedidoDoProfissional(c.pedidoId)),
          aoAbrirContratado: (c) => _acoesPedidoProfissional(
            context,
            pedidoId: c.pedidoId,
            titulo: c.titulo,
            remoto: c.remoto,
            jaAvaliou: c.jaAvaliou,
            consultaMapa: c.consultaMapa,
            estadoApi: c.estadoApi,
            // Antes do pagamento só há a conversa; `concluido` aqui só esconde check-in e check-out.
            estado: c.emAndamento
                ? EstadoAgendamento.emAndamento
                : c.naAgenda
                    ? EstadoAgendamento.agendado
                    : EstadoAgendamento.concluido,
            aoCheckIn: () => _abrir<void>(
              context,
              CheckInTela(
                aoIniciar: () => _aoIniciarServico(context),
                servico: _servicoCheckIn(c.pedidoId, remoto: c.remoto),
                permissao: permissao,
                remoto: c.remoto,
                tituloBarra: c.titulo,
              ),
            ),
          ),
          carregarCategorias: () async {
            final todas = await repos.catalogo.categorias();
            final cadastro = repos.cadastroProfissional;
            if (cadastro == null) return todas;
            try {
              final atual = await cadastro.carregarAtual();
              if (atual == null || atual.categorias.isEmpty) return todas;
              final filtradas = todas.where((c) => atual.categorias.contains(c.nome)).toList();
              return filtradas.isEmpty ? todas : filtradas;
            } on Object {
              return todas;
            }
          },
          aoAbrirNotificacoes: () => abrirNotificacoes(context, profissional: true),
          aoUsarComoCliente: () => irParaCliente(context),
          aoGerenciarProximo: (proximo) => _acoesPedidoProfissional(
            context,
            pedidoId: proximo?.pedidoId ?? _semId,
            titulo: proximo?.titulo ?? 'Pedido de hoje',
            quando: proximo?.quando,
            remoto: proximo?.remoto ?? false,
            estadoApi: proximo?.estadoApi,
            estado: (proximo?.emAndamento == true)
                ? EstadoAgendamento.emAndamento
                : EstadoAgendamento.agendado,
            aoCheckIn: () => _abrir<void>(
              context,
              CheckInTela(
                aoIniciar: () => _aoIniciarServico(context),
                permissao: permissao,
                remoto: proximo?.remoto ?? false,
                servico: _servicoCheckIn(
                  proximo?.pedidoId ?? _semId,
                  remoto: proximo?.remoto ?? false,
                ),
                tituloBarra: proximo == null ? 'Check-in' : '${proximo.titulo} · ${proximo.quando}',
              ),
            ),
          ),
          aoAvisarACaminho: (pedidoId, eta) =>
              repos.profissional.avisarACaminho(pedidoId, etaMinutos: eta),
          aoFazerCheckIn: () => _acoesPedidoProfissional(
            context,
            pedidoId: inicio.proximo?.pedidoId ?? _semId,
            titulo: inicio.proximo?.titulo ?? 'Pedido de hoje',
            quando: inicio.proximo?.quando,
            remoto: inicio.proximo?.remoto ?? false,
            estadoApi: inicio.proximo?.estadoApi,
            estado: (inicio.proximo?.emAndamento == true)
                ? EstadoAgendamento.emAndamento
                : EstadoAgendamento.agendado,
            aoCheckIn: () => _abrir<void>(
              context,
              CheckInTela(
                aoIniciar: () => _aoIniciarServico(context),
                permissao: permissao,
                remoto: inicio.proximo?.remoto ?? false,
                servico: _servicoCheckIn(
                  inicio.proximo?.pedidoId ?? _semId,
                  remoto: inicio.proximo?.remoto ?? false,
                ),
                tituloBarra: inicio.proximo == null
                    ? 'Check-in'
                    : '${inicio.proximo!.titulo} · ${inicio.proximo!.quando}',
              ),
            ),
          ),
          aoFazerOrcamento: () {
            final pedido = inicio.pedidos.isNotEmpty ? inicio.pedidos.first : null;
            final id = pedido?.id ?? _semId;
            final titulo = pedido?.titulo ?? 'Orçamento';
            _abrirOrcamento(context, id, titulo,
                remoto: pedido?.remoto ?? false, categoriaId: pedido?.categoriaId);
          },
          aoFazerOrcamentoDoPedido: (pedido) =>
              _abrirOrcamento(context, pedido.id, pedido.titulo,
                  remoto: pedido.remoto, categoriaId: pedido.categoriaId),
          aoPerguntar: () {
            final pedido = inicio.pedidos.isNotEmpty ? inicio.pedidos.first : null;
            _abrir<void>(
              context,
              _chat(
                pedido?.id ?? _semId,
                comoProfissional: true,
                categoriaNome: pedido?.titulo,
              ),
            );
          },
          aoPerguntarDoPedido: (pedido) => _abrir<void>(
            context,
            _chat(pedido.id, comoProfissional: true, categoriaNome: pedido.titulo),
          ),
        ),
      );

  /// Check-in do pedido. No modo API o serviço já recebe a captura real (câmera, upload e GPS) e
  /// é ele quem guarda foto e posição para enviar; embrulhá-lo no serviço do aparelho fazia a
  /// tela marcar "Feito" sem o envio ter foto nem posição. O embrulho só vale na demonstração.
  static ServicoCheckIn _servicoCheckIn(String pedidoId, {bool remoto = false}) {
    final base = repos.profissional.servicoCheckIn(pedidoId, remoto: remoto);
    return repos.modoApi ? base : ServicoCheckInDispositivo(base: base, dispositivo: dispositivo);
  }

  static String? _textoDecimos(int decimos) {
    if (decimos <= 0) return null;
    final intParte = decimos ~/ 10;
    final resto = decimos % 10;
    return resto == 0 ? '$intParte' : '$intParte,$resto';
  }

  static String _textoCentavosCampo(int centavos) => Dinheiro.paraCampoSemZeros(centavos);

  static void _abrirDetalheOrcamentoEnviado(
    BuildContext context,
    OrcamentoEnviado resumo,
  ) {
    if (resumo.orcamentoId.isEmpty) {
      _abrir<void>(
        context,
        _chat(resumo.pedidoId, comoProfissional: true, categoriaNome: resumo.titulo),
      );
      return;
    }
    _abrir<void>(
      context,
      Carregador<DetalheOrcamentoEnviado>(
        textoNaoEncontrado: TextosNaoEncontrado.orcamento,
        carregar: () => repos.profissional.meuOrcamento(
          resumo.orcamentoId,
          tituloPedido: resumo.titulo,
          situacao: resumo.situacao,
        ),
        construir: (tela, det) => DetalheOrcamentoEnviadoTela(
          detalhe: det,
          aoEditar: det.podeEditar
              ? () => _abrirOrcamento(
                    tela,
                    det.pedidoId,
                    det.tituloPedido,
                    inicial: det,
                  )
              : null,
          aoAbrirChat: () => _abrir<void>(
            tela,
            _chat(det.pedidoId, comoProfissional: true, categoriaNome: det.tituloPedido),
          ),
        ),
      ),
    );
  }

  /// "Meu CNPJ" (Configurações do profissional e aviso ao tentar orçar sem CNPJ).
  static void abrirMeuCnpj(BuildContext context) {
    final servico = repos.mei;
    if (servico == null) return;
    _abrir<void>(context, MeuCnpjTela(servico: servico));
  }

  /// Como [_tentar], mas se o servidor barra o orçamento por falta de CNPJ/MEI, mostra o texto dele
  /// com o botão "Informar meu CNPJ" em vez de um aviso que some.
  static Future<bool> tentarOrcamento(BuildContext context, Future<void> Function() acao) async {
    try {
      await acao();
      return true;
    } on ErroTrato catch (erro) {
      if (context.mounted && erro.codigoHttp == 422 && mensagemDeCnpj(erro.mensagem)) {
        await _avisoCnpjNecessario(context, erro.mensagem);
      } else if (context.mounted) {
        _aviso(context, erro);
      }
      return false;
    } on Object catch (erro) {
      if (context.mounted) _aviso(context, erro);
      return false;
    }
  }

  static Future<void> _avisoCnpjNecessario(BuildContext context, String texto) {
    return showDialog<void>(
      context: context,
      builder: (dialogo) => AlertDialog(
        key: const Key('dialogo-cnpj-necessario'),
        title: const Text('Falta o seu CNPJ'),
        content: Text(texto),
        actions: [
          TextButton(onPressed: () => Navigator.of(dialogo).pop(), child: const Text('Fechar')),
          if (repos.mei != null)
            FilledButton(
              key: const Key('botao-informar-cnpj'),
              onPressed: () {
                Navigator.of(dialogo).pop();
                abrirMeuCnpj(context);
              },
              child: const Text('Informar meu CNPJ'),
            ),
        ],
      ),
    );
  }

  /// Garantia mínima (CDC) da categoria do pedido: o backend manda `garantia_minima_dias` em cada
  /// categoria (90 durável, 30 não durável). Sem o dado ou sem rede, o padrão seguro é 30.
  ///
  /// A categoria é achada pelo ID (o `categoria_id` do pedido aberto; na edição, o do detalhe do
  /// pedido). Só se nenhum id estiver disponível usa o nome da categoria, e sem achar nada fica em
  /// 30: nunca se oferece garantia abaixo do mínimo que se conhece.
  static Future<int> _garantiaMinimaDoPedido(String pedidoId, {String? categoriaId}) async {
    const espera = Duration(seconds: 4);
    try {
      final todas = await repos.catalogo.categorias().timeout(espera);
      var id = categoriaId;
      if (id == null || id.isEmpty) {
        try {
          id = (await repos.profissional.detalhe(pedidoId).timeout(espera)).pedido.categoriaId;
        } on Object {
          id = null;
        }
      }
      if (id != null && id.isNotEmpty) {
        final achada = todas.where((c) => c.id == id).firstOrNull;
        if (achada != null) return achada.garantiaMinimaDias;
      }
      final nome = (await repos.pedidos.dados(pedidoId).timeout(espera)).categoriaNome;
      if (nome == null) return 30;
      return todas.where((c) => c.nome == nome).firstOrNull?.garantiaMinimaDias ?? 30;
    } on Object {
      return 30;
    }
  }

  /// Só para testes.
  @visibleForTesting
  static Future<int> garantiaMinimaParaTeste(String pedidoId, {String? categoriaId}) =>
      _garantiaMinimaDoPedido(pedidoId, categoriaId: categoriaId);

  static Future<void> _abrirOrcamento(
    BuildContext context,
    String pedidoId,
    String titulo, {
    DetalheOrcamentoEnviado? inicial,
    bool remoto = false,
    String? categoriaId,
  }) async {
    final servico = repos.profissional.servicoOrcamento(pedidoId);
    final minima = await _garantiaMinimaDoPedido(pedidoId, categoriaId: categoriaId);
    if (!context.mounted) return;
    _abrir<void>(
      context,
      Builder(
        builder: (tela) => CalculadoraOrcamentoTela(
          servico: servico,
          tituloPedido: titulo,
          edicao: inicial != null,
          remoto: remoto,
          mostrarForaDoEscopo: true,
          deslocamentoInicial: inicial == null ? null : _textoDecimos(inicial.decimosDeslocamento),
          horasInicial: inicial == null ? null : _textoDecimos(inicial.decimosTrabalhadas),
          valorHoraInicial: inicial == null ? null : _textoCentavosCampo(inicial.valorHoraCentavos),
          garantiaInicialDias: inicial?.garantiaDias ?? 90,
          garantiaMinimaDias: minima,
          prazoExecucaoInicialDias: inicial?.prazoExecucaoDias ?? 3,
          itensIniciais: inicial?.materiais ?? const [],
          foraDoEscopoInicial: inicial?.foraDoEscopo,
          observacoesInicial: inicial?.observacoes,
          aoEnviar: (pronto) async {
            final ok = await tentarOrcamento(tela, () => servico.enviar(pronto));
            if (ok && tela.mounted) {
              pedidosMudaram.value++;
              await _abrirSucesso<void>(
                tela,
                (ctxSucesso) => SucessoAcaoTela(
                  titulo: inicial != null ? 'Orçamento atualizado!' : 'Orçamento enviado!',
                  subtitulo: 'O cliente já pode analisar o valor e o prazo combinados.',
                  detalhes: [
                    ItemResumoSucesso('Pedido', titulo),
                    ItemResumoSucesso(
                      'Prazo estimado',
                      '${pronto.prazoExecucaoDias} ${pronto.prazoExecucaoDias == 1 ? 'dia' : 'dias'}',
                    ),
                  ],
                  aoVoltarInicio: () => _voltarAoInicio(ctxSucesso),
                  textoBotaoSecundario: 'Ir para pedidos',
                  aoTocarSecundario: () => _voltarAoInicio(ctxSucesso, aba: 1),
                ),
                substituirAtual: true,
              );
            }
          },
        ),
      ),
    );
  }

  /// Aba Agenda: atendimentos por dia; cada um abre as ações do pedido (check-in, nota, aditivo).
  static Widget _abaAgenda() => Builder(
        builder: (context) => AgendaTela(
          carregar: repos.agenda.listar,
          atualizarQuando: pedidosMudaram,
          atualizarACada: _intervalo,
          aoFazerCheckIn: (a) => _acoesPedidoProfissional(
            context,
            pedidoId: a.pedidoId,
            titulo: a.titulo,
            estado: a.estado,
            estadoApi: a.estadoApi,
            remoto: a.remoto,
            consultaMapa: a.consultaMapa,
            aoCheckIn: () => _abrir<void>(
              context,
              CheckInTela(
                aoIniciar: () => _aoIniciarServico(context),
                permissao: permissao,
                remoto: a.remoto,
                servico: _servicoCheckIn(a.pedidoId, remoto: a.remoto),
                tituloBarra: '${a.titulo} · ${a.horario}',
              ),
            ),
          ),
        ),
      );

  /// Só para testes: no lugar dos seletores de dia e hora.
  @visibleForTesting
  static Future<DateTime?> Function(BuildContext context)? escolherJanelaParaTeste;

  /// Só para testes: o caminho do profissional ("Remarcar data da visita" na agenda).
  @visibleForTesting
  static Future<void> marcarVisitaParaTeste(
    BuildContext context,
    String pedidoId, {
    bool remarcar = false,
    bool remoto = false,
  }) =>
      _marcarVisita(context, pedidoId, remarcar: remarcar, remoto: remoto);

  static Future<DateTime?> _escolherJanelaVisita(
    BuildContext context, {
    String tituloDia = 'Dia da visita',
    String tituloHora = 'Hora da chegada',
  }) async {
    final gancho = escolherJanelaParaTeste;
    if (gancho != null) return gancho(context);
    final hoje = DateTime.now();
    final dia = await showDatePicker(
      context: context,
      firstDate: DateTime(hoje.year, hoje.month, hoje.day), // dias passados ficam desabilitados
      lastDate: hoje.add(const Duration(days: 90)),
      helpText: tituloDia,
    );
    if (dia == null || !context.mounted) return null;
    final hora = await showTimePicker(
      context: context,
      initialTime: const TimeOfDay(hour: 9, minute: 0),
      helpText: tituloHora,
    );
    if (hora == null || !context.mounted) return null;
    final escolhido = DateTime(dia.year, dia.month, dia.day, hora.hour, hora.minute);
    if (escolhido.isBefore(DateTime.now())) {
      _avisoSimples(context, 'Escolha um horário que ainda não passou.');
      return null;
    }
    return escolhido;
  }

  /// Ações do pedido de hoje: check-in, nota de materiais e aditivo.
  /// Escolhe dia e hora da visita de um pedido pago ou já agendado (remarcar).
  static Future<void> _marcarVisita(
    BuildContext context,
    String pedidoId, {
    bool remarcar = false,
    bool remoto = false,
  }) async {
    final inicio = await _escolherJanelaVisita(
      context,
      tituloDia: remoto ? 'Dia do início' : (remarcar ? 'Novo dia da visita' : 'Dia da visita'),
      tituloHora: remoto ? 'Hora do início' : 'Hora da chegada',
    );
    if (inicio == null || !context.mounted) return;
    final fim = inicio.add(const Duration(hours: 2));
    if (remarcar) {
      // Pedido já agendado: mudar a data é uma PROPOSTA; a outra parte precisa aceitar.
      await proporNovaDataDoPedido(context, pedidoId, inicio, fim, remoto: remoto);
      return;
    }
    final ok = await _tentar(context, () => repos.profissional.confirmarAgenda(pedidoId, inicio, fim));
    if (ok) pedidosMudaram.value++;
    if (ok && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            remoto
                ? 'Início combinado. O cliente já pode ver o código de início.'
                : 'Visita marcada. O cliente já pode ver o código de início.',
          ),
        ),
      );
    }
  }

  /// Muda a data de um pedido JÁ agendado, para cliente e profissional: envia uma proposta de
  /// reagendamento (`POST /v1/pedidos/{id}/reagendamentos`). Nada muda até a outra parte aceitar;
  /// ela vê o cartão "Aceitar nova data". O app nunca troca a data sozinho. Se o servidor recusar
  /// (ex.: já há uma proposta), o texto dele aparece.
  static Future<void> proporNovaDataDoPedido(
    BuildContext context,
    String pedidoId,
    DateTime inicio,
    DateTime fim, {
    bool remoto = false,
  }) async {
    final ok = await _tentar(
      context,
      () => repos.pedidos.proporReagendamento(pedidoId, inicio: inicio, fim: fim),
    );
    if (ok) pedidosMudaram.value++;
    if (ok && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            remoto
                ? 'Proposta de novo início enviada. Aguardando a outra parte aceitar.'
                : 'Proposta de nova data enviada. Aguardando a outra parte aceitar.',
          ),
        ),
      );
    }
  }

  /// Depois do início aceito pelo backend: confirma na tela de sucesso e atualiza a casca.
  static void _aoIniciarServico(BuildContext context) {
    pedidosMudaram.value++;
    if (!context.mounted) return;
    _abrirSucesso<void>(
      context,
      (ctxSucesso) => SucessoAcaoTela(
        titulo: 'Serviço iniciado!',
        subtitulo: 'O cliente foi avisado. Ao concluir, faça o check-out no app.',
        aoVoltarInicio: () => _voltarAoInicio(ctxSucesso),
        textoBotaoSecundario: 'Ir para a agenda',
        aoTocarSecundario: () => _voltarAoInicio(ctxSucesso, aba: 2),
      ),
      substituirAtual: true,
    );
  }

  /// Check-out: foto final e o código de conclusão que o cliente informa. Quem confere o código
  /// é o backend; ao ser aceito o serviço vai para "em confirmação" e o cliente é avisado.
  static void _abrirCheckOut(BuildContext context, String pedidoId, String titulo,
      {bool remoto = false}) {
    _abrir<void>(
      context,
      Builder(
        builder: (tela) => CheckOutTela(
          servico: repos.profissional.servicoCheckOut(pedidoId, remoto: remoto),
          permissao: permissao,
          remoto: remoto,
          tituloBarra: titulo,
          aoConcluir: () {
            pedidosMudaram.value++;
            _abrirSucesso<void>(
              tela,
              (ctxSucesso) => SucessoAcaoTela(
                titulo: 'Serviço concluído!',
                subtitulo:
                    'O cliente tem até ${ConfigPublica.horas(ConfigPublica.atual.prazoConfirmacaoHoras)} para confirmar a conclusão.',
                aoVoltarInicio: () => _voltarAoInicio(ctxSucesso),
                textoBotaoSecundario: 'Ir para pedidos',
                aoTocarSecundario: () => _voltarAoInicio(ctxSucesso, aba: 1),
              ),
              substituirAtual: true,
            );
          },
        ),
      ),
    );
  }

  static void _abrirValoresEAvaliar(BuildContext context, String pedidoId) =>
      _abrir<void>(context, _valoresEAvaliar(pedidoId));

  /// "Avaliar o cliente": a tela de nota e, ao enviar, a confirmação (+Tratinhos quem decide é o
  /// servidor). Usada na tela de valores, no pedido concluído e no menu do pedido.
  static Future<void> _avaliarCliente(BuildContext context, String pedidoId) async {
    final enviou = await _abrir<bool>(
      context,
      AvaliarClienteTela(
        pedidoNumero: PedidoApi.numeroDe(pedidoId),
        aoEnviar: (nota, comentario) =>
            repos.profissional.avaliarCliente(pedidoId, nota, comentario),
      ),
    );
    if (enviou == true && context.mounted) {
      pedidosMudaram.value++;
      await _abrirSucesso<void>(
        context,
        (ctxSucesso) => SucessoAcaoTela(
          titulo: 'Avaliação enviada!',
          subtitulo: 'Obrigado por avaliar o atendimento.',
          aoVoltarInicio: () => _voltarAoInicio(ctxSucesso),
        ),
        substituirAtual: true,
      );
    }
  }

  static Widget _valoresEAvaliar(String pedidoId) => Builder(
        builder: (context) => DetalheValoresTela(
          carregar: () => repos.profissional.valoresDoPedido(pedidoId),
          aoAvaliarCliente: () => _avaliarCliente(context, pedidoId),
        ),
      );

  /// Abre o menu de ações do pedido do profissional (para testes de widget).
  @visibleForTesting
  static void acoesPedidoProfissionalParaTeste(
    BuildContext context, {
    required String estadoApi,
    bool remoto = false,
    bool jaAvaliou = false,
  }) =>
      _acoesPedidoProfissional(
        context,
        pedidoId: 'p1',
        titulo: 'Pedido de teste',
        estadoApi: estadoApi,
        remoto: remoto,
        jaAvaliou: jaAvaliou,
        aoCheckIn: () {},
      );

  static void _acoesPedidoProfissional(
    BuildContext context, {
    required String pedidoId,
    required String titulo,
    required VoidCallback aoCheckIn,
    EstadoAgendamento estado = EstadoAgendamento.agendado,
    String? estadoApi,
    bool remoto = false,
    bool jaAvaliou = false,
    String? consultaMapa,
    String? quando,
  }) {
    // Início e Pedidos oferecem as MESMAS ações: com o estado da API, só ele decide.
    final precisaAgendar = estadoApi == 'pago_e_retido';
    final agendado = estadoApi != null
        ? const {'pago_e_retido', 'agendado'}.contains(estadoApi)
        : estado == EstadoAgendamento.agendado;
    final podeCheckIn = agendado && !precisaAgendar;
    final emAndamento =
        estadoApi != null ? estadoApi == 'em_andamento' : estado == EstadoAgendamento.emAndamento;
    final emDisputa = estadoApi == 'em_disputa';
    final emRetrabalho = estadoApi == 'retrabalho';
    final finalizado = estadoApi == 'concluido' ||
        estadoApi == 'em_confirmacao' ||
        (estadoApi == null && estado == EstadoAgendamento.concluido);
    // Agendado ou em andamento: a tela do atendimento, com Chat, Ajuda e SOS sempre à mão.
    final emAtendimento = emAndamento || podeCheckIn;
    Widget acoes(BuildContext folha) => Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (!emAtendimento)
                  ListTile(title: Text(titulo, style: TipografiaTrato.titulo)),
                if (estadoApi == 'pago_e_retido' || estadoApi == 'agendado')
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: EspacosTrato.x4),
                    child: _secaoReagendamento(pedidoId, semHorario: precisaAgendar),
                  ),
                if (!remoto && consultaMapa != null)
                  ListTile(
                    leading: const Icon(Icons.map_outlined),
                    title: const Text('Abrir o endereço no mapa'),
                    onTap: () {
                      Navigator.of(folha).pop();
                      abrirNoMapa(consultaMapa);
                    },
                  ),
                if (precisaAgendar)
                  ListTile(
                    leading: const Icon(Icons.event_available_outlined),
                    title: Text(remoto ? 'Combinar início' : 'Marcar data da visita'),
                    onTap: () {
                      Navigator.of(folha).pop();
                      _marcarVisita(context, pedidoId, remoto: remoto);
                    },
                  ),
                if (agendado && !precisaAgendar && !remoto)
                  ListTile(
                    leading: const Icon(Icons.edit_calendar_outlined),
                    title: const Text('Remarcar data da visita'),
                    onTap: () {
                      Navigator.of(folha).pop();
                      _marcarVisita(context, pedidoId, remarcar: true);
                    },
                  ),
                if (podeCheckIn)
                  ListTile(
                    leading: Icon(remoto ? Icons.play_circle_outline : Icons.place_outlined),
                    title: Text(remoto ? 'Iniciar atendimento' : 'Fazer check-in'),
                    onTap: () {
                      Navigator.of(folha).pop();
                      aoCheckIn();
                    },
                  ),
                if (emAndamento)
                  ListTile(
                    leading: const Icon(Icons.task_alt_outlined),
                    title: const Text('Concluir serviço (check-out)'),
                    onTap: () {
                      Navigator.of(folha).pop();
                      _abrirCheckOut(context, pedidoId, titulo, remoto: remoto);
                    },
                  ),
                if (emDisputa)
                  ListTile(
                    leading: const Icon(Icons.gavel_outlined),
                    title: const Text('Responder disputa'),
                    onTap: () {
                      Navigator.of(folha).pop();
                      abrirDisputa(context, pedidoId);
                    },
                  ),
                if (emRetrabalho)
                  ListTile(
                    leading: const Icon(Icons.build_outlined),
                    title: const Text('Atender retrabalho'),
                    onTap: () {
                      Navigator.of(folha).pop();
                      abrirRetrabalho(context, pedidoId);
                    },
                  ),
                ListTile(
                  leading: const Icon(Icons.chat_bubble_outline),
                  title: const Text('Conversar com o cliente'),
                  onTap: () {
                    Navigator.of(folha).pop();
                    _abrir<void>(context, _chat(pedidoId, comoProfissional: true));
                  },
                ),
                if (agendado)
                  ListTile(
                    leading: const Icon(Icons.cancel_outlined),
                    title: const Text('Cancelar o atendimento'),
                    onTap: () {
                      Navigator.of(folha).pop();
                      _cancelarPedido(context, pedidoId);
                    },
                  ),
                if ((agendado || emAndamento) && !remoto)
                  ListTile(
                    leading: const Icon(Icons.receipt_long_outlined),
                    title: const Text('Enviar nota de materiais'),
                    onTap: () {
                      Navigator.of(folha).pop();
                      _abrir<void>(
                        context,
                        _enviarNota(pedidoId, titulo, servicoEmAndamento: emAndamento),
                      );
                    },
                  ),
                if (emAndamento)
                  ListTile(
                    leading: const Icon(Icons.add_task_outlined),
                    title: const Text('Criar aditivo'),
                    onTap: () {
                      Navigator.of(folha).pop();
                      _abrir<void>(context, _criarAditivo(pedidoId, titulo));
                    },
                  ),
                if (estadoApi == 'concluido')
                  ListTile(
                    key: const ValueKey('baixar-comprovante'),
                    leading: const Icon(Icons.picture_as_pdf_outlined),
                    title: const Text('Baixar comprovante (PDF)'),
                    onTap: () {
                      Navigator.of(folha).pop();
                      _baixarReciboPdf(context, pedidoId);
                    },
                  ),
                if (estadoApi == 'concluido')
                  ListTile(
                    key: const ValueKey('repetir-servico'),
                    leading: const Icon(Icons.event_repeat_outlined),
                    title: const Text('Repetir este serviço'),
                    onTap: () {
                      Navigator.of(folha).pop();
                      _repetirServico(context, pedidoId);
                    },
                  ),
                if ((estadoApi == 'concluido' ||
                        (estadoApi == null && estado == EstadoAgendamento.concluido)) &&
                    !jaAvaliou)
                  ListTile(
                    key: const ValueKey('avaliar-cliente'),
                    leading: const Icon(Icons.star_outline),
                    title: const Text('Avaliar cliente'),
                    subtitle: const Text('Sua nota ajuda outros profissionais.'),
                    onTap: () {
                      Navigator.of(folha).pop();
                      _avaliarCliente(context, pedidoId);
                    },
                  ),
                if (agendado || emAndamento || finalizado || emRetrabalho || emDisputa)
                  ListTile(
                    leading: const Icon(Icons.receipt_outlined),
                    title: const Text('Ver valores do pedido'),
                    onTap: () {
                      Navigator.of(folha).pop();
                      _abrirValoresEAvaliar(context, pedidoId);
                    },
                  ),
              ],
            );
    if (!emAtendimento) {
      showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        // Rolável: com 8 ações a lista passa da altura de um celular menor e estourava embaixo.
        builder: (folha) => ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.85),
          child: SafeArea(child: SingleChildScrollView(child: acoes(folha))),
        ),
      );
      return;
    }
    final status =
        emAndamento ? statusDeAtendimento('em_andamento') : statusDeAtendimento('agendado');
    final resumo = [
      'Atendimento Trato',
      'Serviço: $titulo',
      if ((quando ?? '').isNotEmpty) 'Horário: $quando',
    ].join('\n');
    final outraParte = repos.chat
        .conversa(pedidoId)
        .then<ConversaPedido?>((c) => c)
        .catchError((Object _) => null);
    _abrir<void>(
      context,
      Builder(
        builder: (folha) => Scaffold(
          appBar: AppBar(title: Text(titulo, maxLines: 1, overflow: TextOverflow.ellipsis)),
          body: SafeArea(
            bottom: false,
            child: SingleChildScrollView(
              child: ConteudoResponsivo(
                child: Column(
                  children: [
                    FutureBuilder<ConversaPedido?>(
                      future: outraParte,
                      builder: (_, dado) => CabecalhoAtendimento(
                        status: status,
                        horario: quando,
                        papel: 'Cliente',
                        nome: dado.data?.nome,
                        usuarioId: dado.data?.usuarioId,
                      ),
                    ),
                    const SizedBox(height: EspacosTrato.x3),
                    acoes(folha),
                  ],
                ),
              ),
            ),
          ),
          bottomNavigationBar: SafeArea(
            child: BarraAtendimento(
              aoChat: () => _abrir<void>(folha, _chat(pedidoId, comoProfissional: true)),
              aoAjuda: () => _abrir<void>(folha, _telaAjuda(folha, comoCliente: false)),
              aoSos: remoto ? null : () => _abrirSosEmergencia(folha, resumo),
            ),
          ),
        ),
      ),
    );
  }

  static Widget _enviarNota(
    String pedidoId,
    String titulo, {
    bool servicoEmAndamento = true,
  }) =>
      Builder(
        builder: (context) => EnviarNotaTela(
          servico: servicoNota,
          pedidoId: pedidoId,
          tituloPedido: titulo,
          servicoEmAndamento: servicoEmAndamento,
          aoCapturarFoto: _fotografar,
          aoEnviada: () {
            pedidosMudaram.value++;
            _abrirSucesso<void>(
              context,
              (ctxSucesso) => SucessoAcaoTela(
                titulo: 'Nota enviada!',
                subtitulo: 'O cliente já recebeu a nota dos materiais no pedido.',
                aoVoltarInicio: () => _voltarAoInicio(ctxSucesso),
              ),
              substituirAtual: true,
            );
          },
        ),
      );

  static Widget _criarAditivo(String pedidoId, String titulo) => Builder(
        builder: (context) => CriarAditivoTela(
          servico: servicoAditivo,
          servicoLiquido: repos.profissional.servicoOrcamento(pedidoId),
          pedidoId: pedidoId,
          tituloPedido: titulo,
          aoCriado: () {
            pedidosMudaram.value++;
            _abrirSucesso<void>(
              context,
              (ctxSucesso) => SucessoAcaoTela(
                titulo: 'Aditivo enviado!',
                subtitulo: 'O cliente foi notificado para aprovar a cobrança extra.',
                aoVoltarInicio: () => _voltarAoInicio(ctxSucesso),
              ),
              substituirAtual: true,
            );
          },
        ),
      );

  /// Disputa aberta pelo cliente, vista pelo profissional (a partir da notificação).
  static void abrirDisputa(BuildContext context, String disputaId) => _abrir<void>(
        context,
        Builder(
          builder: (context) => ResponderDisputaTela(
            servico: servicoDisputa,
            disputaId: disputaId,
            aoAdicionarEvidencia: _fotografar,
            aoRespondida: (_) {
              pedidosMudaram.value++;
              _abrirSucesso<void>(
                context,
                (ctxSucesso) => SucessoAcaoTela(
                  titulo: 'Resposta enviada!',
                  subtitulo: 'O cliente e nossa equipe foram avisados da sua posição.',
                  aoVoltarInicio: () => _voltarAoInicio(ctxSucesso),
                ),
                substituirAtual: true,
              );
            },
          ),
        ),
      );

  /// Retrabalho pedido pelo cliente: o profissional escolhe o horário.
  static void abrirRetrabalho(BuildContext context, String disputaId) => _abrir<void>(
        context,
        Builder(
          builder: (context) => AtenderRetrabalhoTela(
            servico: servicoDisputa,
            disputaId: disputaId,
            aoAgendado: (_) {
              pedidosMudaram.value++;
              _abrirSucesso<void>(
                context,
                (ctxSucesso) => SucessoAcaoTela(
                  titulo: 'Retrabalho agendado!',
                  subtitulo: 'O cliente recebeu a data e o horário escolhidos.',
                  aoVoltarInicio: () => _voltarAoInicio(ctxSucesso),
                ),
                substituirAtual: true,
              );
            },
          ),
        ),
      );

  /// Carteira do profissional como EXTRATO (D15): sem saldo próprio, sem saque.
  static Widget _abaCarteira() => _AbaCarteiraPaginada(
        aoAbrirItem: (context, pedidoId) => _abrirValoresEAvaliar(context, pedidoId),
        aoConfigurarRecebimento: _abrirContaRecebimento,
        aoBaixarExtratoPdf: _baixarExtratoPdf,
      );

  static Future<void> _abrirContaRecebimento(
    BuildContext context,
    ContaRecebimento atual,
  ) async {
    final salva = await Navigator.of(context).push<ContaRecebimento>(
      MaterialPageRoute(
        builder: (_) => ContaRecebimentoTela(
          inicial: atual,
          aoSalvar: repos.profissional.salvarContaRecebimento,
          carregarProximaLiberacao: () async =>
              (await repos.profissional.inicio()).carteira.proximaLiberacao,
        ),
      ),
    );
    if (salva != null && context.mounted) {
      pedidosMudaram.value++;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(content: Text('Conta de recebimento salva com sucesso.')),
        );
    }
  }

  static Future<void> _baixarExtratoPdf(BuildContext context) async {
    final agora = DateTime.now();
    final opcoes = <(String, String)>[];
    for (var i = 0; i < 6; i++) {
      final ref = DateTime(agora.year, agora.month - i, 1);
      final iso = '${ref.year}-${ref.month.toString().padLeft(2, '0')}';
      final rotulo = '${ref.month.toString().padLeft(2, '0')}/${ref.year}';
      opcoes.add((iso, rotulo));
    }
    var selecionado = opcoes.first.$1;
    final confirmado = await showDialog<String>(
      context: context,
      builder: (d) => StatefulBuilder(
        builder: (d, setStateDialog) => AlertDialog(
          title: const Text('Extrato mensal em PDF'),
          content: DropdownButtonFormField<String>(
            initialValue: selecionado,
            isExpanded: true,
            items: [
              for (final op in opcoes) DropdownMenuItem(value: op.$1, child: Text('Mês ${op.$2}')),
            ],
            onChanged: (v) {
              if (v != null) setStateDialog(() => selecionado = v);
            },
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(d).pop(),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(d).pop(selecionado),
              child: const Text('Baixar PDF'),
            ),
          ],
        ),
      ),
    );
    if (confirmado == null || !context.mounted) return;
    final mensagens = ScaffoldMessenger.of(context);
    try {
      final bytes = await repos.profissional.baixarExtratoPdf(mes: confirmado);
      final arquivo = 'trato_extrato_${confirmado.replaceAll('-', '_')}.pdf';
      final caminho = await (salvarPdfParaTeste ?? _salvarPdfNoAparelho)(bytes, arquivo);
      if (!context.mounted) return;
      mensagens
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: const Text('Extrato em PDF salvo.'),
            duration: const Duration(seconds: 4),
            persist: false,
            action: SnackBarAction(
              label: 'Compartilhar',
              onPressed: () async {
                try {
                  await compartilharArquivo(caminho);
                } on Object {
                  // Sem compartilhamento: fica só o aviso "Extrato em PDF salvo."
                  mensagens
                    ..hideCurrentSnackBar()
                    ..showSnackBar(
                      const SnackBar(
                        content: Text('Extrato em PDF salvo.'),
                        duration: Duration(seconds: 4),
                        persist: false,
                      ),
                    );
                }
              },
            ),
          ),
        );
    } on ErroTrato catch (e) {
      if (!context.mounted) return;
      mensagens
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(e.mensagem)));
    } on Object {
      if (!context.mounted) return;
      mensagens
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text('Não foi possível baixar o extrato em PDF agora.'),
          ),
        );
    }
  }

  /// Reagendamento dentro do pedido (cliente e profissional usam as mesmas rotas):
  /// propor nova data, aceitar, recusar ou cancelar a própria proposta.
  static Widget _secaoReagendamento(String pedidoId, {bool semHorario = false}) =>
      SecaoReagendamento(
        semHorario: semHorario,
        carregar: () => repos.pedidos.reagendamentos(pedidoId),
        propor: (inicio, fim, motivo) => repos.pedidos
            .proporReagendamento(pedidoId, inicio: inicio, fim: fim, motivo: motivo),
        aceitar: (rid) => repos.pedidos.aceitarReagendamento(pedidoId, rid),
        recusar: (rid) => repos.pedidos.recusarReagendamento(pedidoId, rid),
        meuId: ServicoAuthPadrao.atual.sessaoAtual?.id,
        aoMudar: () => pedidosMudaram.value++,
        intervalo: _intervalo,
      );

  /// Comprovante do pedido (`GET /v1/pedidos/{id}/recibo.pdf`): salva e abre como o extrato em PDF,
  /// com "Compartilhar" no aviso. Cliente e profissional usam o mesmo caminho.
  static Future<void> _baixarReciboPdf(BuildContext context, String pedidoId) async {
    final mensagens = ScaffoldMessenger.of(context);
    try {
      final bytes = await repos.pedidos.baixarReciboPdf(pedidoId);
      final arquivo = 'trato_comprovante_${pedidoId.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_')}.pdf';
      final caminho = await (salvarPdfParaTeste ?? _salvarPdfNoAparelho)(bytes, arquivo);
      if (!context.mounted) return;
      mensagens
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: const Text('Comprovante em PDF salvo.'),
            duration: const Duration(seconds: 4),
            persist: false,
            action: SnackBarAction(
              label: 'Compartilhar',
              onPressed: () async {
                try {
                  await compartilharArquivo(caminho);
                } on Object {
                  // Sem compartilhamento: fica só o aviso de salvo.
                }
              },
            ),
          ),
        );
    } on ErroTrato catch (e) {
      if (!context.mounted) return;
      mensagens
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(e.mensagem)));
    } on Object {
      if (!context.mounted) return;
      mensagens
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(content: Text('Não foi possível baixar o comprovante agora.')),
        );
    }
  }

  static Future<String> _salvarPdfNoAparelho(
    List<int> bytes,
    String arquivo,
  ) async {
    Directory dir;
    try {
      dir = await getApplicationDocumentsDirectory();
    } on Object {
      dir = Directory.systemTemp;
    }
    final destino = File('${dir.path}${Platform.pathSeparator}$arquivo');
    await destino.writeAsBytes(bytes, flush: true);
    try {
      await launchUrl(
        Uri.file(destino.path),
        mode: LaunchMode.externalApplication,
      );
    } on Object {
      // Sem visualizador externo ou em ambiente de teste: arquivo já salvo em disco.
    }
    return destino.path;
  }

  /// Aba "Perfil" da casca do profissional: perfil público e avaliações recebidas.
  static Widget _abaPerfilProfissional() => Builder(
        builder: (context) {
          final servico = repos.perfilPublico!;
          return PerfilPublicoTela(
            servico: servico,
            aoCapturarFotoPerfil: _fotografarPerfil,
            compartilharPerfil: compartilharNoAparelho,
            aoAbrirIndicacoes: () => abrirIndicacoes(context),
            aoAbrirRecorrencias: () => abrirRecorrencias(context),
            carregarTratinhosPendentes: () async {
              final ex = (await repos.profissional.minhasExclusividades());
              return textoTratinhosPendentes(
                ex.moedasPendentesProfissional,
                ex.moedasPendentesLiberacao,
                ex.moedaValorCentavos,
              );
            },
            aoVerAvaliacoes: () => _abrir<void>(
              context,
              AvaliacoesRecebidasTela(servico: servico),
            ),
            aoEditarCadastro: () => _editarCadastroProfissional(context),
            aoAbrirVerificacao: repos.verificacao == null
                ? null
                : () => _abrir<void>(
                      context,
                      VerificacaoTela(
                        servico: repos.verificacao!,
                        aoCapturarDocumento: repos.capturaVerificacao?.documento ?? _fotografar,
                        aoCapturarSelfie: repos.capturaVerificacao?.selfie ?? _fotografar,
                      ),
                    ),
            aoUsarComoCliente: () => irParaCliente(context),
            aoAbrirConfiguracoes: () => abrirConfiguracoes(context, profissional: true),
          );
        },
      );

  // --- Cliente: abas -----------------------------------------------------------------

  static Widget _telaVisitante({
    required String titulo,
    required String texto,
  }) =>
      Builder(
        builder: (context) => Scaffold(
          body: SafeArea(
            child: ConteudoResponsivo(
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(titulo, style: TipografiaTrato.titulo, textAlign: TextAlign.center),
                    const SizedBox(height: EspacosTrato.x2),
                    Text(
                      texto,
                      textAlign: TextAlign.center,
                      style: TipografiaTrato.corpo.copyWith(color: context.cores.textoSecundario),
                    ),
                    const SizedBox(height: EspacosTrato.x5),
                    BotaoPrimario(
                      texto: 'Criar conta',
                      aoTocar: () => _abrir<void>(context, const CriarContaTela()),
                    ),
                    const SizedBox(height: EspacosTrato.x2),
                    BotaoSecundario(
                      texto: 'Já tenho conta',
                      aoTocar: () => _abrir<void>(context, const LoginTela()),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );

  /// Aba "Perfil" da casca do cliente.
  static Widget abaPerfil() => emModoVisitante
      ? _telaVisitante(
          titulo: 'Entre na sua conta',
          texto: 'Crie uma conta ou entre para gerenciar seus dados e endereços.',
        )
      : Carregador<PerfilCliente>(
          carregar: repos.perfil.carregar,
          atualizarQuando: pedidosMudaram,
          construir: (context, perfil) => PerfilClienteTela(
            perfil: _soNoPerfil(perfil),
            aoCapturarFotoPerfil: _fotografarPerfil,
            aoCancelarExclusao: repos.privacidade is CancelamentoExclusao
                ? () => _tentar(context, () async {
                      await (repos.privacidade! as CancelamentoExclusao).cancelarExclusao();
                      pedidosMudaram.value++;
                    })
                : null,
            aoAbrirConfiguracoes: () => abrirConfiguracoes(context, profissional: false),
            aoTocarItem: (acao) {
              switch (acao) {
                case AcaoPerfil.usarComoProfissional:
                  abrirModoProfissionalComTour(context);
                case AcaoPerfil.notificacoes:
                  abrirNotificacoes(context);
                case AcaoPerfil.termos:
                  abrirTermos(context);
                case AcaoPerfil.meusDados:
                  _abrirPrivacidade(context);
                case AcaoPerfil.centralAjuda:
                  _abrir<void>(context, _telaAjuda(context));
                case AcaoPerfil.dadosPessoais:
                  _abrir<void>(
                    context,
                    DadosPessoaisTela(
                      servico: _conta,
                      servicoCep: repos.cep,
                      aoAlterarCredenciais: () => _abrir<void>(context, const SegurancaContaTela()),
                    ),
                  );
                case AcaoPerfil.enderecos:
                  _abrir<void>(context, EnderecosTela(servico: _conta, servicoCep: repos.cep));
                case AcaoPerfil.favoritos:
                  _abrir<void>(
                    context,
                    FavoritosTela(
                      servico: _conta,
                      aoBuscar: () => Navigator.of(context).pushAndRemoveUntil(
                        MaterialPageRoute<void>(
                          builder: (_) => const CascaClienteTela(abaInicial: 1),
                        ),
                        (rota) => false,
                      ),
                      aoChamarDeNovo: (f) => chamarDeNovo(context, f),
                      aoAbrir: (f) => abrirPerfil(
                        context,
                        Profissional(
                          id: f.profissionalId,
                          nome: f.nome ?? 'Profissional',
                          iniciais: (f.nome ?? 'P').substring(0, 1).toUpperCase(),
                          verificacao: '',
                          especialidade: '',
                          servicosConcluidos: f.servicos ?? 0,
                          nota: f.nota ?? 0,
                          distanciaKm: 0,
                        ),
                      ),
                    ),
                  );
                case AcaoPerfil.contatosConfianca:
                  _abrir<void>(context, ContatosConfiancaTela(servico: _conta));
                case AcaoPerfil.servicosRecorrentes:
                  abrirRecorrencias(context);
                case AcaoPerfil.indiqueEGanhe:
                  abrirIndicacoes(context, valorMoedaCentavos: perfil.moedasValorCentavos);
                default:
                  break;
              }
            },
          ),
        );

  /// Central de privacidade (LGPD): exportar e excluir a conta. Igual para cliente e profissional,
  /// porque a conta é uma só.
  static void _abrirPrivacidade(BuildContext context) => _abrir<void>(
        context,
        CentralPrivacidadeTela(
          servico: repos.privacidade!,
          carregarExclusaoAgendada: () async => (await repos.perfil.carregar()).exclusaoAgendadaEm,
          aoCancelarExclusao: repos.privacidade is CancelamentoExclusao
              ? () => _tentar(context, () async {
                    await (repos.privacidade! as CancelamentoExclusao).cancelarExclusao();
                    pedidosMudaram.value++;
                  })
              : null,
          aoAbrirTermos: () => abrirTermos(context),
          aoContaExcluida: () async {
            await sair(context);
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text(
                    'Pedido de exclusão agendado. Sua conta será excluída em 7 dias se você não cancelar. Você foi desconectado.',
                  ),
                ),
              );
            }
          },
        ),
      );

  /// Central de ajuda. "Falar com o suporte" só aparece se o servidor tem o e-mail do
  /// atendimento; "Relatar um problema" leva o cliente aos serviços, onde ele abre o relato.
  static Widget _telaAjuda(BuildContext context, {bool comoCliente = true, String? pedidoId}) {
    final email = ConfigPublica.atual.suporteEmail;
    return AjudaTela(
      servico: const ServicoAjudaLocal(),
      aoFalarComSuporte: email == null
          ? null
          : () async {
              final abriu = await abrirEmail(email, 'Ajuda com o Trato');
              if (!abriu && context.mounted) {
                _avisoSimples(context, 'Não achamos um app de e-mail. Escreva para $email.');
              }
            },
      // Com contexto de pedido o relato abre direto nele; sem contexto, a pessoa escolhe o serviço.
      aoRelatarProblema: !comoCliente
          ? null
          : pedidoId == null
              ? () => abrirServicos(context)
              : () => _abrir<void>(context, _relatarProblema(pedidoId)),
      aoRelatarBug: () => relatarBug(context, tela: 'Central de ajuda'),
      aoVerTour: () => _abrir<void>(
        context,
        TourPerfilTela(
          perfil: comoCliente ? PerfilUso.cliente : PerfilUso.profissional,
          registrarVisto: false,
          aoConcluir: () => Navigator.of(context).pop(),
        ),
      ),
    );
  }

  static final ServicoConta _contaDemo = ServicoContaFake();

  static final ServicoRecorrencias _recorrenciasDemo = ServicoRecorrenciasFake();
  static ServicoRecorrencias get _recorrencias => repos.recorrencias ?? _recorrenciasDemo;

  /// "Serviços recorrentes": a lista da conta (cliente ou profissional) e o detalhe de cada série.
  static void abrirRecorrencias(BuildContext context) => _abrir<void>(
        context,
        ServicosRecorrentesTela(
          servico: _recorrencias,
          aoAbrirPedido: (pedidoId, souCliente) => _abrirPedidoDaVisita(context, pedidoId, souCliente),
        ),
      );

  /// A visita da série é um pedido: o cliente abre o serviço (aceita o orçamento e paga); o
  /// profissional abre a conversa do pedido.
  static void _abrirPedidoDaVisita(BuildContext context, String pedidoId, bool souCliente) =>
      souCliente
          ? abrirServico(context, pedidoId)
          : _abrir<void>(context, _chat(pedidoId, comoProfissional: true));

  static var _propondoRecorrencia = false;

  /// "Repetir este serviço" num pedido concluído (cliente ou profissional): abre a folha de
  /// frequência, data da 1ª visita e valor, envia a proposta e abre a série criada.
  static Future<void> _repetirServico(
    BuildContext context,
    String pedidoId, {
    int? valorCentavos,
  }) async {
    if (_propondoRecorrencia) return;
    _propondoRecorrencia = true;
    try {
      final proposta = await mostrarFolhaRepetirServico(context, valorInicialCentavos: valorCentavos);
      if (proposta == null || !context.mounted) return;
      Recorrencia? criada;
      final ok = await _tentar(context, () async => criada = await _recorrencias.propor(pedidoId, proposta));
      final serie = criada;
      if (!ok || serie == null || !context.mounted) return;
      _avisoSimples(context, 'Proposta enviada. A outra pessoa precisa aceitar.');
      _abrir<void>(
        context,
        DetalheRecorrenciaTela(
          servico: _recorrencias,
          recorrenciaId: serie.id,
          inicial: serie,
          aoAbrirPedido: (id, souCliente) => _abrirPedidoDaVisita(context, id, souCliente),
        ),
      );
    } finally {
      _propondoRecorrencia = false;
    }
  }

  static final ServicoIndicacoes _indicacoesDemo = ServicoIndicacoesFake();
  static ServicoIndicacoes get _indicacoes => repos.indicacoes ?? _indicacoesDemo;

  /// "Indique e ganhe": meu código, resumo, lista e o campo de código de quem chegou por convite.
  static void abrirIndicacoes(BuildContext context, {int? valorMoedaCentavos}) => _abrir<void>(
        context,
        IndiqueEGanheTela(servico: _indicacoes, valorMoedaCentavos: valorMoedaCentavos),
      );
  static ServicoConta get _conta => repos.conta ?? _contaDemo;

  /// O que fica no Perfil do cliente: o que ele usa no dia a dia. O resto mora em Configurações.
  static const _acoesNoPerfil = {
    AcaoPerfil.enderecos,
    AcaoPerfil.favoritos,
    AcaoPerfil.indiqueEGanhe,
    AcaoPerfil.servicosRecorrentes,
    AcaoPerfil.usarComoProfissional,
  };

  @visibleForTesting
  static PerfilCliente soNoPerfilParaTeste(PerfilCliente p) => _soNoPerfil(p);

  static PerfilCliente _soNoPerfil(PerfilCliente p) {
    final itens = [
      for (final g in p.grupos)
        for (final i in g.itens)
          if (_acoesNoPerfil.contains(i.acao)) i,
    ];
    return PerfilCliente(
      nome: p.nome,
      iniciais: p.iniciais,
      resumo: p.resumo,
      fotoReferencia: p.fotoReferencia,
      moedas: p.moedas,
      moedasDescontoDisponivel: p.moedasDescontoDisponivel,
      moedasDescontoMotivo: p.moedasDescontoMotivo,
      moedasDescontoVoltaEm: p.moedasDescontoVoltaEm,
      moedasPendentes: p.moedasPendentes,
      moedasProximaLiberacao: p.moedasProximaLiberacao,
      moedasValorCentavos: p.moedasValorCentavos,
      exclusaoAgendadaEm: p.exclusaoAgendadaEm,
      grupos: itens.isEmpty ? const [] : [GrupoPerfil(titulo: 'CONTA', itens: itens)],
    );
  }

  /// Configurações da conta (engrenagem do Perfil), iguais para cliente e profissional. Formas de
  /// pagamento salvas ficam de fora: o cartão é guardado pelo Stripe, sem rota no Trato.
  static void abrirConfiguracoes(BuildContext context, {required bool profissional}) =>
      _abrir<void>(
        context,
        Builder(
          builder: (context) => ConfiguracoesTela(
            grupos: [
              GrupoConfiguracao(
                titulo: 'CONTA',
                itens: [
                  ItemContaPerfil(
                    icone: Icons.person_outline,
                    titulo: 'Dados pessoais',
                    aoTocar: () => _abrir<void>(
                      context,
                      DadosPessoaisTela(
                        servico: _conta,
                        servicoCep: repos.cep,
                        aoAlterarCredenciais: () =>
                            _abrir<void>(context, const SegurancaContaTela()),
                      ),
                    ),
                  ),
                  if (profissional && repos.mei != null)
                    ItemContaPerfil(
                      icone: Icons.badge_outlined,
                      titulo: 'Meu CNPJ',
                      aoTocar: () => abrirMeuCnpj(context),
                    ),
                  ItemContaPerfil(
                    icone: Icons.notifications_none,
                    titulo: 'Notificações',
                    aoTocar: () => abrirNotificacoes(context, profissional: profissional),
                  ),
                  ItemContaPerfil(
                    icone: Icons.tune,
                    titulo: 'Preferências de alertas',
                    aoTocar: () => _abrir<void>(
                      context,
                      PreferenciasNotificacoesTela(repositorio: repos.notificacoes),
                    ),
                  ),
                  ItemContaPerfil(
                    icone: Icons.shield_outlined,
                    titulo: 'Contatos de confiança',
                    aoTocar: () => _abrir<void>(context, ContatosConfiancaTela(servico: _conta)),
                  ),
                ],
              ),
              GrupoConfiguracao(
                titulo: 'PRIVACIDADE E AJUDA',
                itens: [
                  ItemContaPerfil(
                    icone: Icons.lock_outline,
                    titulo: 'Meus dados e excluir conta',
                    aoTocar: () => _abrirPrivacidade(context),
                  ),
                  ItemContaPerfil(
                    icone: Icons.help_outline,
                    titulo: 'Central de ajuda',
                    aoTocar: () =>
                        _abrir<void>(context, _telaAjuda(context, comoCliente: !profissional)),
                  ),
                  ItemContaPerfil(
                    icone: Icons.bug_report_outlined,
                    titulo: 'Relatar bug',
                    aoTocar: () => relatarBug(context, tela: 'Configurações'),
                  ),
                  ItemContaPerfil(
                    icone: Icons.description_outlined,
                    titulo: 'Termos e políticas',
                    aoTocar: () => abrirTermos(context),
                  ),
                ],
              ),
            ],
            aoSair: () => sair(context),
          ),
        ),
      );

  /// Aba "Mensagens" da casca do cliente: lista de conversas, cada uma abre o chat do pedido.
  static Widget abaMensagens() => emModoVisitante
      ? _telaVisitante(
          titulo: 'Suas conversas',
          texto: 'Entre ou crie uma conta para conversar com os profissionais.',
        )
      : Builder(
          builder: (context) => MensagensTela(
            servico: _servicoMensagens,
            atualizarACada: _intervalo,
            atualizarQuando: pedidosMudaram,
            aoContarNaoLidas: (n) => mensagensNaoLidas.value = n,
            aoAbrirConversa: (conversa) => _abrirConversa(context, conversa, _servicoMensagens),
          ),
        );

  /// Abre o chat e, ao voltar, marca a conversa como lida e atualiza a lista na hora (o contador
  /// de não lidas não pode ficar parado depois de ler).
  static Future<void> _abrirConversa(
    BuildContext context,
    ConversaResumo conversa,
    ServicoMensagens servico, {
    bool comoProfissional = false,
  }) async {
    await _abrir<void>(
      context,
      _chat(
        conversa.pedidoId,
        profissionalId: comoProfissional ? null : conversa.profissionalId,
        comoProfissional: comoProfissional,
        categoriaNome: conversa.tituloPedido,
      ),
    );
    if (servico is ServicoConversasApi) await servico.marcarLida(conversa);
    pedidosMudaram.value++;
  }

  static Widget _notificacoes({required bool profissional}) => Builder(
        builder: (context) => NotificacoesTela(
          servico: ServicoNotificacoesRepositorio(repos.notificacoes),
          atualizarACada: _intervalo,
          atualizarQuando: pedidosMudaram,
          aoContarNaoLidas: (n) => notificacoesNaoLidas.value = n,
          aoAbrirPreferencias: () => _abrir<void>(
            context,
            PreferenciasNotificacoesTela(repositorio: repos.notificacoes),
          ),
          aoAbrirDestino: (n) {
            // A MESMA tabela do push (`resultadoDoPush`): o que o backend manda em `data`.
            final r = destinoDaCaixa(n, modoAtualProfissional: profissional);
            if (r == null) return;
            DeepLinks.abrirDaCaixa(context, r, profissional: profissional);
          },
        ),
      );

  /// O destino de uma notificação da caixa. Com `tela` (como no push) usa a tabela do push; sem
  /// ela, deduz do tipo do evento. Sem destino, nulo.
  @visibleForTesting
  static ResultadoLink? destinoDaCaixa(notif.Notificacao n, {required bool modoAtualProfissional}) {
    final id = n.destinoId;
    final papelValido = n.papel == 'profissional' || n.papel == 'cliente' ? n.papel : null;
    // Retrabalho tem tela própria (agendar o atendimento), mesmo o backend dizendo `pedido`.
    if (id != null && _destinoDaNotificacao(n.tipo) == DestinoApp.retrabalho) {
      return ResultadoLink.valido(DestinoApp.retrabalho, id, papel: papelValido);
    }
    final tela = n.tela ?? _telaDoTipo(n.tipoApi);
    if (tela != null) {
      final r = resultadoDoPush({
        'tela': tela,
        'pedido_id': id,
        'recorrencia_id': n.recorrenciaId,
        'papel': n.papel,
      });
      if (r.situacao != SituacaoLink.ignorado) return r;
    }
    final destino = _destinoDaNotificacao(n.tipo);
    if (id == null || destino == null) return null;
    return ResultadoLink.valido(destino, id, papel: papelValido);
  }

  /// Sem `data.tela` (backend antigo): a tela do evento, igual à tabela do backend.
  static String? _telaDoTipo(String? tipo) => switch (tipo) {
        'pedido.novo' ||
        'pedido.direcionado' ||
        'pedido.urgente' ||
        'orcamento.recusado' ||
        'orcamento.nao_escolhido' ||
        'exclusividade.aceita' =>
          'pedido_aberto',
        'avaliacao.recebida' => 'avaliacao',
        _ => null,
      };

  static DestinoApp? _destinoDaNotificacao(TipoNotificacao tipo) => switch (tipo) {
        TipoNotificacao.disputa => DestinoApp.disputa,
        TipoNotificacao.retrabalho => DestinoApp.retrabalho,
        TipoNotificacao.orcamento => DestinoApp.orcamentos,
        TipoNotificacao.mensagem => DestinoApp.chat,
        TipoNotificacao.pedido || TipoNotificacao.pagamento => DestinoApp.pedido,
        TipoNotificacao.sistema => null,
      };

  /// O ÚNICO caminho que abre uma tela a partir de fora de uma tela: toque numa notificação e
  /// deep link. Só abre; nunca aceita, paga nem cancela. O que a pessoa pode ver quem decide é a
  /// API (403 e 404 viram "não encontrado" dentro de cada tela).
  static void abrirDestino(
    BuildContext context,
    DestinoApp destino,
    String? id, {
    required bool profissional,
  }) {
    if (destino == DestinoApp.indicacoes) {
      abrirIndicacoes(context);
      return;
    }
    if (destino == DestinoApp.recorrencia) {
      id == null
          ? abrirRecorrencias(context)
          : _abrir<void>(
              context,
              DetalheRecorrenciaTela(
                servico: _recorrencias,
                recorrenciaId: id,
                aoAbrirPedido: (pedidoId, souCliente) =>
                    _abrirPedidoDaVisita(context, pedidoId, souCliente),
              ),
            );
      return;
    }
    if (id == null) return;
    switch (destino) {
      case DestinoApp.disputa:
        profissional ? abrirDisputa(context, id) : abrirServico(context, id);
      case DestinoApp.retrabalho:
        profissional ? abrirRetrabalho(context, id) : abrirServico(context, id);
      case DestinoApp.orcamentos:
        profissional
            ? _abrir<void>(context, _chat(id, comoProfissional: true))
            : _abrir<void>(context, _orcamentosRecebidos(id));
      case DestinoApp.chat:
        _abrir<void>(context, _chat(id, comoProfissional: profissional));
      case DestinoApp.pedido:
        profissional
            ? _abrir<void>(context, _pedidoDoProfissional(id))
            : abrirServico(context, id);
      case DestinoApp.pedidoAberto:
        // Pedido novo, direcionado ou urgente: o profissional vê o pedido aberto para orçar.
        profissional
            ? _abrir<void>(context, _detalhePedidoAbertoProfissional(id))
            : abrirServico(context, id);
      case DestinoApp.avaliacao:
        profissional
            ? _abrir<void>(context, _pedidoDoProfissional(id))
            : abrirServico(context, id);
      case DestinoApp.recorrencia || DestinoApp.indicacoes:
        break;
    }
  }

  /// Pedido ainda aberto, do lado do profissional: o detalhe para orçar (a mesma tela da lista
  /// "Pedidos perto de você").
  static Widget _detalhePedidoAbertoProfissional(String pedidoId) => Carregador<DetalhePedido>(
        textoNaoEncontrado: TextosNaoEncontrado.pedido,
        carregar: () => repos.profissional.detalhe(pedidoId),
        construir: (context, dados) => DetalhePedidoTela(
          dados: dados,
          aoFazerOrcamento: () => _abrirOrcamento(
            context,
            pedidoId,
            dados.pedido.titulo,
            remoto: dados.pedido.remoto,
            categoriaId: dados.pedido.categoriaId,
          ),
          aoPerguntar: () => _abrir<void>(
            context,
            _chat(pedidoId, comoProfissional: true, categoriaNome: dados.pedido.titulo),
          ),
          aoPedirExclusividade: (chave) =>
              repos.profissional.solicitarExclusividade(pedidoId, chave),
          aoRecusar: (motivo) async {
            final navegador = Navigator.of(context);
            final ok = await _tentar(context, () => repos.profissional.recusar(pedidoId, motivo));
            if (!ok) return;
            pedidosMudaram.value++;
            if (navegador.mounted) navegador.pop();
          },
        ),
      );

  /// O pedido contratado do lado do profissional (abre pela notificação). Pedido ainda aberto vai
  /// para o detalhe de orçar; serviço concluído e sem avaliar, com [avaliar], para avaliar o
  /// cliente. Nunca a visão do cliente (pagar, avaliar o profissional).
  static Widget _pedidoDoProfissional(String pedidoId) =>
      Carregador<PedidoEmExecucao>(
        textoNaoEncontrado: TextosNaoEncontrado.pedido,
        carregar: () => repos.pedidos.acompanhar(pedidoId),
        atualizarQuando: pedidosMudaram,
        atualizarACada: _intervalo,
        construir: (context, pedido) {
          if (const {'aberto', 'reservado'}.contains(pedido.estadoApi)) {
            return _detalhePedidoAbertoProfissional(pedidoId);
          }
          return PedidoExecucaoTela(
            pedido: pedido,
            comoProfissional: true,
            atualizarAditivoLocalmente: false,
            aoConversar: () => _abrir<void>(
              context,
              _chat(pedidoId, comoProfissional: true, categoriaNome: pedido.categoriaNome ?? pedido.titulo),
            ),
            aoAjuda: () => _abrir<void>(context, _telaAjuda(context, comoCliente: false)),
            aoVerContrato: () => abrirContrato(context, pedidoId),
            // Serviço concluído e ainda não avaliado: "Avaliar cliente" como ação principal.
            aoAvaliar: () => _avaliarCliente(context, pedidoId),
            textoAvaliar: 'Avaliar cliente',
            secaoReagendamento: const {'pago_e_retido', 'agendado'}.contains(pedido.estadoApi)
                ? _secaoReagendamento(pedidoId, semHorario: pedido.estadoApi == 'pago_e_retido')
                : null,
          );
        },
      );

  /// A conta tem perfil de profissional? (Para um push que pede o modo profissional.)
  static Future<bool> usuarioTemPerfilProfissional() async {
    try {
      return repos.modoApi
          ? (await repos.perfilPublico?.temPerfilProfissional() ?? false)
          : ((ServicoAuthPadrao.atual.sessaoAtual?.ehProfissional == true) ||
              (await repos.perfilPublico?.temPerfilProfissional() ?? false));
    } on Object {
      return false;
    }
  }

  /// Abre o que um deep link pediu. Id inválido = "não encontrado", nunca erro.
  static void abrirLink(BuildContext context, ResultadoLink link, {bool? profissional}) {
    final destino = link.destino;
    if (destino == null || link.situacao == SituacaoLink.ignorado) return;
    if (link.situacao == SituacaoLink.invalido) {
      _abrir<void>(context, telaLinkInvalido(destino));
      return;
    }
    final comoProfissional = profissional ??
        (link.papel != null ? link.papel == 'profissional' : ControladorCasca.souProfissional);
    abrirDestino(context, destino, link.id, profissional: comoProfissional);
  }

  /// Aba "Buscar" do cliente: busca por serviço e abertura do perfil do profissional.
  static Widget abaBuscar() => Carregador<List<CategoriaServico>>(
        // Se o catálogo falhar, a busca por texto continua sem as sugestões de categoria.
        carregar: () => repos.catalogo.categorias().catchError((Object _) => <CategoriaServico>[]),
        atualizarQuando: pedidosMudaram,
        construir: (context, cats) {
          final ordenadas = [...cats]..sort((a, b) => compararAlfabeticoPtBr(a.nome, b.nome));
          return BuscaProfissionaisTela(
            servico: servicoBusca,
            sugestoes: [
              ...ordenadas.take(7),
              const CategoriaServico('Ver todas', Icons.grid_view),
            ],
            aoAbrirProfissional: (p) => abrirPerfil(context, p),
            aoEscolherCategoria: (c) => abrirCategoria(context, c),
            aoVerTodas: () => abrirTodasCategorias(context),
          );
        },
      );

  /// Aba "Pedidos" da casca do cliente.
  static Widget abaPedidos() => emModoVisitante
      ? _telaVisitante(
          titulo: 'Seus pedidos',
          texto: 'Entre ou crie uma conta para acompanhar seus pedidos e orçamentos.',
        )
      : Builder(
          builder: (context) => Scaffold(
            body: Carregador<PedidosDoCliente>(
              carregar: repos.pedidos.listar,
              atualizarQuando: pedidosMudaram,
              atualizarACada: _intervalo,
              vazio: (p) => p.vazio,
              tituloVazio: 'Você ainda não fez pedidos',
              textoVazio: 'Toque em "Novo pedido" para pedir um serviço.',
              construir: (_, p) => SeusPedidosTela(
                emAndamento: p.emAndamento,
                finalizados: p.finalizados,
                aoAbrirPedido: (pedido) => abrirPedido(context, pedido),
                aoFazerPedido: () => abrirNovoPedido(context),
              ),
            ),
            floatingActionButton: Padding(
              padding: EdgeInsets.only(bottom: BarraAbasFlutuante.folgaInferior(context)),
              child: FloatingActionButton.extended(
                key: const ValueKey('fab-novo-pedido'),
                backgroundColor: context.cores.petroleo,
                foregroundColor: context.cores.sobrePetroleo,
                icon: const Icon(Icons.add),
                label: const Text('Novo pedido'),
                onPressed: () => abrirNovoPedido(context),
              ),
            ),
          ),
        );

  // --- Cliente: pedido ---------------------------------------------------------------

  static Future<(FormularioPedido, List<EnderecoSalvo>)> _carregarNovoPedido(
    String categoriaId,
  ) =>
      emParalelo2(
        repos.catalogo.formulario(categoriaId),
        (temSessao && repos.conta != null)
            ? repos.conta!.enderecos().catchError((Object _) => <EnderecoSalvo>[])
            : Future.value(const <EnderecoSalvo>[]),
      );

  static Widget _novoPedido(
    CategoriaServico categoria, {
    Profissional? profissionalConvidado,
  }) {
    var enviandoPedido = false;
    return Carregador<(FormularioPedido, List<EnderecoSalvo>)>(
      carregar: () => _carregarNovoPedido(categoria.id),
      construir: (context, dados) => NovoPedidoTela(
        formulario: dados.$1,
        enderecosSalvos: dados.$2,
        servicoCep: repos.cep,
        profissionalConvidadoId: profissionalConvidado?.id,
        profissionalConvidadoNome: profissionalConvidado?.nome,
        aoCapturarFoto: _fotografar,
        aoTrocarCategoria: () => Navigator.of(context).pushReplacement(
          MaterialPageRoute<void>(
            builder: (_) => _escolherCategoria(
              profissionalConvidado: profissionalConvidado,
            ),
          ),
        ),
        aoEnviar: (rascunho) async {
          if (emModoVisitante || !temSessao) {
            rascunhoPendente = rascunho;
            showModalBottomSheet<void>(
              context: context,
              builder: (ctx) => SafeArea(
                child: Padding(
                  padding: const EdgeInsets.all(EspacosTrato.x5),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Falta pouco para enviar seu pedido', style: TipografiaTrato.titulo),
                      const SizedBox(height: EspacosTrato.x2),
                      Text(
                        'Crie sua conta ou entre para receber orçamentos dos profissionais.',
                        style: TipografiaTrato.corpoPequeno
                            .copyWith(color: CoresTrato.textoSecundario),
                      ),
                      const SizedBox(height: EspacosTrato.x4),
                      BotaoPrimario(
                        texto: 'Criar conta',
                        aoTocar: () {
                          Navigator.of(ctx).pop();
                          _abrir<void>(context, const CriarContaTela());
                        },
                      ),
                      const SizedBox(height: EspacosTrato.x2),
                      BotaoSecundario(
                        texto: 'Já tenho conta',
                        aoTocar: () {
                          Navigator.of(ctx).pop();
                          _abrir<void>(context, const LoginTela());
                        },
                      ),
                    ],
                  ),
                ),
              ),
            );
            return;
          }
          if (enviandoPedido) return;
          enviandoPedido = true;
          try {
            String? id;
            final ok = await _tentar(context, () async => id = await repos.pedidos.criar(rascunho));
            if (ok) pedidosMudaram.value++;
            if (!ok || id == null || !context.mounted) return;
            await _abrirSucesso<void>(
              context,
              (ctxSucesso) => SucessoAcaoTela(
                titulo: 'Pedido enviado!',
                subtitulo:
                    'Os profissionais de ${rascunho.modalidade.name == 'remoto' ? 'qualquer região' : 'sua região'} foram notificados e você já pode acompanhar os orçamentos.',
                textoBotaoPrimario: 'Ver pedidos',
                aoTocarPrimario: () => _voltarAoInicio(ctxSucesso, aba: 2),
                textoBotaoSecundario: 'Voltar ao início',
                aoVoltarInicio: () => _voltarAoInicio(ctxSucesso),
              ),
              substituirAtual: true,
            );
          } finally {
            enviandoPedido = false;
          }
        },
      ),
    );
  }

  static void abrirPedido(BuildContext context, PedidoResumo pedido) {
    final id = pedido.id ?? _semId;
    final estado = pedido.estadoApi;
    if (estado != null) {
      switch (estado) {
        case 'aberto' || 'reservado':
          _abrir<void>(context, _pedidoAberto(id));
        default:
          abrirServico(context, id);
      }
      return;
    }
    if (pedido.statusTexto.startsWith('Em execução')) {
      _abrir<void>(context, _pedidoEmExecucao(id));
    } else if (pedido.statusTexto.startsWith('Finalizado')) {
      abrirGarantia(context, pedidoId: id);
    } else if (pedido.statusTexto.contains('orçamentos recebidos')) {
      _abrir<void>(context, _orcamentosRecebidos(id));
    } else {
      abrirServico(context, pedido.id ?? _semId);
    }
  }

  /// Pedido aguardando orçamentos: o que foi descrito (editável) e a porta para os orçamentos.
  static Widget _pedidoAberto(String pedidoId) => Carregador<DadosDoPedido>(
        textoNaoEncontrado: TextosNaoEncontrado.pedido,
        carregar: () => repos.pedidos.dados(pedidoId),
        atualizarQuando: pedidosMudaram,
        construir: (context, dados) {
          var dadosAtuais = dados;
          return PedidoAbertoTela(
            numero: pedidoId.substring(0, pedidoId.length < 4 ? pedidoId.length : 4).toUpperCase(),
            dados: dados,
            servicoCep: repos.cep,
            cepInicial: dados.cep ?? '',
            aoVerOrcamentos: () => _abrir<void>(context, _orcamentosRecebidos(pedidoId)),
            aoCancelar: () => _cancelarPedido(context, pedidoId),
            aoResponderExclusividade: (eid, decisao) async {
              final resp = await repos.pedidos.responderExclusividade(pedidoId, eid, decisao);
              pedidosMudaram.value++;
              return resp;
            },
            aoSalvar: ({
              required String descricao,
              required int faixaMaxCentavos,
              required String logradouro,
              required String numero,
              required String bairro,
              String? cep,
            }) async {
              try {
                final ajustarMin = faixaMaxCentavos == 0 ||
                    (dadosAtuais.faixaMinCentavos != null &&
                        faixaMaxCentavos < dadosAtuais.faixaMinCentavos!);
                final novos = await repos.pedidos.editar(
                  pedidoId,
                  descricao: descricao,
                  faixaMinCentavos: ajustarMin ? 0 : null,
                  faixaMaxCentavos: faixaMaxCentavos,
                  cep: cep,
                  logradouro: logradouro,
                  numero: numero,
                  bairro: bairro,
                );
                dadosAtuais = novos;
                pedidosMudaram.value++;
                if (context.mounted) {
                  _avisoSimples(context, 'Pedido atualizado. Os profissionais já veem a mudança.');
                }
                return novos;
              } on Object catch (erro) {
                if (context.mounted) _aviso(context, erro);
                return null;
              }
            },
          );
        },
      );

  static Widget _orcamentosRecebidos(String pedidoId) => Carregador<OrcamentosDoPedido>(
        textoNaoEncontrado: TextosNaoEncontrado.orcamento,
        carregar: () => repos.orcamentos.listar(pedidoId),
        atualizarQuando: pedidosMudaram,
        atualizarACada: _intervalo,
        vazio: (o) => o.orcamentos.isEmpty,
        tituloVazio: 'Ainda sem orçamentos',
        textoVazio: 'Avisamos quando os profissionais responderem.',
        textoAcaoVazio: 'Atualizar',
        construir: (context, dados) {
          // Já há orçamento aceito: os outros ficam só para leitura (aceitar/recusar dá 409).
          final jaTemAceito = dados.orcamentos.any((o) => o.aceito);
          return OrcamentosRecebidosTela(
            pedido: dados.pedido,
            orcamentos: dados.orcamentos,
            aoVerOrcamento: (orcamento) => _abrir<void>(
              context,
              // O protótipo só traz o detalhe de alguns orçamentos.
              orcamento.detalhe == null
                  ? _PerfilAoAbrir(orcamento: orcamento)
                  : _DetalheOrcamentoAtualizado(
                      pedidoId: pedidoId,
                      inicial: orcamento,
                      construir: (orcamento) => orcamento.aceito || jaTemAceito
                          ? DetalheOrcamentoTela(
                              orcamento: orcamento,
                              contrato: orcamento.aceito,
                              somenteLeitura: !orcamento.aceito,
                              aoVerPerfil: (o) => abrirPerfilDoOrcamento(context, o),
                              aoVerTermos: () => abrirTermos(context),
                              aoConversar: (o) => _abrir<void>(
                                context,
                                _chat(
                                  pedidoId,
                                  profissionalId: o.profissionalId,
                                  comoProfissional: false,
                                ),
                              ),
                            )
                          : DetalheOrcamentoTela(
                              orcamento: orcamento,
                              aoVerPerfil: (o) => abrirPerfilDoOrcamento(context, o),
                              aoConversar: (o) => _abrir<void>(
                                context,
                                _chat(
                                  pedidoId,
                                  profissionalId: o.profissionalId,
                                  comoProfissional: false,
                                ),
                              ),
                              aoFazerContraproposta: (o) async {
                                final proposta = await pedirContrapropostaCompleta(
                                  context,
                                  atualCentavos: o.totalCentavos,
                                );
                                if (proposta == null || !context.mounted) return;
                                final ok = await _tentar(
                                  context,
                                  () => repos.orcamentos.contraproporValor(
                                    pedidoId,
                                    o.id,
                                    proposta.valorCentavos,
                                    prazoExecucaoDias: proposta.prazoExecucaoDias,
                                    mensagem: proposta.mensagem,
                                  ),
                                );
                                if (ok && context.mounted) {
                                  pedidosMudaram.value++;
                                  await _abrirSucesso<void>(
                                    context,
                                    (ctxSucesso) => SucessoAcaoTela(
                                      titulo: 'Contraproposta enviada!',
                                      subtitulo:
                                          'O profissional recebeu sua proposta na conversa e pode aceitar ou responder.',
                                      textoBotaoPrimario: 'Abrir conversa',
                                      aoTocarPrimario: () =>
                                          Navigator.of(ctxSucesso).pushReplacement(
                                        MaterialPageRoute<void>(
                                          builder: (_) => _chat(pedidoId,
                                              profissionalId: o.profissionalId,
                                              comoProfissional: false),
                                        ),
                                      ),
                                      textoBotaoSecundario: 'Voltar ao início',
                                      aoVoltarInicio: () => _voltarAoInicio(ctxSucesso),
                                    ),
                                  );
                                }
                              },
                              aoRecusar: (o) async {
                                final ok = await _tentar(
                                  context,
                                  () => repos.orcamentos.recusar(pedidoId, o.id),
                                );
                                if (ok && context.mounted) {
                                  pedidosMudaram.value++;
                                  Navigator.of(context).pop();
                                  _avisoSimples(context, 'Orçamento recusado.');
                                }
                              },
                              aoAceitar: (o) async {
                                // Só pede ao backend; taxa e líquido são dele.
                                final ok = await _tentar(
                                  context,
                                  () => repos.orcamentos.aceitar(pedidoId, o.id),
                                );
                                if (ok && context.mounted) {
                                  pedidosMudaram.value++;
                                  _abrir<void>(context, _pagamento(pedidoId));
                                }
                              },
                            ),
                    ),
            ),
          );
        },
      );

  /// Cartão do aditivo: abre a folha do provedor e espera o backend confirmar (webhook).
  static Future<void> _pagarAditivo(
    BuildContext context,
    String pedidoId,
    Cobranca cobranca,
  ) async {
    if (!context.mounted) return;
    if (cobranca.precisaDaFolhaDeCartao) {
      ResultadoCartao? resultado;
      final aberto = await _tentar(
        context,
        () async => resultado = await folhaCartao.pagar(
          PreparoFolhaCartao(
            segredoDoPagamento: cobranca.segredoCartao!,
            clienteId: cobranca.clienteCartaoId!,
            chaveEfemera: cobranca.chaveEfemera!,
          ),
        ),
      );
      if (!aberto || !context.mounted) return;
      if (resultado == ResultadoCartao.cancelado) {
        _avisoSimples(context,
            'Pagamento cancelado. A cobrança extra continua pendente; abra o aditivo de novo.');
        return;
      }
    }
    _abrir<void>(
      context,
      AguardandoPagamentoTela(
        cobranca: cobranca,
        consultar: () => servicoAditivo.statusDoPagamento(pedidoId),
        aoConfirmar: () => Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute<void>(builder: (_) => _pedidoEmExecucao(pedidoId)),
          (rota) => rota.isFirst,
        ),
      ),
    );
  }

  @visibleForTesting
  static Widget pagamentoParaTeste(String pedidoId) => _pagamento(pedidoId);

  /// Para teste: roda uma ação como as telas de ação do app (aviso humano se faltar internet).
  @visibleForTesting
  static Future<bool> tentarParaTeste(BuildContext context, Future<void> Function() acao) =>
      _tentar(context, acao);

  @visibleForTesting
  static Future<void> baixarReciboPdfParaTeste(BuildContext context, String pedidoId) =>
      _baixarReciboPdf(context, pedidoId);

  static Widget _pagamento(String pedidoId) {
    // "Tentar de novo" (sem forma de pagamento): o Carregador refaz a mesma chamada em silêncio.
    final recarregar = ValueNotifier<int>(0);
    var iniciandoPagamento = false;
    var usarMoedas = false; // o que o cliente escolheu; quantas moedas entram, o backend decide
    return Carregador<DadosPagamento>(
      textoNaoEncontrado: TextosNaoEncontrado.pedido,
      carregar: () => repos.pagamento.dados(pedidoId),
      atualizarQuando: recarregar,
      construir: (context, dados) => PagamentoTela(
        aoTentarNovamente: () => recarregar.value++,
        dados: dados,
        aoAplicarCupom: (codigo) =>
            repos.pagamento.recalcular(pedidoId, cupom: codigo, usarMoedas: usarMoedas),
        aoAlternarMoedas: (usar, cupom) {
          usarMoedas = usar;
          return repos.pagamento.recalcular(pedidoId, cupom: cupom, usarMoedas: usar);
        },
        aoCadastrarCpf: repos.pagamento.cadastrarCpf,
        aoPagarDetalhado: (metodo, parcelas, cupom) async {
          if (iniciandoPagamento) return;
          iniciandoPagamento = true;
          try {
            Cobranca? cobranca;
            var ok = false;
            try {
              cobranca = await repos.pagamento.criarCobranca(
                pedidoId,
                metodo,
                parcelas: parcelas,
                cupom: cupom,
                usarMoedas: usarMoedas,
              );
              ok = true;
            } on ErroTrato catch (erro) {
              if (erro.codigo == 'cpf_obrigatorio') rethrow;
              if (context.mounted) _aviso(context, erro);
            } on Object catch (erro) {
              if (context.mounted) _aviso(context, erro);
            }
            if (!ok || !context.mounted) return;
            // Cartão: a folha do provedor lista os cartões salvos e cadastra um novo. O app só
            // abre a folha; quem diz "pago" continua sendo o backend.
            final c = cobranca;
            if (metodo == MetodoPagamento.cartao && c != null && c.precisaDaFolhaDeCartao) {
              ResultadoCartao? resultado;
              final aberto = await _tentar(
                context,
                () async => resultado = await folhaCartao.pagar(
                  PreparoFolhaCartao(
                    segredoDoPagamento: c.segredoCartao!,
                    clienteId: c.clienteCartaoId!,
                    chaveEfemera: c.chaveEfemera!,
                  ),
                ),
              );
              if (!aberto || !context.mounted) return;
              if (resultado == ResultadoCartao.cancelado) {
                _avisoSimples(context, 'Pagamento cancelado. Você pode escolher outro cartão.');
                return;
              }
            }
            // O app fica esperando; quem diz "pago" é o backend.
            _abrir<void>(
              context,
              AguardandoPagamentoTela(
                cobranca: cobranca,
                consultar: () => repos.pagamento.status(pedidoId),
                // Pago (confirmado pelo backend): mostra o pedido em andamento.
                aoConfirmar: () => Navigator.of(context).pushAndRemoveUntil(
                  MaterialPageRoute<void>(builder: (_) => _pedidoEmExecucao(pedidoId)),
                  (rota) => rota.isFirst,
                ),
              ),
            );
          } finally {
            iniciandoPagamento = false;
          }
        },
      ),
    );
  }

  /// O contrato do serviço é o orçamento que o cliente aceitou (escopo, valor e garantia).
  static void abrirContrato(BuildContext context, String pedidoId) => _abrir<void>(
        context,
        Carregador<(Orcamento?, DadosContrato)>(
          textoNaoEncontrado: TextosNaoEncontrado.pedido,
          carregar: () async {
            final (todos, contrato) = await emParalelo2(
              repos.orcamentos.listar(pedidoId),
              repos.pedidos.contrato(pedidoId),
            );
            final aceito = todos.orcamentos.where((o) => o.aceito && o.detalhe != null).firstOrNull;
            return (aceito, contrato);
          },
          vazio: (x) => x.$1 == null,
          tituloVazio: 'Contrato indisponível',
          textoVazio: 'Não encontramos o orçamento aceito deste pedido.',
          construir: (context, x) => DetalheOrcamentoTela(
            orcamento: x.$1!,
            contrato: true,
            dadosContrato: x.$2,
            aoVerPerfil: (o) => abrirPerfilDoOrcamento(context, o),
            aoVerTermos: () => abrirTermos(context),
          ),
        ),
      );

  static void abrirGarantia(BuildContext context, {String pedidoId = _semId}) => _abrir<void>(
        context,
        Carregador<DadosGarantia>(
          textoNaoEncontrado: TextosNaoEncontrado.pedido,
          carregar: () => repos.pedidos.garantia(pedidoId),
          atualizarQuando: pedidosMudaram,
          construir: (context, dados) => GarantiaTela(
            dados: dados,
            aoPedirRetrabalho: () => _pedirRetrabalho(context, pedidoId),
            aoVerContrato: () => abrirContrato(context, pedidoId),
          ),
        ),
      );

  static Future<void> _responderAditivoInline(
    BuildContext context,
    String pedidoId, {
    required bool aprovar,
  }) async {
    if (!aprovar) {
      final confirma = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('Recusar o aditivo?'),
          content: const Text('O serviço segue pelo valor combinado antes.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Voltar')),
            TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('Recusar')),
          ],
        ),
      );
      if (confirma != true || !context.mounted) return;
      final ok = await _tentar(
        context,
        () => servicoAditivo.responder(pedidoId, aprovar: false),
      );
      if (ok) pedidosMudaram.value++;
      return;
    }
    Cobranca? cobranca;
    final ok = await _tentar(
      context,
      () async => cobranca = await servicoAditivo.responder(pedidoId, aprovar: true),
    );
    if (!ok || !context.mounted) return;
    pedidosMudaram.value++;
    if (cobranca != null) await _pagarAditivo(context, pedidoId, cobranca!);
  }

  static Future<void> _pedirRetrabalho(BuildContext context, String pedidoId) async {
    final pedido = await showDialog<({String descricao, List<String> fotos})>(
      context: context,
      builder: (_) => const _DialogoPedirRetrabalho(),
    );
    if (pedido == null || pedido.descricao.isEmpty || !context.mounted) return;
    final ok = await _tentar(context,
        () => repos.pedidos.pedirRetrabalho(pedidoId, pedido.descricao, fotos: pedido.fotos));
    if (ok && context.mounted) {
      pedidosMudaram.value++;
      await _abrirSucesso<void>(
        context,
        (ctxSucesso) => SucessoAcaoTela(
          titulo: 'Pedido de retrabalho enviado!',
          subtitulo: 'O profissional foi notificado para agendar o atendimento.',
          aoVoltarInicio: () => _voltarAoInicio(ctxSucesso),
        ),
      );
    }
  }

  static Future<void> _sugerirOuRemarcarVisitaCliente(
    BuildContext context,
    String pedidoId, {
    required bool jaAgendado,
  }) async {
    final inicio = await _escolherJanelaVisita(
      context,
      tituloDia: jaAgendado ? 'Novo dia da visita' : 'Sugerir dia da visita',
    );
    if (inicio == null || !context.mounted) return;
    final fim = inicio.add(const Duration(hours: 2));
    if (jaAgendado) {
      await proporNovaDataDoPedido(context, pedidoId, inicio, fim);
      return;
    }
    final ok = await _tentar(context, () => repos.chat.proporAgenda(pedidoId, inicio, fim));
    if (ok) pedidosMudaram.value++;
    if (ok && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Sugestão de horário enviada no chat para confirmação do profissional.'),
        ),
      );
    }
  }

  static Widget _pedidoEmExecucao(String pedidoId) => Carregador<PedidoEmExecucao>(
        textoNaoEncontrado: TextosNaoEncontrado.pedido,
        carregar: () => repos.pedidos.acompanhar(pedidoId),
        atualizarQuando: pedidosMudaram,
        atualizarACada: _intervalo,
        // Aguardando orçamentos continua na tela do pedido aberto (editar, exclusividade).
        construir: (context, pedido) => const {'aberto', 'reservado'}.contains(pedido.estadoApi)
            ? _pedidoAberto(pedidoId)
            : PedidoExecucaoTela(
                pedido: pedido,
                atualizarAditivoLocalmente: false,
                aoPagar: () => _abrir<void>(context, _pagamento(pedidoId)),
                aoAvaliar: () => _abrir<void>(context, _avaliacao(pedidoId)),
                aoVerGarantia: () => abrirGarantia(context, pedidoId: pedidoId),
                aoBaixarComprovante: () => _baixarReciboPdf(context, pedidoId),
                aoRepetirServico: () => _repetirServico(
                  context,
                  pedidoId,
                  valorCentavos: pedido.totalAtualizadoCentavos ?? pedido.orcamentoCentavos,
                ),
                secaoReagendamento: const {'pago_e_retido', 'agendado'}.contains(pedido.estadoApi)
                    ? _secaoReagendamento(pedidoId, semHorario: pedido.estadoApi == 'pago_e_retido')
                    : null,
                aoAprovarAditivo: () => _responderAditivoInline(context, pedidoId, aprovar: true),
                aoRecusarAditivo: () => _responderAditivoInline(context, pedidoId, aprovar: false),
                aoConversar: () => _abrir<void>(
                  context,
                  _chat(
                    pedidoId,
                    comoProfissional: false,
                    categoriaNome: pedido.categoriaNome ?? pedido.titulo,
                  ),
                ),
                aoVerConclusao: () => _abrir<void>(context, _conclusao(pedidoId)),
                aoRemarcarVisita: const {'pago_e_retido', 'agendado'}.contains(pedido.estadoApi)
                    ? () => _sugerirOuRemarcarVisitaCliente(
                          context,
                          pedidoId,
                          jaAgendado: pedido.estadoApi == 'agendado',
                        )
                    : null,
                aoVerNota: () => _abrir<void>(
                  context,
                  VerNotaTela(servico: servicoNota, pedidoId: pedidoId),
                ),
                // Sem rota de aditivo por pedido: o id do pedido faz de id do aditivo na demonstração.
                aoVerAditivo: () => _abrir<void>(
                  context,
                  ResponderAditivoTela(
                    servico: servicoAditivo,
                    aditivoId: pedidoId,
                    // Aprovou: o cliente paga a cobrança do aditivo (a do pedido já foi paga).
                    aoCobrancaCriada: (cobranca) => _pagarAditivo(context, pedidoId, cobranca),
                  ),
                ),
                aoVerContrato: () => abrirContrato(context, pedidoId),
                aoAbrirProblema: () => _abrir<void>(context, _relatarProblema(pedidoId)),
                aoCompartilharAtendimento: () => _compartilharAtendimento(context, pedido),
                aoSosEmergencia: () => _abrirSosEmergencia(context, _resumoAtendimento(pedido)),
                // Ajuda no atendimento: direto no "Relatar problema" deste pedido (sem escolher serviço).
                aoAjuda: () => _abrir<void>(context, _relatarProblema(pedidoId)),
                aoCancelarPedido:
                    pedido.podeVerConclusao ? null : () => _cancelarPedido(context, pedidoId),
              ),
      );

  static String _resumoAtendimento(PedidoEmExecucao pedido) => [
        'Atendimento Trato (${pedido.numero})',
        if ((pedido.profissionalNome ?? '').isNotEmpty) 'Profissional: ${pedido.profissionalNome}',
        if ((pedido.visita ?? '').isNotEmpty) 'Horário: ${pedido.visita}',
        if ((pedido.enderecoResumo ?? '').isNotEmpty) 'Endereço: ${pedido.enderecoResumo}',
      ].join('\n');

  static Future<void> _compartilharAtendimento(
    BuildContext context,
    PedidoEmExecucao pedido,
  ) async {
    final resumo = _resumoAtendimento(pedido);
    await showModalBottomSheet<void>(
      context: context,
      builder: (folha) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(EspacosTrato.x5),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Compartilhar atendimento', style: TipografiaTrato.titulo),
              const SizedBox(height: EspacosTrato.x3),
              Text(resumo, style: TipografiaTrato.corpo),
              const SizedBox(height: EspacosTrato.x4),
              BotaoPrimario(
                texto: 'Compartilhar agora',
                aoTocar: () async {
                  Navigator.of(folha).pop();
                  await compartilharNoAparelho(resumo);
                },
              ),
              const SizedBox(height: EspacosTrato.x2),
              BotaoSecundario(
                texto: 'Contatos de confiança',
                aoTocar: () {
                  Navigator.of(folha).pop();
                  _abrir<void>(context, ContatosConfiancaTela(servico: _conta));
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  static Future<void> _abrirSosEmergencia(BuildContext context, String resumo) async {
    await showDialog<void>(
      context: context,
      builder: (dialogo) => AlertDialog(
        title: const Text('SOS / Emergência'),
        content: Text(
          'Em caso de risco, ligue para 190 ou copie os dados do atendimento para enviar a um contato de confiança.\n\n$resumo',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogo).pop(),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: resumo));
              if (dialogo.mounted) Navigator.of(dialogo).pop();
              if (context.mounted) {
                _avisoSimples(context, 'Dados do atendimento copiados.');
              }
            },
            child: const Text('Copiar dados'),
          ),
          FilledButton(
            onPressed: () async {
              Navigator.of(dialogo).pop();
              await launchUrl(
                Uri(scheme: 'tel', path: '190'),
                mode: LaunchMode.externalApplication,
              );
            },
            child: const Text('Ligar 190'),
          ),
        ],
      ),
    );
  }

  /// Só para testes do fluxo real do chat (profissional e cliente).
  static Widget chatParaTeste(
    String pedidoId, {
    String? profissionalId,
    bool? comoProfissional,
    String? categoriaNome,
  }) =>
      _chat(
        pedidoId,
        profissionalId: profissionalId,
        comoProfissional: comoProfissional,
        categoriaNome: categoriaNome,
      );

  static Widget _chat(
    String pedidoId, {
    String? profissionalId,
    bool? comoProfissional,
    String? categoriaNome,
  }) {
    final categoriaFallback = categoriaNome?.trim();
    Future<ConversaPedido> carregarConversa() async {
      final conversa = await repos.chat.conversa(pedidoId, profissionalId: profissionalId);
      final temCategoria = conversa.categoriaNome?.trim().isNotEmpty ?? false;
      final categoriaFinal = temCategoria
          ? conversa.categoriaNome
          : ((categoriaFallback != null && categoriaFallback.isNotEmpty)
              ? categoriaFallback
              : null);
      final souClienteFinal = comoProfissional != null ? !comoProfissional : conversa.souCliente;
      if (categoriaFinal == conversa.categoriaNome && souClienteFinal == conversa.souCliente) {
        return conversa;
      }
      return conversa.comContexto(
        categoriaNome: categoriaFinal,
        souCliente: souClienteFinal,
      );
    }

    return Carregador<ConversaPedido>(
      textoNaoEncontrado: TextosNaoEncontrado.conversa,
      carregar: carregarConversa,
      atualizarQuando: pedidosMudaram,
      construir: (context, conversa) {
        final ehPro = comoProfissional ??
            (!conversa.souCliente ||
                (!repos.modoApi && ServicoAuthPadrao.atual.sessaoAtual?.ehProfissional == true));
        final sit = conversa.situacao.toLowerCase();
        final podeCombinarAgenda = !conversa.pedidoAberto &&
            !conversa.remoto &&
            (sit.contains('pago') || sit.contains('agend'));
        final idProChat = profissionalId ?? conversa.usuarioId;
        final VoidCallback? aoAbrirPerfilChat = ehPro
            ? (repos.modoApi
                ? () => showModalBottomSheet<void>(
                      context: context,
                      builder: (_) => FolhaResumoPerfilCliente(
                        carregar: () => repos.chat.perfilClienteDoPedido(pedidoId),
                        nomeFallback: conversa.nome,
                        iniciaisFallback: conversa.iniciais,
                      ),
                    )
                : null)
            : ((idProChat != null && idProChat.isNotEmpty)
                ? () => abrirPerfil(
                      context,
                      Profissional(
                        id: idProChat,
                        nome: conversa.nome,
                        iniciais: conversa.iniciais,
                        verificacao: '',
                        especialidade: '',
                        servicosConcluidos: 0,
                        nota: 0,
                        distanciaKm: 0,
                      ),
                    )
                : null);
        return ChatPedidoTela(
          conversa: conversa,
          aoAbrirPerfil: aoAbrirPerfilChat,
          aoDenunciar: (conversa.usuarioId == null || conversa.usuarioId!.isEmpty)
              ? null
              : () => denunciar(
                    context,
                    alvoTipo: 'chat',
                    denunciadoId: conversa.usuarioId!,
                    pedidoId: pedidoId,
                  ),
          aoCapturarFoto: _fotografar,
          aoRecarregar: repos.modoApi ? carregarConversa : null,
          aoSugerirAgenda: podeCombinarAgenda
              ? () async {
                  final inicio = await _escolherJanelaVisita(
                    context,
                    tituloDia: 'Sugerir dia da visita',
                  );
                  if (inicio == null || !context.mounted) return;
                  final ok = await _tentar(
                    context,
                    () => repos.chat.proporAgenda(
                      pedidoId,
                      inicio,
                      inicio.add(const Duration(hours: 2)),
                    ),
                  );
                  if (ok && context.mounted) {
                    pedidosMudaram.value++;
                    _avisoSimples(context, 'Sugestão de horário enviada no chat.');
                  }
                }
              : null,
          aoAceitarAgenda: (msg) async {
            final prop = msg.propostaAgenda;
            if (prop == null) return;
            final ok = await _tentar(
              context,
              () => repos.chat.aceitarAgenda(
                pedidoId,
                mensagemId: msg.id,
                inicio: prop.inicio,
                fim: prop.fim,
              ),
            );
            if (ok && context.mounted) {
              pedidosMudaram.value++;
              _avisoSimples(context, 'Horário confirmado! Visita agendada.');
            }
          },
          aoAceitarContraproposta: (c) async {
            final ok = await _tentar(
              context,
              () => repos.orcamentos.aceitarContraproposta(
                pedidoId,
                c.orcamentoId,
                c.valorCentavos,
                prazoExecucaoDias: c.prazoExecucaoDias,
              ),
            );
            if (ok && context.mounted) {
              pedidosMudaram.value++;
              _avisoSimples(context, 'Orçamento atualizado com o valor e prazo combinados.');
            }
          },
          aoAceitarProposta: (c) async {
            final ok = await _tentar(
              context,
              () async {
                try {
                  await repos.orcamentos.aceitar(pedidoId, c.orcamentoId);
                } on ErroTrato catch (e) {
                  if (!e.mensagem.toLowerCase().contains('aceit')) rethrow;
                }
              },
            );
            if (ok && context.mounted) {
              pedidosMudaram.value++;
              _abrir<void>(context, _pagamento(pedidoId));
            }
          },
          aoProporNovaCondicao: (ehPro && conversa.orcamentosAtivos.isNotEmpty)
              ? () async {
                  final prop = await pedirNovaPropostaProfissional(context);
                  if (prop == null || !context.mounted) return;
                  final ok = await _tentar(
                    context,
                    () => repos.orcamentos.proporNovaCondicao(
                      pedidoId,
                      conversa.orcamentosAtivos.first,
                      prop.valorCentavos,
                      prazoExecucaoDias: prop.prazoExecucaoDias,
                      mensagem: prop.mensagem,
                    ),
                  );
                  if (ok && context.mounted) {
                    pedidosMudaram.value++;
                    _avisoSimples(context, 'Nova proposta enviada ao cliente.');
                  }
                }
              : null,
          aoEnviar: (texto) async {
            final ok = await _tentar(
              context,
              () => repos.chat.enviar(pedidoId, texto, profissionalId: profissionalId),
            );
            if (!ok) throw StateError('Falha ao enviar mensagem');
          },
          // Com chave: sem internet a mensagem espera e sai sozinha depois, sem duplicar.
          aoEnviarIdempotente: (texto, chave) async {
            try {
              await repos.chat.enviar(
                pedidoId,
                texto,
                profissionalId: profissionalId,
                chaveIdempotencia: chave,
              );
            } on ErroTrato catch (e) {
              if (e.tipo == TipoErro.semInternet) rethrow;
              if (context.mounted) _aviso(context, e);
              throw StateError('Falha ao enviar mensagem');
            } on Object catch (e) {
              // Qualquer outra falha também avisa: a mensagem nunca some calada.
              if (context.mounted) _aviso(context, e);
              rethrow;
            }
          },
          aoEnviarFoto: (ref) async {
            final ok = await _tentar(
              context,
              () => repos.chat.enviarFoto(pedidoId, ref, profissionalId: profissionalId),
            );
            if (!ok) throw StateError('Falha ao enviar foto');
          },
        );
      },
    );
  }

  static Widget _conclusao(String pedidoId) => Carregador<ResumoConclusao>(
        textoNaoEncontrado: TextosNaoEncontrado.pedido,
        carregar: () => repos.pedidos.conclusao(pedidoId),
        atualizarQuando: pedidosMudaram,
        construir: (context, resumo) => ConclusaoTela(
          resumo: resumo,
          aoConfirmar: () async {
            final ok = await _tentar(context, () => repos.pedidos.confirmarConclusao(pedidoId));
            if (ok && context.mounted) {
              pedidosMudaram.value++;
              _abrir<void>(context, _avaliacao(pedidoId));
            }
          },
          aoRelatarProblema: () => _abrir<void>(context, _relatarProblema(pedidoId)),
        ),
      );

  static Widget _avaliacao(String pedidoId) => Carregador<DadosAvaliacao>(
        textoNaoEncontrado: TextosNaoEncontrado.pedido,
        carregar: () => repos.pedidos.dadosAvaliacao(pedidoId),
        construir: (context, dados) => AvaliacaoTela(
          dados: dados,
          aoEnviar: (envio) async {
            var moedas = 0;
            final ok = await _tentar(context, () async {
              moedas = await repos.pedidos.avaliar(pedidoId, envio);
            });
            if (ok && context.mounted) {
              pedidosMudaram.value++;
              // Tratinhos em espera e valor de cada um: extras; se falhar, só não mostra a linha.
              PerfilCliente? saldo;
              if (moedas > 0) {
                try {
                  saldo = await repos.perfil.carregar();
                } on Object {
                  saldo = null;
                }
              }
              if (!context.mounted) return true;
              await _abrirSucesso<void>(
                context,
                (ctxSucesso) => moedas > 0
                    ? MoedasGanhasTela(
                        moedas: moedas,
                        pendentes: saldo?.moedasPendentes ?? 0,
                        proximaLiberacao: saldo?.moedasProximaLiberacao,
                        valorMoedaCentavos: saldo?.moedasValorCentavos,
                        aoContinuar: () => _voltarAoInicio(ctxSucesso),
                        acaoExtra: dados.profissionalId == null
                            ? null
                            : BotaoDeConfianca(
                                clara: true,
                                jaEFavorito: () async => (await _conta.favoritos())
                                    .any((f) => f.profissionalId == dados.profissionalId),
                                favoritar: () => _conta.favoritar(dados.profissionalId!),
                              ),
                      )
                    : SucessoAcaoTela(
                        titulo: 'Avaliação enviada!',
                        subtitulo: 'Obrigado por avaliar o profissional.',
                        aoVoltarInicio: () => _voltarAoInicio(ctxSucesso),
                        acaoExtra: dados.profissionalId == null
                            ? null
                            : BotaoDeConfianca(
                                jaEFavorito: () async => (await _conta.favoritos())
                                    .any((f) => f.profissionalId == dados.profissionalId),
                                favoritar: () => _conta.favoritar(dados.profissionalId!),
                              ),
                      ),
                substituirAtual: true,
              );
            }
            return ok;
          },
          aoAvaliarDepois: () => _voltarAoInicio(context),
        ),
      );

  static Widget _relatarProblema(String pedidoId) => Carregador<DadosRelatoProblema>(
        textoNaoEncontrado: TextosNaoEncontrado.pedido,
        carregar: () => repos.pedidos.dadosRelato(pedidoId),
        construir: (context, dados) => RelatarProblemaTela(
          dados: dados,
          aoCapturarFoto: _fotografar,
          aoEnviar: (relato) async {
            final ok =
                await _tentar(context, () => repos.pedidos.relatarProblema(pedidoId, relato));
            if (ok && context.mounted) {
              pedidosMudaram.value++;
              await _abrirSucesso<void>(
                context,
                (ctxSucesso) => SucessoAcaoTela(
                  titulo: 'Problema registrado!',
                  subtitulo:
                      'Nossa equipe e o profissional receberam seu relato. Você pode acompanhar pelo pedido.',
                  aoVoltarInicio: () => _voltarAoInicio(ctxSucesso),
                ),
                substituirAtual: true,
              );
            }
          },
        ),
      );
}

/// Diálogo com estado próprio para o `TextEditingController` ser descartado só quando a
/// animação de saída do `showDialog` terminar (evita erro `_dependents.isEmpty` no `EditableText`).
class _DialogoPedirRetrabalho extends StatefulWidget {
  const _DialogoPedirRetrabalho();

  @override
  State<_DialogoPedirRetrabalho> createState() => _DialogoPedirRetrabalhoState();
}

class _DialogoPedirRetrabalhoState extends State<_DialogoPedirRetrabalho> {
  final _controlador = TextEditingController();
  final _fotos = <String>[];
  String? _erro;

  @override
  void dispose() {
    _controlador.dispose();
    super.dispose();
  }

  Future<void> _adicionarFoto() async {
    final ref = await RotasTrato._fotografar();
    if (ref != null && mounted) setState(() => _fotos.add(ref));
  }

  void _enviar() {
    final texto = _controlador.text.trim();
    if (texto.isEmpty) {
      setState(() => _erro = 'Descreva o que precisa ser refeito.');
      return;
    }
    Navigator.of(context).pop((descricao: texto, fotos: [..._fotos]));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Pedir retrabalho'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _controlador,
              maxLines: 4,
              onChanged: (_) {
                if (_erro != null) setState(() => _erro = null);
              },
              decoration: InputDecoration(
                labelText: 'O que precisa ser refeito?',
                errorText: _erro,
              ),
            ),
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: _adicionarFoto,
              icon: const Icon(Icons.photo_camera_outlined),
              label: Text(_fotos.isEmpty
                  ? 'Adicionar foto'
                  : '${_fotos.length} ${_fotos.length == 1 ? 'foto' : 'fotos'} · adicionar outra'),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        TextButton(
          onPressed: _enviar,
          child: const Text('Enviar'),
        ),
      ],
    );
  }
}

class _DialogoCancelarPedido extends StatefulWidget {
  const _DialogoCancelarPedido();

  @override
  State<_DialogoCancelarPedido> createState() => _DialogoCancelarPedidoState();
}

class _DialogoCancelarPedidoState extends State<_DialogoCancelarPedido> {
  final _motivo = TextEditingController();
  String? _erro;

  @override
  void dispose() {
    _motivo.dispose();
    super.dispose();
  }

  void _confirmar() {
    final texto = _motivo.text.trim();
    if (texto.isEmpty) {
      setState(() => _erro = 'Informe o motivo do cancelamento.');
      return;
    }
    Navigator.of(context).pop(texto);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Cancelar o pedido?'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Conte o motivo. Se já houve pagamento, analisamos a devolução para você.'),
            const SizedBox(height: 8),
            TextField(
              controller: _motivo,
              maxLines: 3,
              onChanged: (_) {
                if (_erro != null) setState(() => _erro = null);
              },
              decoration: InputDecoration(
                labelText: 'Motivo do cancelamento',
                errorText: _erro,
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Voltar'),
        ),
        TextButton(
          onPressed: _confirmar,
          child: const Text('Cancelar pedido'),
        ),
      ],
    );
  }
}

/// Orçamento sem detalhe no protótipo: abre direto o perfil público do profissional e, ao
/// terminar, volta para a lista.
class _PerfilAoAbrir extends StatefulWidget {
  const _PerfilAoAbrir({required this.orcamento});

  final Orcamento orcamento;

  @override
  State<_PerfilAoAbrir> createState() => _PerfilAoAbrirState();
}

class _PerfilAoAbrirState extends State<_PerfilAoAbrir> {
  Timer? _relogio;
  bool _demorou = false;

  @override
  void initState() {
    super.initState();
    _abrir();
  }

  void _abrir() {
    _relogio?.cancel();
    setState(() => _demorou = false);
    _relogio = Timer(const Duration(seconds: 15), () {
      if (mounted) setState(() => _demorou = true);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      final navegador = Navigator.of(context);
      await RotasTrato.abrirPerfilDoOrcamento(context, widget.orcamento);
      if (mounted && (ModalRoute.of(context)?.isActive ?? false)) {
        navegador.pop();
      }
    });
  }

  @override
  void dispose() {
    _relogio?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(leading: const BackButton()),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (!_demorou) ...[
                  const CircularProgressIndicator(),
                  const SizedBox(height: 16),
                  const Text('Carregando, só um instante...'),
                ] else ...[
                  const Text(
                    'Está demorando mais que o normal. Verifique sua internet.',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: _abrir,
                    child: const Text('Tentar de novo'),
                  ),
                  TextButton(
                    onPressed: () => Navigator.of(context).maybePop(),
                    child: const Text('Voltar'),
                  ),
                ],
              ],
            ),
          ),
        ),
      );
}

/// Detalhe do orçamento que acompanha o servidor: se o profissional aceitar uma contraproposta
/// (ou mudar o orçamento), o valor e os itens na tela passam para a versão nova sozinhos.
class _DetalheOrcamentoAtualizado extends StatefulWidget {
  const _DetalheOrcamentoAtualizado({
    required this.pedidoId,
    required this.inicial,
    required this.construir,
  });

  final String pedidoId;
  final Orcamento inicial;
  final Widget Function(Orcamento orcamento) construir;

  @override
  State<_DetalheOrcamentoAtualizado> createState() => _DetalheOrcamentoAtualizadoState();
}

class _DetalheOrcamentoAtualizadoState extends State<_DetalheOrcamentoAtualizado> {
  late Orcamento _atual = widget.inicial;
  RelogioDeAtualizacao? _relogio;

  @override
  void initState() {
    super.initState();
    final intervalo = RotasTrato._intervalo;
    if (intervalo != null) {
      _relogio = RelogioDeAtualizacao(
        intervalo: intervalo,
        aoAtualizar: _atualizar,
        deveAtualizar: () => mounted && (ModalRoute.of(context)?.isCurrent ?? true),
      );
    }
  }

  @override
  void dispose() {
    _relogio?.parar();
    super.dispose();
  }

  Future<void> _atualizar() async {
    final dono = _atual.profissionalId;
    if (dono == null) return;
    final lista = await RotasTrato.repos.orcamentos.listar(widget.pedidoId);
    final novo = lista.orcamentos.where((o) => o.profissionalId == dono).firstOrNull;
    if (novo == null || !mounted) return;
    setState(() => _atual = novo);
  }

  @override
  Widget build(BuildContext context) => widget.construir(_atual);
}

/// Busca por texto ligada ao catálogo (modo `api`: demonstração até existir a rota de busca).
class _ServicoBuscaCatalogo implements ServicoBusca {
  const _ServicoBuscaCatalogo(this._catalogo);

  final RepositorioCatalogo _catalogo;

  @override
  Future<List<Profissional>> buscar(String termo, {bool disponivelAgora = false}) =>
      _catalogo.buscar(termo, disponivelAgora: disponivelAgora);
}

class _ServicoCadastroEdicao implements ServicoCadastroProfissional {
  const _ServicoCadastroEdicao(this._base, this._verificacao);

  final ServicoCadastroProfissional _base;
  final ServicoVerificacao? _verificacao;

  @override
  Future<OpcoesCadastro> carregarOpcoes() => _base.carregarOpcoes();

  @override
  Future<DadosCadastroProfissional?> carregarAtual() async {
    final atual = await _base.carregarAtual();
    if (atual == null || atual.categoriasTravadas || _verificacao == null) {
      return atual;
    }
    try {
      final sit = await _verificacao.carregarSituacao();
      if (sit.status == StatusVerificacao.emAnalise || sit.status == StatusVerificacao.aprovada) {
        return atual.comCategoriasTravadas(true);
      }
    } on Object {
      // Sem verificação consultável agora: mantém a sinalização do perfil.
    }
    return atual;
  }

  @override
  Future<void> salvar(DadosCadastroProfissional dados) => _base.salvar(dados);
}

class _AbaCarteiraPaginada extends StatefulWidget {
  const _AbaCarteiraPaginada({
    required this.aoAbrirItem,
    required this.aoConfigurarRecebimento,
    required this.aoBaixarExtratoPdf,
  });

  final void Function(BuildContext context, String pedidoId) aoAbrirItem;
  final Future<void> Function(BuildContext context, ContaRecebimento atual) aoConfigurarRecebimento;
  final Future<void> Function(BuildContext context) aoBaixarExtratoPdf;

  @override
  State<_AbaCarteiraPaginada> createState() => _AbaCarteiraPaginadaState();
}

class _AbaCarteiraPaginadaState extends State<_AbaCarteiraPaginada> {
  static const int _tamanhoPagina = 50;

  List<ItemExtrato> _itens = const [];
  ContaRecebimento _conta = const ContaRecebimento(cadastrada: false);
  DateTime? _proximaLiberacao;
  String? _tratinhosPendentes;
  (int, int, int)? _saldo; // liberado, retido, a liberar (como a API devolveu)
  Object? _erro;
  bool _iniciado = false;
  bool _carregando = false;
  bool _carregado = false;
  bool _carregandoMais = false;
  bool _temMais = false;
  bool _sujo = false;
  bool _visivel = true;
  int _geracao = 0;

  @override
  void initState() {
    super.initState();
    RotasTrato.pedidosMudaram.addListener(_aoMudarPedidos);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _visivel = TickerMode.valuesOf(context).enabled;
    if (!_iniciado && _visivel) {
      _iniciado = true;
      _carregarInicial();
    } else if (_visivel && _sujo && !_carregando) {
      _sujo = false;
      _carregarInicial(silencioso: _carregado);
    }
  }

  @override
  void dispose() {
    RotasTrato.pedidosMudaram.removeListener(_aoMudarPedidos);
    super.dispose();
  }

  void _aoMudarPedidos() {
    _sujo = true;
    if (_visivel && !_carregando) {
      _sujo = false;
      _carregarInicial(silencioso: _carregado);
    }
  }

  Future<void> _carregarInicial({bool silencioso = false}) async {
    final minha = ++_geracao;
    if (!silencioso) {
      setState(() {
        _carregando = true;
        _erro = null;
      });
    } else {
      _carregando = true;
    }
    try {
      final (itens, conta, extras) = await emParalelo3(
        RotasTrato.repos.profissional.extrato(
          limite: _tamanhoPagina,
          deslocamento: 0,
        ),
        RotasTrato.repos.profissional.obterContaRecebimento().catchError(
              (_) => const ContaRecebimento(cadastrada: false),
            ),
        // Extras da Carteira (data do repasse e Tratinhos pendentes): se falhar, só não aparecem.
        RotasTrato.repos.profissional.inicio().then<(DateTime?, String?, (int, int, int)?)>((i) {
          final ex = i.exclusividades;
          return (
            i.carteira.proximaLiberacao,
            ex == null
                ? null
                : textoTratinhosPendentes(
                    ex.moedasPendentesProfissional,
                    ex.moedasPendentesLiberacao,
                    ex.moedaValorCentavos,
                  ),
            (
              i.carteira.paraSacarCentavos,
              i.carteira.retidoDesdePagamentoCentavos ?? 0,
              i.carteira.retidoCentavos,
            ),
          );
        }).catchError((Object _) => (null, null, null)),
      );
      if (!mounted || minha != _geracao) return;
      setState(() {
        _itens = itens;
        _conta = conta;
        _proximaLiberacao = extras.$1;
        _tratinhosPendentes = extras.$2;
        _saldo = extras.$3;
        _erro = null;
        _temMais = itens.length >= _tamanhoPagina;
        _carregado = true;
        _carregando = false;
        _carregandoMais = false;
      });
    } on Object catch (erro) {
      if (!mounted || minha != _geracao) return;
      if (!_carregado || !silencioso) {
        setState(() {
          _erro = erro;
          _carregando = false;
        });
      } else {
        _carregando = false;
      }
    }
  }

  Future<void> _carregarMais() async {
    if (_carregandoMais || !_temMais) return;
    final minha = _geracao;
    setState(() => _carregandoMais = true);
    try {
      final novos = await RotasTrato.repos.profissional.extrato(
        limite: _tamanhoPagina,
        deslocamento: _itens.length,
      );
      if (!mounted || minha != _geracao) return;
      setState(() {
        _itens = [..._itens, ...novos];
        _temMais = novos.length >= _tamanhoPagina;
        _carregandoMais = false;
      });
    } on Object {
      if (!mounted || minha != _geracao) return;
      setState(() => _carregandoMais = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Não foi possível carregar mais lançamentos.'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_carregado && _erro == null) {
      return const EstadoTela(carregando: true);
    }
    if (_erro != null && !_carregado) {
      final erro = _erro;
      return RefreshIndicator(
        onRefresh: _carregarInicial,
        child: EstadoTela(
          texto: erro is ErroTrato ? erro.mensagem : 'Algo deu errado. Tente de novo em instantes.',
          aoTentarNovamente: _carregarInicial,
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: () => _carregarInicial(silencioso: true),
      child: CarteiraTela(
        soExtrato: false,
        dados: DadosCarteira(
          resumo: _saldo == null
              ? null
              : resumoCarteiraDoSaldo(
                  liberadoCentavos: _saldo!.$1,
                  retidoCentavos: _saldo!.$2,
                  aLiberarCentavos: _saldo!.$3,
                  proximaLiberacao: _proximaLiberacao,
                  conta: _conta,
                ),
          extrato: _itens,
          contaRecebimento: _conta,
          proximaLiberacao: _proximaLiberacao,
          tratinhosPendentesTexto: _tratinhosPendentes,
        ),
        aoAbrirItem: (item) => widget.aoAbrirItem(context, item.pedidoId!),
        aoConfigurarRecebimento: () => widget.aoConfigurarRecebimento(context, _conta),
        aoBaixarExtratoPdf: () => widget.aoBaixarExtratoPdf(context),
        aoCarregarMais: _carregarMais,
        temMaisExtrato: _temMais,
        carregandoMais: _carregandoMais,
      ),
    );
  }
}
