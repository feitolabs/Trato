import 'package:flutter/material.dart';

import '../componentes/base.dart';
import '../dados/modelos.dart';
import '../nucleo/escopo.dart';
import '../nucleo/formato.dart';
import '../nucleo/papeis.dart';
import '../tema/tema.dart';

/// F7.4 — busca de usuários e pedidos, suporte, categorias e cidades. Cada aba depende do papel.
class BuscaTela extends StatelessWidget {
  const BuscaTela({super.key});

  @override
  Widget build(BuildContext context) {
    final abas = <(String, Widget)>[
      if (context.pode(Permissao.usuariosBuscar)) ('Usuários', const _AbaUsuarios()),
      if (context.pode(Permissao.pedidosBuscar)) ('Pedidos', const _AbaPedidos()),
      if (context.pode(Permissao.suporteVer)) ('Suporte', const _AbaSuporte()),
      if (context.pode(Permissao.categoriasEditar)) ('Categorias', const _AbaCategorias()),
      if (context.pode(Permissao.categoriasEditar)) ('Cidades', const _AbaCidades()),
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
      linha: (context, u, recarregar) => _CartaoUsuario(usuario: u, aoMudar: recarregar),
    );
  }
}

class _CartaoUsuario extends StatefulWidget {
  const _CartaoUsuario({required this.usuario, this.aoMudar});
  final UsuarioBusca usuario;
  final Future<void> Function()? aoMudar;

  @override
  State<_CartaoUsuario> createState() => _CartaoUsuarioState();
}

class _CartaoUsuarioState extends State<_CartaoUsuario> {
  DadosPessoais? _dados;
  String? _statusAtual;

  @override
  void initState() {
    super.initState();
    _statusAtual = widget.usuario.status;
  }

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

  Future<void> _alterarStatus() async {
    final res = await _dialogAlterarStatus(context, widget.usuario.nome, _statusAtual ?? widget.usuario.status);
    if (res == null || !mounted) return;
    final ok = await executar(
      context,
      () => context.api.alterarStatusUsuario(widget.usuario.id, status: res.$1, motivo: res.$2),
      sucesso: 'Status alterado para "${res.$1}".',
    );
    if (ok && mounted) {
      setState(() => _statusAtual = res.$1);
      if (widget.aoMudar != null) await widget.aoMudar!();
    }
  }

