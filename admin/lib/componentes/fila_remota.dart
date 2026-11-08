import 'dart:async';

import 'package:flutter/material.dart';

import '../dados/modelos.dart';
import '../tema/tema.dart';
import 'atualizacao.dart';
import 'botoes.dart';
import 'feedback.dart';

/// O que a tela recebe da [FilaRemota] para montar a lista.
class EstadoFila<T> {
  const EstadoFila({
    required this.itens,
    required this.total,
    required this.carregandoMais,
    required this.carregarMais,
    required this.recarregar,
  });

  /// Itens já trazidos do servidor, na ordem dele.
  final List<T> itens;

  /// Quantos existem no servidor com o filtro atual (não só os trazidos).
  final int total;
  final bool carregandoMais;
  final Future<void> Function() carregarMais;

  /// Busca de novo tudo o que já está na tela, sem esqueleto e sem perder seleção.
  final Future<void> Function() recarregar;

  bool get temMais => itens.length < total;
}

/// Fila paginada no servidor: traz [porPagina] itens por vez, mostra o total de verdade e se
/// atualiza sozinha (ver [AtualizaSozinho]). Quando [filtro] muda, recomeça do zero.
///
/// O backend aceita no máximo 100 por chamada; para reatualizar mais que isso, a fila busca em
/// várias páginas.
class FilaRemota<T> extends StatefulWidget {
  const FilaRemota({
    super.key,
    required this.carregar,
    required this.chave,
    required this.construir,
    this.filtro,
    this.porPagina = 50,
    this.esqueleto,
    this.aoAtualizar,
  });

  final Future<PaginaRemota<T>> Function(int deslocamento, int limite) carregar;
  final Object Function(T item) chave;
  final Widget Function(BuildContext context, EstadoFila<T> fila) construir;
  final Object? filtro;
  final int porPagina;
  final Widget? esqueleto;

  /// Chamado a cada atualização (automática ou depois de uma ação), para a tela atualizar o que
  /// está fora da lista, como os contadores dos filtros.
  final Future<void> Function()? aoAtualizar;

  @override
  State<FilaRemota<T>> createState() => _FilaRemotaState<T>();
}

const _kMaximoPorChamada = 100;

class _FilaRemotaState<T> extends State<FilaRemota<T>> with AtualizaSozinho {
  List<T> _itens = const [];
  int _total = 0;
  bool _carregou = false;
  bool _carregandoMais = false;
  Object? _erro;
  int _geracao = 0;

  bool _iniciou = false;

  /// A primeira carga sai daqui, não do initState: quem carrega lê `context.api`.
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_iniciou) return;
    _iniciou = true;
    _recomecar();
  }

  @override
  void didUpdateWidget(covariant FilaRemota<T> antigo) {
    super.didUpdateWidget(antigo);
    // Filtro novo: lista nova (o build seguinte já mostra o esqueleto).
    if (antigo.filtro != widget.filtro) _recomecar();
  }

  /// Traz os primeiros [quantos] itens, em páginas de no máximo 100.
  Future<PaginaRemota<T>> _buscarAte(int quantos) async {
    final itens = <T>[];
    var total = 0;
    do {
      final falta = quantos - itens.length;
      final limite = falta < _kMaximoPorChamada ? falta : _kMaximoPorChamada;
      final p = await widget.carregar(itens.length, limite);
      total = p.total;
      itens.addAll(p.itens);
      if (p.itens.isEmpty) break;
    } while (itens.length < quantos && itens.length < total);
    return PaginaRemota(itens, total);
  }

  /// Chamado no initState e no didUpdateWidget: muda o estado sem setState (o build já vem).
  Future<void> _recomecar() async {
    final geracao = ++_geracao;
    _carregou = false;
    _erro = null;
    try {
      final p = await _buscarAte(widget.porPagina);
      if (!mounted || geracao != _geracao) return;
      setState(() {
        _itens = p.itens;
        _total = p.total;
        _carregou = true;
      });
    } catch (e) {
      if (!mounted || geracao != _geracao) return;
      setState(() => _erro = e);
    }
  }

  /// Atualiza o que está na tela (mesma quantidade de itens), sem esqueleto.
  Future<void> _recarregar() async {
    if (!_carregou) return _recomecar();
    final geracao = ++_geracao;
    final quantos = _itens.length < widget.porPagina ? widget.porPagina : _itens.length;
    final contadores = widget.aoAtualizar?.call();
    final p = await _buscarAte(quantos);
    await contadores;
    if (!mounted || geracao != _geracao) return;
    setState(() {
      _itens = p.itens;
      _total = p.total;
    });
  }

  Future<void> _carregarMais() async {
    if (_carregandoMais || _itens.length >= _total) return;
    final geracao = _geracao;
    setState(() => _carregandoMais = true);
    try {
      final p = await widget.carregar(_itens.length, widget.porPagina);
      if (!mounted || geracao != _geracao) return;
      // A fila pode ter andado entre uma página e outra: não repete item.
      final vistos = {for (final i in _itens) widget.chave(i)};
      setState(() {
        _itens = [..._itens, ...p.itens.where((i) => !vistos.contains(widget.chave(i)))];
        _total = p.total;
      });
    } catch (e) {
      if (mounted) mostrarErro(context, e);
    } finally {
      if (mounted) setState(() => _carregandoMais = false);
    }
  }

  @override
  Future<void> atualizarEmSilencio() => _recarregar();

  @override
  Widget build(BuildContext context) {
    if (_erro case final erro?) {
      return EstadoErro(erro.toString(), aoTentar: () => setState(() => unawaited(_recomecar())));
    }
    if (!_carregou) return widget.esqueleto ?? const EsqueletoLista();
    return widget.construir(
      context,
      EstadoFila(
        itens: _itens,
        total: _total,
        carregandoMais: _carregandoMais,
        carregarMais: _carregarMais,
        recarregar: _recarregar,
      ),
    );
  }
}

/// Rodapé da fila: "Mostrando 50 de 131" e o botão para trazer mais.
class RodapeFila extends StatelessWidget {
  const RodapeFila(this.fila, {super.key, this.rotuloItens = 'itens'});

  final EstadoFila<Object?> fila;
  final String rotuloItens;

  @override
  Widget build(BuildContext context) {
    final n = fila.itens.length;
    return Padding(
      padding: const EdgeInsets.only(top: EspacosTrato.x2),
      child: Column(
        children: [
          Text(
            fila.temMais ? 'Mostrando $n de ${fila.total} $rotuloItens' : 'Todos os ${fila.total} $rotuloItens',
            style: TipografiaTrato.legenda,
            textAlign: TextAlign.center,
          ),
          if (fila.temMais) ...[
            const SizedBox(height: EspacosTrato.x2),
            BotaoTrato.secundario(
              'Carregar mais',
              aoPressionar: fila.carregandoMais ? null : fila.carregarMais,
              carregando: fila.carregandoMais,
              rotuloCarregando: 'Carregando',
            ),
          ],
        ],
      ),
    );
  }
}
