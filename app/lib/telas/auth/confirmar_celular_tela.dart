import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../componentes/componentes.dart';
import '../../tema/tema.dart';
import '../em_breve_tela.dart';
import '../fluxo/rotas.dart';
import '../onboarding/escolha_perfil_tela.dart';
import 'estrutura_auth.dart';
import 'validacao.dart';

/// Tela 6 do protótipo: "Confirme seu celular", passo 2 de 2.
/// O SMS e o WhatsApp ainda não têm backend: a contagem de reenvio é só visual e os
/// botões abrem [EmBreveTela].
class ConfirmarCelularTela extends StatefulWidget {
  const ConfirmarCelularTela({super.key, required this.celular, this.perfil = PerfilUso.cliente});

  /// Perfil escolhido no cadastro: decide para onde o usuário vai depois de confirmar.
  final PerfilUso perfil;

  /// Celular como foi digitado no passo 1.
  final String celular;

  static const segundosParaReenviar = 45;

  @override
  State<ConfirmarCelularTela> createState() => _ConfirmarCelularTelaState();
}

class _ConfirmarCelularTelaState extends State<ConfirmarCelularTela> {
  final _codigo = TextEditingController();
  late final Timer _timer;
  var _restante = ConfirmarCelularTela.segundosParaReenviar;
  var _tentou = false;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (_restante <= 1) t.cancel();
      setState(() => _restante--);
    });
  }

  @override
  void dispose() {
    _timer.cancel();
    _codigo.dispose();
    super.dispose();
  }

  void _emBreve(String titulo) => Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => EmBreveTela(titulo: titulo)),
      );

  String get _tempo => '${_restante ~/ 60}:${(_restante % 60).toString().padLeft(2, '0')}';

  void _confirmar() {
    setState(() => _tentou = true);
    if (ValidacaoAuth.codigoSms(_codigo.text) != null) return;
    // Ainda sem backend: qualquer código no formato certo conclui o cadastro.
    if (widget.perfil == PerfilUso.cliente) {
      RotasTrato.irParaCliente(context);
    } else {
      RotasTrato.irParaProfissional(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final estiloCodigo = TipografiaTrato.tituloGrande.copyWith(letterSpacing: 12);
    return EstruturaAuth(
      tituloBarra: 'Passo 2 de 2',
      rodape: BotaoPrimario(texto: 'Confirmar código', aoTocar: _confirmar),
      children: [
        const SizedBox(height: EspacosTrato.x2),
        Text('Confirme seu celular', style: TipografiaTrato.tituloGrande),
        const SizedBox(height: EspacosTrato.x3),
        Text.rich(
          TextSpan(
            style: TipografiaTrato.corpoGrande,
            children: [
              const TextSpan(text: 'Enviamos um código de 6 números por SMS para '),
              TextSpan(
                text: ValidacaoAuth.celularMascarado(widget.celular),
                style: TipografiaTrato.corpoGrande.copyWith(fontWeight: FontWeight.w700),
              ),
              const TextSpan(text: '.'),
            ],
          ),
        ),
        const SizedBox(height: EspacosTrato.x5),
        CampoTrato(
          rotulo: 'Código',
          controlador: _codigo,
          dica: '000000',
          teclado: TextInputType.number,
          formatadores: [
            FilteringTextInputFormatter.digitsOnly,
            LengthLimitingTextInputFormatter(6),
          ],
          centralizado: true,
          estilo: estiloCodigo,
          estiloDica: estiloCodigo.copyWith(color: CoresTrato.textoDica),
          erro: _tentou ? ValidacaoAuth.codigoSms(_codigo.text) : null,
          aoMudar: (_) => setState(() {}),
        ),
        const SizedBox(height: EspacosTrato.x4),
        if (_restante > 0)
          Text(
            'Reenviar em $_tempo',
            style: TipografiaTrato.corpoGrande.copyWith(color: CoresTrato.textoSecundario),
          )
        else
          BotaoLink(texto: 'Reenviar código', aoTocar: () => _emBreve('Reenviar código')),
        BotaoLink(texto: 'Receber por WhatsApp', aoTocar: () => _emBreve('Receber por WhatsApp')),
        BotaoLink(texto: 'Mudar número', aoTocar: () => Navigator.of(context).pop()),
        const SizedBox(height: EspacosTrato.x4),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(EspacosTrato.x4),
          decoration: BoxDecoration(
            color: CoresTrato.azulSuave,
            borderRadius: BorderRadius.circular(EspacosTrato.raio),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.lock_outline, size: 22, color: CoresTrato.azulTexto),
              const SizedBox(width: EspacosTrato.x3),
              Expanded(
                child: Text(
                  'Seu número não aparece para os profissionais. As conversas acontecem pelo chat do pedido.',
                  style: TipografiaTrato.corpoPequeno.copyWith(color: CoresTrato.azulTexto),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
