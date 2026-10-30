import 'package:flutter/material.dart';

import '../../dados/carregador.dart';
import '../../dados/erros.dart';
import '../../dados/repositorios.dart';
import '../../auth/servico_auth.dart';
import '../../dados/repositorios_trato.dart';
import '../../dados/sessao.dart';
import '../auth/login_tela.dart';
import '../../tema/tema.dart';
import '../../dispositivo/check_in_dispositivo.dart';
import '../../dispositivo/dispositivo.dart';
import '../aditivo/aditivo.dart';
import '../aditivo/criar_aditivo_tela.dart';
import '../aditivo/responder_aditivo_tela.dart';
import '../busca/busca_profissionais_tela.dart';
import '../busca/modelos.dart';
import '../busca/servico_fake.dart';
import '../cliente/modelos.dart' show Profissional;
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

  /// Modo `api`: nota e aditivo vêm de `repos`; fora dele, a demonstração.
  static ServicoNotaMaterial get servicoNota => repos.notaMaterial ?? _notaDemo;
  static ServicoAditivo get servicoAditivo => repos.aditivo ?? _aditivoDemo;
  static ServicoDisputaProfissional servicoDisputa =
      ServicoDisputaProfissionalFake(disputa: disputaExemplo, retrabalho: retrabalhoExemplo);
  static ServicoBusca servicoBusca = const ServicoBuscaFake();

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

  /// Perfil público do profissional (a partir de orçamentos e da busca). Hoje a busca de
  /// demonstração é quem sabe montar o perfil; sem perfil, avisa em vez de abrir tela vazia.
  static Future<void> abrirPerfilProfissional(BuildContext context, String nome) async {
    final navegador = Navigator.of(context);
    var achados = <Profissional>[];
    final ok = await _tentar(context, () async => achados = await servicoBusca.buscar(nome));
    if (!ok) return;
    final p = achados.where((x) => x.nome == nome && x.detalhe != null).firstOrNull;
    if (p == null) {
      if (context.mounted) _avisoSimples(context, _perfilIndisponivel);
      return;
    }
    await navegador.push(
      MaterialPageRoute<void>(builder: (_) => PerfilProfissionalTela(profissional: p)),
    );
  }

  static const _perfilIndisponivel = 'Perfil indisponível por enquanto.';
  static const _emAnalise = 'Este pedido está em análise. Avisamos aqui quando houver novidade.';

  /// Depois do cadastro de profissional (e em "Usar como profissional"): casca do profissional.
  static void irParaProfissional(BuildContext context) => _abrirCadastroProfissional(context);

  /// Foto pela câmera; devolve só a referência (o upload é do backend, por URL assinada).
  static Future<String?> _fotografar() => dispositivo.fotografarEEnviar();

  static void _entrarNaCascaProfissional(BuildContext context) {
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute<void>(builder: (_) => _cascaProfissional()),
      (rota) => false,
    );
  }

  /// Cadastro → verificação (documento e selfie) → casca do profissional. Os serviços ainda são
  /// de demonstração e a foto vem da câmera do aparelho.
  static void _abrirCadastroProfissional(BuildContext context) => _abrir<void>(
        context,
        Builder(
          builder: (context) => CadastroProfissionalTela(
            // Sem rota de categorias e cidades (catálogo): o cadastro segue em demonstração.
            servico: ServicoCadastroProfissionalFake(),
            aoAdicionarFoto: _fotografar,
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
  static Widget cascaProfissionalParaTeste() => _cascaProfissional();

  static Widget _cascaProfissional() => Carregador<InicioProfissional>(
        carregar: repos.profissional.inicio,
        construir: (context, inicio) => CascaProfissionalTela(
          inicio: inicio,
          carregarDetalhe: (pedido) => repos.profissional.detalhe(pedido.id),
          recusarPedido: (pedido, motivo) => _tentar(
            context,
            () => repos.profissional.recusar(pedido.id, motivo),
          ),
          abaCarteira: _abaCarteira(),
          abaPerfil: _abaPerfilProfissional(),
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
          aoFazerOrcamento: () => _abrir<void>(
            context,
            CalculadoraOrcamentoTela(
              servico: repos.profissional.servicoOrcamento(_idDemo),
              tituloPedido: inicio.pedidos.isEmpty ? 'Orçamento' : inicio.pedidos.first.titulo,
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

  /// Aba "Perfil" da casca do profissional: perfil público e avaliações recebidas (demonstração).
  static Widget _abaPerfilProfissional() => Builder(
        builder: (context) => PerfilPublicoTela(
          servico: ServicoPerfilPublicoFake(),
          aoVerAvaliacoes: () => _abrir<void>(
            context,
            AvaliacoesRecebidasTela(servico: ServicoPerfilPublicoFake()),
          ),
          aoEditarCadastro: () => _abrirCadastroProfissional(context),
          aoSair: () => sair(context),
        ),
      );

  // --- Cliente: abas -----------------------------------------------------------------

  /// Aba "Perfil" da casca do cliente.
  static Widget abaPerfil() => Carregador<PerfilCliente>(
        carregar: repos.perfil.carregar,
        construir: (context, perfil) => PerfilClienteTela(
          perfil: _soComDestino(perfil),
          aoSair: () => sair(context),
          aoTocarItem: (acao) {
            switch (acao) {
              case AcaoPerfil.usarComoProfissional:
                irParaProfissional(context);
              case AcaoPerfil.notificacoes:
                _abrir<void>(context, _notificacoes());
              case AcaoPerfil.meusDados:
                _abrir<void>(
                  context,
                  CentralPrivacidadeTela(
                    servico: ServicoPrivacidadeFake(),
                    aoContaExcluida: () => Navigator.of(context).popUntil((r) => r.isFirst),
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

  /// Itens do Perfil sem tela ainda (dados pessoais, endereços, pagamento, favoritos, contatos,
  /// termos) saem da lista em vez de abrir "Em breve". Voltam quando a tela existir.
  static const _acoesComTela = {
    AcaoPerfil.usarComoProfissional,
    AcaoPerfil.notificacoes,
    AcaoPerfil.meusDados,
    AcaoPerfil.centralAjuda,
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
          servico: const ServicoMensagensFake(),
          aoAbrirConversa: (conversa) => _abrir<void>(context, _chat(conversa.pedidoId)),
        ),
      );

  static Widget _notificacoes() => Builder(
        builder: (context) => NotificacoesTela(
          servico: ServicoNotificacoesRepositorio(repos.notificacoes),
          aoAbrirDestino: (n) {
            final id = n.destinoId;
            if (id == null) return;
            switch (n.tipo) {
              case TipoNotificacao.disputa:
                abrirDisputa(context, id);
              case TipoNotificacao.retrabalho:
                abrirRetrabalho(context, id);
              default:
                break;
            }
          },
        ),
      );

  /// Aba "Buscar" do cliente: busca por serviço e abertura do perfil do profissional.
  static Widget abaBuscar() => Builder(
        builder: (context) => BuscaProfissionaisTela(
          servico: servicoBusca,
          aoAbrirProfissional: (p) {
            if (p.detalhe == null) {
              _avisoSimples(context, _perfilIndisponivel);
              return;
            }
            _abrir<void>(context, PerfilProfissionalTela(profissional: p));
          },
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
            onPressed: () => _abrir<void>(context, _novoPedido()),
          ),
        ),
      );

  // --- Cliente: pedido ---------------------------------------------------------------

  static Widget _novoPedido() => Builder(
        builder: (context) => NovoPedidoTela(
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
          _avisoSimples(context, _emAnalise);
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
      _avisoSimples(context, _emAnalise);
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
                ? _PerfilAoAbrir(nome: orcamento.profissional)
                : DetalheOrcamentoTela(
                    orcamento: orcamento,
                    aoVerPerfil: (o) => abrirPerfilProfissional(context, o.profissional),
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
    final controlador = TextEditingController();
    final descricao = await showDialog<String>(
      context: context,
      builder: (dialogo) => AlertDialog(
        title: const Text('Pedir retrabalho'),
        content: TextField(
          controller: controlador,
          maxLines: 4,
          decoration: const InputDecoration(labelText: 'O que precisa ser refeito?'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(dialogo).pop(), child: const Text('Cancelar')),
          TextButton(
            onPressed: () => Navigator.of(dialogo).pop(controlador.text.trim()),
            child: const Text('Enviar'),
          ),
        ],
      ),
    );
    controlador.dispose();
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

  static Widget _chat(String pedidoId) => Carregador<ConversaPedido>(
        carregar: () => repos.chat.conversa(pedidoId),
        construir: (context, conversa) => ChatPedidoTela(
          conversa: conversa,
          aoEnviar: (texto) => _tentar(context, () => repos.chat.enviar(pedidoId, texto)),
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
          aoEnviar: (relato) async {
            final ok =
                await _tentar(context, () => repos.pedidos.relatarProblema(pedidoId, relato));
            if (ok && context.mounted) _voltarAoInicio(context);
          },
        ),
      );
}

/// Orçamento sem detalhe no protótipo: abre direto o perfil público do profissional e, ao
/// terminar, volta para a lista.
class _PerfilAoAbrir extends StatefulWidget {
  const _PerfilAoAbrir({required this.nome});

  final String nome;

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
      await RotasTrato.abrirPerfilProfissional(context, widget.nome);
      if (mounted) navegador.maybePop();
    });
  }

  @override
  Widget build(BuildContext context) =>
      const Scaffold(body: Center(child: CircularProgressIndicator()));
}
