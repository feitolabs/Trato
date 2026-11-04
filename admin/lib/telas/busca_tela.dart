import 'dart:async';

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
    final abas = <AbaTrato>[
      if (context.pode(Permissao.usuariosBuscar)) const AbaTrato('Usuários', conteudo: _AbaUsuarios()),
      if (context.pode(Permissao.pedidosBuscar)) const AbaTrato('Pedidos', conteudo: _AbaPedidos()),
      if (context.pode(Permissao.suporteVer)) const AbaTrato('Suporte', conteudo: _AbaSuporte()),
      if (context.pode(Permissao.categoriasEditar)) const AbaTrato('Categorias', conteudo: _AbaCategorias()),
      if (context.pode(Permissao.categoriasEditar)) const AbaTrato('Cidades', conteudo: _AbaCidades()),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const CabecalhoPagina(
          'Busca e suporte',
          subtitulo: 'Dados pessoais aparecem mascarados. Revelar e alterar status pedem motivo.',
        ),
        Expanded(child: AbasTrato(abas: abas)),
      ],
    );
  }
}

/// Tira acento e caixa para comparar nomes (RN-02: "Pintura" e "pintura" são a mesma categoria).
String normalizarNome(String texto) {
  const de = 'áàâãäéèêëíìîïóòôõöúùûüçñ';
  const para = 'aaaaaeeeeiiiiooooouuuucn';
  var t = texto.trim().toLowerCase();
  for (var i = 0; i < de.length; i++) {
    t = t.replaceAll(de[i], para[i]);
  }
  return t.replaceAll(RegExp(r'\s+'), ' ');
}

// =============================================================================================
// USUÁRIOS
// =============================================================================================

(String, Tom) _chipStatusUsuario(String status) => switch (status) {
      'ativo' => ('Ativo', Tom.ok),
      'restrito' => ('Restrito', Tom.alerta),
      'bloqueado' => ('Bloqueado', Tom.erro),
      'anonimizado' => ('Anonimizado', Tom.neutro),
      final outro => (outro, Tom.neutro),
    };

class _AbaUsuarios extends StatelessWidget {
  const _AbaUsuarios();

  @override
  Widget build(BuildContext context) {
    return CarregaDados<List<UsuarioBusca>>(
      carregar: () => context.api.buscarUsuarios(''),
      estaVazio: (l) => l.isEmpty,
      mensagemVazia: 'Nenhum usuário encontrado.',
      detalheVazio: 'Quando alguém criar uma conta, ela aparece aqui.',
      construir: (context, lista, recarregar) => _UsuariosLista(lista: lista, aoMudar: recarregar),
    );
  }
}

class _UsuariosLista extends StatefulWidget {
  const _UsuariosLista({required this.lista, required this.aoMudar});
  final List<UsuarioBusca> lista;
  final Future<void> Function() aoMudar;

  @override
  State<_UsuariosLista> createState() => _UsuariosListaState();
}

class _UsuariosListaState extends State<_UsuariosLista> {
  String _busca = '';
  String? _tipo;
  String? _status;

  @override
  Widget build(BuildContext context) {
    final t = normalizarNome(_busca);
    final itens = [
      for (final u in widget.lista)
        if ((_tipo == null || u.tipo == _tipo) &&
            (_status == null || u.status == _status) &&
            (t.isEmpty ||
                normalizarNome(u.nome).contains(t) ||
                u.idPublico.toLowerCase().contains(t) ||
                (u.emailMascarado ?? '').toLowerCase().contains(t) ||
                u.id == _busca.trim()))
          u,
    ];
    final margem = Responsivo.margemLateral(FaixaPainel.de(context));
    return MestreDetalhe<UsuarioBusca>(
      itens: itens,
      mensagemSemItens: 'Nenhum usuário encontrado.',
      tituloDetalhe: (u) => u.nome,
      topo: Padding(
        padding: EdgeInsets.fromLTRB(margem, EspacosTrato.x3, margem, EspacosTrato.x2),
        child: BarraFiltros(
          busca: TextField(
            onChanged: (v) => setState(() => _busca = v),
            decoration: const InputDecoration(
              labelText: 'Buscar usuário por nome',
              helperText: 'Nome, ID ou e-mail',
              prefixIcon: Icon(IconesTrato.buscar, size: 20),
            ),
          ),
          filtros: [
            DropdownButtonFormField<String?>(
              key: ValueKey('tipo-$_tipo'),
              initialValue: _tipo,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Tipo'),
              items: const [
                DropdownMenuItem(value: null, child: Text('Todos')),
                DropdownMenuItem(value: 'Cliente', child: Text('Cliente')),
                DropdownMenuItem(value: 'Profissional', child: Text('Profissional')),
                DropdownMenuItem(value: 'Equipe', child: Text('Equipe')),
              ],
              onChanged: (v) => setState(() => _tipo = v),
            ),
            DropdownButtonFormField<String?>(
              key: ValueKey('status-$_status'),
              initialValue: _status,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Status'),
              items: const [
                DropdownMenuItem(value: null, child: Text('Todos')),
                DropdownMenuItem(value: 'ativo', child: Text('Ativo')),
                DropdownMenuItem(value: 'restrito', child: Text('Restrito')),
                DropdownMenuItem(value: 'bloqueado', child: Text('Bloqueado')),
              ],
              onChanged: (v) => setState(() => _status = v),
            ),
          ],
        ),
      ),
      itemBuilder: (context, u, sel) {
        final (texto, tom) = _chipStatusUsuario(u.status);
        return CartaoLista(
          titulo: u.nome,
          linhas: [
            if (u.emailMascarado != null || u.telefoneMascarado != null)
              [u.emailMascarado, u.telefoneMascarado].whereType<String>().join(' · '),
          ],
          chips: [ChipPapel(u.tipo), ChipEstado(texto, tom: tom)],
          selecionado: sel,
        );
      },
      detalheBuilder: (context, u) => _DetalheUsuario(key: ValueKey(u.id), usuario: u, aoMudar: widget.aoMudar),
    );
  }
}

