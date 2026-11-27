import 'dart:async';

import 'package:flutter/material.dart';

import '../componentes/base.dart';
import '../nucleo/escopo.dart';
import '../nucleo/navegador.dart';
import '../tema/tema.dart';
import 'modal_sigiloso.dart';

/// Quem abre o link da prova. Trocável nos testes.
bool Function(String url) abridorDeProva = abrirEmNovaAba;

/// Um link protegido: o que é e o endereço curto (null = o servidor não liberou).
typedef LinkDeProva = ({String rotulo, String? url, int? segundos});

typedef BuscarProvas = Future<List<LinkDeProva>> Function(BuildContext context, String motivo);

/// Provas de um caso de cliente ausente. Nada é carregado antes de a pessoa escrever o motivo; os
/// links valem pouco tempo e são apagados quando vencem ou quando o modal fecha.
Future<void> abrirProvas(BuildContext context, String pedidoId, String pedido) => _abrir(
      context,
      'Provas · $pedido',
      (ctx, motivo) async => [
        for (final a in await ctx.api.anexosAusencia(pedidoId, motivo: motivo))
          (
            rotulo: [_tipo(a.tipo), ?formatoDoArquivo(a.tipoConteudo), _autor(a.enviadoPor)].join(' · '),
            url: a.url,
            segundos: a.expiraEmSegundos,
          ),
      ],
    );

/// Provas da contestação de uma medida de conta (Termos 20.5).
Future<void> abrirProvasDaContestacao(BuildContext context, String medidaId, String protocolo) => _abrir(
      context,
      'Provas da contestação · $protocolo',
      (ctx, motivo) async => [
        for (final (i, a) in (await ctx.api.abrirAnexosContestacao(medidaId, motivo: motivo)).indexed)
          (
            rotulo: 'Prova ${i + 1} · ${formatoDoArquivo(a.tipoConteudo) ?? 'arquivo'} · '
                '${tamanhoLegivel(a.tamanhoBytes)}',
            url: a.url,
            segundos: a.expiraEmSegundos,
          ),
      ],
    );

/// Foto da nota e provas de uma contestação de materiais (Termos 6.9). A ordem é a do servidor.
Future<void> abrirAnexosDoMaterial(BuildContext context, String contestacaoId, String protocolo) => _abrir(
      context,
      'Nota e provas · $protocolo',
      (ctx, motivo) async => [
        for (final a in await ctx.api.abrirAnexosContestacaoMaterial(contestacaoId, motivo: motivo))
          (
            rotulo: [
              switch (a.tipo) {
                'nota_material' => 'Foto da nota de material',
                'contestacao' => 'Prova da contestação',
                _ => 'Anexo',
              },
              ?formatoDoArquivo(a.tipoConteudo),
              _autor(a.enviadoPor),
            ].join(' · '),
            url: a.url,
            segundos: a.expiraEmSegundos,
          ),
      ],
      maximoMotivo: 2000,
    );

/// [maximoMotivo] é o limite do motivo na rota do backend.
Future<void> _abrir(BuildContext context, String titulo, BuscarProvas buscar, {int maximoMotivo = 500}) =>
    mostrarModal<void>(
      context,
      largura: 560,
      construir: (_) => _ProvasModal(titulo: titulo, buscar: buscar, maximoMotivo: maximoMotivo),
    );

/// "image/jpeg" -> "foto". Tipo ausente ou desconhecido não ganha rótulo.
String? formatoDoArquivo(String? tipo) {
  final t = (tipo ?? '').toLowerCase();
  if (t.startsWith('image/')) return 'foto';
  if (t.startsWith('video/')) return 'vídeo';
  if (t.startsWith('audio/')) return 'áudio';
  return t == 'application/pdf' ? 'PDF' : null;
}

String tamanhoLegivel(int bytes) => bytes < 1024 * 1024
    ? '${(bytes / 1024).ceil()} KB'
    : '${(bytes / (1024 * 1024)).toStringAsFixed(1).replaceAll('.', ',')} MB';

/// Abre um link protegido em outra aba (sem acesso ao painel). Só https.
void abrirLinkProtegido(BuildContext context, String url) {
  if (!url.startsWith('https://') || !abridorDeProva(url)) {
    mostrarAviso(context, 'Não foi possível abrir o arquivo neste navegador.', erro: true);
  }
}

