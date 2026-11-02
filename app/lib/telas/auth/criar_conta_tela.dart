import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../../auth/servico_auth.dart';
import '../../componentes/componentes.dart';
import '../../tema/tema.dart';
import '../legal/texto_legal_tela.dart';
import '../onboarding/escolha_perfil_tela.dart';
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
  final _cpf = TextEditingController();
  final _nascimento = TextEditingController();
  final _celular = TextEditingController();
  final _email = TextEditingController();
  final _senha = TextEditingController();
  final _confirmarSenha = TextEditingController();
  final _scrollController = ScrollController();
  var _mostrarSenha = false;
  var _mostrarConfirmarSenha = false;
  late final _toqueTermos = TapGestureRecognizer()..onTap = () => _abrirTexto(TextoLegal.termos);
  late final _toquePolitica = TapGestureRecognizer()
    ..onTap = () => _abrirTexto(TextoLegal.privacidade);
  var _aceitouTermos = false;
  var _avisosWhatsapp = false;
  var _tentou = false;
  var _carregando = false;
  String? _erroServico;

  ServicoAuth get _servico => widget.servico ?? ServicoAuthPadrao.atual;

  @override
  void dispose() {
    for (final c in [_nome, _cpf, _nascimento, _celular, _email, _senha, _confirmarSenha]) {
      c.dispose();
    }
    _scrollController.dispose();
    _toqueTermos.dispose();
    _toquePolitica.dispose();
    super.dispose();
  }

  void _rolarParaInicio() {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        0,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  void _abrirTexto(TextoLegal texto) => Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => TextoLegalTela.de(texto)),
      );

  String? _erro(String? Function() validar) => _tentou ? validar() : null;

  String? _validarConfirmacaoSenha() {
    if (_confirmarSenha.text.isEmpty) return null;
    return _confirmarSenha.text == _senha.text
        ? null
        : 'As senhas não conferem. Digite exatamente a mesma senha nos dois campos.';
  }

  bool get _valido =>
      ValidacaoAuth.nome(_nome.text) == null &&
      ValidacaoAuth.cpf(_cpf.text) == null &&
      ValidacaoAuth.nascimento(_nascimento.text) == null &&
      ValidacaoAuth.celular(_celular.text) == null &&
      ValidacaoAuth.email(_email.text) == null &&
      ValidacaoAuth.senhaNova(_senha.text) == null &&
      _validarConfirmacaoSenha() == null &&
      _aceitouTermos;

  Future<void> _criar() async {
    if (_carregando) return;
    setState(() => _tentou = true);
    if (!_valido) {
      _rolarParaInicio();
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
        cpf: _cpf.text,
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
      _rolarParaInicio();
      return;
    }
    switch (resultado!) {
      case CadastroAguardandoEmail(:final email):
        Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => ConfirmarEmailTela(
              email: email,
              senha: _senha.text,
              cpf: _cpf.text,
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
        const SizedBox(height: EspacosTrato.x4),
        CampoTrato(
          rotulo: 'Nome completo',
          controlador: _nome,
          erro: _erro(() => ValidacaoAuth.nome(_nome.text)),
          aoMudar: atualizar,
        ),
        const SizedBox(height: EspacosTrato.x4),
        CampoTrato(
          rotulo: 'CPF',
          controlador: _cpf,
          dica: '000.000.000-00',
          teclado: TextInputType.number,
          formatadores: const [MascaraNumerica.cpf],
          erro: _erro(() => ValidacaoAuth.cpf(_cpf.text)),
          aoMudar: atualizar,
        ),
        const SizedBox(height: EspacosTrato.x4),
        CampoTrato(
          rotulo: 'Nascimento',
          controlador: _nascimento,
          dica: 'dd/mm/aaaa',
          ajuda: 'O Trato é para maiores de 18 anos.',
          teclado: TextInputType.number,
          formatadores: const [MascaraNumerica.data],
          erro: _erro(() => ValidacaoAuth.nascimento(_nascimento.text)),
          aoMudar: atualizar,
        ),
        const SizedBox(height: EspacosTrato.x4),
        CampoTrato(
          rotulo: 'Celular',
          controlador: _celular,
          dica: '(31) 90000-0000',
          teclado: TextInputType.phone,
          formatadores: const [MascaraNumerica.celular],
          erro: _erro(() => ValidacaoAuth.celular(_celular.text)),
          aoMudar: atualizar,
        ),
        const SizedBox(height: EspacosTrato.x4),
        CampoTrato(
          rotulo: 'E-mail',
          controlador: _email,
          dica: 'voce@email.com',
          teclado: TextInputType.emailAddress,
          erro: _erro(() => ValidacaoAuth.email(_email.text)),
          aoMudar: atualizar,
        ),
        const SizedBox(height: EspacosTrato.x4),
        CampoTrato(
          rotulo: 'Senha',
          controlador: _senha,
          senha: !_mostrarSenha,
          textoAcao: _mostrarSenha ? 'Ocultar' : 'Mostrar',
          aoTocarAcao: () => setState(() => _mostrarSenha = !_mostrarSenha),
          ajuda: 'Pelo menos 8 caracteres, com letra e número.',
          erro: _erro(() => ValidacaoAuth.senhaNova(_senha.text)),
          aoMudar: atualizar,
        ),
        const SizedBox(height: EspacosTrato.x4),
        CampoTrato(
          rotulo: 'Confirmar senha',
          controlador: _confirmarSenha,
          senha: !_mostrarConfirmarSenha,
          textoAcao: _mostrarConfirmarSenha ? 'Ocultar' : 'Mostrar',
          aoTocarAcao: () => setState(() => _mostrarConfirmarSenha = !_mostrarConfirmarSenha),
          erro: _validarConfirmacaoSenha(),
          aoMudar: atualizar,
        ),
        const SizedBox(height: EspacosTrato.x4),
        _LinhaMarcar(
          marcado: _aceitouTermos,
          aoMudar: (v) => setState(() => _aceitouTermos = v),
          erro: _tentou && !_aceitouTermos
              ? 'Termos não aceitos. Marque a caixa para concordar com os Termos de uso e continuar.'
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
        const SizedBox(height: EspacosTrato.x3),
        _LinhaMarcar(
          marcado: _avisosWhatsapp,
          aoMudar: (v) => setState(() => _avisosWhatsapp = v),
          texto: Text.rich(
            TextSpan(
              style: estiloTexto,
              children: [
                const TextSpan(text: 'Quero receber avisos dos meus pedidos pelo WhatsApp. '),
                TextSpan(
                  text: '(opcional)',
                  style: TipografiaTrato.corpoPequeno.copyWith(color: CoresTrato.textoSecundario),
                ),
              ],
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
        MergeSemantics(child: Row(
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
