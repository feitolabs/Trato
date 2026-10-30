# Build do app Trato (Android e iOS)

Passo a passo para gerar o app. **Nada aqui assina, publica ou envia nada sozinho.** Chaves de assinatura são geradas pelo João e nunca entram no repositório.

Identidade do app (já configurada):

| Item | Valor | Onde |
|---|---|---|
| Nome na tela | `Trato` | `android:label` no `AndroidManifest.xml`; `CFBundleDisplayName` no `Info.plist` |
| Android `applicationId` | `br.com.feitolabs.trato` | `app/android/app/build.gradle.kts` |
| iOS Bundle ID | `br.com.feitolabs.trato` | `app/ios/Runner.xcodeproj/project.pbxproj` |
| Versão | `0.1.0+1` (nome+número) | `app/pubspec.yaml` (`version:`) |
| Flutter | 3.47.8 (stable) | o mesmo no CI (`.github/workflows/*.yml`) |

## 1. Variáveis de build (`--dart-define`)

O app **não lê `.env`**. Os valores entram na compilação com `--dart-define` (ou `--dart-define-from-file`). Tudo é opcional: sem nada, o app abre em modo demo.

| Variável | Para quê | Exemplo de uso |
|---|---|---|
| `TRATO_MODO` | `demo` (padrão, dados de exemplo, sem rede) ou `api` | `--dart-define=TRATO_MODO=api` |
| `TRATO_API_URL` | Endereço base do backend. Só vale com `TRATO_MODO=api`; sem ela o modo `api` cai em `demo` | `--dart-define=TRATO_API_URL=https://api.exemplo.com.br` |
| `SUPABASE_URL` | URL do projeto Supabase "Trato" (liga o login real) | `--dart-define=SUPABASE_URL=...` |
| `SUPABASE_ANON_KEY` | Chave **pública** (anon/publishable). Nunca a `service_role` | `--dart-define=SUPABASE_ANON_KEY=...` |
| `GOOGLE_WEB_CLIENT_ID`, `GOOGLE_IOS_CLIENT_ID` | Login com Google (opcional; ver `docs/login-configuracao.md`) | idem |
| `GALERIA` | `true` abre a galeria de componentes (só desenvolvimento) | `--dart-define=GALERIA=true` |

Receita sem digitar valores na linha de comando: crie `app/dart-defines.json` (**ignorado pelo git**: não commitar; copie os nomes de `.env.example`):

```json
{
  "TRATO_MODO": "api",
  "TRATO_API_URL": "",
  "SUPABASE_URL": "",
  "SUPABASE_ANON_KEY": ""
}
```

```bash
flutter run --dart-define-from-file=dart-defines.json
```

> Atenção: tudo que vai em `--dart-define` fica dentro do aplicativo e pode ser extraído por quem tiver o APK/IPA. Por isso só cabem **valores públicos** (URL da API, chave anon). Segredos (Stripe, `service_role`, `DATABASE_URL`) ficam **só no backend**.

### Lista permitida (M14)

Só estas variáveis podem entrar no app: `TRATO_MODO`, `TRATO_API_URL`, `SUPABASE_URL`, `SUPABASE_ANON_KEY`, `GOOGLE_WEB_CLIENT_ID`, `GOOGLE_IOS_CLIENT_ID` (e `GALERIA`, só desenvolvimento). No painel: `ADMIN_MODO`, `ADMIN_API_URL`, `ADMIN_SUPABASE_URL`, `ADMIN_SUPABASE_ANON_KEY`.

- **Nunca** aponte `--dart-define-from-file` para o `.env` da raiz (tem `service_role`, `DATABASE_URL`, Stripe).
- No código (`app/lib/dados/defines_publicos.dart`): em **debug** o app para com erro se achar variável com cara de segredo (`service_role`, `secret`, `sk_`, `JWT_SECRET`, `DATABASE_URL`, ou uma chave anon que na verdade é `service_role`); em **release** ela é ignorada.
- `python harness/verificar.py --etapa segredos` roda `harness/verificar_defines.py`: falha se qualquer arquivo versionado apontar o `--dart-define-from-file` para um `.env` ou usar um arquivo de defines com chave proibida.

O `.gitignore` do projeto já ignora `dart-defines*.json`, `.env*`, `key.properties`, `*.jks`, `*.keystore`, `*.p12` e `*.mobileprovision`.

## 2. Android

### Pré-requisitos
Flutter 3.47.8, Android Studio com SDK e licenças aceitas (`flutter doctor --android-licenses`), JDK 17 (vem com o Android Studio). Confira com `flutter doctor`.

