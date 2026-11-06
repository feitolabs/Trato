/// Pedidos independentes ao mesmo tempo: a tela espera o mais lento, não a soma de todos.
///
/// Usa `Future.wait`, que repassa o PRIMEIRO erro como veio (um `ErroTrato` continua
/// `ErroTrato`). O `.wait` de record do Dart embrulharia o erro em `ParallelWaitError`.
library;

Future<(A, B)> emParalelo2<A, B>(Future<A> a, Future<B> b) async {
  final r = await Future.wait<Object?>([a, b]);
  return (r[0] as A, r[1] as B);
}

Future<(A, B, C)> emParalelo3<A, B, C>(Future<A> a, Future<B> b, Future<C> c) async {
  final r = await Future.wait<Object?>([a, b, c]);
  return (r[0] as A, r[1] as B, r[2] as C);
}
