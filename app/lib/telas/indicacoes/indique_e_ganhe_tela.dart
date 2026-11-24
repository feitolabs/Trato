import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../componentes/componentes.dart';
import '../../dados/erros.dart';
import '../../tema/tema.dart';
import '../comuns/convite.dart' show CompartilharTexto, compartilharNoAparelho;
import '../comuns/desconto_moedas.dart' show textoTratinhosEmReais;
import '../profissional_apoio/apoio.dart';
import 'modelos.dart';

/// Texto para o amigo: o código, sem id nem link (ainda não há link de loja).
String textoCompartilharIndicacao(String codigo) =>
    'Use meu código de indicação do Trato: $codigo. '
    'Cadastre-se e aplique o código no seu perfil para ganhar Tratinhos.';

/// "Indique e ganhe": meu código (copiar e compartilhar), o resumo, a lista de quem indiquei e o
/// campo para quem chegou com um código. Cliente e profissional usam a mesma tela. O app só pede
/// e mostra: valores, status e limites vêm do backend.
class IndiqueEGanheTela extends StatelessWidget {
  const IndiqueEGanheTela({
    super.key,
    required this.servico,
    this.valorMoedaCentavos,
    this.compartilhar = compartilharNoAparelho,
  });

  final ServicoIndicacoes servico;

  /// Valor de 1 Tratinho em centavos, só para mostrar em reais ao lado. Nulo = só Tratinhos.
  final int? valorMoedaCentavos;
  final CompartilharTexto compartilhar;

  @override
  Widget build(BuildContext context) {
    return PaginaCarregavel<MeuCodigoIndicacao>(
      titulo: 'Indique e ganhe',
      carregar: servico.meuCodigo,
      construir: (context, dados) => CorpoRolavel(
        children: [
          Text(
            'Convide amigos para o Trato. Quando eles fizerem o primeiro serviço, '
            'você ganha Tratinhos.',
            style: TipografiaTrato.corpo,
          ),
          const SizedBox(height: EspacosTrato.x4),
          _CartaoCodigo(codigo: dados.codigo, compartilhar: compartilhar),
          const SizedBox(height: EspacosTrato.x4),
          _Resumo(resumo: dados.resumo),
          const TituloSecao('Suas indicações'),
          if (dados.indicacoes.isEmpty)
            Text(
              'Você ainda não indicou ninguém. Compartilhe seu código para começar.',
              key: const ValueKey('indicacoes-vazio'),
              style: TipografiaTrato.corpo.copyWith(color: context.cores.textoSecundario),
            )
          else
            for (final i in dados.indicacoes)
              _LinhaIndicacao(indicacao: i, valorMoedaCentavos: valorMoedaCentavos),
          const TituloSecao('Tenho um código de indicação'),
          CampoCodigoIndicacao(servico: servico),
        ],
      ),
    );
  }
}

class _CartaoCodigo extends StatelessWidget {
  const _CartaoCodigo({required this.codigo, required this.compartilhar});

  final String codigo;
  final CompartilharTexto compartilhar;

