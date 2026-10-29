import 'package:flutter/material.dart';

import '../../componentes/componentes.dart';
import '../../tema/tema.dart';
import '../em_breve_tela.dart';
import '../onboarding/escolha_perfil_tela.dart';
import '../fluxo/rotas.dart';
import 'estrutura_auth.dart';
import 'recuperar_senha_tela.dart';
import 'validacao.dart';

/// Tela 4 do protótipo: "Entrar na sua conta".
/// Entrar, Google, Apple e biometria ainda não têm backend: abrem [EmBreveTela].
class LoginTela extends StatefulWidget {
  const LoginTela({super.key});

  @override
  State<LoginTela> createState() => _LoginTelaState();
}

class _LoginTelaState extends State<LoginTela> {
  final _identificador = TextEditingController();
  final _senha = TextEditingController();
  var _mostrarSenha = false;
  var _tentou = false;

  @override
  void dispose() {
    _identificador.dispose();
    _senha.dispose();
    super.dispose();
  }

  void _abrir(Widget tela) =>
      Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => tela));

  void _emBreve(String titulo) => _abrir(EmBreveTela(titulo: titulo));

  String? get _erroIdentificador => _tentou
      ? ValidacaoAuth.obrigatorio(_identificador.text, 'Informe e-mail, CPF ou telefone.')
      : null;

  String? get _erroSenha =>
      _tentou ? ValidacaoAuth.obrigatorio(_senha.text, 'Informe sua senha.') : null;

  void _entrar() {
    setState(() => _tentou = true);
    if (_erroIdentificador == null && _erroSenha == null) RotasTrato.irParaCliente(context);
  }

  @override
  Widget build(BuildContext context) {
    return EstruturaAuth(
      comVoltar: false,
      rodape: Wrap(
        alignment: WrapAlignment.center,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text('Não tem conta? ', style: TipografiaTrato.corpo),
          BotaoLink(texto: 'Criar conta', aoTocar: () => _abrir(const EscolhaPerfilTela())),
        ],
      ),
      children: [
        const SizedBox(height: EspacosTrato.x6),
        Text('Trato', style: TipografiaTrato.marcaPequena.copyWith(fontSize: 40)),
        const SizedBox(height: EspacosTrato.x2),
        Text('Entrar na sua conta', style: TipografiaTrato.tituloGrande),
        const SizedBox(height: EspacosTrato.x6),
        CampoTrato(
          rotulo: 'E-mail, CPF ou telefone',
          controlador: _identificador,
          teclado: TextInputType.emailAddress,
          erro: _erroIdentificador,
          aoMudar: (_) => setState(() {}),
        ),
        const SizedBox(height: EspacosTrato.x5),
        CampoTrato(
          rotulo: 'Senha',
          controlador: _senha,
          senha: !_mostrarSenha,
          erro: _erroSenha,
          textoAcao: _mostrarSenha ? 'Ocultar' : 'Mostrar',
          aoTocarAcao: () => setState(() => _mostrarSenha = !_mostrarSenha),
          aoMudar: (_) => setState(() {}),
        ),
        Align(
          alignment: Alignment.centerRight,
          child: BotaoLink(
            texto: 'Esqueci minha senha',
            aoTocar: () => _abrir(const RecuperarSenhaTela()),
          ),
        ),
        const SizedBox(height: EspacosTrato.x3),
        BotaoPrimario(texto: 'Entrar', aoTocar: _entrar),
        const SizedBox(height: EspacosTrato.x4),
        const _DivisorOu(),
        const SizedBox(height: EspacosTrato.x4),
        BotaoSecundario(texto: 'Entrar com Google', aoTocar: () => _emBreve('Entrar com Google')),
        const SizedBox(height: EspacosTrato.x3),
        BotaoSecundario(texto: 'Entrar com Apple', aoTocar: () => _emBreve('Entrar com Apple')),
        const SizedBox(height: EspacosTrato.x3),
        BotaoSecundario(
          texto: 'Entrar com biometria',
          icone: Icons.fingerprint,
          aoTocar: () => _emBreve('Entrar com biometria'),
        ),
        const SizedBox(height: EspacosTrato.x4),
      ],
    );
  }
}

class _DivisorOu extends StatelessWidget {
  const _DivisorOu();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Expanded(child: Divider()),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: EspacosTrato.x3),
          child: Text('ou', style: TipografiaTrato.corpoPequeno),
        ),
        const Expanded(child: Divider()),
      ],
    );
  }
}
