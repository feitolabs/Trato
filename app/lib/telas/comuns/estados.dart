import 'package:flutter/material.dart';

import '../../componentes/componentes.dart';
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
      if (widget.esqueleto != null) return widget.esqueleto!(context);
      return const EstadoCarregando();
    }
    if (_erro != null) return EstadoErro(aoTentarNovamente: _recarregar);
    return widget.construir(context, _dado as T, _recarregar);
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
  const EstadoVazio({super.key, required this.icone, required this.titulo, required this.texto});

  final IconData icone;
  final String titulo;
  final String texto;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(EspacosTrato.x6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icone, size: 48, color: CoresTrato.petroleo),
            const SizedBox(height: EspacosTrato.x4),
            Text(titulo, textAlign: TextAlign.center, style: TipografiaTrato.titulo),
            const SizedBox(height: EspacosTrato.x2),
            Text(
              texto,
              textAlign: TextAlign.center,
              style: TipografiaTrato.corpo.copyWith(color: CoresTrato.textoSecundario),
            ),
          ],
        ),
      ),
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
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(EspacosTrato.x6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 48, color: CoresTrato.vermelhoTexto),
            const SizedBox(height: EspacosTrato.x4),
            Text(mensagem, textAlign: TextAlign.center, style: TipografiaTrato.corpo),
            const SizedBox(height: EspacosTrato.x5),
            BotaoSecundario(texto: 'Tentar de novo', aoTocar: aoTentarNovamente),
          ],
        ),
      ),
    );
  }
}

/// Moldura padrão das telas comuns: título grande no topo e o corpo abaixo.
class MolduraTelaComum extends StatelessWidget {
  const MolduraTelaComum({super.key, required this.titulo, required this.child, this.comVoltar = true});

  final String titulo;
  final Widget child;
  final bool comVoltar;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: comVoltar ? AppBar() : null,
      body: SafeArea(
        child: ConteudoResponsivo(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: EspacosTrato.x4),
              Text(titulo, style: TipografiaTrato.tituloGrande),
              const SizedBox(height: EspacosTrato.x4),
              Expanded(child: child),
            ],
          ),
        ),
      ),
    );
  }
}
