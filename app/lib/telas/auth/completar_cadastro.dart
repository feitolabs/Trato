/// Termos 4.1 e 4.2: o Trato é para maiores de 18 anos. Quem entra sem data de nascimento
/// (Google, Apple ou conta antiga) completa o cadastro antes de usar o app.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../auth/servico_auth.dart';
import '../../componentes/componentes.dart';
import '../../dados/erros.dart';
import '../../tema/tema.dart';
import '../conta/modelos.dart';
import 'estrutura_auth.dart';
import 'validacao.dart';

const _avisoMenor = 'O cadastro é exclusivo para maiores de 18 anos.';

String _ddmmaaaa(DateTime d) => '${d.day.toString().padLeft(2, '0')}/'
    '${d.month.toString().padLeft(2, '0')}/${d.year.toString().padLeft(4, '0')}';

enum _Estado { livre, conferindo, falta, menor }

/// Fica acima do navegador: vale para qualquer caminho de entrada (splash, login, link, push).
///
/// A data vem do servidor. Quem já foi conferido fica anotado no aparelho e não depende mais de
/// rede. Se a consulta falhar, a pessoa NÃO fica presa: o app segue e confere de novo depois.
class PortaoCadastro extends StatefulWidget {
  const PortaoCadastro({
    super.key,
    required this.auth,
    required this.ler,
    required this.gravar,
    required this.sair,
    required this.child,
    this.conferirDeNovo,
    this.tempoLimite = const Duration(seconds: 8),
  });

  final ServicoAuth auth;

  /// `GET /v1/me/dados-pessoais`.
  final Future<DadosPessoaisConta> Function() ler;

  /// `PATCH /v1/me/dados-pessoais` com a data de nascimento.
  final Future<DadosPessoaisConta> Function(DateTime nascimento) gravar;

  final Future<void> Function() sair;

  /// Avisos de "vale conferir de novo" (ex.: a conexão voltou).
  final Listenable? conferirDeNovo;
  final Duration tempoLimite;
  final Widget child;

  static String chaveConferido(String usuarioId) => 'cadastro_com_nascimento_$usuarioId';

  @override
  State<PortaoCadastro> createState() => _PortaoCadastroState();
}

class _PortaoCadastroState extends State<PortaoCadastro> with WidgetsBindingObserver {
  StreamSubscription<SessaoAuth?>? _inscricao;
  String? _usuario;
  var _estado = _Estado.livre;

  /// A consulta falhou: o app segue liberado, mas ainda falta conferir.
  var _semResposta = false;
  var _consultando = false;
  var _saindo = false;

  /// Muda a cada troca de pessoa ou gravação: resposta antiga é ignorada.
  var _versao = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.conferirDeNovo?.addListener(_conferirDeNovo);
    _inscricao = widget.auth.sessaoMudou.listen(_aoMudarSessao, onError: (Object _) {});
    _aoMudarSessao(widget.auth.sessaoAtual);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.conferirDeNovo?.removeListener(_conferirDeNovo);
    _inscricao?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _conferirDeNovo();
  }

  void _mudar(_Estado novo) {
    if (mounted && novo != _estado) setState(() => _estado = novo);
  }

  void _aoMudarSessao(SessaoAuth? quem) {
    if (_saindo || quem?.id == _usuario) return;
    _usuario = quem?.id;
    _versao++;
    _semResposta = false;
    _consultando = false;
    if (quem == null) {
      _mudar(_Estado.livre);
      return;
    }
    _mudar(_Estado.conferindo);
    unawaited(_primeiraConferencia(quem.id, _versao));
  }

  Future<void> _primeiraConferencia(String id, int versao) async {
    var conferido = false;
    try {
      conferido = (await SharedPreferences.getInstance())
              .getBool(PortaoCadastro.chaveConferido(id)) ??
          false;
    } on Object {
      conferido = false;
    }
    if (versao != _versao) return;
    if (conferido) {
      _mudar(_Estado.livre);
      return;
    }
    await _consultar();
  }

  void _conferirDeNovo() {
    if (_usuario == null || _saindo || _consultando) return;
    if (_semResposta || _estado == _Estado.falta) unawaited(_consultar());
  }

  Future<void> _consultar() async {
    final versao = _versao;
    _consultando = true;
    try {
      final dados = await widget.ler().timeout(widget.tempoLimite);
      if (versao != _versao) return;
      _avaliar(dados);
    } on Object {
      if (versao != _versao) return;
      // Sem resposta não se sabe se falta algo: quem já estava na tela de completar continua.
      if (_estado == _Estado.falta) return;
      _semResposta = true;
      _mudar(_Estado.livre);
    } finally {
      if (versao == _versao) _consultando = false;
    }
  }

  void _avaliar(DadosPessoaisConta dados) {
    _semResposta = false;
    final nascimento = dados.dataNascimento;
    if (nascimento == null) {
      _mudar(_Estado.falta);
    } else if (ValidacaoAuth.nascimento(_ddmmaaaa(nascimento)) != null) {
      _mudar(_Estado.menor);
    } else {
      final id = _usuario;
      if (id != null) unawaited(_anotar(id));
      _mudar(_Estado.livre);
    }
  }

  Future<void> _anotar(String id) async {
    try {
      await (await SharedPreferences.getInstance())
          .setBool(PortaoCadastro.chaveConferido(id), true);
    } on Object {
      // Sem armazenamento: na próxima abertura pergunta ao servidor de novo.
    }
  }

  Future<void> _salvar(DateTime nascimento) async {
    final versao = _versao;
    final dados = await widget.gravar(nascimento);
    if (versao != _versao) return;
    if (dados.dataNascimento == null) {
      throw const ErroTrato(
        TipoErro.recusado,
        'Não conseguimos salvar sua data de nascimento. Tente de novo.',
      );
    }
    _versao++;
    _consultando = false;
    _avaliar(dados);
  }

  /// A tela continua cobrindo o app até a saída terminar (nada do app aparece no meio).
  Future<void> _sair() async {
    if (_saindo) return;
    _saindo = true;
    try {
      await widget.sair();
    } finally {
      _saindo = false;
      if (mounted) _aoMudarSessao(widget.auth.sessaoAtual);
    }
  }

  @override
  Widget build(BuildContext context) {
    final coberto = _estado != _Estado.livre;
    return Stack(
      fit: StackFit.expand,
      children: [
        // O app continua montado por baixo, mas sem toque, foco ou leitor de tela.
        ExcludeFocus(
          excluding: coberto,
          child: Offstage(offstage: coberto, child: widget.child),
        ),
        if (coberto)
          // Overlay próprio: o campo de texto precisa de um, e aqui estamos fora do navegador.
          Overlay(
            key: ValueKey('portao-${_estado.name}-$_usuario'),
            initialEntries: [
              OverlayEntry(
                builder: (_) => _estado == _Estado.conferindo
                    ? const Scaffold(
                        body: Center(
                          child: CircularProgressIndicator(
                            semanticsLabel: 'Conferindo seu cadastro',
                          ),
                        ),
                      )
                    : CompletarCadastroTela(
                        menor: _estado == _Estado.menor,
                        aoSalvar: _salvar,
                        aoSair: _sair,
                      ),
              ),
            ],
          ),
      ],
    );
  }
}

