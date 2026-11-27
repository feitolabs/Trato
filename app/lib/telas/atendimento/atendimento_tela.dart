import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../componentes/componentes.dart';
import '../../dados/erros.dart';
import '../../tema/tema.dart';
import '../comuns/estados.dart';
import '../comuns/formato_aparelho.dart';
import '../comuns/textos_dos_termos.dart';
import '../legal/guardar_texto.dart';
import 'modelos.dart';

String _quando(DateTime d) => '${d.day.toString().padLeft(2, '0')}/'
    '${d.month.toString().padLeft(2, '0')}/${d.year}, ${horaDoAparelho(d)}';

/// Um pedido que pode ser ligado ao chamado.
typedef PedidoDoChamado = ({String id, String rotulo});

String? _linhaDePrazo(Chamado c) {
  if (c.encerrado) return null;
  if (c.novoPrazoAte != null) return 'Novo prazo de resposta: ${_quando(c.novoPrazoAte!)}';
  if (c.responderAte != null) return 'Resposta até ${_quando(c.responderAte!)}';
  return null;
}

/// A cópia da conversa em texto puro (25.3).
String copiaDaConversa(Chamado c) {
  final saida = StringBuffer()
    ..writeln('Atendimento Trato')
    ..writeln('Protocolo: ${c.protocolo}')
    ..writeln('Assunto: ${c.assunto}')
    ..writeln('Categoria: ${c.categoriaTexto}')
    ..writeln('Situação: ${c.statusTexto}');
  if (c.criadoEm != null) saida.writeln('Aberto em: ${_quando(c.criadoEm!)}');
  final prazo = _linhaDePrazo(c);
  if (prazo != null) saida.writeln(prazo);
  if (c.motivoExtensao != null) saida.writeln('Motivo do novo prazo: ${c.motivoExtensao}');
  for (final m in c.mensagens) {
    saida
      ..writeln()
      ..writeln('${m.nomeDoAutor}${m.criadaEm == null ? '' : ' · ${_quando(m.criadaEm!)}'}')
      ..writeln(m.texto);
  }
  return saida.toString();
}

/// "Falar com o Trato": os meus chamados e o botão de abrir um novo.
class AtendimentoTela extends StatefulWidget {
  const AtendimentoTela({
    super.key,
    required this.servico,
    this.carregarPedidos,
    this.pedidoInicial,
    this.aoEscreverEmail,
    this.guardar = guardarTextoNoAparelho,
  });

  final ServicoSac servico;
  final Future<List<PedidoDoChamado>> Function()? carregarPedidos;
  final String? pedidoInicial;

  /// Saída por e-mail quando o servidor não tem o atendimento.
  final VoidCallback? aoEscreverEmail;
  final GuardarTextoLegal guardar;

  @override
  State<AtendimentoTela> createState() => _AtendimentoTelaState();
}

class _AtendimentoTelaState extends State<AtendimentoTela> {
  /// Sobe quando algo muda numa tela aberta daqui, para a lista ser lida de novo.
  var _versao = 0;
  final _mais = <Chamado>[];
  var _carregandoMais = false;
  String? _erroMais;

