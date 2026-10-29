# App: câmera, GPS e envio de arquivos

Câmera e GPS reais ficam atrás de interfaces em `app/lib/dispositivo/`. Cada uma tem um fake para teste
e demonstração. **O app só captura e envia. A hora, a distância e a validação da prova são do servidor.**

## O que existe

| Peça | Arquivo | Real | Fake |
|---|---|---|---|
| Câmera e galeria (compressão, sem EXIF, SHA-256) | `dispositivo/servico_camera.dart` | `servico_camera_real.dart` (`image_picker`) | `ServicoCameraFake` |
| Tratamento da imagem | `dispositivo/preparador_imagem.dart` | `PreparadorImagem` (pacote `image`, `crypto`) | — |
| GPS (posição, precisão, distância) | `dispositivo/servico_localizacao.dart` | `servico_localizacao_real.dart` (`geolocator`) | `ServicoLocalizacaoFake` |
| Permissões | `dispositivo/permissao.dart` | `ServicoPermissaoReal` (`permission_handler`) | `ServicoPermissaoFake` |
| Tela de explicação | `dispositivo/explicacao_permissao.dart` | `garantirPermissao(...)` | — |
| Foto + permissão + envio para as telas | `dispositivo/captura_foto.dart` | `CapturaFotoGuiada.capturar(...)` | — |
| Check-in/out no aparelho | `dispositivo/captura_check_in_dispositivo.dart` | `CapturaCheckInDispositivo` | — |
| Envio por URL assinada | `dados/servico_upload.dart` | `ServicoUploadApi` | `ServicoUploadFake` |
| Fila offline | `dados/fila_offline.dart` | `FilaOfflineMemoria` | — |
| Montagem | `dispositivo/servicos_dispositivo.dart` | `ServicosDispositivo.real(api)` | `ServicosDispositivo.fake()` |

Versões fixas (sem `^`): `image_picker 1.1.2`, `geolocator 13.0.2`, `permission_handler 11.3.1`, `image 4.3.0`.

### Tratamento da foto
`PreparadorImagem` aplica a rotação, reduz o lado maior a 1600 px, recodifica em JPEG (qualidade 80) e limpa o
EXIF. Isso tira a localização embutida na foto. O SHA-256 é do arquivo **já tratado**, que é o que vai para o
servidor. Roda em outra thread (`compute`).

### Permissões (LGPD)
- Só pedimos no momento do uso, nunca ao abrir o app.
- Antes do pedido do sistema, uma folha explica **para que serve** e **por quanto tempo guardamos**
  (`TextoPermissao`). Se a pessoa tocar em "Agora não", o sistema nem é chamado.
- "Negada para sempre" (ou restrita pelo sistema) não pergunta de novo: mostra "Permissão desligada" com botão
  **Abrir configurações**.
- Localização só **quando em uso**. Não existe permissão de segundo plano no app.
- Galeria não pede permissão de câmera (o seletor do sistema não precisa).
- Documento e selfie: sempre câmera (sem galeria). Selfie usa a câmera frontal.
- Android e iOS: permissões e textos mínimos em `AndroidManifest.xml` e `Info.plist`. Também entrou `INTERNET` no
  manifesto principal: antes só existia nos de debug e profile, e sem ela o app de produção não fala com a API.

## Telas ligadas

| Tela | Como liga |
|---|---|
| Check-in (`CheckInTela`) | `permissao:` pede câmera e localização na hora. Aviso "longe do endereço" acima de `avisoDistanciaMetros` (só dica; não bloqueia). `ResultadoInicio.guardadoOffline` mostra o aviso e **não** inicia o serviço. |
| Check-out (`CheckOutTela`, nova) | Foto final e código de conclusão. Mesmo tratamento de permissão e offline (`ResultadoFim.guardadoOffline`). |
| Verificação, cadastro, nota de materiais, evidência de disputa | Já recebiam `CapturarFoto`. Basta passar `() => dispositivo.fotos.capturar(context, FinalidadeArquivo.documento)` (ver exemplos abaixo). |
| Novo pedido (`NovoPedidoTela`) | Novo parâmetro `aoCapturarFoto`. As fotos aparecem como anexos e vão em `RascunhoPedido.fotos` (máx. 4 no total). |

### Convivência com `DispositivoTrato` (develop)
A sessão `app-pendencias` deixou uma primeira versão em `dispositivo.dart`, `dispositivo_real.dart` e
`check_in_dispositivo.dart` (`DispositivoTrato`, `ServicoCheckInDispositivo`), que `main.dart` e `rotas.dart`
usam hoje. Ela não tem explicação de permissão, compressão, remoção de EXIF, upload nem offline, e pede a
permissão direto ao plugin. Esta tarefa **não mexeu nela** (os dois arquivos de entrada estavam fora do escopo).
O que está nesta página é o substituto: `ServicosDispositivo` + `CapturaFotoGuiada` + `CapturaCheckInDispositivo`.
Quando o integrador trocar o `RotasTrato.dispositivo`, `dispositivo_real.dart` e `check_in_dispositivo.dart`
podem ser apagados.

