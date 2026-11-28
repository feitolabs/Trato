import 'package:flutter/material.dart';

import '../componentes/base.dart';
import '../dados/api_admin.dart';
import '../nucleo/formato.dart';
import '../tema/tema.dart';

// Trava de saques (Termos 20.6): os textos dizem só o que o backend faz.
const kTravaSemFraude = 'Sem a marcação por fraude, a trava não bloqueia a liberação nem os repasses. Confira à mão.';
const kTravaComFraude = 'Por fraude, a liberação no livro fica adiada até o limite informado, até a trava vencer ou '
    'ser revertida. Pagamento manual ou no Stripe continua sem trava: confira à mão.';
const kTravaRenovar = 'Renovar é registrar uma trava nova. Com mais de uma trava por fraude em vigor, vale a mais '
    'recente; para substituir, reverta a antiga em Medidas.';
const kFimDaTravaAoReverter = 'Esta é uma trava por fraude: reverter encerra a retenção dela, e a liberação no livro '
    'volta a seguir se não houver outra trava por fraude em vigor.';
const kFimDaTravaAoEncurtar = 'Esta é uma trava por fraude: com o novo prazo ela termina antes. Quando terminar, a '
    'liberação adiada no livro pode voltar a andar, se não houver outra trava por fraude em vigor nem outro impedimento.';
const kFimDaTravaAoDestravar = 'Encerra todas as travas de saques da conta, inclusive por fraude: a liberação no '
    'livro volta a seguir.';
const kFimDaTravaAoAtivar = 'Mudar para ativo encerra as travas de saques, inclusive por fraude: a liberação no '
    'livro volta a seguir. Confira em Medidas antes.';

/// Aviso antes de destravar, conforme o que o backend informou ([vigente] null = não informado).
String avisoAoDestravar(bool? vigente) => switch (vigente) {
      true => 'Há trava por fraude em vigor. $kFimDaTravaAoDestravar',
      false => 'Não há trava por fraude em vigor. Encerra todas as travas de saques da conta.',
      null => kFimDaTravaAoDestravar,
    };

/// Aviso antes de reativar a conta. Null = nada a avisar (o backend informou que não há trava).
String? avisoAoAtivar(bool? vigente) => switch (vigente) {
      true => 'Há trava por fraude em vigor. $kFimDaTravaAoAtivar',
      false => null,
      null => kFimDaTravaAoAtivar,
    };

/// Se falhar, o painel segue sem o limite e o servidor recusa o que passar dele.
Future<int?> lerPrazoMaximoDaTrava(ApiAdmin api) async {
  try {
    return await api.prazoMaximoTravaFraude();
  } catch (_) {
    return null;
  }
}

/// Rotas antigas de status e risco (Termos 20.8).
const kAcoesImediatas = 'As ações daqui valem na hora e não cancelam um encerramento agendado (nem voltar para ativo): '
    'para cancelar, reverta a medida em Medidas de conta. Encerramento sem falta do usuário é feito em Medidas de conta.';

/// Limite digitado em reais -> centavos inteiros. Null se vazio, inválido ou zero.
int? lerLimiteDaTrava(String texto) {
  final v = lerReaisEmCentavos(texto);
  return v == null || v <= 0 ? null : v;
}

const kErroLimiteDaTrava = 'Informe um valor maior que zero. Use vírgula nos centavos: 1.234,56.';

/// O que o painel pede em `travar-saque`. O prazo máximo da trava por fraude é do servidor.
class CamposTrava {
  bool fraude = false;
  String textoLimite = '';
  String textoDias = '';

  /// Prazo máximo da trava por fraude informado pelo servidor; null = não informado.
  int? prazoMaximo;

  /// 90 é o que o formato da rota de risco aceita; com fraude vale o configurado, se menor.
  int get maximoDeDias {
    final n = prazoMaximo;
    return fraude && n != null && n < 90 ? n : 90;
  }

  int? get limiteCentavos => fraude ? lerLimiteDaTrava(textoLimite) : null;
  int? get dias => int.tryParse(textoDias.trim());

  /// Vazio é permitido.
  bool get diasValidos => textoDias.trim().isEmpty || (dias != null && dias! >= 1 && dias! <= maximoDeDias);

  bool get valido => diasValidos && (!fraude || limiteCentavos != null);
}

class CamposTravaForm extends StatelessWidget {
  const CamposTravaForm(this.campos, {super.key, required this.aoMudar});

  final CamposTrava campos;
  final VoidCallback aoMudar;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Material(
          type: MaterialType.transparency,
          child: CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            title: Text('Por fraude', style: TipografiaTrato.corpo),
            value: campos.fraude,
            onChanged: (v) {
              campos.fraude = v ?? false;
              aoMudar();
            },
          ),
        ),
        BannerInfo(campos.fraude ? kTravaComFraude : kTravaSemFraude, tom: Tom.alerta),
        if (campos.fraude) ...[
          const SizedBox(height: EspacosTrato.x2),
          Text(kTravaRenovar, style: TipografiaTrato.legenda),
          const SizedBox(height: EspacosTrato.x3),
          TextFormField(
            initialValue: campos.textoLimite,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            onChanged: (v) {
              campos.textoLimite = v;
              aoMudar();
            },
            decoration: InputDecoration(
              labelText: 'Limite da retenção (prejuízo apurado)',
              prefixText: 'R\$ ',
              errorText:
                  campos.textoLimite.trim().isNotEmpty && campos.limiteCentavos == null ? kErroLimiteDaTrava : null,
              errorMaxLines: 3,
            ),
          ),
        ],
        const SizedBox(height: EspacosTrato.x3),
        TextFormField(
          initialValue: campos.textoDias,
          keyboardType: TextInputType.number,
          onChanged: (v) {
            campos.textoDias = v;
            aoMudar();
          },
          decoration: InputDecoration(
            labelText: 'Duração da trava em dias',
            helperText: !campos.fraude
                ? 'Vazio = sem data final.'
                : campos.prazoMaximo == null
                    ? 'Vazio = prazo máximo configurado no servidor, que recusa acima dele.'
                    : 'Vazio = prazo máximo configurado (${campos.prazoMaximo} dias).',
            helperMaxLines: 2,
            errorText: campos.diasValidos ? null : 'Use de 1 a ${campos.maximoDeDias} dias',
          ),
        ),
        const SizedBox(height: EspacosTrato.x3),
      ],
    );
  }
}
