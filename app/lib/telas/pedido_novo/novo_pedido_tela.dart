import 'package:flutter/material.dart';

import '../../componentes/componentes.dart';
import '../../tema/tema.dart';
import '../conclusao/apoio_conclusao.dart' show formatarReais;
import '../em_breve_tela.dart';
import 'dados_exemplo.dart';
import 'modelos.dart';
import 'pecas_pedido.dart';

/// Tela 11 do protótipo: "Conte o que precisa", passo 2 de 3.
///
/// Só coleta e mostra: quem decide o que acontece depois é o backend. Os callbacks são
/// opcionais; sem eles, o botão correspondente abre [EmBreveTela].
class NovoPedidoTela extends StatefulWidget {
  const NovoPedidoTela({
    super.key,
    this.formulario = formularioExemplo,
    this.aoEnviar,
    this.aoTrocarCategoria,
    this.aoMudarEndereco,
    this.aoAdicionarFoto,
  });

  final FormularioPedido formulario;

  /// Chamado com o que foi preenchido, depois de passar nas checagens da tela.
  final ValueChanged<RascunhoPedido>? aoEnviar;
  final VoidCallback? aoTrocarCategoria;
  final VoidCallback? aoMudarEndereco;
  final VoidCallback? aoAdicionarFoto;

  @override
  State<NovoPedidoTela> createState() => _NovoPedidoTelaState();
}

class _NovoPedidoTelaState extends State<NovoPedidoTela> {
  late final Set<String> _servicos = {...widget.formulario.servicosIniciais};
  late int _quantidade = widget.formulario.quantidadeInicial;
  late String _voltagem = widget.formulario.voltagemInicial;
  late String _prazo = widget.formulario.prazos.first;
  late FaixaPreco _faixa = widget.formulario.faixas.first;
  late final _descricao = TextEditingController(text: widget.formulario.descricaoInicial);
  var _tentou = false;

  @override
  void dispose() {
    _descricao.dispose();
    super.dispose();
  }

