import 'package:flutter/material.dart';

import '../componentes/base.dart';
import '../dados/modelos.dart';
import '../nucleo/escopo.dart';
import '../nucleo/formato.dart';
import '../tema/tema.dart';

String _rotuloTratinhos(int qtd) => '${formatarMilhar(qtd)} ${qtd.abs() == 1 ? 'Tratinho' : 'Tratinhos'}';

String _rotuloCarteira(String carteira) => carteira == 'profissional' ? 'Profissional' : 'Cliente';

/// Seção de consulta e ações manuais de Tratinhos por usuário (Termos I.3, 12.10, 13.9 e I.10).
/// Só aparece para quem tem `Permissao.moedasConfigurar`. Quem valida e audita é o servidor.
class SecaoTratinhosUsuario extends StatefulWidget {
  const SecaoTratinhosUsuario({super.key});

  @override
  State<SecaoTratinhosUsuario> createState() => _SecaoTratinhosUsuarioState();
}

class _SecaoTratinhosUsuarioState extends State<SecaoTratinhosUsuario> {
  final _usuarioId = TextEditingController();
  bool _carregando = false;
  String? _erro;
  MoedasUsuario? _dados;

  @override
  void dispose() {
    _usuarioId.dispose();
    super.dispose();
  }

  Future<void> _consultar([String? idForcado]) async {
    final id = (idForcado ?? _usuarioId.text).trim();
    if (id.isEmpty) {
      setState(() => _erro = 'Informe o ID do usuário para consultar.');
      return;
    }
    setState(() {
      _carregando = true;
      _erro = null;
    });
    try {
      final res = await context.api.consultarMoedasUsuario(id);
      if (!mounted) return;
      setState(() {
        _dados = res;
        _carregando = false;
      });
    } on ErroApi catch (e) {
      if (!mounted) return;
      setState(() {
        _erro = e.mensagem;
        _carregando = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _erro = 'Não foi possível consultar os Tratinhos deste usuário.';
        _carregando = false;
      });
    }
  }

  Future<void> _abrirConceder() async {
    final atual = _dados;
    if (atual == null) return;
    final res = await mostrarModal<ResultadoConcederMoedas>(
      context,
      largura: 520,
      construir: (_) => _ModalConcederTratinhos(usuarioId: atual.usuarioId),
    );
    if (res == null || !mounted) return;
    mostrarAviso(
      context,
      'Concedido ${_rotuloTratinhos(res.quantidade)} na carteira ${_rotuloCarteira(res.carteira).toLowerCase()}. '
      'Saldo atual: ${_rotuloTratinhos(res.saldoAtual)}.',
    );
    await _consultar(atual.usuarioId);
  }

  Future<void> _abrirCancelarFraude() async {
    final atual = _dados;
    if (atual == null) return;
    final res = await mostrarModal<ResultadoCancelarFraudeMoedas>(
      context,
      largura: 520,
      construir: (_) => _ModalCancelarFraudeTratinhos(
        usuarioId: atual.usuarioId,
        saldoCliente: atual.saldoCliente,
        saldoProfissional: atual.saldoProfissional,
        pendentesCliente: atual.pendentesCliente.length,
        pendentesProfissional: atual.pendentesProfissional.length,
      ),
    );
    if (res == null || !mounted) return;
    mostrarAviso(
      context,
      'Cancelamento por fraude aplicado: ${_rotuloTratinhos(res.quantidadeDebitada)} debitado(s), '
      '${res.pendentesCancelados} pendente(s) cancelado(s). Saldo atual: ${_rotuloTratinhos(res.saldoAtual)}.',
    );
    await _consultar(atual.usuarioId);
  }

