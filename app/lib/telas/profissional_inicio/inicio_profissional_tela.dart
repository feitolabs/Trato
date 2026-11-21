import 'package:flutter/material.dart';

import '../../componentes/componentes.dart';
import '../../dados/carregador.dart';
import '../../dados/erros.dart';
import '../../tema/tema.dart';
import '../comuns/desconto_moedas.dart' show textoTratinhos, textoTratinhosPendentes;
import '../comuns/formato_aparelho.dart' show diaMesDoAparelho;
import '../conclusao/apoio_conclusao.dart' show formatarReais;
import '../profissional_apoio/apoio.dart' show AvisoFaixa;
import 'modelos.dart';
import 'pecas_profissional.dart';
import 'primeiros_passos.dart';

/// Tela 23 do protótipo: Início do profissional ("Pedidos perto de você").
/// Todos os botões chamam callbacks opcionais; sem callback, não fazem nada.
class InicioProfissionalTela extends StatefulWidget {
  const InicioProfissionalTela({
    super.key,
    required this.dados,
    this.aoAlterarDisponivel,
    this.aoFazerCheckIn,
    this.aoAbrirCarteira,
    this.aoAbrirFiltros,
    this.aoAbrirPedido,
    this.aoAbrirNotificacoes,
    this.aoUsarComoCliente,
    this.aoAvisarACaminho,
    this.carregarPrimeirosPassos,
    this.aoCompletarPerfil,
    this.aoVerPedidos,
    this.aoVerAgenda,
  });

  /// Trilha dos primeiros passos (só profissional aprovado); nulo = não aparece.
  final Future<DadosPrimeirosPassos> Function()? carregarPrimeirosPassos;
  final ValueChanged<DestinoCompletar>? aoCompletarPerfil;
  final VoidCallback? aoVerPedidos;
  final VoidCallback? aoVerAgenda;

  /// Avisa o cliente que o profissional está a caminho. Sem isso, o botão não aparece.
  final Future<AvisoACaminho> Function(String pedidoId, int? etaMinutos)? aoAvisarACaminho;

  /// Abre as notificações. Sem isso, o sino não aparece.
  final VoidCallback? aoAbrirNotificacoes;

  /// Alterna para a visão de cliente.
  final VoidCallback? aoUsarComoCliente;

  final InicioProfissional dados;
  final ValueChanged<bool>? aoAlterarDisponivel;
  final VoidCallback? aoFazerCheckIn;
  final VoidCallback? aoAbrirCarteira;
  final VoidCallback? aoAbrirFiltros;
  final ValueChanged<PedidoAberto>? aoAbrirPedido;

  @override
  State<InicioProfissionalTela> createState() => _InicioProfissionalTelaState();
}

class _InicioProfissionalTelaState extends State<InicioProfissionalTela> {
  late bool _disponivel = widget.dados.disponivelAgora;

