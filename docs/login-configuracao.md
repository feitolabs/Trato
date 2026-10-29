# Login real: o que o João precisa configurar

O app já tem o login pronto (`app/lib/auth/`), mas **roda no modo de teste (fake)** enquanto não houver chaves. Este guia liga o login ao Supabase de verdade. Decisão: D14 (e-mail com senha, Google e Apple; SMS só na confirmação do celular).

Regra de ouro: **nunca** coloque senha, chave ou token no código nem no chat. Tudo vai em arquivo `.env` (que o Git ignora).

## 1. O que existe no código

| Peça | Para quê |
|---|---|
| `ServicoAuth` | Interface única: entrar, criar conta, Google, Apple, sair, recuperar senha, sessão, confirmar celular |
| `ServicoAuthFake` | Em memória. Usado nos testes e quando não há chaves |
| `ServicoAuthSupabase` | Supabase Auth de verdade |
| `ConfigAuth` | Lê `SUPABASE_URL`, `SUPABASE_ANON_KEY`, `GOOGLE_WEB_CLIENT_ID`, `GOOGLE_IOS_CLIENT_ID` |
| `ServicoAuthPadrao.atual` | Serviço que as telas usam quando ninguém passa um. Começa no fake |

**Falta uma ligação no `main.dart`** (arquivo travado para esta tarefa): quando `ConfigAuth.doAmbiente().supabaseConfigurado` for verdadeiro, chamar `ServicoAuthPadrao.atual = await ServicoAuthSupabase.inicializar(config)` antes de `runApp`. É uma tarefa de 5 linhas para quem for dono do `main.dart`.

## 2. Arquivo `.env` do app

Crie `app/.env` (fica fora do Git) com **só** estes quatro nomes e os valores que você pegar nos passos abaixo:

```
SUPABASE_URL=
SUPABASE_ANON_KEY=
GOOGLE_WEB_CLIENT_ID=
GOOGLE_IOS_CLIENT_ID=
```

- `SUPABASE_ANON_KEY` é a chave **pública** (anon / publishable). **Nunca** use a `service_role` aqui: ela dá acesso total ao banco.
- Rodar: `flutter run --dart-define-from-file=.env` (dentro de `app/`). Também vale `--dart-define=SUPABASE_URL=...` um a um.
- Sem os valores, o app abre normalmente com o login de teste.

## 3. Painel do Supabase (projeto "Trato")

Painel: Authentication.

1. **URL e chave pública:** Project Settings → API. Copie "Project URL" e a chave "anon / publishable".
2. **E-mail com senha:** Authentication → Sign In / Providers → Email → ligado.
   - "Confirm email": se ligado, a pessoa precisa clicar no e-mail antes de ter sessão, e o código de SMS **não** poderá ser pedido logo após o cadastro. Para o fluxo atual (cadastro → SMS), **desligue** "Confirm email" no começo ou combine com o time uma tela "confirme seu e-mail".
   - Senha mínima: 8 caracteres (igual ao app).
3. **Recuperar senha:** Authentication → URL Configuration. Defina a "Site URL" e a lista "Redirect URLs" (o link do e-mail abre o app/página). Ainda falta a tela de "criar senha nova" quando o link abrir o app.
4. **Google:** Providers → Google → ligar. Colar o **Web Client ID** e o **Client Secret** (passo 4 abaixo). Marcar "Skip nonce check" só se o login nativo reclamar de nonce.
5. **Apple:** Providers → Apple → ligar. Em "Client IDs" coloque o **Bundle ID** do app iOS (login nativo). Para o login no Android/web seria preciso também Services ID e chave, mas a decisão atual é Apple só no iOS.
6. **Celular (SMS):** Providers → Phone → ligado, com o provedor de SMS definido (passo 6).
7. **CAPTCHA antes do envio de SMS (D14):** Authentication → Attack Protection → CAPTCHA (hCaptcha ou Turnstile). O app ainda não mostra o CAPTCHA: é pendência da tela de confirmar celular.
8. **Limites de envio:** Authentication → Rate Limits. Ajuste "SMS sent per hour" para um número baixo. O app limita 5 tentativas de código e 3 reenvios, 60 s entre reenvios.

## 4. Google Cloud (client IDs)

1. https://console.cloud.google.com → criar projeto "Trato" (ou usar um existente).
2. APIs & Services → OAuth consent screen: nome do app, e-mail de suporte, domínio. Em teste, adicione os e-mails de teste.
3. Credentials → Create credentials → OAuth client ID, **três** vezes:
   - **Web application** → este é o `GOOGLE_WEB_CLIENT_ID`. Em "Authorized redirect URIs" coloque `https://<seu-projeto>.supabase.co/auth/v1/callback`. O Client ID e o Secret deste também vão no painel do Supabase (passo 3.4).
   - **iOS** → informe o Bundle ID. É o `GOOGLE_IOS_CLIENT_ID`. No `ios/Runner/Info.plist` será preciso adicionar o "reversed client ID" como URL scheme (ajuste de projeto iOS, feito quando houver Mac).
   - **Android** → informe o nome do pacote e o SHA-1 da chave de assinatura (`./gradlew signingReport`). Não gera variável: só precisa existir.
4. O botão "Entrar com Google" só aparece quando `GOOGLE_WEB_CLIENT_ID` está preenchido.

## 5. Apple (só iOS)

- Conta **Apple Developer** paga (US$ 99/ano).
- Um **Mac com Xcode** para compilar o app iOS, ligar a capability "Sign in with Apple" no target e assinar.
- No portal Apple: App ID (Bundle ID) com "Sign in with Apple" ligado.
- O botão "Entrar com Apple" só aparece em iOS. No Android e nos testes ele fica escondido.
- A Apple exige o botão quando há login com Google no iOS (regra 4.8 da App Store): por isso os dois andam juntos.

## 6. SMS: o que fica pendente (P11)

O código por SMS vai pelo Supabase Auth, mas **o provedor de SMS ainda não foi escolhido** (P11: Zenvia ou Comtele, via "Send SMS Hook"). Enquanto isso:

- O app já pede o código, limita tentativas e reenvios e mostra os erros.
- Com o Phone ligado e sem provedor, o Supabase devolve erro ao enviar: o app mostra "Este tipo de entrada ainda não está disponível." na criação da conta.
- Falta: escolher o provedor, criar a conta dele, e fazer o **Send SMS Hook** (função no Supabase ou endpoint no backend) que recebe o código e chama a API do provedor. Isso gasta dinheiro de verdade e pede o seu OK.
- Falta também o CAPTCHA (passo 3.7).
- WhatsApp fica para a V1 (o botão continua "em breve").

## 7. Testar com o Supabase de verdade

Com URL, chave pública e e-mail ligados você já testa: criar conta, entrar, sair, recuperar senha. Google precisa do passo 4. SMS precisa do passo 6. Apple precisa de Mac e conta paga.

Sempre use contas de teste. Não grave dados no banco por aqui: o app só conversa com o Supabase Auth.

## 8. O que o login ainda não faz

- CPF e data de nascimento são validados na tela, mas **não** vão para o Supabase Auth (dado sensível). Devem ir ao perfil pelo backend.
- Login por CPF ou telefone: hoje só e-mail.
- Biometria: continua "em breve".
- Guardar o perfil escolhido (cliente/profissional) e tela de nova senha: pendentes.
