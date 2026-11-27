/// Conta bloqueada: o cliente ainda vê os pedidos já contratados, confirma a conclusão ou relata
/// um problema (só texto). O que pode ser feito vem de `acoes_permitidas`; o app não decide.
/// Estas telas só chamam as rotas que o servidor abre a quem está bloqueado.
library;

import 'package:flutter/material.dart';

import '../../componentes/componentes.dart';
import '../../dados/erros.dart';
import '../../tema/tema.dart';
import '../comuns/estados.dart';
import '../comuns/formato_aparelho.dart';
import '../comuns/textos_dos_termos.dart';
import '../profissional_apoio/apoio.dart' show AvisoFaixa;

class PedidoDeContaBloqueada {
  const PedidoDeContaBloqueada({
    required this.id,
    required this.estado,
    required this.estadoNome,
    this.titulo,
    this.profissionalNome,
    this.visitaInicio,
    this.codigoInicio,
    this.codigoConclusao,
    this.checkOutSemCodigo = false,
    this.acoes = const {},
  });

  final String id;
  final String estado;
  final String estadoNome;
  final String? titulo;
  final String? profissionalNome;
  final DateTime? visitaInicio;
  final String? codigoInicio;
  final String? codigoConclusao;
  final bool checkOutSemCodigo;
  final Set<String> acoes;

  bool get podeConfirmar => acoes.contains('confirmar_conclusao');
  bool get podeRelatar => acoes.contains('abrir_disputa');
  bool get temRelato => estado == 'em_disputa' || estado == 'retrabalho';

  String get rotulo =>
      titulo ?? 'Pedido #${id.substring(0, id.length < 4 ? id.length : 4).toUpperCase()}';

  /// Nulo: veio sem o identificador do pedido.
  static PedidoDeContaBloqueada? deJson(Object? json) {
    if (json is! Map) return null;
    String? texto(String chave) {
      final v = json[chave];
      return v is String && v.trim().isNotEmpty ? v.trim() : null;
    }

    final id = texto('id');
    if (id == null) return null;
    final janela = json['janela'];
    final acoes = json['acoes_permitidas'];
    return PedidoDeContaBloqueada(
      id: id,
      estado: texto('estado') ?? '',
      estadoNome: texto('estado_nome') ?? 'Situação não informada',
      titulo: texto('titulo') ?? texto('categoria_nome'),
      profissionalNome: texto('profissional_nome'),
      visitaInicio: janela is Map ? DateTime.tryParse('${janela['inicio']}') : null,
      codigoInicio: texto('codigo_inicio'),
      codigoConclusao: texto('codigo_conclusao'),
      checkOutSemCodigo: json['check_out_sem_codigo'] == true,
      acoes: {if (acoes is List) ...acoes.whereType<String>()},
    );
  }
}

/// O relato já aberto, como o servidor informa.
class RelatoDoPedido {
  const RelatoDoPedido({
    required this.motivo,
    this.descricao,
    this.abertoEm,
    this.respostaAte,
    this.decisaoAte,
  });

  final String motivo;
  final String? descricao;
  final DateTime? abertoEm;
  final DateTime? respostaAte;
  final DateTime? decisaoAte;
}

/// Um motivo que o cliente pode escolher: o código do servidor e o texto da tela.
typedef MotivoDoRelato = ({String codigo, String texto});

abstract interface class PedidosComContaBloqueada {
  List<MotivoDoRelato> get motivosDoRelato;
  List<String> get solucoesDoRelato;

  /// Vazia quando o servidor recusa a lista (não há pedido contratado como cliente).
  Future<List<PedidoDeContaBloqueada>> pedidosContratados();

  Future<PedidoDeContaBloqueada> pedidoContratado(String pedidoId);

  Future<void> confirmarPedidoContratado(String pedidoId);

  Future<void> relatarPedidoContratado(
    String pedidoId, {
    required String motivo,
    required String descricao,
    List<String> fotos,
  });

  /// Nulo: o pedido não tem relato.
  Future<RelatoDoPedido?> relatoDoPedidoContratado(String pedidoId);
}

