// Tokens de cor do painel admin, conforme "Trato · Design system do painel admin" (v2, 02/11/2026).
// O painel tem design system próprio: não é mais cópia de app/lib/tema/ (ver LEIA-ME.md).

import 'package:flutter/painting.dart';

/// Único lugar do painel onde uma cor pode ser escrita. Nome do token do PDF entre parênteses.
abstract final class CoresTrato {
  // ---- Fundamentos (seção 3.1) ----

  /// color.bg.page — fundo da área de conteúdo (Areia).
  static const fundoPagina = Color(0xFFF3EDE2);

  /// color.bg.surface — menu lateral, cards, modais e campos.
  static const fundoSuperficie = Color(0xFFFBF8F2);

  /// color.bg.selected — item de menu ativo e card selecionado.
  static const fundoSelecionado = Color(0xFFDCEBEE);

  /// color.primary — botão primário, títulos, ícone ativo (Petróleo).
  static const primaria = Color(0xFF0E3B43);

  /// color.text.default — texto principal (10,4:1 no fundo).
  static const textoPadrao = Color(0xFF0E3B43);

  /// color.text.muted — texto secundário, rótulos, datas (5,4:1 no fundo).
  static const textoMudo = Color(0xFF4A6469);

  /// color.text.link — links e ações de texto (5,5:1 no fundo).
  static const textoLink = Color(0xFF18687A);

  /// color.border.selected — contorno de card selecionado.
  static const bordaSelecionada = Color(0xFF577D7E);

  /// color.border — divisórias e contorno de card.
  static const bordaSuave = Color(0xFFD9CFBF);

  /// color.border.strong — borda de campos e controles (3,1:1).
  static const bordaForte = Color(0xFF7C8A87);

  /// color.focus — anel de foco de 2 px, afastado 2 px.
  static const foco = Color(0xFF1F7A8C);

  /// color.accent — Brasa: um ponto por tela, nunca texto.
  static const brasa = Color(0xFFF26B21);

  // ---- Status: sempre cor, ícone e palavra ----

  static const sucessoTexto = Color(0xFF2E6E47);
  static const sucessoFundo = Color(0xFFE3EFE4);
  static const avisoTexto = Color(0xFF8A5A00);
  static const avisoFundo = Color(0xFFF7EBCC);
  static const perigoTexto = Color(0xFFB3261E);
  static const perigoFundo = Color(0xFFF8E1DD);
  static const infoTexto = Color(0xFF18687A);
  static const infoFundo = Color(0xFFDCEBEE);
  static const neutroTexto = Color(0xFF4A6469);
  static const neutroFundo = Color(0xFFEAE3D6);

  /// Sem cor (fundo de item inativo, borda de aba inativa).
  static const transparente = Color(0x00000000);

  /// Camada escura translúcida atrás do modal.
  static const camadaModal = Color(0x990E3B43);

  /// Texto sobre fundo petróleo (botão primário, avatar).
  static const textoSobrePrimaria = Color(0xFFFBF8F2);

  /// Escala de tons do primário para o funil (do mais escuro ao mais claro).
  static const funil = [
    Color(0xFF0E3B43),
    Color(0xFF2C5A62),
    Color(0xFF4F7D84),
    Color(0xFF7FA3A8),
  ];

  // ---- Nomes antigos (mantidos para o código que ainda os usa; apontam para os tokens acima) ----

  static const petroleo = primaria;
  static const creme = fundoPagina;
  static const superficie = fundoSuperficie;
  static const borda = bordaSuave;
  static const azulSuave = fundoSelecionado;
  static const azulTexto = textoLink;
  static const laranja = brasa;
  static const ambarSuave = avisoFundo;
  static const ambarTexto = avisoTexto;
  static const verdeSuave = sucessoFundo;
  static const verdeTexto = sucessoTexto;
  static const vermelhoSuave = perigoFundo;
  static const vermelhoTexto = perigoTexto;
  static const textoSecundario = textoMudo;
  static const textoDica = textoMudo;
}
