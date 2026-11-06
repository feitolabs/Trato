import 'package:flutter/material.dart';

/// Ícones do painel (DS 3.4): traço fino, um por ação. Ação repetida usa sempre o mesmo ícone,
/// sempre com texto ou rótulo acessível.
abstract final class IconesTrato {
  // Ações repetidas.
  static const editar = Icons.edit_outlined;
  static const excluir = Icons.delete_outline;
  static const ajuda = Icons.help_outline;
  static const exportar = Icons.file_download_outlined;
  static const travar = Icons.lock_outline;
  static const destravar = Icons.lock_open_outlined;
  static const revelar = Icons.visibility_outlined;
  static const esconder = Icons.visibility_off_outlined;
  static const buscar = Icons.search;
  static const adicionar = Icons.add;
  static const desativar = Icons.block;
  static const ativar = Icons.check_circle_outline;
  static const auditoria = Icons.history_edu_outlined;
  static const fechar = Icons.close;
  static const sair = Icons.logout;

  // Os módulos do menu lateral.
  static const verificacao = Icons.verified_user_outlined;
  static const disputas = Icons.gavel_outlined;
  static const buscaSuporte = Icons.manage_search_outlined;
  static const risco = Icons.shield_outlined;
  static const pagamentos = Icons.account_balance_outlined;
  static const relatorios = Icons.receipt_long_outlined;
  static const painel = Icons.space_dashboard_outlined;
  static const notificacoes = Icons.campaign_outlined;
  static const cupons = Icons.local_offer_outlined;
  static const equipe = Icons.badge_outlined;
  static const configuracoes = Icons.tune;
  static const registroAuditoria = Icons.fact_check_outlined;
  static const mais = Icons.more_horiz;
}
