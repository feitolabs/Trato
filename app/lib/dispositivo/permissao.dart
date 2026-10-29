import 'package:permission_handler/permission_handler.dart' as ph;

/// O que o app pode pedir ao aparelho. Só pedimos no momento do uso.
enum TipoPermissao { camera, localizacao }

enum EstadoPermissao {
  concedida,

  /// Ainda dá para pedir de novo.
  negada,

  /// A pessoa marcou "não perguntar de novo" (ou o sistema bloqueou): só pelas configurações.
  negadaParaSempre,
}

/// Porta para as permissões do sistema. A tela de explicação ([garantirPermissao]) vem antes.
abstract interface class ServicoPermissao {
  Future<EstadoPermissao> estado(TipoPermissao tipo);

  /// Mostra o pedido do sistema. Só chamar depois da explicação.
  Future<EstadoPermissao> pedir(TipoPermissao tipo);

  /// Abre as configurações do app no sistema.
  Future<bool> abrirConfiguracoes();
}

class ServicoPermissaoReal implements ServicoPermissao {
  const ServicoPermissaoReal();

  ph.Permission _de(TipoPermissao tipo) => switch (tipo) {
        TipoPermissao.camera => ph.Permission.camera,
        // Só "quando em uso": nunca pedimos localização em segundo plano.
        TipoPermissao.localizacao => ph.Permission.locationWhenInUse,
      };

  EstadoPermissao _traduzir(ph.PermissionStatus s) {
    if (s.isGranted || s.isLimited) return EstadoPermissao.concedida;
    if (s.isPermanentlyDenied || s.isRestricted) return EstadoPermissao.negadaParaSempre;
    return EstadoPermissao.negada;
  }

  @override
  Future<EstadoPermissao> estado(TipoPermissao tipo) async => _traduzir(await _de(tipo).status);

  @override
  Future<EstadoPermissao> pedir(TipoPermissao tipo) async => _traduzir(await _de(tipo).request());

  @override
  Future<bool> abrirConfiguracoes() => ph.openAppSettings();
}

/// Para teste e demonstração: o estado é definido por quem monta.
class ServicoPermissaoFake implements ServicoPermissao {
  ServicoPermissaoFake({this.atual = EstadoPermissao.concedida, this.aposPedir});

  EstadoPermissao atual;

  /// Estado depois de [pedir]; se nulo, o pedido não muda nada (negado continua negado).
  EstadoPermissao? aposPedir;
  int pedidos = 0;
  int aberturasDeConfiguracao = 0;

  @override
  Future<EstadoPermissao> estado(TipoPermissao tipo) async => atual;

  @override
  Future<EstadoPermissao> pedir(TipoPermissao tipo) async {
    pedidos++;
    if (atual == EstadoPermissao.negada && aposPedir != null) atual = aposPedir!;
    return atual;
  }

  @override
  Future<bool> abrirConfiguracoes() async {
    aberturasDeConfiguracao++;
    return true;
  }
}