  Future<void> _abrirTela(Widget tela) async {
    await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => tela));
    if (mounted) {
      setState(() {
        _versao++;
        _mais.clear();
      });
    }
  }

  Future<void> _carregarMais(int ja) async {
    if (_carregandoMais) return;
    setState(() {
      _carregandoMais = true;
      _erroMais = null;
    });
    try {
      final pagina = await widget.servico.listar(deslocamento: ja);
      if (mounted && pagina != null) setState(() => _mais.addAll(pagina.itens));
    } on Object catch (e) {
      if (mounted) {
        setState(() => _erroMais = e is ErroTrato ? e.mensagem : 'Não foi possível carregar.');
      }
    } finally {
      if (mounted) setState(() => _carregandoMais = false);
    }
  }

  void _ver(String id) => _abrirTela(
        ChamadoTela(servico: widget.servico, id: id, guardar: widget.guardar),
      );

  void _novo() => _abrirTela(
        NovoChamadoTela(
          servico: widget.servico,
          carregarPedidos: widget.carregarPedidos,
          pedidoInicial: widget.pedidoInicial,
          guardar: widget.guardar,
        ),
      );

  @override
  Widget build(BuildContext context) {
    final secundario = TipografiaTrato.corpoPequeno.copyWith(color: context.cores.textoSecundario);
    return MolduraTelaComum(
      titulo: 'Falar com o Trato',
      child: CarregadorTela<PaginaDeChamados?>(
        key: ValueKey('chamados-$_versao'),
        carregar: widget.servico.listar,
        construir: (context, pagina, _) {
          if (pagina == null) {
            return EstadoVazio(
              icone: Icons.support_agent,
              titulo: 'Atendimento pelo app indisponível',
              texto: '$textoAtendimentoIndisponivel $textoAtendimentoHumano',
              textoAcao: widget.aoEscreverEmail == null ? null : 'Escrever por e-mail',
              aoAcao: widget.aoEscreverEmail,
            );
          }
          final itens = [...pagina.itens, ..._mais];
          return ListView(
            padding: const EdgeInsets.only(bottom: EspacosTrato.x6),
            children: [
              Text(textoAtendimentoHumano, style: secundario),
              const SizedBox(height: EspacosTrato.x3),
              BotaoPrimario(
                key: const Key('abrir-chamado'),
                texto: 'Abrir chamado',
                aoTocar: _novo,
              ),
              const SizedBox(height: EspacosTrato.x5),
              Text('Seus chamados', style: TipografiaTrato.titulo),
              const SizedBox(height: EspacosTrato.x3),
              if (itens.isEmpty) Text('Você ainda não abriu nenhum chamado.', style: secundario),
              for (final c in itens) ...[
                CartaoTrato(
                  key: ValueKey('chamado-${c.id}'),
                  aoTocar: () => _ver(c.id),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(c.assunto, style: TipografiaTrato.tituloCartao),
                      Text('Protocolo ${c.protocolo} · ${c.statusTexto}', style: secundario),
                      if (_linhaDePrazo(c) != null) Text(_linhaDePrazo(c)!, style: secundario),
                    ],
                  ),
                ),
                const SizedBox(height: EspacosTrato.x3),
              ],
              if (_erroMais != null)
                Text(
                  _erroMais!,
                  style: TipografiaTrato.corpoPequeno.copyWith(color: context.cores.vermelhoTexto),
                ),
              if (itens.length < pagina.total)
                Center(
                  child: BotaoLink(
                    key: const Key('mais-chamados'),
                    texto: _carregandoMais ? 'Carregando…' : 'Ver mais',
                    aoTocar: () => _carregarMais(itens.length),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class NovoChamadoTela extends StatefulWidget {
  const NovoChamadoTela({
    super.key,
    required this.servico,
    this.carregarPedidos,
    this.pedidoInicial,
    this.guardar = guardarTextoNoAparelho,
    this.seguranca = false,
    this.orientarChegada = false,
    this.pessoaDiferente,
    this.casoInicial,
    this.aoRelatarPessoaDiferente,
  });

  /// Só para o cliente: "pessoa diferente" vai pela rota que pode cancelar o pedido (9.5).
  final ServicoPessoaDiferente? pessoaDiferente;

  /// Caso já escolhido ao abrir.
  final String? casoInicial;

  /// O servidor aceitou o relato: quem abriu atualiza o pedido.
  final VoidCallback? aoRelatarPessoaDiferente;

  final ServicoSac servico;
  final Future<List<PedidoDoChamado>> Function()? carregarPedidos;
  final String? pedidoInicial;
  final GuardarTextoLegal guardar;

  /// Atalho da emergência do pedido: categoria `seguranca`, pedido fixo e os casos da 9.4.
  final bool seguranca;

  /// Cliente em atendimento presencial: orientar sobre quem chega (9.5).
  final bool orientarChegada;

  @override
  State<NovoChamadoTela> createState() => _NovoChamadoTelaState();
}

class _NovoChamadoTelaState extends State<NovoChamadoTela> {
  late final _assunto = TextEditingController(text: widget.casoInicial);

  /// A rota de pessoa diferente falhou: o chamado de segurança passa a ser oferecido.
  var _rotaFalhou = false;
  RelatoPessoaDiferente? _relato;

  bool get _viaRota =>
      widget.seguranca &&
      widget.pessoaDiferente != null &&
      _pedido != null &&
      _assunto.text == casoPessoaDiferente;
  final _textoCampo = TextEditingController();
  late String? _categoria = widget.seguranca ? 'seguranca' : null;
  late String? _pedido = widget.pedidoInicial;
  List<PedidoDoChamado> _pedidos = const [];
  var _falhaPedidos = false;
  var _tentou = false;
  var _enviando = false;
  String? _erro;

  @override
  void initState() {
    super.initState();
    _buscarPedidos();
  }

  Future<void> _buscarPedidos() async {
    final carregar = widget.carregarPedidos;
    if (carregar == null) return;
    setState(() => _falhaPedidos = false);
    try {
      final pedidos = await carregar();
      if (mounted) setState(() => _pedidos = pedidos);
    } on Object {
      if (mounted) setState(() => _falhaPedidos = true);
    }
  }

  @override
  void dispose() {
    _assunto.dispose();
    _textoCampo.dispose();
    super.dispose();
  }

  String? get _erroCategoria => _categoria == null ? 'Escolha o tipo de assunto.' : null;
  String? get _erroAssunto => _assunto.text.trim().length >= 3
      ? null
      : widget.seguranca
          ? 'Escolha o que aconteceu.'
          : 'Escreva o assunto.';
  String? get _erroTexto => _textoCampo.text.trim().isEmpty ? 'Escreva a mensagem.' : null;

  Future<void> _relatarPessoaDiferente() async {
    if (_enviando) return;
    final confirmou = await showDialog<bool>(
      context: context,
      builder: (dialogo) => AlertDialog(
        title: const Text('Relatar pessoa diferente?'),
        scrollable: true,
        content: const Text(
          'Ao enviar, o pedido pode ser cancelado na hora, com reembolso integral. '
          '$orientacaoPessoaDiferente',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogo).pop(false),
            child: const Text('Voltar'),
          ),
          FilledButton(
            key: const Key('confirmar-pessoa-diferente'),
            onPressed: () => Navigator.of(dialogo).pop(true),
            child: const Text('Enviar relato'),
          ),
        ],
      ),
    );
    if (confirmou != true || !mounted) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _enviando = true;
      _erro = null;
    });
    try {
      final relato = await widget.pessoaDiferente!.relatarPessoaDiferente(
        _pedido!,
        descricao: _textoCampo.text,
      );
      widget.aoRelatarPessoaDiferente?.call();
      if (mounted) setState(() => _relato = relato);
    } on Object catch (e) {
      if (!mounted) return;
      // 404 sem a rota e 503 viram texto próprio; os demais mostram o motivo do servidor.
      final indisponivel = e is ErroTrato &&
          (e.codigoHttp == 503 || (e.codigoHttp == 404 && e.mensagem == 'Not Found'));
      setState(() {
        _rotaFalhou = true;
        _erro = indisponivel || e is! ErroTrato
            ? 'Não foi possível enviar este relato pelo app agora.'
            : e.mensagem;
      });
    } finally {
      if (mounted) setState(() => _enviando = false);
    }
  }

  Widget _resultado(BuildContext context, RelatoPessoaDiferente r) {
    final corpo = TipografiaTrato.corpo.copyWith(color: context.cores.texto);
    return MolduraTelaComum(
      titulo: r.cancelado ? 'Pedido cancelado' : 'Relato registrado',
      child: ListView(
        children: [
          if (r.mensagem.isNotEmpty) Text(r.mensagem, style: corpo),
          if (r.protocolo.isNotEmpty) ...[
            const SizedBox(height: EspacosTrato.x3),
            Text('Protocolo ${r.protocolo}', style: TipografiaTrato.corpoForte),
          ],
          const SizedBox(height: EspacosTrato.x3),
          Text(
            'Em risco imediato, ligue 190 (Polícia), 192 (SAMU) ou 193 (Bombeiros).',
            style: corpo,
          ),
          const SizedBox(height: EspacosTrato.x5),
          BotaoPrimario(texto: 'Voltar', aoTocar: () => Navigator.of(context).maybePop()),
        ],
      ),
    );
  }

  Future<void> _enviar() async {
    if (_enviando) return;
    setState(() {
      _tentou = true;
      _erro = null;
    });
    if (_erroCategoria != null || _erroAssunto != null || _erroTexto != null) return;
    FocusScope.of(context).unfocus();
    setState(() => _enviando = true);
    try {
      final chamado = await widget.servico.abrir(
        categoria: _categoria!,
        assunto: _assunto.text,
        texto: _textoCampo.text,
        pedidoId: _pedido,
      );
      if (!mounted) return;
      await Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(
          builder: (_) => ChamadoTela(
            servico: widget.servico,
            id: chamado.id,
            inicial: chamado,
            recemAberto: true,
            guardar: widget.guardar,
          ),
        ),
      );
    } on Object catch (e) {
      if (mounted) {
        setState(() {
          _enviando = false;
          _erro = e is ErroTrato ? e.mensagem : 'Não foi possível enviar. Tente de novo.';
        });
      }
    }
  }

  /// Os casos da 9.4: tocar escolhe o assunto. Nada é enviado antes do botão.
  List<Widget> _casos(BuildContext context) {
    final c = context.cores;
    final corpo = TipografiaTrato.corpo.copyWith(color: c.texto);
    return [
      Text(
        'Em risco imediato, ligue primeiro: 190 (Polícia), 192 (SAMU) ou 193 (Bombeiros).',
        style: corpo.copyWith(fontWeight: FontWeight.w700),
      ),
      const SizedBox(height: EspacosTrato.x3),
      Text('O que aconteceu?', style: TipografiaTrato.tituloCartao),
      for (var i = 0; i < casosDeSeguranca.length; i++)
        Semantics(
          selected: _assunto.text == casosDeSeguranca[i],
          child: ListTile(
            key: ValueKey('caso-seguranca-$i'),
            contentPadding: EdgeInsets.zero,
            leading: Icon(
              _assunto.text == casosDeSeguranca[i]
                  ? Icons.radio_button_checked
                  : Icons.radio_button_unchecked,
              color: c.petroleo,
            ),
            title: Text(casosDeSeguranca[i], style: corpo),
            onTap: _enviando ? null : () => setState(() => _assunto.text = casosDeSeguranca[i]),
          ),
        ),
      if (_tentou && _erroAssunto != null)
        Text(_erroAssunto!, style: corpo.copyWith(color: c.vermelhoTexto)),
      if (widget.orientarChegada && _assunto.text == casoPessoaDiferente) ...[
        const SizedBox(height: EspacosTrato.x2),
        Text(
          orientacaoPessoaDiferente,
          key: const Key('orientacao-pessoa-diferente'),
          style: corpo.copyWith(color: c.vermelhoTexto, fontWeight: FontWeight.w700),
        ),
      ],
      const SizedBox(height: EspacosTrato.x2),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final pedidos = [
      ..._pedidos,
      if (_pedido != null && !_pedidos.any((p) => p.id == _pedido))
        (id: _pedido!, rotulo: 'Pedido em que você estava'),
    ];
    if (_relato case final relato?) return _resultado(context, relato);
    return MolduraTelaComum(
      titulo: widget.seguranca ? 'Relato de segurança' : 'Abrir chamado',
      child: ListView(
        padding: const EdgeInsets.only(bottom: EspacosTrato.x6),
        children: [
          if (widget.seguranca)
            ..._casos(context)
          else ...[
            DropdownButtonFormField<String>(
              key: const Key('categoria-chamado'),
              initialValue: _categoria,
              isExpanded: true,
              style: TipografiaTrato.corpo.copyWith(color: context.cores.texto),
              decoration: InputDecoration(
                labelText: 'Tipo de assunto',
                errorText: _tentou ? _erroCategoria : null,
              ),
              items: [
                for (final e in categoriasDeChamado.entries)
                  DropdownMenuItem(value: e.key, child: Text(e.value)),
              ],
              onChanged: (v) => setState(() => _categoria = v),
            ),
            const SizedBox(height: EspacosTrato.x4),
            TextField(
              key: const Key('assunto-chamado'),
              controller: _assunto,
              maxLength: 200,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                labelText: 'Assunto',
                errorText: _tentou ? _erroAssunto : null,
              ),
            ),
          ],
          const SizedBox(height: EspacosTrato.x2),
          TextField(
            key: const Key('texto-chamado'),
            controller: _textoCampo,
            maxLength: 4000,
            maxLines: 5,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              labelText: _viaRota && !_rotaFalhou ? 'Conte o que houve (opcional)' : 'Mensagem',
              errorText: _tentou ? _erroTexto : null,
            ),
          ),
          if (!widget.seguranca && (widget.carregarPedidos != null || _pedido != null)) ...[
            const SizedBox(height: EspacosTrato.x2),
            DropdownButtonFormField<String?>(
              key: ValueKey('pedido-chamado-${pedidos.length}'),
              initialValue: _pedido,
              isExpanded: true,
              style: TipografiaTrato.corpo.copyWith(color: context.cores.texto),
              decoration: const InputDecoration(labelText: 'Pedido (opcional)'),
              items: [
                const DropdownMenuItem<String?>(child: Text('Nenhum pedido')),
                for (final p in pedidos)
                  DropdownMenuItem<String?>(
                    value: p.id,
                    child: Text(p.rotulo, overflow: TextOverflow.ellipsis),
                  ),
              ],
              onChanged: (v) => setState(() => _pedido = v),
            ),
            if (_falhaPedidos)
              Align(
                alignment: Alignment.centerLeft,
                child: BotaoLink(
                  texto: 'Não carregou os pedidos. Tentar de novo',
                  aoTocar: _buscarPedidos,
                ),
              ),
          ],
          const SizedBox(height: EspacosTrato.x4),
          if (_erro != null) ...[
            Text(
              _erro!,
              key: const Key('erro-chamado'),
              style: TipografiaTrato.corpoPequeno.copyWith(color: context.cores.vermelhoTexto),
            ),
            const SizedBox(height: EspacosTrato.x2),
          ],
          if (_viaRota && _rotaFalhou) ...[
            Text(
              'Você ainda pode abrir um chamado de segurança. Ele registra o relato, mas não '
              'cancela o pedido por si só.',
              key: const Key('alternativa-chamado'),
              style: TipografiaTrato.corpoPequeno.copyWith(color: context.cores.texto),
            ),
            const SizedBox(height: EspacosTrato.x2),
          ],
          if (widget.seguranca && (!_viaRota || _rotaFalhou)) ...[
            Text(
              'O chamado fica ligado a este pedido. Enquanto ele estiver em análise, o valor '
              'ainda não liberado ao profissional pode ficar retido.',
              style: TipografiaTrato.corpoPequeno.copyWith(color: context.cores.texto),
            ),
            const SizedBox(height: EspacosTrato.x3),
          ],
          if (_viaRota) ...[
            BotaoPrimario(
              key: const Key('relatar-pessoa-diferente'),
              texto: _rotaFalhou ? 'Tentar o relato de novo' : 'Relatar pessoa diferente',
              carregando: _enviando && !_rotaFalhou,
              aoTocar: _relatarPessoaDiferente,
            ),
            const SizedBox(height: EspacosTrato.x3),
          ],
          if (!_viaRota || _rotaFalhou)
            BotaoPrimario(
              key: const Key('enviar-chamado'),
              texto: widget.seguranca ? 'Abrir chamado de segurança' : 'Enviar',
              carregando: _enviando,
              aoTocar: _enviar,
            ),
        ],
      ),
    );
  }
}

