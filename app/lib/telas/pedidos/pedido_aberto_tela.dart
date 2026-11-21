import 'package:flutter/material.dart';

import '../../componentes/componentes.dart';
import '../../dados/erros.dart';
import '../../dados/repositorios.dart';
import '../../dados/servico_cep.dart';
import '../../tema/tema.dart';
import '../comuns/foco_rolagem.dart';
import '../comuns/formato_aparelho.dart' show diaMesDoAparelho, horaDoAparelho;
import '../profissional_apoio/apoio.dart' show AvisoFaixa;
import 'modelos.dart' show OfertaExclusividadeCliente;
import '../conclusao/apoio_conclusao.dart' show EspacoFoto, formatarReais;
import '../pedido_novo/pecas_pedido.dart';
import '../profissional/dinheiro.dart';

/// "R$ 1.250,50", "1250,5" ou "1250" viram centavos. Vazio ou inválido: nulo.
int? centavosDoTexto(String texto) {
  final limpo = texto.replaceAll(RegExp(r'[^0-9,]'), '').replaceAll('.', '');
  if (limpo.isEmpty) return null;
  final partes = limpo.split(',');
  final reais = int.tryParse(partes[0].isEmpty ? '0' : partes[0]);
  if (reais == null) return null;
  var centavos = 0;
  if (partes.length > 1 && partes[1].isNotEmpty) {
    centavos = int.tryParse(partes[1].padRight(2, '0').substring(0, 2)) ?? 0;
  }
  return reais * 100 + centavos;
}

/// O pedido do cliente enquanto aguarda orçamentos: mostra o que foi descrito e deixa trocar
/// descrição, valor pretendido e endereço. O backend decide se ainda pode editar.
class PedidoAbertoTela extends StatefulWidget {
  const PedidoAbertoTela({
    super.key,
    required this.numero,
    required this.dados,
    required this.aoSalvar,
    required this.aoVerOrcamentos,
    this.aoCancelar,
    this.servicoCep,
    this.cepInicial = '',
    this.aoResponderExclusividade,
  });

  final String numero;
  final DadosDoPedido dados;
  final ServicoCep? servicoCep;
  final String cepInicial;

  /// Devolve os dados como ficaram gravados; se falhar, a própria função avisa e devolve nulo.
  final Future<DadosDoPedido?> Function({
    required String descricao,
    required int faixaMaxCentavos,
    required String logradouro,
    required String numero,
    required String bairro,
    String? cep,
  }) aoSalvar;
  final VoidCallback aoVerOrcamentos;

  /// Cancelar o pedido; o botão some se nulo.
  final VoidCallback? aoCancelar;

  /// Aceita ou recusa a oferta de exclusividade de 48h (`decisao`: `'aceitar'` ou `'recusar'`).
  final Future<OfertaExclusividadeCliente> Function(String exclusividadeId, String decisao)?
      aoResponderExclusividade;

  @override
  State<PedidoAbertoTela> createState() => _PedidoAbertoTelaState();
}

class _PedidoAbertoTelaState extends State<PedidoAbertoTela> {
  final _scroll = ScrollController();
  late DadosDoPedido _dados = widget.dados;
  var _editando = false;
  var _salvando = false;
  var _tentou = false;
  var _respondendoExclusividade = false;
  String? _erro;
  String? _erroValor;
  String? _erroExclusividade;
  OfertaExclusividadeCliente? _ofertaLocal;

  late final _descricao = TextEditingController(text: _dados.descricao);
  late final _valor = TextEditingController();
  late final _cep = TextEditingController(text: widget.cepInicial);
  late final _rua = TextEditingController(text: _dados.logradouro ?? '');
  late final _numero = TextEditingController(text: _dados.numero ?? '');
  late final _bairro = TextEditingController(text: _dados.bairro ?? '');

  final _keyDescricao = GlobalKey();
  final _keyValor = GlobalKey();
  final _keyRua = GlobalKey();
  final _keyNumero = GlobalKey();
  final _keyBairro = GlobalKey();