class _DetalheUsuario extends StatefulWidget {
  const _DetalheUsuario({super.key, required this.usuario, required this.aoMudar});
  final UsuarioBusca usuario;
  final Future<void> Function() aoMudar;

  @override
  State<_DetalheUsuario> createState() => _DetalheUsuarioState();
}

class _DetalheUsuarioState extends State<_DetalheUsuario> {
  DadosPessoais? _dados;
  Timer? _escondeDados;
  late final Future<UsuarioBusca> _detalhe = _carregar();
  final _pedido = TextEditingController();
  Future<DiagnosticoPedido>? _diagnostico;

  Future<UsuarioBusca> _carregar() async {
    try {
      return await context.api.detalheUsuario(widget.usuario.id);
    } catch (_) {
      return widget.usuario; // o resumo da lista já basta para as informações básicas
    }
  }

  @override
  void dispose() {
    _escondeDados?.cancel();
    _pedido.dispose();
    super.dispose();
  }

  Future<void> _revelar() async {
    final api = context.api;
    final motivo = await pedirMotivo(
      context,
      titulo: 'Revelar dados pessoais de ${widget.usuario.nome}?',
      descricao: 'E-mail, CPF e telefone aparecem por 30 segundos e depois voltam a ficar mascarados.',
      rotuloConfirmar: 'Revelar',
    );
    if (motivo == null || !mounted) return;
    DadosPessoais? d;
    final ok = await executar(context, () async {
      d = await api.revelarDadosPessoais(widget.usuario.id, motivo);
    }, sucesso: 'Dados pessoais revelados por 30 segundos.');
    if (!ok || !mounted) return;
    setState(() => _dados = d);
    _escondeDados?.cancel();
    _escondeDados = Timer(const Duration(seconds: 30), () {
      if (mounted) setState(() => _dados = null);
    });
  }

  Future<void> _alterarStatus() async {
    final u = widget.usuario;
    var novo = u.status;
    final r = await pedirFormulario<(String, String)>(
      context,
      titulo: 'Alterar status de ${u.nome}?',
      consequencia: 'Restrito limita as atividades; bloqueado nega o acesso. Pedidos em andamento não são cancelados.',
      rotuloConfirmar: 'Alterar status',
      campos: (ctx, rebuild) => SeletorTrato<String>(
        rotulo: 'Novo status',
        valor: novo,
        opcoes: const [
          ('ativo', 'Ativo (acesso normal)'),
          ('restrito', 'Restrito (atividades limitadas)'),
          ('bloqueado', 'Bloqueado (acesso negado)'),
        ],
        aoMudar: (v) {
          novo = v;
          rebuild();
        },
      ),
      camposValidos: () => novo != u.status,
      resultado: (motivo) => (novo, motivo),
    );
    if (r == null || !mounted) return;
    final ok = await executar(
      context,
      () => context.api.alterarStatusUsuario(u.id, status: r.$1, motivo: r.$2),
      sucesso: 'Status alterado para ${_chipStatusUsuario(r.$1).$1.toLowerCase()}.',
    );
    if (ok) await widget.aoMudar();
  }

  void _diagnosticar() {
    if (_pedido.text.trim().length < 2) return;
    final futuro = context.api.diagnosticarPedido(widget.usuario.id, _pedido.text);
    setState(() {
      _diagnostico = futuro;
    });
  }

