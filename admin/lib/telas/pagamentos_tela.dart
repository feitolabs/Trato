import 'package:flutter/material.dart';

import '../componentes/base.dart';
import '../dados/modelos.dart';
import '../nucleo/escopo.dart';
import '../nucleo/formato.dart';
import '../tema/tema.dart';

/// F7.3 — pagamentos e conciliação. SOMENTE LEITURA (D15): sem saldo próprio e sem saque.
/// Mostra o espelho do que o provedor de pagamento liquidou.
class PagamentosTela extends StatelessWidget {
  const PagamentosTela({super.key});

  static (String, Tom) _chip(StatusProvedor s) => switch (s) {
        StatusProvedor.aguardandoConfirmacao => ('Aguardando confirmação', Tom.alerta),
        StatusProvedor.confirmado => ('Confirmado pelo provedor', Tom.ok),
        StatusProvedor.falhou => ('Falhou', Tom.erro),
        StatusProvedor.reembolsado => ('Reembolsado', Tom.info),
        StatusProvedor.reembolsadoParcial => ('Reembolsado em parte', Tom.info),
      };

  @override
  Widget build(BuildContext context) {
    final api = context.api;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const CabecalhoPagina('Pagamentos e conciliação', subtitulo: 'Extrato espelho do provedor de pagamento'),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: EspacosTrato.x6),
          child: BannerInfo(
            'Somente leitura. O Trato não guarda saldo próprio e não faz saque: esta tela só espelha o que o '
            'provedor de pagamento confirmou.',
            icone: Icons.visibility_outlined,
          ),
        ),
        const SizedBox(height: EspacosTrato.x4),
        Expanded(
          child: CarregaDados<(ResumoConciliacao, List<LancamentoEspelho>)>(
            carregar: () async {
              final r = await api.resumoConciliacao();
              final e = await api.extrato();
              return (r, e);
            },
            estaVazio: (d) => d.$2.isEmpty,
            mensagemVazia: 'Nenhum lançamento no extrato.',
            construir: (context, dados, recarregar) {
              final (resumo, extrato) = dados;
              return ListView(
                padding: const EdgeInsets.symmetric(horizontal: EspacosTrato.x6),
                children: [
                  Wrap(
                    spacing: EspacosTrato.x3,
                    runSpacing: EspacosTrato.x3,
                    children: [
                      _Resumo('Confirmado pelo provedor', formatarReais(resumo.confirmadoCentavos)),
                      _Resumo('Reembolsado', formatarReais(resumo.estornadoCentavos)),
                      _Resumo('Em andamento', formatarReais(resumo.emAndamentoCentavos)),
                      _Resumo('Divergências', '${resumo.divergencias}',
                          alerta: resumo.divergencias > 0),
                    ],
                  ),
                  const SizedBox(height: EspacosTrato.x2),
                  Text('Atualizado em ${formatarData(resumo.atualizadoEm)}', style: TipografiaTrato.legenda),
                  const SizedBox(height: EspacosTrato.x4),
                  Text('Extrato', style: TipografiaTrato.tituloCartao),
                  const SizedBox(height: EspacosTrato.x2),
                  for (final l in extrato) _LinhaExtrato(l, _chip(l.status)),
                  const SizedBox(height: EspacosTrato.x6),
                ],
              );
            },
          ),
        ),
      ],
    );
  }
}

class _Resumo extends StatelessWidget {
  const _Resumo(this.rotulo, this.valor, {this.alerta = false});
  final String rotulo;
  final String valor;
  final bool alerta;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 230,
      child: Card(
        color: alerta ? CoresTrato.ambarSuave : null,
        child: Padding(
          padding: const EdgeInsets.all(EspacosTrato.x4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(rotulo, style: TipografiaTrato.legenda),
              const SizedBox(height: EspacosTrato.x1),
              Text(valor, style: TipografiaTrato.tituloOpcao),
            ],
          ),
        ),
      ),
    );
  }
}

class _LinhaExtrato extends StatelessWidget {
  const _LinhaExtrato(this.l, this.chip);
  final LancamentoEspelho l;
  final (String, Tom) chip;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: EspacosTrato.x2),
      child: Padding(
        padding: const EdgeInsets.all(EspacosTrato.x4),
        child: Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          runSpacing: EspacosTrato.x2,
          spacing: EspacosTrato.x4,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(l.descricao, style: TipografiaTrato.tituloCartao),
                Text('${l.pedido} · ${l.refProvedor} · ${formatarData(l.data)}', style: TipografiaTrato.legenda),
              ],
            ),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (l.divergente) ...[
                  const ChipEstado('Divergente', tom: Tom.erro),
                  const SizedBox(width: EspacosTrato.x2),
                ],
                ChipEstado(chip.$1, tom: chip.$2),
                const SizedBox(width: EspacosTrato.x4),
                Text(formatarReais(l.valorCentavos), style: TipografiaTrato.corpoForte),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
