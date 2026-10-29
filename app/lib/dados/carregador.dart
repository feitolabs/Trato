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
    this.vazio,
    this.tituloVazio = 'Nada por aqui ainda',
    this.textoVazio = '',
  });

  final Future<T> Function() carregar;
  final Widget Function(BuildContext context, T dado) construir;

  /// Diz se o dado conta como "vazio". Sem isso, nunca mostra o estado vazio.
  final bool Function(T dado)? vazio;
  final String tituloVazio;
  final String textoVazio;

  @override
  State<Carregador<T>> createState() => _CarregadorState<T>();
}

class _CarregadorState<T> extends State<Carregador<T>> {
  late Future<T> _futuro = widget.carregar();

  void _recarregar() {
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
    this.titulo,
    this.texto,
    this.aoTentarNovamente,
  });

  final bool carregando;
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
                      ? Semantics(
                          label: 'Carregando',
                          child: const CircularProgressIndicator(color: CoresTrato.petroleo),
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