  Future<void> _copiar(BuildContext context) async {
    final mensagens = ScaffoldMessenger.of(context);
    await Clipboard.setData(ClipboardData(text: codigo));
    mensagens
      ..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(content: Text('Código copiado!')));
  }

  Future<void> _compartilhar(BuildContext context) async {
    final mensagens = ScaffoldMessenger.of(context);
    final texto = textoCompartilharIndicacao(codigo);
    try {
      await compartilhar(texto);
      return;
    } on Object {
      // sem compartilhamento no aparelho: copia o texto
    }
    await Clipboard.setData(ClipboardData(text: texto));
    mensagens
      ..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(content: Text('Texto copiado! Cole no WhatsApp para convidar.')));
  }

  @override
  Widget build(BuildContext context) {
    final c = context.cores;
    return CartaoTrato(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Seu código', style: TipografiaTrato.corpoPequeno.copyWith(color: c.textoSecundario)),
          const SizedBox(height: EspacosTrato.x1),
          Semantics(
            label: 'Seu código de indicação: $codigo',
            child: SelectableText(
              codigo.isEmpty ? '—' : codigo,
              key: const ValueKey('codigo-indicacao'),
              style: TipografiaTrato.tituloGrande,
            ),
          ),
          const SizedBox(height: EspacosTrato.x3),
          Wrap(
            spacing: EspacosTrato.x2,
            runSpacing: EspacosTrato.x2,
            children: [
              BotaoSecundario(
                key: const ValueKey('copiar-codigo'),
                texto: 'Copiar código',
                icone: Icons.copy_outlined,
                aoTocar: codigo.isEmpty ? null : () => _copiar(context),
              ),
              BotaoSecundario(
                key: const ValueKey('compartilhar-codigo'),
                texto: 'Compartilhar',
                icone: Icons.share_outlined,
                aoTocar: codigo.isEmpty ? null : () => _compartilhar(context),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Resumo extends StatelessWidget {
  const _Resumo({required this.resumo});

  final ResumoIndicacoes resumo;

  @override
  Widget build(BuildContext context) {
    final c = context.cores;
    Widget numero(String rotulo, int valor, Key chave) => Expanded(
          child: Column(
            children: [
              Text('$valor', key: chave, style: TipografiaTrato.tituloGrande),
              const SizedBox(height: EspacosTrato.x1),
              Text(
                rotulo,
                textAlign: TextAlign.center,
                style: TipografiaTrato.corpoPequeno.copyWith(color: c.textoSecundario),
              ),
            ],
          ),
        );
    return CartaoTrato(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              numero('Cadastradas', resumo.cadastradas, const ValueKey('resumo-cadastradas')),
              numero(
                'Aguardando liberação',
                resumo.aguardandoLiberacao,
                const ValueKey('resumo-aguardando'),
              ),
              numero('Liberadas', resumo.liberadas, const ValueKey('resumo-liberadas')),
            ],
          ),
          if (resumo.limiteMensal > 0) ...[
            const SizedBox(height: EspacosTrato.x3),
            Text(
              'Neste mês ainda dá para ganhar com ${resumo.limiteMensalRestante} de '
              '${resumo.limiteMensal} indicações.',
              key: const ValueKey('resumo-limite'),
              style: TipografiaTrato.corpoPequeno.copyWith(color: c.textoSecundario),
            ),
          ],
        ],
      ),
    );
  }
}

class _LinhaIndicacao extends StatelessWidget {
  const _LinhaIndicacao({required this.indicacao, required this.valorMoedaCentavos});

  final Indicacao indicacao;
  final int? valorMoedaCentavos;

  @override
  Widget build(BuildContext context) {
    final c = context.cores;
    final nome = (indicacao.nomeIndicado ?? '').trim().isEmpty ? 'Amigo(a)' : indicacao.nomeIndicado!;
    final mostraBonus = indicacao.bonusTratinhos > 0 && indicacao.status != 'cancelado';
    return Padding(
      padding: const EdgeInsets.only(bottom: EspacosTrato.x3),
      child: CartaoTrato(
        key: ValueKey('indicacao-${indicacao.id}'),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(nome, style: TipografiaTrato.corpoForte),
                  const SizedBox(height: EspacosTrato.x1),
                  Text(
                    indicacao.textoStatus,
                    style: TipografiaTrato.corpoPequeno.copyWith(color: c.textoSecundario),
                  ),
                  if (mostraBonus)
                    Text(
                      '+${textoTratinhosEmReais(indicacao.bonusTratinhos, valorMoedaCentavos)}',
                      style: TipografiaTrato.corpoPequeno.copyWith(color: c.textoSecundario),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// "Tenho um código de indicação": valida o código (consulta pública), mostra "Indicado por X"
/// e aplica. Os textos de erro (404, 409, 422) vêm do backend e aparecem como estão.
class CampoCodigoIndicacao extends StatefulWidget {
  const CampoCodigoIndicacao({super.key, required this.servico, this.aoAplicado});

  final ServicoIndicacoes servico;

  /// Depois de aplicar com sucesso (ex.: recarregar o perfil).
  final VoidCallback? aoAplicado;

  @override
  State<CampoCodigoIndicacao> createState() => _CampoCodigoIndicacaoState();
}

class _CampoCodigoIndicacaoState extends State<CampoCodigoIndicacao> {
  final _controlador = TextEditingController();
  ConviteIndicacao? _convite;
  String? _erro;
  String? _sucesso;
  var _ocupado = false;
  final _foco = FocusNode();
  final _chaveBotao = GlobalKey();
  var _teclado = 0.0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final teclado = MediaQuery.viewInsetsOf(context).bottom;
    final subiu = teclado > _teclado;
    _teclado = teclado;
    if (subiu && _foco.hasFocus) _mostrarBotao();
  }

  @override
  void dispose() {
    _foco.dispose();
    _controlador.dispose();
    super.dispose();
  }

  /// Rola até o botão ficar acima do teclado (o campo vem logo acima dele). Espera dois quadros:
  /// a rolagem automática do próprio campo acontece no primeiro.
  void _mostrarBotao() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final ctx = _chaveBotao.currentContext;
        if (!mounted || ctx == null || !ctx.mounted) return;
        Scrollable.ensureVisible(
          ctx,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOut,
          alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtEnd,
        );
      });
      WidgetsBinding.instance.scheduleFrame();
    });
  }

  String get _codigo => _controlador.text.trim().toUpperCase();

  void _aoMudar(String _) {
    // Código novo: a validação anterior não vale mais.
    if (_convite != null || _erro != null) {
      setState(() {
        _convite = null;
        _erro = null;
      });
    }
  }

  Future<void> _executar(Future<void> Function() acao) async {
    if (_ocupado) return;
    setState(() {
      _ocupado = true;
      _erro = null;
    });
    try {
      await acao();
      if (mounted && _foco.hasFocus) _mostrarBotao();
    } on ErroTrato catch (e) {
      if (mounted) setState(() => _erro = e.mensagem); // texto do backend, como veio
    } on Object {
      if (mounted) setState(() => _erro = 'Não foi possível concluir agora. Tente de novo.');
    } finally {
      if (mounted) setState(() => _ocupado = false);
    }
  }

  Future<void> _validar() => _executar(() async {
        if (_codigo.isEmpty) {
          setState(() => _erro = 'Digite o código de indicação.');
          return;
        }
        final convite = await widget.servico.validar(_codigo);
        if (!mounted) return;
        setState(() {
          if (convite.valido) {
            _convite = convite;
          } else {
            _erro = 'Código de indicação não encontrado.';
          }
        });
      });

  Future<void> _aplicar() => _executar(() async {
        final resultado = await widget.servico.aplicar(_codigo);
        if (!mounted) return;
        setState(() {
          _sucesso = resultado.mensagem;
          _convite = null;
        });
        widget.aoAplicado?.call();
      });

  @override
  Widget build(BuildContext context) {
    final c = context.cores;
    if (_sucesso != null) {
      return Semantics(
        liveRegion: true,
        child: Text(
          _sucesso!,
          key: const ValueKey('codigo-aplicado'),
          style: TipografiaTrato.corpo.copyWith(color: c.verdeTexto),
        ),
      );
    }
    final convite = _convite;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          key: const ValueKey('campo-codigo-indicacao'),
          controller: _controlador,
          focusNode: _foco,
          // Com o teclado aberto, sobra espaço abaixo do campo para o botão.
          scrollPadding: EdgeInsets.fromLTRB(
              20, 20, 20, 40 + MediaQuery.textScalerOf(context).scale(110)),
          readOnly: _ocupado,
          textCapitalization: TextCapitalization.characters,
          autocorrect: false,
          maxLength: 32,
          style: TipografiaTrato.corpo,
          decoration: const InputDecoration(
            labelText: 'Código de indicação',
            hintText: 'Ex.: AMIGO123',
          ),
          onChanged: _aoMudar,
        ),
        if (convite != null) ...[
          const SizedBox(height: EspacosTrato.x2),
          Text(
            (convite.indicadorNomeCurto ?? '').trim().isEmpty
                ? 'Código válido.'
                : 'Indicado por ${convite.indicadorNomeCurto}',
            key: const ValueKey('indicado-por'),
            style: TipografiaTrato.corpoForte.copyWith(color: c.verdeTexto),
          ),
        ],
        if (_erro != null) ...[
          const SizedBox(height: EspacosTrato.x2),
          Semantics(
            liveRegion: true,
            child: Text(
              _erro!,
              key: const ValueKey('erro-codigo-indicacao'),
              style: TipografiaTrato.corpoPequeno.copyWith(color: c.vermelhoTexto),
            ),
          ),
        ],
        const SizedBox(height: EspacosTrato.x3),
        KeyedSubtree(
          key: _chaveBotao,
          child: convite == null
              ? BotaoSecundario(
                  key: const ValueKey('validar-codigo'),
                  texto: 'Validar código',
                  aoTocar: _ocupado ? null : _validar,
                )
              : BotaoPrimario(
                  key: const ValueKey('aplicar-codigo'),
                  texto: 'Aplicar código',
                  carregando: _ocupado,
                  aoTocar: _ocupado ? null : _aplicar,
                ),
        ),
      ],
    );
  }
}
