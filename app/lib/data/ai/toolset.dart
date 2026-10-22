/// AI 工具集：Function Calling 的 schema 定义与本地执行。
///
/// 工具直接读写本地 SQLite，不依赖网络；模型只负责把自然语言转成结构化参数。
/// 覆盖 App 全部功能：收支/转账、账户、分类、预算、体重/围度/运动、学习、身高。
library;

import 'dart:convert';

import '../../core/period.dart';
import '../../core/utils.dart';
import '../db/database.dart';
import '../finance_repository.dart';
import '../finance_stats.dart';
import '../health_repository.dart';
import '../health_stats.dart';
import '../settings_repository.dart';
import '../study/builtin_wordbooks.dart';
import '../study_repository.dart';
import '../study_stats.dart';
import 'deepseek_client.dart';

/// OpenAI 兼容的工具定义。
const aiToolSpecs = <Map<String, dynamic>>[
  // ============================================================ 财务
  {
    'type': 'function',
    'function': {
      'name': 'create_transaction',
      'description': '记录一笔收入或支出。用户说“午饭花了 30”“工资到账 8000，存进储蓄卡0137”时调用。',
      'parameters': {
        'type': 'object',
        'properties': {
          'kind': {
            'type': 'string',
            'enum': ['income', 'expense'],
            'description': '收入还是支出',
          },
          'amount': {'type': 'number', 'description': '金额，单位：元'},
          'category': {
            'type': 'string',
            'description': '分类名，例如 餐饮 / 交通 / 购物 / 工资；不存在会自动创建',
          },
          'account': {
            'type': 'string',
            'description': '账户名或银行卡后四位，例如 微信 / 支付宝 / 0137；省略用默认账户',
          },
          'payee': {'type': 'string', 'description': '商户或对方'},
          'note': {'type': 'string', 'description': '备注，可选'},
          'occurred_at': {
            'type': 'string',
            'description': '发生时间 ISO8601；不确定则省略，默认当前时间',
          },
        },
        'required': ['kind', 'amount'],
      },
    },
  },
  {
    'type': 'function',
    'function': {
      'name': 'create_transfer',
      'description': '账户间转账/划转，例如“从微信转 500 到储蓄卡”“工资存进储蓄卡0137”。不产生收支。',
      'parameters': {
        'type': 'object',
        'properties': {
          'amount': {'type': 'number', 'description': '转账金额，单位：元'},
          'from_account': {'type': 'string', 'description': '转出账户名或卡号后四位'},
          'to_account': {'type': 'string', 'description': '转入账户名或卡号后四位'},
          'occurred_at': {
            'type': 'string',
            'description': '发生时间 ISO8601；省略默认当前时间',
          },
        },
        'required': ['amount', 'from_account', 'to_account'],
      },
    },
  },
  {
    'type': 'function',
    'function': {
      'name': 'query_expense',
      'description': '查询某段时间的收支合计与分类占比，用于回答“我这个月花了多少”“这周收支”。',
      'parameters': {
        'type': 'object',
        'properties': {
          'period': {
            'type': 'string',
            'enum': ['day', 'week', 'month', 'year'],
            'description': '统计周期，默认 month',
          },
          'anchor': {
            'type': 'string',
            'description': '基准日期 YYYY-MM-DD；省略表示今天',
          },
        },
        'required': <String>[],
      },
    },
  },
  {
    'type': 'function',
    'function': {
      'name': 'list_accounts',
      'description': '列出全部账户及实时余额、总资产。回答“我有哪些账户”“总资产多少”“储蓄卡余额”时调用。',
      'parameters': {'type': 'object', 'properties': <String, dynamic>{}},
    },
  },
  {
    'type': 'function',
    'function': {
      'name': 'create_account',
      'description': '新建一个账户（钱包/银行卡/投资账户），例如“帮我建一张招商银行储蓄卡”。',
      'parameters': {
        'type': 'object',
        'properties': {
          'name': {'type': 'string', 'description': '账户名称，例如 招商银行 / 现金钱包'},
          'type': {
            'type': 'string',
            'enum': [
              'cash',
              'debit_card',
              'virtual',
              'receivable',
              'stock',
              'fund',
              'wealth',
              'credit_card',
              'short_loan',
              'long_loan',
            ],
            'description': '账户类型：现金/储蓄卡/虚拟账户/债权/股票/基金/理财/信用卡/短期信贷/长期借贷',
          },
          'initial_balance_yuan': {'type': 'number', 'description': '初始余额（元），默认 0'},
          'card_last4': {'type': 'string', 'description': '银行卡后四位，可选'},
          'card_first4': {'type': 'string', 'description': '银行卡前四位，可选'},
        },
        'required': ['name', 'type'],
      },
    },
  },
  {
    'type': 'function',
    'function': {
      'name': 'list_categories',
      'description': '列出收支分类；不确定用户说的分类是否存在时先查一下。',
      'parameters': {
        'type': 'object',
        'properties': {
          'kind': {
            'type': 'string',
            'enum': ['income', 'expense'],
            'description': '只看收入或支出分类；省略返回全部',
          },
        },
        'required': <String>[],
      },
    },
  },
  {
    'type': 'function',
    'function': {
      'name': 'set_budget',
      'description': '设置某月预算：不传分类是总预算，传分类名是分类预算；同月同分类重复设置会覆盖。例如“这个月预算3000”“餐饮预算800”。',
      'parameters': {
        'type': 'object',
        'properties': {
          'amount_yuan': {'type': 'number', 'description': '预算金额（元）'},
          'month': {
            'type': 'string',
            'description': '月份 YYYY-MM，省略表示当前月',
          },
          'category': {'type': 'string', 'description': '支出分类名；省略表示总预算'},
        },
        'required': ['amount_yuan'],
      },
    },
  },
  {
    'type': 'function',
    'function': {
      'name': 'query_budget',
      'description': '查询某月预算与已花金额、剩余额度。回答“预算还剩多少”“这个月有没有超支”时调用。',
      'parameters': {
        'type': 'object',
        'properties': {
          'month': {
            'type': 'string',
            'description': '月份 YYYY-MM，省略表示当前月',
          },
        },
        'required': <String>[],
      },
    },
  },
  // ============================================================ 健康
  {
    'type': 'function',
    'function': {
      'name': 'create_weight_record',
      'description': '记录体重（可带体脂率），例如“体重 65.5，体脂 18%”。',
      'parameters': {
        'type': 'object',
        'properties': {
          'weight_kg': {'type': 'number', 'description': '体重，单位公斤'},
          'body_fat_pct': {'type': 'number', 'description': '体脂率百分比，可选'},
          'measured_at': {
            'type': 'string',
            'description': '测量时间 ISO8601；省略默认当前时间',
          },
        },
        'required': ['weight_kg'],
      },
    },
  },
  {
    'type': 'function',
    'function': {
      'name': 'create_measure_record',
      'description': '记录身体围度，例如“腰围 78.5”“胸围 95”。单位厘米。',
      'parameters': {
        'type': 'object',
        'properties': {
          'part': {
            'type': 'string',
            'description': '部位：胸围 / 腰围 / 臀围 / 臂围 / 大腿 / 小腿 / 颈围，也支持自定义部位',
          },
          'value_cm': {'type': 'number', 'description': '围度数值，单位厘米'},
          'measured_at': {
            'type': 'string',
            'description': '测量时间 ISO8601；省略默认当前时间',
          },
        },
        'required': ['part', 'value_cm'],
      },
    },
  },
  {
    'type': 'function',
    'function': {
      'name': 'create_workout_record',
      'description': '记录一次运动，例如“跑步 30 分钟 5 公里”。',
      'parameters': {
        'type': 'object',
        'properties': {
          'type': {
            'type': 'string',
            'description': '运动类型：跑步 / 快走 / 骑行 / 游泳 / 力量 / 其他',
          },
          'minutes': {'type': 'integer', 'description': '时长，单位分钟'},
          'distance_km': {'type': 'number', 'description': '距离，单位公里，可选'},
          'calories': {'type': 'integer', 'description': '消耗，单位千卡，可选'},
          'started_at': {
            'type': 'string',
            'description': '开始时间 ISO8601；省略默认当前时间。用户说“昨天”时按昨天填写',
          },
        },
        'required': ['type', 'minutes'],
      },
    },
  },
  {
    'type': 'function',
    'function': {
      'name': 'query_health',
      'description': '查询一段时间的健康汇总：体重（最新/最高/最低/变化、体脂、BMI）、各部位最新围度、运动次数与总时长。',
      'parameters': {
        'type': 'object',
        'properties': {
          'period': {
            'type': 'string',
            'enum': ['day', 'week', 'month', 'year'],
            'description': '统计周期，默认 month',
          },
          'anchor': {
            'type': 'string',
            'description': '基准日期 YYYY-MM-DD；省略表示今天',
          },
        },
        'required': <String>[],
      },
    },
  },
  {
    'type': 'function',
    'function': {
      'name': 'set_height',
      'description': '设置用户身高（厘米），用于计算 BMI。用户说“我身高 175”时调用。',
      'parameters': {
        'type': 'object',
        'properties': {
          'height_cm': {'type': 'integer', 'description': '身高，单位厘米'},
        },
        'required': ['height_cm'],
      },
    },
  },
  // ============================================================ 学习
  {
    'type': 'function',
    'function': {
      'name': 'query_study',
      'description': '查询学习情况：今日待复习数、待学新词数、今日已学、最近 30 天学习量与正确率、词库列表。',
      'parameters': {'type': 'object', 'properties': <String, dynamic>{}},
    },
  },
  {
    'type': 'function',
    'function': {
      'name': 'add_study_word',
      'description': '往词库里添加一个单词（可带释义和例句），例如“把 apple 加到我的词库，释义是苹果”。',
      'parameters': {
        'type': 'object',
        'properties': {
          'spelling': {'type': 'string', 'description': '单词拼写'},
          'meanings': {
            'type': 'array',
            'items': {'type': 'string'},
            'description': '中文释义列表，可选',
          },
          'examples': {
            'type': 'array',
            'items': {'type': 'string'},
            'description': '例句列表，可选',
          },
          'wordbook': {
            'type': 'string',
            'description': '词库名；省略用内置四级词库，词库不存在会新建',
          },
        },
        'required': ['spelling'],
      },
    },
  },
  // ============================================================ 综合
  {
    'type': 'function',
    'function': {
      'name': 'get_overview',
      'description': '获取最近 30 天的财务、预算、账户资产、健康、学习综合概览，用于做总结或给建议。',
      'parameters': {'type': 'object', 'properties': <String, dynamic>{}},
    },
  },
];