  @override
  void didUpdateWidget(covariant InicioProfissionalTela oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.dados.disponivelAgora != widget.dados.disponivelAgora) {
      _disponivel = widget.dados.disponivelAgora;
    }
  }

  @override
  Widget build(BuildContext context) {
    final dados = widget.dados;
    final recarregar = AtualizadorTela.de(context);
    final rolagem = SingleChildScrollView(
      physics: recarregar != null ? const AlwaysScrollableScrollPhysics() : null,
      padding: const EdgeInsets.symmetric(vertical: EspacosTrato.x4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Olá, ${dados.nome}',
                      style:
                          TipografiaTrato.corpoPequeno.copyWith(color: CoresTrato.textoSecundario),
                    ),
                    const SizedBox(height: EspacosTrato.x1),
                    Text('Pedidos perto de você', style: TipografiaTrato.tituloGrande),
                  ],
                ),
              ),
              if (widget.aoAbrirNotificacoes != null) ...[
                const SizedBox(width: EspacosTrato.x2),
                Builder(
                  builder: (context) {
                    final c = context.cores;
                    final naoLidas = dados.notificacoesNaoLidas;
                    final icone = Icon(Icons.notifications_none, color: c.texto);
                    return Semantics(
                      button: true,
                      label: 'Notificações',
                      value: naoLidas > 0 ? '$naoLidas não lidas' : null,
                      excludeSemantics: true,
                      child: Material(
                        color: c.superficie,
                        shape: CircleBorder(side: BorderSide(color: c.borda)),
                        child: InkWell(
                          customBorder: const CircleBorder(),
                          onTap: widget.aoAbrirNotificacoes,
                          child: SizedBox.square(
                            dimension: 48,
                            child: Center(
                              child: naoLidas > 0
                                  ? Badge.count(
                                      count: naoLidas,
                                      maxCount: 99,
                                      backgroundColor: c.laranja,
                                      textColor: CoresTrato.petroleo,
                                      child: icone,
                                    )
                                  : icone,
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ],
            ],
          ),
          if (dados.emAnalise) ...[
            const SizedBox(height: EspacosTrato.x4),
            const AvisoFaixa(
              texto:
                  'Seu cadastro está em análise. Assim que sua verificação for aprovada, os pedidos da sua região aparecerão aqui.',
              tipo: TipoStatus.info,
              icone: Icons.hourglass_top_outlined,
            ),
          ],
          if (!dados.emAnalise)
            CartaoPrimeirosPassos(
              carregar: widget.carregarPrimeirosPassos,
              orcamentosEnviados: dados.orcamentosEnviados.length,
              semPedidosAbertos: dados.pedidos.isEmpty,
              aoCompletar: widget.aoCompletarPerfil,
              aoVerPedidos: widget.aoVerPedidos,
              aoVerAgenda: widget.aoVerAgenda,
            ),
          // Só aparece quando alguém grava a escolha: o backend ainda não tem "disponível agora",
          // e um interruptor que não grava em lugar nenhum engana o profissional.
          if (widget.aoAlterarDisponivel != null) ...[
            const SizedBox(height: EspacosTrato.x4),
            _CartaoDisponivel(
              ligado: _disponivel,
              aoMudar: (v) {
                setState(() => _disponivel = v);
                widget.aoAlterarDisponivel?.call(v);
              },
            ),
          ],
          if (dados.proximo != null) ...[
            const SizedBox(height: EspacosTrato.x4),
            _CartaoProximo(
              proximo: dados.proximo!,
              aoFazerCheckIn: widget.aoFazerCheckIn,
              aoAvisarACaminho: widget.aoAvisarACaminho,
            ),
          ],
          const SizedBox(height: EspacosTrato.x4),
          _CartaoCarteira(carteira: dados.carteira, aoTocar: widget.aoAbrirCarteira),
          if (dados.exclusividades != null) ...[
            const SizedBox(height: EspacosTrato.x4),
            _CartaoExclusividades(resumo: dados.exclusividades!),
          ],
          const SizedBox(height: EspacosTrato.x5),
          Row(
            children: [
              Expanded(child: Text('Pedidos abertos', style: TipografiaTrato.titulo)),
              BotaoLink(texto: 'Filtros', aoTocar: widget.aoAbrirFiltros ?? () {}),
            ],
          ),
          const SizedBox(height: EspacosTrato.x2),
          if (dados.pedidos.isEmpty)
            CartaoTrato(
              child: Text(
                dados.emAnalise
                    ? 'Assim que seu cadastro for aprovado, os pedidos disponíveis aparecerão aqui.'
                    : 'Nenhum pedido aberto na sua região no momento.',
                style: TipografiaTrato.corpoPequeno.copyWith(color: CoresTrato.textoSecundario),
              ),
            )
          else
            for (final pedido in dados.pedidos) ...[
              CartaoPedidoAberto(
                pedido: pedido,
                aoTocar: widget.aoAbrirPedido == null ? null : () => widget.aoAbrirPedido!(pedido),
              ),
              const SizedBox(height: EspacosTrato.x3),
            ],
        ],
      ),
    );
    return Scaffold(
      body: SafeArea(
        child: ConteudoResponsivo(
          child: recarregar == null
              ? rolagem
              : RefreshIndicator(onRefresh: recarregar, child: rolagem),
        ),
      ),
    );
  }
}

class _CartaoDisponivel extends StatelessWidget {
  const _CartaoDisponivel({required this.ligado, required this.aoMudar});

  final bool ligado;
  final ValueChanged<bool> aoMudar;

