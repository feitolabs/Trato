import 'package:flutter/material.dart';

import '../componentes/base.dart';
import '../nucleo/escopo.dart';
import '../nucleo/papeis.dart';
import '../tema/tema.dart';
import 'auditoria_tela.dart';
import 'busca_tela.dart';
import 'config_tela.dart';
import 'disputas_tela.dart';
import 'pagamentos_tela.dart';
import 'verificacao_tela.dart';

/// Uma seção do menu. Só aparece se o papel logado tiver alguma das [permissoes].
class Secao {
  const Secao(this.id, this.rotulo, this.icone, this.permissoes, this.construir);
  final String id;
  final String rotulo;
  final IconData icone;
  final List<Permissao> permissoes;
  final Widget Function() construir;
}

/// Todas as seções possíveis. O menu mostra só as que o papel pode usar.
final List<Secao> todasSecoes = [
  Secao('verificacao', 'Verificação', Icons.verified_user_outlined, [Permissao.verificacoesVer],
      () => const VerificacaoTela()),
  Secao('disputas', 'Disputas', Icons.gavel_outlined, [Permissao.disputasVer], () => const DisputasTela()),
  Secao('pagamentos', 'Pagamentos', Icons.account_balance_outlined, [Permissao.pagamentosVer],
      () => const PagamentosTela()),
  Secao(
    'busca',
    'Busca e suporte',
    Icons.search,
    [Permissao.usuariosBuscar, Permissao.pedidosBuscar, Permissao.suporteVer, Permissao.categoriasEditar],
    () => const BuscaTela(),
  ),
  Secao('config', 'Configurações', Icons.tune, [Permissao.configVer], () => const ConfigTela()),
  Secao('auditoria', 'Auditoria', Icons.fact_check_outlined, [Permissao.auditoriaVer], () => const AuditoriaTela()),
];

class ShellPainel extends StatefulWidget {
  const ShellPainel({super.key});

  @override
  State<ShellPainel> createState() => _ShellPainelState();
}

class _ShellPainelState extends State<ShellPainel> {
  int _indice = 0;

  Future<void> _sair() async {
    final sessao = context.sessao;
    final api = context.api;
    try {
      await api.sair();
    } finally {
      sessao.saiu();
    }
  }

  Widget _menu(List<Secao> secoes, int atual, {required bool gaveta}) {
    return ListView(
      children: [
        for (var i = 0; i < secoes.length; i++)
          ListTile(
            key: ValueKey('menu-${secoes[i].id}'),
            leading: Icon(secoes[i].icone),
            title: Text(secoes[i].rotulo),
            selected: i == atual,
            selectedTileColor: CoresTrato.azulSuave,
            selectedColor: CoresTrato.azulTexto,
            onTap: () {
              if (gaveta) Navigator.of(context).pop();
              setState(() => _indice = i);
            },
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final usuario = context.eu!;
    final secoes = [
      for (final s in todasSecoes)
        if (s.permissoes.any(context.pode)) s,
    ];
    if (secoes.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: Text(usuario.email), actions: [TextButton(onPressed: _sair, child: const Text('Sair'))]),
        body: const EstadoVazio('Seu papel ainda não tem telas liberadas. Fale com o administrador.'),
      );
    }
    final atual = _indice < secoes.length ? _indice : 0;
    final conteudo = KeyedSubtree(key: ValueKey(secoes[atual].id), child: secoes[atual].construir());

    final rodape = Padding(
      padding: const EdgeInsets.all(EspacosTrato.x4),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(usuario.email, style: TipografiaTrato.legenda, overflow: TextOverflow.ellipsis),
          const SizedBox(height: EspacosTrato.x1),
          ChipEstado(usuario.papel.rotulo, tom: Tom.info),
          const SizedBox(height: EspacosTrato.x2),
          TextButton(onPressed: _sair, child: const Text('Sair')),
        ],
      ),
    );
    final marca = Padding(
      padding: const EdgeInsets.all(EspacosTrato.x6),
      child: Align(alignment: Alignment.centerLeft, child: Text('Trato', style: TipografiaTrato.marcaPequena)),
    );

    return LayoutBuilder(builder: (context, c) {
      if (c.maxWidth >= kLarguraDesktop) {
        return Scaffold(
          body: Row(
            children: [
              SizedBox(
                width: 260,
                child: Material(
                  color: CoresTrato.superficie,
                  child: Column(children: [marca, Expanded(child: _menu(secoes, atual, gaveta: false)), rodape]),
                ),
              ),
              const VerticalDivider(width: 1),
              Expanded(child: conteudo),
            ],
          ),
        );
      }
      return Scaffold(
        appBar: AppBar(title: Text(secoes[atual].rotulo, style: TipografiaTrato.tituloCartao)),
        drawer: Drawer(
          child: SafeArea(
            child: Column(children: [marca, Expanded(child: _menu(secoes, atual, gaveta: true)), rodape]),
          ),
        ),
        body: conteudo,
      );
    });
  }
}
