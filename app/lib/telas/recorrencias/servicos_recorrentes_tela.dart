import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../componentes/componentes.dart';
import '../../dados/erros.dart';
import '../../tema/tema.dart';
import '../comuns/estados.dart';
import '../pedido_novo/pecas_pedido.dart' show EstruturaPedido;
import '../profissional/dinheiro.dart';
import '../profissional_apoio/apoio.dart';
import 'modelos.dart';

/// Abre o pedido de uma visita pelo `pedido_id`. [souCliente] diz qual lado da conta abre.
typedef AbrirPedidoDaVisita = void Function(String pedidoId, bool souCliente);

/// Aviso de ação que só funciona com internet; os outros erros mostram o texto do backend.
String _mensagemDaAcao(Object erro) {
  if (erro is ErroTrato) {
    return erro.tipo == TipoErro.semInternet
        ? 'Sem internet. Conecte-se para concluir esta ação.'
        : erro.mensagem;
  }
  return 'Não foi possível concluir agora. Tente de novo.';
}

/// "Serviços recorrentes": a lista da conta (cliente ou profissional), com o status em português
/// simples. Tocar numa série abre o detalhe com as visitas e as ações do seu papel.
class ServicosRecorrentesTela extends StatefulWidget {
  const ServicosRecorrentesTela({super.key, required this.servico, this.aoAbrirPedido});

  final ServicoRecorrencias servico;
  final AbrirPedidoDaVisita? aoAbrirPedido;

  @override
  State<ServicosRecorrentesTela> createState() => _ServicosRecorrentesTelaState();
}

class _ServicosRecorrentesTelaState extends State<ServicosRecorrentesTela> {
  final _recarregar = ValueNotifier<int>(0);

  @override
  void dispose() {
    _recarregar.dispose();
    super.dispose();
  }

  Future<void> _abrir(Recorrencia r) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => DetalheRecorrenciaTela(
          servico: widget.servico,
          recorrenciaId: r.id,
          inicial: r,
          aoAbrirPedido: widget.aoAbrirPedido,
        ),
      ),
    );
    if (mounted) _recarregar.value++; // o detalhe pode ter mudado o status
  }

  @override
  Widget build(BuildContext context) {
    return PaginaCarregavel<List<Recorrencia>>(
      titulo: 'Serviços recorrentes',
      atualizarQuando: _recarregar,
      carregar: widget.servico.listar,
      estaVazio: (lista) => lista.isEmpty,
      iconeVazio: Icons.event_repeat_outlined,
      tituloVazio: 'Nenhum serviço recorrente ainda',
      textoVazio: 'Quando um serviço terminar, toque em "Repetir este serviço" para combinar '
          'visitas toda semana, a cada 15 dias ou todo mês.',
      construir: (context, lista) => CorpoRolavel(
        children: [
          for (final r in lista)
            Padding(
              padding: const EdgeInsets.only(bottom: EspacosTrato.x3),
              child: _CartaoSerie(serie: r, aoTocar: () => _abrir(r)),
            ),
        ],
      ),
    );
  }
}

class _CartaoSerie extends StatelessWidget {
  const _CartaoSerie({required this.serie, required this.aoTocar});

  final Recorrencia serie;
  final VoidCallback aoTocar;

