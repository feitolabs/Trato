import 'package:flutter/material.dart';

import '../../componentes/componentes.dart';
import '../../dados/erros.dart';
import '../../tema/tema.dart';
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
  });

  final ServicoCadastroProfissional servico;
  final CapturarFoto? aoAdicionarFoto;
  final Future<List<String>> Function()? aoAdicionarFotos;

  /// Chamado depois que o serviço salvou com sucesso.
  final VoidCallback? aoConcluir;
  final String nomeInicial;

  @override
  Widget build(BuildContext context) {
    return PaginaCarregavel<OpcoesCadastro>(
      titulo: 'Seu cadastro',
      carregar: servico.carregarOpcoes,
      estaVazio: (o) => o.vazio,
      tituloVazio: 'Cadastro indisponível agora',
      textoVazio: 'Ainda não há categorias para escolher. Volte daqui a pouco.',
      construir: (context, opcoes) => _Formulario(
        opcoes: opcoes,
        servico: servico,
        aoAdicionarFoto: aoAdicionarFoto,
        aoAdicionarFotos: aoAdicionarFotos,
        aoConcluir: aoConcluir,
        nomeInicial: nomeInicial,
      ),
    );
  }
}

class _Formulario extends StatefulWidget {
  const _Formulario({
    required this.opcoes,
    required this.servico,
    required this.aoAdicionarFoto,
    required this.aoAdicionarFotos,
    required this.aoConcluir,
    required this.nomeInicial,
  });

  final OpcoesCadastro opcoes;
  final ServicoCadastroProfissional servico;
  final CapturarFoto? aoAdicionarFoto;
  final Future<List<String>> Function()? aoAdicionarFotos;
  final VoidCallback? aoConcluir;
  final String nomeInicial;

  @override
  State<_Formulario> createState() => _FormularioState();
}

class _FormularioState extends State<_Formulario> {
  late final _nome = TextEditingController(text: widget.nomeInicial);
  final _sobre = TextEditingController();
  String? _cidade;
  final _scrollController = ScrollController();
  final _categorias = <String>{};
  final _dias = <String>{};
  final _periodos = <String>{};
  final _portfolio = <String>[];
  late int _raio = widget.opcoes.raiosKm.isEmpty ? 0 : widget.opcoes.raiosKm.first;
  bool _tentou = false;
  bool _enviando = false;
  String? _erroEnvio;

  @override
  void dispose() {
    _nome.dispose();
    _sobre.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _rolarParaTopo() {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        0,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  String? get _erroNome => _nome.text.trim().length < 3
      ? 'Nome muito curto. Digite seu nome completo (mínimo de 3 letras).'
      : null;
  String? get _erroCidade =>
      _cidade == null ? 'Cidade não escolhida. Escolha a cidade onde você atende.' : null;

  bool get _valido =>
      _erroNome == null &&
      _erroCidade == null &&
      _categorias.isNotEmpty &&
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
      _rolarParaTopo();
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
      _rolarParaTopo();
    }
  }

  Widget _erro(String texto) => Padding(
        padding: const EdgeInsets.only(top: EspacosTrato.x2),
        child: Text(texto, style: TipografiaTrato.corpoPequeno.copyWith(color: CoresTrato.vermelhoTexto)),
      );

  @override
  Widget build(BuildContext context) {
    final o = widget.opcoes;
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
            texto: 'Salvar e continuar',
            carregando: _enviando,
            aoTocar: _salvar,
          ),
        ],
      ),
      children: [
        Text('Conte quem você é', style: TipografiaTrato.tituloGrande),
        const SizedBox(height: EspacosTrato.x2),
        Text(
          'Essas informações aparecem no seu perfil para os clientes.',
          style: TipografiaTrato.corpo.copyWith(color: CoresTrato.textoSecundario),
        ),
        const SizedBox(height: EspacosTrato.x5),
        CampoTrato(
          rotulo: 'Nome completo',
          controlador: _nome,
          erro: _tentou ? _erroNome : null,
          aoMudar: (_) => setState(() {}),
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
        const TituloSecao('Categorias', ajuda: 'Escolha o que você atende.'),
        OpcoesPilula(
          opcoes: o.categorias,
          selecionadas: _categorias,
          aoAlternar: (v) => _alternar(_categorias, v),
        ),
        if (_tentou && _categorias.isEmpty)
          _erro('Nenhuma categoria selecionada. Escolha pelo menos uma área de atuação.'),
        const TituloSecao('Área atendida'),
        Text('Cidade', style: TipografiaTrato.corpoForte),
        const SizedBox(height: EspacosTrato.x2),
        OpcoesPilula(
          opcoes: o.cidades,
          selecionadas: {if (_cidade != null) _cidade!},
          aoAlternar: (v) => setState(() => _cidade = v),
        ),
        if (_tentou && _erroCidade != null) _erro(_erroCidade!),
        const SizedBox(height: EspacosTrato.x3),
        Text('Até onde você vai', style: TipografiaTrato.corpoForte),
        const SizedBox(height: EspacosTrato.x2),
        OpcoesPilula(
          opcoes: [for (final r in o.raiosKm) '$r km'],
          selecionadas: {'$_raio km'},
          aoAlternar: (v) => setState(() => _raio = int.parse(v.split(' ').first)),
        ),
        const TituloSecao('Disponibilidade', ajuda: 'Você pode mudar quando quiser.'),
        OpcoesPilula(
          opcoes: o.dias,
          selecionadas: _dias,
          aoAlternar: (v) => _alternar(_dias, v),
        ),
        if (_tentou && _dias.isEmpty)
          _erro('Nenhum dia selecionado. Escolha pelo menos um dia da semana para atendimento.'),
        const SizedBox(height: EspacosTrato.x3),
        OpcoesPilula(
          opcoes: o.periodos,
          selecionadas: _periodos,
          aoAlternar: (v) => _alternar(_periodos, v),
        ),
        if (_tentou && _periodos.isEmpty)
          _erro('Nenhum período selecionado. Escolha manhã, tarde ou noite para seus atendimentos.'),
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
                  referencia: _portfolio[i],
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
