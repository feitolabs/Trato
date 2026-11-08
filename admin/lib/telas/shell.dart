import 'dart:async';

import 'package:flutter/material.dart';

import '../componentes/base.dart';
import '../dados/modelos.dart';
import '../nucleo/escopo.dart';
import '../nucleo/papeis.dart';
import '../tema/tema.dart';
import 'auditoria_tela.dart';
import 'busca_tela.dart';
import 'config_tela.dart';
import 'cupons_tela.dart';
import 'dashboard_tela.dart';
import 'disputas_tela.dart';
import 'equipe_tela.dart';
import 'notificacoes_tela.dart';
import 'pagamentos_tela.dart';
import 'relatorios_tela.dart';
import 'risco_tela.dart';
import 'verificacao_tela.dart';

/// Sessão que expira após 30 minutos sem uso (RNF-03).
const kSessaoInativaMinutos = 30;

/// Os grupos do menu (DS 4.1): Operação, Financeiro, Crescimento, Administração.
enum GrupoMenu {
  operacao('Operação'),
  financeiro('Financeiro'),
  crescimento('Crescimento'),
  administracao('Administração');

  const GrupoMenu(this.rotulo);
  final String rotulo;
}

/// Uma seção do menu. Só aparece se o papel logado tiver alguma das [permissoes].
class Secao {
  const Secao(this.id, this.rotulo, this.icone, this.grupo, this.permissoes, this.construir);
  final String id;
  final String rotulo;
  final IconData icone;
  final GrupoMenu grupo;
  final List<Permissao> permissoes;
  final Widget Function() construir;
}

/// Todas as seções possíveis, na ordem do menu. O menu mostra só as que o papel pode usar.
final List<Secao> todasSecoes = [
  Secao('verificacao', 'Verificação', IconesTrato.verificacao, GrupoMenu.operacao, [Permissao.verificacoesVer],
      () => const VerificacaoTela()),
  Secao('disputas', 'Disputas', IconesTrato.disputas, GrupoMenu.operacao, [Permissao.disputasVer],
      () => const DisputasTela()),
  Secao(
    'busca',
    'Busca e suporte',
    IconesTrato.buscaSuporte,
    GrupoMenu.operacao,
    [Permissao.usuariosBuscar, Permissao.pedidosBuscar, Permissao.suporteVer, Permissao.categoriasEditar],
    () => const BuscaTela(),
  ),
  Secao('risco', 'Risco e antifraude', IconesTrato.risco, GrupoMenu.operacao, [Permissao.riscoVer],
      () => const RiscoTela()),
  Secao('pagamentos', 'Pagamentos', IconesTrato.pagamentos, GrupoMenu.financeiro, [Permissao.pagamentosVer],
      () => const PagamentosTela()),
  Secao('relatorios', 'Relatórios fiscais', IconesTrato.relatorios, GrupoMenu.financeiro,
      [Permissao.relatoriosExportar], () => const RelatoriosTela()),
  Secao('dashboard', 'Painel', IconesTrato.painel, GrupoMenu.crescimento, [Permissao.dashboardVer],
      () => const DashboardTela()),
  Secao('notificacoes', 'Notificações push', IconesTrato.notificacoes, GrupoMenu.crescimento,
      [Permissao.notificacoesEnviar], () => const NotificacoesTela()),
  Secao('cupons', 'Cupons e promoções', IconesTrato.cupons, GrupoMenu.crescimento, [Permissao.cuponsGerenciar],
      () => const CuponsTela()),
  Secao('equipe', 'Gestão da equipe', IconesTrato.equipe, GrupoMenu.administracao, [Permissao.equipeGerenciar],
      () => const EquipeTela()),
  Secao('config', 'Configurações', IconesTrato.configuracoes, GrupoMenu.administracao, [Permissao.configVer],
      () => const ConfigTela()),
  Secao('auditoria', 'Auditoria', IconesTrato.registroAuditoria, GrupoMenu.administracao, [Permissao.auditoriaVer],
      () => const AuditoriaTela()),
];