String _tipo(String t) => switch (t) {
      'registro_ausencia' => 'Foto do registro da ausência',
      'justificativa' => 'Anexo da justificativa',
      'comprovante_retencao' => 'Comprovante da retenção',
      'contestacao' => 'Anexo da contestação',
      _ => 'Anexo',
    };

String _autor(String? a) => switch (a) {
      'cliente' => 'enviado pelo cliente',
      'profissional' => 'enviado pelo profissional',
      'equipe' => 'enviado pela equipe',
      _ => 'autor não informado',
    };

class _ProvasModal extends StatefulWidget {
  const _ProvasModal({required this.titulo, required this.buscar, required this.maximoMotivo});
  final int maximoMotivo;
  final String titulo;
  final BuscarProvas buscar;

  @override
  State<_ProvasModal> createState() => _ProvasModalState();
}

class _ProvasModalState extends State<_ProvasModal> with SomeComASessao {
  final _motivo = TextEditingController();
  List<LinkDeProva>? _anexos;
  Timer? _validade;
  bool _carregando = false;
  bool _venceu = false;
  String? _erro;

  int get _maximo => widget.maximoMotivo;

  @override
  void limparSigiloso() {
    _validade?.cancel();
    _anexos = null;
  }

  @override
  void dispose() {
    limparSigiloso();
    _motivo.dispose();
    super.dispose();
  }

  bool get _motivoValido {
    final n = _motivo.text.trim().length;
    return n >= kMotivoMinimo && n <= _maximo;
  }

  Future<void> _carregar() async {
    if (_carregando || !_motivoValido) return;
    setState(() {
      _carregando = true;
      _erro = null;
      _venceu = false;
    });
    try {
      final lista = await widget.buscar(context, _motivo.text.trim());
      if (!mounted || !context.sessao.logado) return;
      _validade?.cancel();
      final segundos = lista
          .map((a) => a.segundos)
          .nonNulls
          .fold(300, (menor, s) => s < menor ? s : menor);
      _validade = Timer(Duration(seconds: segundos), () {
        if (mounted) {
          setState(() {
            _anexos = null;
            _venceu = true;
          });
        }
      });
      setState(() => _anexos = lista);
    } catch (e) {
      if (mounted) setState(() => _erro = e.toString());
    } finally {
      if (mounted) setState(() => _carregando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final anexos = _anexos;
    return CorpoModal(
      titulo: widget.titulo,
      consequencia: 'O acesso fica registrado na auditoria com seu nome e o motivo. Os links valem 5 minutos.',
      filhos: [
        if (_erro != null) ...[
          BannerInfo(_erro!, titulo: 'Não foi possível abrir as provas.', tom: Tom.erro),
          const SizedBox(height: EspacosTrato.x3),
        ],
        if (_venceu) ...[
          const BannerInfo('Os links venceram. Peça de novo se ainda precisar.', tom: Tom.alerta),
          const SizedBox(height: EspacosTrato.x3),
        ],
        if (anexos == null) ...[
          CampoMotivo(controle: _motivo, aoMudar: () => setState(() {}), rotulo: 'Motivo do acesso'),
          const SizedBox(height: EspacosTrato.x1),
          Text('Até $_maximo caracteres. Não escreva dado pessoal no motivo.', style: TipografiaTrato.legenda),
        ] else if (anexos.isEmpty)
          Text('Nenhuma prova neste caso.', style: TipografiaTrato.corpo)
        else
          for (final a in anexos)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: EspacosTrato.x1),
              child: Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: EspacosTrato.x3,
                children: [
                  Text(a.rotulo, style: TipografiaTrato.corpo),
                  if (a.url != null && a.url!.startsWith('https://'))
                    BotaoTrato.link('Abrir', aoPressionar: () => abrirLinkProtegido(context, a.url!))
                  else
                    const ChipEstado('Arquivo indisponível', tom: Tom.alerta),
                ],
              ),
            ),
      ],
      acoes: [
        BotaoTrato.secundario('Fechar', aoPressionar: () => Navigator.of(context).pop()),
        if (anexos == null)
          BotaoTrato.primario(
            'Ver provas do caso',
            aoPressionar: _motivoValido && !_carregando ? _carregar : null,
            carregando: _carregando,
            rotuloCarregando: 'Buscando',
          ),
      ],
    );
  }
}
