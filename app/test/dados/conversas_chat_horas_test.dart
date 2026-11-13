import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:trato/dados/cliente_api.dart';
import 'package:trato/dados/repositorios_api.dart';
import 'package:trato/dados/sessao.dart';
import 'package:trato/telas/mensagens/servico_conversas.dart';
import 'package:trato/telas/pedidos/modelos.dart';

import '../apoio/exemplos/dados/servico_upload_fake.dart';

http.Response _json(Object corpo, [int status = 200]) => http.Response(
      jsonEncode(corpo),
      status,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );

class _Chamada {
  _Chamada(this.metodo, this.caminho, this.corpo);

  final String metodo;
  final String caminho;
  final Map<String, dynamic>? corpo;
}

(ClienteApi, List<_Chamada>) _cliente(http.Response Function(http.Request) responder) {
  final chamadas = <_Chamada>[];
  final sessao = SessaoTrato()..entrar('valor-de-teste');
  final api = ClienteApi(
    urlBase: 'https://api.teste/',
    sessao: sessao,
    cliente: MockClient((req) async {
      chamadas.add(
        _Chamada(
          req.method,
          req.url.path + (req.url.hasQuery ? '?${req.url.query}' : ''),
          req.body.isEmpty ? null : jsonDecode(req.body) as Map<String, dynamic>,
        ),
      );
      return responder(req);
    }),
  );
  return (api, chamadas);
}

const _midia = '0123456789abcdef0123456789abcdef';