/// Os cinco módulos mais usados que ficam na barra inferior no celular (os demais vão em "Mais").
const _maisUsados = ['verificacao', 'disputas', 'busca', 'risco', 'dashboard'];

/// "e••••••@feitolabs.com.br": o e-mail do rodapé fica mascarado (RNF-04).
String mascararEmail(String email) {
  final i = email.indexOf('@');
  if (i <= 1) return email;
  return '${email[0]}${'•' * 6}${email.substring(i)}';
}

class ShellPainel extends StatefulWidget {
  const ShellPainel({super.key, this.ambienteTeste = false, this.inatividade});

  final bool ambienteTeste;

  /// Tempo sem uso até encerrar a sessão (padrão: 30 minutos).
  final Duration? inatividade;

  @override
  State<ShellPainel> createState() => _ShellPainelState();
}

class _ShellPainelState extends State<ShellPainel> {
  String? _idAtual;
  Timer? _timerInatividade;
  Future<int>? _pendentes;

  Duration get _limite => widget.inatividade ?? const Duration(minutes: kSessaoInativaMinutos);

  @override
  void initState() {
    super.initState();
    _reiniciarTimer();
  }

  @override
  void dispose() {
    _timerInatividade?.cancel();
    super.dispose();
  }

  void _reiniciarTimer() {
    _timerInatividade?.cancel();
    _timerInatividade = Timer(_limite, () {
      if (!mounted) return;
      final sessao = context.sessao;
      final api = context.api;
      api.sair().whenComplete(sessao.saiu);
    });
  }

  Future<int> _contarPendentes() async {
    try {
      // Contagem do servidor: antes vinha de uma lista cortada em 100.
      final n = await context.api.contarVerificacoes();
      return (n[StatusVerificacao.enviada] ?? 0) + (n[StatusVerificacao.emAnalise] ?? 0);
    } catch (_) {
      return 0;
    }
  }

  Future<void> _sair() async {
    final sessao = context.sessao;
    final api = context.api;
    try {
      await api.sair();
    } finally {
      sessao.saiu();
    }
  }

  void _ir(String id) => setState(() {
        _idAtual = id;
        _pendentes = null;
      });

  @override
  Widget build(BuildContext context) {
    final usuario = context.eu!;
    final secoes = [
      for (final s in todasSecoes)
        if (s.permissoes.any(context.pode)) s,
    ];
    if (secoes.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: Text(usuario.email), actions: [BotaoTrato.link('Sair', aoPressionar: _sair)]),
        body: const EstadoVazio(
          'Seu papel ainda não tem telas liberadas',
          detalhe: 'Fale com o administrador.',
        ),
      );
    }
    final atual = secoes.firstWhere((s) => s.id == _idAtual, orElse: () => secoes.first);
    if (context.pode(Permissao.verificacoesVer)) _pendentes ??= _contarPendentes();
    final conteudo = KeyedSubtree(key: ValueKey(atual.id), child: atual.construir());

    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) => _reiniciarTimer(),
      onPointerSignal: (_) => _reiniciarTimer(),
      child: Column(
        children: [
          if (widget.ambienteTeste) const _FaixaAmbiente(),
          Expanded(
            child: LayoutBuilder(builder: (context, c) {
              final faixa = FaixaPainel.daLargura(c.maxWidth);
              final pagina = ConteudoLimitado(child: conteudo);
              if (faixa == FaixaPainel.celular) {
                return _LayoutCelular(
                  secoes: secoes,
                  atual: atual,
                  pendentes: _pendentes,
                  aoIr: _ir,
                  usuario: usuario,
                  aoSair: _sair,
                  conteudo: pagina,
                );
              }
              return Scaffold(
                body: Row(
                  children: [
                    _Menu(
                      secoes: secoes,
                      atual: atual,
                      pendentes: _pendentes,
                      aoIr: _ir,
                      usuario: usuario,
                      aoSair: _sair,
                      recolhido: faixa == FaixaPainel.tablet,
                    ),
                    Expanded(child: pagina),
                  ],
                ),
              );
            }),
          ),
        ],
      ),
    );
  }
}

