import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../componentes/componentes.dart';
import '../../dados/carregador.dart';
import '../../dados/erros.dart';
import '../../dados/servico_cep.dart';
import '../../tema/tema.dart';
import '../auth/validacao.dart';
import '../comuns/estados.dart';
import '../comuns/foco_rolagem.dart';
import 'modelos.dart';

String textoDoErro(Object erro) =>
    erro is ErroTrato ? erro.mensagem : 'Algo deu errado. Tente de novo.';

/// Dados pessoais e endereço principal com preenchimento automático via CEP.
class DadosPessoaisTela extends StatelessWidget {
  const DadosPessoaisTela({
    super.key,
    required this.servico,
    this.servicoCep,
    this.aoAlterarCredenciais,
  });

  final ServicoConta servico;
  final ServicoCep? servicoCep;
  final VoidCallback? aoAlterarCredenciais;

  @override
  Widget build(BuildContext context) {
    return MolduraTelaComum(
      titulo: 'Dados pessoais',
      child: CarregadorTela<DadosPessoaisConta>(
        carregar: servico.dados,
        construir: (context, dados, _) => _Formulario(
          servico: servico,
          servicoCep: servicoCep,
          dados: dados,
          aoAlterarCredenciais: aoAlterarCredenciais,
        ),
      ),
    );
  }
}

class _Formulario extends StatefulWidget {
  const _Formulario({
    required this.servico,
    required this.dados,
    this.servicoCep,
    this.aoAlterarCredenciais,
  });

  final ServicoConta servico;
  final ServicoCep? servicoCep;
  final DadosPessoaisConta dados;
  final VoidCallback? aoAlterarCredenciais;

  @override
  State<_Formulario> createState() => _FormularioState();
}

class _FormularioState extends State<_Formulario> {
  final _scroll = ScrollController();
  late final _telefone = TextEditingController(text: formatarTelefone(widget.dados.telefone));
  late DateTime? _nascimento = widget.dados.dataNascimento;
  final _cpf = TextEditingController();

  final _cep = TextEditingController();
  final _logradouro = TextEditingController();
  final _numero = TextEditingController();
  final _complemento = TextEditingController();
  final _bairro = TextEditingController();
  final _cidade = TextEditingController();
  final _uf = TextEditingController();

  String? _enderecoId;
  String _apelidoEndereco = 'Principal';
  bool _enderecoModificado = false;

  final _keyCpf = GlobalKey();
  final _keyTelefone = GlobalKey();
  final _keyCep = GlobalKey();
  final _keyRua = GlobalKey();
  final _keyNumero = GlobalKey();
  final _keyBairro = GlobalKey();
  final _keyCidade = GlobalKey();
  final _keyUf = GlobalKey();

  final _focoCpf = FocusNode();
  final _focoTelefone = FocusNode();
  final _focoCep = FocusNode();
  final _focoRua = FocusNode();
  final _focoNumero = FocusNode();
  final _focoBairro = FocusNode();
  final _focoCidade = FocusNode();
  final _focoUf = FocusNode();

  String? _erroCpf;
  String? _erroTelefone;
  String? _erroNascimento;
  String? _erroEnderecoGeral;
  var _salvando = false;
  String? _erro;
  String? _aviso;

  @override
  void initState() {
    super.initState();
    unawaited(_carregarEnderecoPrincipal());
  }

  Future<void> _carregarEnderecoPrincipal() async {
    try {
      final lista = await widget.servico.enderecos();
      if (!mounted || lista.isEmpty) return;
      final principal = lista.where((e) => e.principal).firstOrNull ?? lista.first;
      setState(() {
        _enderecoId = principal.id;
        _apelidoEndereco = principal.apelido.isNotEmpty ? principal.apelido : 'Principal';
        _cep.text = formatarCep(principal.cep);
        _logradouro.text = principal.logradouro;
        _numero.text = principal.numero;
        _complemento.text = principal.complemento ?? '';
        _bairro.text = principal.bairro;
        _cidade.text = principal.cidade;
        _uf.text = principal.uf;
      });
    } on Object {
      // Cadastro sem endereço salvo ou offline: segue sem bloquear os dados pessoais.
    }
  }

