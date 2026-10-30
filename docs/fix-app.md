# Correções do app e do painel (revisão de segurança)

Origem: `docs/revisao-seguranca.md` (M8, M13, M14 e baixos de app/painel).

## Feito

| Item | O que mudou |
|---|---|
| **M13** sessão | `app/lib/auth/armazenamento_sessao.dart`: `LocalStorageSeguro` entrega a sessão do Supabase ao `flutter_secure_storage` 9.2.4 (versão fixa; Keychain no iOS, Keystore no Android). Na primeira abertura migra a sessão que estava em `SharedPreferences` e **apaga** o valor antigo. `ArmazenamentoSessaoMemoria` serve de fake nos testes. |
| **M13** Android | `allowBackup="false"`, `fullBackupContent` e `dataExtractionRules` (excluem tudo), `usesCleartextTraffic="false"`, `minSdk 23` (exigência do Keystore). Para API local em http no emulador, use um manifesto de debug próprio. |
| **M14** lista permitida | `app/lib/dados/defines_publicos.dart` (e cópia `admin/lib/dados/defines_publicos.dart`): só `TRATO_MODO`, `TRATO_API_URL`, `SUPABASE_URL`, `SUPABASE_ANON_KEY`, IDs públicos do Google (painel: `ADMIN_*`). Em **debug** o app/painel para com erro (só o nome da variável aparece); em **release** ignora a variável. Também barra chave anon que na verdade é JWT `service_role`, `sk_`/`whsec_`. |
| **M14** verificador | `harness/verificar_defines.py`, chamado por `verificar.py` (etapa `segredos`): falha se algum arquivo versionado apontar `--dart-define-from-file` para um `.env`, ou usar arquivo/`--dart-define` com chave fora da lista ou com nome de segredo. `docs/BUILD.md`, `docs/login-configuracao.md` e `.env.example` atualizados (só nomes). |
| **M8** EXIF | `garantirSemMetadados` em `ServicoUploadApi.enviar`: qualquer foto que chegue com EXIF/XMP/IPTC (ou que não seja JPEG) é recodificada antes do PUT. Teste com JPEG com GPS. |
| 401 | `ClienteApi` limpa a sessão (`SessaoTrato.expirar`), encerra o login guardado e abre `LoginTela(sessaoExpirada: true)` **por cima** da tela atual (push): o que a pessoa digitou continua lá embaixo e volta após entrar. O aviso é `liveRegion` (leitor de tela anuncia). |
| Baixos já ok | Sem `print`/log com dado pessoal em `app/lib` e `admin/lib`; sem deep link/intent-filter além do launcher; permissões do manifesto só INTERNET, câmera e localização "em uso"; painel guarda o token só em memória, `sair()` limpa token e ids, 401 também limpa. |

## Pendente (não resolvido aqui)

1. **Backend deve revalidar a imagem** quando existir a rota `/v1/arquivos/url-envio` (hoje 404): descartar EXIF, reencodar, conferir tipo/tamanho/sha256 e só então gravar em `midias`. O app não é fronteira de confiança (M8 continua aberto no servidor).
2. Painel (Flutter Web): o token fica em memória, então recarregar a página desloga (decisão de segurança). Falta cabeçalhos de segurança (CSP, `X-Frame-Options`) no host do painel e CSP sem `unsafe-inline`.
3. iOS: conferir `Info.plist` completo (ATS, `NSPhotoLibrary…`), `Keychain` com `first_unlock_this_device` ligado, e nonce do login Google.
4. Ofuscação (`--obfuscate --split-debug-info`) e ProGuard/R8 no release; assinatura com `key.properties`.
5. `usesCleartextTraffic=false` bloqueia API em http no Android; para dev local crie `android/app/src/debug/AndroidManifest.xml` com `tools:replace` (não feito).
6. Teste em aparelho real da migração de sessão e do Keystore (testes automáticos usam fakes).
7. Recuperar o que foi digitado cobre telas empilhadas; formulários que fecham a tela inteira antes do 401 não têm rascunho persistido.
