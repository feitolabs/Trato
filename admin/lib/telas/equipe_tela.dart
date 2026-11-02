import 'package:flutter/material.dart';

import '../componentes/base.dart';
import '../dados/modelos.dart';
import '../nucleo/escopo.dart';
import '../nucleo/formato.dart';
import '../nucleo/papeis.dart';
import '../tema/tema.dart';

/// Módulo 6 — Gestão de Equipe e Acessos Internos
class EquipeTela extends StatefulWidget {
  const EquipeTela({super.key});

  @override
  State<EquipeTela> createState() => _EquipeTelaState();
}

class _EquipeTelaState extends State<EquipeTela> {
  int _versao = 0;

  Future<void> _adicionar(BuildContext context) async {
    final nomeCtrl = TextEditingController();
    final emailCtrl = TextEditingController();
    var papel = 'atendente_n1';
    final alcadaCtrl = TextEditingController(text: '0');
    final motivoCtrl = TextEditingController();

    final res = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSt) => AlertDialog(
          title: const Text('Adicionar novo membro à equipe'),
          content: SizedBox(
            width: 440,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: nomeCtrl,
                    decoration: const InputDecoration(labelText: 'Nome completo *', hintText: 'Ex: Ana Maria'),
                  ),
                  const SizedBox(height: EspacosTrato.x3),
                  TextField(
                    controller: emailCtrl,
                    keyboardType: TextInputType.emailAddress,
                    decoration: const InputDecoration(labelText: 'E-mail corporativo / login *', hintText: 'ana@trato.feitolabs.com.br'),
                  ),
                  const SizedBox(height: EspacosTrato.x3),
                  DropdownButtonFormField<String>(
                    value: papel,
                    items: const [
                      DropdownMenuItem(value: 'atendente_n1', child: Text('Atendente N1 (Busca e Suporte)')),
                      DropdownMenuItem(value: 'atendente_n2', child: Text('Atendente N2 (Suporte e Disputas)')),
                      DropdownMenuItem(value: 'mediador', child: Text('Mediador (Disputas)')),
                      DropdownMenuItem(value: 'cadastro', child: Text('Cadastro (Verificação de Documentos)')),
                      DropdownMenuItem(value: 'moderador', child: Text('Moderador (Catálogo e Campanhas)')),
                      DropdownMenuItem(value: 'financeiro', child: Text('Financeiro (Pagamentos e Configurações)')),
                      DropdownMenuItem(value: 'seguranca', child: Text('Segurança (Antifraude e Auditoria)')),
                      DropdownMenuItem(value: 'lider_suporte', child: Text('Líder de Suporte (Aprovação Nível 2)')),
                      DropdownMenuItem(value: 'administrador', child: Text('Administrador (Autonomia Plena)')),
                    ],
                    onChanged: (v) {
                      if (v != null) setSt(() => papel = v);
                    },
                    decoration: const InputDecoration(labelText: 'Papel na equipe'),
                  ),
                  const SizedBox(height: EspacosTrato.x3),
                  TextField(
                    controller: alcadaCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: r'Alçada máxima de decisão (R$)',
                      hintText: '0 para atendentes comuns, valor para mediadores/gestores',
                      prefixText: r'R$ ',
                    ),
                  ),
                  const SizedBox(height: EspacosTrato.x3),
                  TextField(
                    controller: motivoCtrl,
                    decoration: const InputDecoration(labelText: 'Motivo da concessão de acesso *', hintText: 'Obrigatório para auditoria'),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
            FilledButton(
              onPressed: () {
                final n = nomeCtrl.text.trim();
                final e = emailCtrl.text.trim();
                final mot = motivoCtrl.text.trim();
                if (n.length < 2 || !e.contains('@') || mot.length < 3) {
                  mostrarAviso(ctx, 'Preencha nome, e-mail válido e motivo.');
                  return;
                }
                Navigator.pop(ctx, true);
              },
              child: const Text('Conceder acesso'),
            ),
          ],
        ),
      ),
    );

    if (res != true || !mounted) return;

    final alcVal = double.tryParse(alcadaCtrl.text.trim()) ?? 0;
    final alcCentavos = (alcVal * 100).toInt();

    final ok = await executar(
      context,
      () => context.api.adicionarMembroEquipe(
        nome: nomeCtrl.text.trim(),
        email: emailCtrl.text.trim(),
        papel: papel,
        alcadaCentavos: alcCentavos,
        motivo: motivoCtrl.text.trim(),
      ),
      sucesso: 'Membro da equipe adicionado com sucesso.',
    );
    if (ok && mounted) setState(() => _versao++);
  }

  Future<void> _revogar(MembroEquipeAdmin m) async {
    final motivo = await pedirMotivo(
      context,
      titulo: 'Revogar acesso de ${m.nome}',
      descricao: 'O colaborador perderá imediatamente o acesso administrativo ao painel.',
      rotuloConfirmar: 'Revogar acesso',
    );
    if (motivo == null || !mounted) return;
    final ok = await executar(
      context,
      () => context.api.revogarMembroEquipe(m.usuarioId, motivo: motivo),
      sucesso: 'Acesso revogado.',
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
                'Gestão da Equipe & Acessos',
                subtitulo: 'Colaboradores internos, atribuição de papéis e limites de alçada',
              ),
            ),
            if (context.pode(Permissao.equipeGerenciar))
              Padding(
                padding: const EdgeInsets.only(right: EspacosTrato.x6),
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(0, 40),
                    padding: const EdgeInsets.symmetric(horizontal: EspacosTrato.x4),
                  ),
                  onPressed: () => _adicionar(context),
                  icon: const Icon(Icons.person_add_outlined, size: 18),
                  label: const Text('Novo colaborador'),
                ),
              ),
          ],
        ),
        Expanded(
          child: CarregaDados<List<MembroEquipeAdmin>>(
            key: ValueKey('equipe-$_versao'),
            carregar: context.api.listarEquipe,
            estaVazio: (l) => l.isEmpty,
            mensagemVazia: 'Nenhum colaborador encontrado.',
            construir: (context, lista, _) => ListView.separated(
              padding: const EdgeInsets.all(EspacosTrato.x6),
              itemCount: lista.length,
              separatorBuilder: (_, _) => const SizedBox(height: EspacosTrato.x3),
              itemBuilder: (context, i) {
                final m = lista[i];
                final rotuloPapel = Papel.doCodigo(m.papel)?.rotulo ?? m.papel;
                final tomPapel = m.papel == 'administrador' ? Tom.alerta : Tom.info;

                return Card(
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: m.ativo ? CoresTrato.petroleo : CoresTrato.borda,
                      child: Text(
                        m.nome.isNotEmpty ? m.nome[0].toUpperCase() : 'E',
                        style: const TextStyle(color: CoresTrato.creme, fontWeight: FontWeight.bold),
                      ),
                    ),
                    title: Row(
                      children: [
                        Text(m.nome, style: TipografiaTrato.corpoForte),
                        const SizedBox(width: EspacosTrato.x2),
                        ChipEstado(rotuloPapel, tom: tomPapel),
                        const SizedBox(width: EspacosTrato.x2),
                        ChipEstado(m.ativo ? 'Ativo' : 'Revogado', tom: m.ativo ? Tom.ok : Tom.neutro),
                      ],
                    ),
                    subtitle: Text('${m.email} · Alçada: ${m.alcadaCentavos > 0 ? formatarReais(m.alcadaCentavos) : "Sem alçada financeira"}'),
                    trailing: m.ativo && context.pode(Permissao.equipeGerenciar)
                        ? TextButton(
                            onPressed: () => _revogar(m),
                            child: const Text('Revogar acesso'),
                          )
                        : null,
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
