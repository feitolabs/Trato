import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../auth/sessao_auth.dart';
import '../../tema/tema.dart';

/// Login real (Supabase Auth, mesma conta usada no app Trato).
/// Em telas largas: painel de marca à esquerda, formulário à direita (estilo SaaS).
/// Em telas estreitas: tudo empilhado, como no app.
class TelaLogin extends StatefulWidget {
  const TelaLogin({super.key, required this.servico});

  final ServicoAuthWeb servico;

  @override
  State<TelaLogin> createState() => _TelaLoginState();
}

class _TelaLoginState extends State<TelaLogin> {
  final _email = TextEditingController();
  final _senha = TextEditingController();
  bool _mostrarSenha = false;
  bool _carregando = false;
  String? _erro;

  Future<void> _entrar() async {
    if (_carregando) return;
    setState(() {
      _carregando = true;
      _erro = null;
    });
    try {
      await widget.servico.entrarComEmail(email: _email.text.trim(), senha: _senha.text);
    } catch (erro) {
      if (!mounted) return;
      setState(() => _erro = mensagemErroLogin(erro));
    } finally {
      if (mounted) setState(() => _carregando = false);
    }
  }

  @override
  void dispose() {
    _email.dispose();
    _senha.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: CoresTrato.superficie,
      body: LayoutBuilder(
        builder: (context, restricoes) {
          final larga = restricoes.maxWidth >= 900;
          if (larga) {
            return Row(
              children: [
                const Expanded(flex: 5, child: _PainelMarca()),
                Expanded(
                  flex: 4,
                  child: Center(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.symmetric(horizontal: EspacosTrato.x8, vertical: EspacosTrato.x8),
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 400),
                        child: _FormularioLogin(
                          emailControlador: _email,
                          senhaControlador: _senha,
                          mostrarSenha: _mostrarSenha,
                          aoAlternarSenha: () => setState(() => _mostrarSenha = !_mostrarSenha),
                          carregando: _carregando,
                          erro: _erro,
                          aoEntrar: _entrar,
                          comCartao: false,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            );
          }
          return SafeArea(
            child: Container(
              color: CoresTrato.petroleo,
              child: Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: EspacosTrato.margemOnboarding),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const _CabecalhoMarca(clara: true),
                      const SizedBox(height: EspacosTrato.x8),
                      _FormularioLogin(
                        emailControlador: _email,
                        senhaControlador: _senha,
                        mostrarSenha: _mostrarSenha,
                        aoAlternarSenha: () => setState(() => _mostrarSenha = !_mostrarSenha),
                        carregando: _carregando,
                        erro: _erro,
                        aoEntrar: _entrar,
                        comCartao: true,
                      ),
                      const SizedBox(height: EspacosTrato.x4),
                      Text(
                        'Use a mesma conta do app Trato (cliente ou profissional).',
                        textAlign: TextAlign.center,
                        style: TipografiaTrato.corpoPequeno.copyWith(color: CoresTrato.azulClaro),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Logo + nome + lema, usado no cabeçalho do painel de marca e na versão empilhada.
class _CabecalhoMarca extends StatelessWidget {
  const _CabecalhoMarca({required this.clara});

  /// Texto claro sobre fundo escuro (petróleo) ou escuro sobre fundo claro.
  final bool clara;

  @override
  Widget build(BuildContext context) {
    final corTitulo = clara ? CoresTrato.creme : CoresTrato.petroleo;
    final corLema = clara ? CoresTrato.azulClaro : CoresTrato.textoSecundario;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Image.asset('assets/logo/trato_logo.png', height: 64),
        const SizedBox(height: EspacosTrato.x4),
        Text('Trato', style: TipografiaTrato.marcaPequena.copyWith(color: corTitulo, fontSize: 32)),
        const SizedBox(height: EspacosTrato.x1),
        Text(
          'Conectando clientes a profissionais de qualidade.',
          textAlign: TextAlign.center,
          style: TipografiaTrato.lema.copyWith(color: corLema),
        ),
      ],
    );
  }
}

/// Painel de marca da tela larga: gradiente petróleo com formas decorativas e destaques,
/// estilo SaaS (lado esquerdo "mostra", lado direito "pede login").
class _PainelMarca extends StatelessWidget {
  const _PainelMarca();

  static const _destaques = [
    (Icons.search_rounded, 'Encontre profissionais de confiança perto de você'),
    (Icons.request_quote_outlined, 'Peça orçamentos e compare antes de contratar'),
    (Icons.task_alt_rounded, 'Acompanhe cada pedido do início ao fim'),
  ];

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      child: Stack(
        fit: StackFit.expand,
        children: [
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [CoresTrato.petroleo, CoresTrato.petroleoProfundo],
              ),
            ),
          ),
          Positioned.fill(child: CustomPaint(painter: _PadraoHeroPainter())),
          Center(
            child: Padding(
              padding: const EdgeInsets.all(EspacosTrato.x8),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 440),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const _CabecalhoMarca(clara: true),
                    const SizedBox(height: EspacosTrato.x8),
                    for (final (icone, texto) in _destaques) ...[
                      _ItemDestaque(icone: icone, texto: texto),
                      const SizedBox(height: EspacosTrato.x4),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Grade fina + círculos tracejados sobre o petróleo, igual ao fundo do hero do site
/// (`Trato Feito — versão web.pdf`, pág. 1): textura discreta, não um gradiente decorativo solto.
class _PadraoHeroPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final linha = Paint()
      ..color = CoresTrato.veuGrade
      ..strokeWidth = 1;
    const passo = 56.0;
    for (var x = 0.0; x < size.width; x += passo) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), linha);
    }
    for (var y = 0.0; y < size.height; y += passo) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), linha);
    }

    final tracejado = Paint()
      ..color = CoresTrato.veuTracejado
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;
    void circuloTracejado(Offset centro, double raio) {
      const passoAngulo = 0.12;
      var angulo = 0.0;
      while (angulo < 6.2832) {
        final a1 = Offset(
          centro.dx + raio * math.cos(angulo),
          centro.dy + raio * math.sin(angulo),
        );
        final a2 = Offset(
          centro.dx + raio * math.cos(angulo + passoAngulo * 0.6),
          centro.dy + raio * math.sin(angulo + passoAngulo * 0.6),
        );
        canvas.drawLine(a1, a2, tracejado);
        angulo += passoAngulo;
      }
    }

    circuloTracejado(Offset(size.width * 0.18, size.height * 0.28), 150);
    circuloTracejado(Offset(size.width * 0.18, size.height * 0.28), 230);
    circuloTracejado(Offset(size.width * 0.85, size.height * 0.82), 110);
  }

  @override
  bool shouldRepaint(covariant _PadraoHeroPainter oldDelegate) => false;
}

class _ItemDestaque extends StatelessWidget {
  const _ItemDestaque({required this.icone, required this.texto});

