import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../componentes/componentes.dart';
import '../../tema/tema.dart';
import '../comuns/estados.dart';
import 'dados_pessoais_tela.dart' show textoDoErro;
import 'modelos.dart';

/// Endereços salvos: lista, adicionar, editar, remover e escolher o principal.
class EnderecosTela extends StatefulWidget {
  const EnderecosTela({super.key, required this.servico});

  final ServicoConta servico;

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
      MaterialPageRoute(builder: (_) => _FormEnderecoTela(servico: widget.servico, endereco: e)),
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
        construir: (context, itens, _) => ListView(
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
        ),
      ),
    );
  }
}

class _FormEnderecoTela extends StatefulWidget {
  const _FormEnderecoTela({required this.servico, this.endereco});

  final ServicoConta servico;
  final EnderecoSalvo? endereco;

  @override
  State<_FormEnderecoTela> createState() => _FormEnderecoTelaState();
}

class _FormEnderecoTelaState extends State<_FormEnderecoTela> {
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
  var _salvando = false;
  String? _erro;

  @override
  void dispose() {
    for (final c in [_apelido, _cep, _logradouro, _numero, _complemento, _bairro, _cidade, _uf]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _salvar() async {
    final cep = _cep.text.replaceAll(RegExp(r'\D'), '');
    if (_apelido.text.trim().isEmpty ||
        _logradouro.text.trim().length < 2 ||
        _numero.text.trim().isEmpty ||
        _bairro.text.trim().length < 2 ||
        _cidade.text.trim().length < 2 ||
        _uf.text.trim().length != 2) {
      setState(() => _erro = 'Preencha apelido, rua, número, bairro, cidade e UF.');
      return;
    }
    if (cep.length != 8) {
      setState(() => _erro = 'O CEP tem 8 dígitos.');
      return;
    }
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

  @override
  Widget build(BuildContext context) {
    final editando = widget.endereco != null;
    return MolduraTelaComum(
      titulo: editando ? 'Editar endereço' : 'Novo endereço',
      child: ListView(
        padding: const EdgeInsets.only(bottom: EspacosTrato.x6),
        children: [
          CampoTrato(rotulo: 'Apelido', controlador: _apelido, dica: 'Casa, Trabalho...'),
          const SizedBox(height: EspacosTrato.x3),
          CampoTrato(
            rotulo: 'CEP',
            controlador: _cep,
            teclado: TextInputType.number,
            formatadores: [FilteringTextInputFormatter.allow(RegExp(r'[0-9\-]'))],
          ),
          const SizedBox(height: EspacosTrato.x3),
          CampoTrato(rotulo: 'Rua', controlador: _logradouro),
          const SizedBox(height: EspacosTrato.x3),
          CampoTrato(rotulo: 'Número', controlador: _numero),
          const SizedBox(height: EspacosTrato.x3),
          CampoTrato(rotulo: 'Complemento (opcional)', controlador: _complemento),
          const SizedBox(height: EspacosTrato.x3),
          CampoTrato(rotulo: 'Bairro', controlador: _bairro),
          const SizedBox(height: EspacosTrato.x3),
          CampoTrato(rotulo: 'Cidade', controlador: _cidade),
          const SizedBox(height: EspacosTrato.x3),
          CampoTrato(
            rotulo: 'UF',
            controlador: _uf,
            formatadores: [
              LengthLimitingTextInputFormatter(2),
              FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z]')),
            ],
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
