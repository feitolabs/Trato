import 'package:flutter/material.dart';

import '../componentes/base.dart';
import '../dados/modelos.dart';
import '../nucleo/escopo.dart';
import '../nucleo/formato.dart';
import '../nucleo/papeis.dart';
import '../tema/tema.dart';

/// Módulo 3 — Central Antifraude e Gestão de Risco
class RiscoTela extends StatefulWidget {
  const RiscoTela({super.key});

  @override
  State<RiscoTela> createState() => _RiscoTelaState();
}

class _RiscoTelaState extends State<RiscoTela> {
  int _versao = 0;

  Future<void> _bloquear(BuildContext context, AlertaRisco a) async {
    if (a.usuarioId == null) return;
    final motivo = await pedirMotivo(
      context,
      titulo: 'Bloqueio preventivo',
      descricao: 'A conta do usuário será suspensa preventivamente até a conclusão da análise de fraude.',
      rotuloConfirmar: 'Bloquear conta',
    );
    if (motivo == null || !mounted) return;
    final ok = await executar(
      context,
      () => context.api.aplicarBloqueioPreventivo(a.usuarioId!, motivo: motivo),
      sucesso: 'Usuário bloqueado preventivamente com registro em auditoria.',
    );
    if (ok && mounted) setState(() => _versao++);
  }

  Future<void> _travarSaque(BuildContext context, AlertaRisco a) async {
    if (a.usuarioId == null) return;
    final motivo = await pedirMotivo(
      context,
      titulo: 'Travar saques e repasses',
      descricao: 'Os repasses e transferências PIX deste prestador ficarão retidos na plataforma.',
      rotuloConfirmar: 'Travar saques',
    );
    if (motivo == null || !mounted) return;
    final ok = await executar(
      context,
      () => context.api.travarSaque(a.usuarioId!, motivo: motivo),
      sucesso: 'Saques travados preventivamente com sucesso.',
    );
    if (ok && mounted) setState(() => _versao++);
  }

  Future<void> _resolver(BuildContext context, AlertaRisco a) async {
    final motivo = await pedirMotivo(
      context,
      titulo: 'Resolver alerta de risco',
      descricao: 'Informe o parecer final da análise de segurança.',
      rotuloConfirmar: 'Marcar como resolvido',
    );
    if (motivo == null || !mounted) return;
    final ok = await executar(
      context,
      () => context.api.resolverAlertaRisco(a.id, motivo: motivo),
      sucesso: 'Alerta arquivado como resolvido.',
    );
    if (ok && mounted) setState(() => _versao++);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const CabecalhoPagina(
          'Central de Risco & Antifraude',
          subtitulo: 'Detecção de anomalias, bloqueios preventivos e travas de segurança',
        ),
        Expanded(
          child: CarregaDados<List<AlertaRisco>>(
            key: ValueKey('risco-$_versao'),
            carregar: context.api.listarAlertasRisco,
            estaVazio: (l) => l.isEmpty,
            mensagemVazia: 'Nenhum alerta de risco ou atividade suspeita identificada.',
            construir: (context, lista, _) => ListView.separated(
              padding: const EdgeInsets.all(EspacosTrato.x6),
              itemCount: lista.length,
              separatorBuilder: (_, _) => const SizedBox(height: EspacosTrato.x3),
              itemBuilder: (context, i) {
                final a = lista[i];
                final tom = switch (a.severidade) {
                  'critica' => Tom.alerta,
                  'alta' => Tom.alerta,
                  'media' => Tom.info,
                  _ => Tom.neutro,
                };
                return Card(
                  child: Padding(
                    padding: const EdgeInsets.all(EspacosTrato.x4),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            ChipEstado('Severidade: ${a.severidade.toUpperCase()}', tom: tom),
                            const SizedBox(width: EspacosTrato.x2),
                            ChipEstado(a.tipo, tom: Tom.info),
                            const Spacer(),
                            if (a.resolvido)
                              const ChipEstado('Resolvido', tom: Tom.ok)
                            else
                              const ChipEstado('Em aberto', tom: Tom.alerta),
                          ],
                        ),
                        const SizedBox(height: EspacosTrato.x3),
                        Text(a.detalhes, style: TipografiaTrato.corpoForte),
                        if (a.usuarioNome != null) ...[
                          const SizedBox(height: EspacosTrato.x1),
                          Text('Usuário envolvido: ${a.usuarioNome}', style: TipografiaTrato.corpoPequeno.copyWith(color: CoresTrato.textoSecundario)),
                        ],
                        if (!a.resolvido && context.pode(Permissao.riscoDecidir)) ...[
                          const SizedBox(height: EspacosTrato.x3),
                          Row(
                            children: [
                              TextButton.icon(
                                onPressed: () => _resolver(context, a),
                                icon: const Icon(Icons.check_circle_outline, size: 16),
                                label: const Text('Resolver alerta'),
                              ),
                              const Spacer(),
                              if (a.usuarioId != null) ...[
                                TextButton.icon(
                                  onPressed: () => _travarSaque(context, a),
                                  icon: const Icon(Icons.lock_clock_outlined, size: 16),
                                  label: const Text('Travar saques'),
                                ),
                                const SizedBox(width: EspacosTrato.x2),
                                TextButton.icon(
                                  onPressed: () => _bloquear(context, a),
                                  icon: const Icon(Icons.shield_outlined, size: 16),
                                  label: const Text('Bloqueio preventivo'),
                                ),
                              ],
                            ],
                          ),
                        ],
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
