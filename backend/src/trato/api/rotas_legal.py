"""Páginas públicas de Política de Privacidade (/privacidade) e Termos de Uso (/termos).

Essas rotas são públicas (sem autenticação) para atenderem à exigência da Google Play Store
e da Apple App Store de URLs públicas de privacidade e termos de uso.
"""

from __future__ import annotations

from fastapi import APIRouter
from fastapi.responses import HTMLResponse

router = APIRouter(tags=["legal"])

_ESTILO_BASE = """
<style>
  :root {
    --petroleo: #12353C;
    --creme: #FBF9F5;
    --superficie: #FFFFFF;
    --texto: #1A2B2E;
    --secundario: #4E6368;
    --borda: #DCE4E6;
    --laranja: #E86F38;
  }
  * { box-sizing: border-box; }
  body {
    margin: 0;
    font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica, Arial, sans-serif;
    background-color: var(--creme);
    color: var(--texto);
    line-height: 1.65;
  }
  header {
    background-color: var(--petroleo);
    color: var(--creme);
    padding: 28px 20px;
    text-align: center;
  }
  header h1 {
    margin: 0 0 8px 0;
    font-size: 1.75rem;
  }
  header p {
    margin: 0;
    opacity: 0.9;
    font-size: 0.95rem;
  }
  nav {
    margin-top: 14px;
  }
  nav a {
    color: var(--creme);
    text-decoration: underline;
    margin: 0 10px;
    font-size: 0.9rem;
  }
  main {
    max-width: 860px;
    margin: 28px auto;
    padding: 32px 24px;
    background: var(--superficie);
    border-radius: 12px;
    border: 1px solid var(--borda);
    box-shadow: 0 2px 8px rgba(18, 53, 60, 0.05);
  }
  h2 {
    color: var(--petroleo);
    border-bottom: 1px solid var(--borda);
    padding-bottom: 8px;
    margin-top: 28px;
  }
  table {
    width: 100%;
    border-collapse: collapse;
    margin: 16px 0;
    font-size: 0.92rem;
  }
  th, td {
    border: 1px solid var(--borda);
    padding: 10px 12px;
    text-align: left;
    vertical-align: top;
  }
  th {
    background-color: #F1F5F6;
    color: var(--petroleo);
    font-weight: 600;
  }
  footer {
    text-align: center;
    padding: 24px;
    color: var(--secundario);
    font-size: 0.85rem;
  }
</style>
"""

