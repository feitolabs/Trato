/// O que as telas repetem dos Termos de uso, num só lugar. Só texto: quem aplica prazo e decide
/// é o servidor.
library;

/// Versão dos Termos que o app mostra (`assets/legal/termos-de-uso.md`). É a que o cadastro
/// grava como aceita (Termos 1.4). Ao trocar o texto do app, troque aqui: um teste confere.
const versaoDosTermos = '1.1';

/// Termos 6.1, junto dos preços mostrados ao cliente.
const textoPrecoComTributos =
    'O valor mostrado já inclui os tributos que incidam sobre ele e todas as despesas '
    'conhecidas. Qualquer custo adicional (materiais, deslocamento, taxa de parcelamento) é '
    'informado antes do pagamento.';

/// Termos 13.10 e I.11, no encerramento por vontade própria. A guarda de 90 dias do
/// encerramento feito pelo Trato não entra aqui: o servidor ainda não faz.
const textoTratinhosNoEncerramento =
    'Ao encerrar a conta por vontade própria, você perde os Tratinhos que ainda tiver.';

/// Versão da Política de privacidade que o app mostra (`assets/legal/politica-de-privacidade.md`).
const versaoDaPrivacidade = '1.1';

/// Termos 7.2 e 7.3, junto da caixa do pagamento (que nunca vem marcada).
const textoExecucaoImediata = 'Opcional. Você tem 7 dias para desistir da contratação. Se '
    'marcar e desistir depois de o serviço começar, o reembolso é proporcional à parte não '
    'executada, calculado por um analista; serviço executado por inteiro não é desfeito pela '
    'desistência. Sem marcar, desistir dentro dos 7 dias dá reembolso integral, mesmo depois '
    'do check-in.';

/// Termos 25.5.
const textoAtendimentoHumano =
    'Você pode pedir atendimento por uma pessoa a qualquer momento.';

/// Termos 5.7: check-out sem o código do cliente.
const textoAnalistaDecide = 'Se não houver resposta em 5 dias úteis, um analista decide com '
    'base nas provas do pedido.';

/// Termos 5.7, para o pedido que aguarda confirmação (vale para cliente e profissional).
const textoEncerradoSemCodigo = 'Encerrado sem o código: não há confirmação automática. Se o '
    'cliente não responder em 5 dias úteis, um analista decide com base nas provas do pedido.';
