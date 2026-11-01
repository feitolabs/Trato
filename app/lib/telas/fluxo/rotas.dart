import 'package:flutter/material.dart';

import '../../dados/carregador.dart';
import '../../dados/erros.dart';
import '../../dados/repositorios.dart';
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
import '../../dados/repositorios_catalogo_fake.dart' show ServicosExemplo;
import '../agenda/agenda_tela.dart';
import '../catalogo/avaliacoes_profissional_tela.dart';
import '../catalogo/categoria_tela.dart';
import '../catalogo/todas_categorias_tela.dart';
import '../cliente/dados_exemplo.dart' as cliente_exemplo;
import '../cliente/inicio_tela.dart';
import '../cliente/modelos.dart' show CategoriaServico, DadosInicio, Profissional;
import '../legal/texto_legal_tela.dart';
import '../mensagens/modelos.dart' show ServicoMensagens;
import '../mensagens/servico_pedidos.dart';
import '../orcamentos/modelos.dart' show Orcamento;
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
import '../ajuda/servico_fake.dart';
import '../lgpd/central_privacidade_tela.dart';
import '../lgpd/servico_fake.dart';
import '../mensagens/mensagens_tela.dart';
import '../mensagens/servico_fake.dart';
import '../perfil_publico/avaliacoes_recebidas_tela.dart';
import '../perfil_publico/perfil_publico.dart';
import '../perfil_publico/perfil_publico_tela.dart';
import '../profissional_cadastro/cadastro.dart';
import '../profissional_cadastro/cadastro_profissional_tela.dart';
import '../verificacao/verificacao.dart';
import '../verificacao/verificacao_tela.dart';
import '../carteira/carteira_tela.dart';
import '../carteira/modelos.dart';
import '../cliente/casca_cliente_tela.dart';
import '../conclusao/avaliacao_tela.dart';
import '../conclusao/conclusao_tela.dart';
import '../conclusao/dados_exemplo.dart';
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
import '../pedidos/pedido_execucao_tela.dart';
import '../pedidos/seus_pedidos_tela.dart';
import '../profissional/calculadora_orcamento_tela.dart';
import '../profissional/check_in_tela.dart';
import '../profissional_inicio/casca_profissional_tela.dart';
import '../profissional_inicio/modelos.dart';

/// Liga as telas entre si e aos dados. As telas não se conhecem e não conhecem a rede: quem
/// sabe para onde cada botão vai, e de onde vêm os dados, é este arquivo. Os repositórios
/// (API ou demonstração) vêm de [repos], configurado no `main.dart`.
abstract final class RotasTrato {
  /// Padrão: demonstração (dados de exemplo, sem rede). O `main.dart` troca conforme o modo.
  static RepositoriosTrato repos = RepositoriosTrato.demo();

  /// Câmera, GPS e envio de arquivos. Padrão: fake (testes); o `main.dart` troca pelo real.
  static DispositivoTrato dispositivo = DispositivoTrato.fake();

  /// Serviços de nota, aditivo, disputa e busca. Ainda sem rota na API: seguem em demonstração
  /// (docs/app-ligacao.md). Trocar aqui quando o backend tiver as rotas.
  static final ServicoNotaMaterial _notaDemo = ServicoNotaMaterialFake(nota: notaMaterialExemplo);
  static final ServicoAditivo _aditivoDemo = ServicoAditivoFake(detalhe: aditivoExemplo);

  /// Modo `api`: nota, aditivo e disputa vêm de `repos`; fora dele, a demonstração.
  static ServicoNotaMaterial get servicoNota => repos.notaMaterial ?? _notaDemo;
  static ServicoAditivo get servicoAditivo => repos.aditivo ?? _aditivoDemo;
  static final ServicoDisputaProfissional _disputaDemo =
      ServicoDisputaProfissionalFake(disputa: disputaExemplo, retrabalho: retrabalhoExemplo);
  static ServicoDisputaProfissional get servicoDisputa =>
      repos.disputaProfissional ?? _disputaDemo;