  @override
  Widget build(BuildContext context) {
    final u = widget.usuario;
    final (textoStatus, tomStatus) = _chipStatusUsuario(u.status);
    final podeRevelar = context.pode(Permissao.dadosPessoaisRevelar);
    return FutureBuilder<UsuarioBusca>(
      future: _detalhe,
      builder: (context, snap) {
        final d = snap.data ?? u;
        return ListView(
          padding: const EdgeInsets.all(EspacosTrato.x6),
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(d.nome, style: TipografiaTrato.titulo),
                      const SizedBox(height: EspacosTrato.x1),
                      Text(
                        [d.tipo, if (d.idPublico.isNotEmpty) 'ID ${d.idPublico}', if (d.cidade != null) d.cidade!].join(' · '),
                        style: TipografiaTrato.subtitulo,
                      ),
                    ],
                  ),
                ),
                ChipEstado(textoStatus, tom: tomStatus),
              ],
            ),
            const SizedBox(height: EspacosTrato.x4),
            Wrap(
              spacing: EspacosTrato.x3,
              runSpacing: EspacosTrato.x3,
              children: [
                if (_dados == null && podeRevelar)
                  BotaoTrato.secundario('Revelar dados pessoais', aoPressionar: _revelar, icone: IconesTrato.revelar),
                BotaoTrato.secundario('Alterar status', aoPressionar: _alterarStatus),
              ],
            ),
            const SizedBox(height: EspacosTrato.x4),
            if (_dados != null) ...[
              if (_dados!.email != null) Linha('E-mail', _dados!.email!),
              Linha('CPF', _dados!.cpf),
              Linha('Telefone', _dados!.telefone),
              if (_dados!.nascimento != null) Linha('Nascimento', _dados!.nascimento!),
            ] else ...[
              if (d.emailMascarado != null) Linha('E-mail', d.emailMascarado!),
              if (d.telefoneMascarado != null) Linha('Telefone', d.telefoneMascarado!),
              if (d.cpfMascarado != null) Linha('CPF', d.cpfMascarado!),
            ],
            if (d.tipo == 'Profissional') ...[
              const SizedBox(height: EspacosTrato.x5),
              Text('Categorias cadastradas', style: TipografiaTrato.secao),
              const SizedBox(height: EspacosTrato.x2),
              if (snap.connectionState != ConnectionState.done)
                const LinearProgressIndicator()
              else if (d.categorias.isEmpty)
                Text('Nenhuma categoria cadastrada.', style: TipografiaTrato.corpo.copyWith(color: CoresTrato.textoMudo))
              else
                Wrap(
                  spacing: EspacosTrato.x2,
                  runSpacing: EspacosTrato.x2,
                  children: [
                    for (final c in d.categorias)
                      ChipEstado(
                        '${c.nome} · ${c.ativaNoPerfil ? (c.ativaNaPlataforma ? 'ativa' : 'desativada pela plataforma') : 'inativa no perfil'}',
                        tom: c.ativaNoPerfil && c.ativaNaPlataforma ? Tom.ok : Tom.alerta,
                      ),
                  ],
                ),
              const SizedBox(height: EspacosTrato.x5),
              _Diagnostico(
                controle: _pedido,
                aoDiagnosticar: _diagnosticar,
                diagnostico: _diagnostico,
              ),
            ],
            if (d.historico.isNotEmpty) ...[
              const SizedBox(height: EspacosTrato.x5),
              Text('Histórico', style: TipografiaTrato.secao),
              const SizedBox(height: EspacosTrato.x2),
              for (final e in d.historico)
                Padding(
                  padding: const EdgeInsets.only(bottom: EspacosTrato.x2),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: Text(e.texto, style: TipografiaTrato.corpo)),
                      const SizedBox(width: EspacosTrato.x3),
                      Text(formatarData(e.em), style: TipografiaTrato.legenda),
                    ],
                  ),
                ),
            ],
          ],
        );
      },
    );
  }
}

/// "Por que este pedido não aparece para ele?" (RF-BUS-03, regra RN-01).
class _Diagnostico extends StatelessWidget {
  const _Diagnostico({required this.controle, required this.aoDiagnosticar, required this.diagnostico});
  final TextEditingController controle;
  final VoidCallback aoDiagnosticar;
  final Future<DiagnosticoPedido>? diagnostico;

