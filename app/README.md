# App do Trato (Flutter — Android e iOS)

Esqueleto inicial. As pastas de plataforma (`android/`, `ios/`) ainda não existem porque o
Flutter SDK não estava instalado quando o projeto foi criado.

## Primeira vez (depois de instalar o Flutter)

```bash
cd app
flutter create --org br.com.feitolabs --project-name trato --platforms android,ios .
flutter pub get
flutter test
flutter run
```

O `flutter create .` só adiciona o que falta; não sobrescreve `lib/main.dart` nem `pubspec.yaml`
(confira o `git diff` depois).

## Regras

- Nenhuma cor, fonte ou espaçamento solto: tudo vem de `lib/tema/` (Fase 2).
- Nenhuma regra de dinheiro no app. Taxa, total e líquido vêm do backend.
