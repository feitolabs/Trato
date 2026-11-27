import 'package:flutter/material.dart';

import '../../componentes/componentes.dart';
import '../../dados/erros.dart';
import '../../dispositivo/abrir_link.dart';
import '../../tema/tema.dart';
import '../comuns/estados.dart';
import '../comuns/formato_aparelho.dart';
import '../conclusao/apoio_conclusao.dart' show EspacoFoto;
import '../profissional/dinheiro.dart';
import 'modelos.dart';

/// "26/11, 14:30".
String quandoAusencia(DateTime d) => '${d.day.toString().padLeft(2, '0')}/'
    '${d.month.toString().padLeft(2, '0')}, ${horaDoAparelho(d)}';

String tituloAusencia(CasoAusencia caso, {required bool profissional}) => switch (caso.status) {
      'aguardando_espera' =>
        profissional ? 'Chegada registrada' : 'O profissional chegou ao local',
      'aguardando_justificativa' =>
        profissional ? 'Aguardando a justificativa do cliente' : 'Justifique a ausência',
      'em_analise' => 'Justificativa em análise',
      'justificativa_aceita' => 'Justificativa aceita',
      'justificativa_recusada' => 'Justificativa não aceita',
      'expirada_sem_justificativa' => 'Prazo encerrado sem justificativa',
      _ => 'Registro de cliente ausente',
    };

/// Situação, prazo, decisão, retenção e reembolso: o que o servidor mandou, para os dois lados.
class ResumoAusencia extends StatelessWidget {
  const ResumoAusencia({super.key, required this.caso, required this.profissional});

  final CasoAusencia caso;
  final bool profissional;

  @override
  Widget build(BuildContext context) {
    final ate = caso.justificativaAte;
    final retencao = caso.retencaoCentavos ?? 0;
    final proposta = caso.cancelamentoStatus == 'proposta_retencao_enviada';
    final secundario =
        TipografiaTrato.corpoPequeno.copyWith(color: context.cores.textoSecundario);
    Widget linha(String texto, {Key? key, TextStyle? estilo}) => Padding(
          padding: const EdgeInsets.only(top: EspacosTrato.x2),
          child: Text(texto, key: key, style: estilo ?? TipografiaTrato.corpo),
        );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(tituloAusencia(caso, profissional: profissional),
            style: TipografiaTrato.tituloCartao),
        if (caso.esperando)
          linha(profissional
              ? 'Espere o cliente antes de registrar a ausência.'
              : 'Receba o profissional ou responda no chat.'),
        if (caso.pedeJustificativa) ...[
          if (!profissional)
            linha('Foi registrado que você não estava no local. Envie sua justificativa.'),
          if (ate != null)
            linha(
              'Prazo: até ${quandoAusencia(ate)}.',
              key: const Key('prazo-justificativa'),
              estilo: TipografiaTrato.corpoForte,
            ),
        ],
        // O profissional vê só o que ele mesmo enviou: o texto do cliente fica com o cliente.
        if (!profissional && caso.justificativaTexto != null) ...[
          linha('Sua justificativa', estilo: secundario),
          Text(caso.justificativaTexto!, style: TipografiaTrato.corpo),
          if (caso.anexos > 0) linha('Anexos: ${caso.anexos}', estilo: secundario),
        ],
        if (caso.decisao != null)
          linha('Decisão do analista: ${caso.decisao}', key: const Key('decisao-ausencia')),
        if (retencao > 0) ...[
          linha(
            proposta
                ? 'Retenção proposta, ainda não cobrada: ${Dinheiro.formatar(retencao)}'
                : 'Valor retido: ${Dinheiro.formatar(retencao)}',
            key: const Key('retencao-ausencia'),
            estilo: TipografiaTrato.corpoForte,
          ),
          if (caso.retencaoJustificativa != null)
            linha('Motivo da retenção: ${caso.retencaoJustificativa}'),
          if (caso.comprovantesDaRetencao > 0)
            linha('Comprovantes de custo anexados: ${caso.comprovantesDaRetencao}',
                estilo: secundario),
        ] else if (caso.cancelamentoStatus == 'cancelado_sem_retencao')
          linha('Sem retenção.'),
        if (caso.reembolsoCentavos != null)
          linha('Reembolso ao cliente: ${Dinheiro.formatar(caso.reembolsoCentavos!)}'),
        if (caso.contestacao case final c?) ...[
          linha(
            switch (c.status) {
              'aberta' => 'Contestação em análise',
              'mantida' => 'Contestação analisada: retenção mantida',
              'alterada' => 'Contestação analisada: retenção alterada',
              'revertida' => 'Contestação analisada: retenção retirada',
              _ => 'Retenção contestada',
            },
            key: const Key('situacao-contestacao'),
            estilo: TipografiaTrato.corpoForte,
          ),
          if (c.status == 'aberta') ...[
            if (c.responderAte != null)
              linha('Outro analista responde até ${quandoAusencia(c.responderAte!)}.'),
            linha('Nada é cobrado até a resposta.'),
          ],
          if (!profissional && c.texto != null) ...[
            linha('Sua contestação', estilo: secundario),
            Text(c.texto!, style: TipografiaTrato.corpo),
          ],
          if (c.protocolo != null) linha('Protocolo: ${c.protocolo}', estilo: secundario),
          if (c.resposta != null) linha('Resposta: ${c.resposta}'),
        ] else if (caso.temRetencaoContestavel)
          linha(
            caso.podeContestar(DateTime.now())
                ? '${profissional ? 'O cliente pode' : 'Você pode'} contestar até '
                    '${quandoAusencia(caso.contestarAte!)}.'
                : 'O prazo para contestar terminou em ${quandoAusencia(caso.contestarAte!)}.',
            key: const Key('prazo-contestacao'),
          ),
      ],
    );
  }
}