  @override
  Widget build(BuildContext context) {
    return CartaoSecao(
      titulo: 'Por que este pedido não aparece para ele?',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: TextField(
                  controller: controle,
                  onSubmitted: (_) => aoDiagnosticar(),
                  decoration: const InputDecoration(labelText: 'Pedido', helperText: 'Código (PED-10482) ou ID'),
                ),
              ),
              const SizedBox(width: EspacosTrato.x3),
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: BotaoTrato.secundario('Diagnosticar', aoPressionar: aoDiagnosticar),
              ),
            ],
          ),
          if (diagnostico != null)
            FutureBuilder<DiagnosticoPedido>(
              future: diagnostico,
              builder: (context, snap) {
                if (snap.connectionState != ConnectionState.done) {
                  return const Padding(padding: EdgeInsets.only(top: EspacosTrato.x3), child: LinearProgressIndicator());
                }
                if (snap.hasError) {
                  return Padding(
                    padding: const EdgeInsets.only(top: EspacosTrato.x3),
                    child: BannerInfo(snap.error.toString(), tom: Tom.erro),
                  );
                }
                final r = snap.data!;
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: EspacosTrato.x3),
                    BannerInfo(
                      r.aparece
                          ? '${r.pedido} · ${r.titulo} aparece para este profissional.'
                          : '${r.pedido} · ${r.titulo} não aparece para este profissional.',
                      tom: r.aparece ? Tom.ok : Tom.alerta,
                    ),
                    const SizedBox(height: EspacosTrato.x2),
                    for (final i in r.itens)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: EspacosTrato.x1),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(
                              i.ok ? Icons.check_circle_outline : Icons.cancel_outlined,
                              size: 18,
                              color: i.ok ? CoresTrato.sucessoTexto : CoresTrato.perigoTexto,
                            ),
                            const SizedBox(width: EspacosTrato.x2),
                            Expanded(
                              child: Text.rich(
                                TextSpan(children: [
                                  TextSpan(text: '${i.titulo} ', style: TipografiaTrato.corpoForte),
                                  TextSpan(text: i.detalhe),
                                ]),
                                style: TipografiaTrato.corpo,
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                );
              },
            ),
          const SizedBox(height: EspacosTrato.x3),
          Text(
            'Regra RN-01: o pedido só aparece para quem tem exatamente a categoria dele cadastrada e ativa.',
            style: TipografiaTrato.legenda,
          ),
        ],
      ),
    );
  }
}

// =============================================================================================
// PEDIDOS
// =============================================================================================

class _AbaPedidos extends StatelessWidget {
  const _AbaPedidos();

  @override
  Widget build(BuildContext context) {
    return CarregaDados<List<PedidoBusca>>(
      carregar: () => context.api.buscarPedidos(''),
      estaVazio: (l) => l.isEmpty,
      mensagemVazia: 'Nenhum pedido encontrado.',
      detalheVazio: 'Quando um cliente pedir um serviço, ele aparece aqui.',
      construir: (context, lista, _) => ListaPaginada<PedidoBusca>(
        itens: lista,
        rotuloBusca: 'Buscar pedido por código ou título',
        rotuloItens: 'pedidos',
        textoBusca: (p) => '${p.codigo} ${p.titulo} ${p.cliente} ${p.profissional ?? ''}',
        filtros: [
          FiltroLista<PedidoBusca>(
            rotulo: 'Status',
            opcoes: [for (final s in {for (final p in lista) p.status}) (s, s)],
            aplica: (p, v) => p.status == v,
          ),
        ],
        construirItem: (context, p) => CartaoLista(
          titulo: '${p.codigo.isEmpty ? '' : '${p.codigo} · '}${p.titulo}',
          linhas: [
            'Cliente ${p.cliente}${p.profissional == null ? '' : ' · profissional ${p.profissional}'}',
            [p.categoria, p.cidade].whereType<String>().join(' · '),
          ].where((l) => l.isNotEmpty).toList(),
          chips: [ChipEstado(p.status, tom: Tom.info)],
          acoes: [
            Text(
              p.valorCentavos == 0 ? '—' : formatarReais(p.valorCentavos),
              style: TipografiaTrato.numeroTabular.copyWith(fontWeight: FontWeight.w700),
            ),
          ],
        ),
      ),
    );
  }
}

// =============================================================================================
// SUPORTE
// =============================================================================================

class _AbaSuporte extends StatelessWidget {
  const _AbaSuporte();