### Debug (testar no celular ou emulador)

```bash
cd app
flutter pub get
flutter build apk --debug --dart-define=TRATO_MODO=demo
```

Saída: `app/build/app/outputs/flutter-apk/app-debug.apk`. Instalar no aparelho ligado por USB: `flutter install`.

### Release sem loja (APK de teste interno)
Sem keystore o release é assinado com a chave **debug** (o `build.gradle.kts` faz isso sozinho). Serve só para testar localmente, **não** serve para a Play Store.

```bash
flutter build apk --release --dart-define-from-file=dart-defines.json
```

### Release assinado (APK ou AAB para a Play Store)

**1. O João gera a keystore (uma vez, guarda em lugar seguro, fora do repositório).** Se perder, não dá para atualizar o app na loja.

```bash
keytool -genkey -v -keystore "$HOME/trato-upload.jks" -keyalg RSA -keysize 2048 -validity 10000 -alias trato-upload
```

**2. Crie `app/android/key.properties`** (já ignorado pelo git; **nunca** commitar nem colar no chat):

```properties
storePassword=<senha da keystore>
keyPassword=<senha da chave>
keyAlias=trato-upload
storeFile=C:/caminho/seguro/trato-upload.jks
```

**3. Gere:**

```bash
flutter build appbundle --release --dart-define-from-file=dart-defines.json
```

Saída: `app/build/app/outputs/bundle/release/app-release.aab` (envie à Play Console). Para APK assinado: `flutter build apk --release ...`.

O `build.gradle.kts` usa o `key.properties` se ele existir; se não existir, volta à chave debug. Confira antes de enviar: `keytool -printcert -jarfile app-release.apk` não pode mostrar "Android Debug".

**4. Aumente a versão a cada envio** em `app/pubspec.yaml` (`version: 0.1.0+2`): o número depois do `+` precisa crescer a cada upload.

### Permissões declaradas (`AndroidManifest.xml`)
- `INTERNET`: API e Supabase (o manifest de release não tinha; o de debug já).
- `CAMERA`, `ACCESS_FINE_LOCATION`, `ACCESS_COARSE_LOCATION`: check-in/check-out com foto e localização (escopo). Hoje o app **ainda não usa plugin de câmera/localização**: a declaração fica pronta, e o sistema só pergunta ao usuário quando o recurso for usado. Se a primeira versão da loja sair sem esses recursos, **remova** as três linhas para não gerar pergunta na revisão da Play Store.

### Ícone
Os ícones atuais em `app/android/app/src/main/res/mipmap-*/ic_launcher.png` e `app/ios/Runner/Assets.xcassets/AppIcon.appiconset/` são os padrão do Flutter. Falta o ícone final do Trato (arte 1024×1024 sem transparência, vinda do design). Quando existir, o jeito mais simples é o pacote `flutter_launcher_icons` (acrescenta dependência ao `pubspec.yaml`, por isso não foi feito aqui).

## 3. iOS (sem Mac local: build na nuvem)

iOS só compila em macOS com Xcode. Duas opções, ambas na nuvem. **Nenhuma foi executada ainda.**

### O que o João precisa providenciar (vale para as duas)
1. **Conta Apple Developer** (US$ 99/ano, Apple Developer Program), de pessoa jurídica ou física.
2. **Bundle ID** `br.com.feitolabs.trato` registrado em *Certificates, Identifiers & Profiles > Identifiers* (capabilities: "Sign in with Apple" se for usar o login Apple, que o app já prevê).
3. **App** criado no App Store Connect (nome "Trato", Bundle ID acima, idioma pt-BR).
4. **Chave de API do App Store Connect** (Users and Access > Integrations > App Store Connect API > gerar chave com papel *App Manager*): dá `Issuer ID`, `Key ID` e o arquivo `.p8`. Com ela, a nuvem cria sozinha certificados e perfis, sem o João exportar nada do Mac.
5. Time (Team ID) de 10 caracteres, em *Membership details*.

Segredos (arquivo `.p8`, certificados, senhas) são cadastrados **no painel do serviço de CI**, nunca no repositório nem no chat.