class _FaixaAmbiente extends StatelessWidget {
  const _FaixaAmbiente();

  @override
  Widget build(BuildContext context) {
    return Material(
      color: CoresTrato.avisoFundo,
      child: SafeArea(
        bottom: false,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: EspacosTrato.x1, horizontal: EspacosTrato.x4),
          child: Text(
            'AMBIENTE DE TESTE · os dados deste painel não são de produção',
            textAlign: TextAlign.center,
            style: TipografiaTrato.etiqueta.copyWith(color: CoresTrato.avisoTexto),
          ),
        ),
      ),
    );
  }
}

/// Menu lateral: fixo de 240 px no desktop; recolhido (só ícones) no tablet. Rodapé fixo com
/// nome, e-mail, papel e Sair; só a lista de itens rola.
class _Menu extends StatelessWidget {
  const _Menu({
    required this.secoes,
    required this.atual,
    required this.pendentes,
    required this.aoIr,
    required this.usuario,
    required this.aoSair,
    required this.recolhido,
  });

  final List<Secao> secoes;
  final Secao atual;
  final Future<int>? pendentes;
  final ValueChanged<String> aoIr;
  final UsuarioEquipe usuario;
  final VoidCallback aoSair;
  final bool recolhido;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: recolhido ? EspacosTrato.larguraMenuRecolhido : EspacosTrato.larguraMenu,
      decoration: const BoxDecoration(
        color: CoresTrato.fundoSuperficie,
        border: Border(right: BorderSide(color: CoresTrato.bordaSuave)),
      ),
      child: SafeArea(
        child: Column(
          children: [
            _Marca(recolhido: recolhido),
            Expanded(
              child: ListaMenu(
                secoes: secoes,
                atual: atual,
                pendentes: pendentes,
                aoIr: aoIr,
                recolhido: recolhido,
              ),
            ),
            RodapeMenu(usuario: usuario, aoSair: aoSair, recolhido: recolhido),
          ],
        ),
      ),
    );
  }
}

class _Marca extends StatelessWidget {
  const _Marca({required this.recolhido});
  final bool recolhido;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(EspacosTrato.x4, EspacosTrato.x4, EspacosTrato.x4, EspacosTrato.x2),
      child: Align(
        alignment: recolhido ? Alignment.center : Alignment.centerLeft,
        child: recolhido
            ? Text('T', style: TipografiaTrato.marcaPequena)
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Trato', style: TipografiaTrato.marcaPequena),
                  Text('PAINEL ADMIN', style: TipografiaTrato.sobretitulo),
                ],
              ),
      ),
    );
  }
}

/// Itens do menu agrupados por seção. Também usado dentro da gaveta "Mais" no celular.
class ListaMenu extends StatelessWidget {
  const ListaMenu({
    super.key,
    required this.secoes,
    required this.atual,
    required this.pendentes,
    required this.aoIr,
    this.recolhido = false,
    this.compacto = true,
  });

  /// Desktop: itens de 40 px. No celular (gaveta) ficam com 44 px, a área de toque mínima (RNF-01).
  final bool compacto;
  final List<Secao> secoes;
  final Secao atual;
  final Future<int>? pendentes;
  final ValueChanged<String> aoIr;
  final bool recolhido;

  @override
  Widget build(BuildContext context) {
    final itens = <Widget>[];
    for (final g in GrupoMenu.values) {
      final doGrupo = [for (final s in secoes) if (s.grupo == g) s];
      if (doGrupo.isEmpty) continue;
      itens.add(Padding(
        padding: EdgeInsets.fromLTRB(EspacosTrato.x4, EspacosTrato.x3, EspacosTrato.x4, EspacosTrato.x1),
        child: recolhido
            ? const Divider()
            : Text(g.rotulo.toUpperCase(), style: TipografiaTrato.sobretitulo),
      ));
      for (final s in doGrupo) {
        itens.add(_ItemMenu(
          secao: s,
          ativo: s.id == atual.id,
          pendentes: s.id == 'verificacao' ? pendentes : null,
          aoTocar: () => aoIr(s.id),
          recolhido: recolhido,
          compacto: compacto,
        ));
      }
    }
    return ListView(padding: const EdgeInsets.only(bottom: EspacosTrato.x2), children: itens);
  }
}