  final _focoDescricao = FocusNode();
  final _focoValor = FocusNode();
  final _focoCep = FocusNode();
  final _focoRua = FocusNode();
  final _focoNumero = FocusNode();
  final _focoBairro = FocusNode();

  @override
  void dispose() {
    _scroll.dispose();
    for (final c in [_descricao, _valor, _cep, _rua, _numero, _bairro]) {
      c.dispose();
    }
    for (final f in [
      _focoDescricao,
      _focoValor,
      _focoCep,
      _focoRua,
      _focoNumero,
      _focoBairro,
    ]) {
      f.dispose();
    }
    super.dispose();
  }

  void _comecarEdicao() {
    _descricao.text = _dados.descricao;
    final max = _dados.faixaMaxCentavos;
    _valor.text = max == null ? '' : Dinheiro.paraCampo(max);
    _cep.text = widget.cepInicial;
    _rua.text = _dados.logradouro ?? '';
    _numero.text = _dados.numero ?? '';
    _bairro.text = _dados.bairro ?? '';
    setState(() {
      _editando = true;
      _tentou = false;
      _erro = null;
      _erroValor = null;
    });
  }

  Future<void> _salvar() async {
    setState(() => _tentou = true);
    final descricao = _descricao.text.trim();
    final textoValor = _valor.text.trim();
    final valor = textoValor.isEmpty ? 0 : centavosDoTexto(textoValor);
    final erroVal =
        textoValor.isNotEmpty && valor == null ? 'Informe o valor em reais (ex.: 900,00).' : null;
    setState(() => _erroValor = erroVal);

    if (descricao.isEmpty || erroVal != null) {
      focarPrimeiroErro([
        EntradaCampoErro(
          key: _keyDescricao,
          focusNode: _focoDescricao,
          temErro: () => _descricao.text.trim().isEmpty,
        ),
        EntradaCampoErro(
          key: _keyValor,
          focusNode: _focoValor,
          temErro: () => _erroValor != null,
        ),
      ]);
      return;
    }

    setState(() {
      _salvando = true;
      _erro = null;
    });
    final cepDigitos = _cep.text.replaceAll(RegExp(r'\D'), '');
    final novos = await widget.aoSalvar(
      descricao: descricao,
      faixaMaxCentavos: valor!,
      logradouro: _rua.text,
      numero: _numero.text,
      bairro: _bairro.text,
      cep: cepDigitos.length == 8 ? cepDigitos : null,
    );
    if (!mounted) return;
    setState(() {
      _salvando = false;
      if (novos != null) {
        _dados = novos;
        _editando = false;
        _tentou = false;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return EstruturaPedido(
      scrollController: _scroll,
      tituloBarra: 'Pedido #${widget.numero}',
      rodape: _editando
          ? Row(
              children: [
                Expanded(
                  child: BotaoSecundario(
                    texto: 'Cancelar',
                    aoTocar: _salvando ? null : () => setState(() => _editando = false),
                  ),
                ),
                const SizedBox(width: EspacosTrato.x3),
                Expanded(
                  child: BotaoPrimario(
                    texto: 'Salvar',
                    carregando: _salvando,
                    aoTocar: _salvar,
                  ),
                ),
              ],
            )
          : Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                BotaoPrimario(texto: 'Ver orçamentos', aoTocar: widget.aoVerOrcamentos),
                const SizedBox(height: EspacosTrato.x2),
                BotaoSecundario(texto: 'Editar pedido', aoTocar: _comecarEdicao),
                if (widget.aoCancelar != null)
                  BotaoLink(texto: 'Cancelar pedido', aoTocar: widget.aoCancelar!),
              ],
            ),
      children: [
        const SizedBox(width: double.infinity, height: EspacosTrato.x2),
        Text(
          (_dados.categoriaNome ?? '').isNotEmpty ? _dados.categoriaNome! : 'Seu pedido',
          key: const ValueKey('titulo-pedido'),
          style: TipografiaTrato.tituloGrande,
        ),
        const SizedBox(height: EspacosTrato.x2),
        Text(
          // Com categoria, a descrição que o cliente escreveu é o subtítulo; sem ela, o de antes.
          (_dados.categoriaNome ?? '').isNotEmpty && _dados.descricao.trim().isNotEmpty
              ? _dados.descricao
              : _dados.titulo,
          key: const ValueKey('subtitulo-pedido'),
          style: TipografiaTrato.corpo.copyWith(color: CoresTrato.textoSecundario),
        ),
        if (_dados.remoto) ...[
          const SizedBox(height: EspacosTrato.x3),
          const Align(
            alignment: Alignment.centerLeft,
            child: ChipStatus(
              key: ValueKey('selo-remoto'),
              texto: 'Remoto',
              tipo: TipoStatus.info,
              icone: Icons.videocam_outlined,
            ),
          ),
        ],
        if (!_editando) ...[
          const SizedBox(height: EspacosTrato.x5),
          const LinhaDoTempo(
            etapas: [
              EtapaLinhaDoTempo(
                titulo: 'Pedido enviado',
                detalhe: 'Os profissionais já podem ver',
                estado: EstadoEtapa.atual,
              ),
              EtapaLinhaDoTempo(
                titulo: 'Orçamentos',
                detalhe: 'Você compara e escolhe',
                estado: EstadoEtapa.futura,
              ),
              EtapaLinhaDoTempo(
                titulo: 'Contratação',
                detalhe: 'Você aceita um orçamento e paga',
                estado: EstadoEtapa.futura,
              ),
            ],
          ),
        ],
        if (!_editando && _dados.orcamentosRecebidos == 0) ...[
          const SizedBox(height: EspacosTrato.x4),
          AvisoFaixa(
            texto:
                'Pedido enviado aos profissionais ${_dados.remoto ? 'de qualquer região' : 'da região'} '
                '— avisaremos quando chegar o 1º orçamento.',
            tipo: TipoStatus.info,
            icone: Icons.notifications_active_outlined,
          ),
        ],
        if (!_editando) ..._cartaoExclusividade(),
        const SizedBox(height: EspacosTrato.x5),
        if (_editando) ..._formulario() else ..._resumo(),
      ],
    );
  }

  String _mensagemErroExclusividade(Object erro) {
    if (erro is ErroTrato) {
      return switch (erro.codigo) {
        'prazo_vencido' =>
          'O prazo para responder acabou. A oferta expirou e seus outros orçamentos seguem valendo.',
        'ja_respondida' => 'Você já respondeu a esta oferta.',
        'pedido_indisponivel' => 'Este pedido não está mais aberto, então a oferta foi cancelada.',
        _ => erro.mensagem,
      };
    }
    return 'Não foi possível enviar sua resposta agora. Tente de novo.';
  }

  Future<void> _responderOferta(String exclusividadeId, String decisao) async {
    if (_respondendoExclusividade || widget.aoResponderExclusividade == null) return;
    setState(() {
      _respondendoExclusividade = true;
      _erroExclusividade = null;
    });
    try {
      final anterior = _ofertaLocal ?? _dados.ofertaExclusividade;
      final resposta = await widget.aoResponderExclusividade!(exclusividadeId, decisao);
      if (!mounted) return;
      setState(() {
        _respondendoExclusividade = false;
        _ofertaLocal = OfertaExclusividadeCliente(
          id: resposta.id,
          pedidoId: resposta.pedidoId,
          status: resposta.status,
          profissionalId: anterior?.profissionalId ?? resposta.profissionalId,
          profissionalNome: resposta.profissionalNome ?? anterior?.profissionalNome,
          notaPublica: resposta.notaPublica ?? anterior?.notaPublica,
          expiraEm: resposta.expiraEm,
          texto: anterior?.texto ?? resposta.texto,
          outrosOrcamentosContinuamVisiveis: resposta.outrosOrcamentosContinuamVisiveis,
        );
      });
    } on Object catch (erro) {
      if (!mounted) return;
      setState(() {
        _respondendoExclusividade = false;
        _erroExclusividade = _mensagemErroExclusividade(erro);
      });
    }
  }

  List<Widget> _cartaoExclusividade() {
    final oferta = _ofertaLocal ?? _dados.ofertaExclusividade;
    final reservado = _dados.estado == 'reservado' || (oferta?.ativa ?? false);
    if (reservado) {
      final nome = oferta?.profissionalNome?.trim();
      final quem = (nome == null || nome.isEmpty) ? '' : ' para $nome';
      final expira = oferta?.expiraEm?.toLocal();
      final ate =
          expira == null ? '' : ' até ${diaMesDoAparelho(expira)} às ${horaDoAparelho(expira)}';
      return [
        const SizedBox(height: EspacosTrato.x4),
        CartaoTrato(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const ChipStatus(texto: 'Reservado', tipo: TipoStatus.sucesso),
                  const SizedBox(width: EspacosTrato.x2),
                  Expanded(
                    child: Text(
                      'Reservado$quem$ate',
                      style: TipografiaTrato.tituloCartao,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: EspacosTrato.x2),
              Text(
                'Outros orçamentos já enviados continuam disponíveis.',
                style: TipografiaTrato.corpoPequeno.copyWith(color: CoresTrato.textoSecundario),
              ),
            ],
          ),
        ),
      ];
    }
    if (oferta != null && oferta.recusada) {
      return const [
        SizedBox(height: EspacosTrato.x4),
        AvisoFaixa(
          texto: 'Oferta recusada. Seus outros orçamentos continuam disponíveis.',
          tipo: TipoStatus.info,
          icone: Icons.info_outline,
        ),
      ];
    }
    if (oferta == null || !oferta.aguardandoCliente) return const [];
    final nome = oferta.profissionalNome?.trim();
    final nomeExibicao = (nome == null || nome.isEmpty) ? 'Um profissional' : nome;
    final nota = oferta.notaPublica;
    final responderAte = oferta.responderAte?.toLocal();
    return [
      const SizedBox(height: EspacosTrato.x4),
      CartaoTrato(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    'Pedido de exclusividade de 48h',
                    style: TipografiaTrato.tituloCartao,
                  ),
                ),
                const SizedBox(width: EspacosTrato.x2),
                ChipStatus(texto: oferta.texto, tipo: TipoStatus.info),
              ],
            ),
            const SizedBox(height: EspacosTrato.x2),
            Text(
              nota == null
                  ? nomeExibicao
                  : '$nomeExibicao · nota ${nota.toStringAsFixed(1).replaceAll('.', ',')}',
              style: TipografiaTrato.corpoForte,
            ),
            if (responderAte != null) ...[
              const SizedBox(height: EspacosTrato.x1),
              Text(
                'Responda até ${diaMesDoAparelho(responderAte)} às ${horaDoAparelho(responderAte)}',
                style: TipografiaTrato.corpoPequeno.copyWith(color: CoresTrato.textoSecundario),
              ),
            ],
            const SizedBox(height: EspacosTrato.x2),
            Text(
              'Aceitar é sem compromisso de contratar.',
              style: TipografiaTrato.corpoForte,
            ),
            const SizedBox(height: EspacosTrato.x1),
            Text(
              'Se você aceitar, este profissional terá 48 horas exclusivas para enviar o '
              'orçamento. Se ele não enviar, o pedido volta para outros profissionais. '
              'Outros orçamentos já recebidos continuam visíveis.',
              style: TipografiaTrato.corpoPequeno,
            ),
            if (_erroExclusividade != null) ...[
              const SizedBox(height: EspacosTrato.x3),
              AvisoFaixa(
                texto: _erroExclusividade!,
                tipo: TipoStatus.perigo,
                icone: Icons.error_outline,
              ),
            ],
            const SizedBox(height: EspacosTrato.x4),
            Row(
              children: [
                Expanded(
                  child: BotaoSecundario(
                    texto: 'Recusar e ver outros',
                    aoTocar: _respondendoExclusividade || widget.aoResponderExclusividade == null
                        ? null
                        : () => _responderOferta(oferta.id, 'recusar'),
                  ),
                ),
                const SizedBox(width: EspacosTrato.x3),
                Expanded(
                  child: BotaoSecundario(
                    texto: 'Aceitar',
                    aoTocar: _respondendoExclusividade || widget.aoResponderExclusividade == null
                        ? null
                        : () => _responderOferta(oferta.id, 'aceitar'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    ];
  }

  List<Widget> _resumo() {
    final max = _dados.faixaMaxCentavos;
    return [
      CartaoTrato(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('O que precisa ser feito', style: TipografiaTrato.tituloCartao),
            const SizedBox(height: EspacosTrato.x1),
            Text(_dados.descricao, style: TipografiaTrato.corpo),
            const SizedBox(height: EspacosTrato.x4),
            Text('Quanto pretende gastar', style: TipografiaTrato.tituloCartao),
            const SizedBox(height: EspacosTrato.x1),
            Text(
              max == null ? 'Sem limite definido' : 'Até ${formatarReais(max)}',
              style: TipografiaTrato.corpo,
            ),
            const SizedBox(height: EspacosTrato.x4),
            Text('Endereço', style: TipografiaTrato.tituloCartao),
            const SizedBox(height: EspacosTrato.x1),
            Text(_dados.enderecoResumo ?? 'Ainda sem endereço', style: TipografiaTrato.corpo),
            if (_dados.fotos.isNotEmpty) ...[
              const SizedBox(height: EspacosTrato.x4),
              Text('Fotos anexadas', style: TipografiaTrato.tituloCartao),
              const SizedBox(height: EspacosTrato.x2),
              Wrap(
                spacing: EspacosTrato.x2,
                runSpacing: EspacosTrato.x2,
                children: [
                  for (var i = 0; i < _dados.fotos.length; i++)
                    EspacoFoto(
                      legenda: 'Foto ${i + 1}',
                      referencia: _dados.fotos[i],
                      largura: 92,
                      altura: 92,
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    ];
  }

  List<Widget> _formulario() => [
        KeyedSubtree(
          key: _keyDescricao,
          child: CampoTrato(
            rotulo: 'Descreva o que precisa',
            controlador: _descricao,
            foco: _focoDescricao,
            erro: _tentou && _descricao.text.trim().isEmpty
                ? 'Descreva o que precisa ser feito.'
                : null,
            aoMudar: (_) => setState(() {}),
          ),
        ),
        const SizedBox(height: EspacosTrato.x4),
        KeyedSubtree(
          key: _keyValor,
          child: CampoTrato(
            rotulo: 'Quanto pretende gastar (no máximo)',
            controlador: _valor,
            foco: _focoValor,
            prefixo: 'R\$ ',
            dica: '900,00',
            ajuda: 'Deixe vazio para não limitar.',
            teclado: const TextInputType.numberWithOptions(decimal: true),
            erro: _tentou ? _erroValor : null,
            aoMudar: (_) => setState(() => _erroValor = null),
          ),
        ),
        const SizedBox(height: EspacosTrato.x4),
        CampoCepAutoPreenchimento(
          controlador: _cep,
          servico: widget.servicoCep,
          foco: _focoCep,
          proximoFoco: _focoNumero,
          aoEncontrar: (end) => setState(() {
            if (end.logradouro.trim().isNotEmpty) _rua.text = end.logradouro;
            if (end.bairro.trim().isNotEmpty) _bairro.text = end.bairro;
          }),
        ),
        const SizedBox(height: EspacosTrato.x4),
        KeyedSubtree(
          key: _keyRua,
          child: CampoTrato(rotulo: 'Rua', controlador: _rua, foco: _focoRua),
        ),
        const SizedBox(height: EspacosTrato.x4),
        KeyedSubtree(
          key: _keyNumero,
          child: CampoTrato(rotulo: 'Número', controlador: _numero, foco: _focoNumero),
        ),
        const SizedBox(height: EspacosTrato.x4),
        KeyedSubtree(
          key: _keyBairro,
          child: CampoTrato(rotulo: 'Bairro', controlador: _bairro, foco: _focoBairro),
        ),
        if (_erro != null) ...[
          const SizedBox(height: EspacosTrato.x3),
          Text(_erro!, style: TipografiaTrato.corpo.copyWith(color: CoresTrato.vermelhoTexto)),
        ],
      ];
}
