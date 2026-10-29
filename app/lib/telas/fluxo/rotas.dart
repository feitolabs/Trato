import 'package:flutter/material.dart';

import '../../dados/carregador.dart';
import '../../dados/erros.dart';
import '../../dados/repositorios.dart';
import '../../dados/repositorios_trato.dart';
import '../../tema/tema.dart';
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
import '../em_breve_tela.dart';
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

  /// Depois do cadastro de profissional (e em "Usar como profissional"): casca do profissional.
  static void irParaProfissional(BuildContext context) => _abrirCadastroProfissional(context);

  /// Sem câmera ainda: devolve uma referência de demonstração no lugar da foto.
  static Future<String?> _fotoDemonstracao() async => 'demo://foto';

  static void _entrarNaCascaProfissional(BuildContext context) {
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute<void>(builder: (_) => _cascaProfissional()),
      (rota) => false,
    );
  }

  /// Cadastro → verificação (documento e selfie) → casca do profissional. Os serviços ainda são
  /// de demonstração e a captura de foto fica sem câmera até o plugin entrar.
  static void _abrirCadastroProfissional(BuildContext context) => _abrir<void>(
        context,
        Builder(
          builder: (context) => CadastroProfissionalTela(
            servico: ServicoCadastroProfissionalFake(),
            aoAdicionarFoto: _fotoDemonstracao,
            aoConcluir: () => _abrir<void>(
              context,
              VerificacaoTela(
                servico: ServicoVerificacaoFake(),
                aoCapturarDocumento: _fotoDemonstracao,
                aoCapturarSelfie: _fotoDemonstracao,
                aoConcluir: () => _entrarNaCascaProfissional(context),
              ),
            ),
          ),
        ),
      );

  // --- Profissional ------------------------------------------------------------------

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
          aoFazerCheckIn: () => _abrir<void>(
            context,
            CheckInTela(
              servico: repos.profissional.servicoCheckIn(inicio.proximo?.pedidoId ?? _idDemo),
              tituloBarra: inicio.proximo == null
                  ? 'Check-in'
                  : '${inicio.proximo!.titulo} · ${inicio.proximo!.quando}',
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
        ),
      );

  // --- Cliente: abas -----------------------------------------------------------------

  /// Aba "Perfil" da casca do cliente.
  static Widget abaPerfil() => Carregador<PerfilCliente>(
        carregar: repos.perfil.carregar,
        construir: (context, perfil) => PerfilClienteTela(
          perfil: perfil,
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
                _abrir<void>(context, EmBreveTela(titulo: acao.name));
            }
          },
        ),
      );

  /// Aba "Mensagens" da casca do cliente: lista de conversas, cada uma abre o chat do pedido.
  static Widget abaMensagens() => Builder(
        builder: (context) => MensagensTela(
          servico: const ServicoMensagensFake(),
          aoAbrirConversa: (conversa) => _abrir<void>(context, _chat(conversa.pedidoId)),
        ),
      );

  static Widget _notificacoes() => NotificacoesTela(
        servico: ServicoNotificacoesRepositorio(repos.notificacoes),
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
          _abrir<void>(context, EmBreveTela(titulo: pedido.titulo));
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
      // Disputa em andamento ainda não tem tela.
      _abrir<void>(context, EmBreveTela(titulo: pedido.titulo));
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
                ? EmBreveTela(titulo: 'Orçamento de ${orcamento.profissional}')
                : DetalheOrcamentoTela(
                    orcamento: orcamento,
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
                aoConfirmar: () => _voltarAoInicio(context),
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
            aoVerContrato: () => _abrir<void>(context, const EmBreveTela(titulo: 'Contrato')),
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
          aoTocarSos: () => _abrir<void>(context, const EmBreveTela(titulo: 'SOS')),
          aoConversar: () => _abrir<void>(context, _chat(pedidoId)),
          aoVerConclusao: () => _abrir<void>(context, _conclusao(pedidoId)),
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
