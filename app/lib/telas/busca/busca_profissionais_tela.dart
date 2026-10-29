import 'package:flutter/material.dart';

import '../../tema/tema.dart';
import '../cliente/avatar_iniciais.dart';
import '../cliente/dados_exemplo.dart';
import '../cliente/modelos.dart';
import '../comuns/estados.dart';
import 'modelos.dart';

/// F5.4 — Busca de profissional ou serviço (campo, resultados, estado vazio, erro).
/// Complementa a tela 9 (`BuscarTela`, filtros e mapa): esta fala com um [ServicoBusca].
/// O toque em um resultado chama [aoAbrirProfissional]; o perfil público é
/// `PerfilProfissionalTela`.
class BuscaProfissionaisTela extends StatefulWidget {
  const BuscaProfissionaisTela({
    super.key,
    required this.servico,
    this.aoAbrirProfissional,
    this.termoInicial = '',
    this.sugestoes = categorias,
  });

  final ServicoBusca servico;
  final ValueChanged<Profissional>? aoAbrirProfissional;
  final String termoInicial;

  /// Categorias mostradas antes de qualquer busca.
  final List<CategoriaServico> sugestoes;

  @override
  State<BuscaProfissionaisTela> createState() => _BuscaProfissionaisTelaState();
}

class _BuscaProfissionaisTelaState extends State<BuscaProfissionaisTela> {
  late final _campo = TextEditingController(text: widget.termoInicial);
  Future<List<Profissional>>? _busca;
  var _termo = '';

  @override
  void initState() {
    super.initState();
    if (widget.termoInicial.trim().isNotEmpty) _buscar(widget.termoInicial);
  }

  @override
  void dispose() {
    _campo.dispose();
    super.dispose();
  }

  void _buscar(String texto) {
    final termo = texto.trim();
    setState(() {
      _termo = termo;
      _busca = termo.isEmpty ? null : widget.servico.buscar(termo);
    });
  }

  @override
  Widget build(BuildContext context) {
    return MolduraTelaComum(
      titulo: 'Buscar',
      comVoltar: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _campo,
            style: TipografiaTrato.corpo,
            textInputAction: TextInputAction.search,
            onSubmitted: _buscar,
            decoration: InputDecoration(
              hintText: 'Serviço ou profissional',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: IconButton(
                tooltip: 'Buscar',
                icon: const Icon(Icons.arrow_forward),
                onPressed: () => _buscar(_campo.text),
              ),
            ),
          ),
          const SizedBox(height: EspacosTrato.x4),
          Expanded(child: _busca == null ? _Sugestoes(widget: widget, aoEscolher: _escolher) : _resultado()),
        ],
      ),
    );
  }

  void _escolher(String nome) {
    _campo.text = nome;
    _buscar(nome);
  }

  Widget _resultado() {
    return FutureBuilder<List<Profissional>>(
      key: ValueKey(_busca),
      future: _busca,
      builder: (context, snap) {
        if (snap.hasError) return EstadoErro(aoTentarNovamente: () => _buscar(_termo));
        if (!snap.hasData) return const EstadoCarregando();
        final lista = snap.data!;
        if (lista.isEmpty) {
          return EstadoVazio(
            icone: Icons.search_off,
            titulo: 'Nada encontrado',
            texto: 'Não achamos resultados para "$_termo". Tente outro nome ou categoria.',
          );
        }
        return ListView.separated(
          padding: const EdgeInsets.only(bottom: EspacosTrato.x6),
          itemCount: lista.length + 1,
          separatorBuilder: (_, __) => const SizedBox(height: EspacosTrato.x3),
          itemBuilder: (_, i) {
            if (i == 0) {
              return Text(
                '${lista.length} ${lista.length == 1 ? 'resultado' : 'resultados'}',
                style: TipografiaTrato.corpoPequeno.copyWith(color: CoresTrato.textoSecundario),
              );
            }
            final p = lista[i - 1];
            return _CartaoResultado(
              profissional: p,
              aoTocar: () => widget.aoAbrirProfissional?.call(p),
            );
          },
        );
      },
    );
  }
}

class _Sugestoes extends StatelessWidget {
  const _Sugestoes({required this.widget, required this.aoEscolher});

  final BuscaProfissionaisTela widget;
  final ValueChanged<String> aoEscolher;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('CATEGORIAS', style: TipografiaTrato.sobretitulo),
          const SizedBox(height: EspacosTrato.x3),
          Wrap(
            spacing: EspacosTrato.x2,
            runSpacing: EspacosTrato.x2,
            children: [
              for (final c in widget.sugestoes)
                ActionChip(
                  avatar: Icon(c.icone, size: 18, color: CoresTrato.petroleo),
                  label: Text(c.nome, style: TipografiaTrato.corpoPequeno),
                  backgroundColor: CoresTrato.superficie,
                  side: const BorderSide(color: CoresTrato.borda),
                  onPressed: () => aoEscolher(c.nome),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _CartaoResultado extends StatelessWidget {
  const _CartaoResultado({required this.profissional, required this.aoTocar});

  final Profissional profissional;
  final VoidCallback aoTocar;

  @override
  Widget build(BuildContext context) {
    final p = profissional;
    return Semantics(
      button: true,
      label: '${p.nome}, ${p.especialidade}, nota ${p.nota}',
      excludeSemantics: true,
      child: Material(
        color: CoresTrato.superficie,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(EspacosTrato.raioGrande),
          side: const BorderSide(color: CoresTrato.borda),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: aoTocar,
          child: Padding(
            padding: const EdgeInsets.all(EspacosTrato.x4),
            child: Row(
              children: [
                AvatarIniciais(iniciais: p.iniciais),
                const SizedBox(width: EspacosTrato.x3),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(p.nome, style: TipografiaTrato.tituloCartao),
                      Text(
                        p.especialidade,
                        style: TipografiaTrato.corpoPequeno
                            .copyWith(color: CoresTrato.textoSecundario),
                      ),
                      const SizedBox(height: EspacosTrato.x1),
                      Text(
                        '${p.nota.toStringAsFixed(1).replaceAll('.', ',')} · '
                        '${p.servicosConcluidos} serviços · '
                        '${p.distanciaKm.toStringAsFixed(1).replaceAll('.', ',')} km',
                        style: TipografiaTrato.legenda,
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right, color: CoresTrato.petroleo),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