  @override
  Widget build(BuildContext context) {
    return CartaoTrato(
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Disponível agora', style: TipografiaTrato.tituloCartao),
                const SizedBox(height: EspacosTrato.x1),
                Text(
                  'Você recebe pedidos urgentes da sua região',
                  style: TipografiaTrato.corpoPequeno.copyWith(color: CoresTrato.textoSecundario),
                ),
              ],
            ),
          ),
          const SizedBox(width: EspacosTrato.x3),
          Semantics(
            label: 'Disponível agora',
            child: Switch(
              value: ligado,
              onChanged: aoMudar,
              activeTrackColor: CoresTrato.petroleo,
              activeThumbColor: CoresTrato.creme,
              inactiveTrackColor: CoresTrato.borda,
              inactiveThumbColor: CoresTrato.superficie,
              trackOutlineColor: const WidgetStatePropertyAll(CoresTrato.petroleo),
            ),
          ),
        ],
      ),
    );
  }
}

class _CartaoProximo extends StatelessWidget {
  const _CartaoProximo({
    required this.proximo,
    required this.aoFazerCheckIn,
    this.aoAvisarACaminho,
  });

  final ProximoAtendimento proximo;
  final VoidCallback? aoFazerCheckIn;
  final Future<AvisoACaminho> Function(String pedidoId, int? etaMinutos)? aoAvisarACaminho;

  @override
  Widget build(BuildContext context) {
    return CartaoTrato(
      escuro: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            proximo.quando.toUpperCase(),
            style: TipografiaTrato.sobretitulo.copyWith(color: CoresTrato.creme),
          ),
          const SizedBox(height: EspacosTrato.x3),
          Text(
            proximo.titulo,
            style: TipografiaTrato.titulo.copyWith(color: CoresTrato.creme),
          ),
          const SizedBox(height: EspacosTrato.x3),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.place_outlined, color: CoresTrato.creme),
              const SizedBox(width: EspacosTrato.x2),
              Expanded(
                child: Text(
                  proximo.endereco,
                  style: TipografiaTrato.corpo.copyWith(color: CoresTrato.creme),
                ),
              ),
            ],
          ),
          if (oQueFazerAgora(proximo.estadoApi, remoto: proximo.remoto) case final agora?) ...[
            const SizedBox(height: EspacosTrato.x3),
            Text(
              'O que fazer agora: $agora',
              key: const ValueKey('o-que-fazer-agora'),
              style: TipografiaTrato.corpoForte.copyWith(color: CoresTrato.creme),
            ),
          ],
          const SizedBox(height: EspacosTrato.x4),
          BotaoSecundario(
            texto: proximo.precisaAgendarVisita
                ? (proximo.remoto ? 'Combinar início' : 'Marcar data da visita')
                : (proximo.emAndamento
                    ? 'Gerenciar serviço (check-out)'
                    : (proximo.remoto ? 'Iniciar atendimento' : 'Fazer check-in')),
            aoTocar: aoFazerCheckIn ?? () {},
          ),
          if (proximo.agendado && !proximo.remoto && aoAvisarACaminho != null) ...[
            const SizedBox(height: EspacosTrato.x3),
            _AvisoACaminho(pedidoId: proximo.pedidoId!, enviar: aoAvisarACaminho!),
          ],
        ],
      ),
    );
  }
}

/// "Estou a caminho": chips opcionais de tempo (15, 30, 45 min) e o botão. Erro nunca trava a tela.
class _AvisoACaminho extends StatefulWidget {
  const _AvisoACaminho({required this.pedidoId, required this.enviar});

  final String pedidoId;
  final Future<AvisoACaminho> Function(String pedidoId, int? etaMinutos) enviar;

  @override
  State<_AvisoACaminho> createState() => _AvisoACaminhoState();
}

class _AvisoACaminhoState extends State<_AvisoACaminho> {
  int? _eta;
  var _enviando = false;
  String? _mensagem;

