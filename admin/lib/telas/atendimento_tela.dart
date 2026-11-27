import 'package:flutter/material.dart';

import '../componentes/base.dart';
import '../dados/modelos.dart';
import '../nucleo/escopo.dart';
import '../nucleo/formato.dart';
import '../nucleo/navegacao.dart';
import '../nucleo/papeis.dart';
import '../tema/tema.dart';
import 'atendimento_modais.dart';
import 'contestacao_disputa_registro.dart';

const kStatusChamado = {
  'aberto': 'Aberto',
  'em_atendimento': 'Em atendimento',
  'aguardando_usuario': 'Aguardando usuário',
  'respondido': 'Respondido',
  'encerrado': 'Encerrado',
};

const kCategoriasChamado = {
  'duvida': 'Dúvida',
  'reclamacao': 'Reclamação',
  'contestacao': 'Contestação',
  'dados_pessoais': 'Dados pessoais',
  'seguranca': 'Segurança',
  'outro': 'Outro',
};

const kPrioridadesChamado = {'baixa': 'Baixa', 'normal': 'Normal', 'alta': 'Alta', 'urgente': 'Urgente'};

const kCanaisChamado = {
  'app': 'Aplicativo',
  'telefone': 'Telefone',
  'email': 'E-mail',
  'whatsapp': 'WhatsApp',
  'painel': 'Painel',
};

String _rotulo(Map<String, String> mapa, String codigo) => mapa[codigo] ?? codigo;

(String, Tom) chipStatusChamado(String s) => (
      _rotulo(kStatusChamado, s),
      switch (s) {
        'encerrado' || 'respondido' => Tom.ok,
        'aguardando_usuario' => Tom.neutro,
        'em_atendimento' => Tom.info,
        _ => Tom.alerta,
      },
    );

/// Atendimento (Termos 25.3 e 25.4). Prazos e atraso vêm do backend; a ordem da fila também.
class AtendimentoTela extends StatefulWidget {
  const AtendimentoTela({super.key});

  @override
  State<AtendimentoTela> createState() => _AtendimentoTelaState();
}

class _AtendimentoTelaState extends State<AtendimentoTela> {
  String? _status;
  String? _categoria;
  String? _prioridade;
  bool _atrasados = false;
  bool _meus = false;
  String _protocolo = '';
  int _versao = 0;

  Future<void> _registrar() async {
    final criado = await abrirRegistroDeContato(context);
    if (criado && mounted) setState(() => _versao++);
  }

