import 'package:flutter/material.dart';

import '../../auth/servico_auth.dart';
import '../../componentes/componentes.dart';
import '../../tema/tema.dart';
import '../auth/criar_conta_tela.dart';

enum PerfilUso {
  cliente(
    icone: Icons.home_outlined,
    titulo: 'Quero contratar',
    descricao: 'Peça orçamentos e acompanhe o pagamento pelo app.',
    botao: 'Criar conta de cliente',
  ),
  profissional(
    icone: Icons.edit_outlined,
    titulo: 'Quero trabalhar',
    descricao:
        'Receba pedidos da sua região sem pagar por contato. Veja o valor líquido antes de orçar.',
    botao: 'Criar conta de profissional',
  );

  const PerfilUso({
    required this.icone,
    required this.titulo,
    required this.descricao,
    required this.botao,
  });

  final IconData icone;
  final String titulo;
  final String descricao;
  final String botao;
}

/// Tela 3 do protótipo: "Como você quer usar o Trato?".
class EscolhaPerfilTela extends StatefulWidget {
  const EscolhaPerfilTela({super.key, this.servico});

  /// Repassado ao cadastro. Se nulo, usa o serviço padrão.
  final ServicoAuth? servico;

  @override
  State<EscolhaPerfilTela> createState() => _EscolhaPerfilTelaState();
}

class _EscolhaPerfilTelaState extends State<EscolhaPerfilTela> {
  var _escolhido = PerfilUso.cliente;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(),
      body: SafeArea(
        child: ConteudoResponsivo(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Como você quer usar o Trato?', style: TipografiaTrato.tituloGrande),
                      const SizedBox(height: EspacosTrato.x2),
                      Text(
                        'Dá para mudar depois, no seu perfil.',
                        style: TipografiaTrato.corpo.copyWith(color: CoresTrato.textoSecundario),
                      ),
                      const SizedBox(height: EspacosTrato.x6),
                      for (final perfil in PerfilUso.values) ...[
                        _OpcaoPerfil(
                          perfil: perfil,
                          selecionado: perfil == _escolhido,
                          aoTocar: () => setState(() => _escolhido = perfil),
                        ),
                        const SizedBox(height: EspacosTrato.x3),
                      ],
                    ],
                  ),
                ),
              ),
              BotaoPrimario(
                texto: _escolhido.botao,
                aoTocar: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => CriarContaTela(perfil: _escolhido, servico: widget.servico),
                  ),
                ),
              ),
              const SizedBox(height: EspacosTrato.x4),
            ],
          ),
        ),
      ),
    );
  }
}

class _OpcaoPerfil extends StatelessWidget {
  const _OpcaoPerfil({required this.perfil, required this.selecionado, required this.aoTocar});

  final PerfilUso perfil;
  final bool selecionado;
  final VoidCallback aoTocar;

  @override
  Widget build(BuildContext context) {
    final raio = BorderRadius.circular(EspacosTrato.raioGrande);
    return Semantics(
      button: true,
      selected: selecionado,
      child: Material(
        color: selecionado ? CoresTrato.azulSuave : CoresTrato.superficie,
        shape: RoundedRectangleBorder(
          borderRadius: raio,
          side: BorderSide(
            color: selecionado ? CoresTrato.petroleo : CoresTrato.borda,
            width: selecionado ? 1.5 : EspacosTrato.bordaFina,
          ),
        ),
        child: InkWell(
          onTap: aoTocar,
          borderRadius: raio,
          child: Padding(
            padding: const EdgeInsets.all(EspacosTrato.x5),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    color: CoresTrato.azulClaro,
                    borderRadius: BorderRadius.circular(EspacosTrato.raio),
                  ),
                  child: Icon(perfil.icone, size: 28, color: CoresTrato.petroleo),
                ),
                const SizedBox(width: EspacosTrato.x4),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(perfil.titulo, style: TipografiaTrato.tituloOpcao),
                      const SizedBox(height: EspacosTrato.x2),
                      Text(perfil.descricao, style: TipografiaTrato.corpo),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