class ChamadoTela extends StatelessWidget {
  const ChamadoTela({
    super.key,
    required this.servico,
    required this.id,
    this.inicial,
    this.recemAberto = false,
    this.guardar = guardarTextoNoAparelho,
  });

  final ServicoSac servico;
  final String id;

  /// A resposta de quem acabou de abrir: mostra o protocolo na hora, sem esperar outra leitura.
  final Chamado? inicial;
  final bool recemAberto;
  final GuardarTextoLegal guardar;

  @override
  Widget build(BuildContext context) {
    var primeira = inicial;
    return MolduraTelaComum(
      titulo: 'Chamado',
      child: CarregadorTela<Chamado>(
        carregar: () async {
          final ja = primeira;
          primeira = null;
          return ja ?? await servico.ver(id);
        },
        construir: (context, chamado, _) => _Conversa(tela: this, chamado: chamado),
      ),
    );
  }
}

class _Conversa extends StatefulWidget {
  const _Conversa({required this.tela, required this.chamado});

  final ChamadoTela tela;
  final Chamado chamado;

  @override
  State<_Conversa> createState() => _ConversaState();
}

class _ConversaState extends State<_Conversa> {
  late Chamado _chamado = widget.chamado;
  final _resposta = TextEditingController();
  var _enviando = false;
  var _copiado = false;
  String? _erro;

