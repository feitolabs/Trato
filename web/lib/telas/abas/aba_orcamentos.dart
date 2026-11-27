import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../dados/erros.dart';
import '../../dados/orcamentos.dart';
import '../../tema/tema.dart';

/// Orçamentos enviados pelo profissional, dados reais de `GET /v1/profissional/orcamentos`.
/// Só exibe o valor que o backend calculou; nenhuma conta acontece aqui.
class AbaOrcamentos extends StatefulWidget {
  const AbaOrcamentos({super.key, required this.repositorio});

  final RepositorioOrcamentos repositorio;

  @override
  State<AbaOrcamentos> createState() => _AbaOrcamentosState();
}

class _AbaOrcamentosState extends State<AbaOrcamentos> {
  late Future<List<OrcamentoEnviado>> _futuro = widget.repositorio.listarEnviados();

  Future<void> _recarregar() async {
    setState(() => _futuro = widget.repositorio.listarEnviados());
    await _futuro;
  }

  static const _rotuloSituacao = {
    'aguardando': 'Aguardando o cliente',
    'aceito': 'Aceito',
    'encerrado': 'Encerrado',
  };

  static const _corSituacao = {
    'aguardando': CoresTrato.ambarTexto,
    'aceito': CoresTrato.verdeTexto,
    'encerrado': CoresTrato.textoDica,
  };

  @override
  Widget build(BuildContext context) {
    final formatoMoeda = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');
    return ConteudoResponsivo(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: EspacosTrato.x4),
            Text('Orçamentos', style: TipografiaTrato.tituloGrande.copyWith(color: CoresTrato.petroleo)),
            const SizedBox(height: EspacosTrato.x3),
            Expanded(
              child: RefreshIndicator(
          onRefresh: _recarregar,
          child: FutureBuilder<List<OrcamentoEnviado>>(
            future: _futuro,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snapshot.hasError) {
                return ListView(
                  children: [
                    const SizedBox(height: EspacosTrato.x8),
                    Center(
                      child: Text(
                        mensagemErroTrato(snapshot.error!),
                        textAlign: TextAlign.center,
                        style: TipografiaTrato.corpo.copyWith(color: CoresTrato.vermelhoTexto),
                      ),
                    ),
                  ],
                );
              }
              final orcamentos = snapshot.data ?? const [];
              if (orcamentos.isEmpty) {
                return ListView(
                  children: [
                    const SizedBox(height: EspacosTrato.x8),
                    Center(
                      child: Text(
                        'Você ainda não enviou orçamentos.',
                        style: TipografiaTrato.corpo.copyWith(color: CoresTrato.textoDica),
                      ),
                    ),
                  ],
                );
              }
              return ListView.separated(
                padding: const EdgeInsets.symmetric(vertical: EspacosTrato.x4),
                itemCount: orcamentos.length,
                separatorBuilder: (_, _) => const SizedBox(height: EspacosTrato.x3),
                itemBuilder: (_, i) {
                  final orcamento = orcamentos[i];
                  return Card(
                    child: Padding(
                      padding: const EdgeInsets.all(EspacosTrato.paddingCartao),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  orcamento.tituloPedido ?? 'Pedido',
                                  style: TipografiaTrato.tituloCartao
                                      .copyWith(color: CoresTrato.petroleo),
                                ),
                                const SizedBox(height: EspacosTrato.x1),
                                Text(
                                  _rotuloSituacao[orcamento.situacao] ?? orcamento.situacao,
                                  style: TipografiaTrato.corpoPequeno.copyWith(
                                    color: _corSituacao[orcamento.situacao] ??
                                        CoresTrato.textoSecundario,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Text(
                            formatoMoeda.format(orcamento.valorCentavos / 100),
                            style: TipografiaTrato.tituloCartao.copyWith(color: CoresTrato.petroleo),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              );
            },
          ),
              ),
            ),
          ],
        ),
      );
  }
}
