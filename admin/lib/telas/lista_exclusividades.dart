import 'package:flutter/material.dart';

import '../componentes/base.dart';
import '../dados/modelos.dart';
import '../nucleo/escopo.dart';
import '../nucleo/formato.dart';
import '../tema/tema.dart';

const kStatusExclusividade = {
  'ativa': 'Ativa',
  'concluida': 'Concluída',
  'cancelada': 'Cancelada',
  'expirada_sem_contratacao': 'Expirou sem contratação',
};

String rotuloStatusExclusividade(String s) => kStatusExclusividade[s] ?? s;

/// Exclusividades pagas pelo cliente, com filtros e "Carregar mais", para escolher uma.
class ListaExclusividades extends StatefulWidget {
  const ListaExclusividades({super.key, required this.escolhida, required this.aoEscolher});

  final ExclusividadeCliente? escolhida;
  final ValueChanged<ExclusividadeCliente?>? aoEscolher;

  @override
  State<ListaExclusividades> createState() => _ListaExclusividadesState();
}

class _ListaExclusividadesState extends State<ListaExclusividades> {
  static const _porPagina = 20;

  final _pedido = TextEditingController();
  final _cliente = TextEditingController();
  String? _status;
  List<ExclusividadeCliente> _itens = const [];
  int _total = 0;
  bool _carregando = true;
  String? _erro;
  int _geracao = 0;
  bool _iniciou = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_iniciou) return;
    _iniciou = true;
    _buscar();
  }

  @override
  void dispose() {
    _pedido.dispose();
    _cliente.dispose();
    super.dispose();
  }

  String? _opcional(TextEditingController c) => c.text.trim().isEmpty ? null : c.text.trim();

  Future<void> _buscar({bool mais = false}) async {
    final geracao = ++_geracao;
    setState(() {
      _carregando = true;
      _erro = null;
      if (!mais) _itens = const [];
    });
    try {
      final r = await context.api.listarExclusividades(
        pedidoId: _opcional(_pedido),
        clienteId: _opcional(_cliente),
        status: _status,
        deslocamento: _itens.length,
        limite: _porPagina,
      );
      if (!mounted || geracao != _geracao) return;
      setState(() {
        _itens = [..._itens, ...r.itens];
        _total = r.total;
        _carregando = false;
      });
    } catch (e) {
      if (!mounted || geracao != _geracao) return;
      setState(() {
        _erro = e.toString();
        _carregando = false;
      });
    }
  }

  /// Filtro novo: a escolha anterior pode não estar mais na lista, então é desfeita.
  void _filtrar() {
    widget.aoEscolher?.call(null);
    _buscar();
  }

  Widget _campo(String rotulo, TextEditingController c) => Padding(
        padding: const EdgeInsets.only(bottom: EspacosTrato.x2),
        child: TextField(
          controller: c,
          decoration: InputDecoration(labelText: rotulo, helperText: 'Enter para filtrar'),
          onSubmitted: (_) => _filtrar(),
        ),
      );

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _campo('Filtrar por código do pedido', _pedido),
        _campo('Filtrar por código do cliente', _cliente),
        DropdownButtonFormField<String?>(
          initialValue: _status,
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'Situação'),
          items: [
            const DropdownMenuItem(value: null, child: Text('Todas')),
            for (final e in kStatusExclusividade.entries) DropdownMenuItem(value: e.key, child: Text(e.value)),
          ],
          onChanged: (v) {
            _status = v;
            _filtrar();
          },
        ),
        const SizedBox(height: EspacosTrato.x3),
        if (_erro != null) ...[
          BannerInfo(_erro!, titulo: 'A lista não carregou.', tom: Tom.erro),
          Align(alignment: Alignment.centerLeft, child: BotaoTrato.link('Tentar de novo', aoPressionar: _filtrar)),
        ] else if (!_carregando && _itens.isEmpty)
          Text('Nenhuma exclusividade com esse filtro.', style: TipografiaTrato.corpo),
        for (final e in _itens)
          Padding(
            padding: const EdgeInsets.only(bottom: EspacosTrato.x2),
            child: InkWell(
              key: ValueKey('exclusividade-${e.id}'),
              borderRadius: BorderRadius.circular(EspacosTrato.raio),
              onTap: widget.aoEscolher == null ? null : () => widget.aoEscolher!(e),
              child: Semantics(
                selected: widget.escolhida?.id == e.id,
                button: true,
                child: CartaoLista(
                  titulo: '${e.clienteNome ?? 'Cliente'} × ${e.profissionalNome ?? 'Profissional'}',
                  linhas: ['Criada em ${formatarData(e.criadaEm)} · ${formatarMilhar(e.moedas)} Tratinhos'],
                  chips: [
                    ChipEstado(rotuloStatusExclusividade(e.status), tom: Tom.info),
                    if (e.estornada) const ChipEstado('Já devolvida', tom: Tom.ok),
                  ],
                  selecionado: widget.escolhida?.id == e.id,
                ),
              ),
            ),
          ),
        if (_carregando)
          const Padding(padding: EdgeInsets.all(EspacosTrato.x3), child: Center(child: CircularProgressIndicator()))
        else if (_itens.length < _total) ...[
          Text('Mostrando ${_itens.length} de $_total', style: TipografiaTrato.legenda),
          Align(
            alignment: Alignment.centerLeft,
            child: BotaoTrato.secundario('Carregar mais', aoPressionar: () => _buscar(mais: true)),
          ),
        ],
      ],
    );
  }
}
