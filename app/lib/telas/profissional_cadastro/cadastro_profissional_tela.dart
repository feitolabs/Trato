import 'package:flutter/material.dart';

import '../../componentes/componentes.dart';
import '../../dados/erros.dart';
import '../../dados/paralelo.dart';
import '../../dados/servico_cep.dart';
import '../../tema/tema.dart';
import '../comuns/foco_rolagem.dart';
import '../profissional_apoio/apoio.dart';
import 'cadastro.dart';

/// F6.1: cadastro do profissional (dados, categorias, área atendida, disponibilidade,
/// portfólio simples). A tela só coleta; o backend valida e grava.
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

  /// Profissional já cadastrado mudando os dados: o botão diz "Salvar alterações".
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
      construir: (context, d) => _Formulario(
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

class _Formulario extends StatefulWidget {
  const _Formulario({
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
  State<_Formulario> createState() => _FormularioState();
}

class _FormularioState extends State<_Formulario> {
  // O cadastro salvo preenche o formulário; só entra o que ainda está entre as opções
  // (categoria ou cidade desativada não volta marcada).
  late final DadosCadastroProfissional? _atual = widget.atual;
  late final _nome = TextEditingController(
    text: (_atual?.nome.trim().isNotEmpty ?? false) ? _atual!.nome : widget.nomeInicial,
  );
  late final _sobre = TextEditingController(text: _atual?.sobre ?? '');
  final _cep = TextEditingController();
  late String? _cidade = widget.opcoes.cidades.contains(_atual?.cidade) ? _atual!.cidade : null;
  String? _avisoCep;
  final _scrollController = ScrollController();
  final _keyNome = GlobalKey();
  final _keyCategorias = GlobalKey();
  final _keyModalidades = GlobalKey();
  final _keyCidade = GlobalKey();
  final _keyDias = GlobalKey();
  final _keyPeriodos = GlobalKey();
  final _focoNome = FocusNode();
  final _focoCep = FocusNode();
  late final _categorias = <String>{
    ...?_atual?.categorias.where(widget.opcoes.categorias.contains),
  };
  late final _dias = <String>{...?_atual?.dias.where(widget.opcoes.dias.contains)};
  late final _periodos = <String>{...?_atual?.periodos.where(widget.opcoes.periodos.contains)};
  late final _portfolio = <String>[...?_atual?.portfolio];
  late int _raio = widget.opcoes.raiosKm.contains(_atual?.raioKm)
      ? _atual!.raioKm
      : (widget.opcoes.raiosKm.isEmpty ? 0 : widget.opcoes.raiosKm.first);
  late final _modalidades = <String>{
    if (_atual?.atendePresencial ?? true) 'Presencial',
    if (_atual?.atendeRemoto ?? false) 'Remoto',
  };
  bool _tentou = false;
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

  String? get _erroNome =>
      _nome.text.trim().length < 3 ? 'Informe seu nome completo (mínimo 3 letras).' : null;
  String? get _erroCidade => _cidade == null ? 'Escolha a cidade onde você atende.' : null;

  bool get _valido =>
      _erroNome == null &&
      _erroCidade == null &&
      _categorias.isNotEmpty &&
      _modalidades.isNotEmpty &&
      _dias.isNotEmpty &&
      _periodos.isNotEmpty;

  void _alternar(Set<String> conjunto, String valor) => setState(() {
        conjunto.contains(valor) ? conjunto.remove(valor) : conjunto.add(valor);
      });

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
      _tentou = true;
      _erroEnvio = null;
    });
    if (!_valido) {
      focarPrimeiroErro([
        EntradaCampoErro(key: _keyNome, focusNode: _focoNome, temErro: () => _erroNome != null),
        EntradaCampoErro(key: _keyCategorias, temErro: () => _categorias.isEmpty),
        EntradaCampoErro(key: _keyModalidades, temErro: () => _modalidades.isEmpty),
        EntradaCampoErro(key: _keyCidade, temErro: () => _erroCidade != null),
        EntradaCampoErro(key: _keyDias, temErro: () => _dias.isEmpty),
        EntradaCampoErro(key: _keyPeriodos, temErro: () => _periodos.isEmpty),
      ]);
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
      // Recusa com motivo (cidade que ainda não atendemos, categoria fora do ar...): mostra o
      // motivo. "Confira sua conexão" só vale quando a falha foi de rede mesmo.
      final motivo = e is ErroTrato && e.tipo != TipoErro.semInternet && e.mensagem.isNotEmpty
          ? e.mensagem
          : null;
      setState(() {
        _enviando = false;
        _erroEnvio =
            motivo ?? 'Não foi possível salvar os dados. Confira sua conexão e tente novamente.';
      });
    }
  }

  Widget _erro(String texto) => Padding(
        padding: const EdgeInsets.only(top: EspacosTrato.x2),
        child: Text(texto,
            style: TipografiaTrato.corpoPequeno.copyWith(color: CoresTrato.vermelhoTexto)),
      );

  @override
  Widget build(BuildContext context) {
    final o = widget.opcoes;
    final categoriasOrdenadas = [...o.categorias]..sort(compararAlfabeticoPtBr);
    final cidadesOrdenadas = [...o.cidades]..sort(compararAlfabeticoPtBr);
    return CorpoRolavel(
      scrollController: _scrollController,
      rodape: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_erroEnvio != null) ...[
            AvisoFaixa(texto: _erroEnvio!, tipo: TipoStatus.perigo, icone: Icons.error_outline),
            const SizedBox(height: EspacosTrato.x3),
          ],
          BotaoPrimario(
            texto: widget.edicao ? 'Salvar alterações' : 'Salvar e continuar',
            carregando: _enviando,
            aoTocar: _salvar,
          ),
        ],
      ),
      children: [
        Text('Conte quem você é', style: TipografiaTrato.tituloGrande),
        const SizedBox(height: EspacosTrato.x2),
        Text(
          '0% de taxa enquanto crescemos — receba pedidos direto no celular.',
          style: TipografiaTrato.corpoForte.copyWith(color: CoresTrato.petroleo),
        ),
        const SizedBox(height: EspacosTrato.x2),
        Text(
          'Essas informações aparecem no seu perfil para os clientes.',
          style: TipografiaTrato.corpo.copyWith(color: CoresTrato.textoSecundario),
        ),
        const SizedBox(height: EspacosTrato.x5),
        KeyedSubtree(
          key: _keyNome,
          child: CampoTrato(
            rotulo: 'Nome completo',
            controlador: _nome,
            foco: _focoNome,
            erro: _tentou ? _erroNome : null,
            aoMudar: (_) => setState(() {}),
          ),
        ),
        const SizedBox(height: EspacosTrato.x4),
        Text('Sobre você (opcional)', style: TipografiaTrato.corpoForte),
        const SizedBox(height: EspacosTrato.x2),
        TextField(
          controller: _sobre,
          minLines: 3,
          maxLines: 5,
          keyboardType: TextInputType.multiline,
          textCapitalization: TextCapitalization.sentences,
          style: TipografiaTrato.corpo,
          decoration: const InputDecoration(hintText: 'Anos de experiência, o que você faz melhor'),
        ),
        KeyedSubtree(
          key: _keyCategorias,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (widget.edicao &&
                  (_atual?.categoriasTravadas ?? false) &&
                  _categorias.isNotEmpty) ...[
                const TituloSecao('Categorias'),
                OpcoesPilula(
                  opcoes: _categorias.toList()..sort(compararAlfabeticoPtBr),
                  selecionadas: _categorias,
                  aoAlternar: (_) {},
                ),
                const SizedBox(height: EspacosTrato.x2),
                const AvisoFaixa(
                  texto:
                      'Categorias vinculadas à sua verificação. Para atuar em novas áreas, é necessário passar por nova verificação. Sem custo.',
                  tipo: TipoStatus.info,
                  icone: Icons.lock_outline,
                ),
              ] else ...[
                const TituloSecao('Categorias', ajuda: 'Escolha o que você atende.'),
                OpcoesPilula(
                  opcoes: categoriasOrdenadas,
                  selecionadas: _categorias,
                  aoAlternar: (v) => _alternar(_categorias, v),
                ),
                if (_tentou && _categorias.isEmpty) _erro('Escolha pelo menos uma categoria.'),
              ],
            ],
          ),
        ),
        KeyedSubtree(
          key: _keyModalidades,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const TituloSecao(
                'Como você atende',
                ajuda: 'Presencial: você vai até o cliente. Remoto: atendimento à distância nas '
                    'categorias liberadas. Pode marcar os dois.',
              ),
              OpcoesPilula(
                opcoes: const ['Presencial', 'Remoto'],
                selecionadas: _modalidades,
                aoAlternar: (v) => _alternar(_modalidades, v),
              ),
              if (_tentou && _modalidades.isEmpty)
                _erro('Escolha atender presencial, remoto ou os dois.'),
            ],
          ),
        ),
        const TituloSecao('Área atendida'),
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
            style: TipografiaTrato.corpoPequeno.copyWith(color: CoresTrato.petroleo),
          ),
        ],
        const SizedBox(height: EspacosTrato.x4),
        KeyedSubtree(
          key: _keyCidade,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Cidade', style: TipografiaTrato.corpoForte),
              const SizedBox(height: EspacosTrato.x2),
              OpcoesPilula(
                opcoes: cidadesOrdenadas,
                selecionadas: {if (_cidade != null) _cidade!},
                aoAlternar: (v) => setState(() => _cidade = v),
              ),
              if (_tentou && _erroCidade != null) _erro(_erroCidade!),
            ],
          ),
        ),
        if (o.raiosKm.isNotEmpty) ...[
          const SizedBox(height: EspacosTrato.x3),
          Text('Até onde você vai', style: TipografiaTrato.corpoForte),
          const SizedBox(height: EspacosTrato.x2),
          OpcoesPilula(
            opcoes: [for (final r in o.raiosKm) '$r km'],
            selecionadas: {'$_raio km'},
            aoAlternar: (v) => setState(() => _raio = int.parse(v.split(' ').first)),
          ),
        ],
        KeyedSubtree(
          key: _keyDias,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const TituloSecao('Disponibilidade', ajuda: 'Você pode mudar quando quiser.'),
              OpcoesPilula(
                opcoes: o.dias,
                selecionadas: _dias,
                aoAlternar: (v) => _alternar(_dias, v),
              ),
              if (_tentou && _dias.isEmpty) _erro('Escolha pelo menos um dia.'),
            ],
          ),
        ),
        const SizedBox(height: EspacosTrato.x3),
        KeyedSubtree(
          key: _keyPeriodos,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              OpcoesPilula(
                opcoes: o.periodos,
                selecionadas: _periodos,
                aoAlternar: (v) => _alternar(_periodos, v),
              ),
              if (_tentou && _periodos.isEmpty) _erro('Escolha pelo menos um período.'),
            ],
          ),
        ),
        const TituloSecao('Portfólio', ajuda: 'Fotos de trabalhos que você já fez (opcional).'),
        if (_portfolio.isEmpty)
          Text(
            'Nenhuma foto adicionada ainda.',
            style: TipografiaTrato.corpo.copyWith(color: CoresTrato.textoSecundario),
          )
        else
          Wrap(
            spacing: EspacosTrato.x2,
            runSpacing: EspacosTrato.x2,
            children: [
              for (var i = 0; i < _portfolio.length; i++)
                _MiniFoto(
                  numero: i + 1,
                  referencia: _atual?.urlsDasFotos[_portfolio[i]] ?? _portfolio[i],
                  aoRemover: () => setState(() => _portfolio.removeAt(i)),
                ),
            ],
          ),
        const SizedBox(height: EspacosTrato.x3),
        BotaoSecundario(
          texto: 'Adicionar foto',
          icone: Icons.add_a_photo_outlined,
          aoTocar: widget.aoAdicionarFoto == null ? null : _adicionarFoto,
        ),
      ],
    );
  }
}

