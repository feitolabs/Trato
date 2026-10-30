import 'package:flutter/material.dart';

import '../componentes/base.dart';
import '../dados/modelos.dart';
import '../nucleo/escopo.dart';
import '../nucleo/formato.dart';
import '../nucleo/papeis.dart';
import '../tema/tema.dart';

/// F7.4 — busca de usuários e pedidos, suporte e categorias. Cada aba depende do papel.
class BuscaTela extends StatelessWidget {
  const BuscaTela({super.key});

  @override
  Widget build(BuildContext context) {
    final abas = <(String, Widget)>[
      if (context.pode(Permissao.usuariosBuscar)) ('Usuários', const _AbaUsuarios()),
      if (context.pode(Permissao.pedidosBuscar)) ('Pedidos', const _AbaPedidos()),
      if (context.pode(Permissao.suporteVer)) ('Suporte', const _AbaSuporte()),
      if (context.pode(Permissao.categoriasEditar)) ('Categorias', const _AbaCategorias()),
    ];
    return DefaultTabController(
      length: abas.length,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const CabecalhoPagina('Busca e suporte', subtitulo: 'Usuários, pedidos, chamados e categorias'),
          TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            tabs: [for (final a in abas) Tab(text: a.$1)],
          ),
          Expanded(child: TabBarView(children: [for (final a in abas) a.$2])),
        ],
      ),
    );
  }
}

/// Campo de busca + resultado. O resultado é recarregado a cada "Buscar".
class _Busca<T> extends StatefulWidget {
  const _Busca({
    required this.rotulo,
    required this.buscar,
    required this.linha,
    required this.mensagemVazia,
  });

  final String rotulo;
  final Future<List<T>> Function(String termo) buscar;
  final Widget Function(BuildContext context, T item, Future<void> Function() recarregar) linha;
  final String mensagemVazia;

  @override
  State<_Busca<T>> createState() => _BuscaState<T>();
}

class _BuscaState<T> extends State<_Busca<T>> {
  final _controle = TextEditingController();
  String _termo = '';
  int _versao = 0;

  @override
  void dispose() {
    _controle.dispose();
    super.dispose();
  }

  void _buscar() => setState(() {
        _termo = _controle.text;
        _versao++;
      });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(EspacosTrato.x4),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _controle,
                  onSubmitted: (_) => _buscar(),
                  decoration: InputDecoration(labelText: widget.rotulo, prefixIcon: const Icon(Icons.search)),
                ),
              ),
              const SizedBox(width: EspacosTrato.x3),
              SizedBox(width: 120, child: FilledButton(onPressed: _buscar, child: const Text('Buscar'))),
            ],
          ),
        ),
        Expanded(
          child: CarregaDados<List<T>>(
            key: ValueKey('$_termo#$_versao'),
            carregar: () => widget.buscar(_termo),
            estaVazio: (l) => l.isEmpty,
            mensagemVazia: widget.mensagemVazia,
            construir: (context, lista, recarregar) => ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: EspacosTrato.x4),
              itemCount: lista.length,
              separatorBuilder: (_, _) => const SizedBox(height: EspacosTrato.x2),
              itemBuilder: (context, i) => widget.linha(context, lista[i], recarregar),
            ),
          ),
        ),
      ],
    );
  }
}

class _AbaUsuarios extends StatelessWidget {
  const _AbaUsuarios();

  @override
  Widget build(BuildContext context) {
    return _Busca<UsuarioBusca>(
      rotulo: 'Buscar usuário por nome',
      mensagemVazia: 'Nenhum usuário encontrado.',
      buscar: context.api.buscarUsuarios,
      linha: (context, u, _) => _CartaoUsuario(usuario: u),
    );
  }
}

class _CartaoUsuario extends StatefulWidget {
  const _CartaoUsuario({required this.usuario});
  final UsuarioBusca usuario;

  @override
  State<_CartaoUsuario> createState() => _CartaoUsuarioState();
}

class _CartaoUsuarioState extends State<_CartaoUsuario> {
  DadosPessoais? _dados;

