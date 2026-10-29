import 'package:flutter/material.dart';

import '../../componentes/componentes.dart';
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
    this.aoConcluir,
    this.nomeInicial = '',
  });

  final ServicoCadastroProfissional servico;
  final CapturarFoto? aoAdicionarFoto;

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
    required this.aoConcluir,
    required this.nomeInicial,
  });

  final OpcoesCadastro opcoes;
  final ServicoCadastroProfissional servico;
  final CapturarFoto? aoAdicionarFoto;
  final VoidCallback? aoConcluir;
  final String nomeInicial;

  @override
  State<_Formulario> createState() => _FormularioState();
}

class _FormularioState extends State<_Formulario> {
  late final _nome = TextEditingController(text: widget.nomeInicial);
  final _sobre = TextEditingController();
  final _cidade = TextEditingController();
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
    _cidade.dispose();
    super.dispose();
  }

  String? get _erroNome => _nome.text.trim().length < 3 ? 'Informe seu nome completo' : null;
  String? get _erroCidade => _cidade.text.trim().isEmpty ? 'Informe a cidade ou bairro' : null;

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
    final ref = await widget.aoAdicionarFoto?.call();
    if (ref != null && mounted) setState(() => _portfolio.add(ref));
  }

  Future<void> _salvar() async {
    setState(() {
      _tentou = true;
      _erroEnvio = null;
    });
    if (!_valido) return;
    setState(() => _enviando = true);
    try {
      await widget.servico.salvar(DadosCadastroProfissional(
        nome: _nome.text.trim(),
        sobre: _sobre.text.trim(),
        categorias: {..._categorias},
        cidade: _cidade.text.trim(),
        raioKm: _raio,
        dias: {..._dias},
        periodos: {..._periodos},
        portfolio: [..._portfolio],
      ));
      if (!mounted) return;
      setState(() => _enviando = false);
      widget.aoConcluir?.call();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _enviando = false;
        _erroEnvio = 'Não foi possível salvar. Tente de novo.';
      });
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
        if (_tentou && _categorias.isEmpty) _erro('Escolha pelo menos uma categoria'),
        const TituloSecao('Área atendida'),
        CampoTrato(
          rotulo: 'Cidade ou bairro base',
          controlador: _cidade,
          erro: _tentou ? _erroCidade : null,
          aoMudar: (_) => setState(() {}),
        ),
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
        if (_tentou && _dias.isEmpty) _erro('Escolha pelo menos um dia'),
        const SizedBox(height: EspacosTrato.x3),
        OpcoesPilula(
          opcoes: o.periodos,
          selecionadas: _periodos,
          aoAlternar: (v) => _alternar(_periodos, v),
        ),
        if (_tentou && _periodos.isEmpty) _erro('Escolha pelo menos um período'),
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
  const _MiniFoto({required this.numero, required this.aoRemover});

  final int numero;
  final VoidCallback aoRemover;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 96,
      height: 96,
      decoration: BoxDecoration(
        color: CoresTrato.azulClaro,
        borderRadius: BorderRadius.circular(EspacosTrato.raio),
      ),
      child: Stack(
        children: [
          Center(child: Text('Foto $numero', style: TipografiaTrato.corpoPequeno)),
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