### Ligação que falta no ponto de entrada
`main.dart`, `rotas.dart` e `componentes.dart` ficaram de fora desta tarefa (a sessão `app-pendencias` mexe neles).
Quem ligar faz:

```dart
final dispositivo = ServicosDispositivo.real(clienteApi); // modo api; em demo, ServicosDispositivo.fake()

// Verificação
VerificacaoTela(
  servico: ...,
  aoCapturarDocumento: () => dispositivo.fotos.capturar(
    context, FinalidadeArquivo.documento, textoCamera: TextoPermissao.cameraDocumento),
  aoCapturarSelfie: () => dispositivo.fotos.capturar(
    context, FinalidadeArquivo.selfie, frontal: true, textoCamera: TextoPermissao.cameraDocumento),
);
// Nota de materiais / cadastro / novo pedido: FinalidadeArquivo.notaMaterial / portfolio / fotoPedido,
// com permitirGaleria: true.

// Check-in e check-out
final fila = FilaOfflineMemoria(); // uma só para o app todo
RepositorioProfissionalApi(
  api,
  captura: CapturaCheckInDispositivo(
    camera: dispositivo.camera, localizacao: dispositivo.localizacao,
    upload: dispositivo.upload, pedidoId: id,
    destinoLatitude: ..., destinoLongitude: ...), // endereço liberado, se a API entregar
  upload: dispositivo.upload,
  fila: fila,
);
CheckInTela(servico: ..., permissao: dispositivo.permissao, ...);
CheckOutTela(servico: ServicoCheckOutApi(checkIn, captura), permissao: dispositivo.permissao, ...);
```
Ao abrir a tela do pedido, chamar `ServicoCheckInApi.reenviarPendentes()` para esvaziar a fila.

## Offline
- Sem internet na hora da foto: a foto fica no aparelho (`FotoCapturada.local`, sem `arquivoId`).
- Sem internet no envio do check-in/out: a ação vai para a `FilaOffline`; a tela diz que o serviço **só começa
  quando o Trato confirmar**.
- No reenvio, o app sobe a foto, manda a prova com `offline_capturada_em` (hora do aparelho em UTC, só como dica)
  e tira da fila. Recusa do backend (código errado, longe do local) também tira da fila: o app não decide.

## Depende do backend (TODO)
1. **`POST /v1/arquivos/url-envio` não existe.** `ServicoUploadApi` já está pronto contra este contrato proposto:
   - Pedido: `{finalidade, mime, tamanho_bytes, sha256, pedido_id?}` com `Idempotency-Key`.
   - Resposta: `{arquivo_id, url, cabecalhos?, caminho?}`. A `url` é de uso único e curta (minutos).
   - O app então faz `PUT url` com os bytes, **sem** o token da API.
   - O backend deve conferir tamanho máximo, `mime` e o SHA-256 depois do envio, e escolher o bucket privado e o
     prazo de guarda pela `finalidade` (`check_in`, `check_out`, `documento`, `selfie`, `nota_material`,
     `foto_pedido`, `evidencia_disputa`, `portfolio`).
   - Hoje isso devolve 404 e o app mostra "Esta função ainda não está disponível".
2. **`offline_capturada_em`** dentro de `prova` em `fazer_check_in` e `fazer_check_out`. A coluna existe no modelo
   de dados; a rota ainda não a lê (se o esquema recusar campo extra, o reenvio offline falha).
3. Verificação: `POST /v1/profissional/verificacao` espera `storage_path`; o app passa `arquivo_id`. Alinhar o
   que o `url-envio` devolve em `caminho`.
4. Fila offline **só em memória**: some se o app for fechado antes de reenviar. Persistir exige decidir onde
   guardar a foto (pasta privada do app, criptografada) e por quanto tempo. Decisão pendente.

## Depende de teste em aparelho real
Os testes automáticos cobrem fakes, a lógica e as telas. **Não** provam:
- Pedido de permissão do sistema em Android (11, 13, 14) e iOS: texto, ordem e o "negada para sempre" (no Android
  o sistema só passa a bloquear depois de duas negativas; no iOS, na primeira).
- Abrir as configurações do app e o retorno do usuário à tela.
- Câmera: orientação da foto (`bakeOrientation`) em vários aparelhos, tempo de compressão em celular simples,
  tamanho final, cancelamento no meio, app morto pelo sistema durante a captura (Android recria a atividade).
- Que o JPEG de saída não tem GPS lendo o arquivo real (a verificação automática usa uma imagem sintética).
- GPS: precisão em ambiente fechado, tempo até a primeira posição, GPS desligado, "localização aproximada" do
  Android 12+ e do iOS 14+ (a precisão reportada pode ser de centenas de metros), modo avião.
- Offline de verdade: tirar a foto sem sinal, voltar o sinal e o reenvio automático.
- Envio por URL assinada num armazenamento real (depende do item 1 acima), inclusive em rede lenta.
- Selfie na câmera frontal e documento legível (qualidade, brilho).
- Acessibilidade das folhas de permissão com leitor de tela e fonte grande.