  Future<void> _avisar() async {
    if (_enviando) return;
    setState(() {
      _enviando = true;
      _mensagem = null;
    });
    String texto;
    try {
      final r = await widget.enviar(widget.pedidoId, _eta);
      texto = r.enviado ? 'Aviso enviado ao cliente' : 'Você já avisou há pouco';
    } on ErroTrato catch (e) {
      texto = switch (e.codigoHttp) {
        409 => 'Só dá para avisar em serviço agendado',
        403 || 404 => 'Não encontramos este pedido para avisar.',
        _ => 'Não deu para avisar agora. Tente de novo.',
      };
    } on Object {
      texto = 'Não deu para avisar agora. Tente de novo.';
    }
    if (mounted) {
      setState(() {
        _enviando = false;
        _mensagem = texto;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: EspacosTrato.x2,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(
              'Chego em:',
              style: TipografiaTrato.corpoPequeno.copyWith(color: CoresTrato.creme),
            ),
            for (final min in const [15, 30, 45])
              ChoiceChip(
                key: Key('eta-$min'),
                label: Text('$min min'),
                selected: _eta == min,
                onSelected: (sel) => setState(() => _eta = sel ? min : null),
              ),
          ],
        ),
        const SizedBox(height: EspacosTrato.x2),
        BotaoSecundario(
          texto: _enviando ? 'Avisando...' : 'Estou a caminho',
          aoTocar: _avisar,
        ),
        if (_mensagem != null)
          Padding(
            padding: const EdgeInsets.only(top: EspacosTrato.x2),
            child: Semantics(
              liveRegion: true,
              child: Text(
                _mensagem!,
                key: const Key('mensagem-a-caminho'),
                style: TipografiaTrato.corpoPequeno.copyWith(color: CoresTrato.creme),
              ),
            ),
          ),
      ],
    );
  }
}

class _CartaoCarteira extends StatelessWidget {
  const _CartaoCarteira({required this.carteira, required this.aoTocar});

  final ResumoCarteira carteira;
  final VoidCallback? aoTocar;

  @override
  Widget build(BuildContext context) {
    return CartaoTrato(
      aoTocar: aoTocar ?? () {},
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: _Valor(rotulo: 'Em andamento', centavos: carteira.retidoCentavos)),
              const SizedBox(width: EspacosTrato.x3),
              Expanded(child: _Valor(rotulo: 'Liberado', centavos: carteira.paraSacarCentavos)),
            ],
          ),
          if ((carteira.retidoDesdePagamentoCentavos ?? 0) > 0) ...[
            const SizedBox(height: EspacosTrato.x2),
            _Valor(
              key: const Key('valor-retido'),
              rotulo: 'Retido',
              centavos: carteira.retidoDesdePagamentoCentavos!,
            ),
          ],
          if (carteira.proximaLiberacao != null) ...[
            const SizedBox(height: EspacosTrato.x2),
            Text(
              'Repasse do dinheiro: ${diaMesDoAparelho(carteira.proximaLiberacao!)}',
              key: const Key('repasse-previsto'),
              style: TipografiaTrato.corpoPequeno.copyWith(color: CoresTrato.textoSecundario),
            ),
          ],
          for (final l in carteira.liberacoesPrevistas) ...[
            const SizedBox(height: EspacosTrato.x1),
            Text(
              'Pedido ${l.pedidoNumero} · ${formatarReais(l.valorCentavos)}'
              '${l.liberacaoPrevistaEm == null ? '' : ' · ${diaMesDoAparelho(l.liberacaoPrevistaEm!)}'}',
              key: const Key('liberacao-prevista'),
              style: TipografiaTrato.corpoPequeno.copyWith(color: CoresTrato.textoSecundario),
            ),
          ],
        ],
      ),
    );
  }
}

class _Valor extends StatelessWidget {
  const _Valor({super.key, required this.rotulo, required this.centavos});

  final String rotulo;
  final int centavos;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          rotulo,
          style: TipografiaTrato.corpoPequeno.copyWith(color: CoresTrato.textoSecundario),
        ),
        const SizedBox(height: EspacosTrato.x1),
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(formatarReais(centavos), style: TipografiaTrato.tituloCartao, maxLines: 1),
        ),
      ],
    );
  }
}

class _CartaoExclusividades extends StatelessWidget {
  const _CartaoExclusividades({required this.resumo});

  final ResumoExclusividades resumo;