  @override
  Widget build(BuildContext context) {
    final c = context.cores;
    final nome = (serie.outraParteNome ?? '').trim();
    return CartaoTrato(
      key: ValueKey('serie-${serie.id}'),
      aoTocar: aoTocar,
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(nome.isEmpty ? 'Serviço recorrente' : nome, style: TipografiaTrato.corpoForte),
                const SizedBox(height: EspacosTrato.x1),
                Text(
                  '${serie.textoFrequencia} · ${Dinheiro.formatar(serie.valorCentavos)} por visita',
                  style: TipografiaTrato.corpoPequeno.copyWith(color: c.textoSecundario),
                ),
                if (!serie.cancelada)
                  Text(
                    'Próxima visita: ${dataHoraBrasilia(serie.proximaVisita)}',
                    style: TipografiaTrato.corpoPequeno.copyWith(color: c.textoSecundario),
                  ),
                const SizedBox(height: EspacosTrato.x2),
                Text(
                  serie.textoStatus,
                  key: ValueKey('status-${serie.id}'),
                  style: TipografiaTrato.corpoPequeno.copyWith(
                    color: serie.cancelada ? c.textoSecundario : c.azulTexto,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          Icon(Icons.chevron_right, color: c.textoSecundario),
        ],
      ),
    );
  }
}

/// Detalhe da série: proposta pendente (aceitar/recusar ou aguardar/cancelar), reajuste de valor,
/// ações do status (pausar, retomar, pular, cancelar) e as visitas. Cada ação chama o backend e
/// troca a tela pela série devolvida; cancelar a série e pular visita pedem confirmação.
class DetalheRecorrenciaTela extends StatefulWidget {
  const DetalheRecorrenciaTela({
    super.key,
    required this.servico,
    required this.recorrenciaId,
    this.inicial,
    this.aoAbrirPedido,
  });

  final ServicoRecorrencias servico;
  final String recorrenciaId;

  /// A série já conhecida (da lista): aparece na hora e é atualizada com as visitas.
  final Recorrencia? inicial;
  final AbrirPedidoDaVisita? aoAbrirPedido;

  @override
  State<DetalheRecorrenciaTela> createState() => _DetalheRecorrenciaTelaState();
}

class _DetalheRecorrenciaTelaState extends State<DetalheRecorrenciaTela> {
  Recorrencia? _serie;
  Object? _erroCarga;
  String? _erroAcao;
  var _ocupado = false;
  var _carregando = false;

  @override
  void initState() {
    super.initState();
    _serie = widget.inicial;
    _carregar();
  }

  Future<void> _carregar() async {
    if (_carregando) return;
    _carregando = true;
    if (mounted) setState(() => _erroCarga = null);
    try {
      final s = await widget.servico.detalhe(widget.recorrenciaId);
      if (mounted) setState(() => _serie = s);
    } on Object catch (e) {
      // Com a série da lista na tela, a falha não apaga o que já se vê.
      if (mounted && _serie == null) setState(() => _erroCarga = e);
    } finally {
      _carregando = false;
    }
  }

  Future<void> _agir(Future<Recorrencia> Function() acao, {bool recarregarSe409 = false}) async {
    if (_ocupado) return;
    setState(() {
      _ocupado = true;
      _erroAcao = null;
    });
    try {
      final nova = await acao();
      if (mounted) setState(() => _serie = nova);
    } on Object catch (e) {
      if (mounted) setState(() => _erroAcao = _mensagemDaAcao(e));
      // Valor do reajuste mudou: busca a série de novo para mostrar o valor novo.
      if (recarregarSe409 && e is ErroTrato && e.codigoHttp == 409) await _carregar();
    } finally {
      if (mounted) setState(() => _ocupado = false);
    }
  }