  @override
  Widget build(BuildContext context) {
    return CarregaDados<List<Chamado>>(
      carregar: context.api.listarChamados,
      estaVazio: (l) => l.isEmpty,
      mensagemVazia: 'Nenhum chamado aberto.',
      detalheVazio: 'Quando alguém pedir ajuda, o chamado aparece aqui com prioridade e prazo.',
      construir: (context, lista, _) => ListaPaginada<Chamado>(
        itens: lista,
        rotuloBusca: 'Buscar chamado',
        rotuloItens: 'chamados',
        textoBusca: (c) => '${c.id} ${c.assunto} ${c.solicitante}',
        construirItem: (context, c) => CartaoLista(
          titulo: '${c.id} · ${c.assunto}',
          linhas: [
            '${c.solicitante} · aberto em ${formatarData(c.aberto)}',
            [
              c.responsavel == null ? 'Sem responsável' : 'Responsável ${c.responsavel}',
              if (c.prazo != null) 'prazo ${formatarData(c.prazo!)}',
            ].join(' · '),
          ],
          chips: [
            ChipEstado(c.status == 'aberto' ? 'Aberto' : 'Em atendimento', tom: c.status == 'aberto' ? Tom.alerta : Tom.info),
            ChipEstado(
              switch (c.prioridade) { 'alta' => 'Prioridade alta', 'baixa' => 'Prioridade baixa', _ => 'Prioridade normal' },
              tom: c.prioridade == 'alta' ? Tom.erro : Tom.neutro,
            ),
          ],
        ),
      ),
    );
  }
}

// =============================================================================================
// CATEGORIAS
// =============================================================================================

class _AbaCategorias extends StatelessWidget {
  const _AbaCategorias();

  Future<void> _criar(BuildContext context, List<CategoriaAdmin> existentes, Future<void> Function() recarregar) async {
    final dados = await _formCategoria(context, existentes);
    if (dados == null || !context.mounted) return;
    final ok = await executar(
      context,
      () => context.api.criarCategoria(nome: dados.nome, garantiaDias: dados.garantiaDias, motivo: dados.motivo),
      sucesso: 'Categoria "${dados.nome}" criada.',
    );
    if (ok) await recarregar();
  }

  Future<void> _editar(
    BuildContext context,
    CategoriaAdmin c,
    List<CategoriaAdmin> existentes,
    Future<void> Function() recarregar,
  ) async {
    final dados = await _formCategoria(context, existentes, existente: c);
    if (dados == null || !context.mounted) return;
    final ok = await executar(
      context,
      () => context.api.editarCategoria(c.id, nome: dados.nome, garantiaDias: dados.garantiaDias, motivo: dados.motivo),
      sucesso: 'Categoria atualizada.',
    );
    if (ok) await recarregar();
  }

  Future<void> _excluir(BuildContext context, CategoriaAdmin c, Future<void> Function() recarregar) async {
    final motivo = await pedirMotivo(
      context,
      titulo: 'Excluir a categoria "${c.nome}"?',
      descricao: c.profissionais > 0
          ? '${c.profissionais} ${c.profissionais == 1 ? 'profissional vinculado' : 'profissionais vinculados'}. '
              'Com vínculos ou pedidos a exclusão é recusada: desative a categoria.'
          : 'Ninguém está vinculado. A exclusão não pode ser desfeita.',
      rotuloConfirmar: 'Excluir categoria',
      destrutivo: true,
    );
    if (motivo == null || !context.mounted) return;
    final ok = await executar(
      context,
      () => context.api.excluirCategoria(c.id, motivo: motivo),
      sucesso: 'Categoria excluída.',
    );
    if (ok) await recarregar();
  }

  Future<void> _alternar(BuildContext context, CategoriaAdmin c, Future<void> Function() recarregar) async {
    final api = context.api;
    final ativar = !c.ativa;
    final motivo = await pedirMotivo(
      context,
      titulo: ativar ? 'Ativar "${c.nome}"?' : 'Desativar "${c.nome}"?',
      descricao: ativar
          ? 'A categoria volta a gerar pedidos novos para os profissionais vinculados.'
          : 'Deixa de gerar pedidos novos. Pedidos em andamento seguem normalmente.',
      rotuloConfirmar: ativar ? 'Ativar categoria' : 'Desativar categoria',
    );
    if (motivo == null || !context.mounted) return;
    final ok = await executar(
      context,
      () => api.alterarCategoria(c.id, ativa: ativar, motivo: motivo),
      sucesso: ativar ? 'Categoria ativada.' : 'Categoria desativada.',
    );
    if (ok) await recarregar();
  }

