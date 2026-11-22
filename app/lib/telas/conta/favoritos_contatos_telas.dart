import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../componentes/componentes.dart';
import '../../dados/carregador.dart';
import '../../tema/tema.dart';
import '../comuns/estados.dart';
import '../comuns/foco_rolagem.dart';
import 'dados_pessoais_tela.dart' show textoDoErro;
import 'modelos.dart';

/// Profissionais favoritos. Tocar abre o perfil ([aoAbrir]); o coração tira da lista.
class FavoritosTela extends StatefulWidget {
  const FavoritosTela({
    super.key,
    required this.servico,
    this.aoAbrir,
    this.aoBuscar,
    this.aoChamarDeNovo,
  });

  final ServicoConta servico;
  final ValueChanged<FavoritoConta>? aoAbrir;

  /// "Chamar de novo": abre o novo pedido já direcionado a este profissional.
  final ValueChanged<FavoritoConta>? aoChamarDeNovo;

  /// Ação do estado vazio: leva à busca de profissionais. Sem ela, o botão não aparece.
  final VoidCallback? aoBuscar;

  @override
  State<FavoritosTela> createState() => _FavoritosTelaState();
}

class _FavoritosTelaState extends State<FavoritosTela> {
  final _mudou = ValueNotifier<int>(0);

  @override
  void dispose() {
    _mudou.dispose();
    super.dispose();
  }

  Future<void> _tirar(FavoritoConta f) async {
    try {
      await widget.servico.desfavoritar(f.profissionalId);
      _mudou.value++;
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(textoDoErro(e))));
    }
  }

  @override
  Widget build(BuildContext context) {
    return MolduraTelaComum(
      titulo: 'Profissionais de confiança',
      child: CarregadorTela<List<FavoritoConta>>(
        carregar: widget.servico.favoritos,
        atualizarQuando: _mudou,
        construir: (context, itens, _) {
          final recarregar = AtualizadorTela.de(context);
          final Widget body;
          if (itens.isEmpty) {
            body = EstadoVazio(
              icone: Icons.favorite_border,
              titulo: 'Nenhum profissional de confiança ainda',
              texto: 'Toque no coração no perfil de um profissional para salvá-lo como profissional de confiança.',
              textoAcao: widget.aoBuscar == null ? null : 'Buscar profissionais',
              aoAcao: widget.aoBuscar,
            );
          } else {
            body = ListView.separated(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.only(bottom: EspacosTrato.x6),
              itemCount: itens.length,
              separatorBuilder: (_, __) => const SizedBox(height: EspacosTrato.x3),
              itemBuilder: (context, i) {
                final f = itens[i];
                final detalhe = [
                  if (f.nota != null) 'Nota ${f.nota!.toStringAsFixed(1).replaceAll('.', ',')}',
                  if (f.servicos != null) '${f.servicos} serviços',
                ].join(' · ');
                return CartaoTrato(
                  aoTocar: widget.aoAbrir == null ? null : () => widget.aoAbrir!(f),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(f.nome ?? 'Profissional', style: TipografiaTrato.corpo),
                                if (detalhe.isNotEmpty)
                                  Text(detalhe,
                                      style: TipografiaTrato.corpoPequeno
                                          .copyWith(color: context.cores.textoSecundario)),
                              ],
                            ),
                          ),
                          IconButton(
                            tooltip: 'Remover dos profissionais de confiança',
                            onPressed: () => _tirar(f),
                            icon: Icon(Icons.favorite, color: context.cores.petroleo),
                          ),
                        ],
                      ),
                      if (widget.aoChamarDeNovo != null) ...[
                        const SizedBox(height: EspacosTrato.x2),
                        BotaoSecundario(
                          texto: 'Chamar de novo',
                          aoTocar: () => widget.aoChamarDeNovo!(f),
                        ),
                      ],
                    ],
                  ),
                );
              },
            );
          }
          return recarregar == null ? body : RefreshIndicator(onRefresh: recarregar, child: body);
        },
      ),
    );
  }
}

/// Contatos de confiança (até 5): pessoas que você quer ter à mão durante um serviço.
class ContatosConfiancaTela extends StatefulWidget {
  const ContatosConfiancaTela({super.key, required this.servico});

  final ServicoConta servico;

  @override
  State<ContatosConfiancaTela> createState() => _ContatosConfiancaTelaState();
}

class _ContatosConfiancaTelaState extends State<ContatosConfiancaTela> {
  final _mudou = ValueNotifier<int>(0);

  @override
  void dispose() {
    _mudou.dispose();
    super.dispose();
  }

