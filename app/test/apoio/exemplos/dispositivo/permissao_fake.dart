import 'package:permission_handler/permission_handler.dart' as ph;
import 'package:trato/dispositivo/permissao.dart';

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