  @override
  Widget build(BuildContext context) {
    return CarregaDados<List<CategoriaAdmin>>(
      carregar: context.api.listarCategorias,
      construir: (context, lista, recarregar) => ListaPaginada<CategoriaAdmin>(
        itens: lista,
        mensagemVazia: 'Nenhuma categoria cadastrada',
        detalheVazio: 'Crie a primeira categoria para os clientes poderem pedir serviços.',
        rotuloBusca: 'Buscar categoria',
        rotuloItens: 'categorias',
        textoBusca: (c) => c.nome,
        acoesTopo: [
          BotaoTrato.primario(
            'Nova categoria',
            icone: IconesTrato.adicionar,
            aoPressionar: () => _criar(context, lista, recarregar),
          ),
        ],
        construirItem: (context, c) => CartaoLista(
          tituloWidget: Row(
            children: [
              Flexible(child: Text(c.nome, style: TipografiaTrato.corpoForte)),
              const SizedBox(width: EspacosTrato.x2),
              ChipEstado(c.ativa ? 'Ativa' : 'Inativa', tom: c.ativa ? Tom.ok : Tom.neutro),
            ],
          ),
          titulo: c.nome,
          linhas: [
            '${c.profissionais} ${c.profissionais == 1 ? 'profissional vinculado' : 'profissionais vinculados'}',
          ],
          acoes: [
            BotaoIcone(
              icone: IconesTrato.ajuda,
              rotulo: 'Perguntas do pedido de ${c.nome}',
              aoPressionar: () => showDialog<void>(context: context, builder: (_) => _DialogPerguntas(categoria: c)),
            ),
            BotaoIcone(
              icone: IconesTrato.editar,
              rotulo: 'Editar ${c.nome}',
              aoPressionar: () => _editar(context, c, lista, recarregar),
            ),
            BotaoTrato.link(c.ativa ? 'Desativar' : 'Ativar', aoPressionar: () => _alternar(context, c, recarregar)),
            BotaoIcone(
              icone: IconesTrato.excluir,
              rotulo: 'Excluir ${c.nome}',
              destrutivo: true,
              aoPressionar: () => _excluir(context, c, recarregar),
            ),
          ],
        ),
      ),
    );
  }
}

class _DadosCategoria {
  const _DadosCategoria(this.nome, this.garantiaDias, this.motivo);
  final String nome;
  final int? garantiaDias;
  final String motivo;
}

Future<_DadosCategoria?> _formCategoria(
  BuildContext context,
  List<CategoriaAdmin> existentes, {
  CategoriaAdmin? existente,
}) {
  final nome = TextEditingController(text: existente?.nome ?? '');
  final garantia = TextEditingController(text: existente?.garantiaDias?.toString() ?? '');

  /// RN-02: nome único, sem diferenciar maiúsculas e acentos.
  String? erroNome() {
    final n = normalizarNome(nome.text);
    if (n.isEmpty) return null;
    final repetida = existentes.any((c) => c.id != existente?.id && normalizarNome(c.nome) == n);
    return repetida ? 'Já existe uma categoria com esse nome.' : null;
  }

  return pedirFormulario<_DadosCategoria>(
    context,
    titulo: existente == null ? 'Nova categoria' : 'Editar "${existente.nome}"',
    consequencia: existente == null
        ? 'Nomes quase iguais fragmentam os pedidos: use um nome único.'
        : 'A mudança vale para novos pedidos.',
    rotuloConfirmar: existente == null ? 'Criar categoria' : 'Salvar categoria',
    campos: (ctx, rebuild) => Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        TextField(
          controller: nome,
          onChanged: (_) => rebuild(),
          decoration: InputDecoration(
            labelText: 'Nome da categoria',
            helperText: 'Ex.: Eletricista, Limpeza residencial',
            errorText: erroNome(),
          ),
        ),
        const SizedBox(height: EspacosTrato.x3),
        TextField(
          controller: garantia,
          keyboardType: TextInputType.number,
          onChanged: (_) => rebuild(),
          decoration: const InputDecoration(
            labelText: 'Garantia de retrabalho (dias)',
            helperText: 'Vazio = padrão do sistema',
          ),
        ),
      ],
    ),
    camposValidos: () => nome.text.trim().length >= 2 && erroNome() == null,
    resultado: (motivo) => _DadosCategoria(nome.text.trim(), int.tryParse(garantia.text.trim()), motivo),
  );
}

// =============================================================================================
// CIDADES
// =============================================================================================

class _AbaCidades extends StatelessWidget {
  const _AbaCidades();