/// 工具执行所需的上下文。
class ToolContext {
  const ToolContext({
    required this.finance,
    required this.health,
    required this.study,
    required this.settings,
    this.defaultAccountId,
  });

  final FinanceRepository finance;
  final HealthRepository health;
  final StudyRepository study;
  final SettingsRepository settings;
  final String? defaultAccountId;
}

/// 执行一次工具调用，返回给模型阅读的 JSON 字符串。
Future<String> runTool(ToolCall call, ToolContext context) async {
  try {
    return switch (call.name) {
      'create_transaction' => await _createTransaction(call.arguments, context),
      'create_transfer' => await _createTransfer(call.arguments, context),
      'query_expense' => await _queryExpense(call.arguments, context),
      'list_accounts' => await _listAccounts(context),
      'create_account' => await _createAccount(call.arguments, context),
      'list_categories' => await _listCategories(call.arguments, context),
      'set_budget' => await _setBudget(call.arguments, context),
      'query_budget' => await _queryBudget(call.arguments, context),
      'create_weight_record' => await _createWeight(call.arguments, context),
      'create_measure_record' => await _createMeasure(call.arguments, context),
      'create_workout_record' => await _createWorkout(call.arguments, context),
      'query_health' => await _queryHealth(call.arguments, context),
      'set_height' => await _setHeight(call.arguments, context),
      'query_study' => await _queryStudy(context),
      'add_study_word' => await _addStudyWord(call.arguments, context),
      'get_overview' => await _overview(context),
      _ => _fail('未知工具：${call.name}'),
    };
  } catch (error) {
    return _fail('工具执行失败：$error');
  }
}