  @override
  void dispose() {
    _scroll.dispose();
    for (final c in [
      _telefone,
      _cpf,
      _cep,
      _logradouro,
      _numero,
      _complemento,
      _bairro,
      _cidade,
      _uf,
    ]) {
      c.dispose();
    }
    for (final f in [
      _focoCpf,
      _focoTelefone,
      _focoCep,
      _focoRua,
      _focoNumero,
      _focoBairro,
      _focoCidade,
      _focoUf,
    ]) {
      f.dispose();
    }
    super.dispose();
  }

  Future<void> _escolherData() async {
    final hoje = DateTime.now();
    final limite18 = DateTime(hoje.year - 18, hoje.month, hoje.day);
    final padrao = DateTime(hoje.year - 30, hoje.month, hoje.day);
    final inicial =
        _nascimento != null && !_nascimento!.isAfter(limite18) ? _nascimento! : padrao;
    final data = await showDatePicker(
      context: context,
      initialDate: inicial,
      firstDate: DateTime(1900),
      lastDate: limite18,
    );
    if (data != null) {
      setState(() {
        _nascimento = data;
        _erroNascimento = null;
      });
    }
  }

  bool get _temDadosEndereco =>
      _cep.text.trim().isNotEmpty ||
      _logradouro.text.trim().isNotEmpty ||
      _numero.text.trim().isNotEmpty ||
      _bairro.text.trim().isNotEmpty ||
      _cidade.text.trim().isNotEmpty ||
      _uf.text.trim().isNotEmpty;

  void _aplicarCep(EnderecoPorCep end) {
    setState(() {
      _enderecoModificado = true;
      _erroEnderecoGeral = null;
      if (end.logradouro.trim().isNotEmpty) _logradouro.text = end.logradouro;
      if (end.bairro.trim().isNotEmpty) _bairro.text = end.bairro;
      if (end.cidade.trim().isNotEmpty) _cidade.text = end.cidade;
      if (end.uf.trim().isNotEmpty) _uf.text = end.uf.toUpperCase();
    });
  }

