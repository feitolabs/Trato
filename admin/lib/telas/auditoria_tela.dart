import 'package:flutter/material.dart';

import '../componentes/base.dart';
import '../dados/modelos.dart';
import '../nucleo/escopo.dart';
import '../nucleo/formato.dart';
import '../nucleo/papeis.dart';
import '../tema/tema.dart';

/// F7.6 — trilha de auditoria (só leitura) com filtro e verificação da cadeia de hash.
class AuditoriaTela extends StatefulWidget {
  const AuditoriaTela({super.key});

  @override
  State<AuditoriaTela> createState() => _AuditoriaTelaState();
}

class _AuditoriaTelaState extends State<AuditoriaTela> {
  final _acao = TextEditingController();
  final _ator = TextEditingController();
  String _filtroAcao = '';
  String _filtroAtor = '';
  int _versao = 0;
  bool _verificando = false;
  ResultadoCadeia? _cadeia;
  String? _erroCadeia;

  @override
  void dispose() {
    _acao.dispose();
    _ator.dispose();
    super.dispose();
  }

  void _filtrar() => setState(() {
        _filtroAcao = _acao.text;
        _filtroAtor = _ator.text;
        _versao++;
      });

  Future<void> _verificar() async {
    setState(() {
      _verificando = true;
      _erroCadeia = null;
    });
    final api = context.api;
    try {
      final r = await api.verificarCadeia();
      if (mounted) setState(() => _cadeia = r);
    } catch (e) {
      if (mounted) setState(() => _erroCadeia = e.toString());
    } finally {
      if (mounted) setState(() => _verificando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cadeia = _cadeia;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CabecalhoPagina(
          'Auditoria',
          subtitulo: 'Quem fez o quê, quando e por quê. Ninguém edita nem apaga.',
          acoes: [
            if (context.pode(Permissao.auditoriaVerificarCadeia))
              SizedBox(
                width: 220,
                child: OutlinedButton(
                  onPressed: _verificando ? null : _verificar,
                  child: Text(_verificando ? 'Verificando…' : 'Verificar cadeia de hash'),
                ),
              ),
          ],
        ),
        if (cadeia != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(EspacosTrato.x6, 0, EspacosTrato.x6, EspacosTrato.x3),
            child: cadeia.ok
                ? BannerInfo(
                    cadeia.verificadas == null ? 'Cadeia íntegra.' : 'Cadeia íntegra: ${cadeia.verificadas} registros conferidos.', tom: Tom.ok, icone: Icons.verified_outlined)
                : BannerInfo(
                    'Cadeia quebrada a partir do registro ${cadeia.primeiraQuebraId}. Avise segurança e jurídico.',
                    tom: Tom.erro,
                    icone: Icons.warning_amber_outlined,
                  ),
          ),
        if (_erroCadeia != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(EspacosTrato.x6, 0, EspacosTrato.x6, EspacosTrato.x3),
            child: BannerInfo(_erroCadeia!, tom: Tom.erro, icone: Icons.error_outline),
          ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: EspacosTrato.x6),
          child: Wrap(
            spacing: EspacosTrato.x3,
            runSpacing: EspacosTrato.x3,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SizedBox(
                width: 260,
                child: TextField(
                  controller: _acao,
                  onSubmitted: (_) => _filtrar(),
                  decoration: const InputDecoration(labelText: 'Ação (ex.: disputa.decidida)'),
                ),
              ),
              SizedBox(
                width: 260,
                child: TextField(
                  controller: _ator,
                  onSubmitted: (_) => _filtrar(),
                  decoration: const InputDecoration(labelText: 'Quem (id)'),
                ),
              ),
              SizedBox(width: 120, child: FilledButton(onPressed: _filtrar, child: const Text('Filtrar'))),
            ],
          ),
        ),
        const SizedBox(height: EspacosTrato.x3),
        Expanded(
          child: CarregaDados<List<EntradaAuditoria>>(
            key: ValueKey('$_filtroAcao|$_filtroAtor|$_versao'),
            carregar: () => context.api.listarAuditoria(acao: _filtroAcao, ator: _filtroAtor),
            estaVazio: (l) => l.isEmpty,
            mensagemVazia: 'Nenhum registro com esse filtro.',
            construir: (context, lista, _) => ListView.separated(
              padding: const EdgeInsets.fromLTRB(EspacosTrato.x6, 0, EspacosTrato.x6, EspacosTrato.x6),
              itemCount: lista.length,
              separatorBuilder: (_, _) => const SizedBox(height: EspacosTrato.x2),
              itemBuilder: (context, i) {
                final e = lista[i];
                return Card(
                  child: Padding(
                    padding: const EdgeInsets.all(EspacosTrato.x4),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(child: Text(e.acao, style: TipografiaTrato.tituloCartao)),
                            Text('#${e.id}', style: TipografiaTrato.legenda),
                          ],
                        ),
                        Text('${e.ator} · ${formatarData(e.ocorridaEm)} · ${e.entidade}', style: TipografiaTrato.legenda),
                        if (e.motivo != null) Text('Motivo: ${e.motivo}', style: TipografiaTrato.corpoPequeno),
                        if (e.hash != null) Text('hash ${e.hash}', style: TipografiaTrato.legenda),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}