String _fail(String message) => jsonEncode({'ok': false, 'error': message});

String _ok(Map<String, dynamic> payload) =>
    jsonEncode({'ok': true, ...payload});

// ================================================================ 财务

Future<String> _createTransaction(
  Map<String, dynamic> args,
  ToolContext context,
) async {
  final kind = args['kind'] == 'income' ? TxnKind.income : TxnKind.expense;
  final yuan = _asDouble(args['amount']) ?? 0;
  if (yuan <= 0) return _fail('金额必须大于 0');

  final amount = (yuan * 100).round();
  final categoryName = (args['category'] as String?)?.trim();
  final payee = (args['payee'] as String?)?.trim();
  final note = (args['note'] as String?)?.trim();
  final accountRef = (args['account'] as String?)?.trim();

  final accounts = await context.finance.accountsOnce();
  final account = await _resolveAccount(accountRef, accounts) ??
      accounts
          .where((item) => item.id == context.defaultAccountId)
          .cast<Account?>()
          .firstWhere((_) => true, orElse: () => null);

  if ((accountRef?.isNotEmpty ?? false) && account == null) {
    return _fail('没有找到账户「$accountRef」，可以先调用 list_accounts 确认账户名');
  }

  await context.finance.saveTransaction(
    kind: kind,
    amount: amount,
    occurredAt: _parseMoment(args['occurred_at']),
    categoryId: await _resolveCategory(context, categoryName, kind),
    accountId: account?.id,
    payee: (payee == null || payee.isEmpty) ? null : payee,
    note: (note == null || note.isEmpty) ? null : note,
    source: TxnSource.ai,
  );

  return _ok({
    'summary': '已记账：${kind.label} ¥${formatCents(amount)}'
        '${categoryName == null || categoryName.isEmpty ? '' : ' · $categoryName'}'
        '${account == null ? '' : ' · ${account.name}'}',
  });
}

