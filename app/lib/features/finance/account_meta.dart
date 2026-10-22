/// 账户展示辅助：名称（含卡号尾号）、图标与配色。
library;

import 'package:flutter/material.dart';

import '../../data/db/database.dart';

/// 列表展示名：有卡号尾号时显示为「招商银行(0137)」。
String accountDisplayName(Account account) {
  final last4 = account.cardLast4;
  if (last4 == null || last4.isEmpty) return account.name;
  return '${account.name}($last4)';
}

IconData accountIcon(AccountType type) => switch (type) {
      AccountType.cash => Icons.payments_outlined,
      AccountType.debitCard => Icons.account_balance_outlined,
      AccountType.creditCard => Icons.credit_card,
      AccountType.wechat => Icons.chat_bubble_outline,
      AccountType.alipay => Icons.account_balance_wallet_outlined,
      AccountType.investment => Icons.trending_up,
    };

Color accountColor(AccountType type) => switch (type) {
      AccountType.cash => const Color(0xFF05994F),
      AccountType.debitCard => const Color(0xFFD32F2F),
      AccountType.creditCard => const Color(0xFFE8463A),
      AccountType.wechat => const Color(0xFF07C160),
      AccountType.alipay => const Color(0xFF1677FF),
      AccountType.investment => const Color(0xFFF29B38),
    };