/// Cartão no pedido. Sem registro (ou servidor sem a função) não aparece nada.
class SecaoAusencia extends StatefulWidget {
  const SecaoAusencia({
    super.key,
    required this.carregar,
    required this.profissional,
    required this.aoAbrir,
    this.atualizarQuando,
  });

  final Future<CasoAusencia?> Function() carregar;
  final bool profissional;
  final VoidCallback aoAbrir;
  final Listenable? atualizarQuando;

  @override
  State<SecaoAusencia> createState() => _SecaoAusenciaState();
}

class _SecaoAusenciaState extends State<SecaoAusencia> {
  CasoAusencia? _caso;
  var _falhou = false;

  @override
  void initState() {
    super.initState();
    widget.atualizarQuando?.addListener(_buscar);
    _buscar();
  }

  @override
  void dispose() {
    widget.atualizarQuando?.removeListener(_buscar);
    super.dispose();
  }

  Future<void> _buscar() async {
    try {
      final caso = await widget.carregar();
      if (mounted) {
        setState(() {
          _caso = caso;
          _falhou = false;
        });
      }
    } on Object {
      if (mounted) setState(() => _falhou = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final caso = _caso;
    if (caso == null) {
      if (!_falhou) return const SizedBox.shrink();
      return Padding(
        padding: const EdgeInsets.only(top: EspacosTrato.x4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Não foi possível ver se há um registro de ausência.',
              style: TipografiaTrato.corpoPequeno.copyWith(color: context.cores.vermelhoTexto),
            ),
            BotaoLink(texto: 'Tentar de novo', aoTocar: _buscar),
          ],
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(top: EspacosTrato.x4),
      child: CartaoTrato(
        key: const Key('cartao-ausencia'),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ResumoAusencia(caso: caso, profissional: widget.profissional),
            const SizedBox(height: EspacosTrato.x3),
            BotaoSecundario(
              key: const Key('abrir-ausencia'),
              texto: widget.profissional
                  ? 'Ver registro'
                  : caso.pedeJustificativa
                      ? 'Enviar justificativa'
                      : caso.podeContestar(DateTime.now())
                          ? 'Ver provas e contestar'
                          : 'Ver registro',
              aoTocar: widget.aoAbrir,
            ),
          ],
        ),
      ),
    );
  }
}

/// O registro completo. No lado do cliente, com o prazo aberto, tem o envio da justificativa.
class AusenciaTela extends StatelessWidget {
  const AusenciaTela({
    super.key,
    required this.carregar,
    required this.profissional,
    this.enviar,
    this.capturarFoto,
    this.aoEnviar,
    this.carregarAnexos,
    this.contestar,
  });

  /// Provas do caso. Nulo no retorno: o servidor não tem a função.
  final Future<List<AnexoAusencia>?> Function()? carregarAnexos;

  /// Termos 8.7: contestação da retenção (só do cliente).
  final Future<CasoAusencia> Function(String texto, List<String> fotos)? contestar;

  final Future<CasoAusencia?> Function() carregar;
  final bool profissional;
  final Future<CasoAusencia> Function(String texto, List<String> fotos)? enviar;
  final Future<String?> Function()? capturarFoto;
  final VoidCallback? aoEnviar;

  @override
  Widget build(BuildContext context) {
    return MolduraTelaComum(
      titulo: 'Cliente ausente',
      child: CarregadorTela<CasoAusencia?>(
        carregar: carregar,
        construir: (context, caso, _) => caso == null
            ? const EstadoVazio(
                icone: Icons.event_available_outlined,
                titulo: 'Nenhum registro',
                texto: 'Este pedido não tem registro de cliente ausente.',
              )
            : _CorpoAusencia(tela: this, inicial: caso),
      ),
    );
  }
}

