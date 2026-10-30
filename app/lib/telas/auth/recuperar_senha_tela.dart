import 'package:flutter/material.dart';

import '../../auth/servico_auth.dart';
import '../../componentes/componentes.dart';
import '../../tema/tema.dart';
import '../em_breve_tela.dart';
import 'estrutura_auth.dart';
import 'validacao.dart';

/// Tela 7 do protótipo: "Recuperar senha". O [ServicoAuth] manda o e-mail de recuperação.
class RecuperarSenhaTela extends StatefulWidget {
  const RecuperarSenhaTela({super.key, this.servico});

  /// Se nulo, usa [ServicoAuthPadrao.atual].
  final ServicoAuth? servico;

  @override
  State<RecuperarSenhaTela> createState() => _RecuperarSenhaTelaState();
}

class _RecuperarSenhaTelaState extends State<RecuperarSenhaTela> {
  final _email = TextEditingController();
  var _tentou = false;
  var _carregando = false;
  var _enviado = false;
  String? _erroServico;

  ServicoAuth get _servico => widget.servico ?? ServicoAuthPadrao.atual;

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  void _abrirEmBreve(String titulo) => Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => EmBreveTela(titulo: titulo)),
      );

  Future<void> _enviar() async {
    if (_carregando) return;
    setState(() => _tentou = true);
    if (ValidacaoAuth.email(_email.text) != null) return;
    setState(() {
      _carregando = true;
      _erroServico = null;
      _enviado = false;
    });
    String? erro;
    try {
      await _servico.recuperarSenha(_email.text.trim());
    } on ErroAuth catch (e) {
      erro = e.mensagem;
    }
    if (!mounted) return;
    setState(() {
      _carregando = false;
      _erroServico = erro;
      _enviado = erro == null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return EstruturaAuth(
      rodape: Wrap(
        alignment: WrapAlignment.center,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text(
            'Sem acesso ao e-mail? ',
            style: TipografiaTrato.corpoPequeno.copyWith(color: CoresTrato.textoSecundario),
          ),
          BotaoLink(texto: 'Fale com o suporte', aoTocar: () => _abrirEmBreve('Suporte')),
        ],
      ),
      children: [
        const SizedBox(height: EspacosTrato.x4),
        Text('Recuperar senha', style: TipografiaTrato.tituloGrande),
        const SizedBox(height: EspacosTrato.x3),
        Text(
          'Informe o e-mail da sua conta. Enviamos um código para criar uma senha nova.',
          style: TipografiaTrato.corpo,
        ),
        const SizedBox(height: EspacosTrato.x6),
        CampoTrato(
          rotulo: 'E-mail',
          controlador: _email,
          teclado: TextInputType.emailAddress,
          erro: _tentou ? ValidacaoAuth.email(_email.text) : null,
          aoMudar: (_) => setState(() {}),
        ),
        const SizedBox(height: EspacosTrato.x5),
        MensagemErroAuth(_erroServico),
        if (_enviado)
          Padding(
            padding: const EdgeInsets.only(bottom: EspacosTrato.x3),
            child: Text(
              'Pronto! Se este e-mail tem conta, você vai receber as instruções em instantes.',
              style: TipografiaTrato.corpo.copyWith(color: CoresTrato.azulTexto),
            ),
          ),
        BotaoPrimario(texto: 'Enviar código', aoTocar: _enviar, carregando: _carregando),
      ],
    );
  }
}