  final IconData icone;
  final String texto;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(EspacosTrato.x2),
          decoration: BoxDecoration(
            color: CoresTrato.veuIcone,
            borderRadius: BorderRadius.circular(EspacosTrato.raio),
          ),
          child: Icon(icone, color: CoresTrato.creme, size: 20),
        ),
        const SizedBox(width: EspacosTrato.x3),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(top: EspacosTrato.x1),
            child: Text(
              texto,
              style: TipografiaTrato.corpo.copyWith(color: CoresTrato.creme),
            ),
          ),
        ),
      ],
    );
  }
}

/// Campos de e-mail/senha e o botão de entrar. [comCartao] embrulha num cartão claro
/// (usado na versão estreita, sobre o fundo petróleo); na versão larga o fundo já é claro.
class _FormularioLogin extends StatelessWidget {
  const _FormularioLogin({
    required this.emailControlador,
    required this.senhaControlador,
    required this.mostrarSenha,
    required this.aoAlternarSenha,
    required this.carregando,
    required this.erro,
    required this.aoEntrar,
    required this.comCartao,
  });

  final TextEditingController emailControlador;
  final TextEditingController senhaControlador;
  final bool mostrarSenha;
  final VoidCallback aoAlternarSenha;
  final bool carregando;
  final String? erro;
  final VoidCallback aoEntrar;
  final bool comCartao;

  @override
  Widget build(BuildContext context) {
    final campos = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Entrar na sua conta',
          style: TipografiaTrato.tituloGrande.copyWith(color: CoresTrato.petroleo),
        ),
        const SizedBox(height: EspacosTrato.x1),
        if (!comCartao)
          Text(
            'Use a mesma conta do app Trato (cliente ou profissional).',
            style: TipografiaTrato.corpoPequeno.copyWith(color: CoresTrato.textoSecundario),
          ),
        const SizedBox(height: EspacosTrato.x5),
        TextField(
          controller: emailControlador,
          keyboardType: TextInputType.emailAddress,
          decoration: const InputDecoration(labelText: 'E-mail'),
        ),
        const SizedBox(height: EspacosTrato.x3),
        TextField(
          controller: senhaControlador,
          obscureText: !mostrarSenha,
          onSubmitted: (_) => aoEntrar(),
          decoration: InputDecoration(
            labelText: 'Senha',
            suffixIcon: IconButton(
              icon: Icon(mostrarSenha ? Icons.visibility_off : Icons.visibility),
              onPressed: aoAlternarSenha,
            ),
          ),
        ),
        if (erro != null) ...[
          const SizedBox(height: EspacosTrato.x3),
          Text(erro!, style: TipografiaTrato.corpoPequeno.copyWith(color: CoresTrato.vermelhoTexto)),
        ],
        const SizedBox(height: EspacosTrato.x5),
        FilledButton(
          onPressed: carregando ? null : aoEntrar,
          child: carregando
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Entrar'),
        ),
      ],
    );
    if (!comCartao) return campos;
    return Container(
      padding: const EdgeInsets.all(EspacosTrato.x5),
      decoration: BoxDecoration(
        color: CoresTrato.superficie,
        borderRadius: BorderRadius.circular(EspacosTrato.raioGrande),
      ),
      child: campos,
    );
  }
}
