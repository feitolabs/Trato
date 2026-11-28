import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../componentes/base.dart';
import '../dados/modelos.dart';
import '../nucleo/escopo.dart';
import '../nucleo/formato.dart';
import '../nucleo/papeis.dart';
import '../tema/tema.dart';

const kPeriodosFaltasRepetidas = [30, 90, 180];
const kMinimosFaltasRepetidas = [2, 3, 5];

const kAvisoFaltasRepetidas =
    'Indicador operacional de profissionais com faltas ou cancelamentos repetidos no período '
    '(Termos 7.7). Nenhuma medida punitiva é aplicada automaticamente por esta tela: use Busca e '
    'suporte ou Medidas de conta para analisar o histórico completo.';

/// Lista de profissionais com faltas/cancelamentos repetidos (Termos 7.7). Pede `disputas_ver`.
class FaltasRepetidasTela extends StatefulWidget {
  const FaltasRepetidasTela({super.key});

  @override
  State<FaltasRepetidasTela> createState() => _FaltasRepetidasTelaState();
}

class _FaltasRepetidasTelaState extends State<FaltasRepetidasTela> {
  int _dias = 90;
  int _minimo = 2;
  List<FaltaRepetidaProfissional>? _itens;
  String? _erro;
  bool _carregando = true;
  bool _iniciou = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_iniciou) return;
    _iniciou = true;
    _carregar();
  }

  Future<void> _carregar() async {
    setState(() {
      _carregando = true;
      _erro = null;
    });
    try {
      final lista = await context.api.listarFaltasRepetidas(dias: _dias, minimo: _minimo);
      if (!mounted) return;
      setState(() {
        _itens = lista;
        _carregando = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _erro = e is ErroApi ? e.mensagem : e.toString();
        _carregando = false;
      });
    }
  }

  void _mudarDias(int dias) {
    if (_dias == dias) return;
    setState(() => _dias = dias);
    _carregar();
  }

  void _mudarMinimo(int minimo) {
    if (_minimo == minimo) return;
    setState(() => _minimo = minimo);
    _carregar();
  }

  Future<void> _copiarId(String profissionalId) async {
    await Clipboard.setData(ClipboardData(text: profissionalId));
    if (!mounted) return;
    mostrarAviso(context, 'ID copiado. Cole em Busca e suporte para abrir o profissional.');
  }

  @override
  Widget build(BuildContext context) {
    final margem = Responsivo.margemLateral(FaixaPainel.de(context));
    final podeBuscarUsuario = context.pode(Permissao.usuariosBuscar);
    final itens = _itens ?? const <FaltaRepetidaProfissional>[];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const CabecalhoPagina(
          'Faltas repetidas',
          subtitulo: 'Profissionais com faltas ou cancelamentos repetidos para análise operacional (Termos 7.7)',
        ),
        Expanded(
          child: ListView(
            padding: EdgeInsets.fromLTRB(margem, EspacosTrato.x2, margem, EspacosTrato.x6),
            children: [
              const BannerInfo(kAvisoFaltasRepetidas, tom: Tom.info),
              const SizedBox(height: EspacosTrato.x3),
              Text('Período', style: TipografiaTrato.etiqueta),
              const SizedBox(height: EspacosTrato.x2),
              Wrap(
                spacing: EspacosTrato.x2,
                runSpacing: EspacosTrato.x2,
                children: [
                  for (final d in kPeriodosFaltasRepetidas)
                    ChoiceChip(
                      label: Text('Últimos $d dias'),
                      selected: _dias == d,
                      onSelected: (_) => _mudarDias(d),
                      materialTapTargetSize: MaterialTapTargetSize.padded,
                    ),
                ],
              ),
              const SizedBox(height: EspacosTrato.x3),
              Text('Mínimo de cancelamentos', style: TipografiaTrato.etiqueta),
              const SizedBox(height: EspacosTrato.x2),
              Wrap(
                spacing: EspacosTrato.x2,
                runSpacing: EspacosTrato.x2,
                children: [
                  for (final m in kMinimosFaltasRepetidas)
                    ChoiceChip(
                      label: Text('$m ou mais'),
                      selected: _minimo == m,
                      onSelected: (_) => _mudarMinimo(m),
                      materialTapTargetSize: MaterialTapTargetSize.padded,
                    ),
                ],
              ),
              const SizedBox(height: EspacosTrato.x4),
              if (_carregando)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: EspacosTrato.x5),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (_erro != null) ...[
                BannerInfo(_erro!, titulo: 'Não foi possível carregar a lista.', tom: Tom.erro),
                const SizedBox(height: EspacosTrato.x2),
                Align(
                  alignment: Alignment.centerLeft,
                  child: BotaoTrato.secundario('Tentar novamente', aoPressionar: _carregar),
                ),
              ] else if (itens.isEmpty)
                const EstadoVazio('Nenhum profissional com faltas repetidas nesse filtro.')
              else
                for (final item in itens)
                  Padding(
                    padding: const EdgeInsets.only(bottom: EspacosTrato.intervaloCartoes),
                    child: _CartaoFaltaRepetida(
                      item,
                      podeCopiarParaBusca: podeBuscarUsuario,
                      aoCopiarId: () => _copiarId(item.profissionalId),
                    ),
                  ),
            ],
          ),
        ),
      ],
    );
  }
}

class _CartaoFaltaRepetida extends StatelessWidget {
  const _CartaoFaltaRepetida(
    this.item, {
    required this.podeCopiarParaBusca,
    required this.aoCopiarId,
  });

  final FaltaRepetidaProfissional item;
  final bool podeCopiarParaBusca;
  final VoidCallback aoCopiarId;

  @override
  Widget build(BuildContext context) {
    final tom = item.totalCancelamentos >= 5 ? Tom.erro : Tom.alerta;
    return CartaoSecao(
      titulo: 'Profissional ${item.profissionalId}',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: ChipEstado('${item.totalCancelamentos} cancelamento(s)', tom: tom),
          ),
          const SizedBox(height: EspacosTrato.x2),
          Linha('Profissional', item.profissionalId),
          Linha('Total de cancelamentos', '${item.totalCancelamentos}'),
          Linha('Último cancelamento', formatarDataBrasilia(item.ultimoCancelamentoEm)),
          Linha('Período analisado', 'Últimos ${item.periodoDias} dias'),
          if (podeCopiarParaBusca) ...[
            const SizedBox(height: EspacosTrato.x2),
            Align(
              alignment: Alignment.centerRight,
              child: BotaoTrato.secundario('Copiar ID para Busca', aoPressionar: aoCopiarId),
            ),
          ],
        ],
      ),
    );
  }
}
