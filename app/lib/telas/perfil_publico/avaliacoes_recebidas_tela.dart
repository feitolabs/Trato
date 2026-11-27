import 'package:flutter/material.dart';

import '../../componentes/componentes.dart';
import '../../tema/tema.dart';
import '../profissional_apoio/apoio.dart';
import 'perfil_publico.dart';
import 'perfil_publico_tela.dart' show CartaoAvaliacao;
import 'revisao_avaliacao.dart';

/// Lista das avaliações que o profissional recebeu, com filtro rápido por estrelas (Todas, ★ 5 .. ★ 1).
class AvaliacoesRecebidasTela extends StatefulWidget {
  const AvaliacoesRecebidasTela({super.key, required this.servico});

  final ServicoPerfilPublico servico;

  @override
  State<AvaliacoesRecebidasTela> createState() => _AvaliacoesRecebidasTelaState();
}

class _AvaliacoesRecebidasTelaState extends State<AvaliacoesRecebidasTela> {
  int _versao = 0;
  int? _estrelaFiltro;

  /// Pedidos de revisão. Nulos enquanto consulta, se a consulta falhar ou sem a função.
  List<PedidoRevisaoAvaliacao>? _revisoes;
  var _consultandoRevisoes = false;
  var _falhaNasRevisoes = false;

  @override
  void initState() {
    super.initState();
    _consultarRevisoes();
  }

  /// Consulta à parte: se falhar, as avaliações continuam na tela.
  Future<void> _consultarRevisoes() async {
    final servico = widget.servico;
    if (servico is! RevisaoDeAvaliacao) return;
    setState(() {
      _consultandoRevisoes = true;
      _falhaNasRevisoes = false;
    });
    try {
      final pedidos = await (servico as RevisaoDeAvaliacao).pedidosDeRevisao();
      if (!mounted) return;
      setState(() {
        _revisoes = pedidos;
        _consultandoRevisoes = false;
      });
    } on Object {
      if (!mounted) return;
      setState(() {
        _consultandoRevisoes = false;
        _falhaNasRevisoes = true;
      });
    }
  }