  Future<void> _adicionar() async {
    final feito = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => _FormContatoTela(servico: widget.servico)),
    );
    if (feito == true) _mudou.value++;
  }

  Future<void> _remover(ContatoDeConfianca c) async {
    final confirma = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Remover ${c.nome}?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Remover')),
        ],
      ),
    );
    if (confirma != true) return;
    try {
      await widget.servico.removerContato(c.id);
      _mudou.value++;
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(textoDoErro(e))));
    }
  }

  @override
  Widget build(BuildContext context) {
    return MolduraTelaComum(
      titulo: 'Contatos de confiança',
      child: CarregadorTela<List<ContatoDeConfianca>>(
        carregar: widget.servico.contatos,
        atualizarQuando: _mudou,
        construir: (context, itens, _) {
          final recarregar = AtualizadorTela.de(context);
          final lista = ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.only(bottom: EspacosTrato.x6),
            children: [
              Text(
                'Pessoas de confiança que você quer ter à mão durante um serviço. Até 5.',
                style: TipografiaTrato.corpoPequeno.copyWith(color: context.cores.textoSecundario),
              ),
              const SizedBox(height: EspacosTrato.x4),
              if (itens.isEmpty)
                const EstadoVazio(
                  icone: Icons.people_outline,
                  titulo: 'Nenhum contato ainda',
                  texto: 'Adicione alguém de confiança.',
                ),
              for (final c in itens) ...[
                CartaoTrato(
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(c.nome, style: TipografiaTrato.corpo),
                            Text(
                              [
                                formatarTelefone(c.telefone),
                                if ((c.parentesco ?? '').isNotEmpty) c.parentesco!,
                              ].join(' · '),
                              style: TipografiaTrato.corpoPequeno
                                  .copyWith(color: context.cores.textoSecundario),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        tooltip: 'Remover',
                        onPressed: () => _remover(c),
                        icon: Icon(Icons.delete_outline, color: context.cores.petroleo),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: EspacosTrato.x3),
              ],
              const SizedBox(height: EspacosTrato.x3),
              if (itens.length < 5)
                BotaoPrimario(texto: 'Adicionar contato', aoTocar: _adicionar),
            ],
          );
          return recarregar == null ? lista : RefreshIndicator(onRefresh: recarregar, child: lista);
        },
      ),
    );
  }
}

class _FormContatoTela extends StatefulWidget {
  const _FormContatoTela({required this.servico});

  final ServicoConta servico;

  @override
  State<_FormContatoTela> createState() => _FormContatoTelaState();
}

class _FormContatoTelaState extends State<_FormContatoTela> {
  final _scroll = ScrollController();
  final _keyNome = GlobalKey();
  final _keyTelefone = GlobalKey();
  final _focoNome = FocusNode();
  final _focoTelefone = FocusNode();
  final _nome = TextEditingController();
  final _telefone = TextEditingController();
  final _parentesco = TextEditingController();
  var _salvando = false;
  var _tentou = false;
  String? _erroNome;
  String? _erroTelefone;
  String? _erro;

  @override
  void dispose() {
    _scroll.dispose();
    _focoNome.dispose();
    _focoTelefone.dispose();
    _nome.dispose();
    _telefone.dispose();
    _parentesco.dispose();
    super.dispose();
  }

  Future<void> _salvar() async {
    final digitos = _telefone.text.replaceAll(RegExp(r'\D'), '');
    final errNome = _nome.text.trim().length < 2 ? 'Informe o nome.' : null;
    final errTel = (digitos.length != 10 && digitos.length != 11)
        ? 'Informe o telefone com DDD.'
        : null;
    setState(() {
      _tentou = true;
      _erroNome = errNome;
      _erroTelefone = errTel;
      _erro = null;
    });
    if (errNome != null || errTel != null) {
      focarPrimeiroErro([
        EntradaCampoErro(key: _keyNome, focusNode: _focoNome, temErro: () => _erroNome != null),
        EntradaCampoErro(key: _keyTelefone, focusNode: _focoTelefone, temErro: () => _erroTelefone != null),
      ]);
      return;
    }
    setState(() => _salvando = true);
    try {
      await widget.servico.adicionarContato(
        nome: _nome.text.trim(),
        telefone: digitos,
        parentesco: _parentesco.text.trim(),
      );
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) setState(() => _erro = textoDoErro(e));
    } finally {
      if (mounted) setState(() => _salvando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return MolduraTelaComum(
      titulo: 'Novo contato',
      child: ListView(
        controller: _scroll,
        children: [
          KeyedSubtree(
            key: _keyNome,
            child: CampoTrato(
              rotulo: 'Nome',
              controlador: _nome,
              foco: _focoNome,
              erro: _tentou ? _erroNome : null,
              aoMudar: (_) {
                if (_erroNome != null) setState(() => _erroNome = null);
              },
            ),
          ),
          const SizedBox(height: EspacosTrato.x3),
          KeyedSubtree(
            key: _keyTelefone,
            child: CampoTrato(
              rotulo: 'Telefone',
              controlador: _telefone,
              foco: _focoTelefone,
              dica: '(11) 98888-7777',
              teclado: TextInputType.phone,
              formatadores: [FilteringTextInputFormatter.allow(RegExp(r'[0-9()\- ]'))],
              erro: _tentou ? _erroTelefone : null,
              aoMudar: (_) {
                if (_erroTelefone != null) setState(() => _erroTelefone = null);
              },
            ),
          ),
          const SizedBox(height: EspacosTrato.x3),
          CampoTrato(rotulo: 'Parentesco (opcional)', controlador: _parentesco, dica: 'Irmã, amigo...'),
          if (_erro != null) ...[
            const SizedBox(height: EspacosTrato.x3),
            Text(_erro!,
                style: TipografiaTrato.corpoPequeno.copyWith(color: context.cores.vermelhoTexto)),
          ],
          const SizedBox(height: EspacosTrato.x5),
          BotaoPrimario(
              texto: 'Salvar', carregando: _salvando, aoTocar: _salvando ? null : _salvar),
        ],
      ),
    );
  }
}