  @override
  Widget build(BuildContext context) {
    return CartaoSecao(
      titulo: 'Tratinhos por usuário',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Consulte saldo, pendentes e extrato de um usuário para conceder compensação (Termos I.3) '
            'ou cancelar Tratinhos por fraude (Termos 12.10, 13.9 e I.10). Quem decide e audita é o servidor.',
            style: TipografiaTrato.corpo,
          ),
          const SizedBox(height: EspacosTrato.x3),
          LayoutBuilder(
            builder: (context, c) {
              final estreito = c.maxWidth < 460;
              final campo = TextField(
                key: const ValueKey('moedas-usuario-id'),
                controller: _usuarioId,
                onSubmitted: (_) => _consultar(),
                decoration: const InputDecoration(
                  labelText: 'ID do usuário',
                  hintText: 'Ex.: usr-123 ou UUID',
                ),
              );
              final botao = BotaoTrato.primario(
                'Consultar',
                aoPressionar: _carregando ? null : () => _consultar(),
              );
              if (estreito) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [campo, const SizedBox(height: EspacosTrato.x2), botao],
                );
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: campo),
                  const SizedBox(width: EspacosTrato.x3),
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: KeyedSubtree(key: const ValueKey('moedas-usuario-consultar'), child: botao),
                  ),
                ],
              );
            },
          ),
          if (_carregando) ...[
            const SizedBox(height: EspacosTrato.x3),
            const LinearProgressIndicator(),
          ],
          if (_erro case final erro?) ...[
            const SizedBox(height: EspacosTrato.x3),
            BannerInfo(erro, tom: Tom.erro),
          ],
          if (_dados case final dados?) ...[
            const SizedBox(height: EspacosTrato.x4),
            Text('Usuário: ${dados.usuarioId}', style: TipografiaTrato.corpoForte),
            const SizedBox(height: EspacosTrato.x3),
            LayoutBuilder(
              builder: (context, c) {
                final duasColunas = c.maxWidth >= 640;
                final largura = duasColunas ? (c.maxWidth - EspacosTrato.x4) / 2 : c.maxWidth;
                return Wrap(
                  spacing: EspacosTrato.x4,
                  runSpacing: EspacosTrato.x3,
                  children: [
                    SizedBox(
                      width: largura,
                      child: _CartaoCarteiraUsuario(
                        titulo: 'Carteira cliente',
                        saldo: dados.saldoCliente,
                        pendentes: dados.pendentesCliente,
                        extrato: dados.extratoCliente,
                      ),
                    ),
                    SizedBox(
                      width: largura,
                      child: _CartaoCarteiraUsuario(
                        titulo: 'Carteira profissional',
                        saldo: dados.saldoProfissional,
                        pendentes: dados.pendentesProfissional,
                        extrato: dados.extratoProfissional,
                      ),
                    ),
                  ],
                );
              },
            ),
            const SizedBox(height: EspacosTrato.x4),
            Wrap(
              spacing: EspacosTrato.x3,
              runSpacing: EspacosTrato.x2,
              children: [
                BotaoTrato.primario(
                  'Conceder Tratinhos (compensação)',
                  aoPressionar: _abrirConceder,
                ),
                BotaoTrato.destrutivo(
                  'Cancelar por fraude',
                  aoPressionar: _abrirCancelarFraude,
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _CartaoCarteiraUsuario extends StatelessWidget {
  const _CartaoCarteiraUsuario({
    required this.titulo,
    required this.saldo,
    required this.pendentes,
    required this.extrato,
  });

  final String titulo;
  final int saldo;
  final List<PendenteMoedaUsuario> pendentes;
  final List<LancamentoMoedaUsuario> extrato;

  @override
  Widget build(BuildContext context) {
    final totalPendentes = pendentes.fold<int>(0, (soma, p) => soma + p.quantidade);
    return Container(
      padding: const EdgeInsets.all(EspacosTrato.x4),
      decoration: BoxDecoration(
        color: CoresTrato.fundoPagina,
        borderRadius: BorderRadius.circular(EspacosTrato.raioPequeno),
        border: Border.all(color: CoresTrato.borda),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(titulo, style: TipografiaTrato.corpoForte),
          const SizedBox(height: EspacosTrato.x2),
          Text('Saldo disponível: ${_rotuloTratinhos(saldo)}', style: TipografiaTrato.corpo),
          const SizedBox(height: EspacosTrato.x1),
          Text(
            pendentes.isEmpty
                ? 'Pendentes: nenhum'
                : 'Pendentes: ${pendentes.length} (${_rotuloTratinhos(totalPendentes)})',
            style: TipografiaTrato.legenda,
          ),
          if (pendentes.isNotEmpty) ...[
            const SizedBox(height: EspacosTrato.x2),
            for (final p in pendentes.take(5))
              Padding(
                padding: const EdgeInsets.only(bottom: EspacosTrato.x1),
                child: Text(
                  '• ${_rotuloTratinhos(p.quantidade)} (${p.status}) — libera em ${formatarDataBrasilia(p.liberarEm)}',
                  style: TipografiaTrato.legenda,
                ),
              ),
          ],
          if (extrato.isNotEmpty) ...[
            const SizedBox(height: EspacosTrato.x2),
            Text('Últimos lançamentos', style: TipografiaTrato.legenda),
            const SizedBox(height: EspacosTrato.x1),
            for (final l in extrato.take(5))
              Padding(
                padding: const EdgeInsets.only(bottom: EspacosTrato.x1),
                child: Text(
                  '• ${l.quantidade >= 0 ? '+' : ''}${formatarMilhar(l.quantidade)} (${l.tipo}) em ${formatarDataBrasilia(l.criadaEm)}',
                  style: TipografiaTrato.legenda,
                ),
              ),
          ],
        ],
      ),
    );
  }
}

class _ModalConcederTratinhos extends StatefulWidget {
  const _ModalConcederTratinhos({required this.usuarioId});

  final String usuarioId;

  @override
  State<_ModalConcederTratinhos> createState() => _ModalConcederTratinhosState();
}

class _ModalConcederTratinhosState extends State<_ModalConcederTratinhos> {
  String _carteira = 'cliente';
  final _quantidade = TextEditingController();
  final _validadeDias = TextEditingController();
  final _referencia = TextEditingController();
  final _motivo = TextEditingController();
  bool _confirmando = false;
  bool _enviando = false;
  String? _erro;

  @override
  void dispose() {
    for (final c in [_quantidade, _validadeDias, _referencia, _motivo]) {
      c.dispose();
    }
    super.dispose();
  }

  int? get _qtdValor {
    final n = int.tryParse(_quantidade.text.trim());
    if (n == null || n <= 0 || n > 1000000) return null;
    return n;
  }

  int? get _validadeValor {
    final t = _validadeDias.text.trim();
    if (t.isEmpty) return null;
    final n = int.tryParse(t);
    if (n == null || n <= 0 || n > 3650) return -1;
    return n;
  }

  bool get _valido =>
      _qtdValor != null &&
      _validadeValor != -1 &&
      _motivo.text.trim().length >= 10 &&
      _motivo.text.trim().length <= 500;

  Future<void> _enviar() async {
    final qtd = _qtdValor;
    final val = _validadeValor;
    if (qtd == null || val == -1) return;
    setState(() {
      _enviando = true;
      _erro = null;
    });
    try {
      final ref = _referencia.text.trim();
      final res = await context.api.concederMoedasUsuario(
        widget.usuarioId,
        carteira: _carteira,
        quantidade: qtd,
        validadeDias: val,
        motivo: _motivo.text.trim(),
        referenciaId: ref.isEmpty ? null : ref,
      );
      if (!mounted) return;
      Navigator.of(context).pop(res);
    } on ErroApi catch (e) {
      if (!mounted) return;
      setState(() {
        _erro = e.mensagem;
        _enviando = false;
        _confirmando = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _erro = 'Não foi possível conceder os Tratinhos.';
        _enviando = false;
        _confirmando = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final qtd = _qtdValor;
    final val = _validadeValor;
    final motivoLen = _motivo.text.trim().length;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Conceder Tratinhos (compensação)', style: TipografiaTrato.subtitulo),
        const SizedBox(height: EspacosTrato.x1),
        Text(
          'Usuário: ${widget.usuarioId}. Crédito manual de compensação (Termos I.3), registrado na auditoria.',
          style: TipografiaTrato.legenda,
        ),
        const SizedBox(height: EspacosTrato.x4),
        if (_erro case final erro?) ...[
          BannerInfo(erro, tom: Tom.erro),
          const SizedBox(height: EspacosTrato.x3),
        ],
        if (_confirmando && qtd != null) ...[
          BannerInfo(
            'Você vai conceder ${_rotuloTratinhos(qtd)} na carteira ${_rotuloCarteira(_carteira).toLowerCase()} '
            'do usuário ${widget.usuarioId}'
            '${val != null ? ' com validade de $val dia(s)' : ' com a validade padrão do programa'}. '
            'A ação fica registrada na auditoria.',
            titulo: 'Confirmar concessão?',
            tom: Tom.alerta,
          ),
          const SizedBox(height: EspacosTrato.x4),
          Wrap(
            alignment: WrapAlignment.end,
            spacing: EspacosTrato.x2,
            runSpacing: EspacosTrato.x2,
            children: [
              BotaoTrato.secundario('Voltar', aoPressionar: _enviando ? null : () => setState(() => _confirmando = false)),
              BotaoTrato.primario('Confirmar concessão', aoPressionar: _enviando ? null : _enviar),
            ],
          ),
        ] else ...[
          DropdownButtonFormField<String>(
            key: const ValueKey('conceder-carteira'),
            initialValue: _carteira,
            decoration: const InputDecoration(labelText: 'Carteira'),
            items: const [
              DropdownMenuItem(value: 'cliente', child: Text('Cliente')),
              DropdownMenuItem(value: 'profissional', child: Text('Profissional')),
            ],
            onChanged: (v) {
              if (v != null) setState(() => _carteira = v);
            },
          ),
          const SizedBox(height: EspacosTrato.x3),
          TextField(
            key: const ValueKey('conceder-quantidade'),
            controller: _quantidade,
            keyboardType: TextInputType.number,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              labelText: 'Quantidade de Tratinhos',
              errorText: _quantidade.text.trim().isNotEmpty && qtd == null
                  ? 'Informe um número inteiro entre 1 e 1.000.000.'
                  : null,
            ),
          ),
          const SizedBox(height: EspacosTrato.x3),
          TextField(
            key: const ValueKey('conceder-validade'),
            controller: _validadeDias,
            keyboardType: TextInputType.number,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              labelText: 'Validade em dias (opcional)',
              helperText: 'Em branco usa a validade padrão do programa.',
              errorText: val == -1 ? 'Informe um número inteiro entre 1 e 3650.' : null,
            ),
          ),
          const SizedBox(height: EspacosTrato.x3),
          TextField(
            key: const ValueKey('conceder-referencia'),
            controller: _referencia,
            maxLength: 120,
            decoration: const InputDecoration(
              labelText: 'Referência (opcional)',
              helperText: 'Ex.: ID do pedido ou chamado relacionado.',
              counterText: '',
            ),
          ),
          const SizedBox(height: EspacosTrato.x3),
          TextField(
            key: const ValueKey('conceder-motivo'),
            controller: _motivo,
            maxLines: 3,
            maxLength: 500,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              labelText: 'Motivo (obrigatório)',
              helperText: 'Mínimo de 10 caracteres. Fica registrado na auditoria.',
              errorText: _motivo.text.isNotEmpty && motivoLen < 10 ? 'Escreva pelo menos 10 caracteres.' : null,
            ),
          ),
          const SizedBox(height: EspacosTrato.x4),
          Wrap(
            alignment: WrapAlignment.end,
            spacing: EspacosTrato.x2,
            runSpacing: EspacosTrato.x2,
            children: [
              BotaoTrato.secundario('Cancelar', aoPressionar: () => Navigator.of(context).pop()),
              BotaoTrato.primario(
                'Revisar concessão',
                aoPressionar: _valido ? () => setState(() => _confirmando = true) : null,
              ),
            ],
          ),
        ],
      ],
    );
  }
}

class _ModalCancelarFraudeTratinhos extends StatefulWidget {
  const _ModalCancelarFraudeTratinhos({
    required this.usuarioId,
    required this.saldoCliente,
    required this.saldoProfissional,
    required this.pendentesCliente,
    required this.pendentesProfissional,
  });

  final String usuarioId;
  final int saldoCliente;
  final int saldoProfissional;
  final int pendentesCliente;
  final int pendentesProfissional;

  @override
  State<_ModalCancelarFraudeTratinhos> createState() => _ModalCancelarFraudeTratinhosState();
}

class _ModalCancelarFraudeTratinhosState extends State<_ModalCancelarFraudeTratinhos> {
  String _carteira = 'cliente';
  final _quantidade = TextEditingController(text: '0');
  bool _cancelarPendentes = false;
  final _referencia = TextEditingController();
  final _motivo = TextEditingController();
  bool _confirmando = false;
  bool _enviando = false;
  String? _erro;

  @override
  void dispose() {
    for (final c in [_quantidade, _referencia, _motivo]) {
      c.dispose();
    }
    super.dispose();
  }

  int? get _qtdValor {
    final t = _quantidade.text.trim();
    if (t.isEmpty) return 0;
    final n = int.tryParse(t);
    if (n == null || n < 0 || n > 1000000) return null;
    return n;
  }

  bool get _temAcao => (_qtdValor ?? 0) > 0 || _cancelarPendentes;

  bool get _valido =>
      _qtdValor != null &&
      _temAcao &&
      _motivo.text.trim().length >= 10 &&
      _motivo.text.trim().length <= 500;

  int get _saldoCarteira => _carteira == 'profissional' ? widget.saldoProfissional : widget.saldoCliente;
  int get _pendentesCarteira => _carteira == 'profissional' ? widget.pendentesProfissional : widget.pendentesCliente;

  Future<void> _enviar() async {
    final qtd = _qtdValor;
    if (qtd == null || !_temAcao) return;
    setState(() {
      _enviando = true;
      _erro = null;
    });
    try {
      final ref = _referencia.text.trim();
      final res = await context.api.cancelarFraudeMoedasUsuario(
        widget.usuarioId,
        carteira: _carteira,
        quantidade: qtd,
        cancelarPendentes: _cancelarPendentes,
        motivo: _motivo.text.trim(),
        referenciaId: ref.isEmpty ? null : ref,
      );
      if (!mounted) return;
      Navigator.of(context).pop(res);
    } on ErroApi catch (e) {
      if (!mounted) return;
      setState(() {
        _erro = e.mensagem;
        _enviando = false;
        _confirmando = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _erro = 'Não foi possível cancelar os Tratinhos por fraude.';
        _enviando = false;
        _confirmando = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final qtd = _qtdValor;
    final motivoLen = _motivo.text.trim().length;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Cancelar Tratinhos por fraude', style: TipografiaTrato.subtitulo),
        const SizedBox(height: EspacosTrato.x1),
        Text(
          'Usuário: ${widget.usuarioId}. Cancelamento por fraude (Termos 12.10, 13.9 e I.10). '
          'O servidor valida o saldo e registra auditoria.',
          style: TipografiaTrato.legenda,
        ),
        const SizedBox(height: EspacosTrato.x4),
        if (_erro case final erro?) ...[
          BannerInfo(erro, tom: Tom.erro),
          const SizedBox(height: EspacosTrato.x3),
        ],
        if (_confirmando && qtd != null) ...[
          BannerInfo(
            'Na carteira ${_rotuloCarteira(_carteira).toLowerCase()} de ${widget.usuarioId}: '
            '${qtd > 0 ? 'debitar ${_rotuloTratinhos(qtd)}' : 'sem débito do saldo disponível'}'
            '${_cancelarPendentes ? ' e cancelar os bônus pendentes' : ''}. '
            'A ação fica registrada na auditoria.',
            titulo: 'Confirmar cancelamento por fraude?',
            tom: Tom.erro,
          ),
          const SizedBox(height: EspacosTrato.x4),
          Wrap(
            alignment: WrapAlignment.end,
            spacing: EspacosTrato.x2,
            runSpacing: EspacosTrato.x2,
            children: [
              BotaoTrato.secundario('Voltar', aoPressionar: _enviando ? null : () => setState(() => _confirmando = false)),
              BotaoTrato.destrutivo('Confirmar cancelamento', aoPressionar: _enviando ? null : _enviar),
            ],
          ),
        ] else ...[
          DropdownButtonFormField<String>(
            key: const ValueKey('fraude-carteira'),
            initialValue: _carteira,
            decoration: const InputDecoration(labelText: 'Carteira'),
            items: const [
              DropdownMenuItem(value: 'cliente', child: Text('Cliente')),
              DropdownMenuItem(value: 'profissional', child: Text('Profissional')),
            ],
            onChanged: (v) {
              if (v != null) setState(() => _carteira = v);
            },
          ),
          const SizedBox(height: EspacosTrato.x1),
          Text(
            'Saldo atual nessa carteira: ${_rotuloTratinhos(_saldoCarteira)} · Pendentes: $_pendentesCarteira',
            style: TipografiaTrato.legenda,
          ),
          const SizedBox(height: EspacosTrato.x3),
          TextField(
            key: const ValueKey('fraude-quantidade'),
            controller: _quantidade,
            keyboardType: TextInputType.number,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              labelText: 'Quantidade a debitar',
              helperText: 'Use 0 para cancelar apenas os pendentes.',
              errorText: qtd == null ? 'Informe um número inteiro entre 0 e 1.000.000.' : null,
            ),
          ),
          const SizedBox(height: EspacosTrato.x2),
          CheckboxListTile(
            key: const ValueKey('fraude-cancelar-pendentes'),
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            value: _cancelarPendentes,
            onChanged: (v) => setState(() => _cancelarPendentes = v ?? false),
            title: Text('Cancelar pendentes desta carteira', style: TipografiaTrato.corpo),
          ),
          if (!_temAcao) ...[
            Text(
              'Informe quantidade maior que zero ou marque cancelar pendentes.',
              style: TipografiaTrato.legenda.copyWith(color: CoresTrato.perigoTexto),
            ),
            const SizedBox(height: EspacosTrato.x2),
          ],
          const SizedBox(height: EspacosTrato.x2),
          TextField(
            key: const ValueKey('fraude-referencia'),
            controller: _referencia,
            maxLength: 120,
            decoration: const InputDecoration(
              labelText: 'Referência (opcional)',
              helperText: 'Ex.: ID do pedido, alerta ou ocorrência.',
              counterText: '',
            ),
          ),
          const SizedBox(height: EspacosTrato.x3),
          TextField(
            key: const ValueKey('fraude-motivo'),
            controller: _motivo,
            maxLines: 3,
            maxLength: 500,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              labelText: 'Motivo (obrigatório)',
              helperText: 'Mínimo de 10 caracteres. Fica registrado na auditoria.',
              errorText: _motivo.text.isNotEmpty && motivoLen < 10 ? 'Escreva pelo menos 10 caracteres.' : null,
            ),
          ),
          const SizedBox(height: EspacosTrato.x4),
          Wrap(
            alignment: WrapAlignment.end,
            spacing: EspacosTrato.x2,
            runSpacing: EspacosTrato.x2,
            children: [
              BotaoTrato.secundario('Cancelar', aoPressionar: () => Navigator.of(context).pop()),
              BotaoTrato.destrutivo(
                'Revisar cancelamento',
                aoPressionar: _valido ? () => setState(() => _confirmando = true) : null,
              ),
            ],
          ),
        ],
      ],
    );
  }
}