HTML_PRIVACIDADE = f"""<!DOCTYPE html>
<html lang="pt-BR">
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1" />
  <title>Política de Privacidade — Trato Feito</title>
  {_ESTILO_BASE}
</head>
<body>
  <header>
    <h1>Política de Privacidade do Trato</h1>
    <p>Versão 1.0 · Vigência: 31/10/2026 · Feito Labs Tecnologia Ltda. (Belo Horizonte/MG)</p>
    <nav>
      <a href="/privacidade">Política de Privacidade</a>
      <a href="/termos">Termos de Uso</a>
    </nav>
  </header>
  <main>
    <p><strong>Controlador dos dados:</strong> Feito Labs Tecnologia Ltda., Belo Horizonte/MG.<br/>
    <strong>Encarregado pelo tratamento de dados (DPO):</strong> Encarregado de Proteção de Dados Feito Labs — <code>privacidade@trato.app.br</code>.</p>
    <p>Esta política explica, em linguagem simples e conforme a <strong>Lei Geral de Proteção de Dados (Lei nº 13.709/2018 — LGPD)</strong>, quais dados pessoais coletamos no aplicativo <strong>Trato</strong>, por que precisamos deles, com quem são compartilhados e como você exerce seus direitos.</p>

    <h2>1. Quais dados coletamos e para quê</h2>
    <table>
      <thead>
        <tr>
          <th>Dado</th>
          <th>De quem</th>
          <th>Para que usamos</th>
          <th>Base legal (LGPD)</th>
        </tr>
      </thead>
      <tbody>
        <tr>
          <td><strong>Nome completo, CPF e data de nascimento</strong></td>
          <td>Clientes e profissionais</td>
          <td>Identificar as partes do contrato, confirmar maioridade (18+), emitir cobranças/repasses e prevenir fraude.</td>
          <td>Execução de contrato (art. 7º, V), cumprimento de obrigação legal (art. 7º, II) e prevenção à fraude (art. 11, II, g).</td>
        </tr>
        <tr>
          <td><strong>Celular e e-mail</strong></td>
          <td>Clientes e profissionais</td>
          <td>Acesso à conta, confirmação de segurança e avisos sobre o andamento dos pedidos.</td>
          <td>Execução de contrato (art. 7º, V).</td>
        </tr>
        <tr>
          <td><strong>Avisos por WhatsApp ou notificações promocionais</strong></td>
          <td>Quem optar por receber</td>
          <td>Enviar comunicações opcionais pelo WhatsApp ou avisos sobre novidades do Trato.</td>
          <td>Consentimento (art. 7º, I) — pode ser desligado a qualquer momento em <em>Perfil → Meus dados</em>.</td>
        </tr>
        <tr>
          <td><strong>Endereço do serviço (rua, número, bairro, cidade, CEP)</strong></td>
          <td>Clientes</td>
          <td>Encontrar profissionais da região (que veem apenas o bairro antes da contratação) e permitir que o profissional contratado chegue ao local após o pagamento.</td>
          <td>Execução de contrato (art. 7º, V).</td>
        </tr>
        <tr>
          <td><strong>Fotos do documento de identidade e selfie de verificação</strong></td>
          <td>Profissionais</td>
          <td>Conferir a identidade de quem vai prestar serviços nas residências dos clientes e atribuir o selo de verificação.</td>
          <td>Prevenção à fraude e segurança do titular e de terceiros (art. 7º, IX e art. 11, II, g), mediante ciência e aceite na tela de verificação.</td>
        </tr>
        <tr>
          <td><strong>Localização do aparelho (GPS)</strong></td>
          <td>Clientes (ao buscar) e profissionais (no check-in)</td>
          <td>Mostrar profissionais próximos e registrar a prova de chegada do profissional no endereço do pedido. Nunca rastreamos localização em segundo plano fora do uso ativo.</td>
          <td>Execução de contrato (art. 7º, V) e prevenção à fraude.</td>
        </tr>
        <tr>
          <td><strong>Fotos do pedido, de check-in/check-out, de notas de material e de portfólio</strong></td>
          <td>Clientes e profissionais</td>
          <td>Formar o orçamento, comprovar a execução do serviço, registrar materiais e analisar eventuais disputas. Metadados de localização (EXIF) são removidos das fotos antes do envio.</td>
          <td>Execução de contrato (art. 7º, V) e exercício regular de direitos (art. 7º, VI).</td>
        </tr>
        <tr>
          <td><strong>Mensagens trocadas no chat do pedido</strong></td>
          <td>Clientes e profissionais</td>
          <td>Permitir a combinação do serviço e servir de prova caso haja divergência ou disputa.</td>
          <td>Execução de contrato (art. 7º, V) e exercício regular de direitos (art. 7º, VI).</td>
        </tr>
        <tr>
          <td><strong>Dados de pagamento e repasse</strong></td>
          <td>Clientes e profissionais</td>
          <td>Processar cobranças por Pix ou cartão e transferir valores aos profissionais. Os dados completos de cartão são tratados diretamente pelo parceiro de pagamento; o Trato recebe apenas identificadores e status da transação.</td>
          <td>Execução de contrato (art. 7º, V) e obrigação legal/regulatória (art. 7º, II).</td>
        </tr>
        <tr>
          <td><strong>Registros técnicos de acesso (IP, data e hora, identificadores de sessão)</strong></td>
          <td>Todos os usuários</td>
          <td>Segurança da plataforma e cumprimento do Marco Civil da Internet (Lei nº 12.965/2014).</td>
          <td>Obrigação legal (art. 7º, II) e legítimo interesse de segurança (art. 7º, IX).</td>
        </tr>
      </tbody>
    </table>

    <h2>2. O que o outro lado do pedido vê (e o que não vê)</h2>
    <ul>
      <li><strong>CPF, documento de identidade, selfie, telefone e e-mail</strong> <strong>nunca</strong> aparecem no perfil público nem nas listas de pedidos ou orçamentos.</li>
      <li><strong>Antes do pagamento confirmado:</strong> os profissionais da região veem apenas o título do pedido, a descrição, o <strong>bairro</strong> e as fotos do serviço. O endereço completo (rua, número e complemento) fica oculto.</li>
      <li><strong>No chat antes da contratação:</strong> telefones, e-mails e links externos são <strong>mascarados automaticamente</strong>.</li>
      <li><strong>Depois do pagamento confirmado:</strong> apenas o profissional contratado passa a ver o endereço completo do serviço para poder comparecer no horário agendado.</li>
    </ul>

    <h2>3. Com quem compartilhamos seus dados</h2>
    <p>Não vendemos seus dados pessoais. Compartilhamos apenas o estritamente necessário com:</p>
    <ol>
      <li><strong>A outra parte do pedido</strong> (cliente ou profissional contratado), dentro dos limites explicados na seção 2.</li>
      <li><strong>Parceiro de pagamento e liquidação financeira</strong> (<strong>Stripe Brasil Soluções de Pagamento Ltda.</strong>), para processar Pix, cartão, retenção vinculada ao pedido, estornos e repasses aos profissionais.</li>
      <li><strong>Provedores de infraestrutura em nuvem, autenticação e armazenamento seguro</strong> (<strong>Supabase Inc.</strong> e infraestrutura <strong>Amazon Web Services — AWS</strong>), que operam sob contrato de confidencialidade e segurança da informação.</li>
      <li><strong>Autoridades públicas, judiciais ou administrativas</strong>, quando houver obrigação legal ou ordem competente.</li>
    </ol>

    <h2>4. Como protegemos seus dados</h2>
    <ul>
      <li>Comunicações criptografadas em trânsito (HTTPS/TLS).</li>
      <li>Controle de acesso por linha no banco de dados (<em>Row-Level Security</em>): cada usuário só acessa os próprios pedidos, contratos e mensagens.</li>
      <li>Fotos de documentos de verificação guardadas em armazenamento privado, sem link público, acessíveis apenas por URLs temporárias assinadas e com registro de auditoria.</li>
      <li>Remoção automática de metadados de localização (EXIF) das fotos capturadas no aplicativo antes do envio.</li>
    </ul>

    <h2>5. Por quanto tempo guardamos seus dados</h2>
    <ul>
      <li><strong>Conta ativa:</strong> enquanto você mantiver sua conta no Trato.</li>
      <li><strong>Documentos de verificação recusados ou substituídos:</strong> até <strong>90 dias</strong> após a decisão para fins de auditoria antifraude, sendo eliminados em seguida.</li>
      <li><strong>Registros de conexão e acesso à aplicação:</strong> pelo mínimo de <strong>6 meses</strong>, conforme o art. 15 do Marco Civil da Internet (Lei nº 12.965/2014).</li>
      <li><strong>Contratos, notas, histórico financeiro (ledger), mensagens e provas de pedidos pagos:</strong> por <strong>5 anos</strong> após a conclusão do serviço, para cumprimento de obrigações fiscais, contábeis e exercício regular de defesa.</li>
    </ul>

    <h2>6. Seus direitos como titular (art. 18 da LGPD) e Exclusão de Conta</h2>
    <p>Você pode, a qualquer momento e sem custo, confirmar, acessar, corrigir, exportar uma cópia dos seus dados, rever consentimentos ou solicitar a <strong>exclusão da sua conta</strong>.</p>
    <p><strong>Como exercer no próprio aplicativo:</strong> Vá em <strong>Perfil → Meus dados (LGPD)</strong>. Nessa tela você consulta e altera seus consentimentos, solicita a <strong>exportação dos seus dados</strong> e pode pedir a <strong>exclusão da sua conta</strong> com confirmação imediata. Se preferir, envie um e-mail para <code>privacidade@trato.app.br</code>.</p>
  </main>
  <footer>
    © 2026 Feito Labs Tecnologia Ltda. · Belo Horizonte/MG · suporte@trato.app.br
  </footer>
</body>
</html>
"""