  Future<void> _pedirRevisao(String id) async {
    final servico = widget.servico as RevisaoDeAvaliacao;
    final enviou = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => FolhaPedirRevisao(aoEnviar: (texto) => servico.pedirRevisao(id, texto)),
    );
    if (enviou != true || !mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(content: Text('Pedido de revisão enviado.')));
    await _consultarRevisoes();
  }

  static int _faixaEstrela(double nota) => nota.floor().clamp(1, 5);

  Future<void> _abrirResposta(Avaliacao avaliacao) async {
    final servico = widget.servico;
    final id = avaliacao.id;
    if (servico is! RespostaAvaliacao || id == null || id.isEmpty) return;

    final respondeu = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _FolhaRespostaAvaliacao(
        aoEnviar: (texto) => (servico as RespostaAvaliacao).responderAvaliacao(id, texto),
      ),
    );
    if (respondeu == true && mounted) {
      setState(() => _versao++);
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text('Resposta enviada.')));
    }
  }

  Widget _chipEstrela({
    required Key chave,
    required String rotulo,
    required bool selecionado,
    required CoresTemaTrato cores,
    required VoidCallback aoTocar,
    bool comEstrela = false,
  }) {
    final corTexto = selecionado ? cores.sobrePetroleo : cores.texto;
    return Material(
      key: chave,
      color: selecionado ? cores.petroleo : cores.superficie,
      shape: StadiumBorder(
        side: BorderSide(
          color: selecionado ? cores.petroleo : cores.bordaControle,
          width: EspacosTrato.bordaFina,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: aoTocar,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: EspacosTrato.x3 + 2,
            vertical: EspacosTrato.x2,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (comEstrela) ...[
                Icon(
                  Icons.star_rounded,
                  size: 14,
                  color: selecionado ? cores.sobrePetroleo : cores.petroleo,
                ),
                const SizedBox(width: 4),
              ],
              Text(
                rotulo,
                style: TipografiaTrato.corpoPequeno.copyWith(
                  color: corTexto,
                  fontWeight: selecionado ? FontWeight.w600 : FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.cores;
    final podeResponder = widget.servico is RespostaAvaliacao;
    return PaginaCarregavel<List<Avaliacao>>(
      key: ValueKey(_versao),
      titulo: 'Avaliações recebidas',
      carregar: widget.servico.carregarAvaliacoes,
      estaVazio: (l) => l.isEmpty,
      iconeVazio: Icons.star_border,
      tituloVazio: 'Nenhuma avaliação ainda',
      textoVazio: 'Depois do primeiro serviço concluído, as avaliações dos clientes aparecem aqui.',
      construir: (context, lista) {
        final filtradas = _estrelaFiltro == null
            ? lista
            : [
                for (final a in lista)
                  if (_faixaEstrela(a.nota) == _estrelaFiltro) a,
              ];
        return CorpoRolavel(
          children: [
            Text(
              '${lista.length} ${lista.length == 1 ? 'avaliação' : 'avaliações'}',
              style: TipografiaTrato.tituloGrande,
            ),
            const SizedBox(height: EspacosTrato.x3),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _chipEstrela(
                    chave: const ValueKey('filtro-estrela-todas'),
                    rotulo: 'Todas (${lista.length})',
                    selecionado: _estrelaFiltro == null,
                    cores: c,
                    aoTocar: () => setState(() => _estrelaFiltro = null),
                  ),
                  for (final estrela in const [5, 4, 3, 2, 1]) ...[
                    const SizedBox(width: EspacosTrato.x2),
                    Builder(
                      builder: (_) {
                        final qtd = lista.where((a) => _faixaEstrela(a.nota) == estrela).length;
                        return _chipEstrela(
                          chave: ValueKey('filtro-estrela-$estrela'),
                          rotulo: qtd > 0 ? '$estrela ($qtd)' : '$estrela',
                          comEstrela: true,
                          selecionado: _estrelaFiltro == estrela,
                          cores: c,
                          aoTocar: () => setState(() => _estrelaFiltro = estrela),
                        );
                      },
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: EspacosTrato.x4),
            if (_consultandoRevisoes && _revisoes == null) ...[
              Text(
                'Consultando pedidos de revisão...',
                style: TipografiaTrato.corpoPequeno.copyWith(color: c.textoSecundario),
              ),
              const SizedBox(height: EspacosTrato.x3),
            ],
            if (_falhaNasRevisoes) ...[
              Text(
                'Não foi possível consultar seus pedidos de revisão.',
                key: const ValueKey('revisoes-falha'),
                style: TipografiaTrato.corpoPequeno.copyWith(color: c.vermelhoTexto),
              ),
              BotaoLink(texto: 'Tentar de novo', aoTocar: _consultarRevisoes),
              const SizedBox(height: EspacosTrato.x3),
            ],
            if (filtradas.isEmpty) ...[
              const SizedBox(height: EspacosTrato.x4),
              Text(
                'Nenhuma avaliação com $_estrelaFiltro ${_estrelaFiltro == 1 ? 'estrela' : 'estrelas'}',
                style: TipografiaTrato.tituloCartao.copyWith(color: c.texto),
              ),
              const SizedBox(height: EspacosTrato.x2),
              BotaoLink(
                texto: 'Ver todas',
                aoTocar: () => setState(() => _estrelaFiltro = null),
              ),
            ] else
              for (final a in filtradas)
                CartaoAvaliacao(
                  avaliacao: a,
                  aoResponder:
                      podeResponder && (a.id ?? '').isNotEmpty && (a.resposta ?? '').trim().isEmpty
                          ? () => _abrirResposta(a)
                          : null,
                  rodape: _revisoes == null || (a.id ?? '').isEmpty
                      ? null
                      : SecaoRevisaoAvaliacao(
                          avaliacaoId: a.id!,
                          pedido: pedidoDaAvaliacao(_revisoes!, a.id!),
                          aoPedir: () => _pedirRevisao(a.id!),
                        ),
                ),
          ],
        );
      },
    );
  }
}

class _FolhaRespostaAvaliacao extends StatefulWidget {
  const _FolhaRespostaAvaliacao({required this.aoEnviar});

  final Future<String?> Function(String texto) aoEnviar;

  @override
  State<_FolhaRespostaAvaliacao> createState() => _FolhaRespostaAvaliacaoState();
}

class _FolhaRespostaAvaliacaoState extends State<_FolhaRespostaAvaliacao> {
  final _ctrl = TextEditingController();
  var _enviando = false;
  String? _erro;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _enviar() async {
    final texto = _ctrl.text.trim();
    if (texto.isEmpty) {
      setState(() => _erro = 'Escreva uma resposta antes de enviar.');
      return;
    }
    setState(() {
      _enviando = true;
      _erro = null;
    });
    try {
      await widget.aoEnviar(texto);
      if (mounted) Navigator.of(context).pop(true);
    } on Object {
      if (mounted) {
        setState(() {
          _enviando = false;
          _erro = 'Não foi possível enviar agora. Tente de novo.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.only(
          left: EspacosTrato.x5,
          right: EspacosTrato.x5,
          top: EspacosTrato.x5,
          bottom: MediaQuery.of(context).viewInsets.bottom + EspacosTrato.x5,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Responder avaliação', style: TipografiaTrato.titulo),
            const SizedBox(height: EspacosTrato.x3),
            TextField(
              key: const ValueKey('campo-resposta-avaliacao'),
              controller: _ctrl,
              maxLines: 3,
              decoration: InputDecoration(
                hintText: 'Escreva sua resposta para o cliente',
                errorText: _erro,
              ),
            ),
            const SizedBox(height: EspacosTrato.x4),
            BotaoPrimario(
              key: const ValueKey('botao-enviar-resposta'),
              texto: 'Enviar resposta',
              carregando: _enviando,
              aoTocar: _enviando ? null : _enviar,
            ),
          ],
        ),
      ),
    );
  }
}
