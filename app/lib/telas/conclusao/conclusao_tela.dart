import 'dart:async';

import 'package:flutter/material.dart';

import '../../componentes/componentes.dart';
import '../../tema/tema.dart';
import '../profissional_apoio/apoio.dart' show AvisoFaixa;
import 'apoio_conclusao.dart';
import 'modelos.dart';

/// Tela 18: o profissional terminou; o cliente confere fotos, valor retido e o código.
class ConclusaoTela extends StatefulWidget {
  const ConclusaoTela({
    super.key,
    required this.resumo,
    this.aoConfirmar,
    this.aoRelatarProblema,
  });

  final ResumoConclusao resumo;
  final FutureOr<void> Function()? aoConfirmar;
  final VoidCallback? aoRelatarProblema;

  @override
  State<ConclusaoTela> createState() => _ConclusaoTelaState();
}

class _ConclusaoTelaState extends State<ConclusaoTela> {
  var _confirmando = false;

  ResumoConclusao get resumo => widget.resumo;

  /// Desliga o botão no 1º toque: um 2º toque rápido não repete a confirmação.
  Future<void> _confirmar() async {
    if (_confirmando) return;
    setState(() => _confirmando = true);
    try {
      await widget.aoConfirmar?.call();
    } finally {
      if (mounted) setState(() => _confirmando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return EstruturaConclusao(
      tituloBarra: 'Pedido ${resumo.numeroPedido}',
      rodape: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (resumo.prazoConfirmacao != null || resumo.garantiaTexto != null) ...[
            Text(
              [
                if (resumo.prazoConfirmacao != null) resumo.prazoConfirmacao!,
                if (resumo.garantiaTexto != null) resumo.garantiaTexto!,
              ].join(' '),
              key: const ValueKey('prazo-e-garantia'),
              textAlign: TextAlign.center,
              style: TipografiaTrato.corpoPequeno.copyWith(color: CoresTrato.textoSecundario),
            ),
            const SizedBox(height: EspacosTrato.x2),
          ],
          BotaoPrimario(
            texto: resumo.checkOutSemCodigo
                ? 'Confirmar conclusão e liberar pagamento'
                : 'Confirmar serviço',
            carregando: _confirmando,
            aoTocar: widget.aoConfirmar == null ? () {} : _confirmar,
          ),
          const SizedBox(height: EspacosTrato.x2),
          BotaoSecundario(texto: 'Relatar problema', aoTocar: widget.aoRelatarProblema ?? () {}),
        ],
      ),
      children: [
        Text(
          '${primeiraMaiuscula(resumo.nomeProfissional)} terminou o serviço',
          style: TipografiaTrato.tituloGrande,
        ),
        const SizedBox(height: EspacosTrato.x2),
        Text(
          resumo.remoto
              ? (resumo.checkOutSemCodigo
                  ? 'O profissional encerrou sem o código de conclusão. Confira o resultado antes de liberar o pagamento.'
                  : 'Confira o resultado antes de confirmar.')
              : (resumo.checkOutSemCodigo
                  ? 'O profissional encerrou sem o código de conclusão e enviou a foto final. '
                      'Confira antes de liberar o pagamento.'
                  : 'Confira as fotos e o resultado antes de confirmar.'),
          style: TipografiaTrato.corpo.copyWith(color: CoresTrato.textoSecundario),
        ),
        if (resumo.checkOutSemCodigo) ...[
          const SizedBox(height: EspacosTrato.x4),
          const AvisoFaixa(
            texto: 'Encerramento sem código: o pagamento só é liberado depois da sua confirmação.',
            tipo: TipoStatus.alerta,
            icone: Icons.info_outline,
          ),
        ],
        if (!resumo.remoto) ...[
          const SizedBox(height: EspacosTrato.x5),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _FotoComHora(
                  foto: resumo.fotoAntes ?? (resumo.fotosCarregadas ? 'Sem foto' : '[Foto antes]'),
                  referencia: resumo.fotoAntes,
                  hora: resumo.legendaFotoAntes,
                ),
              ),
              const SizedBox(width: EspacosTrato.x2),
              Expanded(
                child: _FotoComHora(
                  foto:
                      resumo.fotoDepois ?? (resumo.fotosCarregadas ? 'Sem foto' : '[Foto depois]'),
                  referencia: resumo.fotoDepois,
                  hora: resumo.legendaFotoDepois,
                ),
              ),
            ],
          ),
        ],
        const SizedBox(height: EspacosTrato.x5),
        CartaoTrato(
          child: Column(
            children: [
              LinhaValor(rotulo: 'Orçamento', valor: formatarReais(resumo.orcamentoCentavos)),
              const SizedBox(height: EspacosTrato.x3),
              LinhaValor(rotulo: 'Aditivo aprovado', valor: formatarReais(resumo.aditivoCentavos)),
              const SizedBox(height: EspacosTrato.x3),
              const Divider(),
              const SizedBox(height: EspacosTrato.x3),
              LinhaValor(
                rotulo: 'Total pago',
                valor: formatarReais(resumo.totalRetidoCentavos),
                destaque: true,
              ),
            ],
          ),
        ),
        if (!resumo.checkOutSemCodigo) ...[
          const SizedBox(height: EspacosTrato.x4),
          CartaoTrato(
            child: Column(
              children: [
                Text('Código de conclusão', style: TipografiaTrato.tituloCartao),
                const SizedBox(height: EspacosTrato.x4),
                _CodigoConclusao(codigo: resumo.codigo),
                const SizedBox(height: EspacosTrato.x4),
                Text(
                  'Passe ao profissional só se o serviço estiver pronto, ou confirme aqui. '
                  'Não envie o código por mensagem.',
                  textAlign: TextAlign.center,
                  style: TipografiaTrato.corpoPequeno.copyWith(color: CoresTrato.textoSecundario),
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: EspacosTrato.x4),
        _AvisoRelogio(texto: resumo.avisoLiberacao),
      ],
    );
  }
}

class _FotoComHora extends StatelessWidget {
  const _FotoComHora({required this.foto, required this.hora, this.referencia});

