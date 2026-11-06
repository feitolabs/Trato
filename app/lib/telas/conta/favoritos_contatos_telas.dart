import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../componentes/componentes.dart';
import '../../tema/tema.dart';
import '../comuns/estados.dart';
import 'dados_pessoais_tela.dart' show textoDoErro;
import 'modelos.dart';

/// Profissionais favoritos. Tocar abre o perfil ([aoAbrir]); o coração tira da lista.
class FavoritosTela extends StatefulWidget {
  const FavoritosTela({super.key, required this.servico, this.aoAbrir});

  final ServicoConta servico;
  final ValueChanged<FavoritoConta>? aoAbrir;

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
      titulo: 'Profissionais favoritos',
      child: CarregadorTela<List<FavoritoConta>>(
        carregar: widget.servico.favoritos,
        atualizarQuando: _mudou,
        construir: (context, itens, _) {
          if (itens.isEmpty) {
            return const EstadoVazio(
              icone: Icons.favorite_border,
              titulo: 'Nenhum favorito ainda',
              texto: 'Toque no coração no perfil de um profissional para guardá-lo aqui.',
            );
          }
          return ListView.separated(
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
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(f.nome ?? 'Profissional', style: TipografiaTrato.corpo),
                          if (detalhe.isNotEmpty)
                            Text(detalhe,
                                style: TipografiaTrato.corpoPequeno
                                    .copyWith(color: CoresTrato.textoSecundario)),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: 'Tirar dos favoritos',
                      onPressed: () => _tirar(f),
                      icon: const Icon(Icons.favorite, color: CoresTrato.petroleo),
                    ),
                  ],
                ),
              );
            },
          );
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
        construir: (context, itens, _) => ListView(
          padding: const EdgeInsets.only(bottom: EspacosTrato.x6),
          children: [
            Text(
              'Pessoas de confiança que você quer ter à mão durante um serviço. Até 5.',
              style: TipografiaTrato.corpoPequeno.copyWith(color: CoresTrato.textoSecundario),
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
                                .copyWith(color: CoresTrato.textoSecundario),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: 'Remover',
                      onPressed: () => _remover(c),
                      icon: const Icon(Icons.delete_outline, color: CoresTrato.petroleo),
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
        ),
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
  final _nome = TextEditingController();
  final _telefone = TextEditingController();
  final _parentesco = TextEditingController();
  var _salvando = false;
  String? _erro;

  @override
  void dispose() {
    _nome.dispose();
    _telefone.dispose();
    _parentesco.dispose();
    super.dispose();
  }

  Future<void> _salvar() async {
    final digitos = _telefone.text.replaceAll(RegExp(r'\D'), '');
    if (_nome.text.trim().length < 2) {
      setState(() => _erro = 'Informe o nome.');
      return;
    }
    if (digitos.length != 10 && digitos.length != 11) {
      setState(() => _erro = 'Informe o telefone com DDD.');
      return;
    }
    setState(() {
      _salvando = true;
      _erro = null;
    });
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
        children: [
          CampoTrato(rotulo: 'Nome', controlador: _nome),
          const SizedBox(height: EspacosTrato.x3),
          CampoTrato(
            rotulo: 'Telefone',
            controlador: _telefone,
            dica: '(11) 98888-7777',
            teclado: TextInputType.phone,
            formatadores: [FilteringTextInputFormatter.allow(RegExp(r'[0-9()\- ]'))],
          ),
          const SizedBox(height: EspacosTrato.x3),
          CampoTrato(rotulo: 'Parentesco (opcional)', controlador: _parentesco, dica: 'Irmã, amigo...'),
          if (_erro != null) ...[
            const SizedBox(height: EspacosTrato.x3),
            Text(_erro!,
                style: TipografiaTrato.corpoPequeno.copyWith(color: CoresTrato.vermelhoTexto)),
          ],
          const SizedBox(height: EspacosTrato.x5),
          BotaoPrimario(
              texto: 'Salvar', carregando: _salvando, aoTocar: _salvando ? null : _salvar),
        ],
      ),
    );
  }
}
