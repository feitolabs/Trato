// Só para testes: o app não tem modo de demonstração. Monta os repositórios e serviços de
// mentira que os testes de widget usam no lugar da API.
import 'package:trato/auth/servico_auth.dart';
import 'package:trato/dados/repositorios_trato.dart';
import 'package:trato/dispositivo/dispositivo.dart';
import 'package:trato/dispositivo/servicos_dispositivo.dart';
import 'package:trato/telas/fluxo/rotas.dart';

import 'auth/servico_auth_fake.dart';
import 'dados/repositorios_catalogo_fake.dart';
import 'dados/repositorios_fake.dart';
import 'dados/servico_upload_fake.dart';
import 'dispositivo/dispositivo_fake.dart';
import 'dispositivo/permissao_fake.dart';
import 'dispositivo/servico_camera_fake.dart';
import 'dispositivo/servico_localizacao_fake.dart';
import 'telas/aditivo/aditivo_fake.dart';
import 'telas/disputa_profissional/disputa_fake.dart';
import 'telas/lgpd/servico_fake.dart';
import 'telas/mensagens/servico_fake.dart';
import 'telas/nota_material/nota_material_fake.dart';
import 'telas/perfil_publico/perfil_publico_fake.dart';
import 'telas/profissional_cadastro/cadastro_fake.dart';
import 'telas/verificacao/verificacao_fake.dart';

RepositoriosTrato repositoriosDemo() => RepositoriosTrato(
      pedidos: RepositorioPedidosFake(),
      orcamentos: RepositorioOrcamentosFake(),
      pagamento: RepositorioPagamentoFake(),
      chat: RepositorioChatFake(),
      notificacoes: RepositorioNotificacoesFake(),
      perfil: RepositorioPerfilFake(),
      profissional: RepositorioProfissionalFake(),
      catalogo: RepositorioCatalogoFake(),
      servicos: RepositorioServicosClienteFake(),
      agenda: RepositorioAgendaFake(),
      aditivo: ServicoAditivoFake(detalhe: aditivoExemplo),
      notaMaterial: ServicoNotaMaterialFake(nota: notaMaterialExemplo),
      disputaProfissional:
          ServicoDisputaProfissionalFake(disputa: disputaExemplo, retrabalho: retrabalhoExemplo),
      perfilPublico: ServicoPerfilPublicoFake(),
      cadastroProfissional: ServicoCadastroProfissionalFake(),
      verificacao: ServicoVerificacaoFake(),
      privacidade: ServicoPrivacidadeFake(),
      mensagens: const ServicoMensagensFake(),
      mensagensProfissional: const ServicoMensagensFake(),
    );

DispositivoTrato dispositivoDemo() =>
    DispositivoTrato(camera: CapturaFotoFake(), localizador: LocalizadorFake());

ServicosDispositivo servicosDispositivoFake() => ServicosDispositivo(
      camera: ServicoCameraFake(),
      localizacao: ServicoLocalizacaoFake(),
      permissao: ServicoPermissaoFake(),
      upload: ServicoUploadFake(),
    );

/// Estado inicial de cada teste: o que o `main.dart` liga em produção, ligado aos fakes.
void ligarDemoNosTestes() {
  ServicoAuthPadrao.atual = ServicoAuthFake();
  RotasTrato.repos = repositoriosDemo();
  RotasTrato.dispositivo = dispositivoDemo();
}
