import 'package:flutter/material.dart';

import '../../componentes/componentes.dart';
import '../../dados/erros.dart';
import '../../dispositivo/seletor_pdf.dart';
import '../../tema/tema.dart';
import '../comuns/estados.dart';
import '../comuns/formato_aparelho.dart';
import '../comuns/textos_dos_termos.dart';
import 'modelos.dart';

String _quando(DateTime d) => '${d.day.toString().padLeft(2, '0')}/'
    '${d.month.toString().padLeft(2, '0')}/${d.year}, ${horaDoAparelho(d)}';

/// "Medidas da conta", para cliente e profissional.
class MedidasTela extends StatefulWidget {
  const MedidasTela({super.key, required this.servico, this.escolherProva, this.escolherPdf});

  final ServicoMedidas servico;

  /// Escolhe um arquivo para a contestação (nulo se a pessoa cancelar).
  final Future<ProvaEscolhida?> Function()? escolherProva;

  /// Escolhe um PDF no aparelho (nulo se a pessoa cancelar).
  final Future<ProvaEscolhida?> Function()? escolherPdf;

  @override
  State<MedidasTela> createState() => _MedidasTelaState();
}

class _MedidasTelaState extends State<MedidasTela> {
  /// Sobe ao voltar da contestação, para a lista ser lida de novo.
  var _versao = 0;