  @override
  Widget build(BuildContext context) {
    final u = widget.usuario;
    final d = _dados;
    final status = _statusAtual ?? u.status;
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
                ChipEstado(status, tom: status == 'ativo' ? Tom.ok : Tom.alerta),
              ],
            ),
            const SizedBox(height: EspacosTrato.x2),
            if ((d?.email ?? u.emailMascarado) != null) Linha('E-mail', (d?.email ?? u.emailMascarado)!),
            if ((d?.cpf ?? u.cpfMascarado) != null) Linha('CPF', (d?.cpf ?? u.cpfMascarado)!),
            if (d != null) Linha('Telefone', d.telefone),
            if (d?.nascimento != null) Linha('Nascimento', d!.nascimento!),
            const SizedBox(height: EspacosTrato.x2),
            Row(
              children: [
                if (d == null && context.pode(Permissao.dadosPessoaisRevelar))
                  TextButton(onPressed: _revelar, child: const Text('Revelar dados pessoais')),
                const Spacer(),
                TextButton.icon(
                  onPressed: _alterarStatus,
                  icon: const Icon(Icons.manage_accounts_outlined, size: 16),
                  label: const Text('Alterar status'),
                ),
              ],
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

  Future<void> _criar(BuildContext context, Future<void> Function() recarregar) async {
    final dados = await _dialogCategoria(context);
    if (dados == null || !context.mounted) return;
    final ok = await executar(
      context,
      () => context.api.criarCategoria(
        nome: dados.nome,
        slug: dados.slug,
        icone: dados.icone,
        garantiaDias: dados.garantiaDias,
        motivo: dados.motivo,
      ),
      sucesso: 'Categoria "${dados.nome}" criada com sucesso.',
    );
    if (ok) await recarregar();
  }

  Future<void> _editar(BuildContext context, CategoriaAdmin c, Future<void> Function() recarregar) async {
    final dados = await _dialogCategoria(context, existente: c);
    if (dados == null || !context.mounted) return;
    final ok = await executar(
      context,
      () => context.api.editarCategoria(
        c.id,
        nome: dados.nome,
        slug: dados.slug,
        icone: dados.icone,
        garantiaDias: dados.garantiaDias,
        motivo: dados.motivo,
      ),
      sucesso: 'Categoria atualizada com sucesso.',
    );
    if (ok) await recarregar();
  }

  Future<void> _excluir(BuildContext context, CategoriaAdmin c, Future<void> Function() recarregar) async {
    final motivo = await pedirMotivo(
      context,
      titulo: 'Excluir categoria "${c.nome}"',
      descricao: 'A categoria será excluída se não houver histórico de pedidos ou profissionais vinculados.',
      rotuloConfirmar: 'Excluir definitivamente',
    );
    if (motivo == null || !context.mounted) return;
    final ok = await executar(
      context,
      () => context.api.excluirCategoria(c.id, motivo: motivo),
      sucesso: 'Categoria excluída com sucesso.',
    );
    if (ok) await recarregar();
  }

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
      construir: (context, lista, recarregar) => Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: EspacosTrato.x4, vertical: EspacosTrato.x2),
            child: Row(
              children: [
                const Spacer(),
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(0, 40),
                    padding: const EdgeInsets.symmetric(horizontal: EspacosTrato.x4),
                  ),
                  onPressed: () => _criar(context, recarregar),
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Nova categoria'),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: EspacosTrato.x4),
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
                        IconButton(
                          icon: const Icon(Icons.edit_outlined, size: 20),
                          tooltip: 'Editar categoria',
                          onPressed: () => _editar(context, c, recarregar),
                        ),
                        TextButton(
                          onPressed: () => _alternar(context, c, recarregar),
                          child: Text(c.ativa ? 'Desativar' : 'Ativar'),
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete_outline, size: 20),
                          tooltip: 'Excluir categoria',
                          onPressed: () => _excluir(context, c, recarregar),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _AbaCidades extends StatelessWidget {
  const _AbaCidades();

  Future<void> _criar(BuildContext context, Future<void> Function() recarregar) async {
    final dados = await _dialogCidade(context);
    if (dados == null || !context.mounted) return;
    final ok = await executar(
      context,
      () => context.api.criarCidade(
        nome: dados.nome,
        uf: dados.uf,
        motivo: dados.motivo,
      ),
      sucesso: 'Cidade "${dados.nome} - ${dados.uf}" cadastrada com sucesso.',
    );
    if (ok) await recarregar();
  }

  Future<void> _alternar(BuildContext context, CidadeAdmin c, Future<void> Function() recarregar) async {
    final ativar = !c.ativa;
    final motivo = await pedirMotivo(
      context,
      titulo: ativar ? 'Ativar ${c.nome} - ${c.uf}' : 'Desativar ${c.nome} - ${c.uf}',
      descricao: ativar
          ? 'O app Trato passará a permitir pedidos e profissionais nesta cidade.'
          : 'Novos pedidos nesta cidade serão suspensos temporariamente.',
      rotuloConfirmar: ativar ? 'Ativar' : 'Desativar',
    );
    if (motivo == null || !context.mounted) return;
    final ok = await executar(
      context,
      () => context.api.alterarCidade(c.id, ativa: ativar, motivo: motivo),
      sucesso: 'Cidade atualizada.',
    );
    if (ok) await recarregar();
  }

  @override
  Widget build(BuildContext context) {
    return CarregaDados<List<CidadeAdmin>>(
      carregar: context.api.listarCidades,
      estaVazio: (l) => l.isEmpty,
      mensagemVazia: 'Nenhuma cidade cadastrada.',
      construir: (context, lista, recarregar) => Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: EspacosTrato.x4, vertical: EspacosTrato.x2),
            child: Row(
              children: [
                const Spacer(),
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(0, 40),
                    padding: const EdgeInsets.symmetric(horizontal: EspacosTrato.x4),
                  ),
                  onPressed: () => _criar(context, recarregar),
                  icon: const Icon(Icons.add_location_alt_outlined, size: 18),
                  label: const Text('Nova cidade'),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: EspacosTrato.x4),
              itemCount: lista.length,
              separatorBuilder: (_, _) => const SizedBox(height: EspacosTrato.x2),
              itemBuilder: (context, i) {
                final c = lista[i];
                return Card(
                  child: ListTile(
                    title: Text('${c.nome} - ${c.uf}', style: TipografiaTrato.corpoForte),
                    subtitle: Text(c.ativa ? 'Atendimento ativo para novos pedidos' : 'Atendimento inativo'),
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
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// DIÁLOGOS DE CRUD
// =============================================================================

class _DadosCategoriaDialog {
  const _DadosCategoriaDialog({
    required this.nome,
    this.slug,
    this.icone,
    this.garantiaDias,
    required this.motivo,
  });
  final String nome;
  final String? slug;
  final String? icone;
  final int? garantiaDias;
  final String motivo;
}

Future<_DadosCategoriaDialog?> _dialogCategoria(BuildContext context, {CategoriaAdmin? existente}) {
  final nomeCtrl = TextEditingController(text: existente?.nome ?? '');
  final slugCtrl = TextEditingController(text: existente?.slug ?? '');
  final garantiaCtrl = TextEditingController(text: existente?.garantiaDias?.toString() ?? '');
  final motivoCtrl = TextEditingController();

  return showDialog<_DadosCategoriaDialog>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) {
        return AlertDialog(
          title: Text(existente == null ? 'Nova categoria' : 'Editar categoria'),
          content: SingleChildScrollView(
            child: SizedBox(
              width: 440,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: nomeCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Nome da categoria *',
                      hintText: 'Ex: Eletricista, Limpeza residencial',
                    ),
                  ),
                  const SizedBox(height: EspacosTrato.x3),
                  TextField(
                    controller: slugCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Identificador (slug)',
                      hintText: 'Opcional (gerado automaticamente)',
                    ),
                  ),
                  const SizedBox(height: EspacosTrato.x3),
                  TextField(
                    controller: garantiaCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Garantia de retrabalho (dias)',
                      hintText: 'Vazio = padrão do sistema (30 dias)',
                    ),
                  ),
                  const SizedBox(height: EspacosTrato.x3),
                  TextField(
                    controller: motivoCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Motivo da alteração *',
                      hintText: 'Justificativa para a auditoria (mín. 3 caracteres)',
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
            FilledButton(
              onPressed: () {
                final nome = nomeCtrl.text.trim();
                final motivo = motivoCtrl.text.trim();
                if (nome.length < 2 || motivo.length < 3) {
                  mostrarAviso(ctx, 'Preencha o nome e o motivo da alteração.');
                  return;
                }
                final dias = int.tryParse(garantiaCtrl.text.trim());
                final slug = slugCtrl.text.trim().isEmpty ? null : slugCtrl.text.trim();
                Navigator.pop(
                  ctx,
                  _DadosCategoriaDialog(
                    nome: nome,
                    slug: slug,
                    garantiaDias: dias,
                    motivo: motivo,
                  ),
                );
              },
              child: Text(existente == null ? 'Criar categoria' : 'Salvar alterações'),
            ),
          ],
        );
      },
    ),
  );
}

class _DadosCidadeDialog {
  const _DadosCidadeDialog({required this.nome, required this.uf, required this.motivo});
  final String nome;
  final String uf;
  final String motivo;
}

Future<_DadosCidadeDialog?> _dialogCidade(BuildContext context) {
  final nomeCtrl = TextEditingController();
  final ufCtrl = TextEditingController();
  final motivoCtrl = TextEditingController();

  return showDialog<_DadosCidadeDialog>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Nova cidade de atendimento'),
      content: SizedBox(
        width: 380,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nomeCtrl,
              decoration: const InputDecoration(labelText: 'Nome da cidade *', hintText: 'Ex: São Paulo, Campinas'),
            ),
            const SizedBox(height: EspacosTrato.x3),
            TextField(
              controller: ufCtrl,
              maxLength: 2,
              decoration: const InputDecoration(labelText: 'UF *', hintText: 'Ex: SP, MG, RJ'),
            ),
            const SizedBox(height: EspacosTrato.x2),
            TextField(
              controller: motivoCtrl,
              decoration: const InputDecoration(labelText: 'Motivo *', hintText: 'Justificativa para auditoria'),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
        FilledButton(
          onPressed: () {
            final nome = nomeCtrl.text.trim();
            final uf = ufCtrl.text.trim().toUpperCase();
            final motivo = motivoCtrl.text.trim();
            if (nome.length < 2 || uf.length != 2 || motivo.length < 3) {
              mostrarAviso(ctx, 'Preencha nome, UF (2 letras) e motivo.');
              return;
            }
            Navigator.pop(ctx, _DadosCidadeDialog(nome: nome, uf: uf, motivo: motivo));
          },
          child: const Text('Cadastrar cidade'),
        ),
      ],
    ),
  );
}