HTML_TERMOS = f"""<!DOCTYPE html>
<html lang="pt-BR">
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1" />
  <title>Termos de Uso — Trato Feito</title>
  {_ESTILO_BASE}
</head>
<body>
  <header>
    <h1>Termos de Uso do Trato</h1>
    <p>Versão 1.0 · Vigência: 31/10/2026 · Feito Labs Tecnologia Ltda. (Belo Horizonte/MG)</p>
    <nav>
      <a href="/privacidade">Política de Privacidade</a>
      <a href="/termos">Termos de Uso</a>
    </nav>
  </header>
  <main>
    <h2>1. Quem somos e o que o Trato faz</h2>
    <p>O <strong>Trato</strong> é um aplicativo que aproxima <strong>clientes</strong> que precisam de um serviço doméstico e <strong>profissionais</strong> autônomos que executam esse serviço.</p>
    <p>O Trato intermedia o pedido, os orçamentos, a conversa, o pagamento, a prova de início e fim do serviço e a mediação de problemas. O Trato não executa o serviço e não é empregador dos profissionais: cada profissional atua por conta própria e define seu preço, seu prazo e sua garantia.</p>

    <h2>2. Quem pode usar</h2>
    <ul>
      <li>Ter <strong>18 anos ou mais</strong>;</li>
      <li>Informar dados verdadeiros (nome, CPF, data de nascimento, celular e e-mail);</li>
      <li>Manter apenas uma conta por pessoa.</li>
    </ul>

    <h2>3. Como funciona um pedido</h2>
    <ol>
      <li><strong>Pedido:</strong> O cliente descreve o que precisa, escolhe a categoria, informa o endereço e pode anexar fotos. Pedir orçamento é gratuito.</li>
      <li><strong>Orçamentos:</strong> Profissionais da categoria e da região enviam orçamentos com valor, prazo, validade, garantia e o que está ou não incluído.</li>
      <li><strong>Escolha e pagamento:</strong> O cliente compara e aceita um orçamento. O pagamento é feito dentro do aplicativo, por <strong>Pix</strong> ou <strong>cartão de crédito</strong>, processado por parceiro de pagamento autorizado pelo Banco Central (<strong>Stripe Brasil Soluções de Pagamento Ltda.</strong>). O valor pago fica vinculado ao pedido no parceiro de pagamento até a conclusão.</li>
      <li><strong>Agendamento e código de início:</strong> Com o pagamento confirmado, o endereço completo é liberado ao profissional contratado e o cliente recebe um código de início.</li>
      <li><strong>Execução:</strong> Ao chegar, o profissional registra presença no aplicativo (foto e localização) e informa o código de início dito pelo cliente. Ao terminar, registra a conclusão com foto e o código final.</li>
      <li><strong>Confirmação e liberação:</strong> O cliente confirma que o serviço foi concluído (ou o prazo de <strong>48 horas</strong> após o check-out se encerra sem relato de problema). Após a janela de proteção de <strong>7 dias</strong> sem reclamação aberta, o parceiro de pagamento libera o repasse ao profissional conforme as regras da categoria.</li>
    </ol>

    <h2>4. Preços, taxa da plataforma e materiais</h2>
    <ul>
      <li><strong>Quem define o preço do serviço é o profissional</strong>, no orçamento.</li>
      <li><strong>Taxa de serviço do Trato:</strong> calculada sobre o valor do orçamento (taxa base de <strong>7,5%</strong>, respeitado o mínimo de <strong>R$ 3,00</strong>, conforme a tabela progressiva vigente no momento do aceite). A taxa e o valor líquido aparecem de forma clara antes de o profissional enviar o orçamento e antes de o cliente pagar.</li>
      <li><strong>Aditivos:</strong> qualquer trabalho extra deve ser registrado como aditivo no aplicativo e aprovado pelo cliente antes da execução.</li>
      <li><strong>Materiais:</strong> quando o orçamento prevê compra de materiais pelo profissional, ele deve anexar a nota fiscal ou comprovante no aplicativo.</li>
    </ul>

    <h2>5. Cancelamento e desistência</h2>
    <ul>
      <li><strong>Antes de aceitar um orçamento:</strong> cancelamento gratuito a qualquer momento.</li>
      <li><strong>Depois do pagamento e antes do início do serviço:</strong> estorno pelo meio de pagamento usado, descontados apenas eventuais custos comprovados já incorridos.</li>
      <li><strong>Direito de arrependimento (art. 49 do CDC):</strong> prazo legal de 7 dias a contar da contratação, quando o serviço ainda não tiver sido integralmente executado.</li>
    </ul>

    <h2>6. Garantia, problemas e disputas</h2>
    <ul>
      <li>Todo serviço conta com a garantia legal do Código de Defesa do Consumidor (art. 26) e com o prazo de garantia informado pelo profissional no orçamento.</li>
      <li>Se algo saiu diferente do combinado, o cliente pode abrir um relato no aplicativo. Enquanto o relato é analisado, a liberação do valor fica suspensa no parceiro de pagamento.</li>
      <li>O profissional tem até <strong>48 horas</strong> para responder e propor solução (retrabalho sem custo ou reembolso parcial/total).</li>
    </ul>

    <h2>7. Contato e Foro</h2>
    <p>Dúvidas ou solicitações: Central de ajuda no aplicativo ou pelo e-mail <code>suporte@trato.app.br</code>. Foro eleito: domicílio do consumidor ou Comarca de <strong>Belo Horizonte/MG</strong>.</p>
  </main>
  <footer>
    © 2026 Feito Labs Tecnologia Ltda. · Belo Horizonte/MG · suporte@trato.app.br
  </footer>
</body>
</html>
"""