  final String foto;
  final String hora;

  /// URL da foto real; sem ela a caixa mostra só a legenda.
  final String? referencia;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        EspacoFoto(legenda: foto, referencia: referencia),
        const SizedBox(height: EspacosTrato.x2),
        Text(
          hora,
          style: TipografiaTrato.corpoPequeno.copyWith(color: CoresTrato.textoSecundario),
        ),
      ],
    );
  }
}

/// Quatro caixas com um dígito cada; encolhem em tela estreita.
class _CodigoConclusao extends StatelessWidget {
  const _CodigoConclusao({required this.codigo});

  final String codigo;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Código de conclusão ${codigo.split('').join(' ')}',
      excludeSemantics: true,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          for (var i = 0; i < codigo.length; i++) ...[
            if (i > 0) const SizedBox(width: EspacosTrato.x3),
            Flexible(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 60),
                child: AspectRatio(
                  aspectRatio: 0.85,
                  child: Container(
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: CoresTrato.superficie,
                      borderRadius: BorderRadius.circular(EspacosTrato.raio),
                      border: Border.all(color: CoresTrato.petroleo, width: 1.5),
                    ),
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(codigo[i], style: TipografiaTrato.tituloGrande),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _AvisoRelogio extends StatelessWidget {
  const _AvisoRelogio({required this.texto});

  final String texto;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(EspacosTrato.x4),
      decoration: BoxDecoration(
        color: CoresTrato.azulSuave,
        borderRadius: BorderRadius.circular(EspacosTrato.raio),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.schedule, color: CoresTrato.azulTexto),
          const SizedBox(width: EspacosTrato.x3),
          Expanded(
            child: Text(texto, style: TipografiaTrato.corpo.copyWith(color: CoresTrato.azulTexto)),
          ),
        ],
      ),
    );
  }
}
