import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../componentes/componentes.dart';
import '../../dados/carregador.dart';
import '../../dados/servico_cep.dart';
import '../../tema/tema.dart';
import '../comuns/estados.dart';
import '../comuns/foco_rolagem.dart';
import 'dados_pessoais_tela.dart' show textoDoErro;
import 'modelos.dart';

/// Endereços salvos: lista, adicionar, editar, remover e escolher o principal.
class EnderecosTela extends StatefulWidget {
  const EnderecosTela({
    super.key,
    required this.servico,
    this.servicoCep,
  });

  final ServicoConta servico;
  final ServicoCep? servicoCep;

  @override
  State<EnderecosTela> createState() => _EnderecosTelaState();
}

class _EnderecosTelaState extends State<EnderecosTela> {
  final _mudou = ValueNotifier<int>(0);

  @override
  void dispose() {
    _mudou.dispose();
    super.dispose();
  }

  Future<void> _abrirForm([EnderecoSalvo? e]) async {
    final alterou = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => _FormEnderecoTela(
          servico: widget.servico,
          servicoCep: widget.servicoCep,
          endereco: e,
        ),
      ),
    );
    if (alterou == true) _mudou.value++;
  }

  @override
  Widget build(BuildContext context) {
    return MolduraTelaComum(
      titulo: 'Endereços salvos',
      child: CarregadorTela<List<EnderecoSalvo>>(
        carregar: widget.servico.enderecos,
        atualizarQuando: _mudou,
        construir: (context, itens, _) {
          final recarregar = AtualizadorTela.de(context);
          final lista = ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.only(bottom: EspacosTrato.x6),
            children: [
              if (itens.isEmpty)
                const EstadoVazio(
                  icone: Icons.home_outlined,
                  titulo: 'Nenhum endereço salvo',
                  texto: 'Salve o endereço dos seus serviços para não digitar de novo.',
                ),
              for (final e in itens) ...[
                CartaoTrato(
                  aoTocar: () => _abrirForm(e),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(e.apelido, style: TipografiaTrato.corpo),
                          if (e.principal) ...[
                            const SizedBox(width: EspacosTrato.x2),
                            Text('Principal',
                                style: TipografiaTrato.corpoPequeno
                                    .copyWith(color: CoresTrato.verdeTexto)),
                          ],
                        ],
                      ),
                      const SizedBox(height: EspacosTrato.x1),
                      Text(e.linha1, style: TipografiaTrato.corpoPequeno),
                      Text('${e.linha2} · ${formatarCep(e.cep)}',
                          style: TipografiaTrato.corpoPequeno
                              .copyWith(color: CoresTrato.textoSecundario)),
                    ],
                  ),
                ),
                const SizedBox(height: EspacosTrato.x3),
              ],
              const SizedBox(height: EspacosTrato.x3),
              BotaoPrimario(texto: 'Adicionar endereço', aoTocar: () => _abrirForm()),
            ],
          );
          return recarregar == null ? lista : RefreshIndicator(onRefresh: recarregar, child: lista);
        },
      ),
    );
  }
}

class _FormEnderecoTela extends StatefulWidget {
  const _FormEnderecoTela({
    required this.servico,
    this.servicoCep,
    this.endereco,
  });

  final ServicoConta servico;
  final ServicoCep? servicoCep;
  final EnderecoSalvo? endereco;

  @override
  State<_FormEnderecoTela> createState() => _FormEnderecoTelaState();
}

class _FormEnderecoTelaState extends State<_FormEnderecoTela> {
  final _scroll = ScrollController();
  late final _apelido = TextEditingController(text: widget.endereco?.apelido ?? '');
  late final _cep = TextEditingController(
      text: widget.endereco == null ? '' : formatarCep(widget.endereco!.cep));
  late final _logradouro = TextEditingController(text: widget.endereco?.logradouro ?? '');
  late final _numero = TextEditingController(text: widget.endereco?.numero ?? '');
  late final _complemento = TextEditingController(text: widget.endereco?.complemento ?? '');
  late final _bairro = TextEditingController(text: widget.endereco?.bairro ?? '');
  late final _cidade = TextEditingController(text: widget.endereco?.cidade ?? '');
  late final _uf = TextEditingController(text: widget.endereco?.uf ?? '');
  late var _principal = widget.endereco?.principal ?? false;
  var _tentou = false;
  var _salvando = false;
  String? _erro;