void main() {
  group('ServicoConversasApi (GET /v1/conversas)', () {
    final corpo = [
      {
        'id': 'conv-1',
        'pedido_id': 'ped-aaaa',
        'outra_parte_id': 'pro-1',
        'outra_parte_nome': 'Ana S.',
        'titulo_pedido': 'Trocar chuveiro',
        'contratado': false,
        'encerrada': false,
        'nao_lidas': 2,
        'ultima_mensagem': 'Posso ir amanhã',
        'ultima_em': DateTime.now().toUtc().toIso8601String(),
        'ultima_minha': false,
      },
      {
        'id': 'conv-2',
        'pedido_id': 'ped-bbbb',
        'outra_parte_id': 'pro-2',
        'outra_parte_nome': null,
        'titulo_pedido': null,
        'contratado': true,
        'encerrada': false,
        'nao_lidas': 0,
        'ultima_mensagem': '[Foto:$_midia]',
        'ultima_em': '2026-10-01T10:00:00Z',
        'ultima_minha': true,
      },
      {
        'id': 'conv-3',
        'pedido_id': 'ped-cccc',
        'outra_parte_id': 'pro-3',
        'outra_parte_nome': 'Beto',
        'titulo_pedido': 'Pintura',
        'contratado': false,
        'encerrada': false,
        'nao_lidas': 0,
        'ultima_mensagem': '[contraproposta:orc-1:25000] Contraproposta de R\$ 250,00',
        'ultima_em': null,
        'ultima_minha': false,
      },
    ];

    test('mostra todas as conversas, com nome, título, prévia e não lidas', () async {
      final (api, chamadas) = _cliente((_) => _json(corpo));
      final lista = await ServicoConversasApi(api, comoProfissional: false).listar();

      // Só as conversas em que a pessoa é cliente (a mesma conta pode ser profissional também).
      expect(chamadas.single.caminho, '/v1/conversas?como=cliente');
      expect(lista, hasLength(3));
      expect(lista[0].interlocutor, 'Ana S.');
      expect(lista[0].tituloPedido, 'Trocar chuveiro');
      expect(lista[0].ultimaMensagem, 'Posso ir amanhã');
      expect(lista[0].naoLidas, 2);
      expect(lista[0].outraParteId, 'pro-1');
      // Cliente abre o chat com o profissional da conversa.
      expect(lista[0].profissionalId, 'pro-1');
      // Sem nome nem título: rótulos padrão e número do pedido.
      expect(lista[1].interlocutor, 'Profissional');
      expect(lista[1].tituloPedido, 'Pedido #PEDB');
      expect(lista[1].ultimaMensagem, 'Você: 📷 Foto');
      expect(lista[2].ultimaMensagem, 'Contraproposta');
      expect(lista[2].quando, '');
    });

    test('para o profissional, o outro lado é o cliente e não manda profissional_id', () async {
      final (api, _) = _cliente((_) => _json(corpo));
      final (api2, chamadas2) = _cliente((_) => _json(corpo));
      final lista = await ServicoConversasApi(api2, comoProfissional: true).listar();

      expect(chamadas2.single.caminho, '/v1/conversas?como=profissional');
      expect(lista[1].interlocutor, 'Cliente');
      expect(lista.every((c) => c.profissionalId == null), isTrue);
      expect(lista[0].outraParteId, 'pro-1'); // quem está do outro lado (foto de perfil)
    });
  });

  group('Foto no chat', () {
    test('mensagem [Foto:id] vira a URL da imagem (uma busca só, com cache)', () async {
      final (api, chamadas) = _cliente((r) {
        if (r.url.path.endsWith('/mensagens')) {
          return _json([
            {
              'id': 1,
              'autor_id': 'u1',
              'minha': false,
              'texto': '[Foto:$_midia]',
              'mascarada': false,
              'enviada_em': '2026-10-29T10:00:00Z',
              'lida_em': null,
            },
          ]);
        }
        if (r.url.path.contains('/anexos-chat/')) {
          return _json({'url': 'https://storage.teste/foto.jpg?token=1', 'expira_em_segundos': 300});
        }
        return _json({'detail': 'não'}, 404);
      });
      final repo = RepositorioChatApi(api);

      final primeira = await repo.conversa('ped-1');
      final segunda = await repo.conversa('ped-1');

      expect(primeira.mensagens.single.tipo, TipoMensagem.foto);
      expect(primeira.mensagens.single.texto, 'https://storage.teste/foto.jpg?token=1');
      expect(segunda.mensagens.single.texto, 'https://storage.teste/foto.jpg?token=1');
      final buscas = chamadas.where((c) => c.caminho.contains('/anexos-chat/'));
      expect(buscas, hasLength(1)); // a segunda leitura usou o cache
      expect(buscas.single.caminho, '/v1/pedidos/ped-1/anexos-chat/$_midia');
    });

    test('foto que não abre não derruba a conversa', () async {
      final (api, _) = _cliente((r) {
        if (r.url.path.endsWith('/mensagens')) {
          return _json([
            {
              'id': 1,
              'autor_id': 'u1',
              'minha': false,
              'texto': '[Foto:$_midia]',
              'mascarada': false,
              'enviada_em': '2026-10-29T10:00:00Z',
              'lida_em': null,
            },
          ]);
        }
        if (r.url.path.contains('/anexos-chat/')) return _json({'detail': 'fora'}, 503);
        return _json({'detail': 'não encontrado'}, 404);
      });
      final conversa = await RepositorioChatApi(api).conversa('ped-1');
      expect(conversa.mensagens, hasLength(1));
      expect(conversa.mensagens.single.texto, '[Foto indisponível]');
    });

    test('foto antiga (caminho do arquivo do outro celular) vira "Foto indisponível"', () async {
      final (api, _) = _cliente((r) {
        if (r.url.path.endsWith('/mensagens')) {
          return _json([
            {
              'id': 1,
              'autor_id': 'u1',
              'minha': false,
              'texto': '/data/user/0/br.com.feitolabs.trato/cache/scaled_70ea8cbc.jpg',
              'mascarada': false,
              'enviada_em': '2026-10-29T10:00:00Z',
              'lida_em': null,
            },
            {
              'id': 2,
              'autor_id': 'eu',
              'minha': true,
              'texto': '/data/user/0/br.com.feitolabs.trato/cache/scaled_minha.jpg',
              'mascarada': false,
              'enviada_em': '2026-10-29T10:01:00Z',
              'lida_em': null,
            },
          ]);
        }
        return _json({'detail': 'não'}, 404);
      });
      final conversa = await RepositorioChatApi(api).conversa('ped-1');
      // Recebida: nunca mostra o caminho. Enviada por mim: o arquivo existe no meu aparelho.
      expect(conversa.mensagens[0].texto, '[Foto indisponível]');
      expect(conversa.mensagens[1].texto, contains('scaled_minha.jpg'));
    });

    test('foto tirada agora sobe como anexo de chat e a mensagem leva só o id', () async {
      final arquivo = File('${Directory.systemTemp.path}/foto_chat_teste.jpg')
        ..writeAsBytesSync([0xFF, 0xD8, 1, 2, 3, 0xFF, 0xD9]);
      addTearDown(() {
        if (arquivo.existsSync()) arquivo.deleteSync();
      });
      final (api, chamadas) = _cliente((_) => _json({'id': 1}, 201));
      final upload = ServicoUploadFake();

      await RepositorioChatApi(api, upload: upload).enviarFoto(
        'ped-9',
        arquivo.path,
        profissionalId: 'pro-1',
      );

      expect(upload.enviados.single.$2.codigo, 'chat');
      expect(upload.enviados.single.$3, 'ped-9');
      final envio = chamadas.single;
      expect(envio.caminho, '/v1/pedidos/ped-9/mensagens?profissional_id=pro-1');
      // Nunca o caminho do arquivo no celular de quem enviou.
      expect(envio.corpo, {'texto': '[Foto:arq-1]'});
    });
  });

  group('Orçamento por hora', () {
    test('o cliente vê o total de horas; item de hora com valor zero não vira linha de R\$ 0,00',
        () async {
      final (api, _) = _cliente((r) {
        switch (r.url.path) {
          case '/v1/pedidos/ped-1':
            return _json({
              'id': 'ped-1',
              'estado': 'aberto',
              'estado_nome': 'Aberto',
              'cliente_id': 'c1',
              'profissional_id': null,
              'aberto_em': '2026-10-27T12:00:00Z',
              'janela': null,
              'concluido_em': null,
              'acoes_permitidas': <String>[],
              'codigo_inicio': null,
              'codigo_conclusao': null,
            });
          case '/v1/pedidos/ped-1/orcamentos':
            return _json([
              {
                'id': 'orc-1',
                'profissional_id': 'pro-1',
                'profissional_nome': 'Ana Souza',
                'versao': 2,
                'valor_centavos': 30000,
                'prazo_execucao_dias': 2,
                'garantia_dias': 60,
                'observacoes': null,
                'enviado_em': '2026-10-27T12:00:00Z',
                'aceito': false,
              },
            ]);
          default:
            return _json({
              'id': 'orc-1',
              'valor_centavos': 30000,
              'validade_ate': null,
              'garantia_dias': 60,
              'prazo_execucao_dias': 2,
              'fora_do_escopo': null,
              'sinal_material_centavos': null,
              'itens': [
                {
                  'tipo': 'outro',
                  'descricao': 'Valor combinado na contraproposta',
                  'quantidade': '1.00',
                  'valor_unitario_centavos': 30000,
                  'total_centavos': 30000,
                },
                {
                  'tipo': 'deslocamento',
                  'descricao': 'Horas de deslocamento',
                  'quantidade': '1.50',
                  'valor_unitario_centavos': 0,
                  'total_centavos': 0,
                },
                {
                  'tipo': 'horas',
                  'descricao': 'Horas trabalhadas',
                  'quantidade': '3.50',
                  'valor_unitario_centavos': 0,
                  'total_centavos': 0,
                },
              ],
              'horas_deslocamento': '1.5',
              'horas_trabalhadas': '3.5',
              'total_horas': '5',
            });
        }
      });

      final dados = await RepositorioOrcamentosApi(api).listar('ped-1');
      final detalhe = dados.orcamentos.single.detalhe!;

      expect(detalhe.totalHoras, '5 h');
      expect(detalhe.horasDeslocamento, '1,5 h');
      expect(detalhe.horasTrabalhadas, '3,5 h');
      expect(detalhe.itens.map((i) => i.descricao), ['Valor combinado na contraproposta']);
      expect(dados.orcamentos.single.totalCentavos, 30000);
    });
  });

  group('Pedidos do profissional depois do aceite', () {
    Map<String, Object?> pedido(String id, String estado, String nome) => {
          'id': id,
          'estado': estado,
          'estado_nome': nome,
          'cliente_id': 'c1',
          'profissional_id': 'me',
          'aberto_em': '2026-10-27T12:00:00Z',
          'janela': null,
          'concluido_em': null,
          'acoes_permitidas': <String>[],
          'codigo_inicio': null,
          'codigo_conclusao': null,
        };

    test('pedido aceito e ainda não pago continua na lista do profissional', () async {
      final (api, _) = _cliente((r) {
        switch (r.url.path) {
          case '/v1/me':
            return _json({'id': 'me', 'nome': 'Ana Souza'});
          case '/v1/profissional/pedidos-abertos':
            return _json(<Object>[]);
          case '/v1/profissionais/me/saldo':
            return _json({'a_liberar_centavos': 0, 'liberado_centavos': 0});
          case '/v1/profissional/orcamentos':
            return _json([
              {
                'orcamento_id': 'o1',
                'pedido_id': 'ped-1111',
                'titulo_pedido': 'Trocar chuveiro',
                'versao': 2,
                'valor_centavos': 25000,
                'enviado_em': '2026-11-12T10:00:00Z',
                'situacao': 'aguardando',
              },
              {
                'orcamento_id': 'o2',
                'pedido_id': 'ffff2222',
                'titulo_pedido': null,
                'versao': 1,
                'valor_centavos': 9000,
                'enviado_em': null,
                'situacao': 'aceito',
              },
            ]);
          case '/v1/pedidos':
            return _json([
              pedido('aaaa1111', 'orcamento_aceito', 'Orçamento aceito'),
              pedido('bbbb2222', 'aguardando_confirmacao', 'Aguardando'),
              pedido('cccc3333', 'agendado', 'Agendado'),
              pedido('dddd4444', 'concluido', 'Concluído'),
              pedido('eeee5555', 'cancelado', 'Cancelado'),
            ]);
        }
        return _json({'detail': 'não'}, 404);
      });

      final inicio = await RepositorioProfissionalApi(api).inicio();

      expect(inicio.orcamentosEnviados, hasLength(2));
      expect(inicio.orcamentosEnviados.first.titulo, 'Trocar chuveiro');
      expect(inicio.orcamentosEnviados.first.aguardando, isTrue);
      expect(inicio.orcamentosEnviados.first.valorCentavos, 25000);
      expect(inicio.orcamentosEnviados.last.titulo, 'Pedido #FFFF');
      expect(inicio.orcamentosEnviados.last.aceito, isTrue);
      expect(
        inicio.contratados.map((c) => c.estadoApi),
        ['orcamento_aceito', 'aguardando_confirmacao', 'agendado'],
      );
      final aceito = inicio.contratados.first;
      expect(aceito.aguardandoPagamento, isTrue);
      expect(aceito.naAgenda, isFalse);
      expect(aceito.situacao, contains('aguardando o pagamento'));
      expect(inicio.contratados.last.naAgenda, isTrue);
      // Só os pedidos pagos entram na agenda; o "próximo atendimento" segue o primeiro deles.
      expect(inicio.proximo?.pedidoId, 'cccc3333');
    });
  });
}
