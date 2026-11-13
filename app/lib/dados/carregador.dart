import 'package:flutter/material.dart';

import '../componentes/componentes.dart';
import '../tema/tema.dart';
import 'erros.dart';
import 'relogio_de_atualizacao.dart';

/// Carrega algo e mostra os estados que toda tela ligada precisa ter: carregando, erro
/// (com "Tentar de novo") e vazio. Pronto, entrega o dado a [construir].
///
/// Com [atualizarACada], a tela se atualiza sozinha (e quando o app volta do segundo plano),
/// em silêncio: sem spinner e mantendo o que já está na tela se a rede falhar.
class Carregador<T> extends StatefulWidget {
  const Carregador({
    super.key,
    required this.carregar,
    required this.construir,
    this.esqueleto,
    this.vazio,
    this.tituloVazio = 'Nada por aqui ainda',
    this.textoVazio = '',
    this.atualizarQuando,
    this.atualizarACada,
  });

  final Future<T> Function() carregar;

  /// Quando este aviso dispara, recarrega do servidor (ex.: depois de criar um pedido).
  final Listenable? atualizarQuando;

  /// Atualiza sozinho neste intervalo (ver [RelogioDeAtualizacao.intervaloPadrao]). Nulo = só
  /// carrega uma vez.
  final Duration? atualizarACada;
  final Widget Function(BuildContext context, T dado) construir;

  /// Esqueleto opcional para loading (Skeleton loading).
  final Widget Function(BuildContext context)? esqueleto;

  /// Diz se o dado conta como "vazio". Sem isso, nunca mostra o estado vazio.
  final bool Function(T dado)? vazio;
  final String tituloVazio;
  final String textoVazio;

  @override
  State<Carregador<T>> createState() => _CarregadorState<T>();
}

class _CarregadorState<T> extends State<Carregador<T>> {
  T? _dado;
  Object? _erro;
  var _pronto = false;
  var _geracao = 0;
  RelogioDeAtualizacao? _relogio;

  @override
  void initState() {
    super.initState();
    widget.atualizarQuando?.addListener(_recarregar);
    final intervalo = widget.atualizarACada;
    if (intervalo != null) {
      _relogio = RelogioDeAtualizacao(
        intervalo: intervalo,
        aoAtualizar: _atualizarEmSilencio,
        deveAtualizar: () => mounted && (ModalRoute.of(context)?.isCurrent ?? true),
      );
    }
    _carregar();
  }

  @override
  void didUpdateWidget(covariant Carregador<T> antigo) {
    super.didUpdateWidget(antigo);
    if (antigo.atualizarQuando != widget.atualizarQuando) {
      antigo.atualizarQuando?.removeListener(_recarregar);
      widget.atualizarQuando?.addListener(_recarregar);
    }
  }

  @override
  void dispose() {
    _relogio?.parar();
    widget.atualizarQuando?.removeListener(_recarregar);
    super.dispose();
  }

  Future<void> _carregar() async {
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
    }
  }

  /// Mostra o carregando e busca de novo (depois de uma ação ou do "Tentar de novo").
  void _recarregar() {
    if (!mounted) return;
    setState(() {
      _pronto = false;
      _erro = null;
    });
    _carregar();
  }

  /// Busca de novo sem mexer na tela; só troca o dado quando chega. Erro: segue com o que tem.
  Future<void> _atualizarEmSilencio() async {
    if (!_pronto) return;
    final minha = ++_geracao;
    final dado = await widget.carregar();
    if (!mounted || minha != _geracao) return;
    setState(() {
      _dado = dado;
      _erro = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!_pronto) {
      if (widget.esqueleto != null) {
        return widget.esqueleto!(context);
      }
      return const EstadoTela(carregando: true);
    }
    if (_erro != null) {
      final erro = _erro;
      return EstadoTela(
        titulo: 'Não deu certo',
        texto: erro is ErroTrato ? erro.mensagem : 'Algo deu errado. Tente de novo em instantes.',
        aoTentarNovamente: _recarregar,
      );
    }
    final dado = _dado as T;
    if (widget.vazio?.call(dado) ?? false) {
      return EstadoTela(titulo: widget.tituloVazio, texto: widget.textoVazio);
    }
    return widget.construir(context, dado);
  }
}

/// Tela cheia simples para carregando / erro / vazio, no padrão do design.
class EstadoTela extends StatelessWidget {
  const EstadoTela({
    super.key,
    this.carregando = false,
    this.esqueleto,
    this.titulo,
    this.texto,
    this.aoTentarNovamente,
  });

  final bool carregando;
  final Widget? esqueleto;
  final String? titulo;
  final String? texto;
  final VoidCallback? aoTentarNovamente;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: ConteudoResponsivo(
          child: Column(
            children: [
              if (Navigator.of(context).canPop())
                Align(
                  alignment: Alignment.centerLeft,
                  child: IconButton(
                    tooltip: 'Voltar',
                    icon: const Icon(Icons.arrow_back, color: CoresTrato.petroleo),
                    onPressed: () => Navigator.of(context).maybePop(),
                  ),
                ),
              Expanded(
                child: Center(
                  child: carregando
                      ? esqueleto ??
                          Semantics(
                            label: 'Carregando',
                            child: const Align(
                              alignment: Alignment.topCenter,
                              child: EsqueletoLista(),
                            ),
                          )
                      : Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              titulo ?? '',
                              style: TipografiaTrato.tituloCartao,
                              textAlign: TextAlign.center,
                            ),
                            if ((texto ?? '').isNotEmpty) ...[
                              const SizedBox(height: EspacosTrato.x2),
                              Text(
                                texto!,
                                textAlign: TextAlign.center,
                                style: TipografiaTrato.corpo.copyWith(
                                  color: CoresTrato.textoSecundario,
                                ),
                              ),
                            ],
                            if (aoTentarNovamente != null) ...[
                              const SizedBox(height: EspacosTrato.x4),
                              BotaoSecundario(
                                texto: 'Tentar de novo',
                                aoTocar: aoTentarNovamente,
                              ),
                            ],
                          ],
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