  Future<void> _criar(BuildContext context, Future<void> Function() recarregar) async {
    final nome = TextEditingController();
    final uf = TextEditingController();
    final r = await pedirFormulario<(String, String, String)>(
      context,
      titulo: 'Nova cidade de atendimento',
      consequencia: 'A cidade nasce ativa: clientes e profissionais podem usá-la em novos pedidos.',
      rotuloConfirmar: 'Cadastrar cidade',
      campos: (ctx, rebuild) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: nome,
            onChanged: (_) => rebuild(),
            decoration: const InputDecoration(labelText: 'Nome da cidade', helperText: 'Ex.: Contagem, Campinas'),
          ),
          const SizedBox(height: EspacosTrato.x3),
          TextField(
            controller: uf,
            maxLength: 2,
            textCapitalization: TextCapitalization.characters,
            onChanged: (_) => rebuild(),
            decoration: const InputDecoration(labelText: 'UF', helperText: 'Duas letras: MG, SP, RJ', counterText: ''),
          ),
        ],
      ),
      camposValidos: () => nome.text.trim().length >= 2 && uf.text.trim().length == 2,
      resultado: (motivo) => (nome.text.trim(), uf.text.trim().toUpperCase(), motivo),
    );
    if (r == null || !context.mounted) return;
    final ok = await executar(
      context,
      () => context.api.criarCidade(nome: r.$1, uf: r.$2, motivo: r.$3),
      sucesso: 'Cidade "${r.$1} - ${r.$2}" cadastrada.',
    );
    if (ok) await recarregar();
  }

  Future<void> _alternar(BuildContext context, CidadeAdmin c, Future<void> Function() recarregar) async {
    final ativar = !c.ativa;
    final motivo = await pedirMotivo(
      context,
      titulo: ativar ? 'Ativar ${c.nome} - ${c.uf}?' : 'Desativar ${c.nome} - ${c.uf}?',
      descricao: ativar
          ? 'O Trato passa a aceitar novos pedidos nesta cidade.'
          : 'Novos pedidos nesta cidade ficam suspensos. Pedidos já abertos não são afetados.',
      rotuloConfirmar: ativar ? 'Ativar cidade' : 'Desativar cidade',
    );
    if (motivo == null || !context.mounted) return;
    final ok = await executar(
      context,
      () => context.api.alterarCidade(c.id, ativa: ativar, motivo: motivo),
      sucesso: ativar ? 'Cidade ativada.' : 'Cidade desativada.',
    );
    if (ok) await recarregar();
  }

  @override
  Widget build(BuildContext context) {
    return CarregaDados<List<CidadeAdmin>>(
      carregar: context.api.listarCidades,
      construir: (context, lista, recarregar) => ListaPaginada<CidadeAdmin>(
        itens: lista,
        mensagemVazia: 'Nenhuma cidade cadastrada',
        detalheVazio: 'Cadastre a primeira cidade para começar a atender.',
        rotuloBusca: 'Buscar cidade',
        rotuloItens: 'cidades',
        textoBusca: (c) => '${c.nome} ${c.uf}',
        acoesTopo: [
          BotaoTrato.primario('Nova cidade', icone: IconesTrato.adicionar, aoPressionar: () => _criar(context, recarregar)),
        ],
        construirItem: (context, c) => CartaoLista(
          tituloWidget: Row(
            children: [
              Flexible(child: Text('${c.nome} - ${c.uf}', style: TipografiaTrato.corpoForte)),
              const SizedBox(width: EspacosTrato.x2),
              ChipEstado(c.ativa ? 'Ativa' : 'Inativa', tom: c.ativa ? Tom.ok : Tom.neutro),
            ],
          ),
          titulo: '${c.nome} - ${c.uf}',
          linhas: [c.ativa ? 'Atendimento ativo para novos pedidos' : 'Atendimento inativo para novos pedidos'],
          acoes: [
            BotaoTrato.link(c.ativa ? 'Desativar' : 'Ativar', aoPressionar: () => _alternar(context, c, recarregar)),
          ],
        ),
      ),
    );
  }
}

// =============================================================================================
// PERGUNTAS DA CATEGORIA
// =============================================================================================

class _DialogPerguntas extends StatefulWidget {
  const _DialogPerguntas({required this.categoria});
  final CategoriaAdmin categoria;

  @override
  State<_DialogPerguntas> createState() => _DialogPerguntasState();
}

class _DialogPerguntasState extends State<_DialogPerguntas> {
  int _versao = 0;

