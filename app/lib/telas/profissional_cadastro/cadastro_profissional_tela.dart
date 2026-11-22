import 'package:flutter/material.dart';

import '../../componentes/componentes.dart';
import '../../dados/erros.dart';
import '../../dados/paralelo.dart';
import '../../dados/servico_cep.dart';
import '../../tema/tema.dart';
import '../comuns/foco_rolagem.dart';
import '../profissional_apoio/apoio.dart';
import 'cadastro.dart';
import 'componentes_cadastro.dart';

/// F6.1 / F57: cadastro do profissional em 4 passos (cadastro inicial) ou 4 seções
/// editáveis (modo edição). A tela só coleta; o backend valida e grava.
/// [aoAdicionarFoto] abre câmera/galeria fora da tela e devolve a referência da foto.
class CadastroProfissionalTela extends StatelessWidget {
  const CadastroProfissionalTela({
    super.key,
    required this.servico,
    this.aoAdicionarFoto,
    this.aoAdicionarFotos,
    this.aoConcluir,
    this.nomeInicial = '',
    this.edicao = false,
    this.servicoCep,
  });

  final ServicoCadastroProfissional servico;
  final ServicoCep? servicoCep;
  final CapturarFoto? aoAdicionarFoto;
  final Future<List<String>> Function()? aoAdicionarFotos;

  /// Chamado depois que o serviço salvou com sucesso.
  final VoidCallback? aoConcluir;
  final String nomeInicial;

  /// Profissional já cadastrado mudando os dados: abre em modo edição por seções.
  final bool edicao;

  @override
  Widget build(BuildContext context) {
    return PaginaCarregavel<(OpcoesCadastro, DadosCadastroProfissional?)>(
      titulo: 'Seu cadastro',
      // Opções primeiro: o serviço real reaproveita essa carga para traduzir o cadastro salvo.
      carregar: () => emParalelo2(servico.carregarOpcoes(), servico.carregarAtual()),
      estaVazio: (d) => d.$1.vazio,
      tituloVazio: 'Cadastro indisponível agora',
      textoVazio: 'Ainda não há categorias para escolher. Volte daqui a pouco.',
      construir: (context, d) => _FormularioCadastroProfissional(
        opcoes: d.$1,
        atual: d.$2,
        servico: servico,
        servicoCep: servicoCep,
        aoAdicionarFoto: aoAdicionarFoto,
        aoAdicionarFotos: aoAdicionarFotos,
        aoConcluir: aoConcluir,
        nomeInicial: nomeInicial,
        edicao: edicao,
      ),
    );
  }
}

enum _SecaoEdicao { dadosBasicos, categorias, areaHorarios, portfolio }

class _FormularioCadastroProfissional extends StatefulWidget {
  const _FormularioCadastroProfissional({
    required this.opcoes,
    required this.atual,
    required this.servico,
    this.servicoCep,
    required this.aoAdicionarFoto,
    required this.aoAdicionarFotos,
    required this.aoConcluir,
    required this.nomeInicial,
    required this.edicao,
  });

  final OpcoesCadastro opcoes;
  final DadosCadastroProfissional? atual;
  final ServicoCadastroProfissional servico;
  final ServicoCep? servicoCep;
  final CapturarFoto? aoAdicionarFoto;
  final Future<List<String>> Function()? aoAdicionarFotos;
  final VoidCallback? aoConcluir;
  final String nomeInicial;
  final bool edicao;

  @override
  State<_FormularioCadastroProfissional> createState() =>
      _FormularioCadastroProfissionalState();
}