Future<String> _createTransfer(
  Map<String, dynamic> args,
  ToolContext context,
) async {
  final yuan = _asDouble(args['amount']) ?? 0;
  if (yuan <= 0) return _fail('转账金额必须大于 0');

  final accounts = await context.finance.accountsOnce();
  final from = await _resolveAccount(args['from_account'] as String?, accounts);
  final to = await _resolveAccount(args['to_account'] as String?, accounts);
  if (from == null) {
    return _fail('没有找到转出账户，可以先调用 list_accounts 确认');
  }
  if (to == null) {
    return _fail('没有找到转入账户，可以先调用 list_accounts 确认');
  }
  if (from.id == to.id) return _fail('转出和转入账户不能相同');

  final amount = (yuan * 100).round();
  await context.finance.saveTransaction(
    kind: TxnKind.transfer,
    amount: amount,
    occurredAt: _parseMoment(args['occurred_at']),
    accountId: from.id,
    toAccountId: to.id,
    note: '转入：${to.name}',
    source: TxnSource.ai,
  );

  return _ok({
    'summary': '已转账：¥${formatCents(amount)}，${from.name} → ${to.name}',
  });
}

Future<String> _queryExpense(
  Map<String, dynamic> args,
  ToolContext context,
) async {
  final (start, end, period) = _periodRange(args);

  final entries = await context.finance.entriesInRange(start, end);
  final summary = summarize(entries);
  final items = breakdownByCategory(entries, TxnKind.expense);
  final names = await context.finance.categoryNameMap();

  return _ok({
    'period': period,
    'start': formatDate(start),
    'end': formatDate(end),
    'income_yuan': summary.income / 100,
    'expense_yuan': summary.expense / 100,
    'net_yuan': summary.net / 100,
    'count': summary.count,
    'top_expense_categories': [
      for (final item in items.take(5))
        {
          'name': names[item.categoryId] ?? '未分类',
          'amount_yuan': item.amount / 100,
          'ratio': double.parse(item.ratio.toStringAsFixed(4)),
        },
    ],
  });
}

Future<String> _listAccounts(ToolContext context) async {
  final accounts = await context.finance.accountsOnce();
  final summary = await context.finance.assetSummaryOnce();

  final items = <Map<String, dynamic>>[];
  for (final account in accounts) {
    final balance = summary.accounts[account.id];
    items.add({
      'name': account.name,
      'type': account.type.label,
      'card_last4': account.cardLast4,
      'class': account.type.accountClass.label,
      'initial_balance_yuan': account.balanceInit / 100,
      'balance_yuan': (balance?.value ?? 0) / 100,
      if (account.type.accountClass == AccountClass.investment) ...{
        'principal_yuan': (balance?.principal ?? 0) / 100,
        'profit_yuan': (balance?.profit ?? 0) / 100,
      },
    });
  }

  return _ok({
    'total_assets_yuan': summary.totalAssets / 100,
    'total_liabilities_yuan': summary.liabilityTotal / 100,
    'net_worth_yuan': summary.netWorth / 100,
    'investment_profit_yuan': summary.investmentProfit / 100,
    'accounts': items,
  });
}

Future<String> _createAccount(
  Map<String, dynamic> args,
  ToolContext context,
) async {
  final name = (args['name'] as String?)?.trim();
  if (name == null || name.isEmpty) return _fail('缺少账户名称');

  final type = switch (args['type']) {
    'cash' => AccountType.cash,
    'debit_card' => AccountType.debitCard,
    'virtual' => AccountType.virtual,
    'receivable' => AccountType.receivable,
    'stock' => AccountType.stock,
    'fund' => AccountType.fund,
    'wealth' => AccountType.wealth,
    'credit_card' => AccountType.creditCard,
    'short_loan' => AccountType.shortLoan,
    'long_loan' => AccountType.longLoan,
    'wechat' => AccountType.wechat,
    'alipay' => AccountType.alipay,
    'investment' => AccountType.investment,
    _ => null,
  };
  if (type == null) return _fail('账户类型不合法');

  final existing = await context.finance.accountsOnce();
  final duplicated = existing.any(
    (item) => item.name.toLowerCase() == name.toLowerCase(),
  );
  if (duplicated) return _fail('已存在同名账户「$name」');

  final initYuan = _asDouble(args['initial_balance_yuan']) ?? 0;
  var initCents = (initYuan * 100).round();
  if (type.accountClass == AccountClass.liability) initCents = initCents.abs();
  final last4 = _digits(args['card_last4'] as String?, length: 4);
  final first4 = _digits(args['card_first4'] as String?, length: 4);
  final sort = existing.isEmpty
      ? 0
      : existing.map((item) => item.sort).reduce((a, b) => a > b ? a : b) + 1;

  final id = await context.finance.saveAccount(
    name: name,
    type: type,
    balanceInit: initCents,
    cardFirst4: first4,
    cardLast4: last4,
    sort: sort,
  );

  final amountLabel = type.accountClass == AccountClass.liability
      ? '当前欠款'
      : type.accountClass == AccountClass.investment
          ? '初始本金'
          : '初始余额';
  return _ok({
    'summary': '已创建${type.label}账户「$name」'
        '${initCents == 0 ? '' : '，$amountLabel ¥${formatCents(initCents)}'}',
    'account_id': id,
  });
}

