import '../cliente/avatar_de_usuario.dart';
import 'package:flutter/material.dart';

import '../../componentes/componentes.dart';
import '../../tema/tema.dart';
import '../cliente/avatar_iniciais.dart';
import '../cliente/modelos.dart' show formatarNota;
import '../comuns/foco_rolagem.dart';
import '../conclusao/apoio_conclusao.dart' show LinhaValor, formatarReais;
import '../pedido_novo/pecas_pedido.dart';
import 'modelos.dart';

/// Tela 13 do protótipo: detalhe do orçamento, com aceite e contraproposta.
///
/// Só mostra o que vier de [orcamento]; o 30% adiantado e a taxa são do backend. Os callbacks
/// são opcionais; sem eles, o botão não aparece. [aoAceitar] só dispara com o aceite marcado.
class DetalheOrcamentoTela extends StatefulWidget {
  const DetalheOrcamentoTela({
    super.key,
    required this.orcamento,
    this.aoAceitar,
    this.aoRecusar,
    this.aoFazerContraproposta,
    this.aoConversar,
    this.aoVerPerfil,
    this.contrato = false,
    this.dadosContrato,
    this.aoVerTermos,
  });

  /// No modo contrato: o pedido, as partes, datas, local, pagamento e aditivos.
  final DadosContrato? dadosContrato;

  /// Abre os Termos de uso (regras de cancelamento e garantia).
  final VoidCallback? aoVerTermos;

  /// Mostra o orçamento aceito como o contrato do serviço: só leitura, sem aceitar,
  /// contraproposta nem a caixa de "li e aceito".
  final bool contrato;

  final Orcamento orcamento;
  final dynamic Function(Orcamento)? aoAceitar;
  final dynamic Function(Orcamento)? aoRecusar;
  final ValueChanged<Orcamento>? aoFazerContraproposta;
  final ValueChanged<Orcamento>? aoConversar;

  /// Abre o perfil público do profissional. Sem ele, o link não aparece.
  final ValueChanged<Orcamento>? aoVerPerfil;

  @override
  State<DetalheOrcamentoTela> createState() => _DetalheOrcamentoTelaState();
}

