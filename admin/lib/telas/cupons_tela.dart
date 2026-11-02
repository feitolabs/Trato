import 'package:flutter/material.dart';

import '../componentes/base.dart';
import '../dados/modelos.dart';
import '../nucleo/escopo.dart';
import '../nucleo/formato.dart';
import '../nucleo/papeis.dart';
import '../tema/tema.dart';

/// Módulo 5 — Gestão de Cupons de Desconto & Campanhas
class CuponsTela extends StatefulWidget {
  const CuponsTela({super.key});

  @override
  State<CuponsTela> createState() => _CuponsTelaState();
}

class _CuponsTelaState extends State<CuponsTela> {
  int _versao = 0;

  Future<void> _criar(BuildContext context) async {
    final codigoCtrl = TextEditingController();
    var tipo = 'percentual';
    final valorCtrl = TextEditingController();
    final minCtrl = TextEditingController(text: '0');
    final limiteCtrl = TextEditingController();
    final motivoCtrl = TextEditingController();

    final res = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSt) => AlertDialog(
          title: const Text('Cadastrar novo cupom de desconto'),
          content: SizedBox(
            width: 440,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: codigoCtrl,
                    textCapitalization: TextCapitalization.characters,
                    decoration: const InputDecoration(labelText: 'Código do cupom *', hintText: 'Ex: PRIMEIRACOMPRA, TRATO10'),
                  ),
                  const SizedBox(height: EspacosTrato.x3),
                  DropdownButtonFormField<String>(
                    value: tipo,
                    items: const [
                      DropdownMenuItem(value: 'percentual', child: Text('Desconto em % (ex: 10%)')),
                      DropdownMenuItem(value: 'fixo', child: Text(r'Desconto fixo em R$ (ex: R$ 20,00)')),
                    ],
                    onChanged: (v) {
                      if (v != null) setSt(() => tipo = v);
                    },
                    decoration: const InputDecoration(labelText: 'Tipo de desconto'),
                  ),
                  const SizedBox(height: EspacosTrato.x3),
                  TextField(
                    controller: valorCtrl,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: tipo == 'percentual' ? 'Porcentagem de desconto (ex: 15) *' : 'Valor do desconto em Reais (ex: 20) *',
                      prefixText: tipo == 'percentual' ? '% ' : r'R$ ',
                    ),
                  ),
                  const SizedBox(height: EspacosTrato.x3),
                  TextField(
                    controller: minCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Valor mínimo do pedido em Reais (opcional)', prefixText: r'R$ '),
                  ),
                  const SizedBox(height: EspacosTrato.x3),
                  TextField(
                    controller: limiteCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Limite de utilizações (opcional)', hintText: 'Ex: 100 usos'),
                  ),
                  const SizedBox(height: EspacosTrato.x3),
                  TextField(
                    controller: motivoCtrl,
                    decoration: const InputDecoration(labelText: 'Motivo / Campanha *', hintText: 'Justificativa para auditoria'),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
            FilledButton(
              onPressed: () {
                final cod = codigoCtrl.text.trim();
                final val = double.tryParse(valorCtrl.text.trim()) ?? 0;
                final mot = motivoCtrl.text.trim();
                if (cod.length < 3 || val <= 0 || mot.length < 3) {
                  mostrarAviso(ctx, 'Preencha código, valor e motivo.');
                  return;
                }
                Navigator.pop(ctx, true);
              },
              child: const Text('Criar cupom'),
            ),
          ],
        ),
      ),
    );

    if (res != true || !mounted) return;

    final valNum = double.tryParse(valorCtrl.text.trim()) ?? 0;
    final valorFinal = tipo == 'percentual' ? valNum.toInt() : (valNum * 100).toInt();
    final minNum = double.tryParse(minCtrl.text.trim()) ?? 0;
    final minCentavos = (minNum * 100).toInt();
    final limite = int.tryParse(limiteCtrl.text.trim());

    final ok = await executar(
      context,
      () => context.api.criarCupom(
        codigo: codigoCtrl.text.trim().toUpperCase(),
        tipo: tipo,
        valor: valorFinal,
        valorMinimoCentavos: minCentavos,
        limiteUsos: limite,
        motivo: motivoCtrl.text.trim(),
      ),
      sucesso: 'Cupom criado com sucesso.',
    );
    if (ok && mounted) setState(() => _versao++);
  }

  Future<void> _alternar(CupomAdmin c) async {
    final ativar = !c.ativo;
    final motivo = await pedirMotivo(
      context,
      titulo: ativar ? 'Ativar cupom ${c.codigo}' : 'Desativar cupom ${c.codigo}',
      descricao: ativar ? 'O cupom voltará a ser aceito no checkout do app.' : 'O cupom será pausado para novos pedidos.',
      rotuloConfirmar: ativar ? 'Ativar' : 'Desativar',
    );
    if (motivo == null || !mounted) return;
    final ok = await executar(
      context,
      () => context.api.alterarStatusCupom(c.id, ativo: ativar, motivo: motivo),
      sucesso: 'Cupom atualizado com sucesso.',
    );
    if (ok && mounted) setState(() => _versao++);
  }

  Future<void> _excluir(CupomAdmin c) async {
    final motivo = await pedirMotivo(
      context,
      titulo: 'Remover cupom ${c.codigo}',
      descricao: 'O cupom será excluído permanentemente caso não tenha histórico.',
      rotuloConfirmar: 'Excluir',
    );
    if (motivo == null || !mounted) return;
    final ok = await executar(
      context,
      () => context.api.excluirCupom(c.id, motivo: motivo),
      sucesso: 'Cupom removido.',
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
                'Cupons & Campanhas Promocionais',
                subtitulo: 'Criação e controle de cupons de desconto para clientes',
              ),
            ),
            if (context.pode(Permissao.cuponsGerenciar))
              Padding(
                padding: const EdgeInsets.only(right: EspacosTrato.x6),
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(0, 40),
                    padding: const EdgeInsets.symmetric(horizontal: EspacosTrato.x4),
                  ),
                  onPressed: () => _criar(context),
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Novo cupom'),
                ),
              ),
          ],
        ),
        Expanded(
          child: CarregaDados<List<CupomAdmin>>(
            key: ValueKey('cupons-$_versao'),
            carregar: context.api.listarCupons,
            estaVazio: (l) => l.isEmpty,
            mensagemVazia: 'Nenhum cupom promocional cadastrado.',
            construir: (context, lista, _) => ListView.separated(
              padding: const EdgeInsets.all(EspacosTrato.x6),
              itemCount: lista.length,
              separatorBuilder: (_, _) => const SizedBox(height: EspacosTrato.x3),
              itemBuilder: (context, i) {
                final c = lista[i];
                final desc = c.tipo == 'percentual' ? '${c.valor}% OFF' : '${formatarReais(c.valor)} OFF';
                final min = c.valorMinimoCentavos > 0 ? ' (pedido mín. ${formatarReais(c.valorMinimoCentavos)})' : '';
                final limite = c.limiteUsos != null ? 'Usos: ${c.usosAtuais}/${c.limiteUsos}' : 'Usos: ${c.usosAtuais} (ilimitado)';

                return Card(
                  child: ListTile(
                    leading: const CircleAvatar(
                      backgroundColor: CoresTrato.azulSuave,
                      child: Icon(Icons.local_offer, color: CoresTrato.azulTexto),
                    ),
                    title: Row(
                      children: [
                        Text(c.codigo, style: TipografiaTrato.corpoForte.copyWith(fontWeight: FontWeight.bold)),
                        const SizedBox(width: EspacosTrato.x3),
                        ChipEstado(desc, tom: Tom.info),
                      ],
                    ),
                    subtitle: Text('$limite$min'),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        ChipEstado(c.ativo ? 'Ativo' : 'Inativo', tom: c.ativo ? Tom.ok : Tom.neutro),
                        const SizedBox(width: EspacosTrato.x2),
                        TextButton(
                          onPressed: () => _alternar(c),
                          child: Text(c.ativo ? 'Desativar' : 'Ativar'),
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete_outline, size: 18),
                          tooltip: 'Excluir cupom',
                          onPressed: () => _excluir(c),
                        ),
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
