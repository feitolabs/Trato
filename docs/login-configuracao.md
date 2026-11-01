# Login real: o que o João precisa configurar

O app já tem o login pronto (`app/lib/auth/`), mas **roda no modo de teste (fake)** enquanto não houver chaves. Este guia liga o login ao Supabase de verdade. Decisão: D16 (e-mail com senha, Google e Apple; **sem SMS no piloto**, o cadastro confirma por link no e-mail).

Regra de ouro: **nunca** coloque senha, chave ou token no código nem no chat. Tudo vai em arquivo `.env` (que o Git ignora).

## 1. O que existe no código

| Peça | Para quê |
|---|---|
| `ServicoAuth` | Interface única: entrar, criar conta, Google, Apple, sair, recuperar senha, sessão, reenviar e-mail de confirmação |
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
- Rodar: `flutter run --dart-define-from-file=dart-defines.json` (dentro de `app/`). Também vale `--dart-define=SUPABASE_URL=...` um a um.
- Sem os valores, o app abre normalmente com o login de teste.

## 3. Painel do Supabase (projeto "Trato")

Painel: Authentication.

1. **URL e chave pública:** Project Settings → API. Copie "Project URL" e a chave "anon / publishable".
2. **E-mail com senha:** Authentication → Sign In / Providers → Email → ligado.
   - "Confirm email": **ligado** (é o caso real). O cadastro não abre sessão; o app mostra "Confirme seu e-mail" e a pessoa abre o link no celular. Se desligar, o cadastro entra direto (o app trata os dois casos).
   - Senha mínima: 8 caracteres (igual ao app).
   - **Modelo do e-mail em português:** Authentication → Email Templates → "Confirm signup". Sugestão: assunto `Confirme seu e-mail no Trato`; corpo: `Olá! Toque no link para confirmar seu e-mail e entrar no Trato: <a href="{{ .ConfirmationURL }}">Confirmar e-mail</a>. Se você não criou uma conta, ignore esta mensagem.` Faça o mesmo para "Reset password" (`Redefinir senha`).
   - **Limites do e-mail padrão do Supabase (só para teste):** o servidor de e-mail embutido manda pouquíssimos e-mails por hora (hoje na casa de 2 por hora no projeto, e só para membros da equipe do projeto). Estourou: o app mostra "Muitos e-mails enviados..." (`over_email_send_rate_limit`). Para testar, use poucos cadastros ou convide o e-mail como membro da organização.
   - **Produção:** configure **SMTP próprio** em Authentication → Emails → SMTP Settings (Resend, SendGrid, Amazon SES etc.), com remetente do domínio do Trato. Isso gasta dinheiro/DNS de verdade: peça o OK antes.
3. **Deep link e recuperar senha:** Authentication → URL Configuration. Em "Redirect URLs" adicione **`br.com.feitolabs.trato://login-callback`** (o link de confirmação do e-mail abre o app por ele; já está no `AndroidManifest.xml` e no `Info.plist`). Defina também a "Site URL" (uma página pública simples, pois a "Site URL" é o destino se o link não puder abrir o app). Ainda falta a tela de "criar senha nova" quando o link abrir o app.
4. **Google:** Providers → Google → ligar. Colar o **Web Client ID** e o **Client Secret** (passo 4 abaixo). Marcar "Skip nonce check" só se o login nativo reclamar de nonce.
5. **Apple:** Providers → Apple → ligar. Em "Client IDs" coloque o **Bundle ID** do app iOS (login nativo). Para o login no Android/web seria preciso também Services ID e chave, mas a decisão atual é Apple só no iOS.
6. **Celular (SMS):** deixe **desligado** (Providers → Phone). O celular digitado no cadastro vai só como metadado do usuário (`celular`), sem confirmação.
7. **Limites de envio:** Authentication → Rate Limits. O reenvio do e-mail de confirmação espera 60 s no app.

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

## 6. SMS: desligado no piloto (D16)

Não há confirmação por SMS. A tela antiga (`ConfirmarCelularTela`) e o código no `ServicoAuth` continuam no app, desligados pela constante `kConfirmarCelularPorSms = false` (`app/lib/auth/servico_auth.dart`). Se um dia voltar, será preciso: escolher o provedor (P11), o Send SMS Hook, CAPTCHA, e reativar o `updateUser(phone)` depois do primeiro login (com sessão).

## 7. Testar com o Supabase de verdade

Com URL, chave pública e e-mail ligados você já testa: criar conta → abrir o link do e-mail → "Já confirmei" → entrar, sair, recuperar senha. Google precisa do passo 4. Apple precisa de Mac e conta paga.

Sempre use contas de teste. No modo `demo` o app só conversa com o Supabase Auth; no modo `api` ele
confere o CPF antes do `signUp` e grava o CPF no backend no primeiro login.

## 8. O que o login ainda não faz

- CPF e data de nascimento são validados na tela e **não** vão para o Supabase Auth (dado sensível). O CPF vai
  ao backend (`POST /v1/cadastro/cpf` antes do `signUp` e `POST /v1/me/dados-pessoais` no primeiro login); a
  data de nascimento ainda não é enviada.
- Login por CPF ou telefone: hoje só e-mail.
- Biometria: continua "em breve".
- O primeiro login com sessão chama `GET /v1/me` (cria o usuário no backend) só no modo `api`; em `demo` não chama nada.
- Guardar o perfil escolhido (cliente/profissional) e tela de nova senha: pendentes.