class _ItemMenu extends StatelessWidget {
  const _ItemMenu({
    required this.secao,
    required this.ativo,
    required this.pendentes,
    required this.aoTocar,
    required this.recolhido,
    required this.compacto,
  });

  final bool compacto;
  final Secao secao;
  final bool ativo;
  final Future<int>? pendentes;
  final VoidCallback aoTocar;
  final bool recolhido;

  @override
  Widget build(BuildContext context) {
    final cor = ativo ? CoresTrato.primaria : CoresTrato.textoMudo;
    final contador = pendentes == null
        ? null
        : FutureBuilder<int>(
            future: pendentes,
            builder: (context, snap) {
              final n = snap.data ?? 0;
              if (n == 0) return const SizedBox.shrink();
              // Brasa: o único ponto de destaque da tela, como contador (nunca texto).
              return Container(
                constraints: const BoxConstraints(minWidth: 20),
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: CoresTrato.brasa,
                  borderRadius: BorderRadius.circular(EspacosTrato.raioPilula),
                ),
                child: Text(
                  '$n',
                  textAlign: TextAlign.center,
                  semanticsLabel: '$n pendentes',
                  style: TipografiaTrato.etiqueta.copyWith(color: CoresTrato.primaria),
                ),
              );
            },
          );

    final Widget corpo = recolhido
        ? Center(child: Icon(secao.icone, size: 20, color: cor))
        : Row(
            children: [
              Icon(secao.icone, size: 20, color: cor),
              const SizedBox(width: EspacosTrato.x3),
              Expanded(
                child: Text(
                  secao.rotulo,
                  overflow: TextOverflow.ellipsis,
                  style: TipografiaTrato.corpoForte.copyWith(color: cor),
                ),
              ),
              if (contador != null) contador,
            ],
          );

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: EspacosTrato.x2),
      child: Semantics(
        selected: ativo,
        button: true,
        label: secao.rotulo,
        child: Tooltip(
          message: recolhido ? secao.rotulo : '',
          child: Material(
            color: ativo ? CoresTrato.fundoSelecionado : CoresTrato.transparente,
            borderRadius: BorderRadius.circular(EspacosTrato.raio),
            child: InkWell(
              key: ValueKey('menu-${secao.id}'),
              borderRadius: BorderRadius.circular(EspacosTrato.raio),
              onTap: aoTocar,
              child: Container(
                constraints: BoxConstraints(minHeight: compacto ? 40 : EspacosTrato.alturaBotao),
                padding: const EdgeInsets.symmetric(horizontal: EspacosTrato.x3),
                child: corpo,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Rodapé fixo: nome, e-mail mascarado, papel e Sair.
class RodapeMenu extends StatelessWidget {
  const RodapeMenu({super.key, required this.usuario, required this.aoSair, this.recolhido = false});

  final UsuarioEquipe usuario;
  final VoidCallback aoSair;
  final bool recolhido;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: EspacosTrato.x4, vertical: EspacosTrato.x3),
      decoration: const BoxDecoration(border: Border(top: BorderSide(color: CoresTrato.bordaSuave))),
      child: recolhido
          ? Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Tooltip(
                  message: '${usuario.nome} · ${usuario.papel.rotulo}',
                  child: CircleAvatar(
                    radius: 16,
                    backgroundColor: CoresTrato.primaria,
                    child: Text(
                      usuario.nome.isNotEmpty ? usuario.nome[0].toUpperCase() : 'E',
                      style: TipografiaTrato.etiqueta.copyWith(color: CoresTrato.textoSobrePrimaria),
                    ),
                  ),
                ),
                BotaoIcone(icone: IconesTrato.sair, rotulo: 'Sair', aoPressionar: aoSair),
              ],
            )
          : Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(usuario.nome, style: TipografiaTrato.corpoForte, overflow: TextOverflow.ellipsis),
                Text(mascararEmail(usuario.email), style: TipografiaTrato.legenda, overflow: TextOverflow.ellipsis),
                const SizedBox(height: EspacosTrato.x2),
                ChipPapel(usuario.papel.rotulo),
                const SizedBox(height: EspacosTrato.x2),
                BotaoTrato.link('Sair', aoPressionar: aoSair, icone: IconesTrato.sair),
              ],
            ),
    );
  }
}