/// Tela curta "Completar cadastro": só a data de nascimento.
class CompletarCadastroTela extends StatefulWidget {
  const CompletarCadastroTela({
    super.key,
    required this.aoSalvar,
    required this.aoSair,
    this.menor = false,
  });

  final Future<void> Function(DateTime nascimento) aoSalvar;
  final Future<void> Function() aoSair;

  /// O servidor já tem uma data de menor de idade: só resta sair.
  final bool menor;

  @override
  State<CompletarCadastroTela> createState() => _CompletarCadastroTelaState();
}

class _CompletarCadastroTelaState extends State<CompletarCadastroTela> {
  final _nascimento = TextEditingController();
  String? _erroCampo;
  String? _erroEnvio;
  var _salvando = false;
  var _saindo = false;

  @override
  void dispose() {
    _nascimento.dispose();
    super.dispose();
  }

  Future<void> _continuar() async {
    if (_salvando || _saindo) return;
    final invalida = ValidacaoAuth.nascimento(_nascimento.text);
    setState(() {
      _erroCampo = invalida;
      _erroEnvio = null;
      _salvando = invalida == null;
    });
    if (invalida != null) return;
    final partes = _nascimento.text.split('/').map(int.parse).toList();
    try {
      await widget.aoSalvar(DateTime(partes[2], partes[1], partes[0]));
    } on Object catch (e) {
      if (mounted) {
        setState(() => _erroEnvio =
            e is ErroTrato ? e.mensagem : 'Não foi possível salvar. Tente de novo.');
      }
    } finally {
      if (mounted) setState(() => _salvando = false);
    }
  }

  Future<void> _sair() async {
    if (_saindo) return;
    setState(() => _saindo = true);
    try {
      await widget.aoSair();
    } finally {
      if (mounted) setState(() => _saindo = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final secundario = TipografiaTrato.corpo.copyWith(color: context.cores.textoSecundario);
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(vertical: EspacosTrato.x6),
          child: ConteudoResponsivo(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  widget.menor ? 'Cadastro só para maiores de 18 anos' : 'Completar cadastro',
                  style: TipografiaTrato.tituloGrande,
                ),
                const SizedBox(height: EspacosTrato.x2),
                Text(
                  widget.menor
                      ? 'O Trato não é destinado a menores de 18 anos, por isso não dá para '
                          'continuar com esta conta.'
                      : 'O Trato é para maiores de 18 anos. Informe sua data de nascimento para '
                          'continuar.',
                  style: secundario,
                ),
                const SizedBox(height: EspacosTrato.x5),
                if (!widget.menor) ...[
                  CampoTrato(
                    rotulo: 'Data de nascimento',
                    controlador: _nascimento,
                    dica: 'dd/mm/aaaa',
                    teclado: TextInputType.number,
                    formatadores: const [MascaraNumerica.data],
                    erro: _erroCampo,
                    aoMudar: (_) {
                      if (_erroCampo != null || _erroEnvio != null) {
                        setState(() => _erroCampo = _erroEnvio = null);
                      }
                    },
                  ),
                  if (_erroCampo == _avisoMenor) ...[
                    const SizedBox(height: EspacosTrato.x2),
                    Text('Sem 18 anos não dá para continuar.', style: secundario),
                  ],
                  const SizedBox(height: EspacosTrato.x5),
                  MensagemErroAuth(_erroEnvio),
                  BotaoPrimario(
                    texto: _erroEnvio == null ? 'Continuar' : 'Tentar de novo',
                    carregando: _salvando,
                    aoTocar: _continuar,
                  ),
                  const SizedBox(height: EspacosTrato.x3),
                ],
                Center(
                  child: BotaoLink(
                    texto: _saindo ? 'Saindo…' : 'Sair da conta',
                    aoTocar: _sair,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