class _FormularioCadastroProfissionalState
    extends State<_FormularioCadastroProfissional> {
  static const _totalPassos = 4;

  // O cadastro salvo preenche o formulário; só entra o que ainda está entre as opções
  // (categoria ou cidade desativada não volta marcada).
  late final DadosCadastroProfissional? _atual = widget.atual;
  late final _nome = TextEditingController(
    text: (_atual?.nome.trim().isNotEmpty ?? false) ? _atual!.nome : widget.nomeInicial,
  );
  late final _sobre = TextEditingController(text: _atual?.sobre ?? '');
  final _cep = TextEditingController();
  late String? _cidade =
      widget.opcoes.cidades.contains(_atual?.cidade) ? _atual!.cidade : null;
  String? _avisoCep;
  final _scrollController = ScrollController();
  final _focoNome = FocusNode();
  final _focoCep = FocusNode();
  late final _categorias = <String>{
    ...?_atual?.categorias.where(widget.opcoes.categorias.contains),
  };
  late final _dias = <String>{...?_atual?.dias.where(widget.opcoes.dias.contains)};
  late final _periodos = <String>{
    ...?_atual?.periodos.where(widget.opcoes.periodos.contains),
  };
  late final _portfolio = <String>[...?_atual?.portfolio];
  late int _raio = widget.opcoes.raiosKm.contains(_atual?.raioKm)
      ? _atual!.raioKm
      : (widget.opcoes.raiosKm.isEmpty ? 0 : widget.opcoes.raiosKm.first);
  late final _modalidades = <String>{
    if (_atual?.atendePresencial ?? true) 'Presencial',
    if (_atual?.atendeRemoto ?? false) 'Remoto',
  };

  /// Modo edição ativa quando `edicao` é true ou quando já existe cadastro preenchido.
  late final bool _modoEdicao = widget.edicao ||
      (_atual != null && _nome.text.trim().isNotEmpty && _categorias.isNotEmpty);

  int _passo = 0;
  _SecaoEdicao? _secaoAberta;
  final Set<int> _passosValidados = {};
  bool _tentouSalvar = false;
  bool _enviando = false;
  String? _erroEnvio;

  @override
  void dispose() {
    _nome.dispose();
    _sobre.dispose();
    _cep.dispose();
    _focoNome.dispose();
    _focoCep.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _aplicarCep(EnderecoPorCep end) {
    final alvo = normalizarTextoBusca(end.cidade);
    String? combinada;
    for (final op in widget.opcoes.cidades) {
      final nomeOp = normalizarTextoBusca(op.split('·').first.split('/').first);
      if (nomeOp == alvo || (alvo.isNotEmpty && nomeOp.contains(alvo))) {
        combinada = op;
        break;
      }
    }
    setState(() {
      if (combinada != null) {
        _cidade = combinada;
        _avisoCep = end.bairro.isNotEmpty
            ? 'Cidade selecionada: $combinada (${end.bairro}).'
            : 'Cidade selecionada: $combinada.';
      } else {
        _avisoCep =
            'Ainda não atendemos ${end.cidade}/${end.uf}. Escolha abaixo uma cidade disponível.';
      }
    });
  }

  String? get _erroNome => _nome.text.trim().length < 3
      ? 'Informe seu nome completo (mínimo 3 letras).'
      : null;

  String? get _erroCategorias =>
      _categorias.isEmpty ? 'Escolha pelo menos uma categoria.' : null;

  String? get _erroModalidades => _modalidades.isEmpty
      ? 'Escolha atender presencial, remoto ou os dois.'
      : null;

  String? get _erroCidade =>
      _cidade == null ? 'Escolha a cidade onde você atende.' : null;

  String? get _erroDias => _dias.isEmpty ? 'Escolha pelo menos um dia.' : null;

  String? get _erroPeriodos =>
      _periodos.isEmpty ? 'Escolha pelo menos um período.' : null;

  bool get _passo1Valido => _erroNome == null;

  bool get _passo2Valido => _erroCategorias == null;

  bool get _passo3Valido =>
      _erroCidade == null &&
      _erroModalidades == null &&
      _erroDias == null &&
      _erroPeriodos == null;

  bool get _valido => _passo1Valido && _passo2Valido && _passo3Valido;

  bool _deveMostrarErroPasso(int passo) =>
      _tentouSalvar || _passosValidados.contains(passo);

  void _alternar(Set<String> conjunto, String valor) => setState(() {
        conjunto.contains(valor) ? conjunto.remove(valor) : conjunto.add(valor);
      });

  void _rolarParaTopo() {
    if (_scrollController.hasClients) {
      _scrollController.jumpTo(0);
    }
  }

  void _avancarPasso() {
    setState(() {
      _passosValidados.add(_passo);
      _erroEnvio = null;
    });
    if (_passo == 0 && !_passo1Valido) {
      _focoNome.requestFocus();
      return;
    }
    if (_passo == 1 && !_passo2Valido) {
      return;
    }
    if (_passo == 2 && !_passo3Valido) {
      return;
    }
    if (_passo < _totalPassos - 1) {
      setState(() => _passo++);
      _rolarParaTopo();
    }
  }

  void _voltarPasso() {
    if (_passo <= 0) return;
    setState(() {
      _passo--;
      _erroEnvio = null;
    });
    _rolarParaTopo();
  }

  void _abrirSecao(_SecaoEdicao secao) {
    setState(() {
      _secaoAberta = secao;
      _erroEnvio = null;
    });
    _rolarParaTopo();
  }

  void _fecharSecao() {
    setState(() {
      _secaoAberta = null;
      _erroEnvio = null;
    });
    _rolarParaTopo();
  }

  Future<void> _adicionarFoto() async {
    if (widget.aoAdicionarFotos != null) {
      final refs = await widget.aoAdicionarFotos!();
      if (refs.isNotEmpty && mounted) {
        setState(() => _portfolio.addAll(refs));
      }
      return;
    }
    final ref = await widget.aoAdicionarFoto?.call();
    if (ref != null && mounted) setState(() => _portfolio.add(ref));
  }

  Future<void> _salvar() async {
    if (_enviando) return;
    setState(() {
      _tentouSalvar = true;
      _passosValidados.addAll([0, 1, 2]);
      _erroEnvio = null;
    });

    if (!_valido) {
      if (!_modoEdicao) {
        final passoComErro = !_passo1Valido ? 0 : (!_passo2Valido ? 1 : 2);
        if (_passo != passoComErro) {
          setState(() => _passo = passoComErro);
          _rolarParaTopo();
        }
        if (passoComErro == 0) _focoNome.requestFocus();
      } else if (_secaoAberta == null) {
        final secaoComErro = !_passo1Valido
            ? _SecaoEdicao.dadosBasicos
            : (!_passo2Valido
                ? _SecaoEdicao.categorias
                : _SecaoEdicao.areaHorarios);
        setState(() => _secaoAberta = secaoComErro);
        _rolarParaTopo();
      }
      return;
    }

    setState(() => _enviando = true);
    try {
      await widget.servico.salvar(DadosCadastroProfissional(
        nome: _nome.text.trim(),
        sobre: _sobre.text.trim(),
        categorias: {..._categorias},
        cidade: _cidade!,
        raioKm: _raio,
        dias: {..._dias},
        periodos: {..._periodos},
        portfolio: [..._portfolio],
        atendePresencial: _modalidades.contains('Presencial'),
        atendeRemoto: _modalidades.contains('Remoto'),
      ));
      if (!mounted) return;
      setState(() => _enviando = false);
      widget.aoConcluir?.call();
    } catch (e) {
      if (!mounted) return;
      final motivo = e is ErroTrato &&
              e.tipo != TipoErro.semInternet &&
              e.mensagem.isNotEmpty
          ? e.mensagem
          : null;
      setState(() {
        _enviando = false;
        _erroEnvio = motivo ??
            'Não foi possível salvar os dados. Confira sua conexão e tente novamente.';
      });
    }
  }

  Widget _erroTexto(BuildContext context, String texto) {
    final c = context.cores;
    return Padding(
      padding: const EdgeInsets.only(top: EspacosTrato.x2),
      child: Text(
        texto,
        style: TipografiaTrato.corpoPequeno.copyWith(color: c.vermelhoTexto),
      ),
    );
  }

  List<Widget> _construirPassoDadosBasicos(BuildContext context) {
    final c = context.cores;
    final mostrarErro = _deveMostrarErroPasso(0);
    return [
      CabecalhoPasso(
        titulo: _modoEdicao ? 'Dados básicos' : 'Quem é você',
        subtitulo: 'Essas informações aparecem no seu perfil para os clientes.',
        destaque: _modoEdicao
            ? null
            : 'Sem taxa de serviço. Receba pedidos direto no celular.',
      ),
      const SizedBox(height: EspacosTrato.x6),
      CampoTrato(
        rotulo: 'Nome completo',
        dica: 'Como os clientes vão encontrar você',
        controlador: _nome,
        foco: _focoNome,
        acaoTeclado: TextInputAction.next,
        erro: mostrarErro ? _erroNome : null,
        aoMudar: (_) => setState(() {}),
      ),
      const SizedBox(height: EspacosTrato.x5),
      Text(
        'Sobre você (opcional)',
        style: TipografiaTrato.corpoForte.copyWith(color: c.texto),
      ),
      const SizedBox(height: EspacosTrato.x2),
      TextField(
        controller: _sobre,
        minLines: 3,
        maxLines: 5,
        keyboardType: TextInputType.multiline,
        textCapitalization: TextCapitalization.sentences,
        style: TipografiaTrato.corpo.copyWith(color: c.texto),
        decoration: const InputDecoration(
          hintText: 'Anos de experiência, o que você faz melhor',
        ),
        onChanged: (_) => setState(() {}),
      ),
    ];
  }

  List<Widget> _construirPassoCategorias(BuildContext context) {
    final categoriasOrdenadas = [...widget.opcoes.categorias]
      ..sort(compararAlfabeticoPtBr);
    final travadas = _modoEdicao &&
        (_atual?.categoriasTravadas ?? false) &&
        _categorias.isNotEmpty;
    final mostrarErro = _deveMostrarErroPasso(1);

    return [
      CabecalhoPasso(
        titulo: _modoEdicao ? 'Categorias' : 'O que você faz',
        subtitulo: travadas
            ? 'Suas áreas de atuação vinculadas à verificação.'
            : 'Escolha as categorias em que você atende. Pode marcar mais de uma.',
      ),
      const SizedBox(height: EspacosTrato.x6),
      if (travadas) ...[
        PilulasSelecao(
          opcoes: _categorias.toList()..sort(compararAlfabeticoPtBr),
          selecionadas: _categorias,
          travado: true,
          aoAlternar: (_) {},
        ),
        const SizedBox(height: EspacosTrato.x4),
        const AvisoFaixa(
          texto:
              'Categorias vinculadas à sua verificação. Para atuar em novas áreas, é necessário passar por nova verificação. Sem custo.',
          tipo: TipoStatus.info,
          icone: Icons.lock_outline,
        ),
      ] else ...[
        PilulasSelecao(
          opcoes: categoriasOrdenadas,
          selecionadas: _categorias,
          aoAlternar: (v) => _alternar(_categorias, v),
        ),
        if (mostrarErro && _erroCategorias != null)
          _erroTexto(context, _erroCategorias!),
      ],
    ];
  }

  List<Widget> _construirPassoAreaHorarios(BuildContext context) {
    final c = context.cores;
    final o = widget.opcoes;
    final cidadesOrdenadas = [...o.cidades]..sort(compararAlfabeticoPtBr);
    final mostrarErro = _deveMostrarErroPasso(2);

    return [
      CabecalhoPasso(
        titulo: _modoEdicao ? 'Área e horários' : 'Onde e quando atende',
        subtitulo:
            'Escolha sua cidade, distância e os horários em que pode receber pedidos.',
      ),
      const SizedBox(height: EspacosTrato.x6),
      Text('Cidade', style: TipografiaTrato.corpoForte.copyWith(color: c.texto)),
      const SizedBox(height: EspacosTrato.x2),
      PilulasSelecao(
        opcoes: cidadesOrdenadas,
        selecionadas: {if (_cidade != null) _cidade!},
        aoAlternar: (v) => setState(() => _cidade = v),
      ),
      if (mostrarErro && _erroCidade != null) _erroTexto(context, _erroCidade!),
      const SizedBox(height: EspacosTrato.x5),
      CampoCepAutoPreenchimento(
        rotulo: 'CEP da sua região (opcional)',
        controlador: _cep,
        servico: widget.servicoCep,
        foco: _focoCep,
        aoEncontrar: _aplicarCep,
      ),
      if (_avisoCep != null) ...[
        const SizedBox(height: EspacosTrato.x2),
        Text(
          _avisoCep!,
          style: TipografiaTrato.corpoPequeno.copyWith(color: c.azulTexto),
        ),
      ],
      if (o.raiosKm.isNotEmpty) ...[
        const SizedBox(height: EspacosTrato.x5),
        Text(
          'Até onde você vai',
          style: TipografiaTrato.corpoForte.copyWith(color: c.texto),
        ),
        const SizedBox(height: EspacosTrato.x2),
        PilulasSelecao(
          opcoes: [for (final r in o.raiosKm) '$r km'],
          selecionadas: {'$_raio km'},
          aoAlternar: (v) => setState(() => _raio = int.parse(v.split(' ').first)),
        ),
      ],
      const SizedBox(height: EspacosTrato.x5),
      Text(
        'Como você atende',
        style: TipografiaTrato.corpoForte.copyWith(color: c.texto),
      ),
      const SizedBox(height: EspacosTrato.x1),
      Text(
        'Presencial no local do cliente, remoto ou os dois.',
        style: TipografiaTrato.corpoPequeno.copyWith(color: c.textoSecundario),
      ),
      const SizedBox(height: EspacosTrato.x2),
      PilulasSelecao(
        opcoes: const ['Presencial', 'Remoto'],
        selecionadas: _modalidades,
        aoAlternar: (v) => _alternar(_modalidades, v),
      ),
      if (mostrarErro && _erroModalidades != null)
        _erroTexto(context, _erroModalidades!),
      const SizedBox(height: EspacosTrato.x6),
      BlocoDisponibilidade(
        dias: o.dias,
        diasSelecionados: _dias,
        aoAlternarDia: (v) => _alternar(_dias, v),
        periodos: o.periodos,
        periodosSelecionados: _periodos,
        aoAlternarPeriodo: (v) => _alternar(_periodos, v),
        erroDias: mostrarErro ? _erroDias : null,
        erroPeriodos: mostrarErro ? _erroPeriodos : null,
      ),
    ];
  }

  List<Widget> _construirPassoPortfolio(BuildContext context) {
    final podeAdicionar =
        widget.aoAdicionarFoto != null || widget.aoAdicionarFotos != null;
    return [
      const CabecalhoPasso(
        titulo: 'Portfólio (opcional)',
        subtitulo:
            'Adicione fotos de trabalhos que você já fez para passar mais confiança.',
      ),
      const SizedBox(height: EspacosTrato.x6),
      GradePortfolio(
        fotos: _portfolio,
        urlsDasFotos: _atual?.urlsDasFotos ?? const {},
        aoRemover: (i) => setState(() => _portfolio.removeAt(i)),
        aoAdicionar: podeAdicionar ? _adicionarFoto : null,
      ),
    ];
  }

  String _resumoDadosBasicos() {
    final nome = _nome.text.trim();
    final sobre = _sobre.text.trim();
    if (nome.isEmpty) return 'Preencha seu nome completo';
    if (sobre.isEmpty) return nome;
    return '$nome · $sobre';
  }

  String _resumoCategorias() {
    if (_categorias.isEmpty) return 'Escolha pelo menos uma categoria';
    final ordenadas = _categorias.toList()..sort(compararAlfabeticoPtBr);
    return ordenadas.join(', ');
  }

  String _resumoAreaHorarios() {
    final partes = <String>[];
    if (_cidade != null) partes.add(_cidade!);
    if (widget.opcoes.raiosKm.isNotEmpty && _raio > 0) partes.add('$_raio km');
    if (_dias.isNotEmpty) partes.add(_dias.join(', '));
    if (_periodos.isNotEmpty) partes.add(_periodos.join(', '));
    if (partes.isEmpty) return 'Defina cidade e disponibilidade';
    return partes.join(' · ');
  }

  String _resumoPortfolio() {
    if (_portfolio.isEmpty) return 'Nenhuma foto adicionada';
    if (_portfolio.length == 1) return '1 foto adicionada';
    return '${_portfolio.length} fotos adicionadas';
  }

  List<Widget> _construirVisaoGeralEdicao(BuildContext context) {
    return [
      const CabecalhoPasso(
        titulo: 'Editar cadastro',
        subtitulo: 'Toque na seção que deseja atualizar.',
      ),
      const SizedBox(height: EspacosTrato.x6),
      ListaSecoesEdicao(
        secoes: [
          ResumoSecaoCadastro(
            titulo: 'Dados básicos',
            resumo: _resumoDadosBasicos(),
            icone: Icons.person_outline,
            pendente: _tentouSalvar && !_passo1Valido,
            aoTocar: () => _abrirSecao(_SecaoEdicao.dadosBasicos),
          ),
          ResumoSecaoCadastro(
            titulo: 'Categorias',
            resumo: _resumoCategorias(),
            icone: (_atual?.categoriasTravadas ?? false)
                ? Icons.lock_outline
                : Icons.handyman_outlined,
            pendente: _tentouSalvar && !_passo2Valido,
            aoTocar: () => _abrirSecao(_SecaoEdicao.categorias),
          ),
          ResumoSecaoCadastro(
            titulo: 'Área e horários',
            resumo: _resumoAreaHorarios(),
            icone: Icons.location_on_outlined,
            pendente: _tentouSalvar && !_passo3Valido,
            aoTocar: () => _abrirSecao(_SecaoEdicao.areaHorarios),
          ),
          ResumoSecaoCadastro(
            titulo: 'Portfólio',
            resumo: _resumoPortfolio(),
            icone: Icons.photo_library_outlined,
            aoTocar: () => _abrirSecao(_SecaoEdicao.portfolio),
          ),
        ],
      ),
    ];
  }

  List<Widget> _construirConteudo(BuildContext context) {
    if (_modoEdicao) {
      return switch (_secaoAberta) {
        null => _construirVisaoGeralEdicao(context),
        _SecaoEdicao.dadosBasicos => _construirPassoDadosBasicos(context),
        _SecaoEdicao.categorias => _construirPassoCategorias(context),
        _SecaoEdicao.areaHorarios => _construirPassoAreaHorarios(context),
        _SecaoEdicao.portfolio => _construirPassoPortfolio(context),
      };
    }

    return [
      BarraProgressoPassos(
        passoAtual: _passo,
        totalPassos: _totalPassos,
      ),
      const SizedBox(height: EspacosTrato.x6),
      ...switch (_passo) {
        0 => _construirPassoDadosBasicos(context),
        1 => _construirPassoCategorias(context),
        2 => _construirPassoAreaHorarios(context),
        _ => _construirPassoPortfolio(context),
      },
    ];
  }

  Widget _construirRodape(BuildContext context) {
    final c = context.cores;
    final Widget acoes;

    if (_modoEdicao) {
      if (_secaoAberta == null) {
        acoes = BotaoPrimario(
          texto: 'Salvar alterações',
          carregando: _enviando,
          aoTocar: _salvar,
        );
      } else {
        acoes = Row(
          children: [
            Expanded(
              flex: 2,
              child: BotaoSecundario(
                texto: 'Voltar',
                aoTocar: _enviando ? null : _fecharSecao,
              ),
            ),
            const SizedBox(width: EspacosTrato.x3),
            Expanded(
              flex: 3,
              child: BotaoPrimario(
                texto: 'Salvar alterações',
                carregando: _enviando,
                aoTocar: _salvar,
              ),
            ),
          ],
        );
      }
    } else if (_passo == 0) {
      acoes = BotaoPrimario(
        texto: 'Continuar',
        aoTocar: _avancarPasso,
      );
    } else if (_passo < _totalPassos - 1) {
      acoes = Row(
        children: [
          Expanded(
            flex: 2,
            child: BotaoSecundario(
              texto: 'Voltar',
              aoTocar: _voltarPasso,
            ),
          ),
          const SizedBox(width: EspacosTrato.x3),
          Expanded(
            flex: 3,
            child: BotaoPrimario(
              texto: 'Continuar',
              aoTocar: _avancarPasso,
            ),
          ),
        ],
      );
    } else {
      acoes = Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                flex: 2,
                child: BotaoSecundario(
                  texto: 'Voltar',
                  aoTocar: _enviando ? null : _voltarPasso,
                ),
              ),
              const SizedBox(width: EspacosTrato.x3),
              Expanded(
                flex: 3,
                child: BotaoPrimario(
                  texto: 'Salvar cadastro',
                  carregando: _enviando,
                  aoTocar: _salvar,
                ),
              ),
            ],
          ),
          if (_portfolio.isEmpty) ...[
            const SizedBox(height: EspacosTrato.x2),
            BotaoLink(
              texto: 'Pular por enquanto',
              aoTocar: _enviando ? null : _salvar,
            ),
          ],
        ],
      );
    }

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: c.superficie,
        border: Border(
          top: BorderSide(color: c.borda, width: EspacosTrato.bordaFina),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: EspacosTrato.x4),
          child: ConteudoResponsivo(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_erroEnvio != null) ...[
                  AvisoFaixa(
                    texto: _erroEnvio!,
                    tipo: TipoStatus.perigo,
                    icone: Icons.error_outline,
                  ),
                  const SizedBox(height: EspacosTrato.x3),
                ],
                acoes,
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: SafeArea(
            bottom: false,
            child: SingleChildScrollView(
              controller: _scrollController,
              padding: const EdgeInsets.only(
                top: EspacosTrato.x3,
                bottom: EspacosTrato.x6,
              ),
              child: ConteudoResponsivo(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: _construirConteudo(context),
                ),
              ),
            ),
          ),
        ),
        _construirRodape(context),
      ],
    );
  }
}
