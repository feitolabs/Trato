import 'package:flutter/material.dart';

import '../../componentes/componentes.dart';
import '../../dados/carregador.dart';
import '../../dados/erros.dart';
import '../../dados/relogio_de_atualizacao.dart';
import '../../tema/tema.dart';

/// Carrega dados de um serviço e mostra carregando, erro (com "Tentar de novo") ou o conteúdo.
/// Quem decide o que é "vazio" é o [construir] (use [EstadoVazio]).
///
/// Com [atualizarACada], a lista se atualiza sozinha (e quando o app volta do segundo plano),
/// em silêncio: sem spinner e mantendo o que já está na tela se a rede falhar.
class CarregadorTela<T> extends StatefulWidget {
  const CarregadorTela({
    super.key,
    required this.carregar,
    required this.construir,
    this.esqueleto,
    this.atualizarQuando,
    this.atualizarACada,
  });

  final Future<T> Function() carregar;
  final Widget Function(BuildContext context, T dados, VoidCallback recarregar) construir;
  final Widget Function(BuildContext context)? esqueleto;

  /// Quando este aviso dispara, recarrega do servidor.
  final Listenable? atualizarQuando;

  /// Atualiza sozinho neste intervalo. Nulo = só carrega uma vez.
  final Duration? atualizarACada;

  @override
  State<CarregadorTela<T>> createState() => _CarregadorTelaState<T>();
}

class _CarregadorTelaState<T> extends State<CarregadorTela<T>> {
  T? _dado;
  Object? _erro;
  var _pronto = false;
  var _emVoo = false;
  var _geracao = 0;
  var _visivel = true;
  RelogioDeAtualizacao? _relogio;

  @override
  void initState() {
    super.initState();
    widget.atualizarQuando?.addListener(_aoDispararAtualizacao);
    final intervalo = widget.atualizarACada;
    if (intervalo != null) {
      _relogio = RelogioDeAtualizacao(
        intervalo: intervalo,
        aoAtualizar: _atualizarEmSilencio,
        deveAtualizar: () =>
            mounted &&
            TickerMode.valuesOf(context).enabled &&
            (ModalRoute.of(context)?.isCurrent ?? true),
      );
    }
    _carregar();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final ativo = TickerMode.valuesOf(context).enabled;
    if (ativo && !_visivel && _pronto) {
      _atualizarEmSilencio();
    }
    _visivel = ativo;
  }

  @override
  void didUpdateWidget(covariant CarregadorTela<T> antigo) {
    super.didUpdateWidget(antigo);
    if (antigo.atualizarQuando != widget.atualizarQuando) {
      antigo.atualizarQuando?.removeListener(_aoDispararAtualizacao);
      widget.atualizarQuando?.addListener(_aoDispararAtualizacao);
    }
  }

  @override
  void dispose() {
    _relogio?.parar();
    widget.atualizarQuando?.removeListener(_aoDispararAtualizacao);
    super.dispose();
  }

  void _aoDispararAtualizacao() {
    if (!mounted || _emVoo) return;
    if (_pronto && _erro == null) {
      _atualizarEmSilencio();
    } else {
      _recarregar();
    }
  }

  Future<void> _carregar() async {
    _emVoo = true;
    final minha = ++_geracao;
    try {
      final dado = await widget.carregar();
      if (!mounted || minha != _geracao) return;
      setState(() {
        _dado = dado;
        _erro = null;
        _pronto = true;
      });
    } on Object catch (erro) {
      if (!mounted || minha != _geracao) return;
      setState(() {
        _erro = erro;
        _pronto = true;
      });
    } finally {
      _emVoo = false;
    }
  }

  void _recarregar() {
    if (!mounted) return;
    // Bloco, não seta: o setState do Flutter recusa callback que devolve Future (lança no debug).
    setState(() {
      _pronto = false;
      _erro = null;
    });
    _carregar();
  }

  /// Busca de novo sem mexer na tela; só troca o dado quando chega. Erro: segue com o que tem.
  Future<void> _atualizarEmSilencio() async {
    if (_emVoo) return;
    if (!_pronto) {
      await _carregar();
      return;
    }
    _emVoo = true;
    final minha = ++_geracao;
    try {
      final dado = await widget.carregar();
      if (!mounted || minha != _geracao) return;
      setState(() {
        _dado = dado;
        _erro = null;
      });
    } on Object catch (erro) {
      if (_dado == null && _erro != null && mounted && minha == _geracao) {
        setState(() => _erro = erro);
      }
    } finally {
      _emVoo = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_pronto) {
      if (widget.esqueleto != null) return widget.esqueleto!(context);
      return const EstadoCarregando();
    }
    if (_erro != null) {
      return RefreshIndicator(
        onRefresh: _atualizarEmSilencio,
        child: EstadoErro(
          mensagem: mensagemErroTrato(_erro!),
          aoTentarNovamente: _recarregar,
        ),
      );
    }
    return AtualizadorTela(
      recarregar: _atualizarEmSilencio,
      child: widget.construir(context, _dado as T, _recarregar),
    );
  }
}

