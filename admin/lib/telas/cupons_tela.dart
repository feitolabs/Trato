import 'package:flutter/material.dart';

import '../componentes/base.dart';
import '../dados/modelos.dart';
import '../nucleo/escopo.dart';
import '../nucleo/formato.dart';
import '../nucleo/papeis.dart';
import '../tema/tema.dart';

/// Cupons e promoções (RF-CUP-01 a RF-CUP-03).
class CuponsTela extends StatefulWidget {
  const CuponsTela({super.key});

  @override
  State<CuponsTela> createState() => _CuponsTelaState();
}

class _CuponsTelaState extends State<CuponsTela> {
  int _versao = 0;

  static String _dia(String? iso) {
    final d = iso == null ? null : DateTime.tryParse(iso);
    return d == null ? '' : formatarDia(d.toLocal());
  }

  static String descontoDe(CupomAdmin c) => c.tipo == 'percentual' ? '${c.valor}%' : formatarReais(c.valor);

  Future<void> _criar(List<CupomAdmin> existentes) async {
    final codigo = TextEditingController();
    final valor = TextEditingController();
    final minimo = TextEditingController();
    final limite = TextEditingController();
    final porUsuario = TextEditingController();
    final campanha = TextEditingController();
    var tipo = 'percentual';
    DateTime? inicio;
    DateTime? fim;

    String? erroCodigo() {
      final c = codigo.text.trim();
      if (c.isEmpty) return null;
      if (RegExp(r'\s').hasMatch(c)) return 'O código não pode ter espaços';
      if (existentes.any((e) => e.codigo == c.toUpperCase())) return 'Esse código já existe';
      return null;
    }

    String? erroValor() {
      if (valor.text.trim().isEmpty) return null;
      if (tipo == 'percentual') {
        final v = int.tryParse(valor.text.trim());
        return v == null || v < 1 || v > 100 ? 'Entre 1 e 100' : null;
      }
      final v = lerReaisEmCentavos(valor.text);
      return v == null || v <= 0 ? 'Informe um valor em reais' : null;
    }

    String? erroFim() => inicio != null && fim != null && !fim!.isAfter(inicio!) ? 'O fim precisa ser depois do início' : null;

    final r = await pedirFormulario<Map<String, Object?>>(
      context,
      titulo: 'Novo cupom',
      consequencia: 'O cupom já nasce ativo e vale no pedido de quem usar o código.',
      rotuloConfirmar: 'Criar cupom',
      campos: (ctx, rebuild) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: codigo,
            textCapitalization: TextCapitalization.characters,
            onChanged: (_) => rebuild(),
            decoration: InputDecoration(labelText: 'Código', helperText: 'Ex.: BEMVINDO10', errorText: erroCodigo()),
          ),
          const SizedBox(height: EspacosTrato.x3),
          Wrap(
            spacing: EspacosTrato.x2,
            children: [
              ChoiceChip(
                label: const Text('Percentual'),
                selected: tipo == 'percentual',
                onSelected: (_) {
                  tipo = 'percentual';
                  rebuild();
                },
                materialTapTargetSize: MaterialTapTargetSize.padded,
              ),
              ChoiceChip(
                label: const Text('Valor fixo'),
                selected: tipo == 'fixo',
                onSelected: (_) {
                  tipo = 'fixo';
                  rebuild();
                },
                materialTapTargetSize: MaterialTapTargetSize.padded,
              ),
            ],
          ),
          const SizedBox(height: EspacosTrato.x3),
          TextField(
            controller: valor,
            keyboardType: TextInputType.number,
            onChanged: (_) => rebuild(),
            decoration: InputDecoration(
              labelText: 'Valor',
              prefixText: tipo == 'percentual' ? null : 'R\$ ',
              suffixText: tipo == 'percentual' ? '%' : null,
              helperText: tipo == 'percentual' ? 'Entre 1 e 100' : null,
              errorText: erroValor(),
            ),
          ),
          const SizedBox(height: EspacosTrato.x3),
          TextField(
            controller: minimo,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'Pedido mínimo', prefixText: 'R\$ ', helperText: 'Vazio = sem mínimo'),
          ),
          const SizedBox(height: EspacosTrato.x3),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: limite,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Limite total de usos'),
                ),
              ),
              const SizedBox(width: EspacosTrato.x3),
              Expanded(
                child: TextField(
                  controller: porUsuario,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Por usuário'),
                ),
              ),
            ],
          ),
          const SizedBox(height: EspacosTrato.x3),
          Row(
            children: [
              Expanded(
                child: CampoData(
                  rotulo: 'Início',
                  valor: inicio,
                  aoMudar: (d) {
                    inicio = d;
                    rebuild();
                  },
                ),
              ),
              const SizedBox(width: EspacosTrato.x3),
              Expanded(
                child: CampoData(
                  rotulo: 'Fim',
                  valor: fim,
                  erro: erroFim(),
                  aoMudar: (d) {
                    fim = d;
                    rebuild();
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: EspacosTrato.x3),
          TextField(
            controller: campanha,
            decoration: const InputDecoration(labelText: 'Campanha', helperText: 'Ex.: Boas-vindas'),
          ),
        ],
      ),
      camposValidos: () =>
          codigo.text.trim().length >= 3 &&
          erroCodigo() == null &&
          valor.text.trim().isNotEmpty &&
          erroValor() == null &&
          erroFim() == null,
      resultado: (motivo) => {
        'codigo': codigo.text.trim().toUpperCase(),
        'tipo': tipo,
        'valor': tipo == 'percentual' ? int.parse(valor.text.trim()) : lerReaisEmCentavos(valor.text)!,
        'minimo': lerReaisEmCentavos(minimo.text) ?? 0,
        'limite': int.tryParse(limite.text.trim()),
        'porUsuario': int.tryParse(porUsuario.text.trim()),
        'inicio': inicio?.toIso8601String().substring(0, 10),
        'fim': fim?.toIso8601String().substring(0, 10),
        'campanha': campanha.text.trim(),
        'motivo': motivo,
      },
    );
    if (r == null || !mounted) return;
    final ok = await executar(
      context,
      () => context.api.criarCupom(
        codigo: r['codigo']! as String,
        tipo: r['tipo']! as String,
        valor: r['valor']! as int,
        valorMinimoCentavos: r['minimo']! as int,
        limiteUsos: r['limite'] as int?,
        limitePorUsuario: r['porUsuario'] as int?,
        validoDesde: r['inicio'] as String?,
        validoAte: r['fim'] as String?,
        campanha: r['campanha'] as String?,
        motivo: r['motivo']! as String,
      ),
      sucesso: 'Cupom criado.',
    );
    if (ok && mounted) setState(() => _versao++);
  }

  Future<void> _alternar(CupomAdmin c) async {
    final ativar = !c.ativo;
    final motivo = await pedirMotivo(
      context,
      titulo: ativar ? 'Ativar o cupom ${c.codigo}?' : 'Desativar o cupom ${c.codigo}?',
      descricao: ativar
          ? 'O cupom volta a ser aceito no pedido.'
          : 'O cupom deixa de ser aceito em novos pedidos. O histórico de usos fica preservado.',
      rotuloConfirmar: ativar ? 'Ativar cupom' : 'Desativar cupom',
    );
    if (motivo == null || !mounted) return;
    final ok = await executar(
      context,
      () => context.api.alterarStatusCupom(c.id, ativo: ativar, motivo: motivo),
      sucesso: ativar ? 'Cupom ativado.' : 'Cupom desativado.',
    );
    if (ok && mounted) setState(() => _versao++);
  }

  Future<void> _excluir(CupomAdmin c) async {
    final motivo = await pedirMotivo(
      context,
      titulo: 'Excluir o cupom ${c.codigo}?',
      descricao: 'Ele nunca foi usado, então pode ser excluído. A exclusão não pode ser desfeita.',
      rotuloConfirmar: 'Excluir cupom',
      destrutivo: true,
    );
    if (motivo == null || !mounted) return;
    final ok = await executar(
      context,
      () => context.api.excluirCupom(c.id, motivo: motivo),
      sucesso: 'Cupom excluído.',
    );
    if (ok && mounted) setState(() => _versao++);
  }

  @override
  Widget build(BuildContext context) {
    final podeGerenciar = context.pode(Permissao.cuponsGerenciar);
    return CarregaDados<List<CupomAdmin>>(
      key: ValueKey('cupons-$_versao'),
      carregar: context.api.listarCupons,
      construir: (context, lista, _) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          CabecalhoPagina(
            'Cupons e promoções',
            subtitulo: 'Desativar preserva o histórico. Excluir só vale para cupom nunca usado.',
            acoes: [
              if (podeGerenciar)
                BotaoTrato.primario('Novo cupom', icone: IconesTrato.adicionar, aoPressionar: () => _criar(lista)),
            ],
          ),
          Expanded(
            child: ListaPaginada<CupomAdmin>(
              itens: lista,
              mensagemVazia: 'Nenhum cupom cadastrado',
              detalheVazio: 'Crie o primeiro cupom para incentivar novos pedidos.',
              rotuloBusca: 'Buscar cupom por código ou campanha',
              rotuloItens: 'cupons',
              textoBusca: (c) => '${c.codigo} ${c.campanha ?? ''}',
              filtros: [
                FiltroLista<CupomAdmin>(
                  rotulo: 'Status',
                  opcoes: const [('ativo', 'Ativo'), ('inativo', 'Inativo')],
                  aplica: (c, v) => (v == 'ativo') == c.ativo,
                ),
              ],
              construirItem: (context, c) => CartaoLista(
                tituloWidget: Wrap(
                  spacing: EspacosTrato.x2,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(c.codigo, style: TipografiaTrato.corpoForte),
                    ChipEstado(c.ativo ? 'Ativo' : 'Inativo', tom: c.ativo ? Tom.ok : Tom.neutro),
                    if (c.campanha != null && c.campanha!.isNotEmpty) ChipPapel(c.campanha!),
                  ],
                ),
                titulo: c.codigo,
                linhas: [
                  [
                    descontoDe(c),
                    if (c.valorMinimoCentavos > 0) 'pedido mínimo ${formatarReais(c.valorMinimoCentavos)}',
                    if (c.limitePorUsuario != null) '${c.limitePorUsuario} por usuário',
                    if (_dia(c.validoAte).isNotEmpty) 'até ${_dia(c.validoAte)}',
                  ].join(' · '),
                  '${c.usosAtuais} de ${c.limiteUsos ?? 'ilimitados'} usos',
                  if (c.usosAtuais == 0) 'Nunca usado',
                ],
                acoes: [
                  if (podeGerenciar) BotaoTrato.link(c.ativo ? 'Desativar' : 'Ativar', aoPressionar: () => _alternar(c)),
                  if (podeGerenciar && c.usosAtuais == 0)
                    BotaoIcone(
                      icone: IconesTrato.excluir,
                      rotulo: 'Excluir ${c.codigo}',
                      destrutivo: true,
                      aoPressionar: () => _excluir(c),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
