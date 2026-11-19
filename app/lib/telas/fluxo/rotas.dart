import 'dart:async';

import 'package:flutter/material.dart';

import '../agenda/modelos.dart' show EstadoAgendamento;
import '../../dados/carregador.dart';
import '../../dados/erros.dart';
import '../../dados/config_publica.dart';
import '../../dados/relogio_de_atualizacao.dart';
import '../../dispositivo/mapa.dart';
import '../../dados/repositorios.dart';
import '../../dispositivo/folha_cartao.dart';
import '../orcamentos/folha_contraproposta.dart';
import '../../auth/servico_auth.dart';
import '../../dados/repositorios_trato.dart';
import '../../dados/sessao.dart';
import '../auth/login_tela.dart';
import '../onboarding/escolha_perfil_tela.dart' show PerfilUso;
import '../../tema/tema.dart';
import '../../dispositivo/check_in_dispositivo.dart';
import '../../dispositivo/dispositivo.dart';
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
import '../cliente/modelos.dart'
    show CategoriaServico, DadosInicio, Profissional;
import '../legal/texto_legal_tela.dart';
import '../mensagens/modelos.dart' show ConversaResumo, ServicoMensagens;
import '../mensagens/servico_conversas.dart' show ServicoConversasApi;
import '../mensagens/servico_pedidos.dart';
import '../orcamentos/modelos.dart' show DadosContrato, Orcamento;
import '../pedido_novo/modelos.dart' show FormularioPedido;
import '../servicos/detalhe_servico_tela.dart';
import '../servicos/modelos.dart';
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
import '../comuns/foco_rolagem.dart';
import '../comuns/moedas_ganhas_tela.dart';
import '../comuns/sucesso_acao_tela.dart';
import '../conta/dados_pessoais_tela.dart';
import '../conta/enderecos_tela.dart';
import '../conta/favoritos_contatos_telas.dart';
import '../conta/modelos.dart' show EnderecoSalvo, ServicoConta;
import 'navegacao_casca.dart';
import '../../dados/modelos_api.dart' show PedidoApi;
import '../../dispositivo/abrir_email.dart';
import '../conta/servico_fake.dart';
import '../lgpd/central_privacidade_tela.dart';
import '../mensagens/mensagens_tela.dart';
import '../perfil_publico/avaliacoes_recebidas_tela.dart';
import '../perfil_publico/perfil_publico_tela.dart';
import '../profissional_cadastro/cadastro.dart';
import '../profissional_cadastro/cadastro_profissional_tela.dart';
import '../verificacao/verificacao.dart'
    show ServicoVerificacao, SituacaoVerificacao, StatusVerificacao;