class _CorpoAusencia extends StatefulWidget {
  const _CorpoAusencia({required this.tela, required this.inicial});

  final AusenciaTela tela;
  final CasoAusencia inicial;

  @override
  State<_CorpoAusencia> createState() => _CorpoAusenciaState();
}

class _CorpoAusenciaState extends State<_CorpoAusencia> {
  static const _maxAnexos = 10;

  CasoAusencia? _enviado;
  final _texto = TextEditingController();
  final _fotos = <String>[];
  var _enviando = false;
  String? _erro;

  @override
  void dispose() {
    _texto.dispose();
    super.dispose();
  }

  Future<void> _adicionar() async {
    if (_fotos.length >= _maxAnexos) return;
    try {
      final foto = await widget.tela.capturarFoto!();
      if (foto != null && mounted && _fotos.length < _maxAnexos) {
        setState(() => _fotos.add(foto));
      }
    } on Object catch (e) {
      if (mounted) {
        setState(() => _erro = e is ErroTrato ? e.mensagem : 'Não deu para anexar a foto.');
      }
    }
  }

  /// Sobe a cada envio, para as provas serem lidas de novo.
  var _versao = 0;

  Future<void> _enviar(bool contestando) async {
    if (_enviando) return;
    final texto = _texto.text.trim();
    if (texto.isEmpty) {
      setState(() => _erro = contestando
          ? 'Conte o que a análise não considerou.'
          : 'Escreva a justificativa.');
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _enviando = true;
      _erro = null;
    });
    try {
      final acao = contestando ? widget.tela.contestar! : widget.tela.enviar!;
      final novo = await acao(texto, List.unmodifiable(_fotos));
      if (!mounted) return;
      setState(() {
        _enviado = novo;
        _versao++;
        _texto.clear();
        _fotos.clear();
      });
      widget.tela.aoEnviar?.call();
    } on Object catch (e) {
      if (mounted) {
        setState(() => _erro =
            e is ErroTrato ? e.mensagem : 'Não foi possível enviar. Tente de novo.');
      }
    } finally {
      if (mounted) setState(() => _enviando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final caso = _enviado ?? widget.inicial;
    final justificando =
        !widget.tela.profissional && widget.tela.enviar != null && caso.pedeJustificativa;
    final contestando = !widget.tela.profissional &&
        widget.tela.contestar != null &&
        caso.podeContestar(DateTime.now());
    final formulario = justificando || contestando;
    final nome = contestando ? 'contestacao' : 'justificativa';
    return ListView(
      padding: const EdgeInsets.only(bottom: EspacosTrato.x6),
      children: [
        CartaoTrato(
          child: ResumoAusencia(caso: caso, profissional: widget.tela.profissional),
        ),
        if (widget.tela.carregarAnexos != null)
          _Provas(
            key: ValueKey('provas-$_versao'),
            carregar: widget.tela.carregarAnexos!,
            profissional: widget.tela.profissional,
          ),
        if (formulario) ...[
          const SizedBox(height: EspacosTrato.x4),
          if (contestando) ...[
            Text('Contestar a retenção', style: TipografiaTrato.tituloCartao),
            const SizedBox(height: EspacosTrato.x2),
            Text(
              'Conte o que a análise não considerou. Dá para contestar uma vez.',
              style: TipografiaTrato.corpo,
            ),
            const SizedBox(height: EspacosTrato.x3),
          ],
          TextField(
            key: Key('texto-$nome'),
            controller: _texto,
            maxLines: 4,
            maxLength: 2000,
            onChanged: (_) {
              if (_erro != null) setState(() => _erro = null);
            },
            decoration:
                InputDecoration(labelText: contestando ? 'Contestação' : 'Justificativa'),
          ),
          if (widget.tela.capturarFoto != null) ...[
            Text('Anexos: ${_fotos.length} de $_maxAnexos', style: TipografiaTrato.corpoPequeno),
            for (var i = 0; i < _fotos.length; i++)
              Row(
                children: [
                  Expanded(child: Text('Foto ${i + 1}', style: TipografiaTrato.corpo)),
                  IconButton(
                    tooltip: 'Remover foto ${i + 1}',
                    icon: const Icon(Icons.close),
                    onPressed: () => setState(() => _fotos.removeAt(i)),
                  ),
                ],
              ),
            if (_fotos.length < _maxAnexos)
              BotaoLink(
                key: Key('anexar-foto-$nome'),
                texto: 'Adicionar foto',
                aoTocar: _adicionar,
              ),
          ],
          const SizedBox(height: EspacosTrato.x3),
          if (_erro != null) ...[
            Text(
              _erro!,
              key: Key('erro-$nome'),
              style: TipografiaTrato.corpoPequeno.copyWith(color: context.cores.vermelhoTexto),
            ),
            const SizedBox(height: EspacosTrato.x2),
          ],
          BotaoPrimario(
            key: Key('enviar-$nome'),
            texto: contestando ? 'Enviar contestação' : 'Enviar justificativa',
            carregando: _enviando,
            aoTocar: () => _enviar(contestando),
          ),
        ],
      ],
    );
  }
}

String _tipoDeProva(String tipo) => switch (tipo) {
      'registro_ausencia' => 'Registro no local',
      'registro_chegada' => 'Registro de chegada',
      'justificativa' => 'Justificativa',
      'comprovante_retencao' => 'Comprovante de custo',
      'contestacao' => 'Contestação',
      _ => 'Anexo',
    };

/// Fotos e comprovantes do caso. Os links são curtos: vencidos, são buscados de novo.
class _Provas extends StatefulWidget {
  const _Provas({super.key, required this.carregar, required this.profissional});

