import 'package:flutter/material.dart';

import '../componentes/componentes.dart';
import '../tema/tema.dart';
import 'erros.dart';

/// Carrega algo e mostra os estados que toda tela ligada precisa ter: carregando, erro
/// (com "Tentar de novo") e vazio. Pronto, entrega o dado a [construir].
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
  });

  final Future<T> Function() carregar;

  /// Quando este aviso dispara, recarrega do servidor (ex.: depois de criar um pedido).
  final Listenable? atualizarQuando;
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
  late Future<T> _futuro = widget.carregar();

  @override
  void initState() {
    super.initState();
    widget.atualizarQuando?.addListener(_recarregar);
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
    widget.atualizarQuando?.removeListener(_recarregar);
    super.dispose();
  }

  void _recarregar() {
    if (!mounted) return;
    setState(() {
      _futuro = widget.carregar();
    });
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<T>(
      future: _futuro,
      builder: (context, foto) {
        if (foto.connectionState != ConnectionState.done) {
          if (widget.esqueleto != null) {
            return widget.esqueleto!(context);
          }
          return const EstadoTela(carregando: true);
        }
        if (foto.hasError) {
          final erro = foto.error;
          return EstadoTela(
            titulo: 'Não deu certo',
            texto:
                erro is ErroTrato ? erro.mensagem : 'Algo deu errado. Tente de novo em instantes.',
            aoTentarNovamente: _recarregar,
          );
        }
        final dado = foto.data as T;
        if (widget.vazio?.call(dado) ?? false) {
          return EstadoTela(titulo: widget.tituloVazio, texto: widget.textoVazio);
        }
        return widget.construir(context, dado);
      },
    );
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