class _MiniFoto extends StatelessWidget {
  const _MiniFoto({
    required this.numero,
    required this.aoRemover,
    this.referencia,
  });

  final int numero;
  final String? referencia;
  final VoidCallback aoRemover;

  @override
  Widget build(BuildContext context) {
    final imagemReal = construirImagemReal(referencia);
    return Container(
      width: 96,
      height: 96,
      clipBehavior: imagemReal != null ? Clip.antiAlias : Clip.none,
      decoration: BoxDecoration(
        color: CoresTrato.azulClaro,
        borderRadius: BorderRadius.circular(EspacosTrato.raio),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (imagemReal != null)
            ToquePreviewImagem(
              referencia: referencia ?? 'Foto $numero',
              legenda: 'Foto $numero',
              child: imagemReal,
            ),
          Center(
            child: Container(
              padding: imagemReal != null
                  ? const EdgeInsets.symmetric(horizontal: 6, vertical: 2)
                  : EdgeInsets.zero,
              decoration: imagemReal != null
                  ? BoxDecoration(
                      color: CoresTrato.overlayFoto,
                      borderRadius: BorderRadius.circular(4),
                    )
                  : null,
              child: Text(
                'Foto $numero',
                style: imagemReal != null
                    ? TipografiaTrato.legenda.copyWith(color: CoresTrato.textoSobreFoto)
                    : TipografiaTrato.corpoPequeno,
              ),
            ),
          ),
          Positioned(
            top: 0,
            right: 0,
            child: IconButton(
              tooltip: 'Remover foto $numero',
              icon: const Icon(Icons.close, size: 18),
              onPressed: aoRemover,
            ),
          ),
        ],
      ),
    );
  }
}
