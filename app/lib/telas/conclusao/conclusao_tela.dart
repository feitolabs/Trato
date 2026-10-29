import 'package:flutter/material.dart';

import '../../componentes/componentes.dart';
import '../../tema/tema.dart';
import 'apoio_conclusao.dart';
import 'dados_exemplo.dart';

/// Tela 18: o profissional terminou; o cliente confere fotos, valor retido e o código.
class ConclusaoTela extends StatelessWidget {
  const ConclusaoTela({
    super.key,
    this.resumo = resumoConclusaoExemplo,
    this.aoConfirmar,
    this.aoRelatarProblema,
  });

  final ResumoConclusao resumo;
  final VoidCallback? aoConfirmar;
  final VoidCallback? aoRelatarProblema;

  @override
  Widget build(BuildContext context) {
    return EstruturaConclusao(
      tituloBarra: 'Pedido ${resumo.numeroPedido}',
      rodape: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          BotaoPrimario(texto: 'Confirmar serviço', aoTocar: aoConfirmar ?? () {}),
          const SizedBox(height: EspacosTrato.x2),
          BotaoSecundario(texto: 'Relatar problema', aoTocar: aoRelatarProblema ?? () {}),
        ],
      ),
      children: [
        Text('${resumo.nomeProfissional} terminou o serviço', style: TipografiaTrato.tituloGrande),
        const SizedBox(height: EspacosTrato.x2),
        Text(
          'Confira as fotos e o resultado antes de confirmar.',
          style: TipografiaTrato.corpo.copyWith(color: CoresTrato.textoSecundario),
        ),
        const SizedBox(height: EspacosTrato.x5),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: _FotoComHora(foto: '[Foto antes]', hora: resumo.legendaFotoAntes)),
            const SizedBox(width: EspacosTrato.x2),
            Expanded(child: _FotoComHora(foto: '[Foto depois]', hora: resumo.legendaFotoDepois)),
          ],
        ),
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
                rotulo: 'Total do serviço',
                valor: formatarReais(resumo.totalRetidoCentavos),
                destaque: true,
              ),
            ],
          ),
        ),
        const SizedBox(height: EspacosTrato.x4),
        CartaoTrato(
          child: Column(
            children: [
              Text('Código de conclusão', style: TipografiaTrato.tituloCartao),
              const SizedBox(height: EspacosTrato.x4),
              _CodigoConclusao(codigo: resumo.codigo),
              const SizedBox(height: EspacosTrato.x4),
              Text(
                'Passe ao profissional só se o serviço estiver pronto, ou confirme aqui.',
                textAlign: TextAlign.center,
                style: TipografiaTrato.corpoPequeno.copyWith(color: CoresTrato.textoSecundario),
              ),
            ],
          ),
        ),
        const SizedBox(height: EspacosTrato.x4),
        _AvisoRelogio(texto: resumo.avisoLiberacao),
      ],
    );
  }
}

class _FotoComHora extends StatelessWidget {
  const _FotoComHora({required this.foto, required this.hora});

  final String foto;
  final String hora;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        EspacoFoto(legenda: foto),
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