  @override
  Widget build(BuildContext context) {
    final recentes = resumo.itens.take(3).toList();
    return CartaoTrato(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Exclusividades: ${resumo.ativasOuPendentes} de ${resumo.limiteMaximo}',
                  style: TipografiaTrato.tituloCartao,
                ),
              ),
              Text(
                textoTratinhos(resumo.saldoProfissional),
                style: TipografiaTrato.corpoForte.copyWith(color: CoresTrato.petroleo),
              ),
            ],
          ),
          const SizedBox(height: EspacosTrato.x1),
          Text(
            'Ganhe Tratinhos avaliando clientes e use 100 para pedir 48h de exclusividade.',
            style: TipografiaTrato.corpoPequeno.copyWith(color: CoresTrato.textoSecundario),
          ),
          if (resumo.moedasPendentesProfissional > 0) ...[
            const SizedBox(height: EspacosTrato.x1),
            Text(
              textoTratinhosPendentes(
                    resumo.moedasPendentesProfissional,
                    resumo.moedasPendentesLiberacao,
                    resumo.moedaValorCentavos,
                  ) ??
                  '${textoTratinhos(resumo.moedasPendentesProfissional)} a liberar',
              style: TipografiaTrato.corpoPequeno.copyWith(color: CoresTrato.textoSecundario),
            ),
          ],
          if (recentes.isNotEmpty) ...[
            const SizedBox(height: EspacosTrato.x2),
            for (final item in recentes)
              Padding(
                padding: const EdgeInsets.only(top: EspacosTrato.x1),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        item.tituloPedido ?? 'Pedido ${item.pedidoId}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TipografiaTrato.corpoPequeno,
                      ),
                    ),
                    const SizedBox(width: EspacosTrato.x2),
                    Text(
                      item.rotuloStatus,
                      style: TipografiaTrato.legenda.copyWith(color: CoresTrato.textoSecundario),
                    ),
                  ],
                ),
              ),
          ],
        ],
      ),
    );
  }
}

class CartaoPedidoAberto extends StatelessWidget {
  const CartaoPedidoAberto({super.key, required this.pedido, required this.aoTocar});

  final PedidoAberto pedido;
  final VoidCallback? aoTocar;

  @override
  Widget build(BuildContext context) {
    final secundario = TipografiaTrato.corpoPequeno.copyWith(color: CoresTrato.textoSecundario);
    final partesSub = [
      if (pedido.remoto)
        'Atendimento remoto'
      else ...[
        if (pedido.bairro.isNotEmpty) pedido.bairro,
        textoDistancia(pedido.distanciaKm),
      ],
      if (!pedido.urgente || pedido.prazo.toLowerCase() != 'urgente') pedido.prazo,
    ].where((t) => t.isNotEmpty);
    return Semantics(
      button: true,
      label: '${pedido.titulo}${pedido.urgente ? ', urgente' : ''}, ${textoFaixa(pedido)}',
      child: GestureDetector(
        onTap: aoTocar,
        behavior: HitTestBehavior.opaque,
        child: CartaoTrato(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: Text(pedido.titulo, style: TipografiaTrato.tituloCartao)),
                  if (pedido.convidado) ...[
                    const SizedBox(width: EspacosTrato.x2),
                    const ChipStatus(texto: 'Para você', tipo: TipoStatus.sucesso),
                  ],
                  if (pedido.remoto) ...[
                    const SizedBox(width: EspacosTrato.x2),
                    const ChipStatus(texto: 'Remoto', tipo: TipoStatus.info),
                  ],
                  if (pedido.urgente) ...[
                    const SizedBox(width: EspacosTrato.x2),
                    const ChipStatus(texto: 'Urgente', tipo: TipoStatus.destaque),
                  ],
                ],
              ),
              if (pedido.reservado || (pedido.exclusividade?.aguardandoCliente ?? false)) ...[
                const SizedBox(height: EspacosTrato.x2),
                Wrap(
                  spacing: EspacosTrato.x2,
                  runSpacing: EspacosTrato.x1,
                  children: [
                    if (pedido.reservado)
                      const ChipStatus(texto: 'Reservado para você', tipo: TipoStatus.sucesso)
                    else
                      const ChipStatus(
                        texto: 'Oferta enviada, aguardando o cliente',
                        tipo: TipoStatus.info,
                      ),
                  ],
                ),
              ],
              const SizedBox(height: EspacosTrato.x2),
              Text(
                partesSub.join(' · '),
                style: secundario,
              ),
              const SizedBox(height: EspacosTrato.x2),
              Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: EspacosTrato.x3,
                children: [
                  Text(textoFaixa(pedido), style: TipografiaTrato.corpoForte),
                  Text(textoOrcamentos(pedido), style: secundario),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