Future<String> _listCategories(
  Map<String, dynamic> args,
  ToolContext context,
) async {
  final kind = switch (args['kind']) {
    'income' => TxnKind.income,
    'expense' => TxnKind.expense,
    _ => null,
  };
  final categories = await context.finance.categoriesOnce(kind: kind);
  return _ok({
    'categories': [
      for (final category in categories)
        {'name': category.name, 'kind': category.kind.label},
    ],
  });
}

Future<String> _setBudget(
  Map<String, dynamic> args,
  ToolContext context,
) async {
  final yuan = _asDouble(args['amount_yuan']) ?? 0;
  if (yuan <= 0) return _fail('预算金额必须大于 0');

  final month = (args['month'] as String?)?.trim() ?? _currentMonth();
  if (!_isMonth(month)) return _fail('月份格式应为 YYYY-MM');

  final categoryName = (args['category'] as String?)?.trim();
  String? categoryId;
  if (categoryName != null && categoryName.isNotEmpty) {
    categoryId = await _resolveCategory(context, categoryName, TxnKind.expense);
  }

  final budgets = await context.finance.budgetsForPeriod(month);
  final existing = budgets
      .where((item) => item.categoryId == categoryId)
      .cast<Budget?>()
      .firstWhere((_) => true, orElse: () => null);

  final amount = (yuan * 100).round();
  await context.finance.saveBudget(
    id: existing?.id,
    period: month,
    categoryId: categoryId,
    amount: amount,
  );

  final target = categoryId == null ? '总预算' : '「$categoryName」预算';
  final suffix = existing == null ? '' : '（覆盖旧值）';
  return _ok({
    'summary': '$month$target已设为 ¥${formatCents(amount)}$suffix',
  });
}

Future<String> _queryBudget(
  Map<String, dynamic> args,
  ToolContext context,
) async {
  final month = (args['month'] as String?)?.trim() ?? _currentMonth();
  if (!_isMonth(month)) return _fail('月份格式应为 YYYY-MM');

  final start = DateTime.tryParse('$month-01');
  if (start == null) return _fail('月份无法解析：$month');
  final end = DateTime(start.year, start.month + 1, 1).subtract(
    const Duration(days: 1),
  );

  final entries = await context.finance.entriesInRange(start, end);
  final spent = summarize(entries).expense;
  final budgets = await context.finance.budgetsForPeriod(month);
  final names = await context.finance.categoryNameMap();

  Budget? totalBudget;
  final categoryBudgets = <Map<String, dynamic>>[];
  final spentByCategory = <String?, int>{};
  for (final entry in entries) {
    if (entry.kind != TxnKind.expense) continue;
    spentByCategory[entry.categoryId] =
        (spentByCategory[entry.categoryId] ?? 0) + entry.amount;
  }
  for (final budget in budgets) {
    final item = {
      'category': budget.categoryId == null
          ? null
          : names[budget.categoryId] ?? '未分类',
      'budget_yuan': budget.amount / 100,
      'spent_yuan': (spentByCategory[budget.categoryId] ?? 0) / 100,
      'remaining_yuan':
          (budget.amount - (spentByCategory[budget.categoryId] ?? 0)) / 100,
    };
    if (budget.categoryId == null) {
      totalBudget = budget;
    } else {
      categoryBudgets.add(item);
    }
  }

  return _ok({
    'month': month,
    'spent_yuan': spent / 100,
    'total_budget_yuan':
        totalBudget == null ? null : totalBudget.amount / 100,
    'total_remaining_yuan': totalBudget == null
        ? null
        : (totalBudget.amount - spent) / 100,
    'category_budgets': categoryBudgets,
  });
}

// ================================================================ 健康

Future<String> _createWeight(
  Map<String, dynamic> args,
  ToolContext context,
) async {
  final kg = _asDouble(args['weight_kg']) ?? 0;
  if (kg <= 0 || kg > 500) return _fail('体重数值不合理（0~500 公斤）');

  final bodyFat = _asDouble(args['body_fat_pct']);
  if (bodyFat != null && (bodyFat <= 0 || bodyFat > 100)) {
    return _fail('体脂率应在 0~100% 之间');
  }

  await context.health.saveWeight(
    recordedAt: _parseMoment(args['measured_at']),
    grams: (kg * 1000).round(),
    bodyFatPct: bodyFat,
  );
  return _ok({'summary': '已记录体重 ${kg.toStringAsFixed(2)} kg'});
}

Future<String> _createMeasure(
  Map<String, dynamic> args,
  ToolContext context,
) async {
  final part = (args['part'] as String?)?.trim();
  final cm = _asDouble(args['value_cm']) ?? 0;
  if (part == null || part.isEmpty) return _fail('缺少围度部位');
  if (cm <= 0 || cm > 300) return _fail('围度数值不合理（0~300 厘米）');

  await context.health.saveMeasure(
    measuredAt: _parseMoment(args['measured_at']),
    part: part,
    mm: (cm * 10).round(),
  );
  return _ok({'summary': '已记录$part ${cm.toStringAsFixed(1)} cm'});
}