  final _keyApelido = GlobalKey();
  final _keyCep = GlobalKey();
  final _keyRua = GlobalKey();
  final _keyNumero = GlobalKey();
  final _keyBairro = GlobalKey();
  final _keyCidade = GlobalKey();
  final _keyUf = GlobalKey();

  final _focoApelido = FocusNode();
  final _focoCep = FocusNode();
  final _focoRua = FocusNode();
  final _focoNumero = FocusNode();
  final _focoBairro = FocusNode();
  final _focoCidade = FocusNode();
  final _focoUf = FocusNode();

  @override
  void dispose() {
    _scroll.dispose();
    for (final c in [_apelido, _cep, _logradouro, _numero, _complemento, _bairro, _cidade, _uf]) {
      c.dispose();
    }
    for (final f in [
      _focoApelido,
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

  String? get _erroApelido =>
      _tentou && _apelido.text.trim().isEmpty ? 'Informe um apelido (ex.: Casa).' : null;
  String? get _erroCep {
    if (!_tentou) return null;
    final digitos = _cep.text.replaceAll(RegExp(r'\D'), '');
    return digitos.length == 8 ? null : 'CEP inválido. Use 8 dígitos.';
  }

  String? get _erroRua =>
      _tentou && _logradouro.text.trim().length < 2 ? 'Informe o nome da rua.' : null;
  String? get _erroNumero =>
      _tentou && _numero.text.trim().isEmpty ? 'Informe o número.' : null;
  String? get _erroBairro =>
      _tentou && _bairro.text.trim().length < 2 ? 'Informe o bairro.' : null;
  String? get _erroCidade =>
      _tentou && _cidade.text.trim().length < 2 ? 'Informe a cidade.' : null;
  String? get _erroUf =>
      _tentou && _uf.text.trim().length != 2 ? 'Informe a UF (2 letras).' : null;

  Future<void> _salvar() async {
    setState(() {
      _tentou = true;
      _erro = null;
    });
    if (_erroApelido != null ||
        _erroCep != null ||
        _erroRua != null ||
        _erroNumero != null ||
        _erroBairro != null ||
        _erroCidade != null ||
        _erroUf != null) {
      focarPrimeiroErro([
        EntradaCampoErro(key: _keyApelido, focusNode: _focoApelido, temErro: () => _erroApelido != null),
        EntradaCampoErro(key: _keyCep, focusNode: _focoCep, temErro: () => _erroCep != null),
        EntradaCampoErro(key: _keyRua, focusNode: _focoRua, temErro: () => _erroRua != null),
        EntradaCampoErro(key: _keyNumero, focusNode: _focoNumero, temErro: () => _erroNumero != null),
        EntradaCampoErro(key: _keyBairro, focusNode: _focoBairro, temErro: () => _erroBairro != null),
        EntradaCampoErro(key: _keyCidade, focusNode: _focoCidade, temErro: () => _erroCidade != null),
        EntradaCampoErro(key: _keyUf, focusNode: _focoUf, temErro: () => _erroUf != null),
      ]);
      return;
    }
    final cep = _cep.text.replaceAll(RegExp(r'\D'), '');
    setState(() {
      _salvando = true;
      _erro = null;
    });
    try {
      await widget.servico.salvarEndereco(EnderecoSalvo(
        id: widget.endereco?.id ?? '',
        apelido: _apelido.text.trim(),
        cep: cep,
        logradouro: _logradouro.text.trim(),
        numero: _numero.text.trim(),
        complemento: _complemento.text.trim(),
        bairro: _bairro.text.trim(),
        cidade: _cidade.text.trim(),
        uf: _uf.text.trim().toUpperCase(),
        principal: _principal,
      ));
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) setState(() => _erro = textoDoErro(e));
    } finally {
      if (mounted) setState(() => _salvando = false);
    }
  }

  Future<void> _remover() async {
    final confirma = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remover endereço?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Remover')),
        ],
      ),
    );
    if (confirma != true) return;
    try {
      await widget.servico.removerEndereco(widget.endereco!.id);
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) setState(() => _erro = textoDoErro(e));
    }
  }

  void _aplicarCep(EnderecoPorCep end) {
    setState(() {
      if (end.logradouro.trim().isNotEmpty) _logradouro.text = end.logradouro;
      if (end.bairro.trim().isNotEmpty) _bairro.text = end.bairro;
      if (end.cidade.trim().isNotEmpty) _cidade.text = end.cidade;
      if (end.uf.trim().isNotEmpty) _uf.text = end.uf.toUpperCase();
    });
  }

  @override
  Widget build(BuildContext context) {
    final editando = widget.endereco != null;
    return MolduraTelaComum(
      titulo: editando ? 'Editar endereço' : 'Novo endereço',
      child: ListView(
        controller: _scroll,
        padding: const EdgeInsets.only(bottom: EspacosTrato.x6),
        children: [
          KeyedSubtree(
            key: _keyApelido,
            child: CampoTrato(
              rotulo: 'Apelido',
              controlador: _apelido,
              foco: _focoApelido,
              dica: 'Casa, Trabalho...',
              erro: _erroApelido,
              aoMudar: (_) => setState(() {}),
            ),
          ),
          const SizedBox(height: EspacosTrato.x3),
          KeyedSubtree(
            key: _keyCep,
            child: CampoCepAutoPreenchimento(
              controlador: _cep,
              servico: widget.servicoCep,
              foco: _focoCep,
              proximoFoco: _focoNumero,
              erro: _erroCep,
              aoAlterar: () => setState(() {}),
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
              erro: _erroRua,
              aoMudar: (_) => setState(() {}),
            ),
          ),
          const SizedBox(height: EspacosTrato.x3),
          KeyedSubtree(
            key: _keyNumero,
            child: CampoTrato(
              rotulo: 'Número',
              controlador: _numero,
              foco: _focoNumero,
              erro: _erroNumero,
              aoMudar: (_) => setState(() {}),
            ),
          ),
          const SizedBox(height: EspacosTrato.x3),
          CampoTrato(rotulo: 'Complemento (opcional)', controlador: _complemento),
          const SizedBox(height: EspacosTrato.x3),
          KeyedSubtree(
            key: _keyBairro,
            child: CampoTrato(
              rotulo: 'Bairro',
              controlador: _bairro,
              foco: _focoBairro,
              erro: _erroBairro,
              aoMudar: (_) => setState(() {}),
            ),
          ),
          const SizedBox(height: EspacosTrato.x3),
          KeyedSubtree(
            key: _keyCidade,
            child: CampoTrato(
              rotulo: 'Cidade',
              controlador: _cidade,
              foco: _focoCidade,
              erro: _erroCidade,
              aoMudar: (_) => setState(() {}),
            ),
          ),
          const SizedBox(height: EspacosTrato.x3),
          KeyedSubtree(
            key: _keyUf,
            child: CampoTrato(
              rotulo: 'UF',
              controlador: _uf,
              foco: _focoUf,
              erro: _erroUf,
              aoMudar: (_) => setState(() {}),
              formatadores: [
                LengthLimitingTextInputFormatter(2),
                FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z]')),
              ],
            ),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Endereço principal'),
            value: _principal,
            onChanged: widget.endereco?.principal == true
                ? null
                : (v) => setState(() => _principal = v),
          ),
          if (_erro != null) ...[
            Text(_erro!,
                style: TipografiaTrato.corpoPequeno.copyWith(color: CoresTrato.vermelhoTexto)),
            const SizedBox(height: EspacosTrato.x3),
          ],
          BotaoPrimario(
              texto: 'Salvar', carregando: _salvando, aoTocar: _salvando ? null : _salvar),
          if (editando) ...[
            const SizedBox(height: EspacosTrato.x3),
            Center(child: BotaoLink(texto: 'Remover endereço', aoTocar: _remover)),
          ],
        ],
      ),
    );
  }
}