  void _emBreve(String titulo) => Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => EmBreveTela(titulo: titulo)),
      );

  void _chamarOuEmBreve(VoidCallback? acao, String titulo) =>
      acao != null ? acao() : _emBreve(titulo);

  String? get _erroServicos =>
      _tentou && _servicos.isEmpty ? 'Escolha pelo menos um serviço.' : null;

  String? get _erroDescricao =>
      _tentou && _descricao.text.trim().isEmpty ? 'Conte o que está acontecendo.' : null;

  void _enviar() {
    setState(() => _tentou = true);
    if (_servicos.isNotEmpty && _descricao.text.trim().isNotEmpty) {
      final rascunho = RascunhoPedido(
        servicos: [
          for (final s in widget.formulario.servicos)
            if (_servicos.contains(s)) s
        ],
        quantidade: _quantidade,
        voltagem: _voltagem,
        descricao: _descricao.text.trim(),
        prazo: _prazo,
        faixa: _faixa,
      );
      if (widget.aoEnviar != null) {
        widget.aoEnviar!(rascunho);
      } else {
        _emBreve('Próximo passo do pedido');
      }
    }
  }

  static String _rotuloFaixa(FaixaPreco f) =>
      '${formatarReais(f.minimoCentavos).replaceAll(',00', '')} a '
      '${formatarReais(f.maximoCentavos).replaceAll(',00', '')}';

  @override
  Widget build(BuildContext context) {
    final f = widget.formulario;
    final secundario = TipografiaTrato.corpoPequeno.copyWith(color: CoresTrato.textoSecundario);
    return EstruturaPedido(
      tituloBarra: 'Passo 2 de 3',
      rodape: BotaoPrimario(texto: 'Próximo', aoTocar: _enviar),
      children: [
        const SizedBox(height: EspacosTrato.x2),
        Text('Conte o que precisa', style: TipografiaTrato.tituloGrande),
        const SizedBox(height: EspacosTrato.x2),
        Row(
          children: [
            const Icon(Icons.bolt, size: 22, color: CoresTrato.petroleo),
            const SizedBox(width: EspacosTrato.x2),
            Expanded(child: Text(f.categoria, style: secundario)),
            BotaoLink(
              texto: 'Trocar',
              aoTocar: () => _chamarOuEmBreve(widget.aoTrocarCategoria, 'Trocar categoria'),
            ),
          ],
        ),
        const SizedBox(height: EspacosTrato.x4),
        const RotuloSecao('O que precisa ser feito?'),
        const SizedBox(height: EspacosTrato.x3),
        Wrap(
          spacing: EspacosTrato.x2,
          runSpacing: EspacosTrato.x2,
          children: [
            for (final s in f.servicos)
              ChipOpcao(
                texto: s,
                marcado: _servicos.contains(s),
                aoTocar: () =>
                    setState(() => _servicos.contains(s) ? _servicos.remove(s) : _servicos.add(s)),
              ),
          ],
        ),
        if (_erroServicos != null) _MensagemErro(_erroServicos!),
        const SizedBox(height: EspacosTrato.x5),
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(f.perguntaQuantidade, style: TipografiaTrato.corpoForte),
                  Text(f.dicaQuantidade, style: secundario),
                ],
              ),
            ),
            const SizedBox(width: EspacosTrato.x3),
            _Contador(valor: _quantidade, aoMudar: (v) => setState(() => _quantidade = v)),
          ],
        ),
        const SizedBox(height: EspacosTrato.x5),
        RotuloSecao(f.perguntaVoltagem),
        const SizedBox(height: EspacosTrato.x3),
        Row(
          children: [
            for (var i = 0; i < f.voltagens.length; i++) ...[
              if (i > 0) const SizedBox(width: EspacosTrato.x2),
              Expanded(
                child: _OpcaoRadio(
                  texto: f.voltagens[i],
                  marcada: f.voltagens[i] == _voltagem,
                  aoTocar: () => setState(() => _voltagem = f.voltagens[i]),
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: EspacosTrato.x5),
        const RotuloSecao('Descreva o problema'),
        const SizedBox(height: EspacosTrato.x3),
        TextField(
          controller: _descricao,
          minLines: 3,
          maxLines: 6,
          keyboardType: TextInputType.multiline,
          style: TipografiaTrato.corpoGrande,
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(errorText: _erroDescricao),
        ),
        const SizedBox(height: EspacosTrato.x5),
        const RotuloSecao('Fotos'),
        const SizedBox(height: EspacosTrato.x3),
        Row(
          children: [
            for (final foto in f.fotos) ...[
              Expanded(child: _FotoReservada(foto)),
              const SizedBox(width: EspacosTrato.x3),
            ],
            Expanded(
              child: _AdicionarFoto(
                aoTocar: () => _chamarOuEmBreve(widget.aoAdicionarFoto, 'Adicionar foto'),
              ),
            ),
          ],
        ),
        const SizedBox(height: EspacosTrato.x5),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: _CampoLista<String>(
                rotulo: 'Prazo',
                valor: _prazo,
                opcoes: f.prazos,
                texto: (p) => p,
                aoMudar: (p) => setState(() => _prazo = p),
              ),
            ),
            const SizedBox(width: EspacosTrato.x3),
            Expanded(
              child: _CampoLista<FaixaPreco>(
                rotulo: 'Quanto pensa gastar?',
                valor: _faixa,
                opcoes: f.faixas,
                texto: _rotuloFaixa,
                aoMudar: (v) => setState(() => _faixa = v),
              ),
            ),
          ],
        ),
        const SizedBox(height: EspacosTrato.x5),
        CartaoTrato(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.location_on_outlined, color: CoresTrato.petroleo),
              const SizedBox(width: EspacosTrato.x3),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(child: Text(f.endereco, style: TipografiaTrato.corpoForte)),
                        BotaoLink(
                          texto: 'Mudar',
                          aoTocar: () => _chamarOuEmBreve(widget.aoMudarEndereco, 'Mudar endereço'),
                        ),
                      ],
                    ),
                    Text(f.avisoEndereco, style: secundario),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: EspacosTrato.x4),
        AvisoInfo(texto: TextSpan(text: f.avisoPrazo)),
      ],
    );
  }
}

class _MensagemErro extends StatelessWidget {
  const _MensagemErro(this.texto);

  final String texto;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: EspacosTrato.x2),
        child:
            Text(texto, style: TipografiaTrato.legenda.copyWith(color: CoresTrato.vermelhoTexto)),
      );
}

/// "− 2 +", mínimo 1.
class _Contador extends StatelessWidget {
  const _Contador({required this.valor, required this.aoMudar});

