import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../../auth/servico_auth.dart';
import '../../componentes/componentes.dart';
import '../../tema/tema.dart';
import '../legal/texto_legal_tela.dart';
import '../onboarding/escolha_perfil_tela.dart';
import '../comuns/desconto_moedas.dart';
import '../comuns/foco_rolagem.dart';
import '../fluxo/rotas.dart';
import 'confirmar_celular_tela.dart';
import 'confirmar_email_tela.dart';
import 'estrutura_auth.dart';
import 'validacao.dart';

/// Tela 5 do protótipo: "Criar conta", passo 1 de 2.
/// Termos e política abrem os textos legais (rascunhos, com aviso de revisão).
class CriarContaTela extends StatefulWidget {
  const CriarContaTela({super.key, this.perfil = PerfilUso.cliente, this.servico});

  final PerfilUso perfil;

  /// Se nulo, usa [ServicoAuthPadrao.atual].
  final ServicoAuth? servico;

  @override
  State<CriarContaTela> createState() => _CriarContaTelaState();
}

class _CriarContaTelaState extends State<CriarContaTela> {
  final _nome = TextEditingController();
  final _celular = TextEditingController();
  final _email = TextEditingController();
  final _senha = TextEditingController();
  final _confirmarSenha = TextEditingController();
  final _scrollController = ScrollController();
  final _keyNome = GlobalKey();
  final _keyCelular = GlobalKey();
  final _keyEmail = GlobalKey();
  final _keySenha = GlobalKey();
  final _keyConfirmar = GlobalKey();
  final _keyTermos = GlobalKey();
  final _focoNome = FocusNode();
  final _focoCelular = FocusNode();
  final _focoEmail = FocusNode();
  final _focoSenha = FocusNode();
  final _focoConfirmar = FocusNode();
  var _mostrarSenha = false;
  var _mostrarConfirmarSenha = false;
  late final _toqueTermos = TapGestureRecognizer()..onTap = () => _abrirTexto(TextoLegal.termos);
  late final _toquePolitica = TapGestureRecognizer()
    ..onTap = () => _abrirTexto(TextoLegal.privacidade);
  var _aceitouTermos = false;
  var _tentou = false;
  var _carregando = false;
  String? _erroServico;

  ServicoAuth get _servico => widget.servico ?? ServicoAuthPadrao.atual;

  @override
  void dispose() {
    for (final c in [_nome, _celular, _email, _senha, _confirmarSenha]) {
      c.dispose();
    }
    for (final f in [
      _focoNome,
      _focoCelular,
      _focoEmail,
      _focoSenha,
      _focoConfirmar,
    ]) {
      f.dispose();
    }
    _scrollController.dispose();
    _toqueTermos.dispose();
    _toquePolitica.dispose();
    super.dispose();
  }