  Widget _filtro(String rotulo, String? valor, Map<String, String> opcoes, ValueChanged<String?> aoMudar) => SizedBox(
        width: 180,
        child: DropdownButtonFormField<String?>(
          key: ValueKey('chamado-$rotulo'),
          initialValue: valor,
          isExpanded: true,
          decoration: InputDecoration(labelText: rotulo),
          items: [
            const DropdownMenuItem(value: null, child: Text('Todos')),
            for (final e in opcoes.entries) DropdownMenuItem(value: e.key, child: Text(e.value)),
          ],
          onChanged: (v) => setState(() => aoMudar(v)),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final filtro = FiltroChamados(
      status: _status,
      categoria: _categoria,
      prioridade: _prioridade,
      responsavelId: _meus ? context.eu?.id : null,
      protocolo: _protocolo.isEmpty ? null : _protocolo,
      atrasados: _atrasados,
    );
    // Guardada aqui: no celular o detalhe abre numa rota que não enxerga o menu.
    final irPara = NavegacaoPainel.de(context);
    final margem = Responsivo.margemLateral(FaixaPainel.de(context));
    final filtros = Padding(
      padding: EdgeInsets.fromLTRB(margem, 0, margem, EspacosTrato.x2),
      child: Wrap(
        spacing: EspacosTrato.x2,
        runSpacing: EspacosTrato.x2,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          SizedBox(
            width: 220,
            child: TextField(
              decoration: const InputDecoration(labelText: 'Protocolo', helperText: 'Enter para buscar'),
              onSubmitted: (v) => setState(() => _protocolo = v.trim()),
            ),
          ),
          _filtro('Situação', _status, kStatusChamado, (v) => _status = v),
          _filtro('Categoria', _categoria, kCategoriasChamado, (v) => _categoria = v),
          _filtro('Prioridade', _prioridade, kPrioridadesChamado, (v) => _prioridade = v),
          FilterChip(
            label: const Text('Só atrasados'),
            selected: _atrasados,
            onSelected: (v) => setState(() => _atrasados = v),
          ),
          FilterChip(label: const Text('Só meus'), selected: _meus, onSelected: (v) => setState(() => _meus = v)),
        ],
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        CabecalhoPagina(
          'Atendimento',
          subtitulo: 'Chamados pelo prazo de resposta',
          acoes: [
            if (context.pode(Permissao.sacResponder))
              BotaoTrato.primario('Registrar contato', aoPressionar: _registrar),
          ],
        ),
        Expanded(
          child: FilaRemota<Chamado>(
            key: ValueKey('fila-sac-$_versao'),
            filtro: filtro,
            esqueleto: const EsqueletoPagina(),
            chave: (c) => c.id,
            carregar: (deslocamento, limite) =>
                context.api.listarChamados(filtro, deslocamento: deslocamento, limite: limite),
            construir: (context, fila) => LayoutBuilder(
              builder: (context, tam) => Column(
                children: [
                  // Os filtros rolam sozinhos em tela baixa, sem empurrar a lista para fora.
                  ConstrainedBox(
                    constraints: BoxConstraints(maxHeight: tam.maxHeight * 0.4),
                    child: SingleChildScrollView(padding: const EdgeInsets.only(top: EspacosTrato.x2), child: filtros),
                  ),
                  Expanded(
                    child: MestreDetalhe<Chamado>(
                      itens: fila.itens,
                      chave: (c) => c.id,
                      mensagemSemItens: 'Nenhum chamado com esse filtro.',
                      tituloDetalhe: (c) => c.protocolo,
                      rodape: fila.itens.isEmpty ? null : RodapeFila(fila, rotuloItens: 'chamados'),
                      itemBuilder: (context, c, sel) {
                        final (texto, tom) = chipStatusChamado(c.status);
                        return CartaoLista(
                          titulo: '${c.protocolo} · ${c.assunto}',
                          linhas: [
                            '${c.solicitante} · ${_rotulo(kCategoriasChamado, c.categoria)}',
                            'Responder até ${formatarData(c.prazo)}',
                          ],
                          chips: [
                            if (c.atrasado) const ChipEstado('Atrasado', tom: Tom.erro),
                            ChipEstado(texto, tom: tom),
                            if (c.prioridade == 'alta' || c.prioridade == 'urgente')
                              ChipEstado('Prioridade ${c.prioridade}', tom: Tom.alerta),
                          ],
                          selecionado: sel,
                        );
                      },
                      detalheBuilder: (context, c) => CarregaDados<Chamado>(
                        key: ValueKey('chamado-${c.id}'),
                        esqueleto: const EsqueletoPagina(),
                        atualizarSozinho: true,
                        carregar: () => context.api.obterChamado(c.id),
                        construir: (context, completo, recarregar) => _DetalheChamado(
                          key: ValueKey(c.id),
                          chamado: completo,
                          irPara: irPara,
                          aoMudar: () async {
                            await recarregar();
                            await fila.recarregar();
                          },
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _DetalheChamado extends StatefulWidget {
  const _DetalheChamado({super.key, required this.chamado, required this.aoMudar, required this.irPara});

  final Chamado chamado;
  final Future<void> Function() aoMudar;
  final void Function(String)? irPara;

  @override
  State<_DetalheChamado> createState() => _DetalheChamadoState();
}

class _DetalheChamadoState extends State<_DetalheChamado> {
  final _texto = TextEditingController();
  bool _interna = false;
  bool _aguardar = false;
  bool _enviando = false;
  String? _erro;

  @override
  void dispose() {
    _texto.dispose();
    super.dispose();
  }

  /// Uma escrita por vez; o erro fica fixo na tela e o texto digitado só some se der certo.
  Future<void> _enviar(Future<Chamado> Function() chamada, String sucesso, {bool limparTexto = false}) async {
    if (_enviando) return;
    setState(() {
      _enviando = true;
      _erro = null;
    });
    try {
      await chamada();
      if (mounted) {
        if (limparTexto) _texto.clear();
        mostrarAviso(context, sucesso);
      }
    } catch (e) {
      if (mounted) setState(() => _erro = e.toString());
    } finally {
      await widget.aoMudar();
      if (mounted) setState(() => _enviando = false);
    }
  }

  Future<void> _assumir() async {
    final c = widget.chamado;
    final deOutro = c.responsavelId != null;
    final ok = await confirmarAtendimento(
      context,
      titulo: deOutro ? 'Assumir no lugar de outra pessoa?' : 'Assumir este chamado?',
      texto: deOutro
          ? '${c.responsavelNome ?? 'Outra pessoa'} já está atendendo. O chamado passa para você.'
          : 'Você fica como responsável pelo chamado.',
      verbo: deOutro ? 'Assumir no lugar' : 'Assumir',
    );
    if (!ok || !mounted) return;
    final api = context.api;
    await _enviar(() => api.assumirChamado(c.id, substituir: deOutro), 'Chamado assumido.');
  }

  Future<void> _responder() async {
    final texto = _texto.text.trim();
    if (texto.isEmpty || _enviando) return;
    final interna = _interna;
    final aguardar = !interna && _aguardar;
    if (!interna) {
      final ok = await confirmarAtendimento(
        context,
        titulo: 'Enviar a resposta ao usuário?',
        texto: 'Protocolo ${widget.chamado.protocolo}. Depois de enviada, a mensagem não pode ser apagada.\n\n$texto',
        verbo: 'Enviar resposta',
      );
      if (!ok || !mounted) return;
    }
    final api = context.api;
    await _enviar(
      () => api.responderChamado(widget.chamado.id, texto: texto, interna: interna, aguardarUsuario: aguardar),
      interna ? 'Nota interna salva.' : 'Resposta registrada.',
      limparTexto: true,
    );
  }

  Future<void> _prazo() async {
    if (await abrirNovoPrazo(context, widget.chamado) && mounted) await widget.aoMudar();
  }

  Future<void> _encerrar() async {
    if (await abrirEncerramento(context, widget.chamado) && mounted) await widget.aoMudar();
  }

  void _irParaAusencias() {
    Navigator.of(context).popUntil((r) => r.isFirst);
    widget.irPara?.call('ausencias');
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.chamado;
    final (textoStatus, tom) = chipStatusChamado(c.status);
    final pode = context.pode(Permissao.sacResponder);
    final meu = c.responsavelId != null && c.responsavelId == context.eu?.id;
    return ListView(
      padding: const EdgeInsets.all(EspacosTrato.x6),
      children: [
        Text(c.assunto, style: TipografiaTrato.titulo),
        const SizedBox(height: EspacosTrato.x2),
        Wrap(
          spacing: EspacosTrato.x2,
          runSpacing: EspacosTrato.x2,
          children: [
            if (c.atrasado) const ChipEstado('Atrasado', tom: Tom.erro),
            ChipEstado(textoStatus, tom: tom),
          ],
        ),
        const SizedBox(height: EspacosTrato.x3),
        Linha('Protocolo', c.protocolo),
        Linha('Solicitante', c.solicitante),
        if (c.contato != null) Linha('Contato', c.contato!),
        Linha('Canal', _rotulo(kCanaisChamado, c.canal)),
        Linha('Categoria', _rotulo(kCategoriasChamado, c.categoria)),
        Linha('Prioridade', _rotulo(kPrioridadesChamado, c.prioridade)),
        Linha('Aberto em', formatarData(c.abertoEm)),
        Linha('Responder até', formatarData(c.prazo)),
        if (c.motivoExtensao != null) Linha('Motivo do novo prazo', c.motivoExtensao!),
        Linha(
          'Responsável',
          c.responsavelId == null
              ? 'Sem responsável'
              : (meu ? 'Você' : c.responsavelNome ?? 'Outra pessoa da equipe'),
        ),
        if (c.pedidoId != null) Linha('Pedido', c.pedidoId!),
        if (c.encerradoEm != null) Linha('Encerrado em', formatarData(c.encerradoEm!)),
        if (c.contestacaoRetencao) ...[
          const SizedBox(height: EspacosTrato.x3),
          const BannerInfo(
            'Esta contestação não se encerra por aqui: só pela decisão de outro analista, no caso de '
            'Cliente ausente (Termos 8.7).',
            titulo: 'Contestação de retenção.',
            tom: Tom.alerta,
          ),
          if (context.pode(Permissao.disputasVer) && widget.irPara != null)
            Align(
              alignment: Alignment.centerLeft,
              child: BotaoTrato.link('Abrir Cliente ausente', aoPressionar: _irParaAusencias),
            )
          else
            Text('Peça a quem analisa disputas.', style: TipografiaTrato.legenda),
        ],
        // A contestação da decisão (8.7) nasce de um chamado de uma conta (a parte).
        if (pode && c.usuarioId != null && !c.contestacaoRetencao) ...[
          const SizedBox(height: EspacosTrato.x3),
          Align(
            alignment: Alignment.centerLeft,
            child: BotaoTrato.secundario('Registrar contestação de disputa',
                aoPressionar: () => abrirRegistroDeContestacaoDeDisputa(context, c)),
          ),
        ],
        const SizedBox(height: EspacosTrato.x5),
        Text('Mensagens', style: TipografiaTrato.secao),
        const SizedBox(height: EspacosTrato.x2),
        if (c.mensagens.isEmpty) Text('Sem mensagens.', style: TipografiaTrato.corpo),
        for (final m in c.mensagens) _Mensagem(m),
        if (_erro != null) ...[
          const SizedBox(height: EspacosTrato.x3),
          BannerInfo(_erro!, titulo: 'Não foi feito.', tom: Tom.erro),
        ],
        const SizedBox(height: EspacosTrato.x4),
        if (!pode)
          const BannerInfo('Seu papel acompanha o atendimento, mas não responde.')
        else if (c.encerrado)
          const BannerInfo('Chamado encerrado.')
        else ...[
          Wrap(
            spacing: EspacosTrato.x2,
            runSpacing: EspacosTrato.x2,
            children: [
              if (!meu) BotaoTrato.secundario('Assumir', aoPressionar: _enviando ? null : _assumir),
              BotaoTrato.secundario('Estender prazo', aoPressionar: _enviando ? null : _prazo),
              if (!c.contestacaoRetencao)
                BotaoTrato.secundario('Encerrar', aoPressionar: _enviando ? null : _encerrar),
            ],
          ),
          const SizedBox(height: EspacosTrato.x4),
          Wrap(
            spacing: EspacosTrato.x2,
            children: [
              for (final (valor, rotulo) in const [(false, 'Responder ao usuário'), (true, 'Nota interna')])
                ChoiceChip(
                  label: Text(rotulo),
                  selected: _interna == valor,
                  onSelected: _enviando ? null : (_) => setState(() => _interna = valor),
                  materialTapTargetSize: MaterialTapTargetSize.padded,
                ),
            ],
          ),
          const SizedBox(height: EspacosTrato.x3),
          TextField(
            controller: _texto,
            minLines: 3,
            maxLines: 6,
            maxLength: 4000,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              labelText: _interna ? 'Nota interna (só a equipe vê)' : 'Mensagem ao usuário',
            ),
          ),
          if (!_interna)
            // Material próprio: o toque aparece mesmo sobre o fundo do cartão do detalhe.
            Material(
              type: MaterialType.transparency,
              child: CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                title: Text('Aguardar resposta do usuário', style: TipografiaTrato.corpo),
                value: _aguardar,
                onChanged: _enviando ? null : (v) => setState(() => _aguardar = v ?? false),
              ),
            ),
          if (!_interna && c.usuarioId == null)
            const BannerInfo(
              'Este contato não tem conta: o painel só registra a resposta. Envie também pelo canal de contato.',
              tom: Tom.alerta,
            ),
          const SizedBox(height: EspacosTrato.x2),
          Align(
            alignment: Alignment.centerRight,
            child: BotaoTrato.primario(
              _interna ? 'Salvar nota' : 'Responder',
              aoPressionar: _enviando || _texto.text.trim().isEmpty ? null : _responder,
              carregando: _enviando,
              rotuloCarregando: 'Enviando',
            ),
          ),
        ],
      ],
    );
  }
}

class _Mensagem extends StatelessWidget {
  const _Mensagem(this.m);
  final MensagemChamado m;

  @override
  Widget build(BuildContext context) {
    final autor = switch (m.autor) { 'usuario' => 'Usuário', 'sistema' => 'Sistema', _ => 'Equipe' };
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: EspacosTrato.x2),
      padding: const EdgeInsets.all(EspacosTrato.x3),
      decoration: BoxDecoration(
        color: m.interna ? CoresTrato.avisoFundo : CoresTrato.fundoPagina,
        borderRadius: BorderRadius.circular(EspacosTrato.raio),
        border: Border.all(color: CoresTrato.bordaSuave),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$autor · ${formatarData(m.criadaEm)}${m.interna ? ' · nota interna (o usuário não vê)' : ''}',
            style: TipografiaTrato.legenda,
          ),
          Text(m.texto, style: TipografiaTrato.corpo),
        ],
      ),
    );
  }
}