  Future<void> _adicionar(BuildContext context) async {
    final texto = TextEditingController();
    final opcoes = TextEditingController();
    var tipo = 'texto';
    var obrigatoria = false;
    final r = await pedirFormulario<String>(
      context,
      titulo: 'Nova pergunta para "${widget.categoria.nome}"',
      consequencia: 'A pergunta aparece para o cliente ao pedir este serviço.',
      rotuloConfirmar: 'Adicionar pergunta',
      campos: (ctx, rebuild) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: texto,
            onChanged: (_) => rebuild(),
            decoration: const InputDecoration(labelText: 'Texto da pergunta', helperText: 'Ex.: Qual a voltagem do imóvel?'),
          ),
          const SizedBox(height: EspacosTrato.x3),
          SeletorTrato<String>(
            rotulo: 'Tipo de resposta',
            valor: tipo,
            opcoes: const [
              ('texto', 'Resposta em texto'),
              ('numero', 'Número ou quantidade'),
              ('escolha_unica', 'Escolha única'),
              ('multipla', 'Múltipla escolha'),
              ('sim_nao', 'Sim ou não'),
            ],
            aoMudar: (v) {
              tipo = v;
              rebuild();
            },
          ),
          if (tipo == 'escolha_unica' || tipo == 'multipla') ...[
            const SizedBox(height: EspacosTrato.x3),
            TextField(
              controller: opcoes,
              onChanged: (_) => rebuild(),
              decoration: const InputDecoration(labelText: 'Opções', helperText: 'Separadas por vírgula: 110V, 220V, Bivolt'),
            ),
          ],
          CheckboxListTile(
            title: const Text('Pergunta obrigatória'),
            value: obrigatoria,
            contentPadding: EdgeInsets.zero,
            onChanged: (v) {
              obrigatoria = v ?? false;
              rebuild();
            },
          ),
        ],
      ),
      camposValidos: () => texto.text.trim().length >= 3 && ((tipo != 'escolha_unica' && tipo != 'multipla') || opcoes.text.trim().isNotEmpty),
      resultado: (motivo) => motivo,
    );
    if (r == null || !mounted) return;
    final lista = (tipo == 'escolha_unica' || tipo == 'multipla')
        ? opcoes.text.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList()
        : null;
    final ok = await executar(
      this.context,
      () => this.context.api.criarPerguntaCategoria(
            widget.categoria.id,
            texto: texto.text.trim(),
            tipo: tipo,
            opcoes: lista,
            obrigatoria: obrigatoria,
            motivo: r,
          ),
      sucesso: 'Pergunta adicionada.',
    );
    if (ok && mounted) setState(() => _versao++);
  }

  Future<void> _desativar(PerguntaCategoriaAdmin p) async {
    final motivo = await pedirMotivo(
      context,
      titulo: 'Desativar a pergunta?',
      descricao: 'Ela deixa de ser feita para novos pedidos desta categoria.',
      rotuloConfirmar: 'Desativar pergunta',
    );
    if (motivo == null || !mounted) return;
    final ok = await executar(
      context,
      () => context.api.desativarPerguntaCategoria(widget.categoria.id, p.id, motivo: motivo),
      sucesso: 'Pergunta desativada.',
    );
    if (ok && mounted) setState(() => _versao++);
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.all(EspacosTrato.x4),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640, maxHeight: 560),
        child: Padding(
          padding: const EdgeInsets.all(EspacosTrato.x6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(child: Text('Perguntas: ${widget.categoria.nome}', style: TipografiaTrato.secao)),
                  BotaoTrato.primario('Nova pergunta', icone: IconesTrato.adicionar, aoPressionar: () => _adicionar(context)),
                ],
              ),
              const SizedBox(height: EspacosTrato.x3),
              Expanded(
                child: CarregaDados<List<PerguntaCategoriaAdmin>>(
                  key: ValueKey('perguntas-${widget.categoria.id}-$_versao'),
                  carregar: () => context.api.listarPerguntasCategoria(widget.categoria.id),
                  estaVazio: (l) => l.isEmpty,
                  mensagemVazia: 'Nenhuma pergunta cadastrada',
                  detalheVazio: 'As perguntas ajudam o profissional a entender o serviço antes de orçar.',
                  esqueleto: const EsqueletoLista(linhas: 3),
                  construir: (context, lista, _) => ListView.separated(
                    itemCount: lista.length,
                    separatorBuilder: (_, _) => const Divider(),
                    itemBuilder: (context, i) {
                      final p = lista[i];
                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(p.texto, style: TipografiaTrato.corpoForte),
                                Text(
                                  '${p.obrigatoria ? 'Obrigatória' : 'Opcional'}'
                                  '${p.opcoes != null ? ' · ${p.opcoes!.join(', ')}' : ''}',
                                  style: TipografiaTrato.legenda,
                                ),
                              ],
                            ),
                          ),
                          ChipEstado(p.ativa ? 'Ativa' : 'Inativa', tom: p.ativa ? Tom.ok : Tom.neutro),
                          if (p.ativa)
                            BotaoIcone(
                              icone: IconesTrato.desativar,
                              rotulo: 'Desativar pergunta',
                              aoPressionar: () => _desativar(p),
                            ),
                        ],
                      );
                    },
                  ),
                ),
              ),
              const SizedBox(height: EspacosTrato.x3),
              Align(
                alignment: Alignment.centerRight,
                child: BotaoTrato.secundario('Fechar', aoPressionar: () => Navigator.of(context).pop()),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