Future<(String, String)?> _dialogAlterarStatus(BuildContext context, String nomeUsuario, String statusAtual) {
  var selecionado = statusAtual;
  final motivoCtrl = TextEditingController();

  return showDialog<(String, String)>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) => AlertDialog(
        title: Text('Alterar status de $nomeUsuario'),
        content: SizedBox(
          width: 380,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Status atual: $statusAtual', style: TipografiaTrato.corpoPequeno),
              const SizedBox(height: EspacosTrato.x3),
              DropdownButtonFormField<String>(
                value: selecionado,
                items: const [
                  DropdownMenuItem(value: 'ativo', child: Text('Ativo (acesso normal)')),
                  DropdownMenuItem(value: 'restrito', child: Text('Restrito (atividades limitadas)')),
                  DropdownMenuItem(value: 'bloqueado', child: Text('Bloqueado (acesso negado)')),
                ],
                onChanged: (v) {
                  if (v != null) setState(() => selecionado = v);
                },
                decoration: const InputDecoration(labelText: 'Novo status'),
              ),
              const SizedBox(height: EspacosTrato.x3),
              TextField(
                controller: motivoCtrl,
                decoration: const InputDecoration(labelText: 'Motivo da alteração *', hintText: 'Obrigatório para auditoria'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
          FilledButton(
            onPressed: () {
              final motivo = motivoCtrl.text.trim();
              if (motivo.length < 3) {
                mostrarAviso(ctx, 'Informe o motivo da alteração.');
                return;
              }
              Navigator.pop(ctx, (selecionado, motivo));
            },
            child: const Text('Salvar status'),
          ),
        ],
      ),
    ),
  );
}