  /// Busca por texto: pede ao catálogo (modo `api`: demonstração até a rota de busca existir).
  static ServicoBusca get servicoBusca => _ServicoBuscaCatalogo(repos.catalogo);

  /// Lista de conversas da aba Mensagens. No modo `api` vem dos pedidos (uma conversa por
  /// pedido contratado); na demonstração, dados de exemplo.
  static ServicoMensagens get _servicoMensagens => repos.modoApi
      ? ServicoMensagensDosPedidos(repos.pedidos, chat: repos.chat)
      : const ServicoMensagensFake();

  /// Sessão do cliente HTTP, para o "Sair" limpar o token. O `main.dart` liga.
  static SessaoTrato? sessao;

  /// Há login guardado (a splash pula o onboarding)?
  static bool get temSessao => ServicoAuthPadrao.atual.sessaoAtual != null;

  /// Id usado nos dados de exemplo, que não têm pedido real por trás.
  static const _idDemo = 'demo';

  static Future<T?> _abrir<T>(BuildContext context, Widget tela) =>
      Navigator.of(context).push(MaterialPageRoute<T>(builder: (_) => tela));

  static void _voltarAoInicio(BuildContext context) =>
      Navigator.of(context).popUntil((rota) => rota.isFirst);

  static void _aviso(BuildContext context, Object erro) {
    final texto = erro is ErroTrato ? erro.mensagem : 'Algo deu errado. Tente de novo.';
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
      _entrarNaCascaProfissional(context);
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
    sessao?.sair();
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
          carregar: () async => p.detalhe != null || p.id == null
              ? p
              : await repos.catalogo.perfil(p.id!),
          vazio: (perfil) => perfil.detalhe == null,
          tituloVazio: 'Perfil indisponível',
          textoVazio: 'Este perfil ainda não tem as informações completas.',
          construir: (context, perfil) => PerfilProfissionalTela(
            profissional: perfil,
            aoPedirOrcamento: (x) => _pedirOrcamentoA(context, x),
            aoVerAvaliacoes: (x) => _abrir<void>(
              context,
              AvaliacoesProfissionalTela(profissional: x),
            ),
          ),
        ),
      );

  /// "Pedir orçamento" no perfil: abre o Novo pedido na categoria do profissional.
  static Future<void> _pedirOrcamentoA(BuildContext context, Profissional p) async {
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
  static void abrirNovoPedido(BuildContext context, {CategoriaServico? categoria}) =>
      _abrir<void>(context, categoria == null ? _escolherCategoria() : _novoPedido(categoria));

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
            aoAbrir: (s) => abrirServico(context, s.pedidoId ?? _idDemo),
          ),
        ),
      );

  /// Detalhe do serviço (pedido) com as ações possíveis em cada estado.
  static void abrirServico(BuildContext context, String pedidoId) => _abrir<void>(
        context,
        Carregador<DetalheServico>(
          carregar: () => repos.servicos.detalhe(pedidoId),
          construir: (context, dados) => DetalheServicoTela(
            dados: dados,
            aoAcao: (acao) => _acaoDoServico(context, acao, pedidoId),
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

  static void _acaoDoServico(BuildContext context, AcaoServico acao, String pedidoId) {
    switch (acao) {
      case AcaoServico.verOrcamentos:
        _abrir<void>(context, _orcamentosRecebidos(pedidoId));
      case AcaoServico.pagar:
        _abrir<void>(context, _pagamento(pedidoId));
      case AcaoServico.acompanhar:
        _abrir<void>(context, _pedidoEmExecucao(pedidoId));
      case AcaoServico.conversar:
        _abrir<void>(context, _chat(pedidoId));
      case AcaoServico.avaliar:
        _abrir<void>(context, _avaliacao(pedidoId));
      case AcaoServico.verGarantia:
        abrirGarantia(context, pedidoId: pedidoId);
      case AcaoServico.abrirProblema:
        _abrir<void>(context, _relatarProblema(pedidoId));
    }
  }

  /// Notificações. [profissional] muda para onde o toque leva (disputa e retrabalho abrem as
  /// telas do profissional; o cliente vê o serviço).
  static void abrirNotificacoes(BuildContext context, {bool profissional = false}) =>
      _abrir<void>(context, _notificacoes(profissional: profissional));

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
        construir: (context, dados) => InicioTela(
          aoBuscar: aoBuscar,
          dados: dados,
          aoAbrirNotificacoes: () => abrirNotificacoes(context),
          aoNovoPedido: () => abrirNovoPedido(context),
          aoAbrirPedidoEmAndamento: (p) => abrirServico(context, p.pedidoId ?? _idDemo),
          aoAbrirCategoria: (c) => abrirCategoria(context, c),
          aoVerTodasCategorias: () => abrirTodasCategorias(context),
          aoAbrirServico: (s) => abrirServico(context, s.pedidoId ?? _idDemo),
          aoVerServicos: () => abrirServicos(context),
        ),
      );

  static Future<DadosInicio> _carregarInicio() async {
    final perfil = await repos.perfil.carregar();
    final categorias = await repos.catalogo.categorias();
    final andamento = await repos.servicos.emAndamento();
    final recentes = await repos.servicos.recentes();
    return DadosInicio(
      nome: perfil.nome.trim().split(' ').first,
      categorias: categorias,
      emAndamento: andamento,
      recentes: recentes,
    );
  }

  static const _perfilIndisponivel = 'Perfil indisponível por enquanto.';

  /// Depois do cadastro de profissional (e em "Usar como profissional"): casca do profissional.
  static Future<void> irParaProfissional(BuildContext context) async {
    final tem = await repos.perfilPublico?.temPerfilProfissional() ?? false;
    if (tem && context.mounted) {
      _entrarNaCascaProfissional(context);
      return;
    }
    if (context.mounted) {
      _abrirCadastroProfissional(context);
    }
  }

  /// Foto pela câmera; devolve só a referência (o upload é do backend, por URL assinada).
  static Future<String?> _fotografar() => dispositivo.fotografarEEnviar();
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
            nomeInicial: ServicoAuthPadrao.atual.sessaoAtual?.nome ?? '',
            servico: repos.cadastroProfissional ?? ServicoCadastroProfissionalFake(),
            aoAdicionarFoto: _fotografar,
            aoAdicionarFotos: _selecionarFotos,
            aoConcluir: () => _abrir<void>(
              context,
              VerificacaoTela(
                servico: repos.verificacao ?? ServicoVerificacaoFake(),
                aoCapturarDocumento: repos.capturaVerificacao?.documento ?? _fotografar,
                aoCapturarSelfie: repos.capturaVerificacao?.selfie ?? _fotografar,
                aoConcluir: () => _entrarNaCascaProfissional(context),
              ),
            ),
          ),
        ),
      );

  // --- Profissional ------------------------------------------------------------------

  @visibleForTesting
  static Widget cascaProfissionalParaTeste({int abaInicial = 0}) =>
      _cascaProfissional(abaInicial: abaInicial);

  static Widget _cascaProfissional({int abaInicial = 0}) => Carregador<InicioProfissional>(
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
              servico: repos.modoApi
                  ? ServicoMensagensDoProfissional(repos.profissional, chat: repos.chat)
                  : const ServicoMensagensFake(),
              textoVazio: 'Quando um cliente conversar com você sobre um pedido, aparece aqui.',
              aoAbrirConversa: (c) => _abrir<void>(context, _chat(c.pedidoId)),
            ),
          ),
          carregarPedidos: repos.profissional.pedidosAbertos,
          carregarCategorias: repos.catalogo.categorias,
          aoAbrirNotificacoes: () => abrirNotificacoes(context, profissional: true),
          aoFazerCheckIn: () => _acoesPedidoProfissional(
            context,
            pedidoId: inicio.proximo?.pedidoId ?? _idDemo,
            titulo: inicio.proximo?.titulo ?? 'Pedido de hoje',
            aoCheckIn: () => _abrir<void>(
              context,
              CheckInTela(
                servico: ServicoCheckInDispositivo(
                  base: repos.profissional.servicoCheckIn(inicio.proximo?.pedidoId ?? _idDemo),
                  dispositivo: dispositivo,
                ),
                tituloBarra: inicio.proximo == null
                    ? 'Check-in'
                    : '${inicio.proximo!.titulo} · ${inicio.proximo!.quando}',
              ),
            ),
          ),
          aoFazerOrcamento: () {
            final pedido = inicio.pedidos.isNotEmpty ? inicio.pedidos.first : null;
            final id = pedido?.id ?? _idDemo;
            final titulo = pedido?.titulo ?? 'Orçamento';
            _abrirOrcamento(context, id, titulo);
          },
          aoFazerOrcamentoDoPedido: (pedido) => _abrirOrcamento(context, pedido.id, pedido.titulo),
          aoPerguntar: () {
            final pedido = inicio.pedidos.isNotEmpty ? inicio.pedidos.first : null;
            _abrir<void>(context, _chat(pedido?.id ?? _idDemo));
          },
          aoPerguntarDoPedido: (pedido) => _abrir<void>(context, _chat(pedido.id)),
        ),
      );

  static void _abrirOrcamento(BuildContext context, String pedidoId, String titulo) {
    final servico = repos.profissional.servicoOrcamento(pedidoId);
    _abrir<void>(
      context,
      CalculadoraOrcamentoTela(
        servico: servico,
        tituloPedido: titulo,
        aoEnviar: (pronto) async {
          final ok = await _tentar(context, () => servico.enviar(pronto));
          if (ok && context.mounted) {
            Navigator.of(context).pop();
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Orçamento enviado com sucesso!')),
            );
          }
        },
      ),
    );
  }

  /// Aba Agenda: atendimentos por dia; cada um abre as ações do pedido (check-in, nota, aditivo).
  static Widget _abaAgenda() => Builder(
        builder: (context) => AgendaTela(
          carregar: repos.agenda.listar,
          aoFazerCheckIn: (a) => _acoesPedidoProfissional(
            context,
            pedidoId: a.pedidoId,
            titulo: a.titulo,
            aoCheckIn: () => _abrir<void>(
              context,
              CheckInTela(
                servico: ServicoCheckInDispositivo(
                  base: repos.profissional.servicoCheckIn(a.pedidoId),
                  dispositivo: dispositivo,
                ),
                tituloBarra: '${a.titulo} · ${a.horario}',
              ),
            ),
          ),
        ),
      );

  /// Ações do pedido de hoje: check-in, nota de materiais e aditivo.
  static void _acoesPedidoProfissional(
    BuildContext context, {
    required String pedidoId,
    required String titulo,
    required VoidCallback aoCheckIn,
  }) {
    showModalBottomSheet<void>(
      context: context,
      builder: (folha) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(title: Text(titulo, style: TipografiaTrato.titulo)),
            ListTile(
              leading: const Icon(Icons.place_outlined),
              title: const Text('Fazer check-in'),
              onTap: () {
                Navigator.of(folha).pop();
                aoCheckIn();
              },
            ),
            ListTile(
              leading: const Icon(Icons.chat_bubble_outline),
              title: const Text('Conversar com o cliente'),
              onTap: () {
                Navigator.of(folha).pop();
                _abrir<void>(context, _chat(pedidoId));
              },
            ),
            ListTile(
              leading: const Icon(Icons.receipt_long_outlined),
              title: const Text('Enviar nota de materiais'),
              onTap: () {
                Navigator.of(folha).pop();
                _abrir<void>(context, _enviarNota(pedidoId, titulo));
              },
            ),
            ListTile(
              leading: const Icon(Icons.add_task_outlined),
              title: const Text('Criar aditivo'),
              onTap: () {
                Navigator.of(folha).pop();
                _abrir<void>(context, _criarAditivo(pedidoId, titulo));
              },
            ),
            // Sem lista de disputas na API, o id do pedido faz de id da disputa (demonstração).
            ListTile(
              leading: const Icon(Icons.gavel_outlined),
              title: const Text('Responder disputa'),
              onTap: () {
                Navigator.of(folha).pop();
                abrirDisputa(context, pedidoId);
              },
            ),
            ListTile(
              leading: const Icon(Icons.build_outlined),
              title: const Text('Atender retrabalho'),
              onTap: () {
                Navigator.of(folha).pop();
                abrirRetrabalho(context, pedidoId);
              },
            ),
          ],
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
          aoEnviada: () => Navigator.of(context).maybePop(),
        ),
      );

  static Widget _criarAditivo(String pedidoId, String titulo) => Builder(
        builder: (context) => CriarAditivoTela(
          servico: servicoAditivo,
          servicoLiquido: repos.profissional.servicoOrcamento(pedidoId),
          pedidoId: pedidoId,
          tituloPedido: titulo,
          aoCriado: () => Navigator.of(context).maybePop(),
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
            aoRespondida: (_) => Navigator.of(context).maybePop(),
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
            aoAgendado: (_) => Navigator.of(context).maybePop(),
          ),
        ),
      );

  /// Carteira do profissional como EXTRATO (D15): sem saldo próprio, sem saque.
  static Widget _abaCarteira() => Carregador<List<ItemExtrato>>(
        carregar: repos.profissional.extrato,
        construir: (context, itens) => CarteiraTela(
          soExtrato: true,
          dados: DadosCarteira(extrato: itens),
        ),
      );

  /// Aba "Perfil" da casca do profissional: perfil público e avaliações recebidas.
  static Widget _abaPerfilProfissional() => Builder(
        builder: (context) {
          final servico = repos.perfilPublico ?? ServicoPerfilPublicoFake();
          return PerfilPublicoTela(
            servico: servico,
            aoCapturarFotoPerfil: _fotografar,
            aoVerAvaliacoes: () => _abrir<void>(
              context,
              AvaliacoesRecebidasTela(servico: servico),
            ),
            aoEditarCadastro: () => _abrirCadastroProfissional(context),
            aoUsarComoCliente: () => irParaCliente(context),
            aoSair: () => sair(context),
          );
        },
      );

  // --- Cliente: abas -----------------------------------------------------------------

  /// Aba "Perfil" da casca do cliente.
  static Widget abaPerfil() => Carregador<PerfilCliente>(
        carregar: repos.perfil.carregar,
        construir: (context, perfil) => PerfilClienteTela(
          perfil: _soComDestino(perfil),
          aoCapturarFotoPerfil: _fotografar,
          aoSair: () => sair(context),
          aoTocarItem: (acao) {
            switch (acao) {
              case AcaoPerfil.usarComoProfissional:
                irParaProfissional(context);
              case AcaoPerfil.notificacoes:
                abrirNotificacoes(context);
              case AcaoPerfil.termos:
                abrirTermos(context);
              case AcaoPerfil.meusDados:
                _abrir<void>(
                  context,
                  CentralPrivacidadeTela(
                    servico: repos.privacidade ?? ServicoPrivacidadeFake(),
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
              case AcaoPerfil.centralAjuda:
                _abrir<void>(context, const AjudaTela(servico: ServicoAjudaFake()));
              default:
                break;
            }
          },
        ),
      );

  /// Itens do Perfil sem tela ainda (dados pessoais, endereços, pagamento, favoritos, contatos)
  /// saem da lista em vez de abrir uma tela vazia. Voltam quando a tela existir
  /// (`docs/placeholders.md`).
  static const _acoesComTela = {
    AcaoPerfil.usarComoProfissional,
    AcaoPerfil.notificacoes,
    AcaoPerfil.meusDados,
    AcaoPerfil.centralAjuda,
    AcaoPerfil.termos,
  };

  static PerfilCliente _soComDestino(PerfilCliente p) => PerfilCliente(
        nome: p.nome,
        iniciais: p.iniciais,
        resumo: p.resumo,
        grupos: [
          for (final g in p.grupos)
            if (g.itens.any((i) => _acoesComTela.contains(i.acao)))
              GrupoPerfil(
                titulo: g.titulo,
                itens: [
                  for (final i in g.itens)
                    if (_acoesComTela.contains(i.acao)) i,
                ],
              ),
        ],
      );

  /// Aba "Mensagens" da casca do cliente: lista de conversas, cada uma abre o chat do pedido.
  static Widget abaMensagens() => Builder(
        builder: (context) => MensagensTela(
          servico: _servicoMensagens,
          aoAbrirConversa: (conversa) => _abrir<void>(context, _chat(conversa.pedidoId)),
        ),
      );

  static Widget _notificacoes({required bool profissional}) => Builder(
        builder: (context) => NotificacoesTela(
          servico: ServicoNotificacoesRepositorio(repos.notificacoes),
          aoAbrirDestino: (n) {
            final id = n.destinoId;
            if (id == null) return;
            switch (n.tipo) {
              case TipoNotificacao.disputa:
                profissional ? abrirDisputa(context, id) : abrirServico(context, id);
              case TipoNotificacao.retrabalho:
                profissional ? abrirRetrabalho(context, id) : abrirServico(context, id);
              case TipoNotificacao.orcamento:
                _abrir<void>(context, _orcamentosRecebidos(id));
              case TipoNotificacao.mensagem:
                _abrir<void>(context, _chat(id));
              case TipoNotificacao.pedido || TipoNotificacao.pagamento:
                if (!profissional) abrirServico(context, id);
              case TipoNotificacao.sistema:
                break;
            }
          },
        ),
      );

  /// Aba "Buscar" do cliente: busca por serviço e abertura do perfil do profissional.
  static Widget abaBuscar() => Carregador<List<CategoriaServico>>(
        // Se o catálogo falhar, a busca por texto continua com as categorias do protótipo.
        carregar: () => repos.catalogo.categorias().catchError(
              (Object _) => cliente_exemplo.categorias.take(7).toList(),
            ),
        construir: (context, cats) => BuscaProfissionaisTela(
          servico: servicoBusca,
          sugestoes: [...cats.take(7), const CategoriaServico('Ver todas', Icons.grid_view)],
          aoAbrirProfissional: (p) => abrirPerfil(context, p),
          aoEscolherCategoria: (c) => abrirCategoria(context, c),
          aoVerTodas: () => abrirTodasCategorias(context),
        ),
      );

  /// Aba "Pedidos" da casca do cliente.
  static Widget abaPedidos() => Builder(
        builder: (context) => Scaffold(
          body: Carregador<PedidosDoCliente>(
            carregar: repos.pedidos.listar,
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

  static Widget _novoPedido(CategoriaServico categoria) => Carregador<FormularioPedido>(
        carregar: () => repos.catalogo.formulario(categoria.id),
        construir: (context, formulario) => NovoPedidoTela(
          formulario: formulario,
          aoCapturarFoto: _fotografar,
          aoTrocarCategoria: () => Navigator.of(context).pushReplacement(
            MaterialPageRoute<void>(builder: (_) => _escolherCategoria()),
          ),
          aoEnviar: (rascunho) async {
            final navegador = Navigator.of(context);
            final mensagens = ScaffoldMessenger.of(context);
            String? id;
            final ok = await _tentar(context, () async => id = await repos.pedidos.criar(rascunho));
            if (!ok || id == null) return;
            navegador.pop();
            mensagens
              ..hideCurrentSnackBar()
              ..showSnackBar(
                const SnackBar(content: Text('Pedido enviado. Os orçamentos chegam aqui.')),
              );
          },
        ),
      );

  static void abrirPedido(BuildContext context, PedidoResumo pedido) {
    final id = pedido.id ?? _idDemo;
    final estado = pedido.estadoApi;
    if (estado != null) {
      switch (estado) {
        case 'aberto':
          _abrir<void>(context, _orcamentosRecebidos(id));
        case 'orcamento_aceito':
          _abrir<void>(context, _pagamento(id));
        case 'concluido':
          abrirGarantia(context, pedidoId: id);
        case 'pago_e_retido' || 'agendado' || 'em_andamento' || 'em_confirmacao':
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
      abrirServico(context, pedido.id ?? ServicosExemplo.vazamento);
    }
  }

  static Widget _orcamentosRecebidos(String pedidoId) => Carregador<OrcamentosDoPedido>(
        carregar: () => repos.orcamentos.listar(pedidoId),
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
                : DetalheOrcamentoTela(
                    orcamento: orcamento,
                    aoVerPerfil: (o) => abrirPerfilDoOrcamento(context, o),
                    aoConversar: (o) => _abrir<void>(
                      context,
                      _chat(pedidoId, profissionalId: o.profissionalId),
                    ),
                    aoFazerContraproposta: (o) => _abrir<void>(
                      context,
                      _chat(pedidoId, profissionalId: o.profissionalId),
                    ),
                    aoAceitar: (o) async {
                      // Só pede ao backend; taxa e líquido são dele.
                      final ok = await _tentar(
                        context,
                        () => repos.orcamentos.aceitar(pedidoId, o.id),
                      );
                      if (ok && context.mounted) {
                        _abrir<void>(context, _pagamento(pedidoId));
                      }
                    },
                  ),
          ),
        ),
      );

  static Widget _pagamento(String pedidoId) => Carregador<DadosPagamento>(
        carregar: () => repos.pagamento.dados(pedidoId),
        construir: (context, dados) => PagamentoTela(
          dados: dados,
          aoPagar: (metodo) async {
            Cobranca? cobranca;
            final ok = await _tentar(
              context,
              () async => cobranca = await repos.pagamento.criarCobranca(pedidoId, metodo),
            );
            if (!ok || !context.mounted) return;
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
          },
        ),
      );

  static void abrirGarantia(BuildContext context, {String pedidoId = _idDemo}) => _abrir<void>(
        context,
        Carregador<DadosGarantia>(
          carregar: () => repos.pedidos.garantia(pedidoId),
          construir: (context, dados) => GarantiaTela(
            dados: dados,
            aoPedirRetrabalho: () => _pedirRetrabalho(context, pedidoId),
          ),
        ),
      );

  static Future<void> _pedirRetrabalho(BuildContext context, String pedidoId) async {
    final descricao = await showDialog<String>(
      context: context,
      builder: (_) => const _DialogoPedirRetrabalho(),
    );
    if (descricao == null || descricao.isEmpty || !context.mounted) return;
    final ok = await _tentar(context, () => repos.pedidos.pedirRetrabalho(pedidoId, descricao));
    if (ok && context.mounted) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text('Pedido de retrabalho enviado.')));
    }
  }

  static Widget _pedidoEmExecucao(String pedidoId) => Carregador<PedidoEmExecucao>(
        carregar: () => repos.pedidos.acompanhar(pedidoId),
        construir: (context, pedido) => PedidoExecucaoTela(
          pedido: pedido,
          aoConversar: () => _abrir<void>(context, _chat(pedidoId)),
          aoVerConclusao: () => _abrir<void>(context, _conclusao(pedidoId)),
          aoVerNota: () => _abrir<void>(
            context,
            VerNotaTela(servico: servicoNota, pedidoId: pedidoId),
          ),
          // Sem rota de aditivo por pedido: o id do pedido faz de id do aditivo na demonstração.
          aoVerAditivo: () => _abrir<void>(
            context,
            ResponderAditivoTela(servico: servicoAditivo, aditivoId: pedidoId),
          ),
        ),
      );

  static Widget _chat(String pedidoId, {String? profissionalId}) => Carregador<ConversaPedido>(
        carregar: () => repos.chat.conversa(pedidoId, profissionalId: profissionalId),
        construir: (context, conversa) => ChatPedidoTela(
          conversa: conversa,
          aoCapturarFoto: _fotografar,
          aoRecarregar: repos.modoApi
              ? () => repos.chat.conversa(pedidoId, profissionalId: profissionalId)
              : null,
          aoEnviar: (texto) => _tentar(
            context,
            () => repos.chat.enviar(pedidoId, texto, profissionalId: profissionalId),
          ),
          aoEnviarFoto: (ref) => _tentar(
            context,
            () => repos.chat.enviarFoto(pedidoId, ref, profissionalId: profissionalId),
          ),
        ),
      );

  static Widget _conclusao(String pedidoId) => Carregador<ResumoConclusao>(
        carregar: () => repos.pedidos.conclusao(pedidoId),
        construir: (context, resumo) => ConclusaoTela(
          resumo: resumo,
          aoConfirmar: () async {
            final ok = await _tentar(context, () => repos.pedidos.confirmarConclusao(pedidoId));
            if (ok && context.mounted) {
              _abrir<void>(context, _avaliacao(pedidoId));
            }
          },
          aoRelatarProblema: () => _abrir<void>(context, _relatarProblema(pedidoId)),
        ),
      );

  static Widget _avaliacao(String pedidoId) => Carregador<DadosAvaliacao>(
        carregar: () => repos.pedidos.dadosAvaliacao(pedidoId),
        construir: (context, dados) => AvaliacaoTela(
          dados: dados,
          aoEnviar: (envio) async {
            final ok = await _tentar(context, () => repos.pedidos.avaliar(pedidoId, envio));
            if (ok && context.mounted) _voltarAoInicio(context);
          },
          aoAvaliarDepois: () => _voltarAoInicio(context),
        ),
      );

  static Widget _relatarProblema(String pedidoId) => Carregador<DadosRelatoProblema>(
        carregar: () => repos.pedidos.dadosRelato(pedidoId),
        construir: (context, dados) => RelatarProblemaTela(
          dados: dados,
          aoCapturarFoto: _fotografar,
          aoEnviar: (relato) async {
            final ok =
                await _tentar(context, () => repos.pedidos.relatarProblema(pedidoId, relato));
            if (ok && context.mounted) _voltarAoInicio(context);
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

  @override
  void dispose() {
    _controlador.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Pedir retrabalho'),
      content: TextField(
        controller: _controlador,
        maxLines: 4,
        decoration: const InputDecoration(labelText: 'O que precisa ser refeito?'),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(_controlador.text.trim()),
          child: const Text('Enviar'),
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
      if (mounted && (ModalRoute.of(context)?.isActive ?? false)) navegador.pop();
    });
  }

  @override
  Widget build(BuildContext context) =>
      const Scaffold(body: Center(child: CircularProgressIndicator()));
}

/// Busca por texto ligada ao catálogo (modo `api`: demonstração até existir a rota de busca).
class _ServicoBuscaCatalogo implements ServicoBusca {
  const _ServicoBuscaCatalogo(this._catalogo);

  final RepositorioCatalogo _catalogo;

  @override
  Future<List<Profissional>> buscar(String termo) => _catalogo.buscar(termo);
}