Future<String> _createWorkout(
  Map<String, dynamic> args,
  ToolContext context,
) async {
  final type = (args['type'] as String?)?.trim();
  final minutes = _asInt(args['minutes']) ?? 0;
  if (type == null || type.isEmpty) return _fail('缺少运动类型');
  if (minutes <= 0 || minutes > 1440) return _fail('时长不合理（1~1440 分钟）');

  final km = _asDouble(args['distance_km']);

  await context.health.saveWorkout(
    startedAt: _parseMoment(args['started_at']),
    minutes: minutes,
    type: type,
    meters: km == null ? null : (km * 1000).round(),
    calories: _asInt(args['calories']),
  );
  return _ok({
    'summary': '已记录运动：$type ${formatDuration(minutes)}',
  });
}

Future<String> _queryHealth(
  Map<String, dynamic> args,
  ToolContext context,
) async {
  final (start, end, period) = _periodRange(args);

  final weights = await context.health.weightEntriesInRange(start, end);
  final measures = await context.health.measureEntriesInRange(start, end);
  final workouts = await context.health.workoutEntriesInRange(start, end);
  final weightSummary = summarizeWeight(weights);
  final latestRow = await context.health.latestWeightRow();
  final heightCm = int.tryParse(
    (await context.settings.get(SettingKeys.heightCm)) ?? '',
  );

  final byType = <String, Map<String, int>>{};
  var totalMinutes = 0;
  var totalMeters = 0;
  var totalCalories = 0;
  for (final workout in workouts) {
    final stat = byType.putIfAbsent(workout.type, () => {'count': 0, 'minutes': 0});
    stat['count'] = stat['count']! + 1;
    stat['minutes'] = stat['minutes']! + workout.minutes;
    totalMinutes += workout.minutes;
    totalMeters += workout.meters ?? 0;
    totalCalories += workout.calories ?? 0;
  }

  final latestMeasures = <String, Map<String, dynamic>>{};
  for (final measure in measures) {
    final old = latestMeasures[measure.part];
    if (old == null || measure.at.isAfter(DateTime.parse(old['at'] as String))) {
      latestMeasures[measure.part] = {
        'value_cm': measure.mm / 10,
        'at': measure.at.toIso8601String(),
      };
    }
  }

  final bmi = bmiOf(latestRow?.weightGrams, heightCm);
  final latestInRange = latestRow != null &&
      !latestRow.recordedAt.isBefore(startOfDay(start)) &&
      !latestRow.recordedAt.isAfter(endOfDay(end));

  return _ok({
    'period': period,
    'start': formatDate(start),
    'end': formatDate(end),
    'weight': {
      'latest_kg': weightSummary.latestGrams == null
          ? null
          : weightSummary.latestGrams! / 1000,
      'first_kg': weightSummary.firstGrams == null
          ? null
          : weightSummary.firstGrams! / 1000,
      'min_kg': weightSummary.minGrams == null
          ? null
          : weightSummary.minGrams! / 1000,
      'max_kg': weightSummary.maxGrams == null
          ? null
          : weightSummary.maxGrams! / 1000,
      'delta_kg': weightSummary.deltaGrams == null
          ? null
          : weightSummary.deltaGrams! / 1000,
      'body_fat_pct': latestInRange ? latestRow.bodyFatPct : null,
      'bmi': bmi == null ? null : double.parse(bmi.toStringAsFixed(1)),
      'bmi_label': bmi == null ? null : bmiLabel(bmi),
      'count': weightSummary.count,
    },
    'measures_latest': [
      for (final entry in latestMeasures.entries)
        {'part': entry.key, 'value_cm': entry.value['value_cm']},
    ],
    'workouts': {
      'count': workouts.length,
      'total_minutes': totalMinutes,
      'total_distance_km': double.parse((totalMeters / 1000).toStringAsFixed(2)),
      'total_calories': totalCalories,
      'by_type': [
        for (final entry in byType.entries)
          {
            'type': entry.key,
            'count': entry.value['count'],
            'minutes': entry.value['minutes'],
          },
      ],
    },
  });
}

Future<String> _setHeight(
  Map<String, dynamic> args,
  ToolContext context,
) async {
  final cm = _asInt(args['height_cm']) ?? 0;
  if (cm < 50 || cm > 300) return _fail('身高数值不合理（50~300 厘米）');

  await context.settings.set(SettingKeys.heightCm, '$cm');

  final latest = await context.health.latestWeightRow();
  final bmi = bmiOf(latest?.weightGrams, cm);
  final bmiPart = bmi == null
      ? ''
      : '，当前 BMI ${bmi.toStringAsFixed(1)}（${bmiLabel(bmi)}）';
  return _ok({
    'summary': '已设置身高 $cm cm$bmiPart',
  });
}

