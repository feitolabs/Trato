import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../componentes/componentes.dart';
import '../../dados/erros.dart';
import '../comuns/prazo_avaliacao.dart';
import '../../tema/tema.dart';
import 'apoio_conclusao.dart';
import 'campo_longo.dart';
import 'modelos.dart';
import 'estrelas_nota.dart';
import '../cliente/etiquetas_elogio.dart';

/// Tela 19: avaliação em 5 critérios, comentário e gorjeta opcional.
class AvaliacaoTela extends StatefulWidget {
  const AvaliacaoTela({
    super.key,
    required this.dados,
    this.notasIniciais,
    this.aoEnviar,
    this.aoAvaliarDepois,
  });

  final DadosAvaliacao dados;

  /// Notas já marcadas ao abrir (o protótipo mostra 5, 5, 4, 5, 0). Sem isso, tudo zerado.
  final List<int>? notasIniciais;
  final dynamic Function(EnvioAvaliacao)? aoEnviar;
  final VoidCallback? aoAvaliarDepois;

  @override
  State<AvaliacaoTela> createState() => _AvaliacaoTelaState();
}

class _AvaliacaoTelaState extends State<AvaliacaoTela> {
  late final List<int> _notas = List.of(
    widget.notasIniciais ?? List.filled(widget.dados.criterios.length, 0),
  );
  final _comentario = TextEditingController();
  final _outraGorjeta = TextEditingController();
  var _enviando = false;

  /// O servidor recusou o envio (409): prazo terminado, já avaliado... O botão sai da tela.
  String? _recusa;
  final _etiquetas = <String>[];
  var _avisoEtiquetas = false;

  /// null = "Não"; -1 = "Outro"; senão o valor sugerido em centavos.
  int? _gorjeta;

  static const _outro = -1;

  @override
  void dispose() {
    _comentario.dispose();
    _outraGorjeta.dispose();
    super.dispose();
  }

  int get _gorjetaCentavos {
    if (_gorjeta == null) return 0;
    if (_gorjeta == _outro) {
      final digitos = _outraGorjeta.text.replaceAll(RegExp(r'\D'), '');
      return digitos.isEmpty ? 0 : int.parse(digitos) * 100;
    }
    return _gorjeta!;
  }

  void _alternarEtiqueta(String e) {
    setState(() {
      if (_etiquetas.contains(e)) {
        _etiquetas.remove(e);
        _avisoEtiquetas = false;
      } else if (_etiquetas.length >= maxEtiquetasPorAvaliacao) {
        _avisoEtiquetas = true; // o 4º toque não seleciona
      } else {
        _etiquetas.add(e);
        _avisoEtiquetas = false;
      }
    });
  }

  Future<void> _enviar() async {
    if (_enviando) return;
    setState(() => _enviando = true);
    var sucesso = false;
    try {
      final resposta = await widget.aoEnviar?.call(
        EnvioAvaliacao(
          notas: List.unmodifiable(_notas),
          comentario: _comentario.text.trim(),
          gorjetaCentavos: _gorjetaCentavos,
          etiquetas: List.unmodifiable(_etiquetas),
        ),
      );
      // Se quem chamou devolve `true`, a avaliação foi gravada: o botão fica desligado.
      sucesso = resposta == true;
    } on ErroTrato catch (e) {
      if (e.codigoHttp != 409) rethrow;
      if (mounted) setState(() => _recusa = e.mensagem);
    } finally {
      if (mounted) setState(() => _enviando = sucesso);
    }
  }

  /// Termos 12.4: a tela avisa do incentivo, igual para qualquer nota.
  String _textoBonus(DadosAvaliacao dados) =>
      '${_textoGanho(dados)} Vale para qualquer nota, positiva ou negativa.';

  String _textoGanho(DadosAvaliacao dados) {
    if (dados.bonusMoedas <= 0) {
      return 'Avaliar pode render Tratinhos de desconto.';
    }
    final nomeMoeda = dados.bonusMoedas == 1 ? 'Tratinho' : 'Tratinhos';
    final valorCentavos = dados.valorMoedaCentavos;
    if (valorCentavos != null) {
      return 'Avaliar rende +${dados.bonusMoedas} $nomeMoeda '
          '(${formatarReais(dados.bonusMoedas * valorCentavos)} de desconto).';
    }
    return 'Avaliar rende +${dados.bonusMoedas} $nomeMoeda.';
  }

