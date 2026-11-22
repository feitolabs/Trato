import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../componentes/componentes.dart';
import '../../tema/tema.dart';
import 'escolha_perfil_tela.dart';

/// Uma página do tour rápido de onboarding por perfil.
class PaginaTour {
  const PaginaTour({required this.icone, required this.titulo, required this.texto});

  final IconData icone;
  final String titulo;
  final String texto;
}

/// Páginas fixas do tour de cada perfil (F49).
List<PaginaTour> paginasTourDoPerfil(PerfilUso perfil) => switch (perfil) {
      PerfilUso.cliente => const [
          PaginaTour(
            icone: Icons.format_list_bulleted,
            titulo: 'Conte o que você precisa',
            texto: 'Descreva o serviço. É grátis e sem taxa.',
          ),
          PaginaTour(
            icone: Icons.fact_check_outlined,
            titulo: 'Compare e escolha',
            texto: 'Profissionais verificados mandam orçamentos. Veja o que inclui e escolha.',
          ),
          PaginaTour(
            icone: Icons.lock_outline,
            titulo: 'Pague com segurança',
            texto:
                'O dinheiro fica guardado no app. Só vai para o profissional quando você confirma o serviço.',
          ),
          PaginaTour(
            icone: Icons.star_outline,
            titulo: 'Avalie e ganhe Tratinhos',
            texto:
                'Avalie o serviço e ganhe Tratinhos de desconto. Deu problema? Abra uma disputa.',
          ),
        ],
      PerfilUso.profissional => const [
          PaginaTour(
            icone: Icons.person_outline,
            titulo: 'Complete seu perfil',
            texto:
                'Foto, categorias, regiões e conta para receber. Depois da verificação, os clientes veem você.',
          ),
          PaginaTour(
            icone: Icons.work_outline,
            titulo: 'Receba pedidos',
            texto: 'Veja os pedidos perto de você e mande o orçamento pela calculadora.',
          ),
          PaginaTour(
            icone: Icons.account_balance_wallet_outlined,
            titulo: 'Receba sem taxa',
            texto: 'O valor líquido cai na sua carteira depois que o cliente confirma. Sem taxa.',
          ),
          PaginaTour(
            icone: Icons.star_outline,
            titulo: 'Ganhe Tratinhos',
            texto:
                'Avalie seus clientes e ganhe Tratinhos. Use para ter 48 horas de exclusividade em um pedido.',
          ),
        ],
    };

/// Controle local no aparelho: cada perfil vê o tour uma vez (ao concluir ou pular).
abstract final class PreferenciaTourPerfil {
  static const chaveCliente = 'tour_visto_cliente';
  static const chaveProfissional = 'tour_visto_profissional';

  static String chave(PerfilUso perfil) =>
      perfil == PerfilUso.cliente ? chaveCliente : chaveProfissional;

  static Future<bool> visto(PerfilUso perfil) async {
    try {
      return (await SharedPreferences.getInstance()).getBool(chave(perfil)) ?? false;
    } on Object {
      return false;
    }
  }

  static Future<void> marcarVisto(PerfilUso perfil) async {
    try {
      await (await SharedPreferences.getInstance()).setBool(chave(perfil), true);
    } on Object {
      // Sem armazenamento: segue o fluxo normalmente.
    }
  }
}

/// Tour rápido de 4 páginas por perfil (Cliente ou Profissional), reaproveitando o visual do
/// onboarding original.
class TourPerfilTela extends StatefulWidget {
  const TourPerfilTela({
    super.key,
    required this.perfil,
    required this.aoConcluir,
    this.registrarVisto = true,
  });

  final PerfilUso perfil;
  final VoidCallback aoConcluir;

  /// Verdadeiro na 1ª abertura (grava em SharedPreferences); falso em "Ver tour de novo" (Ajuda).
  final bool registrarVisto;

  @override
  State<TourPerfilTela> createState() => _TourPerfilTelaState();
}

class _TourPerfilTelaState extends State<TourPerfilTela> {
  final _controlador = PageController();
  var _pagina = 0;

  List<PaginaTour> get _paginas => paginasTourDoPerfil(widget.perfil);
  bool get _ultima => _pagina == _paginas.length - 1;

  @override
  void dispose() {
    _controlador.dispose();
    super.dispose();
  }

  Future<void> _finalizar() async {
    if (widget.registrarVisto) {
      await PreferenciaTourPerfil.marcarVisto(widget.perfil);
    }
    if (mounted) widget.aoConcluir();
  }

  void _avancar() {
    if (_ultima) {
      _finalizar();
    } else {
      _controlador.nextPage(
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final margem = TamanhoTela.de(context) == TamanhoTela.celular
        ? EspacosTrato.margemOnboarding
        : Responsivo.margemLateral(TamanhoTela.de(context)) + EspacosTrato.x1;
    final paginas = _paginas;
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
                    BotaoLink(texto: 'Pular', aoTocar: _finalizar),
                  ],
                ),
              ),
              Expanded(
                child: PageView.builder(
                  controller: _controlador,
                  itemCount: paginas.length,
                  onPageChanged: (i) => setState(() => _pagina = i),
                  itemBuilder: (_, i) => PaginaTourVisual(
                    icone: paginas[i].icone,
                    titulo: paginas[i].titulo,
                    texto: paginas[i].texto,
                    numero: i,
                    total: paginas.length,
                    margem: margem,
                  ),
                ),
              ),
              Padding(
                padding: EdgeInsets.symmetric(horizontal: margem),
                child: IndicadorPaginas(total: paginas.length, atual: _pagina),
              ),
              const SizedBox(height: EspacosTrato.x6),
              Padding(
                padding: EdgeInsets.symmetric(horizontal: margem),
                child: BotaoPrimario(texto: 'Avançar', aoTocar: _avancar),
              ),
              const SizedBox(height: EspacosTrato.x4),
            ],
          ),
        ),
      ),
    );
  }
}

/// Página visual reutilizável (ícone, indicador "N DE M", título e texto) do onboarding/tour.
class PaginaTourVisual extends StatelessWidget {
  const PaginaTourVisual({
    super.key,
    required this.icone,
    required this.titulo,
    required this.texto,
    required this.numero,
    required this.total,
    required this.margem,
  });

  final IconData icone;
  final String titulo;
  final String texto;
  final int numero;
  final int total;
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
            child: Icon(icone, size: 72, color: CoresTrato.petroleo),
          ),
          const SizedBox(height: EspacosTrato.x6),
          Text('${numero + 1} DE $total', style: TipografiaTrato.sobretitulo),
          const SizedBox(height: EspacosTrato.x3),
          Text(titulo, style: TipografiaTrato.tituloGrande),
          const SizedBox(height: EspacosTrato.x3),
          Text(texto, style: TipografiaTrato.corpoGrande),
        ],
      ),
    );
  }
}