### Opção A: Codemagic (recomendada para iOS sem Mac)
Tem Mac na nuvem e assinatura automática. Plano gratuito cobre uso pequeno.
1. Em codemagic.io, conectar a conta do GitHub e escolher o repositório `feitolabs/Trato`.
2. Em *Teams > Integrations*, adicionar a chave do App Store Connect (Issuer ID, Key ID, `.p8`).
3. Criar o workflow (no editor do Codemagic, ou um `codemagic.yaml` na raiz; o João decide). Pontos que importam: diretório de trabalho `app`, Flutter `3.47.8`, assinatura iOS automática com o Bundle ID `br.com.feitolabs.trato`, comando de build:
   ```bash
   flutter build ipa --release --dart-define-from-file=dart-defines.json
   ```
   (no Codemagic, os valores entram como variáveis de ambiente do painel e o arquivo é gerado no script), publicação opcional no TestFlight.
4. Rodar o build e instalar pelo TestFlight.

### Opção B: GitHub Actions em macOS
O repositório já tem `.github/workflows/build.yml` (manual) que compila o iOS **sem assinatura** (`flutter build ios --release --no-codesign`). Serve para provar que o código compila no macOS, mas **não gera IPA instalável**. Para IPA assinado no Actions, é preciso configurar certificado de distribuição e perfil de provisionamento como *secrets* e um passo de assinatura (ou fastlane `match`); é mais trabalhoso que o Codemagic. Nomes de secrets a cadastrar, se escolher este caminho (nenhum valor no repositório): `IOS_CERT_P12`, `IOS_CERT_PASSWORD`, `IOS_PROVISIONING_PROFILE`, `APPSTORE_ISSUER_ID`, `APPSTORE_KEY_ID`, `APPSTORE_PRIVATE_KEY`.

### Permissões iOS (`Info.plist`)
Textos em português já escritos: `NSCameraUsageDescription` (fotos de início e fim), `NSLocationWhenInUseUsageDescription` (chegada ao local), `NSPhotoLibraryUsageDescription` (anexos). Valem quando os plugins forem adotados; sem uso, a Apple pode questionar na revisão.

### Antes de submeter
- Login com Apple: a Apple exige "Entrar com Apple" quando há login com Google (diretriz 4.8). O app já usa `sign_in_with_apple`; falta ativar a capability no Xcode/Apple Developer.
- Política de privacidade com endereço público e página de exclusão de conta (LGPD): obrigatórias nas duas lojas.
- Textos de loja: seguir a D13 (sem "escrow", "garantia total", "24/7" etc.).

## 4. Flavors (dev / homologação / produção)

Ainda **não há flavors nativos** (Gradle `productFlavors` / esquemas Xcode). Hoje a diferença entre ambientes é só o `--dart-define`: um arquivo por ambiente (`dart-defines.dev.json`, `dart-defines.hml.json`, `dart-defines.prod.json`, todos ignorados pelo git) com URL da API e projeto Supabase diferentes. Se for preciso instalar dev e produção no mesmo aparelho ao mesmo tempo (apps com ícone/ID diferentes), aí sim se cria flavor: decisão para depois do piloto.

## 5. Conferências antes de entregar um build
- `python harness/verificar.py` passa.
- `git status` sem `key.properties`, `.jks`, `.p12`, `dart-defines*.json`.
- O APK/AAB de release **não** mostra "Android Debug" no certificado.
- O app abre no aparelho real e mostra o nome "Trato".

## 6. CI: goldens, regeneração e consulta ao Actions

**Por que o golden é ignorado no CI.** Os 166 testes golden (`app/test/golden/`) comparam pixel a pixel com PNGs gerados no Windows. O runner Ubuntu rasteriza o texto de outro jeito, então todos falhavam lá (166 falhas no run 41081706382; no Windows os 638 passam). Por isso o job "App (Flutter)" define `TRATO_GOLDEN=ignorar`. Isso é tratado em `app/test/flutter_test_config.dart`: a imagem continua sendo gerada e comparada, a diferença só vira a linha `GOLDEN IGNORADO` no log, e **arquivo de referência ausente continua falhando**. Sem a variável (seu Windows, `python harness/verificar.py`) a comparação é exata, como sempre.

**Regenerar goldens** (depois de mudar uma tela de propósito, no Windows):

```bash
cd app
flutter test --update-goldens test/golden
```

Confira o diff das imagens no git antes de commitar.

**Ver o resultado do Actions sem login.** Na aba Actions, abra o run e a página de resumo: o passo do app escreve em `$GITHUB_STEP_SUMMARY` os nomes dos testes que falharam e os 30 primeiros erros. Pela API pública, sem token:

```bash
curl -s https://api.github.com/repos/feitolabs/Trato/actions/runs/<ID>/jobs
```

O CI roda `flutter test --reporter expanded` (via `harness/verificar.py --etapa app`), então o log mostra cada teste.
