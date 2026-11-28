/// Termos 1.4: a pessoa consulta o registro do próprio aceite. Só mostra o que o servidor manda
/// (versão, data, hora e o endereço de IP, quando vier).
library;

import 'package:flutter/material.dart';

import '../../componentes/componentes.dart';
import '../../tema/tema.dart';
import '../comuns/formato_aparelho.dart';

class RegistroDoAceite {
  const RegistroDoAceite({this.versao, this.aceitoEm, this.ip});

  /// `aceito_ip`: nulo se o servidor não informou.
  final String? ip;

  /// Nula: não há aceite registrado.
  final String? versao;
  final DateTime? aceitoEm;

  /// Nulo: o registro está indisponível (sem histórico no servidor ou campo ausente).
  static RegistroDoAceite? deJson(Object? json) {
    if (json is! Map || json['registro_disponivel'] != true) return null;
    if (!json.containsKey('versao_aceita')) return null;
    final versao = json['versao_aceita'];
    if (versao == null) return const RegistroDoAceite();
    if (versao is! String || versao.trim().isEmpty) return null;
    final quando = json['aceita_em'];
    final ip = json['aceito_ip'];
    return RegistroDoAceite(
      versao: versao.trim(),
      aceitoEm: quando is String ? DateTime.tryParse(quando) : null,
      ip: ip is String && ip.trim().isNotEmpty ? ip.trim() : null,
    );
  }
}

abstract interface class ConsultaDoAceite {
  /// Nulo: registro indisponível (404/503 ou servidor sem o histórico).
  Future<RegistroDoAceite?> registroDoAceite();
}

String _dataEHora(DateTime momento) {
  final d = momento.toLocal();
  String dois(int n) => n.toString().padLeft(2, '0');
  return '${dois(d.day)}/${dois(d.month)}/${d.year} às ${horaDoAparelho(momento)}';
}

/// Cartão "Seu aceite dos Termos", com consulta própria: se falhar, o resto da tela continua.
class CartaoRegistroDoAceite extends StatefulWidget {
  const CartaoRegistroDoAceite({super.key, required this.consulta});

  final ConsultaDoAceite consulta;

  @override
  State<CartaoRegistroDoAceite> createState() => _CartaoRegistroDoAceiteState();
}

class _CartaoRegistroDoAceiteState extends State<CartaoRegistroDoAceite> {
  RegistroDoAceite? _registro;
  var _carregando = true;
  var _falhou = false;

  @override
  void initState() {
    super.initState();
    _consultar();
  }

  Future<void> _consultar() async {
    setState(() {
      _carregando = true;
      _falhou = false;
    });
    try {
      final registro = await widget.consulta.registroDoAceite();
      if (!mounted) return;
      setState(() {
        _registro = registro;
        _carregando = false;
      });
    } on Object {
      if (!mounted) return;
      setState(() {
        _carregando = false;
        _falhou = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.cores;
    final corpo = TipografiaTrato.corpo.copyWith(color: c.texto);
    final registro = _registro;
    return CartaoTrato(
      child: SizedBox(
        width: double.infinity,
        child: Column(
          key: const ValueKey('registro-do-aceite'),
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Seu aceite dos Termos', style: TipografiaTrato.tituloCartao),
            const SizedBox(height: EspacosTrato.x2),
            if (_carregando)
              Text('Consultando seu aceite...', style: corpo)
            else if (_falhou) ...[
              Text(
                'Não foi possível consultar seu aceite agora.',
                style: corpo.copyWith(color: c.vermelhoTexto),
              ),
              BotaoLink(texto: 'Tentar de novo', aoTocar: _consultar),
            ] else if (registro == null)
              Text('O registro do aceite está indisponível agora.', style: corpo)
            else if (registro.versao == null)
              Text('Não há aceite dos Termos registrado para a sua conta.', style: corpo)
            else ...[
              Text('Versão aceita: ${registro.versao}', style: corpo),
              Text(
                registro.aceitoEm == null
                    ? 'Data do aceite não informada.'
                    : 'Aceito em ${_dataEHora(registro.aceitoEm!)}',
                style: corpo,
              ),
              if (registro.ip != null)
                Text('Endereço de IP do aceite: ${registro.ip}', style: corpo),
            ],
          ],
        ),
      ),
    );
  }
}