  Future<bool> _confirmar({
    required String titulo,
    required String texto,
    required String rotuloConfirmar,
    required Key chaveConfirmar,
  }) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogo) => AlertDialog(
        title: Text(titulo),
        content: Text(texto),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogo).pop(false),
            child: const Text('Voltar'),
          ),
          FilledButton(
            key: chaveConfirmar,
            onPressed: () => Navigator.of(dialogo).pop(true),
            child: Text(rotuloConfirmar),
          ),
        ],
      ),
    );
    return ok == true;
  }

  Future<void> _cancelarSerie(Recorrencia s) async {
    final ok = await _confirmar(
      titulo: s.proposta ? 'Cancelar a proposta?' : 'Cancelar o serviço recorrente?',
      texto: 'As próximas visitas deixam de ser agendadas.',
      rotuloConfirmar: s.proposta ? 'Cancelar proposta' : 'Cancelar série',
      chaveConfirmar: const ValueKey('confirmar-cancelar-serie'),
    );
    if (ok && mounted) await _agir(() => widget.servico.cancelar(s.id));
  }

  Future<void> _pularProxima(Recorrencia s) async {
    final ok = await _confirmar(
      titulo: 'Pular a próxima visita?',
      texto: 'A série continua nas datas seguintes.',
      rotuloConfirmar: 'Pular visita',
      chaveConfirmar: const ValueKey('confirmar-pular-visita'),
    );
    if (ok && mounted) await _agir(() => widget.servico.pularProxima(s.id));
  }

  Future<void> _pularVisita(Recorrencia s, VisitaRecorrente v) async {
    final ok = await _confirmar(
      titulo: 'Pular esta visita?',
      texto: 'A visita de ${dataHoraBrasilia(v.dataPrevista)} não acontece. '
          'A série continua nas datas seguintes.',
      rotuloConfirmar: 'Pular visita',
      chaveConfirmar: const ValueKey('confirmar-pular-visita'),
    );
    if (ok && mounted) await _agir(() => widget.servico.pularVisita(s.id, v.id));
  }

  Future<void> _proporReajuste(Recorrencia s) async {
    final centavos = await showDialog<int>(
      context: context,
      builder: (_) => _DialogoNovoValor(valorAtualCentavos: s.valorCentavos),
    );
    if (centavos != null && mounted) {
      await _agir(() => widget.servico.proporReajuste(s.id, centavos));
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = _serie;
    if (s != null) {
      return _Conteudo(
        aoAtualizar: _carregar,
        serie: s,
        ocupado: _ocupado,
        erroAcao: _erroAcao,
        aoAceitar: () => _agir(() => widget.servico.aceitar(s.id)),
        aoRecusar: () => _agir(() => widget.servico.recusar(s.id)),
        aoCancelarSerie: () => _cancelarSerie(s),
        aoPausar: () => _agir(() => widget.servico.pausar(s.id)),
        aoRetomar: () => _agir(() => widget.servico.retomar(s.id)),
        aoPularProxima: () => _pularProxima(s),
        aoPularVisita: (v) => _pularVisita(s, v),
        aoProporReajuste: () => _proporReajuste(s),
        aoAceitarReajuste: () => _agir(
          () => widget.servico.aceitarReajuste(s.id, s.valorPropostoCentavos ?? 0),
          recarregarSe409: true,
        ),
        aoRecusarReajuste: () => _agir(() => widget.servico.recusarReajuste(s.id)),
        aoAbrirPedido: widget.aoAbrirPedido == null
            ? null
            : (pedidoId) => widget.aoAbrirPedido!(pedidoId, s.souCliente),
      );
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Serviço recorrente')),
      body: SafeArea(
        child: _erroCarga == null
            ? const EstadoCarregando()
            : EstadoErro(
                mensagem: _erroCarga is ErroTrato
                    ? (_erroCarga! as ErroTrato).mensagem
                    : 'Não foi possível carregar agora. Confira sua conexão e tente de novo.',
                aoTentarNovamente: _carregar,
              ),
      ),
    );
  }
}

class _Conteudo extends StatelessWidget {
  const _Conteudo({
    required this.aoAtualizar,
    required this.serie,
    required this.ocupado,
    required this.erroAcao,
    required this.aoAceitar,
    required this.aoRecusar,
    required this.aoCancelarSerie,
    required this.aoPausar,
    required this.aoRetomar,
    required this.aoPularProxima,
    required this.aoPularVisita,
    required this.aoProporReajuste,
    required this.aoAceitarReajuste,
    required this.aoRecusarReajuste,
    required this.aoAbrirPedido,
  });

