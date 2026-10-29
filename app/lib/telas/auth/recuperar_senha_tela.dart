import 'package:flutter/material.dart';

import '../../componentes/componentes.dart';
import '../../tema/tema.dart';
import '../em_breve_tela.dart';
import 'estrutura_auth.dart';
import 'validacao.dart';

/// Tela 7 do protótipo: "Recuperar senha". Enviar código ainda não tem backend.
class RecuperarSenhaTela extends StatefulWidget {
  const RecuperarSenhaTela({super.key});

  @override
  State<RecuperarSenhaTela> createState() => _RecuperarSenhaTelaState();
}

class _RecuperarSenhaTelaState extends State<RecuperarSenhaTela> {
  final _email = TextEditingController();
  var _tentou = false;

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  void _abrirEmBreve(String titulo) => Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => EmBreveTela(titulo: titulo)),
      );

  void _enviar() {
    setState(() => _tentou = true);
    if (ValidacaoAuth.email(_email.text) == null) _abrirEmBreve('Enviar código');
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
          style: TipografiaTrato.corpoGrande,
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
        BotaoPrimario(texto: 'Enviar código', aoTocar: _enviar),
      ],
    );
  }
}
