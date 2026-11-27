import 'package:flutter/material.dart';

import '../componentes/base.dart';
import '../dados/modelos.dart';
import '../nucleo/escopo.dart';
import '../nucleo/formato.dart';
import '../tema/tema.dart';
import 'atendimento_tela.dart';

Future<bool> confirmarAtendimento(BuildContext context,
    {required String titulo, required String texto, required String verbo}) async {
  final r = await mostrarModal<bool>(
    context,
    construir: (ctx) => CorpoModal(
      titulo: titulo,
      consequencia: texto,
      acoes: [
        BotaoTrato.secundario('Cancelar', aoPressionar: () => Navigator.of(ctx).pop(false)),
        BotaoTrato.primario(verbo, aoPressionar: () => Navigator.of(ctx).pop(true)),
      ],
    ),
  );
  return r ?? false;
}

/// Novo prazo (25.4): o usuário lê o motivo. Devolve true se o backend aceitou.
Future<bool> abrirNovoPrazo(BuildContext context, Chamado chamado) async =>
    await mostrarModal<bool>(context, construir: (_) => _ModalPrazo(chamado)) ?? false;

Future<bool> abrirEncerramento(BuildContext context, Chamado chamado) async =>
    await mostrarModal<bool>(context, construir: (_) => _ModalEncerrar(chamado)) ?? false;

/// Contato por telefone, e-mail ou WhatsApp. Depois de registrar mostra o protocolo.
Future<bool> abrirRegistroDeContato(BuildContext context) async =>
    await mostrarModal<bool>(context, largura: 560, construir: (_) => const _ModalContato()) ?? false;

/// Envio dos modais: trava o segundo clique e deixa o erro dentro do modal, com o texto mantido.
mixin _Envio<T extends StatefulWidget> on State<T> {
  bool enviando = false;
  String? erro;

  Future<void> enviar(Future<void> Function() chamada) async {
    if (enviando) return;
    setState(() {
      enviando = true;
      erro = null;
    });
    try {
      await chamada();
    } catch (e) {
      if (mounted) setState(() => erro = e.toString());
    } finally {
      if (mounted) setState(() => enviando = false);
    }
  }

  List<Widget> avisoDeErro() => [
        if (erro != null) ...[
          BannerInfo(erro!, titulo: 'Não foi feito.', tom: Tom.erro),
          const SizedBox(height: EspacosTrato.x3),
        ],
      ];
}

class _ModalPrazo extends StatefulWidget {
  const _ModalPrazo(this.chamado);
  final Chamado chamado;

  @override
  State<_ModalPrazo> createState() => _ModalPrazoState();
}

class _ModalPrazoState extends State<_ModalPrazo> with _Envio {
  final _motivo = TextEditingController();
  DateTime? _dia;

  @override
  void dispose() {
    _motivo.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dia = _dia;
    final valido = dia != null && _motivo.text.trim().length >= kMotivoMinimo;
    return CorpoModal(
      titulo: 'Estender o prazo de resposta?',
      consequencia: 'Prazo atual: ${formatarData(widget.chamado.prazo)}. O usuário é avisado e lê o motivo.',
      filhos: [
        ...avisoDeErro(),
        CampoData(
          rotulo: 'Novo prazo (até o fim do dia)',
          valor: dia,
          aoMudar: (v) => setState(() => _dia = v),
        ),
        const SizedBox(height: EspacosTrato.x3),
        CampoMotivo(controle: _motivo, aoMudar: () => setState(() {}), rotulo: 'Motivo (o usuário lê)'),
        const SizedBox(height: EspacosTrato.x3),
        const AvisoAuditoria(),
      ],
      acoes: [
        BotaoTrato.secundario('Cancelar', aoPressionar: () => Navigator.of(context).pop(false)),
        BotaoTrato.primario(
          'Informar novo prazo',
          carregando: enviando,
          rotuloCarregando: 'Enviando',
          aoPressionar: !valido || enviando
              ? null
              : () => enviar(() async {
                    await context.api.estenderPrazoChamado(
                      widget.chamado.id,
                      ate: DateTime(dia.year, dia.month, dia.day, 23, 59),
                      motivo: _motivo.text.trim(),
                    );
                    if (!context.mounted) return;
                    mostrarAviso(context, 'Novo prazo informado.');
                    Navigator.of(context).pop(true);
                  }),
        ),
      ],
    );
  }
}

class _ModalEncerrar extends StatefulWidget {
  const _ModalEncerrar(this.chamado);
  final Chamado chamado;

  @override
  State<_ModalEncerrar> createState() => _ModalEncerrarState();
}

class _ModalEncerrarState extends State<_ModalEncerrar> with _Envio {
  final _mensagem = TextEditingController();

  @override
  void dispose() {
    _mensagem.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final valido = _mensagem.text.trim().length >= kMotivoMinimo;
    return CorpoModal(
      titulo: 'Encerrar o chamado ${widget.chamado.protocolo}?',
      consequencia: 'A mensagem é a resposta final ao usuário. Encerrado não recebe novas mensagens.',
      filhos: [
        ...avisoDeErro(),
        CampoMotivo(controle: _mensagem, aoMudar: () => setState(() {}), rotulo: 'Resposta final ao usuário'),
        if (widget.chamado.usuarioId == null) ...[
          const SizedBox(height: EspacosTrato.x2),
          const BannerInfo('Contato sem conta: envie a resposta também pelo canal de contato.', tom: Tom.alerta),
        ],
        const SizedBox(height: EspacosTrato.x3),
        const AvisoAuditoria(),
      ],
      acoes: [
        BotaoTrato.secundario('Cancelar', aoPressionar: () => Navigator.of(context).pop(false)),
        BotaoTrato.destrutivo(
          'Encerrar chamado',
          carregando: enviando,
          rotuloCarregando: 'Encerrando',
          aoPressionar: !valido || enviando
              ? null
              : () => enviar(() async {
                    await context.api.encerrarChamado(widget.chamado.id, mensagem: _mensagem.text.trim());
                    if (!context.mounted) return;
                    mostrarAviso(context, 'Chamado encerrado.');
                    Navigator.of(context).pop(true);
                  }),
        ),
      ],
    );
  }
}

