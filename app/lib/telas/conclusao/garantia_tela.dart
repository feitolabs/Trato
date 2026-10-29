import 'package:flutter/material.dart';

import '../../componentes/componentes.dart';
import '../../tema/tema.dart';
import 'apoio_conclusao.dart';
import 'dados_exemplo.dart';

/// Tela 21: dias restantes da garantia, o que cobre e o que não cobre.
/// Prazos e a data final vêm do backend; o app não calcula garantia.
class GarantiaTela extends StatelessWidget {
  const GarantiaTela({
    super.key,
    required this.dados,
    this.aoPedirRetrabalho,
    this.aoVerContrato,
  });

  final DadosGarantia dados;
  final VoidCallback? aoPedirRetrabalho;
  final VoidCallback? aoVerContrato;

  @override
  Widget build(BuildContext context) {
    final ativa = dados.ativa;
    return EstruturaConclusao(
      tituloBarra: dados.titulo,
      rodape: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          BotaoPrimario(
            texto: 'Pedir retrabalho',
            aoTocar: ativa ? (aoPedirRetrabalho ?? () {}) : null,
          ),
          const SizedBox(height: EspacosTrato.x1),
          BotaoLink(texto: 'Ver contrato do serviço', aoTocar: aoVerContrato ?? () {}),
        ],
      ),
      children: [
        Text('Garantia do serviço', style: TipografiaTrato.tituloGrande),
        const SizedBox(height: EspacosTrato.x4),
        CartaoTrato(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ChipStatus(
                texto: ativa ? 'Garantia ativa' : 'Garantia encerrada',
                tipo: ativa ? TipoStatus.info : TipoStatus.alerta,
                icone: Icons.shield_outlined,
              ),
              const SizedBox(height: EspacosTrato.x3),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Flexible(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        '${dados.diasRestantes} ${dados.diasRestantes == 1 ? 'dia' : 'dias'}',
                        style: TipografiaTrato.tituloGrande,
                        maxLines: 1,
                      ),
                    ),
                  ),
                  const SizedBox(width: EspacosTrato.x3),
                  Expanded(
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          'até ${formatarData(dados.fimEm)}',
                          style: TipografiaTrato.corpoPequeno.copyWith(
                            color: CoresTrato.textoSecundario,
                          ),
                          maxLines: 1,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: EspacosTrato.x3),
              ClipRRect(
                borderRadius: BorderRadius.circular(EspacosTrato.raioPilula),
                child: LinearProgressIndicator(
                  value: dados.progresso,
                  minHeight: 8,
                  color: CoresTrato.azulTexto,
                  backgroundColor: CoresTrato.borda,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: EspacosTrato.x5),
        Text('O que a garantia cobre', style: TipografiaTrato.titulo),
        const SizedBox(height: EspacosTrato.x3),
        _ItemCobertura(texto: dados.cobre, cobre: true),
        const SizedBox(height: EspacosTrato.x3),
        _ItemCobertura(texto: dados.naoCobre, cobre: false),
        const SizedBox(height: EspacosTrato.x3),
        Text(
          'O profissional tem ${dados.prazoAtendimentoDias} dias para atender. '
          'Se não houver atendimento, o suporte analisa o caso.',
          style: TipografiaTrato.corpoPequeno.copyWith(color: CoresTrato.textoSecundario),
        ),
        const SizedBox(height: EspacosTrato.x4),
        const Row(
          children: [
            Expanded(child: EspacoFoto(legenda: '[Antes]')),
            SizedBox(width: EspacosTrato.x2),
            Expanded(child: EspacoFoto(legenda: '[Depois]')),
          ],
        ),
      ],
    );
  }
}

class _ItemCobertura extends StatelessWidget {
  const _ItemCobertura({required this.texto, required this.cobre});

  final String texto;
  final bool cobre;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Icon(
            cobre ? Icons.check : Icons.close,
            color: cobre ? CoresTrato.verdeTexto : CoresTrato.vermelhoTexto,
            semanticLabel: cobre ? 'Cobre' : 'Não cobre',
          ),
        ),
        const SizedBox(width: EspacosTrato.x3),
        Expanded(child: Text(texto, style: TipografiaTrato.corpo)),
      ],
    );
  }
}
