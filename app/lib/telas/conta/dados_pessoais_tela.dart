import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../componentes/componentes.dart';
import '../../dados/erros.dart';
import '../../tema/tema.dart';
import '../auth/validacao.dart';
import '../comuns/estados.dart';
import 'modelos.dart';

String textoDoErro(Object erro) =>
    erro is ErroTrato ? erro.mensagem : 'Algo deu errado. Tente de novo.';

/// Dados pessoais: nome, e-mail e CPF (final) só para ver; telefone e nascimento podem mudar.
class DadosPessoaisTela extends StatelessWidget {
  const DadosPessoaisTela({super.key, required this.servico});

  final ServicoConta servico;

  @override
  Widget build(BuildContext context) {
    return MolduraTelaComum(
      titulo: 'Dados pessoais',
      child: CarregadorTela<DadosPessoaisConta>(
        carregar: servico.dados,
        construir: (context, dados, _) => _Formulario(servico: servico, dados: dados),
      ),
    );
  }
}

class _Formulario extends StatefulWidget {
  const _Formulario({required this.servico, required this.dados});

  final ServicoConta servico;
  final DadosPessoaisConta dados;

  @override
  State<_Formulario> createState() => _FormularioState();
}

class _FormularioState extends State<_Formulario> {
  late final _telefone = TextEditingController(text: formatarTelefone(widget.dados.telefone));
  late DateTime? _nascimento = widget.dados.dataNascimento;
  final _cpf = TextEditingController();
  String? _erroCpf;
  var _salvando = false;
  String? _erro;
  String? _aviso;

  @override
  void dispose() {
    _telefone.dispose();
    _cpf.dispose();
    super.dispose();
  }

  Future<void> _escolherData() async {
    final hoje = DateTime.now();
    final data = await showDatePicker(
      context: context,
      initialDate: _nascimento ?? DateTime(hoje.year - 30),
      firstDate: DateTime(1900),
      lastDate: hoje,
    );
    if (data != null) setState(() => _nascimento = data);
  }

  Future<void> _salvar() async {
    final digitos = _telefone.text.replaceAll(RegExp(r'\D'), '');
    if (digitos.isNotEmpty && digitos.length != 10 && digitos.length != 11) {
      setState(() => _erro = 'Informe o telefone com DDD.');
      return;
    }
    final semCpf = (widget.dados.cpfFinal ?? '').isEmpty;
    final cpfDigitos = _cpf.text.replaceAll(RegExp(r'\D'), '');
    if (semCpf && (cpfDigitos.isNotEmpty || digitos.isNotEmpty)) {
      final msg = ValidacaoAuth.cpf(_cpf.text);
      if (msg != null) {
        setState(() => _erroCpf = msg);
        return;
      }
    }
    setState(() {
      _salvando = true;
      _erro = null;
      _erroCpf = null;
      _aviso = null;
    });
    try {
      // Conta sem CPF: o telefone só salva depois de vincular o CPF (o servidor guarda os dois juntos).
      if (semCpf && cpfDigitos.isNotEmpty) {
        await widget.servico.registrarCpf(cpfDigitos);
      }
      await widget.servico.salvarDados(
        telefone: digitos.isEmpty ? null : digitos,
        nascimento: _nascimento,
        removerTelefone: digitos.isEmpty && (widget.dados.telefone ?? '').isNotEmpty,
        removerNascimento: _nascimento == null && widget.dados.dataNascimento != null,
      );
      if (mounted) setState(() => _aviso = 'Dados salvos.');
    } catch (e) {
      if (mounted) setState(() => _erro = textoDoErro(e));
    } finally {
      if (mounted) setState(() => _salvando = false);
    }
  }

  static String _data(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

  @override
  Widget build(BuildContext context) {
    final d = widget.dados;
    return ListView(
      padding: const EdgeInsets.only(bottom: EspacosTrato.x6),
      children: [
        CartaoTrato(
          child: Column(
            children: [
              _Linha('Nome', d.nome ?? '—'),
              if ((d.email ?? '').isNotEmpty) _Linha('E-mail', d.email!),
              if ((d.cpfFinal ?? '').isNotEmpty) _Linha('CPF', '•••.•••.•••-${d.cpfFinal}'),
            ],
          ),
        ),
        const SizedBox(height: EspacosTrato.x2),
        Text(
          'Nome, e-mail e CPF não mudam por aqui. Para corrigir, fale com a Central de ajuda.',
          style: TipografiaTrato.corpoPequeno.copyWith(color: CoresTrato.textoSecundario),
        ),
        if ((d.cpfFinal ?? '').isEmpty) ...[
          const SizedBox(height: EspacosTrato.x5),
          CampoTrato(
            rotulo: 'CPF',
            controlador: _cpf,
            dica: '000.000.000-00',
            teclado: TextInputType.number,
            formatadores: [MascaraNumerica.cpf],
            erro: _erroCpf,
          ),
          const SizedBox(height: EspacosTrato.x1),
          Text(
            'Sua conta ainda não tem CPF. Ele é gravado uma única vez e não muda depois.',
            style: TipografiaTrato.corpoPequeno.copyWith(color: CoresTrato.textoSecundario),
          ),
        ],
        const SizedBox(height: EspacosTrato.x5),
        CampoTrato(
          rotulo: 'Telefone',
          controlador: _telefone,
          dica: '(11) 98888-7777',
          teclado: TextInputType.phone,
          formatadores: [FilteringTextInputFormatter.allow(RegExp(r'[0-9()\- ]'))],
          erro: _erro,
        ),
        const SizedBox(height: EspacosTrato.x4),
        Text('Data de nascimento', style: TipografiaTrato.corpoPequeno),
        const SizedBox(height: EspacosTrato.x1),
        Row(
          children: [
            Expanded(
              child: BotaoSecundario(
                texto: _nascimento == null ? 'Escolher data' : _data(_nascimento!),
                aoTocar: _escolherData,
              ),
            ),
            if (_nascimento != null) ...[
              const SizedBox(width: EspacosTrato.x2),
              BotaoLink(texto: 'Limpar', aoTocar: () => setState(() => _nascimento = null)),
            ],
          ],
        ),
        if (_aviso != null) ...[
          const SizedBox(height: EspacosTrato.x3),
          Text(_aviso!, style: TipografiaTrato.corpoPequeno.copyWith(color: CoresTrato.verdeTexto)),
        ],
        const SizedBox(height: EspacosTrato.x5),
        BotaoPrimario(texto: 'Salvar', carregando: _salvando, aoTocar: _salvando ? null : _salvar),
      ],
    );
  }
}

class _Linha extends StatelessWidget {
  const _Linha(this.rotulo, this.valor);

  final String rotulo;
  final String valor;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: EspacosTrato.x2),
      child: Row(
        children: [
          Text(rotulo,
              style: TipografiaTrato.corpoPequeno.copyWith(color: CoresTrato.textoSecundario)),
          const SizedBox(width: EspacosTrato.x4),
          Expanded(child: Text(valor, textAlign: TextAlign.end, style: TipografiaTrato.corpo)),
        ],
      ),
    );
  }
}
