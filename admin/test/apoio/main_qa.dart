// Só para conferir o visual localmente (build com `-t test/apoio/main_qa.dart --output build/qa`).
// Nunca entra no app: fica em test/ e usa o ApiFake dos testes.
import 'package:flutter/material.dart';
import 'package:trato_admin/app.dart';

import 'api_fake.dart';

void main() => runApp(PainelApp(api: ApiFake(atraso: const Duration(milliseconds: 150)), ambienteTeste: true));
