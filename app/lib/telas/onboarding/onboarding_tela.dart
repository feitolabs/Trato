import 'package:flutter/material.dart';

import '../../componentes/componentes.dart';
import '../../tema/tema.dart';
import '../em_breve_tela.dart';
import 'escolha_perfil_tela.dart';

class _PaginaOnboarding {
  const _PaginaOnboarding({required this.icone, required this.titulo, required this.texto});

  final IconData icone;
  final String titulo;
  final String texto;
}

/// Os textos da página 1 são do protótipo. As páginas 2 e 3 seguem o escopo (5.1: orçamento,
/// pagamento retido e garantia) e usam frases já presentes nas telas de pagamento e disputa.
/// Confirmar o texto com o João (P14).
const _paginas = [
  _PaginaOnboarding(
    icone: Icons.format_list_bulleted,
    titulo: 'Descreva o problema,\nreceba orçamentos',
    texto: 'Até 5 profissionais com identidade verificada respondem em até 48 horas.',
  ),
  _PaginaOnboarding(
    icone: Icons.lock_outline,
    titulo: 'Seu dinheiro fica\nprotegido',
    texto: 'O pagamento fica retido até a conclusão. Você confirma o serviço e o valor é liberado.',
  ),
  _PaginaOnboarding(
    icone: Icons.verified_user_outlined,
    titulo: 'Se algo der errado,\nvocê tem garantia',
    texto: 'Abra uma disputa e o valor fica congelado até a decisão. Serviços com garantia ativa.',
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
        MaterialPageRoute<void>(builder: (_) => const EmBreveTela(titulo: 'Entrar na sua conta')),
      );

  @override
  Widget build(BuildContext context) {
    final margem = Responsivo.margemLateral(TamanhoTela.de(context)) + EspacosTrato.x1;
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
                    BotaoLink(texto: 'Pular', aoTocar: _irParaEscolhaDePerfil),
                  ],
                ),
              ),
              Expanded(
                child: PageView.builder(
                  controller: _controlador,
                  itemCount: _paginas.length,
                  onPageChanged: (i) => setState(() => _pagina = i),
                  itemBuilder: (_, i) => _Pagina(pagina: _paginas[i], numero: i, margem: margem),
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

class _Pagina extends StatelessWidget {
  const _Pagina({required this.pagina, required this.numero, required this.margem});

  final _PaginaOnboarding pagina;
  final int numero;
  final double margem;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: EdgeInsets.symmetric(horizontal: margem, vertical: EspacosTrato.x6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            height: 260,
            width: double.infinity,
            decoration: BoxDecoration(
              color: CoresTrato.azulClaro,
              borderRadius: BorderRadius.circular(EspacosTrato.raioGrande),
            ),
            child: Icon(pagina.icone, size: 72, color: CoresTrato.petroleo),
          ),
          const SizedBox(height: EspacosTrato.x6),
          Text('${numero + 1} DE ${_paginas.length}', style: TipografiaTrato.sobretitulo),
          const SizedBox(height: EspacosTrato.x3),
          Text(pagina.titulo, style: TipografiaTrato.tituloGrande),
          const SizedBox(height: EspacosTrato.x3),
          Text(pagina.texto, style: TipografiaTrato.corpoGrande),
        ],
      ),
    );
  }
}