  Future<void> _revelar() async {
    final api = context.api;
    final motivo = await pedirMotivo(
      context,
      titulo: 'Ver dados pessoais',
      descricao: 'E-mail, CPF e telefone ficam escondidos por padrão (LGPD).',
      rotuloConfirmar: 'Revelar',
    );
    if (motivo == null || !mounted) return;
    try {
      final d = await api.revelarDadosPessoais(widget.usuario.id, motivo);
      if (mounted) setState(() => _dados = d);
    } catch (e) {
      if (mounted) mostrarAviso(context, e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    final u = widget.usuario;
    final d = _dados;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(EspacosTrato.x4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(child: Text(u.nome, style: TipografiaTrato.tituloCartao)),
                ChipEstado(u.tipo, tom: Tom.info),
                const SizedBox(width: EspacosTrato.x2),
                ChipEstado(u.status, tom: u.status == 'ativo' ? Tom.ok : Tom.alerta),
              ],
            ),
            const SizedBox(height: EspacosTrato.x2),
            if ((d?.email ?? u.emailMascarado) != null) Linha('E-mail', (d?.email ?? u.emailMascarado)!),
            if ((d?.cpf ?? u.cpfMascarado) != null) Linha('CPF', (d?.cpf ?? u.cpfMascarado)!),
            if (d != null) Linha('Telefone', d.telefone),
            if (d?.nascimento != null) Linha('Nascimento', d!.nascimento!),
            if (d == null && context.pode(Permissao.dadosPessoaisRevelar))
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(onPressed: _revelar, child: const Text('Revelar dados pessoais')),
              ),
          ],
        ),
      ),
    );
  }
}

class _AbaPedidos extends StatelessWidget {
  const _AbaPedidos();

  @override
  Widget build(BuildContext context) {
    return _Busca<PedidoBusca>(
      rotulo: 'Buscar pedido por código ou título',
      mensagemVazia: 'Nenhum pedido encontrado.',
      buscar: context.api.buscarPedidos,
      linha: (context, p, _) => Card(
        child: ListTile(
          title: Text('${p.id} · ${p.titulo}'),
          subtitle: Text('${p.cliente} · ${p.status}'),
          trailing: Text(formatarReais(p.valorCentavos), style: TipografiaTrato.corpoForte),
        ),
      ),
    );
  }
}

class _AbaSuporte extends StatelessWidget {
  const _AbaSuporte();

  @override
  Widget build(BuildContext context) {
    return CarregaDados<List<Chamado>>(
      carregar: context.api.listarChamados,
      estaVazio: (l) => l.isEmpty,
      mensagemVazia: 'Nenhum chamado aberto.',
      construir: (context, lista, _) => ListView.separated(
        padding: const EdgeInsets.all(EspacosTrato.x4),
        itemCount: lista.length,
        separatorBuilder: (_, _) => const SizedBox(height: EspacosTrato.x2),
        itemBuilder: (context, i) {
          final c = lista[i];
          return Card(
            child: ListTile(
              title: Text('${c.id} · ${c.assunto}'),
              subtitle: Text('${c.solicitante} · aberto em ${formatarData(c.aberto)}'),
              trailing: ChipEstado(c.status, tom: c.status == 'aberto' ? Tom.alerta : Tom.info),
            ),
          );
        },
      ),
    );
  }
}

class _AbaCategorias extends StatelessWidget {
  const _AbaCategorias();

  Future<void> _alternar(BuildContext context, CategoriaAdmin c, Future<void> Function() recarregar) async {
    final api = context.api;
    final ativar = !c.ativa;
    final motivo = await pedirMotivo(
      context,
      titulo: ativar ? 'Ativar ${c.nome}' : 'Desativar ${c.nome}',
      descricao: ativar
          ? 'A categoria volta a aparecer para novos pedidos.'
          : 'A categoria sai da lista de novos pedidos. Pedidos em andamento seguem normalmente.',
      rotuloConfirmar: ativar ? 'Ativar' : 'Desativar',
    );
    if (motivo == null || !context.mounted) return;
    final ok = await executar(context, () => api.alterarCategoria(c.id, ativa: ativar, motivo: motivo),
        sucesso: 'Categoria atualizada.');
    if (ok) await recarregar();
  }

  @override
  Widget build(BuildContext context) {
    return CarregaDados<List<CategoriaAdmin>>(
      carregar: context.api.listarCategorias,
      estaVazio: (l) => l.isEmpty,
      mensagemVazia: 'Nenhuma categoria cadastrada.',
      construir: (context, lista, recarregar) => ListView.separated(
        padding: const EdgeInsets.all(EspacosTrato.x4),
        itemCount: lista.length,
        separatorBuilder: (_, _) => const SizedBox(height: EspacosTrato.x2),
        itemBuilder: (context, i) {
          final c = lista[i];
          return Card(
            child: ListTile(
              title: Text(c.nome),
              subtitle: Text('${c.profissionais} profissionais'),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ChipEstado(c.ativa ? 'Ativa' : 'Inativa', tom: c.ativa ? Tom.ok : Tom.neutro),
                  const SizedBox(width: EspacosTrato.x2),
                  TextButton(
                    onPressed: () => _alternar(context, c, recarregar),
                    child: Text(c.ativa ? 'Desativar' : 'Ativar'),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
