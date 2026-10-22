/// 账户展示辅助：名称（含卡号尾号）、类型名称、图标与配色。
library;

import 'package:flutter/material.dart';

import '../../data/db/database.dart';

/// 列表展示名：有卡号尾号时显示为「招商银行(0137)」。
String accountDisplayName(Account account) {
  final last4 = account.cardLast4;
  if (last4 == null || last4.isEmpty) return account.name;
  return '${account.name}($last4)';
}

/// 类型展示名：自定义类型优先用用户填写的名称。
String accountTypeLabel(Account account) {
  final custom = account.customLabel?.trim();
  if (custom != null && custom.isNotEmpty) return custom;
  return account.type.label;
}

IconData accountIcon(AccountType type) => switch (type) {
      AccountType.cash => Icons.payments_outlined,
      AccountType.debitCard => Icons.account_balance_outlined,
      AccountType.creditCard => Icons.credit_card,
      AccountType.wechat => Icons.chat_bubble_outline,
      AccountType.alipay => Icons.account_balance_wallet_outlined,
      AccountType.investment => Icons.trending_up,
      AccountType.virtual => Icons.phone_iphone,
      AccountType.receivable => Icons.handshake_outlined,
      AccountType.customAsset => Icons.inventory_2_outlined,
      AccountType.stock => Icons.show_chart,
      AccountType.fund => Icons.pie_chart_outline,
      AccountType.wealth => Icons.savings_outlined,
      AccountType.customInvestment => Icons.trending_up,
      AccountType.shortLoan => Icons.credit_card,
      AccountType.longLoan => Icons.home_work_outlined,
      AccountType.customLiability => Icons.receipt_long_outlined,
    };

Color accountColor(AccountType type) => switch (type) {
      AccountType.cash => const Color(0xFF05994F),
      AccountType.debitCard => const Color(0xFFD32F2F),
      AccountType.creditCard => const Color(0xFFE8463A),
      AccountType.wechat => const Color(0xFF07C160),
      AccountType.alipay => const Color(0xFF1677FF),
      AccountType.investment => const Color(0xFFF29B38),
      AccountType.virtual => const Color(0xFF4F7CF7),
      AccountType.receivable => const Color(0xFF7A5AF8),
      AccountType.customAsset => const Color(0xFF5B8FF9),
      AccountType.stock => const Color(0xFFF06E3C),
      AccountType.fund => const Color(0xFF9A6BFF),
      AccountType.wealth => const Color(0xFFF2A93B),
      AccountType.customInvestment => const Color(0xFFEE8B3C),
      AccountType.shortLoan => const Color(0xFFE35D5D),
      AccountType.longLoan => const Color(0xFFB45454),
      AccountType.customLiability => const Color(0xFFC96A6A),
    };
