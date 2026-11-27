import 'package:flutter/material.dart';

import '../auth/sessao_auth.dart';
import '../componentes/barra_abas.dart';
import '../componentes/barra_lateral.dart';
import '../dados/orcamentos.dart';
import '../dados/pedidos.dart';
import '../dados/perfil.dart';
import '../tema/tema.dart';
import 'abas/aba_em_breve.dart';
import 'abas/aba_orcamentos.dart';
import 'abas/aba_pedidos.dart';
import 'abas/aba_perfil.dart';

/// Casca do profissional: barra lateral fixa (Pedidos · Orçamentos · Agenda · Carteira ·
/// Perfil público), no estilo do painel do PDF de referência (págs. 9–12).
class CascaProfissional extends StatefulWidget {
  const CascaProfissional({
    super.key,
    required this.perfil,
    required this.repositorioPedidos,
    required this.repositorioOrcamentos,
    required this.servicoAuth,
  });

  final PerfilTrato perfil;
  final RepositorioPedidos repositorioPedidos;
  final RepositorioOrcamentos repositorioOrcamentos;
  final ServicoAuthWeb servicoAuth;

  @override
  State<CascaProfissional> createState() => _CascaProfissionalState();
}

class _CascaProfissionalState extends State<CascaProfissional> {
  var _aba = 0;

  @override
  Widget build(BuildContext context) {
    final paginas = <Widget>[
      AbaPedidos(
        repositorio: widget.repositorioPedidos,
        cabecalho: _CabecalhoBoasVindas(perfil: widget.perfil),
      ),
      AbaOrcamentos(repositorio: widget.repositorioOrcamentos),
      const AbaEmBreve(
        titulo: 'Agenda',
        explicacao: 'A agenda por dia com check-in ainda não tem rota própria no backend.',
      ),
      const AbaEmBreve(
        titulo: 'Carteira',
        explicacao: 'O extrato da carteira ainda não tem rota própria no backend.',
      ),
      AbaPerfil(perfil: widget.perfil, servicoAuth: widget.servicoAuth),
    ];
    return Scaffold(
      backgroundColor: CoresTrato.creme,
      body: Row(
        children: [
          BarraLateralTrato(
            abas: abasProfissional,
            indiceAtual: _aba,
            aoSelecionar: (i) => setState(() => _aba = i),
            perfil: widget.perfil,
          ),
          Expanded(child: IndexedStack(index: _aba, children: paginas)),
        ],
      ),
    );
  }
}

class _CabecalhoBoasVindas extends StatelessWidget {
  const _CabecalhoBoasVindas({required this.perfil});

  final PerfilTrato perfil;

  @override
  Widget build(BuildContext context) {
    final partes = (perfil.nome ?? '').trim().split(' ');
    final primeiroNome = partes.isEmpty || partes.first.isEmpty ? null : partes.first;
    return Padding(
      padding: const EdgeInsets.only(bottom: EspacosTrato.x5),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: EspacosTrato.x4),
          Text(
            primeiroNome == null ? 'Bom dia!' : 'Bom dia, $primeiroNome',
            style: TipografiaTrato.tituloGrande.copyWith(color: CoresTrato.petroleo),
          ),
          const SizedBox(height: EspacosTrato.x4),
          Row(
            children: [
              Expanded(
                child: _CartaoEstatistica(
                  rotulo: 'Status da conta',
                  valor: perfil.status,
                ),
              ),
              const SizedBox(width: EspacosTrato.x3),
              Expanded(
                child: _CartaoEstatistica(
                  rotulo: 'Nota pública',
                  valor: perfil.notaPublica?.toStringAsFixed(1) ?? '—',
                ),
              ),
              const SizedBox(width: EspacosTrato.x3),
              Expanded(
                child: _CartaoEstatistica(
                  rotulo: 'Serviços concluídos',
                  valor: '${perfil.servicosConcluidos ?? 0}',
                ),
              ),
            ],
          ),
          const SizedBox(height: EspacosTrato.x5),
          Text(
            'Pedidos',
            style: TipografiaTrato.titulo.copyWith(color: CoresTrato.petroleo),
          ),
          const SizedBox(height: EspacosTrato.x3),
        ],
      ),
    );
  }
}

class _CartaoEstatistica extends StatelessWidget {
  const _CartaoEstatistica({required this.rotulo, required this.valor});

  final String rotulo;
  final String valor;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(EspacosTrato.paddingCartao),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(rotulo, style: TipografiaTrato.corpoPequeno.copyWith(color: CoresTrato.textoSecundario)),
            const SizedBox(height: EspacosTrato.x1),
            Text(valor, style: TipografiaTrato.tituloGrande.copyWith(color: CoresTrato.petroleo)),
          ],
        ),
      ),
    );
  }
}