  final int valor;
  final ValueChanged<int> aoMudar;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: CoresTrato.superficie,
        border: Border.all(color: CoresTrato.borda),
        borderRadius: BorderRadius.circular(EspacosTrato.raio),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            tooltip: 'Diminuir',
            icon: const Icon(Icons.remove),
            onPressed: valor > 1 ? () => aoMudar(valor - 1) : null,
          ),
          SizedBox(
            width: EspacosTrato.x6,
            child: Text('$valor', textAlign: TextAlign.center, style: TipografiaTrato.corpoForte),
          ),
          IconButton(
            tooltip: 'Aumentar',
            icon: const Icon(Icons.add),
            onPressed: () => aoMudar(valor + 1),
          ),
        ],
      ),
    );
  }
}

class _OpcaoRadio extends StatelessWidget {
  const _OpcaoRadio({required this.texto, required this.marcada, required this.aoTocar});

  final String texto;
  final bool marcada;
  final VoidCallback aoTocar;

  @override
  Widget build(BuildContext context) {
    final raio = BorderRadius.circular(EspacosTrato.raio);
    return Semantics(
      button: true,
      selected: marcada,
      child: Material(
        color: marcada ? CoresTrato.azulSuave : CoresTrato.superficie,
        shape: RoundedRectangleBorder(
          borderRadius: raio,
          side: BorderSide(
            color: marcada ? CoresTrato.petroleo : CoresTrato.borda,
            width: marcada ? 1.5 : EspacosTrato.bordaFina,
          ),
        ),
        child: InkWell(
          borderRadius: raio,
          onTap: aoTocar,
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: EspacosTrato.x3,
              vertical: EspacosTrato.x4,
            ),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    marcada ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                    size: EspacosTrato.x4,
                    color: CoresTrato.petroleo,
                  ),
                  const SizedBox(width: EspacosTrato.x2),
                  Text(
                    texto,
                    maxLines: 1,
                    style: TipografiaTrato.corpoForte.copyWith(
                      fontWeight: marcada ? FontWeight.w700 : FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _FotoReservada extends StatelessWidget {
  const _FotoReservada(this.rotulo);

  final String rotulo;

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 1,
      child: Container(
        padding: const EdgeInsets.all(EspacosTrato.x2),
        alignment: Alignment.bottomLeft,
        decoration: BoxDecoration(
          color: CoresTrato.azulClaro,
          borderRadius: BorderRadius.circular(EspacosTrato.raio),
        ),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            rotulo,
            style: TipografiaTrato.corpoPequeno.copyWith(
              color: CoresTrato.petroleo,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}

class _AdicionarFoto extends StatelessWidget {
  const _AdicionarFoto({required this.aoTocar});

  final VoidCallback aoTocar;

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 1,
      child: CustomPaint(
        painter: _BordaTracejada(),
        child: Semantics(
          button: true,
          label: 'Adicionar foto',
          child: InkWell(
            borderRadius: BorderRadius.circular(EspacosTrato.raio),
            onTap: aoTocar,
            child: Center(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.photo_camera_outlined, color: CoresTrato.petroleo),
                    const SizedBox(height: EspacosTrato.x2),
                    Text('Adicionar', style: TipografiaTrato.corpoForte),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _BordaTracejada extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final caminho = Path()
      ..addRRect(
        RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(EspacosTrato.raio)),
      );
    final pintura = Paint()
      ..color = CoresTrato.borda
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    for (final metrica in caminho.computeMetrics()) {
      for (var d = 0.0; d < metrica.length; d += 8) {
        canvas.drawPath(metrica.extractPath(d, d + 4), pintura);
      }
    }
  }

  @override
  bool shouldRepaint(_BordaTracejada antigo) => false;
}

class _CampoLista<T> extends StatelessWidget {
  const _CampoLista({
    required this.rotulo,
    required this.valor,
    required this.opcoes,
    required this.texto,
    required this.aoMudar,
  });

  final String rotulo;
  final T valor;
  final List<T> opcoes;
  final String Function(T) texto;
  final ValueChanged<T> aoMudar;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(rotulo, maxLines: 1, style: TipografiaTrato.corpoForte),
        ),
        const SizedBox(height: EspacosTrato.x2),
        DropdownButtonFormField<T>(
          initialValue: valor,
          isExpanded: true,
          style: TipografiaTrato.corpoPequeno.copyWith(color: CoresTrato.petroleo),
          items: [
            for (final o in opcoes)
              DropdownMenuItem<T>(
                value: o,
                child: Text(texto(o), maxLines: 1, overflow: TextOverflow.ellipsis),
              ),
          ],
          onChanged: (v) {
            if (v != null) aoMudar(v);
          },
        ),
      ],
    );
  }
}