import '../verificacao/verificacao_tela.dart';
import '../carteira/carteira_tela.dart';
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
import '../notificacoes/notificacoes_tela.dart';
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
import '../pedidos/pedido_execucao_tela.dart';
import '../pedidos/seus_pedidos_tela.dart';
import '../profissional/calculadora_orcamento_tela.dart';
import '../profissional/check_in_tela.dart';
import '../profissional/check_out_tela.dart';
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

  /// Câmera, GPS e envio de arquivos. O `main.dart` liga o real.
  static late DispositivoTrato dispositivo;

  /// Nota de materiais, aditivo e disputa vêm sempre da API (`repos`).
  static ServicoNotaMaterial get servicoNota => repos.notaMaterial!;
  static ServicoAditivo get servicoAditivo => repos.aditivo!;
  static ServicoDisputaProfissional get servicoDisputa =>
      repos.disputaProfissional!;

  /// Busca por texto: pede ao catálogo (modo `api`: demonstração até a rota de busca existir).
  static ServicoBusca get servicoBusca => _ServicoBuscaCatalogo(repos.catalogo);

  /// Lista de conversas da aba Mensagens. No modo `api` vem de `GET /v1/conversas` (todas as
  /// conversas, antes e depois de contratar); na demonstração, a lista montada dos pedidos.
  static ServicoMensagens get _servicoMensagens =>
      repos.mensagens ??
      ServicoMensagensDosPedidos(repos.pedidos, chat: repos.chat);

  /// Intervalo da atualização automática das telas. Só no modo `api` (na demonstração e nos
  /// testes os dados não mudam sozinhos e não há por que manter relógios ligados).
  static Duration? get _intervalo =>
      repos.modoApi ? RelogioDeAtualizacao.intervaloPadrao : null;

  /// Sessão do cliente HTTP, para o "Sair" limpar o token. O `main.dart` liga.
  static SessaoTrato? sessao;

  /// Há login guardado (a splash pula o onboarding)?
  static bool get temSessao => ServicoAuthPadrao.atual.sessaoAtual != null;

  /// Sem id de pedido (não deveria acontecer com dado da API): a chamada falha com erro claro.
  static const _semId = '';

  /// Avisa a lista de pedidos que ela precisa recarregar (criou pedido, mexeu num pedido).
  static final ValueNotifier<int> pedidosMudaram = ValueNotifier<int>(0);

  static Future<T?> _abrir<T>(BuildContext context, Widget tela) =>
      Navigator.of(context)
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
        ? erro.mensagem
        : erro is ErroFolhaCartao
            ? erro.mensagem
            : 'Algo deu errado. Tente de novo.';
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(texto)));
  }

  static void _avisoSimples(BuildContext context, String texto) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(texto)));
  }

  /// Faz uma chamada e, se der erro, avisa em português simples. Devolve se deu certo.
  static Future<bool> _tentar(
      BuildContext context, Future<void> Function() acao) async {
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
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute<void>(builder: (_) => const CascaClienteTela()),
      (rota) => false,
    );
  }

  /// Depois do cadastro (com sessão aberta): cliente vai à casca; profissional ao cadastro dele.
  static void irParaDepoisDoCadastro(BuildContext context, PerfilUso perfil) {
    if (perfil == PerfilUso.cliente) {
      irParaCliente(context);
    } else {
      irParaProfissional(context);
    }
  }

  /// Entra na casca certa para o perfil do usuário: profissional ou cliente (padrão).
  static void irParaInicio(BuildContext context, [SessaoAuth? quem]) {
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

  /// Sair da conta: encerra o login, limpa o token e volta ao login sem histórico.
  static Future<void> sair(BuildContext context) async {
    final navegador = Navigator.of(context);
    try {
      await ServicoAuthPadrao.atual.sair();
    } on Object {
      // Mesmo sem rede, o token local é descartado abaixo.
    }
    PerfilClienteTela.limparFotoSessao();
    PerfilPublicoTela.limparFotoSessao();
    sessao?.sair();
    navegador.pushAndRemoveUntil(
      MaterialPageRoute<void>(builder: (_) => const LoginTela()),
      (rota) => false,
    );
  }

  /// Perfil público de quem enviou o orçamento. Com o id do profissional (API), abre direto;
  /// sem ele, procura pelo nome no catálogo.
  static Future<void> abrirPerfilDoOrcamento(
      BuildContext context, Orcamento o) async {
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
  static Future<void> abrirPerfilProfissional(
      BuildContext context, String nome) async {
    var achados = <Profissional>[];
    final ok = await _tentar(
        context, () async => achados = await repos.catalogo.buscar(nome));
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
          carregar: () async => p.detalhe != null || p.id == null
              ? p
              : await repos.catalogo.perfil(p.id!),
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
                  : () async => (await _conta.favoritos())
                      .any((f) => f.profissionalId == perfil.id),
              aoMudarFavorito: perfil.id == null || ehProprio
                  ? null
                  : (v) => v
                      ? _conta.favoritar(perfil.id!)
                      : _conta.desfavoritar(perfil.id!),
            );
          },
        ),
      );

  /// "Pedir orçamento" no perfil: abre o Novo pedido na categoria do profissional.
  static Future<void> _pedirOrcamentoA(
      BuildContext context, Profissional p) async {
    CategoriaServico? categoria;
    final ok = await _tentar(context, () async {
      final todas = await repos.catalogo.categorias();
      categoria = todas.where((c) => c.id == p.categoriaId).firstOrNull;
    });
    if (!ok || !context.mounted) return;
    abrirNovoPedido(context, categoria: categoria);
  }

  // --- Cliente: catálogo, serviços, notificações, termos ------------------------------

  /// Novo pedido. Sem [categoria], o cliente escolhe uma antes (passo 1).
  static void abrirNovoPedido(BuildContext context,
          {CategoriaServico? categoria}) =>
      _abrir<void>(context,
          categoria == null ? _escolherCategoria() : _novoPedido(categoria));

  static Widget _escolherCategoria() => Builder(
        builder: (context) => TodasCategoriasTela(
          titulo: 'Que serviço você precisa?',
          carregar: repos.catalogo.categorias,
          aoEscolher: (c) => Navigator.of(context).pushReplacement(
            MaterialPageRoute<void>(builder: (_) => _novoPedido(c)),
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

  static void abrirCategoria(
          BuildContext context, CategoriaServico categoria) =>
      _abrir<void>(
        context,
        Builder(
          builder: (context) => CategoriaTela(
            categoria: categoria,
            carregar: (filtro) =>
                repos.catalogo.profissionais(categoria.id, filtro),
            aoAbrirProfissional: (p) => abrirPerfil(context, p),
            aoPedirOrcamento: (_) =>
                abrirNovoPedido(context, categoria: categoria),
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

  /// Detalhe do serviço (pedido) com as ações possíveis em cada estado.
  static void abrirServico(BuildContext context, String pedidoId) =>
      _abrir<void>(
        context,
        Carregador<DetalheServico>(
          carregar: () => repos.servicos.detalhe(pedidoId),
          atualizarQuando: pedidosMudaram,
          construir: (context, dados) => DetalheServicoTela(
            dados: dados,
            aoAcao: (acao) => _acaoDoServico(context, acao, pedidoId),
            aoEditarPedido: (dados.profissional == null &&
                    dados.acoes.contains(AcaoServico.cancelar))
                ? () => _abrir<void>(context, _pedidoAberto(pedidoId))
                : null,
            aoVerContrato: dados.profissional != null
                ? () => abrirContrato(context, pedidoId)
                : null,
            aoVerNota: dados.profissional != null
                ? () => _abrir<void>(
                      context,
                      VerNotaTela(servico: servicoNota, pedidoId: pedidoId),
                    )
                : null,
            aoVerAditivo: dados.profissional != null
                ? () => _abrir<void>(
                      context,
                      ResponderAditivoTela(
                        servico: servicoAditivo,
                        aditivoId: pedidoId,
                        aoCobrancaCriada: (cobranca) =>
                            _pagarAditivo(context, pedidoId, cobranca),
                      ),
                    )
                : null,
            aoVerConclusao: const {'em_confirmacao', 'concluido'}
                    .contains(dados.estadoApi)
                ? () => _abrir<void>(context, _conclusao(pedidoId))
                : null,
            aoVerProfissional: (pro) => abrirPerfil(
              context,
              Profissional(
                id: pro.id,
                nome: pro.nome,
                iniciais: pro.iniciais,
                verificacao: pro.verificacao ?? 'Verificado',
                especialidade: '',
                servicosConcluidos: 0,
                nota: 0,
                distanciaKm: 0,
              ),
            ),
          ),
        ),
      );

  static void _acaoDoServico(
      BuildContext context, AcaoServico acao, String pedidoId) {
    switch (acao) {
      case AcaoServico.verOrcamentos:
        _abrir<void>(context, _orcamentosRecebidos(pedidoId));
      case AcaoServico.pagar:
        _abrir<void>(context, _pagamento(pedidoId));
      case AcaoServico.acompanhar:
        _abrir<void>(context, _pedidoEmExecucao(pedidoId));
      case AcaoServico.conversar:
        _abrir<void>(context, _chat(pedidoId, comoProfissional: false));
      case AcaoServico.avaliar:
        _abrir<void>(context, _avaliacao(pedidoId));
      case AcaoServico.verGarantia:
        abrirGarantia(context, pedidoId: pedidoId);
      case AcaoServico.abrirProblema:
        _abrir<void>(context, _relatarProblema(pedidoId));
      case AcaoServico.cancelar:
        _cancelarPedido(context, pedidoId);
    }
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
  static void abrirNotificacoes(BuildContext context,
          {bool profissional = false}) =>
      _abrir<void>(context, _notificacoes(profissional: profissional));

  /// Termos de uso e política de privacidade (rascunhos; a tela avisa que serão revisados).
  static void abrirTermos(BuildContext context) => _abrir<void>(
        context,
        Builder(
          builder: (context) =>
              TermosEPoliticaTela(aoAbrir: (t) => abrirTextoLegal(context, t)),
        ),
      );

  static void abrirTextoLegal(BuildContext context, TextoLegal texto) =>
      _abrir<void>(context, TextoLegalTela.de(texto));

  /// Aba "Início" do cliente: carrega nome, categorias, pedido em andamento e serviços recentes.
  static Widget abaInicio({required VoidCallback aoBuscar}) =>
      Carregador<DadosInicio>(
        carregar: _carregarInicio,
        atualizarQuando: pedidosMudaram,
        atualizarACada: _intervalo,
        construir: (context, dados) => InicioTela(
          aoBuscar: aoBuscar,
          dados: dados,
          aoAbrirNotificacoes: () => abrirNotificacoes(context),
          aoNovoPedido: () => abrirNovoPedido(context),
          aoAbrirPedidoEmAndamento: (p) =>
              abrirServico(context, p.pedidoId ?? _semId),
          aoAbrirCategoria: (c) => abrirCategoria(context, c),
          aoVerTodasCategorias: () => abrirTodasCategorias(context),
          aoAbrirServico: (s) => abrirServico(context, s.pedidoId ?? _semId),
          aoVerServicos: () => abrirServicos(context),
        ),
      );

  static Future<DadosInicio> _carregarInicio() async {
    // As quatro em paralelo: a tela espera a mais lenta, não a soma das quatro.
    final ((perfil, categorias), (andamento, recentes)) = await emParalelo2(
      emParalelo2(repos.perfil.carregar(), repos.catalogo.categorias()),
      emParalelo2(repos.servicos.emAndamento(), repos.servicos.recentes()),
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
    );
  }

  static const _perfilIndisponivel = 'Perfil indisponível por enquanto.';

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

  static Future<List<String>> _selecionarFotos() =>
      dispositivo.fotografarMultiplasEEnviar();

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
            nomeInicial: repos.perfil.nomeSalvo ??
                ServicoAuthPadrao.atual.sessaoAtual?.nome ??
                '',
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
                  aoCapturarDocumento:
                      repos.capturaVerificacao?.documento ?? _fotografar,
                  aoCapturarSelfie:
                      repos.capturaVerificacao?.selfie ?? _fotografar,
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
  static Future<void> _editarCadastroProfissional(BuildContext context) =>
      _abrir<void>(
        context,
        Builder(
          builder: (tela) => CadastroProfissionalTela(
            edicao: true,
            nomeInicial: repos.perfil.nomeSalvo ??
                ServicoAuthPadrao.atual.sessaoAtual?.nome ??
                '',
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

  static Widget _cascaProfissional({int abaInicial = 0}) =>
      Carregador<InicioProfissional>(
        carregar: repos.profissional.inicio,
        construir: (context, inicio) => CascaProfissionalTela(
          abaInicial: abaInicial,
          inicio: inicio,
          carregarDetalhe: (pedido) => repos.profissional.detalhe(pedido.id),
          recusarPedido: (pedido, motivo) => _tentar(
            context,
            () => repos.profissional.recusar(pedido.id, motivo),
          ),
          abaCarteira: _abaCarteira(),
          abaPerfil: _abaPerfilProfissional(),
          abaAgenda: _abaAgenda(),
          abaConversas: Builder(
            builder: (context) => ListaConversas(
              servico: repos.mensagensProfissional ??
                  ServicoMensagensDoProfissional(repos.profissional,
                      chat: repos.chat),
              textoVazio:
                  'Quando um cliente conversar com você sobre um pedido, aparece aqui.',
              atualizarACada: _intervalo,
              atualizarQuando: pedidosMudaram,
              aoAbrirConversa: (c) => _abrirConversa(
                context,
                c,
                repos.mensagensProfissional ?? _servicoMensagens,
                comoProfissional: true,
              ),
            ),
          ),
          carregarPedidos: repos.profissional.pedidosAbertos,
          recarregarInicio: repos.profissional.inicio,
          aoAbrirOrcamentoEnviado: (o) => _abrir<void>(
            context,
            _chat(o.pedidoId, comoProfissional: true),
          ),
          atualizarACada: _intervalo,
          atualizarQuando: pedidosMudaram,
          aoAbrirMapa: abrirNoMapa,
          aoAbrirContratado: (c) => _acoesPedidoProfissional(
            context,
            pedidoId: c.pedidoId,
            titulo: c.titulo,
            remoto: c.remoto,
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
              final filtradas =
                  todas.where((c) => atual.categorias.contains(c.nome)).toList();
              return filtradas.isEmpty ? todas : filtradas;
            } on Object {
              return todas;
            }
          },
          aoAbrirNotificacoes: () =>
              abrirNotificacoes(context, profissional: true),
          aoUsarComoCliente: () => irParaCliente(context),
          aoGerenciarProximo: (proximo) => _acoesPedidoProfissional(
            context,
            pedidoId: proximo?.pedidoId ?? _semId,
            titulo: proximo?.titulo ?? 'Pedido de hoje',
            remoto: proximo?.remoto ?? false,
            estadoApi: proximo?.estadoApi,
            estado: (proximo?.emAndamento == true)
                ? EstadoAgendamento.emAndamento
                : EstadoAgendamento.agendado,
            aoCheckIn: () => _abrir<void>(
              context,
              CheckInTela(
                aoIniciar: () => _aoIniciarServico(context),
                remoto: proximo?.remoto ?? false,
                servico: _servicoCheckIn(
                  proximo?.pedidoId ?? _semId,
                  remoto: proximo?.remoto ?? false,
                ),
                tituloBarra: proximo == null
                    ? 'Check-in'
                    : '${proximo.titulo} · ${proximo.quando}',
              ),
            ),
          ),
          aoFazerCheckIn: () => _acoesPedidoProfissional(
            context,
            pedidoId: inicio.proximo?.pedidoId ?? _semId,
            titulo: inicio.proximo?.titulo ?? 'Pedido de hoje',
            remoto: inicio.proximo?.remoto ?? false,
            estadoApi: inicio.proximo?.estadoApi,
            estado: (inicio.proximo?.emAndamento == true)
                ? EstadoAgendamento.emAndamento
                : EstadoAgendamento.agendado,
            aoCheckIn: () => _abrir<void>(
              context,
              CheckInTela(
                aoIniciar: () => _aoIniciarServico(context),
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
            final pedido =
                inicio.pedidos.isNotEmpty ? inicio.pedidos.first : null;
            final id = pedido?.id ?? _semId;
            final titulo = pedido?.titulo ?? 'Orçamento';
            _abrirOrcamento(context, id, titulo);
          },
          aoFazerOrcamentoDoPedido: (pedido) =>
              _abrirOrcamento(context, pedido.id, pedido.titulo),
          aoPerguntar: () {
            final pedido =
                inicio.pedidos.isNotEmpty ? inicio.pedidos.first : null;
            _abrir<void>(
              context,
              _chat(pedido?.id ?? _semId, comoProfissional: true),
            );
          },
          aoPerguntarDoPedido: (pedido) =>
              _abrir<void>(context, _chat(pedido.id, comoProfissional: true)),
        ),
      );

  /// Check-in do pedido. No modo API o serviço já recebe a captura real (câmera, upload e GPS) e
  /// é ele quem guarda foto e posição para enviar; embrulhá-lo no serviço do aparelho fazia a
  /// tela marcar "Feito" sem o envio ter foto nem posição. O embrulho só vale na demonstração.
  static ServicoCheckIn _servicoCheckIn(String pedidoId, {bool remoto = false}) {
    final base = repos.profissional.servicoCheckIn(pedidoId, remoto: remoto);
    return repos.modoApi
        ? base
        : ServicoCheckInDispositivo(base: base, dispositivo: dispositivo);
  }

  static void _abrirOrcamento(
      BuildContext context, String pedidoId, String titulo) {
    final servico = repos.profissional.servicoOrcamento(pedidoId);
    _abrir<void>(
      context,
      Builder(
        builder: (tela) => CalculadoraOrcamentoTela(
          servico: servico,
          tituloPedido: titulo,
          aoEnviar: (pronto) async {
            final ok = await _tentar(tela, () => servico.enviar(pronto));
            if (ok && tela.mounted) {
              pedidosMudaram.value++;
              await _abrirSucesso<void>(
                tela,
                (ctxSucesso) => SucessoAcaoTela(
                  titulo: 'Orçamento enviado!',
                  subtitulo:
                      'O cliente já pode analisar o valor e o prazo combinados.',
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
            remoto: a.remoto,
            consultaMapa: a.consultaMapa,
            aoCheckIn: () => _abrir<void>(
              context,
              CheckInTela(
                aoIniciar: () => _aoIniciarServico(context),
                remoto: a.remoto,
                servico: _servicoCheckIn(a.pedidoId, remoto: a.remoto),
                tituloBarra: '${a.titulo} · ${a.horario}',
              ),
            ),
          ),
        ),
      );

  /// Ações do pedido de hoje: check-in, nota de materiais e aditivo.
  /// Escolhe dia e hora da visita de um pedido pago. Quem aceita ou recusa é o backend.
  static Future<void> _marcarVisita(
      BuildContext context, String pedidoId) async {
    final hoje = DateTime.now();
    final dia = await showDatePicker(
      context: context,
      firstDate: hoje,
      lastDate: hoje.add(const Duration(days: 90)),
      helpText: 'Dia da visita',
    );
    if (dia == null || !context.mounted) return;
    final hora = await showTimePicker(
      context: context,
      initialTime: const TimeOfDay(hour: 9, minute: 0),
      helpText: 'Hora da chegada',
      // Relógio no formato brasileiro (24 h), como o Flutter faz em português do Brasil.
    );
    if (hora == null || !context.mounted) return;
    final inicio =
        DateTime(dia.year, dia.month, dia.day, hora.hour, hora.minute);
    final ok = await _tentar(
      context,
      () => repos.profissional.confirmarAgenda(
        pedidoId,
        inicio,
        inicio.add(const Duration(hours: 2)),
      ),
    );
    if (ok) pedidosMudaram.value++;
    if (ok && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text(
                'Visita marcada. O cliente já pode ver o código de início.')),
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
  static void _abrirCheckOut(
      BuildContext context, String pedidoId, String titulo,
      {bool remoto = false}) {
    _abrir<void>(
      context,
      Builder(
        builder: (tela) => CheckOutTela(
          servico: repos.profissional.servicoCheckOut(pedidoId, remoto: remoto),
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
      _abrir<void>(
        context,
        DetalheValoresTela(
          carregar: () => repos.profissional.valoresDoPedido(pedidoId),
          aoAvaliarCliente: () async {
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
          },
        ),
      );

  static void _acoesPedidoProfissional(
    BuildContext context, {
    required String pedidoId,
    required String titulo,
    required VoidCallback aoCheckIn,
    EstadoAgendamento estado = EstadoAgendamento.agendado,
    String? estadoApi,
    bool remoto = false,
    String? consultaMapa,
  }) {
    final precisaAgendar = estadoApi == 'pago_e_retido';
    final agendado = estado == EstadoAgendamento.agendado;
    final podeCheckIn = agendado && !precisaAgendar;
    final emAndamento = estado == EstadoAgendamento.emAndamento;
    final emDisputa = estadoApi == 'em_disputa';
    final emRetrabalho = estadoApi == 'retrabalho';
    final finalizado = estadoApi == 'concluido' ||
        estadoApi == 'em_confirmacao' ||
        (estadoApi == null && estado == EstadoAgendamento.concluido);
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      // Rolável: com 8 ações a lista passa da altura de um celular menor e estourava embaixo.
      builder: (folha) => ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.85),
        child: SafeArea(
          child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(title: Text(titulo, style: TipografiaTrato.titulo)),
              if (!remoto && consultaMapa != null)
                ListTile(
                  leading: const Icon(Icons.map_outlined),
                  title: const Text('Abrir o endereço no mapa'),
                  onTap: () {
                    Navigator.of(folha).pop();
                    abrirNoMapa(consultaMapa);
                  },
                ),
              if (precisaAgendar || agendado)
                ListTile(
                  leading: const Icon(Icons.event_available_outlined),
                  title: const Text('Marcar data da visita'),
                  onTap: () {
                    Navigator.of(folha).pop();
                    _marcarVisita(context, pedidoId);
                  },
                ),
              if (podeCheckIn)
                ListTile(
                  leading: const Icon(Icons.place_outlined),
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
              if (agendado || emAndamento)
                ListTile(
                  leading: const Icon(Icons.receipt_long_outlined),
                  title: const Text('Enviar nota de materiais'),
                  onTap: () {
                    Navigator.of(folha).pop();
                    _abrir<void>(context, _enviarNota(pedidoId, titulo));
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
              if (agendado || emAndamento || finalizado)
                ListTile(
                  leading: const Icon(Icons.receipt_outlined),
                  title: Text(finalizado ? 'Ver valores e avaliar cliente' : 'Ver valores do pedido'),
                  onTap: () {
                    Navigator.of(folha).pop();
                    _abrirValoresEAvaliar(context, pedidoId);
                  },
                ),
            ],
          ),
        ),
        ),
      ),
    );
  }

  static Widget _enviarNota(String pedidoId, String titulo) => Builder(
        builder: (context) => EnviarNotaTela(
          servico: servicoNota,
          pedidoId: pedidoId,
          tituloPedido: titulo,
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
                subtitulo:
                    'O cliente foi notificado para aprovar a cobrança extra.',
                aoVoltarInicio: () => _voltarAoInicio(ctxSucesso),
              ),
              substituirAtual: true,
            );
          },
        ),
      );

  /// Disputa aberta pelo cliente, vista pelo profissional (a partir da notificação).
  static void abrirDisputa(BuildContext context, String disputaId) =>
      _abrir<void>(
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
  static void abrirRetrabalho(BuildContext context, String disputaId) =>
      _abrir<void>(
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
  static Widget _abaCarteira() => Carregador<List<ItemExtrato>>(
        carregar: repos.profissional.extrato,
        atualizarQuando: pedidosMudaram,
        construir: (context, itens) => CarteiraTela(
          soExtrato: true,
          dados: DadosCarteira(extrato: itens),
          aoAbrirItem: (item) => _abrirValoresEAvaliar(context, item.pedidoId!),
        ),
      );

  /// Aba "Perfil" da casca do profissional: perfil público e avaliações recebidas.
  static Widget _abaPerfilProfissional() => Builder(
        builder: (context) {
          final servico = repos.perfilPublico!;
          return PerfilPublicoTela(
            servico: servico,
            aoCapturarFotoPerfil: _fotografarPerfil,
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
                        aoCapturarDocumento:
                            repos.capturaVerificacao?.documento ?? _fotografar,
                        aoCapturarSelfie:
                            repos.capturaVerificacao?.selfie ?? _fotografar,
                      ),
                    ),
            aoUsarComoCliente: () => irParaCliente(context),
            aoAbrirConfiguracoes: () => abrirConfiguracoes(context, profissional: true),
          );
        },
      );

  // --- Cliente: abas -----------------------------------------------------------------

  /// Aba "Perfil" da casca do cliente.
  static Widget abaPerfil() => Carregador<PerfilCliente>(
        carregar: repos.perfil.carregar,
        atualizarQuando: pedidosMudaram,
        construir: (context, perfil) => PerfilClienteTela(
          perfil: _soNoPerfil(perfil),
          aoCapturarFotoPerfil: _fotografarPerfil,
          aoAbrirConfiguracoes: () => abrirConfiguracoes(context, profissional: false),
          aoTocarItem: (acao) {
            switch (acao) {
              case AcaoPerfil.usarComoProfissional:
                irParaProfissional(context);
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
                    context, DadosPessoaisTela(servico: _conta, servicoCep: repos.cep));
              case AcaoPerfil.enderecos:
                _abrir<void>(
                    context, EnderecosTela(servico: _conta, servicoCep: repos.cep));
              case AcaoPerfil.favoritos:
                _abrir<void>(
                  context,
                  FavoritosTela(
                    servico: _conta,
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
          aoAbrirTermos: () => abrirTermos(context),
          aoContaExcluida: () async {
            await sair(context);
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Sua conta foi excluída e você foi desconectado.'),
                ),
              );
            }
          },
        ),
      );

  /// Central de ajuda. "Falar com o suporte" só aparece se o servidor tem o e-mail do
  /// atendimento; "Relatar um problema" leva o cliente aos serviços, onde ele abre o relato.
  static Widget _telaAjuda(BuildContext context, {bool comoCliente = true}) {
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
      aoRelatarProblema: comoCliente ? () => abrirServicos(context) : null,
    );
  }

  static final ServicoConta _contaDemo = ServicoContaFake();
  static ServicoConta get _conta => repos.conta ?? _contaDemo;

  /// O que fica no Perfil do cliente: o que ele usa no dia a dia. O resto mora em Configurações.
  static const _acoesNoPerfil = {
    AcaoPerfil.enderecos,
    AcaoPerfil.favoritos,
    AcaoPerfil.usarComoProfissional,
  };

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
                      DadosPessoaisTela(servico: _conta, servicoCep: repos.cep),
                    ),
                  ),
                  ItemContaPerfil(
                    icone: Icons.notifications_none,
                    titulo: 'Notificações',
                    aoTocar: () => abrirNotificacoes(context, profissional: profissional),
                  ),
                  ItemContaPerfil(
                    icone: Icons.shield_outlined,
                    titulo: 'Contatos de confiança',
                    aoTocar: () =>
                        _abrir<void>(context, ContatosConfiancaTela(servico: _conta)),
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
                    aoTocar: () => _abrir<void>(
                        context, _telaAjuda(context, comoCliente: !profissional)),
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
  static Widget abaMensagens() => Builder(
        builder: (context) => MensagensTela(
          servico: _servicoMensagens,
          atualizarACada: _intervalo,
          atualizarQuando: pedidosMudaram,
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
          aoAbrirDestino: (n) {
            final id = n.destinoId;
            if (id == null) return;
            switch (n.tipo) {
              case TipoNotificacao.disputa:
                profissional
                    ? abrirDisputa(context, id)
                    : abrirServico(context, id);
              case TipoNotificacao.retrabalho:
                profissional
                    ? abrirRetrabalho(context, id)
                    : abrirServico(context, id);
              case TipoNotificacao.orcamento:
                profissional
                    ? _abrir<void>(context, _chat(id))
                    : _abrir<void>(context, _orcamentosRecebidos(id));
              case TipoNotificacao.mensagem:
                _abrir<void>(context, _chat(id));
              case TipoNotificacao.pedido || TipoNotificacao.pagamento:
                profissional
                    ? _abrir<void>(context, _chat(id))
                    : abrirServico(context, id);
              case TipoNotificacao.sistema:
                break;
            }
          },
        ),
      );

  /// Aba "Buscar" do cliente: busca por serviço e abertura do perfil do profissional.
  static Widget abaBuscar() => Carregador<List<CategoriaServico>>(
        // Se o catálogo falhar, a busca por texto continua sem as sugestões de categoria.
        carregar: () => repos.catalogo
            .categorias()
            .catchError((Object _) => <CategoriaServico>[]),
        atualizarQuando: pedidosMudaram,
        construir: (context, cats) {
          final ordenadas = [...cats]
            ..sort((a, b) => compararAlfabeticoPtBr(a.nome, b.nome));
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
  static Widget abaPedidos() => Builder(
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
            ),
          ),
          floatingActionButton: FloatingActionButton.extended(
            backgroundColor: CoresTrato.petroleo,
            foregroundColor: CoresTrato.creme,
            icon: const Icon(Icons.add),
            label: const Text('Novo pedido'),
            onPressed: () => abrirNovoPedido(context),
          ),
        ),
      );

  // --- Cliente: pedido ---------------------------------------------------------------

  static Future<(FormularioPedido, List<EnderecoSalvo>)> _carregarNovoPedido(
    String categoriaId,
  ) =>
      emParalelo2(
        repos.catalogo.formulario(categoriaId),
        repos.conta != null
            ? repos.conta!
                .enderecos()
                .catchError((Object _) => <EnderecoSalvo>[])
            : Future.value(const <EnderecoSalvo>[]),
      );

  static Widget _novoPedido(CategoriaServico categoria) {
    var enviandoPedido = false;
    return Carregador<(FormularioPedido, List<EnderecoSalvo>)>(
      carregar: () => _carregarNovoPedido(categoria.id),
      construir: (context, dados) => NovoPedidoTela(
        formulario: dados.$1,
        enderecosSalvos: dados.$2,
        servicoCep: repos.cep,
        aoCapturarFoto: _fotografar,
        aoTrocarCategoria: () => Navigator.of(context).pushReplacement(
          MaterialPageRoute<void>(builder: (_) => _escolherCategoria()),
        ),
        aoEnviar: (rascunho) async {
          if (enviandoPedido) return;
          enviandoPedido = true;
          try {
            String? id;
            final ok = await _tentar(
                context, () async => id = await repos.pedidos.criar(rascunho));
            if (ok) pedidosMudaram.value++;
            if (!ok || id == null || !context.mounted) return;
            await _abrirSucesso<void>(
              context,
              (ctxSucesso) => SucessoAcaoTela(
                titulo: 'Pedido enviado!',
                subtitulo:
                    'Os profissionais da sua região foram notificados e você já pode acompanhar os orçamentos.',
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
        case 'aberto':
          _abrir<void>(context, _pedidoAberto(id));
        case 'orcamento_aceito':
          _abrir<void>(context, _pagamento(id));
        case 'concluido':
          abrirGarantia(context, pedidoId: id);
        case 'pago_e_retido' ||
              'agendado' ||
              'em_andamento' ||
              'em_confirmacao':
          _abrir<void>(context, _pedidoEmExecucao(id));
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
        carregar: () => repos.pedidos.dados(pedidoId),
        atualizarQuando: pedidosMudaram,
        construir: (context, dados) {
          var dadosAtuais = dados;
          return PedidoAbertoTela(
            numero: pedidoId
                .substring(0, pedidoId.length < 4 ? pedidoId.length : 4)
                .toUpperCase(),
            dados: dados,
            servicoCep: repos.cep,
            cepInicial: dados.cep ?? '',
            aoVerOrcamentos: () =>
                _abrir<void>(context, _orcamentosRecebidos(pedidoId)),
            aoCancelar: () => _cancelarPedido(context, pedidoId),
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
                  _avisoSimples(context,
                      'Pedido atualizado. Os profissionais já veem a mudança.');
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

  static Widget _orcamentosRecebidos(String pedidoId) =>
      Carregador<OrcamentosDoPedido>(
        carregar: () => repos.orcamentos.listar(pedidoId),
        atualizarQuando: pedidosMudaram,
        atualizarACada: _intervalo,
        vazio: (o) => o.orcamentos.isEmpty,
        tituloVazio: 'Ainda sem orçamentos',
        textoVazio: 'Avisamos quando os profissionais responderem.',
        construir: (context, dados) => OrcamentosRecebidosTela(
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
                    construir: (orcamento) => DetalheOrcamentoTela(
                      orcamento: orcamento,
                      aoVerPerfil: (o) => abrirPerfilDoOrcamento(context, o),
                      aoConversar: (o) => _abrir<void>(
                        context,
                        _chat(pedidoId, profissionalId: o.profissionalId),
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
                              aoTocarPrimario: () => Navigator.of(ctxSucesso).pushReplacement(
                                MaterialPageRoute<void>(
                                  builder: (_) =>
                                      _chat(pedidoId, profissionalId: o.profissionalId, comoProfissional: false),
                                ),
                              ),
                              textoBotaoSecundario: 'Voltar ao início',
                              aoVoltarInicio: () => _voltarAoInicio(ctxSucesso),
                            ),
                          );
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
        ),
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

  static Widget _pagamento(String pedidoId) {
    var iniciandoPagamento = false;
    return Carregador<DadosPagamento>(
      carregar: () => repos.pagamento.dados(pedidoId),
      construir: (context, dados) => PagamentoTela(
        dados: dados,
        aoPagar: (metodo) async {
          if (iniciandoPagamento) return;
          iniciandoPagamento = true;
          try {
            Cobranca? cobranca;
            final ok = await _tentar(
              context,
              () async => cobranca =
                  await repos.pagamento.criarCobranca(pedidoId, metodo),
            );
            if (!ok || !context.mounted) return;
            // Cartão: a folha do provedor lista os cartões salvos e cadastra um novo. O app só
            // abre a folha; quem diz "pago" continua sendo o backend.
            final c = cobranca;
            if (metodo == MetodoPagamento.cartao &&
                c != null &&
                c.precisaDaFolhaDeCartao) {
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
                _avisoSimples(context,
                    'Pagamento cancelado. Você pode escolher outro cartão.');
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
                  MaterialPageRoute<void>(
                      builder: (_) => _pedidoEmExecucao(pedidoId)),
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
          carregar: () async {
            final (todos, contrato) = await emParalelo2(
              repos.orcamentos.listar(pedidoId),
              repos.pedidos.contrato(pedidoId),
            );
            final aceito = todos.orcamentos
                .where((o) => o.aceito && o.detalhe != null)
                .firstOrNull;
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

  static void abrirGarantia(BuildContext context, {String pedidoId = _semId}) =>
      _abrir<void>(
        context,
        Carregador<DadosGarantia>(
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

  static Future<void> _pedirRetrabalho(
      BuildContext context, String pedidoId) async {
    final pedido = await showDialog<({String descricao, List<String> fotos})>(
      context: context,
      builder: (_) => const _DialogoPedirRetrabalho(),
    );
    if (pedido == null || pedido.descricao.isEmpty || !context.mounted) return;
    final ok = await _tentar(
        context,
        () => repos.pedidos
            .pedirRetrabalho(pedidoId, pedido.descricao, fotos: pedido.fotos));
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

  static Widget _pedidoEmExecucao(String pedidoId) =>
      Carregador<PedidoEmExecucao>(
        carregar: () => repos.pedidos.acompanhar(pedidoId),
        atualizarQuando: pedidosMudaram,
        atualizarACada: _intervalo,
        construir: (context, pedido) => PedidoExecucaoTela(
          pedido: pedido,
          atualizarAditivoLocalmente: false,
          aoAprovarAditivo: () => _responderAditivoInline(context, pedidoId, aprovar: true),
          aoRecusarAditivo: () => _responderAditivoInline(context, pedidoId, aprovar: false),
          aoConversar: () =>
              _abrir<void>(context, _chat(pedidoId, comoProfissional: false)),
          aoVerConclusao: () => _abrir<void>(context, _conclusao(pedidoId)),
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
          aoCancelarPedido: pedido.podeVerConclusao
              ? null
              : () => _cancelarPedido(context, pedidoId),
        ),
      );

  static Widget _chat(
    String pedidoId, {
    String? profissionalId,
    bool? comoProfissional,
  }) =>
      Carregador<ConversaPedido>(
        carregar: () =>
            repos.chat.conversa(pedidoId, profissionalId: profissionalId),
        atualizarQuando: pedidosMudaram,
        construir: (context, conversa) {
          final ehPro = comoProfissional ??
              (!conversa.souCliente ||
                  (!repos.modoApi &&
                      ServicoAuthPadrao.atual.sessaoAtual?.ehProfissional == true));
          return ChatPedidoTela(
            conversa: conversa,
            aoCapturarFoto: _fotografar,
            aoRecarregar: repos.modoApi
                ? () =>
                    repos.chat.conversa(pedidoId, profissionalId: profissionalId)
                : null,
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
                _avisoSimples(
                    context, 'Orçamento atualizado com o valor e prazo combinados.');
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
            aoEnviar: (texto) => _tentar(
              context,
              () => repos.chat
                  .enviar(pedidoId, texto, profissionalId: profissionalId),
            ),
            aoEnviarFoto: (ref) => _tentar(
              context,
              () => repos.chat
                  .enviarFoto(pedidoId, ref, profissionalId: profissionalId),
            ),
          );
        },
      );

  static Widget _conclusao(String pedidoId) => Carregador<ResumoConclusao>(
        carregar: () => repos.pedidos.conclusao(pedidoId),
        atualizarQuando: pedidosMudaram,
        construir: (context, resumo) => ConclusaoTela(
          resumo: resumo,
          aoConfirmar: () async {
            final ok = await _tentar(
                context, () => repos.pedidos.confirmarConclusao(pedidoId));
            if (ok && context.mounted) {
              pedidosMudaram.value++;
              _abrir<void>(context, _avaliacao(pedidoId));
            }
          },
          aoRelatarProblema: () =>
              _abrir<void>(context, _relatarProblema(pedidoId)),
        ),
      );

  static Widget _avaliacao(String pedidoId) => Carregador<DadosAvaliacao>(
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
              await _abrirSucesso<void>(
                context,
                (ctxSucesso) => moedas > 0
                    ? MoedasGanhasTela(
                        moedas: moedas,
                        aoContinuar: () => _voltarAoInicio(ctxSucesso),
                      )
                    : SucessoAcaoTela(
                        titulo: 'Avaliação enviada!',
                        subtitulo: 'Obrigado por avaliar o profissional.',
                        aoVoltarInicio: () => _voltarAoInicio(ctxSucesso),
                      ),
                substituirAtual: true,
              );
            }
          },
          aoAvaliarDepois: () => _voltarAoInicio(context),
        ),
      );

  static Widget _relatarProblema(String pedidoId) =>
      Carregador<DadosRelatoProblema>(
        carregar: () => repos.pedidos.dadosRelato(pedidoId),
        construir: (context, dados) => RelatarProblemaTela(
          dados: dados,
          aoCapturarFoto: _fotografar,
          aoEnviar: (relato) async {
            final ok = await _tentar(
                context, () => repos.pedidos.relatarProblema(pedidoId, relato));
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
  State<_DialogoPedirRetrabalho> createState() =>
      _DialogoPedirRetrabalhoState();
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
  @override
  void initState() {
    super.initState();
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
  Widget build(BuildContext context) =>
      const Scaffold(body: Center(child: CircularProgressIndicator()));
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
  State<_DetalheOrcamentoAtualizado> createState() =>
      _DetalheOrcamentoAtualizadoState();
}

class _DetalheOrcamentoAtualizadoState
    extends State<_DetalheOrcamentoAtualizado> {
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
        deveAtualizar: () =>
            mounted && (ModalRoute.of(context)?.isCurrent ?? true),
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
    final novo =
        lista.orcamentos.where((o) => o.profissionalId == dono).firstOrNull;
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
  Future<List<Profissional>> buscar(String termo) => _catalogo.buscar(termo);
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
      if (sit.status == StatusVerificacao.emAnalise ||
          sit.status == StatusVerificacao.aprovada) {
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