// ================================================================ 学习

Future<String> _queryStudy(ToolContext context) async {
  final now = DateTime.now();
  final words = await context.study.wordsOnce();
  final reviews = await context.study.reviewsOnce();
  final cards = buildCardStates(words, latestByWord(reviews));
  final dueCount = cards.where((card) => card.isDue(now)).length;
  final newCount = cards.where((card) => card.isNew).length;
  final queueSize = buildDailyQueue(cards: cards, now: now).length;

  final todayStart = startOfDay(now);
  final today = summarizeStudy(
    await context.study.statsOnce(todayStart, now),
  );
  final month30 = summarizeStudy(
    await context.study.statsOnce(now.subtract(const Duration(days: 29)), now),
  );
  final books = await context.study.wordbooksOnce();

  return _ok({
    'today': {
      'due_count': dueCount,
      'new_available': newCount,
      'queue_size': queueSize,
      'learned_today': today.total,
      'new_today': today.newCount,
      'reviewed_today': today.reviewCount,
    },
    'last_30_days': {
      'total_learned': month30.total,
      'new_words': month30.newCount,
      'reviews': month30.reviewCount,
      'correct_rate': double.parse(month30.correctRate.toStringAsFixed(4)),
      'study_minutes': (month30.durationSec / 60).round(),
    },
    'wordbooks': [
      for (final book in books)
        {'name': book.name, 'word_count': book.wordCount, 'source': book.source},
    ],
  });
}

Future<String> _addStudyWord(
  Map<String, dynamic> args,
  ToolContext context,
) async {
  final spelling = (args['spelling'] as String?)?.trim();
  if (spelling == null || spelling.isEmpty) return _fail('缺少单词拼写');

  final bookName = ((args['wordbook'] as String?)?.trim());
  final usesDefault = bookName == null || bookName.isEmpty;
  var targetName = usesDefault ? defaultBuiltinWordbookName : bookName;

  var book = await context.study.findWordbookByName(targetName);
  if (book == null && usesDefault) {
    // 默认词库可能已被用户删除：改放自建词库，避免把删掉的内置词库又建回来。
    targetName = '我的词库';
    book = await context.study.findWordbookByName(targetName);
  }
  book ??= await _getOrCreateBuiltin(context, targetName);
  if (book == null) return _fail('词库「$targetName」不存在');

  if (await context.study.hasWord(book.id, spelling)) {
    return _fail('词库「${book.name}」里已经有单词 $spelling');
  }

  await context.study.addWord(
    wordbookId: book.id,
    spelling: spelling,
    meanings: _stringList(args['meanings']),
    examples: _stringList(args['examples']),
  );

  return _ok({'summary': '已把 $spelling 加入词库「${book.name}」'});
}

/// 找内置词库；用户显式指定了不存在的词库名时新建自定义词库。
Future<Wordbook?> _getOrCreateBuiltin(
  ToolContext context,
  String name,
) async {
  final id = await context.study.createWordbook(
    name: name,
    source: name == defaultBuiltinWordbookName ? 'builtin' : 'custom',
  );
  final books = await context.study.wordbooksOnce();
  for (final book in books) {
    if (book.id == id) return book;
  }
  return null;
}

// ================================================================ 综合

Future<String> _overview(ToolContext context) async {
  final now = DateTime.now();
  final from = now.subtract(const Duration(days: 29));

  final entries = await context.finance.entriesInRange(from, now);
  final summary = summarize(entries);
  final weights = await context.health.weightEntriesInRange(from, now);
  final workouts = await context.health.workoutEntriesInRange(from, now);
  final weightSummary = summarizeWeight(weights);
  final workoutSummary = summarizeWorkouts(workouts);
  final study30 = summarizeStudy(await context.study.statsOnce(from, now));

  final accounts = await context.finance.accountsOnce();
  final assetSummary = await context.finance.assetSummaryOnce();

  final month = _currentMonth();
  final monthStart = DateTime(now.year, now.month);
  final monthEntries = await context.finance.entriesInRange(monthStart, now);
  final monthSpent = summarize(monthEntries).expense;
  final budgets = await context.finance.budgetsForPeriod(month);
  final totalBudget = budgets
      .where((item) => item.categoryId == null)
      .cast<Budget?>()
      .firstWhere((_) => true, orElse: () => null);

  return _ok({
    'range_days': 30,
    'finance': {
      'income_yuan': summary.income / 100,
      'expense_yuan': summary.expense / 100,
      'net_yuan': summary.net / 100,
      'count': summary.count,
    },
    'assets': {
      'total_assets_yuan': assetSummary.totalAssets / 100,
      'total_liabilities_yuan': assetSummary.liabilityTotal / 100,
      'net_worth_yuan': assetSummary.netWorth / 100,
      'investment_profit_yuan': assetSummary.investmentProfit / 100,
      'account_count': accounts.length,
    },
    'budget_this_month': {
      'total_budget_yuan':
          totalBudget == null ? null : totalBudget.amount / 100,
      'spent_yuan': monthSpent / 100,
      'remaining_yuan': totalBudget == null
          ? null
          : (totalBudget.amount - monthSpent) / 100,
    },
    'health': {
      'latest_weight_kg': weightSummary.latestGrams == null
          ? null
          : weightSummary.latestGrams! / 1000,
      'weight_delta_kg': weightSummary.deltaGrams == null
          ? null
          : weightSummary.deltaGrams! / 1000,
      'workout_count': workoutSummary.count,
      'workout_minutes': workoutSummary.minutes,
    },
    'study_last_30_days': {
      'total_learned': study30.total,
      'correct_rate': double.parse(study30.correctRate.toStringAsFixed(4)),
      'study_minutes': (study30.durationSec / 60).round(),
    },
  });
}

