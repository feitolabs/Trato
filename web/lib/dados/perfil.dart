import 'cliente_api.dart';

/// Espelha `PerfilOut` do backend (`GET /v1/me`), só os campos usados aqui.
class PerfilTrato {
  const PerfilTrato({
    required this.id,
    required this.nome,
    required this.papel,
    required this.status,
    this.notaPublica,
    this.servicosConcluidos,
  });

  final String id;
  final String? nome;
  final String papel;
  final String status;
  final double? notaPublica;
  final int? servicosConcluidos;

  bool get ehProfissional => papel == 'profissional';

  factory PerfilTrato.deJson(Map<String, dynamic> json) => PerfilTrato(
        id: json['id'] as String,
        nome: json['nome'] as String?,
        papel: json['papel'] as String,
        status: json['status'] as String,
        notaPublica: (json['nota_publica'] as num?)?.toDouble(),
        servicosConcluidos: json['servicos_concluidos'] as int?,
      );
}

class RepositorioPerfil {
  RepositorioPerfil(this._api);

  final ClienteApi _api;

  Future<PerfilTrato> carregar() async {
    final json = await _api.get('/v1/me');
    return PerfilTrato.deJson(json as Map<String, dynamic>);
  }
}