class _DetalheOrcamentoTelaState extends State<DetalheOrcamentoTela> {
  final _scroll = ScrollController();
  final _keyAceite = GlobalKey();
  var _leu = false;
  var _tentou = false;
  var _aceitando = false;

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _confirmarRecusa() async {
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (dialogo) => AlertDialog(
        title: const Text('Recusar orçamento?'),
        content: const Text('Este orçamento sairá da sua lista de pendentes.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogo).pop(false),
            child: const Text('Voltar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogo).pop(true),
            child: const Text('Recusar'),
          ),
        ],
      ),
    );
    if (confirmar != true || !mounted) return;
    setState(() => _aceitando = true);
    try {
      await widget.aoRecusar?.call(widget.orcamento);
    } finally {
      if (mounted) setState(() => _aceitando = false);
    }
  }

  Future<void> _aceitar() async {
    if (_aceitando) return;
    setState(() => _tentou = true);
    if (!_leu) {
      focarPrimeiroErro([
        EntradaCampoErro(key: _keyAceite, temErro: () => !_leu),
      ]);
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
              content: Text(
                  'Marque "Li o que está incluso, a garantia e o cancelamento" para aceitar.')),
        );
      return;
    }
    setState(() => _aceitando = true);
    try {
      await widget.aoAceitar?.call(widget.orcamento);
    } finally {
      if (mounted) setState(() => _aceitando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final o = widget.orcamento;
    final d = o.detalhe!; // a tela só abre para orçamento com detalhe
    final secundario = TipografiaTrato.corpoPequeno.copyWith(color: CoresTrato.textoSecundario);
    return EstruturaPedido(
      scrollController: _scroll,
      tituloBarra: widget.contrato ? 'Contrato do serviço' : 'Válido até ${d.validoAte}',
      acoesBarra: [
        if (widget.aoConversar != null) ...[
          TextButton.icon(
            onPressed: () => widget.aoConversar!(o),
            icon: const Icon(Icons.chat_bubble_outline, size: EspacosTrato.x5),
            label: const Text('Conversar'),
            style: TextButton.styleFrom(
              textStyle: TipografiaTrato.corpoForte.copyWith(decoration: TextDecoration.none),
            ),
          ),
          const SizedBox(width: EspacosTrato.x2),
        ],
      ],
      rodape: widget.contrato
          ? null
          : Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                BotaoPrimario(
                  texto: 'Aceitar e ir para o pagamento',
                  carregando: _aceitando,
                  aoTocar: _aceitando ? null : _aceitar,
                ),
                if (widget.aoFazerContraproposta != null)
                  BotaoLink(
                    texto: 'Fazer contraproposta',
                    aoTocar: () => widget.aoFazerContraproposta!(o),
                  ),
                if (widget.aoRecusar != null)
                  BotaoLink(
                    key: const ValueKey('botao-recusar-orcamento'),
                    texto: 'Recusar orçamento',
                    destrutivo: true,
                    aoTocar: _aceitando ? null : _confirmarRecusa,
                  ),
              ],
            ),
      children: [
        if (widget.contrato && widget.dadosContrato != null) ...[
          Text(
            'Pedido ${widget.dadosContrato!.numeroPedido}'
            '${widget.dadosContrato!.contratadoEm == null ? '' : ' · contratado em ${widget.dadosContrato!.contratadoEm}'}',
            key: const ValueKey('contrato-cabecalho'),
            style: secundario,
          ),
          const SizedBox(height: EspacosTrato.x3),
        ],
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            AvatarDeUsuario(iniciais: o.iniciais, usuarioId: o.profissionalId, tamanho: 64),
            const SizedBox(width: EspacosTrato.x4),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(o.profissional, style: TipografiaTrato.tituloGrande),
                  const SizedBox(height: EspacosTrato.x1),
                  Builder(
                    builder: (_) {
                      final iniciante = o.servicosConcluidos == 0 && o.notaResumo == semAvaliacoes;
                      final selo = o.verificacao.isNotEmpty
                          ? o.verificacao
                          : (iniciante ? 'Identidade verificada' : '');
                      return Wrap(
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          if (selo.isNotEmpty) SeloVerificacao(selo),
                          Text(
                            iniciante
                                ? '${selo.isNotEmpty ? ' · ' : ''}Novo no Trato'
                                : '${selo.isNotEmpty ? ' · ' : ''}'
                                    '${o.notaResumo == semAvaliacoes ? semAvaliacoes : 'Nota ${formatarNota(o.nota)}'}'
                                    ' · ${o.servicosConcluidos} '
                                    '${o.servicosConcluidos == 1 ? 'serviço' : 'serviços'}',
                            style: secundario,
                          ),
                        ],
                      );
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
        if (widget.aoVerPerfil != null)
          BotaoLink(
            texto: 'Ver perfil de ${o.profissional}',
            aoTocar: () => widget.aoVerPerfil!(o),
          ),
        const SizedBox(height: EspacosTrato.x4),
        CartaoTrato(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('O que está incluso', style: TipografiaTrato.tituloOpcao),
              const SizedBox(height: EspacosTrato.x4),
              for (final item in d.itens) ...[
                LinhaValor(rotulo: item.descricao, valor: formatarReais(item.centavos)),
                if (contaDoItem(item) case final conta?)
                  Padding(
                    padding: const EdgeInsets.only(top: EspacosTrato.x1),
                    child: Text(conta, style: secundario),
                  ),
                const SizedBox(height: EspacosTrato.x3),
              ],
              if (d.totalHoras.isNotEmpty) ...[
                LinhaValor(
                  key: const ValueKey('total-horas-orcamento'),
                  rotulo: 'Total de horas',
                  valor: d.totalHoras,
                ),
                if (d.horasDeslocamento.isNotEmpty && d.horasTrabalhadas.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: EspacosTrato.x1),
                    child: Text(
                      '${d.horasTrabalhadas} trabalhadas + ${d.horasDeslocamento} de deslocamento',
                      style: secundario,
                    ),
                  ),
                const SizedBox(height: EspacosTrato.x3),
              ],
              const Divider(),
              const SizedBox(height: EspacosTrato.x3),
              LinhaValor(rotulo: 'Total', valor: formatarReais(o.totalCentavos), destaque: true),
              const SizedBox(height: EspacosTrato.x3),
              Text(d.notaMaterial, style: secundario),
            ],
          ),
        ),
        const SizedBox(height: EspacosTrato.x4),
        Card(
          child: Column(
            children: [
              if (d.agendaTitulo.trim().isNotEmpty) ...[
                _BlocoRegra(
                  icone: Icons.calendar_today_outlined,
                  titulo: d.agendaTitulo,
                  texto: d.agendaDetalhe,
                ),
                const Divider(height: 1),
              ],
              _BlocoRegra(
                icone: Icons.verified_user_outlined,
                titulo: d.garantiaTitulo,
                texto: d.garantiaDetalhe,
              ),
              // Bloco sem texto não aparece: o profissional pode não ter preenchido.
              if (d.foraDoEscopo.trim().isNotEmpty || widget.contrato) ...[
                const Divider(height: 1),
                _BlocoRegra(
                  icone: Icons.warning_amber_rounded,
                  titulo: 'Fora do escopo',
                  texto: d.foraDoEscopo.trim().isNotEmpty
                      ? d.foraDoEscopo
                      : 'O profissional não listou exclusões. Vale o que está nos itens acima.',
                ),
              ],
              if (d.cancelamento.trim().isNotEmpty) ...[
                const Divider(height: 1),
                _BlocoRegra(
                  icone: Icons.schedule,
                  titulo: 'Cancelamento',
                  texto: d.cancelamento,
                ),
              ],
            ],
          ),
        ),
        if (widget.contrato) ...[
          if (widget.dadosContrato != null)
            _SecoesDoContrato(
              dados: widget.dadosContrato!,
              profissional: o.profissional,
              aoVerTermos: widget.aoVerTermos,
            ),
          const SizedBox(height: EspacosTrato.x4),
          Text(
            'Este é o orçamento que você aceitou: ele vale como o contrato do serviço '
            '(escopo, valor e garantia).',
            key: const ValueKey('aviso-contrato'),
            style: TipografiaTrato.corpo,
          ),
        ] else ...[
          const SizedBox(height: EspacosTrato.x4),
          KeyedSubtree(
            key: _keyAceite,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => setState(() => _leu = !_leu),
                  child: MergeSemantics(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Checkbox(value: _leu, onChanged: (v) => setState(() => _leu = v ?? false)),
                        const SizedBox(width: EspacosTrato.x2),
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.only(top: EspacosTrato.x3),
                            child: Text(
                              'Li o que está incluso, a garantia e o cancelamento.',
                              style: TipografiaTrato.corpo,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(left: EspacosTrato.x3, top: EspacosTrato.x1),
                  child: Text(
                    'Cancelar antes de o serviço começar não gera cobrança do profissional.',
                    style: TipografiaTrato.corpoPequeno.copyWith(color: CoresTrato.textoSecundario),
                  ),
                ),
                if (_tentou && !_leu)
                  Text(
                    'Marque que leu para aceitar o orçamento.',
                    style: TipografiaTrato.legenda.copyWith(color: CoresTrato.vermelhoTexto),
                  ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _BlocoRegra extends StatelessWidget {
  const _BlocoRegra({required this.icone, required this.titulo, required this.texto});

  final IconData icone;
  final String titulo;
  final String texto;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(EspacosTrato.paddingCartao),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icone, color: CoresTrato.petroleo),
          const SizedBox(width: EspacosTrato.x3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(titulo, style: TipografiaTrato.corpoForte),
                const SizedBox(height: EspacosTrato.x1),
                Text(
                  texto,
                  style: TipografiaTrato.corpoPequeno.copyWith(color: CoresTrato.textoSecundario),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// A conta da linha: "45 h × R\$ 15,00 por hora" ou "2 × R\$ 30,00". Nula quando não há o que
/// explicar (quantidade 1 de item comum, ou dado faltando).
String? contaDoItem(ItemOrcamento item) {
  final q = item.quantidade;
  final u = item.unitarioCentavos;
  if (q == null || u == null || q <= 0) return null;
  final qtd = q == q.roundToDouble() ? q.toInt().toString() : q.toString().replaceAll('.', ',');
  if (item.porHora) return '$qtd h × ${formatarReais(u)} por hora';
  if (q == 1) return null;
  return '$qtd × ${formatarReais(u)}';
}

/// O contrato além do orçamento: o que foi pedido, as partes, quando e onde, pagamento e regras.
class _SecoesDoContrato extends StatelessWidget {
  const _SecoesDoContrato({required this.dados, required this.profissional, this.aoVerTermos});

  final DadosContrato dados;
  final String profissional;
  final VoidCallback? aoVerTermos;

  @override
  Widget build(BuildContext context) {
    final secundario = TipografiaTrato.corpoPequeno.copyWith(color: CoresTrato.textoSecundario);
    Widget secao(String titulo, List<Widget> filhos, {Key? key}) => Padding(
          padding: const EdgeInsets.only(top: EspacosTrato.x4),
          child: CartaoTrato(
            key: key,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(titulo, style: TipografiaTrato.tituloOpcao),
                const SizedBox(height: EspacosTrato.x3),
                ...filhos,
              ],
            ),
          ),
        );
    Widget linha(String rotulo, String valor) => Padding(
          padding: const EdgeInsets.only(bottom: EspacosTrato.x2),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(rotulo, style: secundario),
              Text(valor, style: TipografiaTrato.corpo),
            ],
          ),
        );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        secao('O que foi contratado', key: const ValueKey('contrato-servico'), [
          Text(dados.titulo, style: TipografiaTrato.corpoForte),
          if (dados.descricao.isNotEmpty) ...[
            const SizedBox(height: EspacosTrato.x1),
            Text(dados.descricao, style: TipografiaTrato.corpo),
          ],
          if (dados.respostas.isNotEmpty) const SizedBox(height: EspacosTrato.x3),
          for (final r in dados.respostas) linha(r.rotulo, r.valor),
        ]),
        secao('Partes', key: const ValueKey('contrato-partes'), [
          linha('Contratante', dados.cliente ?? 'Você'),
          linha('Profissional', profissional),
        ]),
        secao('Quando e onde', key: const ValueKey('contrato-local'), [
          linha('Visita', dados.visita ?? 'Ainda não marcada'),
          linha('Local do serviço', dados.local),
        ]),
        secao('Pagamento', key: const ValueKey('contrato-pagamento'), [
          linha(
            'Pago pelo app',
            dados.pagoCentavos == null
                ? 'Aguardando a confirmação do pagamento'
                : formatarReais(dados.pagoCentavos!),
          ),
          if (dados.aditivos.isEmpty)
            linha('Aditivos', 'Nenhum')
          else
            for (final a in dados.aditivos) linha(a.rotulo, a.valor),
          Text(
            'O valor fica retido pelo processamento do app e só é liberado ao profissional '
            'depois que você confirma o serviço.',
            style: secundario,
          ),
        ]),
        secao('Regras', key: const ValueKey('contrato-regras'), [
          Text(
            'Garantia: se o problema voltar dentro do prazo, peça o retrabalho pela tela de '
            'garantia. O profissional tem ${dados.prazoRetrabalhoDias} '
            '${dados.prazoRetrabalhoDias == 1 ? 'dia' : 'dias'} para atender; sem atendimento, '
            'o suporte analisa o caso.',
            style: TipografiaTrato.corpo,
          ),
          const SizedBox(height: EspacosTrato.x2),
          Text(
            'Cancelamento e demais regras seguem os Termos de uso do Trato.',
            style: TipografiaTrato.corpo,
          ),
          if (aoVerTermos != null) BotaoLink(texto: 'Ver termos de uso', aoTocar: aoVerTermos!),
        ]),
      ],
    );
  }
}