String _quando(DateTime data) => '${diaMesDoAparelho(data)} · ${horaDoAparelho(data)}';

String _mensagem(Object erro, String padrao) => erro is ErroTrato ? erro.mensagem : padrao;

class PedidosContratadosTela extends StatelessWidget {
  const PedidosContratadosTela({
    super.key,
    required this.servico,
    required this.aoFalar,
    this.secoes,
    this.capturarFoto,
  });

  final PedidosComContaBloqueada servico;
  final SecoesDoBloqueado? secoes;
  final Future<String?> Function()? capturarFoto;

  /// "Falar com o Trato", já com o pedido quando houver.
  final void Function(BuildContext context, String? pedidoId) aoFalar;

  @override
  Widget build(BuildContext context) {
    final c = context.cores;
    return MolduraTelaComum(
      titulo: 'Meus pedidos contratados',
      child: CarregadorTela<List<PedidoDeContaBloqueada>>(
        carregar: servico.pedidosContratados,
        construir: (context, pedidos, recarregar) => ListView(
          children: [
            if (pedidos.isEmpty) ...[
              Text(
                'Não há pedido contratado para mostrar.',
                key: const ValueKey('contratados-vazio'),
                style: TipografiaTrato.corpo.copyWith(color: c.texto),
              ),
              const SizedBox(height: EspacosTrato.x3),
              BotaoSecundario(texto: 'Falar com o Trato', aoTocar: () => aoFalar(context, null)),
            ],
            for (final p in pedidos)
              Padding(
                padding: const EdgeInsets.only(bottom: EspacosTrato.x3),
                child: InkWell(
                  key: ValueKey('contratado-${p.id}'),
                  borderRadius: BorderRadius.circular(EspacosTrato.raio),
                  onTap: () async {
                    await Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => PedidoContratadoTela(
                          servico: servico,
                          pedidoId: p.id,
                          aoFalar: aoFalar,
                          secoes: secoes,
                          capturarFoto: capturarFoto,
                        ),
                      ),
                    );
                    recarregar();
                  },
                  child: CartaoTrato(
                    child: SizedBox(
                      width: double.infinity,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(p.rotulo, style: TipografiaTrato.corpoForte),
                          const SizedBox(height: EspacosTrato.x1),
                          Text(
                            p.estadoNome,
                            style: TipografiaTrato.corpoPequeno.copyWith(color: c.texto),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Entradas extras abertas ao bloqueado no próprio pedido (ausência e contestação da decisão).
typedef SecoesDoBloqueado = List<Widget> Function(
    BuildContext context, PedidoDeContaBloqueada pedido);

typedef _Dados = ({PedidoDeContaBloqueada pedido, RelatoDoPedido? relato, bool falhaNoRelato});

class PedidoContratadoTela extends StatefulWidget {
  const PedidoContratadoTela({
    super.key,
    required this.servico,
    required this.pedidoId,
    required this.aoFalar,
    this.secoes,
    this.capturarFoto,
  });

  final PedidosComContaBloqueada servico;
  final String pedidoId;
  final void Function(BuildContext context, String? pedidoId) aoFalar;
  final SecoesDoBloqueado? secoes;
  final Future<String?> Function()? capturarFoto;

  @override
  State<PedidoContratadoTela> createState() => _PedidoContratadoTelaState();
}

class _PedidoContratadoTelaState extends State<PedidoContratadoTela> {
  final _atualizar = ValueNotifier(0);
  var _confirmando = false;
  String? _erro;

  @override
  void dispose() {
    _atualizar.dispose();
    super.dispose();
  }

  Future<_Dados> _carregar() async {
    final pedido = await widget.servico.pedidoContratado(widget.pedidoId);
    if (!pedido.temRelato) return (pedido: pedido, relato: null, falhaNoRelato: false);
    try {
      final relato = await widget.servico.relatoDoPedidoContratado(pedido.id);
      return (pedido: pedido, relato: relato, falhaNoRelato: false);
    } on Object {
      // O pedido continua na tela; só o relato fica sem aparecer.
      return (pedido: pedido, relato: null, falhaNoRelato: true);
    }
  }

  Future<void> _confirmar() async {
    if (_confirmando) return;
    final sim = await showDialog<bool>(
      context: context,
      builder: (dialogo) => AlertDialog(
        title: const Text('Confirmar a conclusão?'),
        content: const Text('Confirme só se o serviço foi concluído do jeito combinado.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogo).pop(false),
            child: const Text('Voltar'),
          ),
          FilledButton(
            key: const ValueKey('contratado-confirmar-sim'),
            onPressed: () => Navigator.of(dialogo).pop(true),
            child: const Text('Confirmar'),
          ),
        ],
      ),
    );
    if (sim != true || !mounted) return;
    setState(() {
      _confirmando = true;
      _erro = null;
    });
    try {
      await widget.servico.confirmarPedidoContratado(widget.pedidoId);
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Conclusão confirmada.')));
      _atualizar.value++;
    } on Object catch (e) {
      if (!mounted) return;
      setState(() => _erro = _mensagem(e, 'Não foi possível confirmar agora. Tente de novo.'));
    } finally {
      if (mounted) setState(() => _confirmando = false);
    }
  }

  Future<void> _relatar() async {
    setState(() => _erro = null);
    final enviou = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _FolhaRelato(
        servico: widget.servico,
        pedidoId: widget.pedidoId,
        aoFalar: () => widget.aoFalar(context, widget.pedidoId),
        capturarFoto: widget.capturarFoto,
      ),
    );
    if (!mounted) return;
    if (enviou == true) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Relato enviado.')));
    }
    // Também depois de fechar sem sucesso: um relato repetido muda o que o pedido permite.
    _atualizar.value++;
  }

  @override
  Widget build(BuildContext context) {
    final c = context.cores;
    final corpo = TipografiaTrato.corpo.copyWith(color: c.texto);
    return MolduraTelaComum(
      titulo: 'Pedido',
      child: CarregadorTela<_Dados>(
        carregar: _carregar,
        atualizarQuando: _atualizar,
        construir: (context, dados, recarregar) {
          final p = dados.pedido;
          final relato = dados.relato;
          // Como no app com a conta ativa: cada código aparece na fase em que é usado.
          final inicio = const {'em_andamento', 'em_confirmacao', 'concluido'}.contains(p.estado)
              ? null
              : p.codigoInicio;
          final conclusao = p.estado == 'em_andamento' ? p.codigoConclusao : null;
          return ListView(
            children: [
              Text(p.rotulo, style: TipografiaTrato.titulo),
              const SizedBox(height: EspacosTrato.x2),
              Text(p.estadoNome, style: TipografiaTrato.corpoForte),
              if (p.profissionalNome != null)
                Text('Profissional: ${p.profissionalNome}', style: corpo),
              if (p.visitaInicio != null) Text('Visita: ${_quando(p.visitaInicio!)}', style: corpo),
              if (inicio != null) ...[
                const SizedBox(height: EspacosTrato.x3),
                Text('Código de Início: $inicio', style: TipografiaTrato.corpoForte),
              ],
              if (conclusao != null) ...[
                const SizedBox(height: EspacosTrato.x3),
                Text('Código de conclusão: $conclusao', style: TipografiaTrato.corpoForte),
              ],
              if (relato != null) ...[
                const SizedBox(height: EspacosTrato.x4),
                CartaoTrato(
                  child: SizedBox(
                    width: double.infinity,
                    child: Column(
                      key: const ValueKey('contratado-relato'),
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Problema relatado', style: TipografiaTrato.corpoForte),
                        Text(relato.motivo, style: corpo),
                        if (relato.descricao != null) Text(relato.descricao!, style: corpo),
                        if (relato.abertoEm != null)
                          Text('Aberto em ${_quando(relato.abertoEm!)}', style: corpo),
                        if (relato.respostaAte != null)
                          Text(
                            'Prazo de resposta do profissional: ${_quando(relato.respostaAte!)}',
                            style: corpo,
                          ),
                        if (relato.decisaoAte != null)
                          Text('Prazo da decisão: ${_quando(relato.decisaoAte!)}', style: corpo),
                      ],
                    ),
                  ),
                ),
              ],
              if (dados.falhaNoRelato) ...[
                const SizedBox(height: EspacosTrato.x3),
                Text(
                  'Não foi possível abrir o relato agora.',
                  style: corpo.copyWith(color: c.vermelhoTexto),
                ),
                BotaoLink(texto: 'Tentar de novo', aoTocar: recarregar),
              ],
              if (p.podeConfirmar && p.checkOutSemCodigo) ...[
                const SizedBox(height: EspacosTrato.x4),
                const AvisoFaixa(
                  texto: 'Encerramento sem código: o pagamento só é liberado depois da sua '
                      'confirmação.',
                  tipo: TipoStatus.alerta,
                  icone: Icons.info_outline,
                ),
                const SizedBox(height: EspacosTrato.x2),
                Text(textoAnalistaDecide, style: TipografiaTrato.corpoPequeno),
              ],
              if (widget.secoes != null) ...widget.secoes!(context, p),
              const SizedBox(height: EspacosTrato.x5),
              if (_erro != null) ...[
                Semantics(
                  liveRegion: true,
                  child: Text(_erro!, style: corpo.copyWith(color: c.vermelhoTexto)),
                ),
                const SizedBox(height: EspacosTrato.x2),
              ],
              if (p.podeConfirmar) ...[
                BotaoPrimario(
                  key: const ValueKey('contratado-confirmar'),
                  texto: p.checkOutSemCodigo
                      ? 'Confirmar conclusão e liberar pagamento'
                      : 'Confirmar serviço',
                  carregando: _confirmando,
                  aoTocar: _confirmar,
                ),
                const SizedBox(height: EspacosTrato.x2),
              ],
              if (p.podeRelatar) ...[
                BotaoSecundario(
                  key: const ValueKey('contratado-relatar'),
                  texto: 'Relatar problema',
                  aoTocar: _relatar,
                ),
                const SizedBox(height: EspacosTrato.x2),
              ],
              if (!p.podeConfirmar && !p.podeRelatar)
                Text('Não há ação disponível neste pedido agora.', style: corpo),
              Center(
                child: BotaoLink(
                  key: const ValueKey('contratado-falar'),
                  texto: 'Falar com o Trato',
                  aoTocar: () => widget.aoFalar(context, p.id),
                ),
              ),
              const SizedBox(height: EspacosTrato.x5),
            ],
          );
        },
      ),
    );
  }
}

class _FolhaRelato extends StatefulWidget {
  const _FolhaRelato({
    required this.servico,
    required this.pedidoId,
    required this.aoFalar,
    this.capturarFoto,
  });

  final PedidosComContaBloqueada servico;
  final Future<String?> Function()? capturarFoto;
  final String pedidoId;
  final VoidCallback aoFalar;

  @override
  State<_FolhaRelato> createState() => _FolhaRelatoState();
}

class _FolhaRelatoState extends State<_FolhaRelato> {
  final _descricao = TextEditingController();
  String? _motivo;
  String? _solucao;
  var _tentou = false;
  var _enviando = false;
  String? _erro;
  final _fotos = <String>[];

  Future<void> _fotografar() async {
    try {
      final foto = await widget.capturarFoto!();
      if (foto != null && mounted) setState(() => _fotos.add(foto));
    } on Object catch (e) {
      if (mounted) setState(() => _erro = _mensagem(e, 'Não foi possível tirar a foto.'));
    }
  }

  @override
  void dispose() {
    _descricao.dispose();
    super.dispose();
  }

  Future<void> _enviar() async {
    if (_enviando) return;
    setState(() {
      _tentou = true;
      _erro = null;
    });
    final texto = _descricao.text.trim();
    if (_motivo == null || _solucao == null || texto.isEmpty) return;
    setState(() => _enviando = true);
    try {
      await widget.servico.relatarPedidoContratado(
        widget.pedidoId,
        motivo: _motivo!,
        // O mesmo formato do relato com a conta ativa.
        descricao: '$texto\n\nSolução que o cliente prefere: $_solucao',
        fotos: List.of(_fotos),
      );
      if (mounted) Navigator.of(context).pop(true);
    } on Object catch (e) {
      if (!mounted) return;
      setState(() {
        _enviando = false;
        _erro = _mensagem(e, 'Não foi possível enviar agora. Tente de novo.');
      });
    }
  }

  Widget _escolha({
    required Key chave,
    required String rotulo,
    required List<({String codigo, String texto})> opcoes,
    required String? erro,
    required ValueChanged<String?> aoMudar,
  }) =>
      DropdownButtonFormField<String>(
        key: chave,
        isExpanded: true,
        itemHeight: null,
        style: TipografiaTrato.corpo.copyWith(color: context.cores.texto),
        decoration: InputDecoration(labelText: rotulo, errorText: erro, errorMaxLines: 3),
        items: [
          for (final o in opcoes) DropdownMenuItem(value: o.codigo, child: Text(o.texto)),
        ],
        onChanged: _enviando ? null : aoMudar,
      );

  @override
  Widget build(BuildContext context) {
    final c = context.cores;
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
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Relatar problema', style: TipografiaTrato.titulo),
            const SizedBox(height: EspacosTrato.x2),
            Text(
              widget.capturarFoto == null
                  ? 'Aqui o relato vai só com texto. Para mandar fotos, fale com o atendimento.'
                  : 'Conte o problema. Se ajudar, tire fotos.',
              style: TipografiaTrato.corpo.copyWith(color: c.texto),
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: BotaoLink(texto: 'Falar com o Trato', aoTocar: widget.aoFalar),
            ),
            _escolha(
              chave: const ValueKey('relato-motivo'),
              rotulo: 'O que aconteceu',
              opcoes: widget.servico.motivosDoRelato,
              erro: _tentou && _motivo == null ? 'Escolha o que aconteceu.' : null,
              aoMudar: (v) => setState(() => _motivo = v),
            ),
            const SizedBox(height: EspacosTrato.x3),
            _escolha(
              chave: const ValueKey('relato-solucao'),
              rotulo: 'Solução que você prefere',
              opcoes: [
                for (final s in widget.servico.solucoesDoRelato) (codigo: s, texto: s),
              ],
              erro: _tentou && _solucao == null ? 'Escolha a solução que você prefere.' : null,
              aoMudar: (v) => setState(() => _solucao = v),
            ),
            const SizedBox(height: EspacosTrato.x3),
            TextField(
              key: const ValueKey('relato-descricao'),
              controller: _descricao,
              enabled: !_enviando,
              minLines: 3,
              maxLines: 6,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                labelText: 'Conte o problema',
                alignLabelWithHint: true,
                errorText: _tentou && _descricao.text.trim().isEmpty ? 'Conte o problema.' : null,
              ),
            ),
            const SizedBox(height: EspacosTrato.x3),
            if (widget.capturarFoto != null) ...[
              if (_fotos.isNotEmpty)
                Text(
                  '${_fotos.length} ${_fotos.length == 1 ? 'foto anexada' : 'fotos anexadas'}',
                  style: TipografiaTrato.corpoPequeno.copyWith(color: c.texto),
                ),
              if (_fotos.length < 10)
                BotaoSecundario(
                  key: const ValueKey('relato-foto'),
                  texto: 'Tirar foto',
                  icone: Icons.photo_camera_outlined,
                  aoTocar: _enviando ? null : _fotografar,
                ),
              const SizedBox(height: EspacosTrato.x3),
            ],
            if (_erro != null) ...[
              Semantics(
                liveRegion: true,
                child: Text(
                  _erro!,
                  style: TipografiaTrato.corpoPequeno.copyWith(color: c.vermelhoTexto),
                ),
              ),
              const SizedBox(height: EspacosTrato.x2),
            ],
            BotaoPrimario(
              key: const ValueKey('relato-enviar'),
              texto: 'Enviar relato',
              carregando: _enviando,
              aoTocar: _enviar,
            ),
          ],
        ),
      ),
    );
  }
}
