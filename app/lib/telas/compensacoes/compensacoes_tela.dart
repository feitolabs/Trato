import 'package:flutter/material.dart';

import '../../componentes/componentes.dart';
import '../../dados/modelos_api.dart';
import '../../tema/tema.dart';
import '../comuns/estados.dart';
import '../comuns/formato_aparelho.dart';
import '../profissional/dinheiro.dart';
import 'modelos.dart';

String _quando(DateTime d) => '${d.day.toString().padLeft(2, '0')}/'
    '${d.month.toString().padLeft(2, '0')}/${d.year}, ${horaDoAparelho(d)}';

/// "Compensações" do profissional (Termos 8.6 e 17.4), com o atendimento para contestar.
class CompensacoesTela extends StatelessWidget {
  const CompensacoesTela({
    super.key,
    required this.servico,
    required this.aoFalarComOTrato,
    this.compensacaoId,
  });

  final ServicoCompensacoes servico;

  /// Abre o atendimento, já com o pedido da compensação quando houver.
  final void Function(BuildContext context, String? pedidoId) aoFalarComOTrato;

  /// A compensação do aviso: vem primeiro e marcada.
  final String? compensacaoId;

  @override
  Widget build(BuildContext context) {
    final secundario = TipografiaTrato.corpoPequeno.copyWith(color: context.cores.textoSecundario);
    return MolduraTelaComum(
      titulo: 'Compensações',
      child: CarregadorTela<List<Compensacao>?>(
        carregar: servico.listar,
        construir: (context, itens, _) {
          if (itens == null) {
            return EstadoVazio(
              icone: Icons.receipt_long_outlined,
              titulo: 'Compensações indisponíveis',
              texto: textoCompensacoesIndisponiveis,
              textoAcao: 'Falar com o Trato',
              aoAcao: () => aoFalarComOTrato(context, null),
            );
          }
          final doAviso = [
            for (final c in itens)
              if (c.id == compensacaoId) c,
          ];
          final naoAchou = compensacaoId != null && doAviso.isEmpty;
          if (itens.isEmpty) {
            return EstadoVazio(
              icone: Icons.receipt_long_outlined,
              titulo: 'Nenhuma compensação',
              texto: naoAchou
                  ? 'Não achamos a compensação deste aviso e não há outras registradas.'
                  : 'Não há descontos registrados nos seus repasses.',
              textoAcao: 'Falar com o Trato',
              aoAcao: () => aoFalarComOTrato(context, null),
            );
          }
          final ordem = [
            ...doAviso,
            for (final c in itens)
              if (c.id != compensacaoId) c,
          ];
          // Coluna (e não lista preguiçosa): são poucos itens.
          return SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.only(bottom: EspacosTrato.x6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Descontos nos seus próximos repasses.', style: secundario),
                const SizedBox(height: EspacosTrato.x3),
                if (naoAchou) ...[
                  Text(
                    'Não achamos a compensação deste aviso. Veja as outras abaixo.',
                    key: const Key('compensacao-nao-achada'),
                    style: TipografiaTrato.corpoForte,
                  ),
                  const SizedBox(height: EspacosTrato.x3),
                ],
                for (final c in ordem) ...[
                  _CartaoCompensacao(
                    item: c,
                    doAviso: c.id == compensacaoId,
                    aoFalar: () => aoFalarComOTrato(context, c.pedidoId),
                  ),
                  const SizedBox(height: EspacosTrato.x3),
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}

class _CartaoCompensacao extends StatelessWidget {
  const _CartaoCompensacao({required this.item, required this.doAviso, required this.aoFalar});

  final Compensacao item;
  final bool doAviso;
  final VoidCallback aoFalar;

  @override
  Widget build(BuildContext context) {
    final c = item;
    final secundario = TipografiaTrato.corpoPequeno.copyWith(color: context.cores.textoSecundario);
    List<Widget> bloco(String rotulo, String? texto) => [
          if (texto != null) ...[
            const SizedBox(height: EspacosTrato.x2),
            Text(rotulo, style: secundario),
            Text(texto, style: TipografiaTrato.corpo),
          ],
        ];
    String valor(int? centavos) => centavos == null ? 'Não informado' : Dinheiro.formatar(centavos);
    return CartaoTrato(
      key: ValueKey('compensacao-${c.id}'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (doAviso) ...[
            Text('Compensação deste aviso',
                key: const Key('compensacao-do-aviso'), style: TipografiaTrato.corpoForte),
            const SizedBox(height: EspacosTrato.x1),
          ],
          Text(
            c.pedidoId == null ? 'Compensação' : 'Pedido ${PedidoApi.numeroDe(c.pedidoId!)}',
            style: TipografiaTrato.tituloCartao,
          ),
          const SizedBox(height: EspacosTrato.x2),
          Align(
            alignment: Alignment.centerLeft,
            child: ChipStatus(
              texto: c.situacaoTexto,
              tipo: switch (c.status) {
                'aberta' => TipoStatus.alerta,
                'quitada' => TipoStatus.sucesso,
                _ => TipoStatus.info,
              },
            ),
          ),
          ...bloco('Valor', valor(c.valorCentavos)),
          ...bloco('Já descontado', valor(c.compensadoCentavos)),
          ...bloco('Falta descontar', valor(c.restanteCentavos)),
          ...bloco('Motivo', c.motivo ?? 'Não informado'),
          ...bloco('Registrada em', c.criadaEm == null ? null : _quando(c.criadaEm!)),
          ...bloco('Aviso enviado em', c.avisadoEm == null ? null : _quando(c.avisadoEm!)),
          ...bloco('Cancelada em', c.canceladaEm == null ? null : _quando(c.canceladaEm!)),
          ...bloco('Motivo do cancelamento', c.motivoCancelamento),
          const SizedBox(height: EspacosTrato.x3),
          Text('Não concorda? Conteste pelo atendimento.', style: secundario),
          const SizedBox(height: EspacosTrato.x2),
          BotaoSecundario(
            key: ValueKey('falar-${c.id}'),
            texto: 'Falar com o Trato',
            aoTocar: aoFalar,
          ),
        ],
      ),
    );
  }
}

/// A entrada "Compensações" na Carteira. Some quando o servidor não tem a função (404/503); numa
/// falha passageira aparece, e a tela dela tem "Tentar de novo".
class EntradaDeCompensacoes extends StatefulWidget {
  const EntradaDeCompensacoes({super.key, required this.servico, required this.aoAbrir});

  final ServicoCompensacoes servico;
  final VoidCallback aoAbrir;

  @override
  State<EntradaDeCompensacoes> createState() => _EntradaDeCompensacoesState();
}

class _EntradaDeCompensacoesState extends State<EntradaDeCompensacoes> {
  var _tem = false;

  @override
  void initState() {
    super.initState();
    _conferir();
  }

  Future<void> _conferir() async {
    var tem = true;
    try {
      tem = await widget.servico.listar() != null;
    } on Object {
      // Falha passageira: a entrada aparece.
    }
    if (mounted) setState(() => _tem = tem);
  }

  @override
  Widget build(BuildContext context) {
    if (!_tem) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: EspacosTrato.x4),
      child: BotaoSecundario(
        key: const Key('entrada-compensacoes'),
        texto: 'Compensações',
        aoTocar: widget.aoAbrir,
      ),
    );
  }
}
