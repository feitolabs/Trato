import 'dart:math';

import 'package:flutter/material.dart';

import '../componentes/base.dart';
import '../dados/modelos.dart';
import '../nucleo/escopo.dart';
import '../nucleo/papeis.dart';
import '../tema/tema.dart';

const kAvisoMotivoDoSelo = 'O profissional lê este motivo e não dá para apagar nem mudar. Não escreva dado pessoal '
    'nem de saúde (CPF, contato, link, endereço).';

const kOrientacaoSeloRetirado = 'Nada foi aprovado. Regularize o selo antes, em Busca e suporte, no usuário, em '
    '"Selo de verificação" (Cadastro ou Administrador). Depois volte aqui e decida de novo.';

const kMotivoTravado = 'O envio anterior ficou sem resposta e pode ter sido gravado. Repita com o mesmo motivo: ele '
    'fica travado porque um texto novo seria ignorado sem aviso. Se precisar mudar o texto, confira antes na '
    'auditoria se a ação foi gravada.';

const kSeloSemConsulta = 'O painel não consulta o estado do selo: o servidor confere cada ação e recusa a que não '
    'couber (Termos 10.3).';

const _kMotivoMaximo = 1000;

enum AcaoSelo {
  retirar('Retirar selo', 'Selo retirado.',
      'O selo sai até a regularização e, até lá, o profissional não envia orçamentos novos.'),
  reconferencia('Pedir reconferência', 'Reconferência pedida.',
      'Pede uma nova conferência da identidade. Não muda o nível de verificação.'),
  regularizar('Regularizar selo', 'Selo regularizado.', 'Devolve o nível que o profissional tinha antes da retirada.');

  const AcaoSelo(this.rotulo, this.feito, this.efeito);
  final String rotulo;
  final String feito;
  final String efeito;

  Permissao get permissao => this == regularizar ? Permissao.seloRegularizar : Permissao.seloRetirar;
}

/// Uma chave por ação; a mesma chave vai em toda repetição do envio (8 a 100 caracteres).
String gerarChaveDoSelo([Random? sorteio]) {
  final r = sorteio ?? Random.secure();
  return 'selo-${List.generate(16, (_) => r.nextInt(256).toRadixString(16).padLeft(2, '0')).join()}';
}

/// Envio sem resposta definitiva: a chave e o motivo ficam para a repetição.
class _Tentativa {
  String chave = gerarChaveDoSelo();
  String motivo = '';

  /// Enviado sem resposta definitiva: o servidor pode ter gravado, então o motivo não muda
  /// enquanto a chave for esta.
  bool semResposta = false;
}

/// Ações sobre o selo do profissional (Termos 10.3). O painel pede; o backend decide.
class CartaoSelo extends StatefulWidget {
  const CartaoSelo({super.key, required this.usuarioId, required this.nome, this.nivel});
  final String usuarioId;
  final String nome;

  /// `nivel_verificacao` do usuário, como o servidor mandou. Null = não informado.
  final String? nivel;

  @override
  State<CartaoSelo> createState() => _CartaoSeloState();
}

class _CartaoSeloState extends State<CartaoSelo> {
  final _tentativas = <AcaoSelo, _Tentativa>{};
  ResultadoSeloAdmin? _ultimo;

  Future<void> _abrir(AcaoSelo acao) async {
    final tentativa = _tentativas.putIfAbsent(acao, _Tentativa.new);
    final r = await mostrarModal<ResultadoSeloAdmin>(
      context,
      construir: (_) => _ModalSelo(
        usuarioId: widget.usuarioId,
        nome: widget.nome,
        acao: acao,
        tentativa: tentativa,
        // Gravada: a próxima ação ganha chave e motivo novos.
        aoGravar: () => _tentativas.remove(acao),
      ),
    );
    if (r != null && mounted) setState(() => _ultimo = r);
  }

  @override
  Widget build(BuildContext context) {
    final acoes = [for (final a in AcaoSelo.values) if (context.pode(a.permissao)) a];
    if (acoes.isEmpty) return const SizedBox.shrink();
    final nivel = _ultimo?.nivelVerificacao ?? widget.nivel;
    return CartaoSecao(
      titulo: 'Selo de verificação',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Linha('Nível de verificação', nivel == null || nivel.isEmpty ? 'Não informado' : nivel),
          if (_ultimo case final u?) Linha('Retirada em aberto', u.retiradaAberta ? 'Sim' : 'Não'),
          const SizedBox(height: EspacosTrato.x2),
          Text(kSeloSemConsulta, style: TipografiaTrato.legenda),
          const SizedBox(height: EspacosTrato.x3),
          Wrap(
            spacing: EspacosTrato.x2,
            runSpacing: EspacosTrato.x2,
            children: [for (final a in acoes) BotaoTrato.secundario(a.rotulo, aoPressionar: () => _abrir(a))],
          ),
        ],
      ),
    );
  }
}