class EstadoCarregando extends StatelessWidget {
  const EstadoCarregando({super.key, this.esqueleto});

  final Widget? esqueleto;

  @override
  Widget build(BuildContext context) {
    if (esqueleto != null) return esqueleto!;
    // Esqueleto em vez de spinner: a tela parece pronta mais cedo (cartões no lugar).
    return Semantics(
      label: 'Carregando',
      child: const Align(alignment: Alignment.topCenter, child: EsqueletoLista()),
    );
  }
}

class EstadoVazio extends StatelessWidget {
  const EstadoVazio({
    super.key,
    required this.icone,
    required this.titulo,
    required this.texto,
    this.textoAcao,
    this.aoAcao,
  });

  final IconData icone;
  final String titulo;
  final String texto;

  /// Ação opcional (botão) abaixo do texto; só aparece com [textoAcao] e [aoAcao].
  final String? textoAcao;
  final VoidCallback? aoAcao;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, limites) {
        final alturaMinima = limites.hasBoundedHeight
            ? (limites.maxHeight - EspacosTrato.x6 * 2).clamp(0.0, double.infinity)
            : 0.0;
        return SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(EspacosTrato.x6),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: alturaMinima),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icone, size: 48, color: context.cores.petroleo),
                  const SizedBox(height: EspacosTrato.x4),
                  Text(
                    titulo,
                    textAlign: TextAlign.center,
                    style: TipografiaTrato.titulo.copyWith(color: context.cores.texto),
                  ),
                  const SizedBox(height: EspacosTrato.x2),
                  Text(
                    texto,
                    textAlign: TextAlign.center,
                    style: TipografiaTrato.corpo.copyWith(color: context.cores.textoSecundario),
                  ),
                  if (textoAcao != null && aoAcao != null) ...[
                    const SizedBox(height: EspacosTrato.x4),
                    BotaoSecundario(texto: textoAcao!, aoTocar: aoAcao!),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class EstadoErro extends StatelessWidget {
  const EstadoErro({
    super.key,
    this.mensagem = 'Não foi possível carregar agora. Confira sua conexão e tente de novo.',
    this.aoTentarNovamente,
  });

  final String mensagem;
  final VoidCallback? aoTentarNovamente;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, limites) {
        final alturaMinima = limites.hasBoundedHeight
            ? (limites.maxHeight - EspacosTrato.x6 * 2).clamp(0.0, double.infinity)
            : 0.0;
        return SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(EspacosTrato.x6),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: alturaMinima),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.error_outline, size: 48, color: context.cores.vermelhoTexto),
                  const SizedBox(height: EspacosTrato.x4),
                  Text(
                    mensagem,
                    textAlign: TextAlign.center,
                    style: TipografiaTrato.corpo.copyWith(color: context.cores.texto),
                  ),
                  const SizedBox(height: EspacosTrato.x5),
                  BotaoSecundario(texto: 'Tentar de novo', aoTocar: aoTentarNovamente),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Moldura padrão das telas comuns: título grande no topo e o corpo abaixo.
class MolduraTelaComum extends StatelessWidget {
  const MolduraTelaComum({
    super.key,
    required this.titulo,
    required this.child,
    this.comVoltar = true,
    this.acoes = const [],
  });

  final String titulo;
  final Widget child;
  final bool comVoltar;
  final List<Widget> acoes;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: comVoltar ? AppBar(actions: acoes.isEmpty ? null : acoes) : null,
      body: SafeArea(
        bottom: false,
        child: ConteudoResponsivo(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: EspacosTrato.x4),
              if (!comVoltar && acoes.isNotEmpty)
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        titulo,
                        style: TipografiaTrato.tituloGrande.copyWith(color: context.cores.texto),
                      ),
                    ),
                    ...acoes,
                  ],
                )
              else
                Text(
                  titulo,
                  style: TipografiaTrato.tituloGrande.copyWith(color: context.cores.texto),
                ),
              const SizedBox(height: EspacosTrato.x4),
              Expanded(child: child),
            ],
          ),
        ),
      ),
    );
  }
}
