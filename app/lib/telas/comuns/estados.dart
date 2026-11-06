import 'package:flutter/material.dart';

import '../../componentes/componentes.dart';
import '../../tema/tema.dart';

/// Carrega dados de um serviço e mostra carregando, erro (com "Tentar de novo") ou o conteúdo.
/// Quem decide o que é "vazio" é o [construir] (use [EstadoVazio]).
class CarregadorTela<T> extends StatefulWidget {
  const CarregadorTela({
    super.key,
    required this.carregar,
    required this.construir,
    this.esqueleto,
    this.atualizarQuando,
  });

  final Future<T> Function() carregar;
  final Widget Function(BuildContext context, T dados, VoidCallback recarregar) construir;
  final Widget Function(BuildContext context)? esqueleto;

  /// Quando este aviso dispara, recarrega do servidor.
  final Listenable? atualizarQuando;

  @override
  State<CarregadorTela<T>> createState() => _CarregadorTelaState<T>();
}

class _CarregadorTelaState<T> extends State<CarregadorTela<T>> {
  late Future<T> _futuro = widget.carregar();

  @override
  void initState() {
    super.initState();
    widget.atualizarQuando?.addListener(_recarregar);
  }

  @override
  void dispose() {
    widget.atualizarQuando?.removeListener(_recarregar);
    super.dispose();
  }

  void _recarregar() {
    if (!mounted) return;
    // Bloco, não seta: o setState do Flutter recusa callback que devolve Future (lança no debug).
    setState(() {
      _futuro = widget.carregar();
    });
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<T>(
      future: _futuro,
      builder: (context, snap) {
        if (snap.hasError) return EstadoErro(aoTentarNovamente: _recarregar);
        if (!snap.hasData) {
          if (widget.esqueleto != null) return widget.esqueleto!(context);
          return const EstadoCarregando();
        }
        return widget.construir(context, snap.data as T, _recarregar);
      },
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
