import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../comuns/textos_dos_termos.dart';
import '../../componentes/componentes.dart';
import '../../dados/erros.dart';
import '../../dispositivo/abrir_link.dart';
import '../../tema/tema.dart';
import '../comuns/estados.dart';
import 'mei.dart';

/// Portal do Empreendedor (gov.br): onde se abre o MEI de graça.
final Uri enderecoAbrirMei =
    Uri.parse('https://www.gov.br/empresas-e-negocios/pt-br/empreendedor');

/// "Meu MEI": o profissional informa o CNPJ do MEI e vê a situação. O app só pede e mostra; quem
/// decide é o servidor. A razão social aparece só aqui, para o próprio profissional.
class MeuCnpjTela extends StatelessWidget {
  const MeuCnpjTela({super.key, required this.servico});

  final ServicoMei servico;

  @override
  Widget build(BuildContext context) {
    return MolduraTelaComum(
      titulo: 'Meu MEI',
      child: CarregadorTela<DadosMei>(
        carregar: servico.carregar,
        construir: (context, dados, _) => _Corpo(servico: servico, inicial: dados),
      ),
    );
  }
}

class _Corpo extends StatefulWidget {
  const _Corpo({required this.servico, required this.inicial});

  final ServicoMei servico;
  final DadosMei inicial;

  @override
  State<_Corpo> createState() => _CorpoState();
}

class _CorpoState extends State<_Corpo> {
  late DadosMei _dados = widget.inicial;
  late final _campo = TextEditingController(text: formatarCnpj(widget.inicial.cnpj ?? ''));
  String? _erro;
  var _enviando = false;

  /// O servidor recusou (422) falando de MEI: o caminho "Abrir meu MEI" sobe para junto do erro.
  var _recusadoPorMei = false;

  @override
  void dispose() {
    _campo.dispose();
    super.dispose();
  }

  /// Dica local (o servidor decide): 14 dígitos com dígito verificador que bate.
  String? get _dica {
    final d = soDigitosCnpj(_campo.text);
    if (d.length < 14) return null;
    return cnpjParecidoValido(d) ? null : 'Confira o número: ele parece estar incorreto.';
  }

  Future<void> _validar() async {
    final d = soDigitosCnpj(_campo.text);
    if (d.length != 14) {
      setState(() => _erro = 'O CNPJ do MEI tem 14 números. Confira o que você digitou.');
      return;
    }
    setState(() {
      _enviando = true;
      _erro = null;
      _recusadoPorMei = false;
    });
    try {
      final novo = await widget.servico.validar(d);
      if (mounted) setState(() => _dados = novo);
    } on ErroTrato catch (e) {
      if (mounted) {
        setState(() {
          _erro = e.mensagem;
          _recusadoPorMei =
              e.codigoHttp == 422 && RegExp(r'\bmei\b', caseSensitive: false).hasMatch(e.mensagem);
        });
      }
    } on Object {
      if (mounted) {
        setState(() => _erro = 'Não foi possível validar agora. Tente de novo.');
      }
    } finally {
      if (mounted) setState(() => _enviando = false);
    }
  }

  Future<void> _abrirMei() async {
    final abriu = await abrirLink(enderecoAbrirMei);
    if (!abriu && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Não deu para abrir o navegador. Acesse $enderecoAbrirMei')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.cores;
    final verificado = _dados.status == StatusMei.valido;
    return ListView(
      padding: const EdgeInsets.only(bottom: EspacosTrato.x6),
      children: [
        Text(
          'Para orçar e receber, você precisa de um MEI ativo (qualquer atividade).',
          style: TipografiaTrato.corpo.copyWith(color: c.textoSecundario),
        ),
        const SizedBox(height: EspacosTrato.x4),
        _Situacao(dados: _dados),
        const SizedBox(height: EspacosTrato.x4),
        CampoTrato(
          key: const Key('campo-cnpj'),
          rotulo: 'CNPJ do MEI',
          controlador: _campo,
          teclado: TextInputType.number,
          dica: '00.000.000/0000-00',
          ajuda: _erro == null ? _dica : null,
          erro: _erro,
          formatadores: [_FormatadorCnpj()],
          aoMudar: (_) => setState(() {
            _erro = null;
            _recusadoPorMei = false;
          }),
        ),
        if (_recusadoPorMei) ...[
          const SizedBox(height: EspacosTrato.x4),
          _CaminhoMei(aoAbrir: _abrirMei),
        ],
        const SizedBox(height: EspacosTrato.x4),
        BotaoPrimario(
          key: const Key('botao-validar-cnpj'),
          texto: verificado ? 'Validar de novo' : 'Validar',
          carregando: _enviando,
          aoTocar: _enviando ? null : _validar,
        ),
        if (!verificado && !_recusadoPorMei) ...[
          const SizedBox(height: EspacosTrato.x6),
          _CaminhoMei(aoAbrir: _abrirMei),
        ],
      ],
    );
  }
}

class _Situacao extends StatelessWidget {
  const _Situacao({required this.dados});