/// Celular: título no topo, barra inferior com os cinco módulos mais usados e "Mais".
class _LayoutCelular extends StatelessWidget {
  const _LayoutCelular({
    required this.secoes,
    required this.atual,
    required this.pendentes,
    required this.aoIr,
    required this.usuario,
    required this.aoSair,
    required this.conteudo,
  });

  final List<Secao> secoes;
  final Secao atual;
  final Future<int>? pendentes;
  final ValueChanged<String> aoIr;
  final UsuarioEquipe usuario;
  final VoidCallback aoSair;
  final Widget conteudo;

  @override
  Widget build(BuildContext context) {
    final fixas = [
      for (final id in _maisUsados)
        for (final s in secoes)
          if (s.id == id) s,
    ].take(5).toList();
    final naBarra = fixas.any((s) => s.id == atual.id);

    void abrirMais() {
      showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        builder: (ctx) => Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: ListaMenu(
                secoes: secoes,
                atual: atual,
                pendentes: pendentes,
                aoIr: (id) {
                  Navigator.of(ctx).pop();
                  aoIr(id);
                },
                compacto: false,
              ),
            ),
            RodapeMenu(usuario: usuario, aoSair: aoSair),
          ],
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Text('Trato', style: TipografiaTrato.marcaPequena),
            const SizedBox(width: EspacosTrato.x3),
            Expanded(
              child: Text(atual.rotulo, overflow: TextOverflow.ellipsis, style: TipografiaTrato.legenda),
            ),
          ],
        ),
        shape: const Border(bottom: BorderSide(color: CoresTrato.bordaSuave)),
      ),
      body: conteudo,
      bottomNavigationBar: SafeArea(
        child: Container(
          decoration: const BoxDecoration(
            color: CoresTrato.fundoSuperficie,
            border: Border(top: BorderSide(color: CoresTrato.bordaSuave)),
          ),
          child: Row(
            children: [
              for (final s in fixas)
                Expanded(
                  child: _ItemBarra(
                    key: ValueKey('menu-${s.id}'),
                    icone: s.icone,
                    rotulo: s.rotulo.split(' ').first,
                    ativo: s.id == atual.id,
                    aoTocar: () => aoIr(s.id),
                  ),
                ),
              Expanded(
                child: _ItemBarra(
                  key: const ValueKey('menu-mais'),
                  icone: IconesTrato.mais,
                  rotulo: 'Mais',
                  ativo: !naBarra,
                  aoTocar: abrirMais,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ItemBarra extends StatelessWidget {
  const _ItemBarra({super.key, required this.icone, required this.rotulo, required this.ativo, required this.aoTocar});
  final IconData icone;
  final String rotulo;
  final bool ativo;
  final VoidCallback aoTocar;

  @override
  Widget build(BuildContext context) {
    final cor = ativo ? CoresTrato.primaria : CoresTrato.textoMudo;
    return Semantics(
      selected: ativo,
      button: true,
      label: rotulo,
      child: InkWell(
        onTap: aoTocar,
        child: Container(
          constraints: const BoxConstraints(minHeight: 56),
          padding: const EdgeInsets.symmetric(vertical: EspacosTrato.x2),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: EspacosTrato.x4, vertical: 2),
                decoration: BoxDecoration(
                  color: ativo ? CoresTrato.fundoSelecionado : CoresTrato.transparente,
                  borderRadius: BorderRadius.circular(EspacosTrato.raioPilula),
                ),
                child: Icon(icone, size: 20, color: cor),
              ),
              Text(rotulo, style: TipografiaTrato.etiqueta.copyWith(color: cor), overflow: TextOverflow.ellipsis),
            ],
          ),
        ),
      ),
    );
  }
}
