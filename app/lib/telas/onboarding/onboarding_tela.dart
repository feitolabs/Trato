import 'package:flutter/material.dart';

import '../../dados/config_publica.dart';

import '../../componentes/componentes.dart';
import '../../tema/tema.dart';
import '../auth/login_tela.dart';
import '../fluxo/rotas.dart';
import 'escolha_perfil_tela.dart';
import 'tour_perfil_tela.dart';

class _PaginaOnboarding {
  const _PaginaOnboarding({
    this.icone,
    this.mascote,
    required this.titulo,
    required this.texto,
  });

  final IconData? icone;

  /// Imagem do Tratinho no lugar do ícone.
  final String? mascote;
  final String titulo;
  final String texto;
}

/// Os textos da página 1 são do protótipo. As páginas 2 e 3 seguem o escopo (5.1: orçamento,
/// pagamento retido e garantia) e usam frases já presentes nas telas de pagamento e disputa.
/// Confirmar o texto com o João (P14).
List<_PaginaOnboarding> get _paginas => [
      _PaginaOnboarding(
        icone: Icons.format_list_bulleted,
        titulo: 'Descreva o problema,\nreceba orçamentos',
        texto: 'Orçamento grátis · 0% de taxa. '
            'Até ${ConfigPublica.atual.limiteOrcamentos} profissionais com identidade verificada '
            'respondem em até ${ConfigPublica.horas(ConfigPublica.atual.validadePedidoHoras)}.',
      ),
      const _PaginaOnboarding(
        icone: Icons.lock_outline,
        titulo: 'Pagamento seguro\npelo app',
        texto:
            'O pagamento fica protegido pelo app e só é liberado depois que você confirma o serviço.',
      ),
      const _PaginaOnboarding(
        mascote: 'assets/mascote/tratinho-acenando.webp',
        titulo: 'Conte comigo.\nSe algo der errado, há suporte',
        texto:
            'Eu sou o Tratinho. Abra uma disputa e o caso passa por suporte e análise de problemas. O prazo de garantia do serviço vem no orçamento.',
      ),
    ];

/// Telas 2 do protótipo ("1 DE 3"): três páginas explicando orçamento, pagamento e garantia.
class OnboardingTela extends StatefulWidget {
  const OnboardingTela({super.key});

  @override
  State<OnboardingTela> createState() => _OnboardingTelaState();
}

class _OnboardingTelaState extends State<OnboardingTela> {
  final _controlador = PageController();
  var _pagina = 0;

  bool get _ultima => _pagina == _paginas.length - 1;

  @override
  void dispose() {
    _controlador.dispose();
    super.dispose();
  }

  void _avancar() {
    if (_ultima) {
      _irParaEscolhaDePerfil();
    } else {
      _controlador.nextPage(
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    }
  }

  void _irParaEscolhaDePerfil() => Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => const EscolhaPerfilTela()),
      );

  void _irParaLogin() => Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => const LoginTela()),
      );

  void _pularParaInicioCliente() {
    RotasTrato.modoVisitante = true;
    RotasTrato.irParaCliente(context);
  }

  @override
  Widget build(BuildContext context) {
    final margem = TamanhoTela.de(context) == TamanhoTela.celular
        ? EspacosTrato.margemOnboarding
        : Responsivo.margemLateral(TamanhoTela.de(context)) + EspacosTrato.x1;
    return Scaffold(
      body: SafeArea(
        child: ConteudoResponsivo(
          comMargem: false,
          child: Column(
            children: [
              Padding(
                padding: EdgeInsets.fromLTRB(margem, EspacosTrato.x4, margem, 0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Trato', style: TipografiaTrato.marcaPequena),
                    BotaoLink(texto: 'Pular', aoTocar: _pularParaInicioCliente),
                  ],
                ),
              ),
              Expanded(
                child: PageView.builder(
                  controller: _controlador,
                  itemCount: _paginas.length,
                  onPageChanged: (i) => setState(() => _pagina = i),
                  itemBuilder: (_, i) => PaginaTourVisual(
                    icone: _paginas[i].mascote == null ? _paginas[i].icone : null,
                    construirIlustracao: _paginas[i].mascote == null
                        ? null
                        : (tamanho) => Semantics(
                              label: 'Tratinho, o mascote do Trato, acenando',
                              image: true,
                              child: Image.asset(
                                _paginas[i].mascote!,
                                width: tamanho,
                                height: tamanho,
                                fit: BoxFit.contain,
                                excludeFromSemantics: true,
                              ),
                            ),
                    titulo: _paginas[i].titulo,
                    texto: _paginas[i].texto,
                    numero: i,
                    total: _paginas.length,
                    margem: margem,
                  ),
                ),
              ),
              Padding(
                padding: EdgeInsets.symmetric(horizontal: margem),
                child: IndicadorPaginas(total: _paginas.length, atual: _pagina),
              ),
              const SizedBox(height: EspacosTrato.x6),
              Padding(
                padding: EdgeInsets.symmetric(horizontal: margem),
                child: BotaoPrimario(texto: 'Próximo', aoTocar: _avancar),
              ),
              BotaoLink(texto: 'Já tenho conta', aoTocar: _irParaLogin),
              const SizedBox(height: EspacosTrato.x2),
            ],
          ),
        ),
      ),
    );
  }
}