  final Future<void> Function() aoAtualizar;
  final Recorrencia serie;
  final bool ocupado;
  final String? erroAcao;
  final VoidCallback aoAceitar;
  final VoidCallback aoRecusar;
  final VoidCallback aoCancelarSerie;
  final VoidCallback aoPausar;
  final VoidCallback aoRetomar;
  final VoidCallback aoPularProxima;
  final void Function(VisitaRecorrente) aoPularVisita;
  final VoidCallback aoProporReajuste;
  final VoidCallback aoAceitarReajuste;
  final VoidCallback aoRecusarReajuste;
  final void Function(String pedidoId)? aoAbrirPedido;

  @override
  Widget build(BuildContext context) {
    final c = context.cores;
    final s = serie;
    final nome = (s.outraParteNome ?? '').trim().isEmpty ? 'a outra pessoa' : s.outraParteNome!;
    final podeAgir = s.ativa || s.pausada;
    return EstruturaPedido(
      tituloBarra: 'Serviço recorrente',
      aoAtualizar: aoAtualizar,
      children: [
        Text(nome == 'a outra pessoa' ? 'Serviço recorrente' : nome,
            style: TipografiaTrato.tituloGrande),
        const SizedBox(height: EspacosTrato.x1),
        Text(
          s.textoStatus,
          key: const ValueKey('status-detalhe'),
          style: TipografiaTrato.corpoForte
              .copyWith(color: s.cancelada ? c.textoSecundario : c.azulTexto),
        ),
        const SizedBox(height: EspacosTrato.x2),
        Text(
          '${s.textoFrequencia} · ${Dinheiro.formatar(s.valorCentavos)} por visita',
          key: const ValueKey('resumo-serie'),
          style: TipografiaTrato.corpo,
        ),
        if (!s.cancelada)
          Text(
            'Próxima visita: ${dataHoraBrasilia(s.proximaVisita)} (Brasília)',
            key: const ValueKey('proxima-visita'),
            style: TipografiaTrato.corpoPequeno.copyWith(color: c.textoSecundario),
          ),
        if (erroAcao != null) ...[
          const SizedBox(height: EspacosTrato.x3),
          Semantics(
            liveRegion: true,
            child: Text(
              erroAcao!,
              key: const ValueKey('erro-recorrencia'),
              style: TipografiaTrato.corpoPequeno.copyWith(color: c.vermelhoTexto),
            ),
          ),
        ],
        if (s.proposta) ...[
          const SizedBox(height: EspacosTrato.x4),
          _LarguraToda(
              child: CartaoTrato(
            key: const ValueKey('cartao-proposta'),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  s.propostoPorMim
                      ? 'Aguardando resposta de $nome'
                      : 'Proposta de serviço recorrente',
                  style: TipografiaTrato.corpoForte,
                ),
                const SizedBox(height: EspacosTrato.x1),
                Text(
                  s.propostoPorMim
                      ? 'Você propôs repetir este serviço. Se mudar de ideia, cancele a proposta.'
                      : '$nome propôs repetir este serviço: ${s.textoFrequencia.toLowerCase()}, '
                          '${Dinheiro.formatar(s.valorCentavos)} por visita, a partir de '
                          '${dataHoraBrasilia(s.proximaVisita)}.',
                  style: TipografiaTrato.corpo,
                ),
                const SizedBox(height: EspacosTrato.x3),
                if (s.propostoPorMim)
                  BotaoSecundario(
                    key: const ValueKey('cancelar-proposta-serie'),
                    texto: 'Cancelar proposta',
                    aoTocar: ocupado ? null : aoCancelarSerie,
                  )
                else ...[
                  BotaoPrimario(
                    key: const ValueKey('aceitar-serie'),
                    texto: 'Aceitar',
                    carregando: ocupado,
                    aoTocar: ocupado ? null : aoAceitar,
                  ),
                  const SizedBox(height: EspacosTrato.x2),
                  BotaoSecundario(
                    key: const ValueKey('recusar-serie'),
                    texto: 'Recusar',
                    aoTocar: ocupado ? null : aoRecusar,
                  ),
                ],
              ],
            ),
          )),
        ],
        if (podeAgir && s.temReajustePendente) ...[
          const SizedBox(height: EspacosTrato.x4),
          _LarguraToda(
              child: CartaoTrato(
            key: const ValueKey('cartao-reajuste'),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  s.souCliente ? 'Novo valor proposto' : 'Novo valor aguardando o cliente',
                  style: TipografiaTrato.corpoForte,
                ),
                const SizedBox(height: EspacosTrato.x1),
                Text(
                  s.souCliente
                      ? '$nome propôs ${Dinheiro.formatar(s.valorPropostoCentavos!)} por visita '
                          '(hoje ${Dinheiro.formatar(s.valorCentavos)}). Só vale se você aceitar, '
                          'a partir das próximas visitas.'
                      : 'Você propôs ${Dinheiro.formatar(s.valorPropostoCentavos!)} por visita. '
                          'Só vale se o cliente aceitar.',
                  style: TipografiaTrato.corpo,
                ),
                if (s.souCliente) ...[
                  const SizedBox(height: EspacosTrato.x3),
                  BotaoPrimario(
                    key: const ValueKey('aceitar-reajuste'),
                    texto: 'Aceitar novo valor',
                    carregando: ocupado,
                    aoTocar: ocupado ? null : aoAceitarReajuste,
                  ),
                  const SizedBox(height: EspacosTrato.x2),
                  BotaoSecundario(
                    key: const ValueKey('recusar-reajuste'),
                    texto: 'Recusar',
                    aoTocar: ocupado ? null : aoRecusarReajuste,
                  ),
                ],
              ],
            ),
          )),
        ],
        if (podeAgir) ...[
          const SizedBox(height: EspacosTrato.x4),
          _LarguraToda(
            child: Card(
              key: const ValueKey('acoes-serie'),
              margin: EdgeInsets.zero,
              clipBehavior: Clip.antiAlias,
              child: Column(
                children: [
                  if (s.ativa)
                    _Acao(
                      chave: const ValueKey('pausar-serie'),
                      icone: Icons.pause_circle_outline,
                      texto: 'Pausar série',
                      aoTocar: ocupado ? null : aoPausar,
                    ),
                  if (s.pausada)
                    _Acao(
                      chave: const ValueKey('retomar-serie'),
                      icone: Icons.play_circle_outline,
                      texto: 'Retomar série',
                      aoTocar: ocupado ? null : aoRetomar,
                    ),
                  if (s.ativa)
                    _Acao(
                      chave: const ValueKey('pular-proxima'),
                      icone: Icons.skip_next_outlined,
                      texto: 'Pular próxima visita',
                      aoTocar: ocupado ? null : aoPularProxima,
                    ),
                  if (!s.souCliente && !s.temReajustePendente)
                    _Acao(
                      chave: const ValueKey('propor-reajuste'),
                      icone: Icons.payments_outlined,
                      texto: 'Propor novo valor',
                      aoTocar: ocupado ? null : aoProporReajuste,
                    ),
                  Divider(height: 1, color: c.borda),
                  _Acao(
                    chave: const ValueKey('cancelar-serie'),
                    icone: Icons.cancel_outlined,
                    texto: 'Cancelar série',
                    cor: c.vermelhoTexto,
                    aoTocar: ocupado ? null : aoCancelarSerie,
                  ),
                ],
              ),
            ),
          ),
        ],
        const TituloSecao('Visitas'),
        if (s.visitas.isEmpty)
          Text(
            s.proposta
                ? 'As visitas aparecem depois que a proposta for aceita.'
                : 'Ainda não há visitas geradas.',
            key: const ValueKey('visitas-vazio'),
            style: TipografiaTrato.corpo.copyWith(color: c.textoSecundario),
          )
        else
          for (final v in s.visitas)
            Padding(
              padding: const EdgeInsets.only(bottom: EspacosTrato.x3),
              child: _LarguraToda(
                  child: CartaoTrato(
                key: ValueKey('visita-${v.id}'),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(dataHoraBrasilia(v.dataPrevista), style: TipografiaTrato.corpoForte),
                    Text(
                      v.textoStatus,
                      style: TipografiaTrato.corpoPequeno.copyWith(color: c.textoSecundario),
                    ),
                    if ((v.pedidoId != null && aoAbrirPedido != null) || (v.agendada && podeAgir))
                      Wrap(
                        spacing: EspacosTrato.x3,
                        children: [
                          if (v.pedidoId != null && aoAbrirPedido != null)
                            BotaoLink(
                              key: ValueKey('abrir-pedido-${v.id}'),
                              texto: 'Abrir pedido',
                              aoTocar: () => aoAbrirPedido!(v.pedidoId!),
                            ),
                          if (v.agendada && podeAgir)
                            BotaoLink(
                              key: ValueKey('pular-${v.id}'),
                              texto: 'Pular visita',
                              aoTocar: ocupado ? null : () => aoPularVisita(v),
                            ),
                        ],
                      ),
                  ],
                ),
              )),
            ),
      ],
    );
  }
}

