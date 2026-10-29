import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../../componentes/componentes.dart';
import '../../tema/tema.dart';
import '../em_breve_tela.dart';
import '../onboarding/escolha_perfil_tela.dart';
import 'confirmar_celular_tela.dart';
import 'estrutura_auth.dart';
import 'validacao.dart';

/// Tela 5 do protótipo: "Criar conta", passo 1 de 2.
/// Termos e política abrem [EmBreveTela] até os textos legais existirem.
class CriarContaTela extends StatefulWidget {
  const CriarContaTela({super.key, this.perfil = PerfilUso.cliente});

  final PerfilUso perfil;

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
  late final _toqueTermos = TapGestureRecognizer()..onTap = () => _emBreve('Termos de uso');
  late final _toquePolitica = TapGestureRecognizer()
    ..onTap = () => _emBreve('Política de privacidade');
  var _aceitouTermos = false;
  var _avisosWhatsapp = false;
  var _tentou = false;

  @override
  void dispose() {
    for (final c in [_nome, _cpf, _nascimento, _celular, _email, _senha]) {
      c.dispose();
    }
    _toqueTermos.dispose();
    _toquePolitica.dispose();
    super.dispose();
  }

  void _emBreve(String titulo) => Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => EmBreveTela(titulo: titulo)),
      );

  String? _erro(String? Function() validar) => _tentou ? validar() : null;

  bool get _valido =>
      ValidacaoAuth.nome(_nome.text) == null &&
      ValidacaoAuth.cpf(_cpf.text) == null &&
      ValidacaoAuth.nascimento(_nascimento.text) == null &&
      ValidacaoAuth.celular(_celular.text) == null &&
      ValidacaoAuth.email(_email.text) == null &&
      ValidacaoAuth.senhaNova(_senha.text) == null &&
      _aceitouTermos;

  void _criar() {
    setState(() => _tentou = true);
    if (!_valido) return;
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => ConfirmarCelularTela(celular: _celular.text)),
    );
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
      rodape: BotaoPrimario(texto: 'Criar conta', aoTocar: _criar),
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
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: CampoTrato(
                rotulo: 'CPF',
                controlador: _cpf,
                dica: '000.000.000-00',
                teclado: TextInputType.number,
                formatadores: const [MascaraNumerica.cpf],
                erro: _erro(() => ValidacaoAuth.cpf(_cpf.text)),
                aoMudar: atualizar,
              ),
            ),
            const SizedBox(width: EspacosTrato.x3),
            Expanded(
              child: CampoTrato(
                rotulo: 'Nascimento',
                controlador: _nascimento,
                dica: 'dd/mm/aaaa',
                teclado: TextInputType.number,
                formatadores: const [MascaraNumerica.data],
                erro: _erro(() => ValidacaoAuth.nascimento(_nascimento.text)),
                aoMudar: atualizar,
              ),
            ),
          ],
        ),
        const SizedBox(height: EspacosTrato.x2),
        Text('O Trato é para maiores de 18 anos.', style: TipografiaTrato.legenda),
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
          senha: true,
          ajuda: 'Pelo menos 8 caracteres, com letra e número.',
          erro: _erro(() => ValidacaoAuth.senhaNova(_senha.text)),
          aoMudar: atualizar,
        ),
        const SizedBox(height: EspacosTrato.x4),
        _LinhaMarcar(
          marcado: _aceitouTermos,
          aoMudar: (v) => setState(() => _aceitouTermos = v),
          erro: _tentou && !_aceitouTermos ? 'Aceite os termos para continuar.' : null,
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
        Row(
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
        ),
        if (erro != null)
          Text(erro!, style: TipografiaTrato.legenda.copyWith(color: CoresTrato.vermelhoTexto)),
      ],
    );
  }
}
