import '../../dados/erros.dart';
import 'modelos.dart';

/// Demonstração e testes: tudo na memória, sem rede.
class ServicoIndicacoesFake implements ServicoIndicacoes {
  ServicoIndicacoesFake({
    MeuCodigoIndicacao? meu,
    this.codigosValidos = const {'AMIGO123': 'Ana S.'},
    this.falharAoCarregar = false,
  }) : _meu = meu ?? const MeuCodigoIndicacao(codigo: 'TRATO2026');

  final MeuCodigoIndicacao _meu;

  /// Código -> nome curto de quem indica.
  final Map<String, String> codigosValidos;
  final bool falharAoCarregar;

  /// Códigos aplicados (para conferir nos testes).
  final List<String> aplicados = [];
  final List<String> validados = [];

  /// Se preenchido, [aplicar] falha com esse erro (texto do backend).
  ErroTrato? erroAoAplicar;

  @override
  Future<MeuCodigoIndicacao> meuCodigo() async {
    if (falharAoCarregar) throw ErroTrato.servidor;
    return _meu;
  }

  @override
  Future<ConviteIndicacao> validar(String codigo) async {
    final c = codigo.trim().toUpperCase();
    validados.add(c);
    final nome = codigosValidos[c];
    if (nome == null) {
      throw const ErroTrato(TipoErro.naoEncontrado, 'Código de indicação não encontrado.');
    }
    return ConviteIndicacao(valido: true, indicadorNomeCurto: nome, indicadorPapel: 'cliente');
  }

  @override
  Future<ResultadoAplicacao> aplicar(String codigo) async {
    final erro = erroAoAplicar;
    if (erro != null) throw erro;
    aplicados.add(codigo.trim().toUpperCase());
    return const ResultadoAplicacao(
      mensagem: 'Código aplicado! Seu bônus sai depois do 1º serviço.',
      bonusIndicadoTratinhos: 50,
      status: 'cadastrado',
    );
  }
}