/// Cartões do detalhe ocupam a largura toda (sem isso encolhem até o texto).
class _LarguraToda extends StatelessWidget {
  const _LarguraToda({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => SizedBox(width: double.infinity, child: child);
}

/// Linha de ação da série: ícone e texto alinhados à esquerda.
class _Acao extends StatelessWidget {
  const _Acao({
    required this.chave,
    required this.icone,
    required this.texto,
    required this.aoTocar,
    this.cor,
  });

  final Key chave;
  final IconData icone;
  final String texto;
  final VoidCallback? aoTocar;
  final Color? cor;

  @override
  Widget build(BuildContext context) {
    final tom = cor ?? context.cores.petroleo;
    return ListTile(
      key: chave,
      enabled: aoTocar != null,
      leading: Icon(icone, color: tom),
      title: Text(texto, style: TipografiaTrato.corpoForte.copyWith(color: tom)),
      onTap: aoTocar,
    );
  }
}

/// Valor novo por visita, em reais com vírgula; devolve centavos.
class _DialogoNovoValor extends StatefulWidget {
  const _DialogoNovoValor({required this.valorAtualCentavos});

  final int valorAtualCentavos;

  @override
  State<_DialogoNovoValor> createState() => _DialogoNovoValorState();
}

class _DialogoNovoValorState extends State<_DialogoNovoValor> {
  final _campo = TextEditingController();
  String? _erro;

  @override
  void dispose() {
    _campo.dispose();
    super.dispose();
  }

  void _enviar() {
    final centavos = Dinheiro.lerCentavos(_campo.text);
    if (centavos == null || centavos <= 0) {
      setState(() => _erro = 'Informe um valor válido por visita.');
      return;
    }
    Navigator.of(context).pop(centavos);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Propor novo valor'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Valor atual: ${Dinheiro.formatar(widget.valorAtualCentavos)} por visita. '
              'O novo valor só vale se o cliente aceitar.'),
          const SizedBox(height: EspacosTrato.x3),
          TextField(
            key: const ValueKey('novo-valor'),
            controller: _campo,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
            decoration: InputDecoration(
                labelText: 'Novo valor por visita', prefixText: 'R\$ ', errorText: _erro),
            onChanged: (_) {
              if (_erro != null) setState(() => _erro = null);
            },
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Voltar')),
        FilledButton(
          key: const ValueKey('enviar-novo-valor'),
          onPressed: _enviar,
          child: const Text('Enviar proposta'),
        ),
      ],
    );
  }
}