  Future<void> _salvar() async {
    String? errCpf;
    String? errTel;
    final digitos = _telefone.text.replaceAll(RegExp(r'\D'), '');
    if (digitos.isNotEmpty && digitos.length != 10 && digitos.length != 11) {
      errTel = 'Informe o telefone com DDD.';
    }
    final semCpf = (widget.dados.cpfFinal ?? '').isEmpty;
    final cpfDigitos = _cpf.text.replaceAll(RegExp(r'\D'), '');
    if (semCpf) {
      errCpf = ValidacaoAuth.cpf(_cpf.text);
    }
    String? errNasc;
    if (_nascimento != null) {
      final hoje = DateTime.now();
      var idade = hoje.year - _nascimento!.year;
      if (hoje.month < _nascimento!.month ||
          (hoje.month == _nascimento!.month && hoje.day < _nascimento!.day)) {
        idade--;
      }
      if (idade < 18) {
        errNasc = 'O cadastro é exclusivo para maiores de 18 anos.';
      }
    }

    final cepDigitos = _cep.text.replaceAll(RegExp(r'\D'), '');
    final validarEndereco = _enderecoModificado && _temDadosEndereco;
    final cepInvalido = validarEndereco && cepDigitos.length != 8;
    final ruaInvalida = validarEndereco && _logradouro.text.trim().length < 2;
    final numInvalido = validarEndereco && _numero.text.trim().isEmpty;
    final bairroInvalido = validarEndereco && _bairro.text.trim().length < 2;
    final cidadeInvalida = validarEndereco && _cidade.text.trim().length < 2;
    final ufInvalida = validarEndereco && _uf.text.trim().length != 2;
    final erroEnd = (cepInvalido ||
            ruaInvalida ||
            numInvalido ||
            bairroInvalido ||
            cidadeInvalida ||
            ufInvalida)
        ? 'Complete todos os campos obrigatórios do endereço.'
        : null;

    setState(() {
      _erroCpf = errCpf;
      _erroTelefone = errTel;
      _erroNascimento = errNasc;
      _erroEnderecoGeral = erroEnd;
      _erro = null;
      _aviso = null;
    });

    if (errCpf != null || errTel != null || errNasc != null || erroEnd != null) {
      focarPrimeiroErro([
        EntradaCampoErro(key: _keyCpf, focusNode: _focoCpf, temErro: () => _erroCpf != null),
        EntradaCampoErro(key: _keyTelefone, focusNode: _focoTelefone, temErro: () => _erroTelefone != null),
        EntradaCampoErro(key: _keyCep, focusNode: _focoCep, temErro: () => cepInvalido),
        EntradaCampoErro(key: _keyRua, focusNode: _focoRua, temErro: () => ruaInvalida),
        EntradaCampoErro(key: _keyNumero, focusNode: _focoNumero, temErro: () => numInvalido),
        EntradaCampoErro(key: _keyBairro, focusNode: _focoBairro, temErro: () => bairroInvalido),
        EntradaCampoErro(key: _keyCidade, focusNode: _focoCidade, temErro: () => cidadeInvalida),
        EntradaCampoErro(key: _keyUf, focusNode: _focoUf, temErro: () => ufInvalida),
      ]);
      return;
    }

    setState(() => _salvando = true);
    try {
      // Conta sem CPF: o telefone só salva depois de vincular o CPF (o servidor guarda os dois juntos).
      if (semCpf && cpfDigitos.isNotEmpty) {
        await widget.servico.registrarCpf(cpfDigitos);
      }
      await widget.servico.salvarDados(
        telefone: digitos.isEmpty ? null : digitos,
        nascimento: _nascimento,
        removerTelefone: digitos.isEmpty && (widget.dados.telefone ?? '').isNotEmpty,
        removerNascimento: false,
      );
      if (validarEndereco) {
        await widget.servico.salvarEndereco(EnderecoSalvo(
          id: _enderecoId ?? '',
          apelido: _apelidoEndereco,
          cep: cepDigitos,
          logradouro: _logradouro.text.trim(),
          numero: _numero.text.trim(),
          complemento: _complemento.text.trim(),
          bairro: _bairro.text.trim(),
          cidade: _cidade.text.trim(),
          uf: _uf.text.trim().toUpperCase(),
          principal: true,
        ));
        _enderecoModificado = false;
      }
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
    final recarregar = AtualizadorTela.de(context);
    final lista = ListView(
      controller: _scroll,
      physics: const AlwaysScrollableScrollPhysics(),
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
          style: TipografiaTrato.corpoPequeno.copyWith(color: context.cores.textoSecundario),
        ),
        if ((d.cpfFinal ?? '').isEmpty) ...[
          const SizedBox(height: EspacosTrato.x5),
          KeyedSubtree(
            key: _keyCpf,
            child: CampoTrato(
              rotulo: 'CPF',
              controlador: _cpf,
              foco: _focoCpf,
              dica: '000.000.000-00',
              teclado: TextInputType.number,
              formatadores: [MascaraNumerica.cpf],
              erro: _erroCpf,
            ),
          ),
          const SizedBox(height: EspacosTrato.x1),
          Text(
            'Sua conta ainda não tem CPF. Ele é gravado uma única vez e não muda depois.',
            style: TipografiaTrato.corpoPequeno.copyWith(color: context.cores.textoSecundario),
          ),
        ],
        const SizedBox(height: EspacosTrato.x5),
        KeyedSubtree(
          key: _keyTelefone,
          child: CampoTrato(
            rotulo: 'Telefone',
            controlador: _telefone,
            foco: _focoTelefone,
            dica: '(11) 98888-7777',
            teclado: TextInputType.phone,
            formatadores: [FilteringTextInputFormatter.allow(RegExp(r'[0-9()\- ]'))],
            erro: _erroTelefone ?? _erro,
          ),
        ),
        const SizedBox(height: EspacosTrato.x4),
        Text('Data de nascimento', style: TipografiaTrato.corpoPequeno),
        const SizedBox(height: EspacosTrato.x1),
        BotaoSecundario(
          texto: _nascimento == null ? 'Escolher data' : _data(_nascimento!),
          aoTocar: _escolherData,
        ),
        if (_erroNascimento != null) ...[
          const SizedBox(height: EspacosTrato.x1),
          Text(
            _erroNascimento!,
            style: TipografiaTrato.legenda.copyWith(color: context.cores.vermelhoTexto),
          ),
        ],
        const SizedBox(height: EspacosTrato.x6),
        Text('ENDEREÇO PRINCIPAL', style: TipografiaTrato.sobretitulo),
        const SizedBox(height: EspacosTrato.x2),
        KeyedSubtree(
          key: _keyCep,
          child: CampoCepAutoPreenchimento(
            controlador: _cep,
            servico: widget.servicoCep,
            foco: _focoCep,
            proximoFoco: _focoNumero,
            aoAlterar: () => _enderecoModificado = true,
            aoEncontrar: _aplicarCep,
          ),
        ),
        const SizedBox(height: EspacosTrato.x3),
        KeyedSubtree(
          key: _keyRua,
          child: CampoTrato(
            rotulo: 'Rua',
            controlador: _logradouro,
            foco: _focoRua,
            aoMudar: (_) => _enderecoModificado = true,
          ),
        ),
        const SizedBox(height: EspacosTrato.x3),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: KeyedSubtree(
                key: _keyNumero,
                child: CampoTrato(
                  rotulo: 'Número',
                  controlador: _numero,
                  foco: _focoNumero,
                  aoMudar: (_) => _enderecoModificado = true,
                ),
              ),
            ),
            const SizedBox(width: EspacosTrato.x3),
            Expanded(
              child: CampoTrato(
                rotulo: 'Complemento',
                controlador: _complemento,
                dica: 'Opcional',
                aoMudar: (_) => _enderecoModificado = true,
              ),
            ),
          ],
        ),
        const SizedBox(height: EspacosTrato.x3),
        KeyedSubtree(
          key: _keyBairro,
          child: CampoTrato(
            rotulo: 'Bairro',
            controlador: _bairro,
            foco: _focoBairro,
            aoMudar: (_) => _enderecoModificado = true,
          ),
        ),
        const SizedBox(height: EspacosTrato.x3),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              flex: 3,
              child: KeyedSubtree(
                key: _keyCidade,
                child: CampoTrato(
                  rotulo: 'Cidade',
                  controlador: _cidade,
                  foco: _focoCidade,
                  aoMudar: (_) => _enderecoModificado = true,
                ),
              ),
            ),
            const SizedBox(width: EspacosTrato.x3),
            Expanded(
              child: KeyedSubtree(
                key: _keyUf,
                child: CampoTrato(
                  rotulo: 'UF',
                  controlador: _uf,
                  foco: _focoUf,
                  aoMudar: (_) => _enderecoModificado = true,
                  formatadores: [
                    LengthLimitingTextInputFormatter(2),
                    FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z]')),
                  ],
                ),
              ),
            ),
          ],
        ),
        if (_erroEnderecoGeral != null) ...[
          const SizedBox(height: EspacosTrato.x3),
          Text(_erroEnderecoGeral!,
              style: TipografiaTrato.corpoPequeno.copyWith(color: context.cores.vermelhoTexto)),
        ],
        if (_aviso != null) ...[
          const SizedBox(height: EspacosTrato.x3),
          Text(_aviso!, style: TipografiaTrato.corpoPequeno.copyWith(color: context.cores.verdeTexto)),
        ],
        const SizedBox(height: EspacosTrato.x5),
        if (widget.aoAlterarCredenciais != null) ...[
          BotaoSecundario(
            key: const Key('botao-alterar-credenciais'),
            texto: 'Alterar e-mail ou senha',
            icone: Icons.lock_outline,
            aoTocar: widget.aoAlterarCredenciais,
          ),
          const SizedBox(height: EspacosTrato.x3),
        ],
        BotaoPrimario(texto: 'Salvar', carregando: _salvando, aoTocar: _salvando ? null : _salvar),
      ],
    );
    return recarregar == null ? lista : RefreshIndicator(onRefresh: recarregar, child: lista);
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
              style: TipografiaTrato.corpoPequeno.copyWith(color: context.cores.textoSecundario)),
          const SizedBox(width: EspacosTrato.x4),
          Expanded(child: Text(valor, textAlign: TextAlign.end, style: TipografiaTrato.corpo)),
        ],
      ),
    );
  }
}
