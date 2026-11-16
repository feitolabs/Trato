import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:path_provider/path_provider.dart';

import '../dispositivo/servico_camera.dart';
import 'fila_offline.dart';
import 'repositorios_api.dart' show FotoCapturada, PosicaoCapturada;

/// Fila offline que sobrevive ao app fechado: a lista vai num JSON e cada foto num arquivo, na
/// pasta privada do app (nunca na galeria). Check-in e check-out sem internet esperam aqui até
/// o servidor aceitar. A hora que vale é a do servidor; a do aparelho vai só como dica.
class FilaOfflineArquivo implements FilaOffline {
  FilaOfflineArquivo._(this._pasta, this._itens, this._arquivos);

  /// Abre (ou cria) a fila na pasta de documentos do app.
  static Future<FilaOfflineArquivo> abrir() async {
    final base = await getApplicationDocumentsDirectory();
    return abrirEm(Directory('${base.path}/fila_offline'));
  }

  /// Abre a fila numa pasta qualquer (testes). Arquivo estragado vira fila vazia.
  static FilaOfflineArquivo abrirEm(Directory pasta) {
    pasta.createSync(recursive: true);
    final itens = <AcaoOffline>[];
    final arquivos = <AcaoOffline, String>{};
    final indice = File('${pasta.path}/fila.json');
    if (indice.existsSync()) {
      try {
        for (final j in jsonDecode(indice.readAsStringSync()) as List) {
          final mapa = j as Map<String, dynamic>;
          final acao = _ler(pasta, mapa);
          if (acao == null) continue;
          itens.add(acao);
          final nome = mapa['foto'] as String?;
          if (nome != null) arquivos[acao] = nome;
        }
      } on Object {
        itens.clear();
        arquivos.clear();
      }
    }
    return FilaOfflineArquivo._(pasta, itens, arquivos);
  }

  final Directory _pasta;
  final List<AcaoOffline> _itens;
  final Map<AcaoOffline, String> _arquivos;

  @override
  List<AcaoOffline> get pendentes => List.unmodifiable(_itens);

  @override
  void guardar(AcaoOffline acao) {
    final foto = acao.foto.local;
    if (foto != null) {
      final nome = 'foto_${DateTime.now().microsecondsSinceEpoch}.jpg';
      File('${_pasta.path}/$nome').writeAsBytesSync(foto.bytes, flush: true);
      _arquivos[acao] = nome;
    }
    _itens.add(acao);
    _gravar();
  }

  @override
  void remover(AcaoOffline acao) {
    if (!_itens.remove(acao)) return;
    final nome = _arquivos.remove(acao);
    if (nome != null) {
      final arquivo = File('${_pasta.path}/$nome');
      if (arquivo.existsSync()) arquivo.deleteSync();
    }
    _gravar();
  }

  void _gravar() {
    final lista = [
      for (final a in _itens)
        {
          'pedido_id': a.pedidoId,
          'tipo': a.tipo.name,
          'codigo': a.codigo,
          'tirada_em': a.foto.tiradaEm.toUtc().toIso8601String(),
          'arquivo_id': a.foto.arquivoId,
          'foto': _arquivos[a],
          'posicao': a.posicao == null
              ? null
              : {
                  'latitude': a.posicao!.latitude,
                  'longitude': a.posicao!.longitude,
                  'distancia_m': a.posicao!.distanciaMetros,
                },
        },
    ];
    File('${_pasta.path}/fila.json').writeAsStringSync(jsonEncode(lista), flush: true);
  }

  static AcaoOffline? _ler(Directory pasta, Map<String, dynamic> j) {
    final tirada = DateTime.tryParse('${j['tirada_em']}');
    if (tirada == null) return null;
    ArquivoCapturado? local;
    final nome = j['foto'] as String?;
    if (nome != null) {
      final arquivo = File('${pasta.path}/$nome');
      if (!arquivo.existsSync()) return null;
      final Uint8List bytes = arquivo.readAsBytesSync();
      local = ArquivoCapturado(
        bytes: bytes,
        sha256: crypto.sha256.convert(bytes).toString(),
        capturadaEm: tirada,
      );
    }
    final pos = j['posicao'];
    return AcaoOffline(
      pedidoId: j['pedido_id'] as String,
      tipo: TipoAcaoOffline.values.byName(j['tipo'] as String),
      codigo: j['codigo'] as String,
      foto: FotoCapturada(arquivoId: j['arquivo_id'] as String?, tiradaEm: tirada, local: local),
      posicao: pos is Map
          ? PosicaoCapturada(
              (pos['latitude'] as num).toDouble(),
              (pos['longitude'] as num).toDouble(),
              distanciaMetros: (pos['distancia_m'] as num?)?.toInt(),
            )
          : null,
    );
  }
}