class _ModalContato extends StatefulWidget {
  const _ModalContato();

  @override
  State<_ModalContato> createState() => _ModalContatoState();
}

class _ModalContatoState extends State<_ModalContato> with _Envio {
  String _canal = 'telefone';
  String _categoria = 'duvida';
  String _prioridade = 'normal';
  final _nome = TextEditingController();
  final _contato = TextEditingController();
  final _usuario = TextEditingController();
  final _pedido = TextEditingController();
  final _assunto = TextEditingController();
  final _texto = TextEditingController();
  Chamado? _criado;

  @override
  void dispose() {
    for (final c in [_nome, _contato, _usuario, _pedido, _assunto, _texto]) {
      c.dispose();
    }
    super.dispose();
  }

  String? _opcional(TextEditingController c) => c.text.trim().isEmpty ? null : c.text.trim();

  bool get _valido =>
      _assunto.text.trim().length >= 3 &&
      _texto.text.trim().isNotEmpty &&
      (_contato.text.trim().isNotEmpty || _usuario.text.trim().isNotEmpty);

  Widget _campo(String rotulo, TextEditingController c, int maximo, {int linhas = 1, String? ajuda}) => Padding(
        padding: const EdgeInsets.only(top: EspacosTrato.x3),
        child: TextField(
          controller: c,
          minLines: linhas,
          maxLines: linhas == 1 ? 1 : linhas + 3,
          maxLength: maximo,
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(labelText: rotulo, helperText: ajuda, helperMaxLines: 2, counterText: ''),
        ),
      );

  Widget _escolha(String rotulo, String valor, Map<String, String> opcoes, ValueChanged<String> aoMudar) => Padding(
        padding: const EdgeInsets.only(top: EspacosTrato.x3),
        child: DropdownButtonFormField<String>(
          initialValue: valor,
          isExpanded: true,
          decoration: InputDecoration(labelText: rotulo),
          items: [for (final e in opcoes.entries) DropdownMenuItem(value: e.key, child: Text(e.value))],
          onChanged: (v) => setState(() => aoMudar(v ?? valor)),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final criado = _criado;
    if (criado != null) {
      return CorpoModal(
        titulo: 'Contato registrado',
        consequencia: criado.usuarioId == null
            ? 'Informe o protocolo à pessoa agora: sem conta, o sistema não envia a confirmação por aqui.'
            : 'Informe o protocolo à pessoa agora, por escrito.',
        filhos: [
          SelectableText(criado.protocolo, style: TipografiaTrato.titulo),
          const SizedBox(height: EspacosTrato.x2),
          Linha('Responder até', formatarData(criado.prazo)),
        ],
        acoes: [BotaoTrato.primario('Concluir', aoPressionar: () => Navigator.of(context).pop(true))],
      );
    }
    return PopScope(
      canPop: !enviando,
      child: CorpoModal(
        titulo: 'Registrar contato',
        consequencia: 'Abre um chamado com protocolo para um contato recebido fora do aplicativo.',
        filhos: [
          ...avisoDeErro(),
          _escolha('Canal', _canal, {
            for (final e in kCanaisChamado.entries)
              if (e.key != 'app') e.key: e.value,
          }, (v) => _canal = v),
          _escolha('Categoria', _categoria, kCategoriasChamado, (v) => _categoria = v),
          _escolha('Prioridade', _prioridade, kPrioridadesChamado, (v) => _prioridade = v),
          _campo('Nome de quem entrou em contato', _nome, 200),
          _campo('Telefone ou e-mail', _contato, 320, ajuda: 'Obrigatório se não informar a conta.'),
          _campo('Código da conta (opcional)', _usuario, 64),
          _campo('Código do pedido (opcional)', _pedido, 64),
          _campo('Assunto', _assunto, 200),
          _campo('O que a pessoa disse', _texto, 4000, linhas: 3),
          const SizedBox(height: EspacosTrato.x3),
          const AvisoAuditoria(texto: 'O registro fica na auditoria com seu nome.'),
        ],
        acoes: [
          BotaoTrato.secundario('Cancelar', aoPressionar: enviando ? null : () => Navigator.of(context).pop(false)),
          BotaoTrato.primario(
            'Registrar e gerar protocolo',
            carregando: enviando,
            rotuloCarregando: 'Registrando',
            aoPressionar: !_valido || enviando
                ? null
                : () => enviar(() async {
                      final r = await context.api.registrarContato(NovoContato(
                        canal: _canal,
                        categoria: _categoria,
                        prioridade: _prioridade,
                        assunto: _assunto.text.trim(),
                        texto: _texto.text.trim(),
                        nomeContato: _opcional(_nome),
                        contato: _opcional(_contato),
                        usuarioId: _opcional(_usuario),
                        pedidoId: _opcional(_pedido),
                      ));
                      if (mounted) setState(() => _criado = r);
                    }),
          ),
        ],
      ),
    );
  }
}