  Future<void> _contestar(MedidaDeConta medida) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ContestarMedidaTela(
          servico: widget.servico,
          medida: medida,
          escolherProva: widget.escolherProva,
          escolherPdf: widget.escolherPdf,
        ),
      ),
    );
    if (mounted) setState(() => _versao++);
  }

  @override
  Widget build(BuildContext context) {
    return MolduraTelaComum(
      titulo: 'Medidas da conta',
      child: CarregadorTela<List<MedidaDeConta>?>(
        key: ValueKey('medidas-$_versao'),
        carregar: widget.servico.listar,
        construir: (context, medidas, _) {
          if (medidas == null) {
            return const EstadoVazio(
              icone: Icons.gavel_outlined,
              titulo: 'Medidas indisponíveis',
              texto: textoMedidasIndisponiveis,
            );
          }
          if (medidas.isEmpty) {
            return const EstadoVazio(
              icone: Icons.verified_user_outlined,
              titulo: 'Nenhuma medida',
              texto: 'Sua conta não tem nenhuma medida registrada.',
            );
          }
          return ListView(
            padding: const EdgeInsets.only(bottom: EspacosTrato.x6),
            children: [
              for (final m in medidas) ...[
                _CartaoMedida(medida: m, aoContestar: () => _contestar(m)),
                const SizedBox(height: EspacosTrato.x3),
              ],
              Text(
                textoAtendimentoHumano,
                style: TipografiaTrato.corpoPequeno
                    .copyWith(color: context.cores.textoSecundario),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _CartaoMedida extends StatelessWidget {
  const _CartaoMedida({required this.medida, required this.aoContestar});

  final MedidaDeConta medida;
  final VoidCallback aoContestar;

  @override
  Widget build(BuildContext context) {
    final m = medida;
    final secundario =
        TipografiaTrato.corpoPequeno.copyWith(color: context.cores.textoSecundario);
    List<Widget> bloco(String rotulo, String? texto) => [
          if (texto != null) ...[
            const SizedBox(height: EspacosTrato.x2),
            Text(rotulo, style: secundario),
            Text(texto, style: TipografiaTrato.corpo),
          ],
        ];
    final c = m.contestacao;
    return CartaoTrato(
      key: ValueKey('medida-${m.id}'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(m.tipoTexto, style: TipografiaTrato.tituloCartao),
          Text(
            [m.situacaoTexto, if (m.protocolo != null) 'Protocolo ${m.protocolo}'].join(' · '),
            style: secundario,
          ),
          ...bloco('Motivo', m.motivo),
          ...bloco('Cláusulas dos Termos', m.clausulas.isEmpty ? null : m.clausulas.join(', ')),
          ...bloco('Início', m.inicioEm == null ? null : _quando(m.inicioEm!)),
          ...bloco('Fim', m.fimEm == null ? null : _quando(m.fimEm!)),
          ...bloco('Revertida em', m.revertidaEm == null ? null : _quando(m.revertidaEm!)),
          ...bloco('Pedidos e valores em andamento', m.efeito),
          ...bloco('Como contestar', m.comoContestar),
          if (c != null) ...[
            const SizedBox(height: EspacosTrato.x3),
            const Divider(),
            Text(c.statusTexto,
                key: ValueKey('contestacao-${m.id}'), style: TipografiaTrato.corpoForte),
            if (c.protocolo != null) Text('Protocolo ${c.protocolo}', style: secundario),
            if (c.decididaEm != null)
              Text('Respondida em ${_quando(c.decididaEm!)}', style: secundario)
            else if (c.responderAte != null)
              Text('Resposta até ${_quando(c.responderAte!)}', style: secundario),
            ...bloco('Sua versão', c.versao),
            ...bloco(
              'Provas enviadas',
              c.anexos.isEmpty
                  ? null
                  : [
                      for (final (i, a) in c.anexos.indexed)
                        '${i + 1}. ${nomeDoTipo(a.contentType)} · ${tamanhoLegivel(a.tamanhoBytes)}',
                    ].join('\n'),
            ),
            ...bloco('Resposta', c.resposta),
          ] else if (m.contestavelAte != null && m.revertidaEm == null) ...[
            const SizedBox(height: EspacosTrato.x3),
            Text(
              m.podeContestar(DateTime.now())
                  ? 'Dá para contestar até ${_quando(m.contestavelAte!)}.'
                  : 'O prazo para contestar terminou em ${_quando(m.contestavelAte!)}.',
              key: ValueKey('prazo-${m.id}'),
              style: TipografiaTrato.corpo,
            ),
            if (m.podeContestar(DateTime.now())) ...[
              const SizedBox(height: EspacosTrato.x2),
              BotaoSecundario(
                key: ValueKey('contestar-${m.id}'),
                texto: 'Contestar',
                aoTocar: aoContestar,
              ),
            ],
          ],
        ],
      ),
    );
  }
}

/// O campo "a sua versão" (Termos 20.5).
class ContestarMedidaTela extends StatefulWidget {
  const ContestarMedidaTela({
    super.key,
    required this.servico,
    required this.medida,
    this.escolherProva,
    this.escolherPdf,
  });

  final ServicoMedidas servico;
  final MedidaDeConta medida;
  final Future<ProvaEscolhida?> Function()? escolherProva;

  /// Escolhe um PDF no aparelho (nulo se a pessoa cancelar).
  final Future<ProvaEscolhida?> Function()? escolherPdf;

  @override
  State<ContestarMedidaTela> createState() => _ContestarMedidaTelaState();
}

class _ContestarMedidaTelaState extends State<ContestarMedidaTela> {
  final _versao = TextEditingController();
  var _enviando = false;
  String? _erro;
  MedidaDeConta? _enviada;

  /// Ficam na tela quando o envio falha, junto com o texto.
  final _provas = <ProvaEscolhida>[];
  var _escolhendo = false;
  String? _erroProva;

  Future<void> _adicionar(Future<ProvaEscolhida?> Function() escolher) async {
    if (_escolhendo || _enviando || _provas.length >= maximoDeProvas) return;
    setState(() {
      _escolhendo = true;
      _erroProva = null;
    });
    try {
      final prova = await escolher();
      if (!mounted || prova == null) return;
      setState(() {
        if (tipoDaProva(prova.bytes) == null) {
          _erroProva = textoProvaRecusada;
        } else if (prova.bytes.length > tamanhoMaximoDaProva) {
          _erroProva = 'O arquivo "${prova.nome}" passa de 10 MB.';
        } else {
          _provas.add(prova);
        }
      });
    } on PdfGrandeDemais catch (e) {
      if (mounted) setState(() => _erroProva = 'O arquivo "${e.nome}" passa de 10 MB.');
    } on Object {
      if (mounted) setState(() => _erroProva = 'Não deu para abrir o arquivo. Tente de novo.');
    } finally {
      if (mounted) setState(() => _escolhendo = false);
    }
  }

  @override
  void dispose() {
    _versao.dispose();
    super.dispose();
  }

  Future<void> _enviar() async {
    if (_enviando) return;
    final texto = _versao.text.trim();
    if (texto.isEmpty) {
      setState(() => _erro = 'Conte a sua versão.');
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _enviando = true;
      _erro = null;
    });
    try {
      final medida = await widget.servico.contestar(
        widget.medida.id,
        texto,
        provas: List.of(_provas),
      );
      if (mounted) setState(() => _enviada = medida);
    } on Object catch (e) {
      if (mounted) {
        setState(() =>
            _erro = e is ErroTrato ? e.mensagem : 'Não foi possível enviar. Tente de novo.');
      }
    } finally {
      if (mounted) setState(() => _enviando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final enviada = _enviada;
    return MolduraTelaComum(
      titulo: 'Contestar medida',
      child: ListView(
        padding: const EdgeInsets.only(bottom: EspacosTrato.x6),
        children: [
          Text(widget.medida.tipoTexto, style: TipografiaTrato.titulo),
          const SizedBox(height: EspacosTrato.x3),
          if (enviada != null) ...[
            Text(
              'Recebemos a sua contestação.',
              key: const Key('contestacao-recebida'),
              style: TipografiaTrato.corpoForte,
            ),
            if (enviada.contestacao?.protocolo case final protocolo?)
              SelectableText('Protocolo $protocolo', style: TipografiaTrato.corpo),
            if (enviada.contestacao?.responderAte case final ate?)
              Text('Resposta até ${_quando(ate)}', style: TipografiaTrato.corpo),
            const SizedBox(height: EspacosTrato.x4),
            BotaoPrimario(texto: 'Voltar', aoTocar: () => Navigator.of(context).maybePop()),
          ] else ...[
            Text(
              'Conte o que aconteceu do seu ponto de vista. Dá para contestar uma vez.',
              style: TipografiaTrato.corpo,
            ),
            const SizedBox(height: EspacosTrato.x3),
            TextField(
              key: const Key('versao-contestacao'),
              controller: _versao,
              maxLength: 4000,
              maxLines: 6,
              onChanged: (_) {
                if (_erro != null) setState(() => _erro = null);
              },
              decoration: const InputDecoration(labelText: 'A sua versão'),
            ),
            if (widget.escolherProva != null || widget.escolherPdf != null) ...[
              Text(
                'Provas (opcional): ${_provas.length} de $maximoDeProvas, até 10 MB cada.',
                style: TipografiaTrato.corpoPequeno,
              ),
              for (var i = 0; i < _provas.length; i++)
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${_provas[i].nome} · ${tamanhoLegivel(_provas[i].bytes.length)}',
                        style: TipografiaTrato.corpo,
                      ),
                    ),
                    IconButton(
                      key: ValueKey('remover-prova-$i'),
                      tooltip: 'Remover ${_provas[i].nome}',
                      icon: const Icon(Icons.close),
                      onPressed: _enviando ? null : () => setState(() => _provas.removeAt(i)),
                    ),
                  ],
                ),
              if (_erroProva != null)
                Text(
                  _erroProva!,
                  key: const Key('erro-prova'),
                  style:
                      TipografiaTrato.corpoPequeno.copyWith(color: context.cores.vermelhoTexto),
                ),
              if (_provas.length < maximoDeProvas) ...[
                if (widget.escolherProva case final escolher?)
                  BotaoLink(
                    key: const Key('adicionar-prova'),
                    texto: _escolhendo ? 'Abrindo…' : 'Adicionar foto como prova',
                    aoTocar: () => _adicionar(escolher),
                  ),
                if (widget.escolherPdf case final escolher?)
                  BotaoLink(
                    key: const Key('adicionar-pdf'),
                    texto: _escolhendo ? 'Abrindo…' : 'Adicionar PDF como prova',
                    aoTocar: () => _adicionar(escolher),
                  ),
              ],
              const SizedBox(height: EspacosTrato.x3),
            ],
            if (_erro != null) ...[
              Text(
                _erro!,
                key: const Key('erro-contestacao-medida'),
                style: TipografiaTrato.corpoPequeno.copyWith(color: context.cores.vermelhoTexto),
              ),
              const SizedBox(height: EspacosTrato.x2),
            ],
            BotaoPrimario(
              key: const Key('enviar-contestacao-medida'),
              texto: 'Enviar contestação',
              carregando: _enviando,
              aoTocar: _enviar,
            ),
          ],
        ],
      ),
    );
  }
}

/// Tela de bloqueio: a API respondeu `conta_bloqueada`. A pessoa continua logada para falar com
/// o Trato, ver as medidas ou sair.
class ContaBloqueadaTela extends StatefulWidget {
  const ContaBloqueadaTela({
    super.key,
    this.mensagem,
    required this.aoFalar,
    required this.aoSair,
    this.temMedidas,
    this.aoVerMedidas,
    this.contaEncerrada,
    this.aoPedirRetorno,
    this.temPedidos,
    this.aoVerPedidos,
  });

  /// Verdadeiro: há pedido já contratado como cliente (confirmar conclusão ou relatar problema).
  final Future<bool> Function()? temPedidos;
  final VoidCallback? aoVerPedidos;

  /// O texto do servidor.
  final String? mensagem;
  final VoidCallback aoFalar;
  final Future<void> Function() aoSair;

  /// Falso: o servidor não tem as medidas (a entrada some).
  final Future<bool> Function()? temMedidas;
  final VoidCallback? aoVerMedidas;

  /// Verdadeiro: há um encerramento de conta (20.9). Suspensão não mostra o pedido de retorno.
  final Future<bool> Function()? contaEncerrada;
  final VoidCallback? aoPedirRetorno;

  @override
  State<ContaBloqueadaTela> createState() => _ContaBloqueadaTelaState();
}

class _ContaBloqueadaTelaState extends State<ContaBloqueadaTela> {
  var _medidas = false;
  var _retorno = false;
  var _pedidos = false;
  var _saindo = false;

  @override
  void initState() {
    super.initState();
    _conferir();
    _conferirRetorno();
    _conferirPedidos();
  }

  Future<void> _conferirPedidos() async {
    final conferir = widget.temPedidos;
    if (conferir == null || widget.aoVerPedidos == null) return;
    var tem = true;
    try {
      tem = await conferir();
    } on Object {
      // Falha passageira: a entrada aparece e a lista tem "tentar de novo".
    }
    if (mounted) setState(() => _pedidos = tem);
  }

  Future<void> _conferirRetorno() async {
    final conferir = widget.contaEncerrada;
    if (conferir == null || widget.aoPedirRetorno == null) return;
    var encerrada = true;
    try {
      encerrada = await conferir();
    } on Object {
      // Falha passageira: a entrada aparece e o servidor decide quem pode pedir.
    }
    if (mounted) setState(() => _retorno = encerrada);
  }

  Future<void> _conferir() async {
    final conferir = widget.temMedidas;
    if (conferir == null || widget.aoVerMedidas == null) return;
    var tem = true;
    try {
      tem = await conferir();
    } on Object {
      // Falha passageira: a entrada aparece e a tela dela tem "tentar de novo".
    }
    if (mounted) setState(() => _medidas = tem);
  }

  Future<void> _sair() async {
    if (_saindo) return;
    setState(() => _saindo = true);
    try {
      await widget.aoSair();
    } finally {
      if (mounted) setState(() => _saindo = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(vertical: EspacosTrato.x6),
          child: ConteudoResponsivo(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Icon(Icons.lock_outline, size: 48, color: context.cores.petroleo),
                const SizedBox(height: EspacosTrato.x4),
                Text('Conta bloqueada', style: TipografiaTrato.tituloGrande),
                const SizedBox(height: EspacosTrato.x3),
                Text(
                  widget.mensagem ?? 'Sua conta está bloqueada no momento.',
                  key: const Key('motivo-bloqueio'),
                  style: TipografiaTrato.corpo,
                ),
                const SizedBox(height: EspacosTrato.x2),
                Text(
                  textoAtendimentoHumano,
                  style: TipografiaTrato.corpo.copyWith(color: context.cores.textoSecundario),
                ),
                const SizedBox(height: EspacosTrato.x6),
                BotaoPrimario(
                  key: const Key('bloqueio-falar'),
                  texto: 'Falar com o Trato',
                  aoTocar: widget.aoFalar,
                ),
                if (_pedidos) ...[
                  const SizedBox(height: EspacosTrato.x3),
                  BotaoSecundario(
                    key: const Key('bloqueio-pedidos'),
                    texto: 'Meus pedidos contratados',
                    aoTocar: widget.aoVerPedidos!,
                  ),
                ],
                if (_medidas) ...[
                  const SizedBox(height: EspacosTrato.x3),
                  BotaoSecundario(
                    key: const Key('bloqueio-medidas'),
                    texto: 'Ver medidas da conta',
                    aoTocar: widget.aoVerMedidas!,
                  ),
                ],
                if (_retorno) ...[
                  const SizedBox(height: EspacosTrato.x3),
                  BotaoSecundario(
                    key: const Key('bloqueio-retorno'),
                    texto: 'Pedir retorno da conta',
                    aoTocar: widget.aoPedirRetorno!,
                  ),
                ],
                const SizedBox(height: EspacosTrato.x3),
                Center(
                  child: BotaoLink(
                    key: const Key('bloqueio-sair'),
                    texto: _saindo ? 'Saindo…' : 'Sair',
                    aoTocar: _sair,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Descobre se o servidor tem as medidas antes de mostrar a entrada nas Configurações.
class EntradaDeMedidas extends StatefulWidget {
  const EntradaDeMedidas({super.key, required this.verificar, required this.construir});

  final Future<bool> Function()? verificar;
  final Widget Function(BuildContext context, bool temMedidas) construir;

  @override
  State<EntradaDeMedidas> createState() => _EntradaDeMedidasState();
}

class _EntradaDeMedidasState extends State<EntradaDeMedidas> {
  var _tem = false;

  @override
  void initState() {
    super.initState();
    _conferir();
  }

  Future<void> _conferir() async {
    final verificar = widget.verificar;
    if (verificar == null) return;
    var tem = true;
    try {
      tem = await verificar();
    } on Object {
      // Falha passageira: a entrada aparece e a tela dela tem "tentar de novo".
    }
    if (mounted) setState(() => _tem = tem);
  }

  @override
  Widget build(BuildContext context) => widget.construir(context, _tem);
}