class _ModalSelo extends StatefulWidget {
  const _ModalSelo(
      {required this.usuarioId, required this.nome, required this.acao, required this.tentativa, required this.aoGravar});
  final String usuarioId;
  final String nome;
  final AcaoSelo acao;
  final _Tentativa tentativa;
  final VoidCallback aoGravar;

  @override
  State<_ModalSelo> createState() => _ModalSeloState();
}

class _ModalSeloState extends State<_ModalSelo> {
  late final _motivo = TextEditingController(text: widget.tentativa.motivo);
  bool _revisando = false;
  bool _enviando = false;
  String? _erro;

  @override
  void dispose() {
    _motivo.dispose();
    super.dispose();
  }

  Future<void> _enviar() async {
    if (_enviando) return;
    setState(() {
      _enviando = true;
      _erro = null;
    });
    final tentativa = widget.tentativa;
    final motivo = tentativa.motivo = _motivo.text.trim();
    try {
      final r = await context.api
          .mudarSelo(widget.usuarioId, widget.acao.name, motivo: motivo, chaveIdempotencia: tentativa.chave);
      widget.aoGravar();
      if (!mounted) return;
      mostrarAviso(context, r.jaExistia ? 'Essa ação já estava registrada. Nada novo foi criado.' : widget.acao.feito);
      Navigator.of(context).pop(r);
    } catch (e) {
      // 409 e 422 provam que nada ficou gravado com esta chave. 403 e 404 podem ser barrados antes
      // de o servidor olhar a chave: só liberam se não houve envio sem resposta antes. No resto
      // (sem resposta, 5xx), a chave e o motivo ficam.
      final status = e is ErroApi ? e.status : null;
      if (status == 409 || status == 422 || (!tentativa.semResposta && (status == 403 || status == 404))) {
        tentativa
          ..chave = gerarChaveDoSelo()
          ..semResposta = false;
      } else {
        tentativa.semResposta = true;
      }
      if (mounted) {
        setState(() {
          _erro = e.toString();
          _enviando = false;
          _revisando = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final valido = _motivo.text.trim().length >= kMotivoMinimo;
    return PopScope(
      canPop: !_enviando,
      child: CorpoModal(
        titulo: _revisando ? 'Confirmar: ${widget.acao.rotulo.toLowerCase()}?' : widget.acao.rotulo,
        consequencia: widget.acao.efeito,
        filhos: [
          if (_erro != null) ...[
            BannerInfo(_erro!, titulo: 'Não foi confirmado.', tom: Tom.erro),
            const SizedBox(height: EspacosTrato.x3),
          ],
          Linha('Profissional', widget.nome),
          const SizedBox(height: EspacosTrato.x2),
          const BannerInfo(kAvisoMotivoDoSelo, tom: Tom.alerta),
          const SizedBox(height: EspacosTrato.x3),
          if (widget.tentativa.semResposta) ...[
            const BannerInfo(kMotivoTravado, titulo: 'Motivo travado.', tom: Tom.info),
            const SizedBox(height: EspacosTrato.x3),
          ],
          if (_revisando)
            Linha('Motivo', _motivo.text.trim())
          else
            TextField(
              controller: _motivo,
              readOnly: widget.tentativa.semResposta,
              minLines: 2,
              maxLines: 5,
              maxLength: _kMotivoMaximo,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(labelText: 'Motivo', helperText: 'Pelo menos $kMotivoMinimo caracteres'),
            ),
          const SizedBox(height: EspacosTrato.x2),
          const AvisoAuditoria(),
        ],
        acoes: [
          BotaoTrato.secundario(
            _revisando ? 'Voltar' : 'Cancelar',
            aoPressionar: _enviando
                ? null
                : () => _revisando ? setState(() => _revisando = false) : Navigator.of(context).pop(),
          ),
          _revisando
              ? BotaoTrato.primario(
                  'Confirmar',
                  carregando: _enviando,
                  rotuloCarregando: 'Enviando',
                  aoPressionar: _enviando ? null : _enviar,
                )
              : BotaoTrato.primario(
                  'Revisar',
                  aoPressionar: valido
                      ? () => setState(() {
                            _erro = null;
                            _revisando = true;
                          })
                      : null,
                ),
        ],
      ),
    );
  }
}