  void _abrirTexto(TextoLegal texto) => Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => TextoLegalTela.de(texto)),
      );

  String? _erro(String? Function() validar) => _tentou ? validar() : null;

  String? _validarConfirmacaoSenha() {
    if (_confirmarSenha.text.isEmpty) {
      return _tentou ? 'Repita a senha para confirmar.' : null;
    }
    return _confirmarSenha.text == _senha.text
        ? null
        : 'As senhas não conferem. Digite a mesma senha.';
  }

  bool get _valido =>
      ValidacaoAuth.nome(_nome.text) == null &&
      ValidacaoAuth.celular(_celular.text) == null &&
      ValidacaoAuth.email(_email.text) == null &&
      ValidacaoAuth.senhaNova(_senha.text) == null &&
      _confirmarSenha.text == _senha.text &&
      _aceitouTermos;

  Future<void> _criar() async {
    if (_carregando) return;
    setState(() => _tentou = true);
    if (!_valido) {
      focarPrimeiroErro([
        EntradaCampoErro(
          key: _keyNome,
          focusNode: _focoNome,
          temErro: () => ValidacaoAuth.nome(_nome.text) != null,
        ),
        EntradaCampoErro(
          key: _keyCelular,
          focusNode: _focoCelular,
          temErro: () => ValidacaoAuth.celular(_celular.text) != null,
        ),
        EntradaCampoErro(
          key: _keyEmail,
          focusNode: _focoEmail,
          temErro: () => ValidacaoAuth.email(_email.text) != null,
        ),
        EntradaCampoErro(
          key: _keySenha,
          focusNode: _focoSenha,
          temErro: () => ValidacaoAuth.senhaNova(_senha.text) != null,
        ),
        EntradaCampoErro(
          key: _keyConfirmar,
          focusNode: _focoConfirmar,
          temErro: () => _confirmarSenha.text != _senha.text,
        ),
        EntradaCampoErro(
          key: _keyTermos,
          temErro: () => !_aceitouTermos,
        ),
      ]);
      return;
    }
    setState(() {
      _carregando = true;
      _erroServico = null;
    });
    String? erro;
    ResultadoCadastro? resultado;
    try {
      resultado = await _servico.criarConta(DadosCadastro(
        nome: _nome.text.trim(),
        email: _email.text.trim(),
        senha: _senha.text,
        celular: _celular.text,
        perfil: widget.perfil.name,
        termosAceitos: _aceitouTermos,
      ));
    } on ErroAuth catch (e) {
      erro = e.mensagem;
    }
    if (!mounted) return;
    setState(() {
      _carregando = false;
      _erroServico = erro;
    });
    if (erro != null) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          0,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
      return;
    }
    switch (resultado!) {
      case CadastroAguardandoEmail(:final email):
        Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => ConfirmarEmailTela(
              email: email,
              senha: _senha.text,
              cpf: '',
              perfil: widget.perfil,
              servico: widget.servico,
            ),
          ),
        );
      case CadastroComSessao():
        // SMS desligado no piloto (D16): sem confirmação de e-mail, entra direto.
        if (kConfirmarCelularPorSms) {
          Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => ConfirmarCelularTela(
                celular: _celular.text,
                perfil: widget.perfil,
                servico: widget.servico,
              ),
            ),
          );
        } else {
          RotasTrato.irParaDepoisDoCadastro(context, widget.perfil);
        }
    }
  }

  @override
  Widget build(BuildContext context) {
    void atualizar(String _) => setState(() {});
    final estiloTexto = TipografiaTrato.corpo;
    final estiloLink = estiloTexto.copyWith(
      color: CoresTrato.azulTexto,
      decoration: TextDecoration.underline,
    );
    return EstruturaAuth(
      tituloBarra: 'Passo 1 de 2',
      scrollController: _scrollController,
      rodape: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          MensagemErroAuth(_erroServico),
          BotaoPrimario(texto: 'Criar conta', aoTocar: _criar, carregando: _carregando),
        ],
      ),
      children: [
        const SizedBox(height: EspacosTrato.x2),
        Text('Criar conta', style: TipografiaTrato.tituloGrande),
        const SizedBox(height: EspacosTrato.x2),
        Text(
          fraseSemTaxa,
          key: const Key('frase-sem-taxa'),
          style: TipografiaTrato.corpoPequeno.copyWith(color: CoresTrato.textoSecundario),
        ),
        const SizedBox(height: EspacosTrato.x4),
        KeyedSubtree(
          key: _keyNome,
          child: CampoTrato(
            rotulo: 'Nome completo',
            controlador: _nome,
            foco: _focoNome,
            erro: _erro(() => ValidacaoAuth.nome(_nome.text)),
            aoMudar: atualizar,
          ),
        ),
        const SizedBox(height: EspacosTrato.x4),
        KeyedSubtree(
          key: _keyCelular,
          child: CampoTrato(
            rotulo: 'Celular',
            controlador: _celular,
            foco: _focoCelular,
            dica: '(31) 90000-0000',
            teclado: TextInputType.phone,
            formatadores: const [MascaraNumerica.celular],
            erro: _erro(() => ValidacaoAuth.celular(_celular.text)),
            aoMudar: atualizar,
          ),
        ),
        const SizedBox(height: EspacosTrato.x4),
        KeyedSubtree(
          key: _keyEmail,
          child: CampoTrato(
            rotulo: 'E-mail',
            controlador: _email,
            foco: _focoEmail,
            dica: 'voce@email.com',
            teclado: TextInputType.emailAddress,
            erro: _erro(() => ValidacaoAuth.email(_email.text)),
            aoMudar: atualizar,
          ),
        ),
        const SizedBox(height: EspacosTrato.x4),
        KeyedSubtree(
          key: _keySenha,
          child: CampoTrato(
            rotulo: 'Senha',
            controlador: _senha,
            foco: _focoSenha,
            senha: !_mostrarSenha,
            textoAcao: _mostrarSenha ? 'Ocultar' : 'Mostrar',
            aoTocarAcao: () => setState(() => _mostrarSenha = !_mostrarSenha),
            ajuda: 'Pelo menos 8 caracteres, com letra e número.',
            erro: _erro(() => ValidacaoAuth.senhaNova(_senha.text)),
            aoMudar: atualizar,
          ),
        ),
        const SizedBox(height: EspacosTrato.x4),
        KeyedSubtree(
          key: _keyConfirmar,
          child: CampoTrato(
            rotulo: 'Confirmar senha',
            controlador: _confirmarSenha,
            foco: _focoConfirmar,
            senha: !_mostrarConfirmarSenha,
            textoAcao: _mostrarConfirmarSenha ? 'Ocultar' : 'Mostrar',
            aoTocarAcao: () => setState(() => _mostrarConfirmarSenha = !_mostrarConfirmarSenha),
            erro: _validarConfirmacaoSenha(),
            aoMudar: atualizar,
          ),
        ),
        const SizedBox(height: EspacosTrato.x4),
        KeyedSubtree(
          key: _keyTermos,
          child: _LinhaMarcar(
            marcado: _aceitouTermos,
            aoMudar: (v) => setState(() => _aceitouTermos = v),
            erro: _tentou && !_aceitouTermos
                ? 'Marque para concordar com os Termos de uso e continuar.'
                : null,
            texto: Text.rich(
              TextSpan(
                style: estiloTexto,
                children: [
                  const TextSpan(text: 'Li e aceito os '),
                  TextSpan(text: 'Termos de uso', style: estiloLink, recognizer: _toqueTermos),
                  const TextSpan(text: ' e a '),
                  TextSpan(
                    text: 'Política de privacidade',
                    style: estiloLink,
                    recognizer: _toquePolitica,
                  ),
                  const TextSpan(text: '.'),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _LinhaMarcar extends StatelessWidget {
  const _LinhaMarcar({
    required this.marcado,
    required this.aoMudar,
    required this.texto,
    this.erro,
  });

  final bool marcado;
  final ValueChanged<bool> aoMudar;
  final Widget texto;
  final String? erro;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        MergeSemantics(
            child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Checkbox(value: marcado, onChanged: (v) => aoMudar(v ?? false)),
            const SizedBox(width: EspacosTrato.x2),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(top: EspacosTrato.x3),
                child: texto,
              ),
            ),
          ],
        )),
        if (erro != null)
          Text(erro!, style: TipografiaTrato.legenda.copyWith(color: CoresTrato.vermelhoTexto)),
      ],
    );
  }
}