  @override
  void didUpdateWidget(covariant _Conversa antigo) {
    super.didUpdateWidget(antigo);
    if (widget.chamado != antigo.chamado) _chamado = widget.chamado;
  }

  @override
  void dispose() {
    _resposta.dispose();
    super.dispose();
  }

  Future<void> _responder() async {
    if (_enviando) return;
    final texto = _resposta.text.trim();
    if (texto.isEmpty) {
      setState(() => _erro = 'Escreva a mensagem.');
      return;
    }
    setState(() {
      _enviando = true;
      _erro = null;
    });
    try {
      final novo = await widget.tela.servico.responder(_chamado.id, texto);
      if (!mounted) return;
      setState(() {
        _chamado = novo;
        _resposta.clear();
      });
    } on Object catch (e) {
      if (mounted) {
        setState(
            () => _erro = e is ErroTrato ? e.mensagem : 'Não foi possível enviar. Tente de novo.');
      }
    } finally {
      if (mounted) setState(() => _enviando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = _chamado;
    final secundario = TipografiaTrato.corpoPequeno.copyWith(color: context.cores.textoSecundario);
    return ListView(
      padding: const EdgeInsets.only(bottom: EspacosTrato.x6),
      children: [
        CartaoTrato(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (widget.tela.recemAberto) ...[
                Text('Recebemos o seu contato. Guarde o protocolo.', style: TipografiaTrato.corpo),
                const SizedBox(height: EspacosTrato.x2),
              ],
              Text('Protocolo', style: secundario),
              SelectableText(c.protocolo,
                  key: const Key('protocolo'), style: TipografiaTrato.titulo),
              BotaoLink(
                key: const Key('copiar-protocolo'),
                texto: _copiado ? 'Protocolo copiado' : 'Copiar protocolo',
                aoTocar: () async {
                  await Clipboard.setData(ClipboardData(text: c.protocolo));
                  if (mounted) setState(() => _copiado = true);
                },
              ),
              Text(c.assunto, style: TipografiaTrato.tituloCartao),
              Text('${c.categoriaTexto} · ${c.statusTexto}', style: secundario),
              if (_linhaDePrazo(c) != null) ...[
                const SizedBox(height: EspacosTrato.x2),
                Text(_linhaDePrazo(c)!,
                    key: const Key('prazo-chamado'), style: TipografiaTrato.corpoForte),
              ],
              if (c.motivoExtensao != null)
                Text('Motivo do novo prazo: ${c.motivoExtensao}', style: TipografiaTrato.corpo),
            ],
          ),
        ),
        const SizedBox(height: EspacosTrato.x4),
        for (final m in c.mensagens) ...[
          Text(
            '${m.nomeDoAutor}${m.criadaEm == null ? '' : ' · ${_quando(m.criadaEm!)}'}',
            style: secundario,
          ),
          Text(m.texto, style: TipografiaTrato.corpo),
          const SizedBox(height: EspacosTrato.x3),
        ],
        if (c.encerrado)
          Text('Este chamado foi encerrado. Se precisar, abra um novo.', style: secundario)
        else ...[
          TextField(
            key: const Key('resposta-chamado'),
            controller: _resposta,
            maxLength: 4000,
            maxLines: 3,
            decoration: const InputDecoration(labelText: 'Sua mensagem'),
          ),
          if (_erro != null) ...[
            Text(
              _erro!,
              key: const Key('erro-resposta'),
              style: TipografiaTrato.corpoPequeno.copyWith(color: context.cores.vermelhoTexto),
            ),
            const SizedBox(height: EspacosTrato.x2),
          ],
          BotaoPrimario(
            key: const Key('enviar-resposta'),
            texto: 'Enviar mensagem',
            carregando: _enviando,
            aoTocar: _responder,
          ),
        ],
        const SizedBox(height: EspacosTrato.x4),
        BotaoGuardarTexto(
          nomeArquivo:
              'trato-atendimento-${c.protocolo.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '-')}.txt',
          conteudo: copiaDaConversa(c),
          guardar: widget.tela.guardar,
        ),
      ],
    );
  }
}
