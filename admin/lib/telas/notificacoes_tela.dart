import 'package:flutter/material.dart';

import '../componentes/base.dart';
import '../dados/modelos.dart';
import '../nucleo/escopo.dart';
import '../nucleo/formato.dart';
import '../nucleo/papeis.dart';
import '../tema/tema.dart';

/// Módulo 4 — Central de Push Notifications & Mensagens em Massa
class NotificacoesTela extends StatefulWidget {
  const NotificacoesTela({super.key});

  @override
  State<NotificacoesTela> createState() => _NotificacoesTelaState();
}

class _NotificacoesTelaState extends State<NotificacoesTela> {
  int _versao = 0;

  Future<void> _disparar(BuildContext context) async {
    final tituloCtrl = TextEditingController();
    final msgCtrl = TextEditingController();
    var segmento = 'todos';
    final motivoCtrl = TextEditingController();

    final res = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSt) => AlertDialog(
          title: const Text('Disparar notificação push em massa'),
          content: SizedBox(
            width: 480,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: tituloCtrl,
                  decoration: const InputDecoration(labelText: 'Título da notificação *', hintText: 'Ex: Alta procura por serviços hoje!'),
                ),
                const SizedBox(height: EspacosTrato.x3),
                TextField(
                  controller: msgCtrl,
                  maxLines: 3,
                  decoration: const InputDecoration(labelText: 'Mensagem do push *', hintText: 'Texto claro e atrativo para o usuário'),
                ),
                const SizedBox(height: EspacosTrato.x3),
                DropdownButtonFormField<String>(
                  value: segmento,
                  items: const [
                    DropdownMenuItem(value: 'todos', child: Text('Todos os usuários ativos')),
                    DropdownMenuItem(value: 'clientes', child: Text('Apenas Clientes')),
                    DropdownMenuItem(value: 'profissionais', child: Text('Apenas Profissionais / Prestadores')),
                  ],
                  onChanged: (v) {
                    if (v != null) setSt(() => segmento = v);
                  },
                  decoration: const InputDecoration(labelText: 'Segmento alvo'),
                ),
                const SizedBox(height: EspacosTrato.x3),
                TextField(
                  controller: motivoCtrl,
                  decoration: const InputDecoration(labelText: 'Motivo do disparo *', hintText: 'Obrigatório para auditoria da empresa'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
            FilledButton(
              onPressed: () {
                final t = tituloCtrl.text.trim();
                final m = msgCtrl.text.trim();
                final mot = motivoCtrl.text.trim();
                if (t.length < 3 || m.length < 5 || mot.length < 3) {
                  mostrarAviso(ctx, 'Preencha título, mensagem e motivo.');
                  return;
                }
                Navigator.pop(ctx, true);
              },
              child: const Text('Enviar push agora'),
            ),
          ],
        ),
      ),
    );

    if (res != true || !mounted) return;

    final ok = await executar(
      context,
      () => context.api.dispararCampanhaNotificacao(
        titulo: tituloCtrl.text.trim(),
        mensagem: msgCtrl.text.trim(),
        segmento: segmento,
        motivo: motivoCtrl.text.trim(),
      ),
      sucesso: 'Notificação push disparada com sucesso para a base!',
    );
    if (ok && mounted) setState(() => _versao++);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Expanded(
              child: CabecalhoPagina(
                'Comunicação & Push Notifications',
                subtitulo: 'Envio de comunicados em massa, alertas operacionais e marketing',
              ),
            ),
            if (context.pode(Permissao.notificacoesEnviar))
              Padding(
                padding: const EdgeInsets.only(right: EspacosTrato.x6),
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(0, 40),
                    padding: const EdgeInsets.symmetric(horizontal: EspacosTrato.x4),
                  ),
                  onPressed: () => _disparar(context),
                  icon: const Icon(Icons.send_outlined, size: 18),
                  label: const Text('Nova notificação'),
                ),
              ),
          ],
        ),
        Expanded(
          child: CarregaDados<List<CampanhaNotificacao>>(
            key: ValueKey('campanhas-$_versao'),
            carregar: context.api.listarCampanhasNotificacao,
            estaVazio: (l) => l.isEmpty,
            mensagemVazia: 'Nenhuma campanha enviada até o momento.',
            construir: (context, lista, _) => ListView.separated(
              padding: const EdgeInsets.all(EspacosTrato.x6),
              itemCount: lista.length,
              separatorBuilder: (_, _) => const SizedBox(height: EspacosTrato.x3),
              itemBuilder: (context, i) {
                final c = lista[i];
                return Card(
                  child: ListTile(
                    leading: const CircleAvatar(
                      backgroundColor: CoresTrato.azulSuave,
                      child: Icon(Icons.campaign, color: CoresTrato.azulTexto),
                    ),
                    title: Text(c.titulo, style: TipografiaTrato.corpoForte),
                    subtitle: Text('${c.mensagem}\nSegmento: ${c.segmento.toUpperCase()} · ${c.totalDestinatarios} destinatários'),
                    isThreeLine: true,
                    trailing: ChipEstado('Enviada', tom: Tom.ok),
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

