import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as sb;

import 'auth/sessao_auth.dart';
import 'dados/cliente_api.dart';
import 'dados/config_web.dart';
import 'dados/erros.dart';
import 'dados/orcamentos.dart';
import 'dados/pedidos.dart';
import 'dados/perfil.dart';
import 'dados/sessao.dart';
import 'tema/tema.dart';
import 'telas/auth/tela_login.dart';
import 'telas/casca_cliente.dart';
import 'telas/casca_profissional.dart';
import 'telas/tela_sem_configuracao.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final config = ConfigWeb.doAmbiente();
  final problemas = config.problemas;
  if (problemas.isNotEmpty) {
    // Sem configuração válida o site não tenta falar com ninguém: mostra o que falta.
    debugPrint('Trato web sem configuração: ${problemas.join('; ')}');
    runApp(TelaSemConfiguracao(problemas: problemas));
    return;
  }
  await sb.Supabase.initialize(url: config.urlSupabase, publishableKey: config.chaveAnon);
  runApp(TratoWebApp(config: config));
}

/// App web do Trato: login real (Supabase, mesma conta do app) e dados reais do backend
/// (endereços em [ConfigWeb]). Nada de dados mockados nem regra de dinheiro aqui.
class TratoWebApp extends StatefulWidget {
  const TratoWebApp({super.key, required this.config});

  final ConfigWeb config;

  @override
  State<TratoWebApp> createState() => _TratoWebAppState();
}

class _TratoWebAppState extends State<TratoWebApp> {
  final _sessao = SessaoTrato();
  late final _auth = ServicoAuthWeb(_sessao);
  late final _api = ClienteApi(urlBase: widget.config.urlApi, sessao: _sessao);
  late final _repoPerfil = RepositorioPerfil(_api);
  late final _repoPedidos = RepositorioPedidos(_api);
  late final _repoOrcamentos = RepositorioOrcamentos(_api);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Trato',
      debugShowCheckedModeBanner: false,
      theme: TemaTrato.claro,
      home: _PortaDeEntrada(
        auth: _auth,
        repoPerfil: _repoPerfil,
        repoPedidos: _repoPedidos,
        repoOrcamentos: _repoOrcamentos,
      ),
    );
  }
}

class _PortaDeEntrada extends StatefulWidget {
  const _PortaDeEntrada({
    required this.auth,
    required this.repoPerfil,
    required this.repoPedidos,
    required this.repoOrcamentos,
  });

  final ServicoAuthWeb auth;
  final RepositorioPerfil repoPerfil;
  final RepositorioPedidos repoPedidos;
  final RepositorioOrcamentos repoOrcamentos;

  @override
  State<_PortaDeEntrada> createState() => _PortaDeEntradaState();
}

class _PortaDeEntradaState extends State<_PortaDeEntrada> {
  Future<PerfilTrato>? _futuroPerfil;

  @override
  void initState() {
    super.initState();
    widget.auth.logado.addListener(_aoMudarLogado);
    if (widget.auth.logado.value) _futuroPerfil = widget.repoPerfil.carregar();
  }

  @override
  void dispose() {
    widget.auth.logado.removeListener(_aoMudarLogado);
    super.dispose();
  }

  void _aoMudarLogado() {
    setState(() {
      _futuroPerfil = widget.auth.logado.value ? widget.repoPerfil.carregar() : null;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.auth.logado.value || _futuroPerfil == null) {
      return TelaLogin(servico: widget.auth);
    }
    return FutureBuilder<PerfilTrato>(
      future: _futuroPerfil,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }
        if (snapshot.hasError) {
          return _TelaErroPerfil(
            erro: snapshot.error!,
            aoTentarDeNovo: () => setState(() => _futuroPerfil = widget.repoPerfil.carregar()),
            aoSair: widget.auth.sair,
          );
        }
        final perfil = snapshot.data!;
        return perfil.ehProfissional
            ? CascaProfissional(
                perfil: perfil,
                repositorioPedidos: widget.repoPedidos,
                repositorioOrcamentos: widget.repoOrcamentos,
                servicoAuth: widget.auth,
              )
            : CascaCliente(
                perfil: perfil,
                repositorioPedidos: widget.repoPedidos,
                servicoAuth: widget.auth,
              );
      },
    );
  }
}

class _TelaErroPerfil extends StatelessWidget {
  const _TelaErroPerfil({required this.erro, required this.aoTentarDeNovo, required this.aoSair});

  final Object erro;
  final VoidCallback aoTentarDeNovo;
  final VoidCallback aoSair;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: ConteudoResponsivo(
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline_rounded, size: 40, color: CoresTrato.vermelhoTexto),
              const SizedBox(height: EspacosTrato.x3),
              Text(
                mensagemErroTrato(erro),
                textAlign: TextAlign.center,
                style: TipografiaTrato.corpo.copyWith(color: CoresTrato.textoSecundario),
              ),
              const SizedBox(height: EspacosTrato.x4),
              FilledButton(onPressed: aoTentarDeNovo, child: const Text('Tentar de novo')),
              const SizedBox(height: EspacosTrato.x2),
              TextButton(onPressed: aoSair, child: const Text('Sair')),
            ],
          ),
        ),
      ),
    );
  }
}