  @override
  Widget build(BuildContext context) {
    final c = context.cores;
    final dados = widget.dados;
    final fechada = _recusa ?? (dados.prazoEncerrado ? textoPrazoEncerrado : null);
    if (!dados.jaAvaliou && fechada != null) {
      return EstruturaConclusao(
        rodape: BotaoPrimario(
          texto: 'Voltar',
          aoTocar: widget.aoAvaliarDepois ?? () => Navigator.of(context).maybePop(),
        ),
        children: [
          const SizedBox(height: EspacosTrato.x8),
          Icon(Icons.event_busy_outlined, size: 48, color: c.textoSecundario),
          const SizedBox(height: EspacosTrato.x5),
          Text(
            'Não dá para avaliar',
            style: TipografiaTrato.tituloGrande.copyWith(color: c.texto),
          ),
          const SizedBox(height: EspacosTrato.x3),
          Text(
            fechada,
            key: const ValueKey('avaliacao-fechada'),
            style: TipografiaTrato.corpo.copyWith(color: c.textoSecundario),
          ),
        ],
      );
    }
    if (dados.jaAvaliou) {
      return EstruturaConclusao(
        rodape: BotaoPrimario(
          texto: 'Voltar',
          aoTocar: widget.aoAvaliarDepois ?? () => Navigator.of(context).maybePop(),
        ),
        children: [
          const SizedBox(height: EspacosTrato.x8),
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: c.verdeSuave,
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.check_rounded, size: 36, color: c.verdeTexto),
          ),
          const SizedBox(height: EspacosTrato.x5),
          Text(
            'Você já avaliou este serviço',
            style: TipografiaTrato.tituloGrande.copyWith(color: c.texto),
          ),
          const SizedBox(height: EspacosTrato.x3),
          Text(
            'Sua avaliação sobre o atendimento de ${dados.nomeProfissional} já foi registrada.',
            style: TipografiaTrato.corpo.copyWith(color: c.textoSecundario),
          ),
        ],
      );
    }

    return EstruturaConclusao(
      rodape: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (dados.bonusDisponivel)
            Padding(
              padding: const EdgeInsets.only(bottom: EspacosTrato.x2),
              child: Text(
                _textoBonus(dados),
                key: const ValueKey('legenda-bonus-tratinhos'),
                textAlign: TextAlign.center,
                style: TipografiaTrato.legenda.copyWith(color: c.textoSecundario),
              ),
            ),
          if (dados.avaliarAte != null)
            Padding(
              padding: const EdgeInsets.only(bottom: EspacosTrato.x2),
              child: Text(
                textoAvaliarAte(dados.avaliarAte!),
                key: const ValueKey('avaliar-ate'),
                textAlign: TextAlign.center,
                style: TipografiaTrato.legenda.copyWith(color: c.textoSecundario),
              ),
            ),
          BotaoPrimario(
            texto: 'Enviar avaliação',
            carregando: _enviando,
            aoTocar: _enviando ? null : _enviar,
          ),
          const SizedBox(height: EspacosTrato.x1),
          BotaoLink(texto: 'Avaliar depois', aoTocar: widget.aoAvaliarDepois ?? () {}),
        ],
      ),
      children: [
        const SizedBox(height: EspacosTrato.x2),
        Align(
          alignment: Alignment.centerLeft,
          child: ChipStatus(
            // O pagamento já foi confirmado pelo parceiro antes do serviço; aqui o que acabou
            // de acontecer é a confirmação do serviço pelo cliente.
            texto: 'Serviço confirmado · ${formatarReais(dados.valorLiberadoCentavos)} pagos',
            tipo: TipoStatus.sucesso,
            icone: Icons.check,
          ),
        ),
        const SizedBox(height: EspacosTrato.x4),
        Text('Como foi o serviço com ${dados.nomeProfissional}?',
            style: TipografiaTrato.tituloGrande),
        const SizedBox(height: EspacosTrato.x2),
        Text(
          'Sua nota ajuda outros clientes. ${primeiraMaiuscula(dados.nomeProfissional)} também avalia você.',
          style: TipografiaTrato.corpo.copyWith(color: context.cores.textoSecundario),
        ),
        const SizedBox(height: EspacosTrato.x5),
        CartaoTrato(
          child: Column(
            children: [
              for (var i = 0; i < dados.criterios.length; i++) ...[
                if (i > 0) const Divider(height: EspacosTrato.x6),
                _LinhaCriterio(
                  criterio: dados.criterios[i],
                  nota: _notas[i],
                  aoMudar: (n) => setState(() => _notas[i] = n),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: EspacosTrato.x5),
        Text('O que foi bom?', style: TipografiaTrato.corpoForte),
        const SizedBox(height: EspacosTrato.x1),
        Text(
          'Opcional. Escolha até $maxEtiquetasPorAvaliacao.',
          style: TipografiaTrato.legenda.copyWith(color: context.cores.textoSecundario),
        ),
        const SizedBox(height: EspacosTrato.x3),
        Wrap(
          spacing: EspacosTrato.x2,
          runSpacing: EspacosTrato.x2,
          children: [
            for (final e in etiquetasDeElogio)
              FilterChip(
                key: ValueKey('etiqueta-$e'),
                label: Text(e),
                selected: _etiquetas.contains(e),
                onSelected: (_) => _alternarEtiqueta(e),
              ),
          ],
        ),
        if (_avisoEtiquetas)
          Padding(
            padding: const EdgeInsets.only(top: EspacosTrato.x2),
            child: Text(
              'Você pode escolher até $maxEtiquetasPorAvaliacao elogios.',
              key: const Key('aviso-etiquetas'),
              style: TipografiaTrato.legenda.copyWith(color: context.cores.vermelhoTexto),
            ),
          ),
        const SizedBox(height: EspacosTrato.x5),
        CampoLongo(rotulo: 'Conte como foi (opcional)', controlador: _comentario),
        if (dados.gorjetaDisponivel) ...[
          const SizedBox(height: EspacosTrato.x5),
          Text('Gorjeta (opcional)', style: TipografiaTrato.corpoForte),
          const SizedBox(height: EspacosTrato.x1),
          Text(
            'Vai inteira para o profissional, sem taxa.',
            style: TipografiaTrato.legenda.copyWith(color: context.cores.textoSecundario),
          ),
          const SizedBox(height: EspacosTrato.x3),
          Row(
            children: [
              _OpcaoGorjeta(
                texto: 'Não',
                selecionado: _gorjeta == null,
                aoTocar: () => setState(() => _gorjeta = null),
              ),
              for (final valor in dados.gorjetasCentavos)
                _OpcaoGorjeta(
                  texto: formatarReais(valor).replaceAll(',00', ''),
                  selecionado: _gorjeta == valor,
                  aoTocar: () => setState(() => _gorjeta = valor),
                ),
              _OpcaoGorjeta(
                texto: 'Outro',
                selecionado: _gorjeta == _outro,
                aoTocar: () => setState(() => _gorjeta = _outro),
              ),
            ],
          ),
          if (_gorjeta == _outro) ...[
            const SizedBox(height: EspacosTrato.x3),
            CampoTrato(
              rotulo: 'Valor da gorjeta',
              controlador: _outraGorjeta,
              prefixo: 'R\$ ',
              teclado: TextInputType.number,
              formatadores: [FilteringTextInputFormatter.digitsOnly],
            ),
          ],
        ],
      ],
    );
  }
}

class _LinhaCriterio extends StatelessWidget {
  const _LinhaCriterio({required this.criterio, required this.nota, required this.aoMudar});

  final String criterio;
  final int nota;
  final ValueChanged<int> aoMudar;

  @override
  Widget build(BuildContext context) {
    final rotulo = Text(criterio, style: TipografiaTrato.corpoForte);
    final estrelas = EstrelasNota(rotulo: criterio, nota: nota, aoMudar: aoMudar);
    // Em coluna estreita (320 dp) o rótulo vai para cima das estrelas em vez de encolher.
    return LayoutBuilder(
      builder: (context, caixa) {
        if (caixa.maxWidth < 300) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [rotulo, const SizedBox(height: EspacosTrato.x1), estrelas],
          );
        }
        return Row(
          children: [
            Expanded(child: rotulo),
            const SizedBox(width: EspacosTrato.x2),
            estrelas,
          ],
        );
      },
    );
  }
}

class _OpcaoGorjeta extends StatelessWidget {
  const _OpcaoGorjeta({required this.texto, required this.selecionado, required this.aoTocar});

  final String texto;
  final bool selecionado;
  final VoidCallback aoTocar;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: EspacosTrato.x1),
        child: BotaoSecundario(texto: texto, aoTocar: aoTocar, selecionado: selecionado),
      ),
    );
  }
}