// ================================================================ 辅助

/// 分类不存在时自动创建，让记账一次到位。
Future<String?> _resolveCategory(
  ToolContext context,
  String? name,
  TxnKind kind,
) async {
  final trimmed = name?.trim();
  if (trimmed == null || trimmed.isEmpty) return null;

  final existing = await context.finance.findCategoryByName(trimmed, kind);
  if (existing != null) return existing.id;

  await context.finance.saveCategory(name: trimmed, kind: kind);
  final created = await context.finance.findCategoryByName(trimmed, kind);
  return created?.id;
}

/// 按账户名或银行卡后四位解析账户：先精确，再名称包含/尾号后缀。
Future<Account?> _resolveAccount(
  String? ref,
  List<Account> accounts,
) async {
  final query = ref?.trim();
  if (query == null || query.isEmpty) return null;
  final lower = query.toLowerCase();
  final digits = query.replaceAll(RegExp(r'[^0-9]'), '');

  for (final account in accounts) {
    if (account.name.toLowerCase() == lower) return account;
    final last4 = account.cardLast4;
    if (last4 != null && last4.isNotEmpty) {
      if (last4 == digits) return account;
      if ('${account.name.toLowerCase()}($last4)' == lower) return account;
    }
  }
  for (final account in accounts) {
    if (account.name.toLowerCase().contains(lower) && lower.isNotEmpty) {
      return account;
    }
    if (digits.length >= 4 &&
        account.cardLast4 != null &&
        digits.endsWith(account.cardLast4!)) {
      return account;
    }
  }
  return null;
}

/// 日 / 周 / 月 / 年的统一区间解析，返回 (开始, 结束, 周期名)。
(DateTime, DateTime, String) _periodRange(Map<String, dynamic> args) {
  final anchor = _parseDay(args['anchor']) ?? DateTime.now();
  return switch (args['period']) {
    'day' => () {
        final (s, e) = StatsPeriod.day.rangeOf(anchor);
        return (s, e, 'day');
      }(),
    'week' => () {
        final (s, e) = ViewPeriod.week.rangeOf(anchor);
        return (s, e, 'week');
      }(),
    'year' => () {
        final (s, e) = ViewPeriod.year.rangeOf(anchor);
        return (s, e, 'year');
      }(),
    _ => () {
        final (s, e) = ViewPeriod.month.rangeOf(anchor);
        return (s, e, 'month');
      }(),
  };
}

/// 解析数值参数：兼容模型偶尔把数字写成字符串（如 "70"、"70kg"、"1,200"）。
double? _asDouble(Object? value) {
  if (value is num) return value.toDouble();
  if (value is String) {
    final match = RegExp(r'-?\d+(?:\.\d+)?')
        .firstMatch(value.replaceAll(',', '').trim());
    if (match != null) return double.tryParse(match.group(0)!);
  }
  return null;
}

int? _asInt(Object? value) => _asDouble(value)?.round();

List<String> _stringList(Object? value) => [
      if (value is List)
        for (final item in value)
          if (item is String && item.trim().isNotEmpty) item.trim(),
    ];

String? _digits(String? value, {required int length}) {
  final digits = value?.replaceAll(RegExp(r'[^0-9]'), '');
  if (digits == null || digits.isEmpty) return null;
  return digits.length <= length ? digits : digits.substring(digits.length - length);
}

String _currentMonth() {
  final now = DateTime.now();
  return '${now.year}-${now.month.toString().padLeft(2, '0')}';
}

bool _isMonth(String value) => RegExp(r'^\d{4}-\d{2}$').hasMatch(value);

DateTime _parseMoment(Object? value) {
  if (value is String) {
    final parsed = DateTime.tryParse(value);
    if (parsed != null) return parsed.toLocal();
  }
  return DateTime.now();
}

DateTime? _parseDay(Object? value) {
  if (value is String) {
    final parsed = DateTime.tryParse(value);
    if (parsed != null) return parsed;
  }
  return null;
}
