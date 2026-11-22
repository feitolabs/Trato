import 'package:flutter/material.dart';

import '../../componentes/componentes.dart';
import '../../tema/tema.dart';
import '../comuns/desconto_moedas.dart';
import '../comuns/estados.dart';
import '../comuns/moeda_trato.dart';
import '../profissional/dinheiro.dart';
import 'modelos.dart';

/// Subtela de extrato de Tratinhos do cliente (saldo disponível, a liberar e lançamentos).
class ExtratoTratinhosTela extends StatelessWidget {
  const ExtratoTratinhosTela({super.key, required this.perfil});

  final PerfilCliente perfil;

  static String rotuloTipo(String tipo) => switch (tipo.trim().toLowerCase()) {
        'bonus_avaliacao' || 'bonus_avaliacao_cliente' => 'Bônus por avaliação',
        'bonus_avaliacao_profissional' => 'Bônus por avaliação',
        'desconto' || 'desconto_pedido' || 'uso_desconto' || 'resgate' => 'Desconto em pedido',
        'estorno' || 'estorno_desconto' || 'devolucao' => 'Devolução de Tratinhos',
        'expiracao' || 'expirado' => 'Tratinhos expirados',
        'exclusividade' => 'Exclusividade em pedido',
        _ => tipo.replaceAll('_', ' ').trim().isEmpty
            ? 'Movimentação de Tratinhos'
            : tipo.replaceAll('_', ' '),
      };

  static String _dataCurta(DateTime? d) {
    if (d == null) return '';
    final dia = d.day.toString().padLeft(2, '0');
    final mes = d.month.toString().padLeft(2, '0');
    return '$dia/$mes/${d.year}';
  }

  @override
  Widget build(BuildContext context) {
    final disponiveis = perfil.moedas ?? 0;
    final pendentes = perfil.moedasPendentes;
    final valorCentavos = perfil.moedasValorCentavos;
    final extrato = perfil.moedasExtrato;
    final secundario = TipografiaTrato.corpoPequeno.copyWith(color: context.cores.textoSecundario);

    return MolduraTelaComum(
      titulo: 'Seus Tratinhos',
      child: ListView(
        padding: const EdgeInsets.only(bottom: EspacosTrato.x6),
        children: [
          CartaoTrato(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const MoedaTrato(tamanho: 36),
                    const SizedBox(width: EspacosTrato.x3),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Saldo disponível', style: secundario),
                          const SizedBox(height: 2),
                          Text(
                            '$disponiveis ${disponiveis == 1 ? 'Tratinho' : 'Tratinhos'}',
                            style: TipografiaTrato.tituloGrande,
                          ),
                          if (valorCentavos != null)
                            Text(
                              textoTratinhosEmReais(disponiveis, valorCentavos),
                              style: secundario,
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
                if (pendentes > 0) ...[
                  const SizedBox(height: EspacosTrato.x3),
                  const Divider(height: 1),
                  const SizedBox(height: EspacosTrato.x3),
                  Text(
                    textoTratinhosPendentes(
                      pendentes,
                      perfil.moedasProximaLiberacao,
                      valorCentavos,
                    )!,
                    style: secundario,
                  ),
                ],
                if (perfil.moedasVenceEm != null) ...[
                  const SizedBox(height: EspacosTrato.x2),
                  Text(
                    'Tratinhos vencem em ${formatarDiaMes(perfil.moedasVenceEm!)}',
                    style: secundario,
                  ),
                ],
                if (perfil.descontoUsadoMesCentavos != null &&
                    perfil.tetoDescontoMesCentavos != null) ...[
                  const SizedBox(height: EspacosTrato.x2),
                  Text(
                    'Desconto usado no mês: ${Dinheiro.formatar(perfil.descontoUsadoMesCentavos!)} '
                    'de ${Dinheiro.formatar(perfil.tetoDescontoMesCentavos!)}',
                    style: secundario,
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: EspacosTrato.x5),
          Text('Extrato', style: TipografiaTrato.titulo),
          const SizedBox(height: EspacosTrato.x3),
          if (extrato.isEmpty)
            const EstadoVazio(
              icone: Icons.receipt_long_outlined,
              titulo: 'Nenhum lançamento ainda',
              texto: 'Quando você ganhar ou usar Tratinhos, cada movimentação aparece aqui.',
            )
          else
            CartaoTrato(
              child: Column(
                children: [
                  for (var i = 0; i < extrato.length; i++) ...[
                    if (i > 0) const Divider(height: 1),
                    _LinhaLancamento(
                      item: extrato[i],
                      valorMoedaCentavos: valorCentavos,
                      dataTexto: _dataCurta(extrato[i].criadaEm),
                    ),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _LinhaLancamento extends StatelessWidget {
  const _LinhaLancamento({
    required this.item,
    required this.valorMoedaCentavos,
    required this.dataTexto,
  });

  final LancamentoTratinho item;
  final int? valorMoedaCentavos;
  final String dataTexto;

  @override
  Widget build(BuildContext context) {
    final positivo = item.quantidade >= 0;
    final sinal = positivo ? '+' : '';
    final qtdTexto =
        '$sinal${item.quantidade} ${item.quantidade.abs() == 1 ? 'Tratinho' : 'Tratinhos'}';
    final emReais = valorMoedaCentavos == null
        ? null
        : Dinheiro.formatar(item.quantidade.abs() * valorMoedaCentavos!);

    return Padding(
      padding: const EdgeInsets.symmetric(
        vertical: EspacosTrato.x3,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  ExtratoTratinhosTela.rotuloTipo(item.tipo),
                  style: TipografiaTrato.corpoForte,
                ),
                if (dataTexto.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    dataTexto,
                    style: TipografiaTrato.legenda.copyWith(color: context.cores.textoSecundario),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: EspacosTrato.x3),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                qtdTexto,
                style: TipografiaTrato.corpoForte.copyWith(
                  color: positivo ? context.cores.verdeTexto : context.cores.petroleo,
                ),
              ),
              if (emReais != null)
                Text(
                  '${positivo ? '+' : '-'}$emReais',
                  style: TipografiaTrato.legenda.copyWith(color: context.cores.textoSecundario),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