  final DadosMei dados;

  @override
  Widget build(BuildContext context) {
    final c = context.cores;
    final secundario = TipografiaTrato.corpoPequeno.copyWith(color: c.textoSecundario);
    switch (dados.status) {
      case StatusMei.valido:
        return CartaoTrato(
          key: const Key('situacao-cnpj'),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const ChipStatus(
                texto: 'MEI verificado',
                tipo: TipoStatus.sucesso,
                icone: Icons.verified_outlined,
              ),
              if (dados.razaoSocial != null) ...[
                const SizedBox(height: EspacosTrato.x3),
                Text(dados.razaoSocial!, style: TipografiaTrato.corpoForte),
                Text('Aparece só para você.', style: secundario),
              ],
              if (!dados.podeOrcarEReceber) ...[
                const SizedBox(height: EspacosTrato.x2),
                Text(
                    'Ainda não dá para enviar orçamentos. Fale com o suporte. '
                    '$textoAtendimentoHumano',
                    style: secundario),
              ],
            ],
          ),
        );
      case StatusMei.pendente:
        return _aviso(
          context,
          chip: const ChipStatus(texto: 'Em conferência', tipo: TipoStatus.alerta),
          texto: 'Estamos conferindo o seu MEI. Pode levar um pouco; volte mais tarde.',
          motivo: dados.motivo,
        );
      case StatusMei.invalido:
        return _aviso(
          context,
          chip: const ChipStatus(texto: 'MEI não validado', tipo: TipoStatus.perigo),
          texto: 'Não conseguimos validar este CNPJ como MEI. Confira o número do seu MEI.',
          motivo: dados.motivo,
        );
      case StatusMei.naoInformado:
        return _aviso(
          context,
          chip: const ChipStatus(texto: 'MEI não informado', tipo: TipoStatus.info),
          texto: 'Sem MEI você não consegue enviar orçamentos.',
          motivo: null,
        );
    }
  }

  Widget _aviso(BuildContext context,
      {required Widget chip, required String texto, String? motivo}) {
    return CartaoTrato(
      key: const Key('situacao-cnpj'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          chip,
          const SizedBox(height: EspacosTrato.x3),
          Text(texto, style: TipografiaTrato.corpo),
          if (motivo != null) ...[
            const SizedBox(height: EspacosTrato.x2),
            Text('Motivo: $motivo',
                key: const Key('motivo-cnpj'),
                style: TipografiaTrato.corpoPequeno.copyWith(color: context.cores.textoSecundario)),
          ],
        ],
      ),
    );
  }
}

class _CaminhoMei extends StatelessWidget {
  const _CaminhoMei({required this.aoAbrir});

  final VoidCallback aoAbrir;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Ainda não tem MEI?', style: TipografiaTrato.titulo),
        const SizedBox(height: EspacosTrato.x2),
        Text('Sem um MEI ativo você não consegue enviar orçamentos.',
            style: TipografiaTrato.corpo),
        const SizedBox(height: EspacosTrato.x1),
        Text('Abrir o MEI é grátis e leva cerca de 10 minutos.', style: TipografiaTrato.corpo),
        const SizedBox(height: EspacosTrato.x1),
        Text('Volte aqui para informar o CNPJ do MEI.', style: TipografiaTrato.corpo),
        const SizedBox(height: EspacosTrato.x4),
        BotaoSecundario(
          key: const Key('botao-abrir-mei'),
          texto: 'Abrir meu MEI (grátis)',
          icone: Icons.open_in_new,
          aoTocar: aoAbrir,
        ),
      ],
    );
  }
}

/// Máscara 00.000.000/0000-00 enquanto digita.
class _FormatadorCnpj extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue antigo, TextEditingValue novo) {
    final texto = formatarCnpj(novo.text);
    return TextEditingValue(
      text: texto,
      selection: TextSelection.collapsed(offset: texto.length),
    );
  }
}