  final Future<List<AnexoAusencia>?> Function() carregar;
  final bool profissional;

  @override
  State<_Provas> createState() => _ProvasState();
}

class _ProvasState extends State<_Provas> {
  List<AnexoAusencia>? _itens;
  DateTime _lidoEm = DateTime.now();
  var _carregando = true;
  var _falhou = false;
  String? _erroAbrir;

  @override
  void initState() {
    super.initState();
    _buscar();
  }

  Future<void> _buscar() async {
    setState(() {
      _carregando = true;
      _falhou = false;
      _erroAbrir = null;
    });
    try {
      final itens = await widget.carregar();
      if (!mounted) return;
      setState(() {
        // O profissional vê só o que enviou (o servidor já filtra; aqui é a segunda trava).
        _itens = itens == null || !widget.profissional
            ? itens
            : [
                for (final a in itens)
                  if (a.enviadoPor == 'profissional') a,
              ];
        _lidoEm = DateTime.now();
        _carregando = false;
      });
    } on Object {
      if (mounted) {
        setState(() {
          _falhou = true;
          _carregando = false;
        });
      }
    }
  }

  Future<void> _abrir(AnexoAusencia anexo) async {
    var atual = anexo;
    final validade = Duration(seconds: (anexo.expiraEmSegundos ?? 300) - 30);
    if (DateTime.now().difference(_lidoEm) >= validade) {
      await _buscar();
      if (!mounted || _falhou) return;
      atual = _itens?.where((a) => a.arquivoId == anexo.arquivoId).firstOrNull ?? anexo;
    }
    final url = atual.url;
    final abriu = url != null && await abrirLink(Uri.parse(url));
    if (!abriu && mounted) {
      setState(() => _erroAbrir = 'Não deu para abrir o arquivo. Atualize e tente de novo.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final itens = _itens;
    final secundario =
        TipografiaTrato.corpoPequeno.copyWith(color: context.cores.textoSecundario);
    final erro = TipografiaTrato.corpoPequeno.copyWith(color: context.cores.vermelhoTexto);
    // Servidor sem a função: nada aparece.
    if (!_carregando && !_falhou && itens == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: EspacosTrato.x4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            widget.profissional ? 'Fotos que você enviou' : 'Fotos e comprovantes',
            style: TipografiaTrato.tituloCartao,
          ),
          const SizedBox(height: EspacosTrato.x2),
          if (_carregando)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(EspacosTrato.x4),
                child: CircularProgressIndicator(semanticsLabel: 'Carregando as provas'),
              ),
            )
          else if (_falhou) ...[
            Text('Não foi possível carregar as fotos.', style: erro),
            BotaoLink(texto: 'Tentar de novo', aoTocar: _buscar),
          ] else if (itens!.isEmpty)
            Text('Nenhuma foto anexada.', style: secundario)
          else ...[
            for (final a in itens) ...[
              Text(_tipoDeProva(a.tipo), style: TipografiaTrato.corpoForte),
              if (a.url == null)
                Text('Arquivo indisponível.', style: secundario)
              else ...[
                const SizedBox(height: EspacosTrato.x1),
                EspacoFoto(
                  legenda: _tipoDeProva(a.tipo),
                  referencia: a.url,
                  altura: 160,
                ),
                Align(
                  alignment: Alignment.centerLeft,
                  child: BotaoLink(
                    key: Key('abrir-anexo-${a.arquivoId}'),
                    texto: 'Abrir arquivo',
                    aoTocar: () => _abrir(a),
                  ),
                ),
              ],
              const SizedBox(height: EspacosTrato.x3),
            ],
            if (_erroAbrir != null) Text(_erroAbrir!, style: erro),
            Align(
              alignment: Alignment.centerLeft,
              child: BotaoLink(
                key: const Key('atualizar-provas'),
                texto: 'Atualizar fotos',
                aoTocar: _buscar,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
