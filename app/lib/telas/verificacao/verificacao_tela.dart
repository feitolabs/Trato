import 'package:flutter/material.dart';

import '../../componentes/componentes.dart';
import '../../tema/tema.dart';
import '../profissional_apoio/apoio.dart';
import 'verificacao.dart';

/// F6.1: verificação de identidade (documento + selfie) e status da análise.
/// Texto neutro: a verificação confere identidade, não garante o serviço.
class VerificacaoTela extends StatelessWidget {
  const VerificacaoTela({
    super.key,
    required this.servico,
    this.aoCapturarDocumento,
    this.aoCapturarSelfie,
    this.aoConcluir,
  });

  final ServicoVerificacao servico;
  final CapturarFoto? aoCapturarDocumento;
  final CapturarFoto? aoCapturarSelfie;

  /// Depois que o envio foi aceito pelo serviço.
  final VoidCallback? aoConcluir;

  @override
  Widget build(BuildContext context) {
    return PaginaCarregavel<(SituacaoVerificacao, TextoLgpd)>(
      titulo: 'Verificação',
      carregar: () async => (await servico.carregarSituacao(), await servico.carregarTextoLgpd()),
      construir: (context, d) => _Corpo(
        situacao: d.$1,
        lgpd: d.$2,
        servico: servico,
        aoCapturarDocumento: aoCapturarDocumento,
        aoCapturarSelfie: aoCapturarSelfie,
        aoConcluir: aoConcluir,
      ),
    );
  }
}

class _Corpo extends StatefulWidget {
  const _Corpo({
    required this.situacao,
    required this.lgpd,
    required this.servico,
    required this.aoCapturarDocumento,
    required this.aoCapturarSelfie,
    required this.aoConcluir,
  });

  final SituacaoVerificacao situacao;
  final TextoLgpd lgpd;
  final ServicoVerificacao servico;
  final CapturarFoto? aoCapturarDocumento;
  final CapturarFoto? aoCapturarSelfie;
  final VoidCallback? aoConcluir;

  @override
  State<_Corpo> createState() => _CorpoState();
}

class _CorpoState extends State<_Corpo> {
  String? _documento;
  String? _selfie;
  bool _ciente = false;
  bool _enviando = false;
  bool _enviado = false;
  String? _erro;

  late StatusVerificacao _status = widget.situacao.status;

  bool get _podeEnviar => _status == StatusVerificacao.naoEnviada || _status == StatusVerificacao.pendente;
  bool get _completo => _documento != null && _selfie != null && _ciente;

  Future<void> _capturar(CapturarFoto? captura, void Function(String) guardar) async {
    final ref = await captura?.call();
    if (ref != null && mounted) setState(() => guardar(ref));
  }