HTML_EMAIL_CONFIRMADO = f"""<!DOCTYPE html>
<html lang="pt-BR">
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1" />
  <title>E-mail Confirmado — Trato Feito</title>
  {_ESTILO_BASE}
  <style>
    .caixa-sucesso {{
      text-align: center;
      padding: 40px 24px;
    }}
    .icone-ok {{
      display: inline-flex;
      width: 64px;
      height: 64px;
      border-radius: 50%;
      background-color: var(--petroleo);
      color: var(--creme);
      align-items: center;
      justify-content: center;
      font-size: 32px;
      margin-bottom: 16px;
    }}
    .botao-app {{
      display: inline-block;
      margin-top: 20px;
      background-color: var(--laranja);
      color: #FFFFFF;
      text-decoration: none;
      font-weight: 600;
      padding: 14px 28px;
      border-radius: 999px;
    }}
  </style>
</head>
<body>
  <header>
    <h1>Trato Feito</h1>
    <p>Serviços residenciais com segurança e transparência</p>
  </header>
  <main class="caixa-sucesso">
    <div class="icone-ok">✓</div>
    <h2>E-mail confirmado com sucesso!</h2>
    <p>Sua conta no <strong>Trato</strong> já está ativa e pronta para uso.</p>
    <p>Volte para o aplicativo no seu celular e toque em <strong>"Já confirmei"</strong> ou faça login normalmente.</p>
    <a class="botao-app" href="br.com.feitolabs.trato://login-callback">Abrir o aplicativo Trato</a>
  </main>
  <footer>
    © 2026 Feito Labs Tecnologia Ltda. · Belo Horizonte/MG · suporte@trato.app.br
  </footer>
</body>
</html>
"""


@router.get("/", response_class=HTMLResponse, include_in_schema=False)
@router.get("/email-confirmado", response_class=HTMLResponse, include_in_schema=False)
def pagina_email_confirmado() -> HTMLResponse:
    return HTMLResponse(content=HTML_EMAIL_CONFIRMADO, status_code=200)


@router.get("/privacidade", response_class=HTMLResponse, include_in_schema=False)
def pagina_privacidade() -> HTMLResponse:
    return HTMLResponse(content=HTML_PRIVACIDADE, status_code=200)


@router.get("/termos", response_class=HTMLResponse, include_in_schema=False)
def pagina_termos() -> HTMLResponse:
    return HTMLResponse(content=HTML_TERMOS, status_code=200)