  Future<void> _enviar() async {
    setState(() {
      _enviando = true;
      _erro = null;
    });
    try {
      await widget.servico.enviar(EnvioVerificacao(documento: _documento!, selfie: _selfie!));
      if (!mounted) return;
      setState(() {
        _enviando = false;
        _enviado = true;
        _status = StatusVerificacao.emAnalise;
      });
      widget.aoConcluir?.call();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _enviando = false;
        _erro = 'Não foi possível enviar. Tente de novo.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = widget.lgpd;
    return CorpoRolavel(
      rodape: _podeEnviar
          ? Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_erro != null) ...[
                  AvisoFaixa(texto: _erro!, tipo: TipoStatus.perigo, icone: Icons.error_outline),
                  const SizedBox(height: EspacosTrato.x3),
                ],
                BotaoPrimario(
                  texto: 'Enviar para análise',
                  carregando: _enviando,
                  aoTocar: _completo ? _enviar : null,
                ),
              ],
            )
          : null,
      children: [
        Text('Confirme sua identidade', style: TipografiaTrato.tituloGrande),
        const SizedBox(height: EspacosTrato.x3),
        _CartaoStatus(status: _status, motivo: widget.situacao.motivo),
        const SizedBox(height: EspacosTrato.x3),
        Text(
          'A verificação confere se o documento é seu. Ela não garante a qualidade '
          'de nenhum serviço.',
          style: TipografiaTrato.corpoPequeno.copyWith(color: CoresTrato.textoSecundario),
        ),
        if (_podeEnviar) ...[
          const TituloSecao('Envie duas fotos'),
          CampoFoto(
            rotulo: 'Foto do documento',
            referencia: _documento,
            aoTocar: () => _capturar(widget.aoCapturarDocumento, (r) => _documento = r),
          ),
          const SizedBox(height: EspacosTrato.x3),
          CampoFoto(
            rotulo: 'Selfie segurando o rosto',
            referencia: _selfie,
            aoTocar: () => _capturar(widget.aoCapturarSelfie, (r) => _selfie = r),
          ),
        ],
        const TituloSecao('Seus dados, em linguagem simples'),
        CartaoTrato(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _BlocoLgpd(titulo: 'Para que usamos', texto: l.finalidade),
              const SizedBox(height: EspacosTrato.x3),
              _BlocoLgpd(titulo: 'Por quanto tempo guardamos', texto: l.retencao),
              const SizedBox(height: EspacosTrato.x3),
              _BlocoLgpd(titulo: 'Quem pode ver', texto: l.quemVe),
            ],
          ),
        ),
        if (_podeEnviar) ...[
          const SizedBox(height: EspacosTrato.x3),
          CheckboxListTile(
            key: const Key('ciente_lgpd'),
            value: _ciente,
            onChanged: (v) => setState(() => _ciente = v ?? false),
            controlAffinity: ListTileControlAffinity.leading,
            contentPadding: EdgeInsets.zero,
            activeColor: CoresTrato.petroleo,
            title: Text(
              'Li como meus dados serão usados e quero enviar.',
              style: TipografiaTrato.corpo,
            ),
          ),
        ],
        if (_enviado) ...[
          const SizedBox(height: EspacosTrato.x3),
          const AvisoFaixa(
            texto: 'Recebemos suas fotos. Avisaremos quando a análise terminar.',
            tipo: TipoStatus.info,
            icone: Icons.info_outline,
          ),
        ],
      ],
    );
  }
}

class _BlocoLgpd extends StatelessWidget {
  const _BlocoLgpd({required this.titulo, required this.texto});

  final String titulo;
  final String texto;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(titulo, style: TipografiaTrato.corpoForte),
        const SizedBox(height: EspacosTrato.x1),
        Text(texto, style: TipografiaTrato.corpo),
      ],
    );
  }
}

class _CartaoStatus extends StatelessWidget {
  const _CartaoStatus({required this.status, required this.motivo});

  final StatusVerificacao status;
  final String? motivo;

  @override
  Widget build(BuildContext context) {
    final (texto, tipo, icone, explica) = switch (status) {
      StatusVerificacao.naoEnviada => (
          'Ainda não enviada',
          TipoStatus.alerta,
          Icons.hourglass_empty,
          'Envie as fotos abaixo para começar a análise.'
        ),
      StatusVerificacao.emAnalise => (
          'Em análise',
          TipoStatus.info,
          Icons.hourglass_top,
          'Estamos conferindo suas fotos. Você será avisado quando terminar.'
        ),
      StatusVerificacao.aprovada => (
          'Aprovada',
          TipoStatus.sucesso,
          Icons.check_circle_outline,
          'Seu documento foi conferido.'
        ),
      StatusVerificacao.pendente => (
          'Pendente',
          TipoStatus.alerta,
          Icons.error_outline,
          'Precisamos que você envie de novo.'
        ),
    };
    return CartaoTrato(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ChipStatus(texto: texto, tipo: tipo, icone: icone),
          const SizedBox(height: EspacosTrato.x2),
          Text(explica, style: TipografiaTrato.corpo),
          if (status == StatusVerificacao.pendente && motivo != null) ...[
            const SizedBox(height: EspacosTrato.x2),
            Text('Motivo: $motivo', style: TipografiaTrato.corpoForte),
          ],
        ],
      ),
    );
  }
}
