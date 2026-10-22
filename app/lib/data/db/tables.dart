/// 本地 SQLite 表结构定义（Drift）。
///
/// 说明：
/// - 金额一律用整数「分」存储（`IntColumn`），避免浮点误差
/// - 所有业务表统一带 `id / createdAt / updatedAt / deletedAt`，`deletedAt` 为软删除墓碑
/// - 因数据只存本机、无多端同步，不需要 version / deviceId 字段
library;

import 'package:drift/drift.dart';

enum TxnKind { income, expense, transfer }

enum TxnSource { manual, ai, ocr }

/// 账户大类：资产 / 投资 / 负债。
enum AccountClass { asset, investment, liability }

extension AccountClassLabel on AccountClass {
  String get label => switch (this) {
        AccountClass.asset => '资产类',
        AccountClass.investment => '投资类',
        AccountClass.liability => '负债类',
      };
}

enum AccountType {
  cash,
  debitCard,
  creditCard,
  wechat,
  alipay,
  investment,
  virtual,
  receivable,
  customAsset,
  stock,
  fund,
  wealth,
  customInvestment,
  shortLoan,
  longLoan,
  customLiability,
}

extension AccountTypeLabel on AccountType {
  String get label => switch (this) {
        AccountType.cash => '现金',
        AccountType.debitCard => '储蓄卡',
        AccountType.creditCard => '信用卡',
        AccountType.wechat => '微信',
        AccountType.alipay => '支付宝',
        AccountType.investment => '投资账户',
        AccountType.virtual => '虚拟账户',
        AccountType.receivable => '债权',
        AccountType.customAsset => '自定义资产',
        AccountType.stock => '股票',
        AccountType.fund => '基金',
        AccountType.wealth => '理财产品',
        AccountType.customInvestment => '自定义投资',
        AccountType.shortLoan => '短期信贷',
        AccountType.longLoan => '长期借贷',
        AccountType.customLiability => '自定义负债',
      };

  /// 所属大类：投资类在算总资产时按市值计入，负债类只计入总负债。
  AccountClass get accountClass => switch (this) {
        AccountType.cash ||
        AccountType.debitCard ||
        AccountType.wechat ||
        AccountType.alipay ||
        AccountType.virtual ||
        AccountType.receivable ||
        AccountType.customAsset =>
          AccountClass.asset,
        AccountType.investment ||
        AccountType.stock ||
        AccountType.fund ||
        AccountType.wealth ||
        AccountType.customInvestment =>
          AccountClass.investment,
        AccountType.creditCard ||
        AccountType.shortLoan ||
        AccountType.longLoan ||
        AccountType.customLiability =>
          AccountClass.liability,
      };

  /// 是否需要自定义类型名称。
  bool get isCustom =>
      this == AccountType.customAsset ||
      this == AccountType.customInvestment ||
      this == AccountType.customLiability;

  /// 需要填写银行卡前后四位。
  bool get isCardType =>
      this == AccountType.debitCard || this == AccountType.creditCard;

}

/// 大类下的可选类型（新建账户时使用）。
List<AccountType> accountTypesOf(AccountClass cls) => [
      for (final type in AccountType.values)
        if (type.accountClass == cls) type,
    ];

extension TxnKindLabel on TxnKind {
  String get label => switch (this) {
        TxnKind.income => '收入',
        TxnKind.expense => '支出',
        TxnKind.transfer => '转账',
      };
}

extension TxnSourceLabel on TxnSource {
  String get label => switch (this) {
        TxnSource.manual => '手动',
        TxnSource.ai => 'AI',
        TxnSource.ocr => '识图',
      };
}

/// 公共字段：UUIDv7 主键 + 时间戳 + 软删除。
mixin BaseColumns on Table {
  TextColumn get id => text()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
  DateTimeColumn get deletedAt => dateTime().nullable()();
}

// ---------------------------------------------------------------- 财务

class Accounts extends Table with BaseColumns {
  TextColumn get name => text().withLength(min: 1, max: 64)();
  TextColumn get type => textEnum<AccountType>()();
  IntColumn get balanceInit => integer().withDefault(const Constant(0))();

  /// 自定义类型名称（仅 customAsset / customInvestment / customLiability 使用）。
  TextColumn get customLabel => text().nullable()();

  /// 投资类的手动市值调整（分）：市值 = 本金 + 盈亏，盈亏主要来自这里。
  IntColumn get marketAdjustment => integer().withDefault(const Constant(0))();

  /// 银行卡号后四位（储蓄卡 / 信用卡必填）。只存后四位，不存完整卡号。
  TextColumn get cardLast4 => text().nullable()();

  /// 银行卡号前四位（选填）。
  TextColumn get cardFirst4 => text().nullable()();
  TextColumn get icon => text().nullable()();
  IntColumn get sort => integer().withDefault(const Constant(0))();

  @override
  Set<Column> get primaryKey => {id};
}

class Categories extends Table with BaseColumns {
  TextColumn get name => text().withLength(min: 1, max: 64)();
  TextColumn get kind => textEnum<TxnKind>()();
  TextColumn get parentId => text().nullable()();
  TextColumn get icon => text().nullable()();
  IntColumn get sort => integer().withDefault(const Constant(0))();

  @override
  Set<Column> get primaryKey => {id};
}

class Transactions extends Table with BaseColumns {
  TextColumn get accountId => text().nullable()();

  /// 转账的转入账户；普通收支为空。
  TextColumn get toAccountId => text().nullable()();
  TextColumn get categoryId => text().nullable()();
  TextColumn get kind => textEnum<TxnKind>()();
  IntColumn get amount => integer()();
  DateTimeColumn get occurredAt => dateTime()();
  TextColumn get payee => text().nullable()();
  TextColumn get note => text().nullable()();
  TextColumn get source => textEnum<TxnSource>().withDefault(const Constant('manual'))();
  RealColumn get confidence => real().nullable()();
  TextColumn get imageRef => text().nullable()();
  TextColumn get fingerprint => text().nullable()();
  TextColumn get tradeNo => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

class Budgets extends Table with BaseColumns {
  /// YYYY-MM
  TextColumn get period => text().withLength(min: 7, max: 7)();

  /// 为空表示总预算
  TextColumn get categoryId => text().nullable()();
  IntColumn get amount => integer()();

  @override
  Set<Column> get primaryKey => {id};
}

class AssetSnapshots extends Table with BaseColumns {
  /// YYYY-MM-DD
  TextColumn get snapshotDate => text().withLength(min: 10, max: 10)();
  IntColumn get totalAssets => integer().withDefault(const Constant(0))();
  IntColumn get totalLiabilities => integer().withDefault(const Constant(0))();
  IntColumn get netWorth => integer().withDefault(const Constant(0))();
  TextColumn get detailJson => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

// ---------------------------------------------------------------- 健康

class WeightRecords extends Table with BaseColumns {
  DateTimeColumn get recordedAt => dateTime()();
  IntColumn get weightGrams => integer()();
  RealColumn get bodyFatPct => real().nullable()();
  TextColumn get note => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

/// 围度采用长表结构：一行一个部位，便于任意部位自由对比。
class BodyMeasures extends Table with BaseColumns {
  DateTimeColumn get measuredAt => dateTime()();
  TextColumn get part => text().withLength(min: 1, max: 32)();

  /// 毫米，避免浮点
  IntColumn get valueMm => integer()();
  TextColumn get note => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

class Workouts extends Table with BaseColumns {
  DateTimeColumn get startedAt => dateTime()();
  IntColumn get durationMin => integer()();
  TextColumn get type => text().withLength(min: 1, max: 32)();

  /// 米
  IntColumn get distanceM => integer().nullable()();
  IntColumn get calories => integer().nullable()();
  IntColumn get avgHr => integer().nullable()();
  TextColumn get note => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

// ---------------------------------------------------------------- 学习

class Wordbooks extends Table with BaseColumns {
  TextColumn get name => text().withLength(min: 1, max: 64)();
  TextColumn get source => text().withDefault(const Constant('builtin'))();
  TextColumn get language => text().withDefault(const Constant('en'))();
  IntColumn get wordCount => integer().withDefault(const Constant(0))();

  @override
  Set<Column> get primaryKey => {id};
}

class Words extends Table with BaseColumns {
  TextColumn get wordbookId => text()();
  TextColumn get spelling => text()();
  TextColumn get phoneticUk => text().nullable()();
  TextColumn get phoneticUs => text().nullable()();
  TextColumn get audioUk => text().nullable()();
  TextColumn get audioUs => text().nullable()();
  TextColumn get meaningsJson => text().nullable()();
  TextColumn get examplesJson => text().nullable()();
  TextColumn get tags => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

/// SRS 状态机：维护 ease / intervalDays / repetitions。
class ReviewRecords extends Table with BaseColumns {
  TextColumn get wordId => text()();
  DateTimeColumn get reviewedAt => dateTime()();
  TextColumn get result => text()();
  IntColumn get intervalDays => integer().withDefault(const Constant(0))();
  RealColumn get ease => real().withDefault(const Constant(2.5))();
  IntColumn get repetitions => integer().withDefault(const Constant(0))();
  DateTimeColumn get nextReviewAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

class StudyStats extends Table with BaseColumns {
  /// YYYY-MM-DD
  TextColumn get statDate => text().withLength(min: 10, max: 10)();
  IntColumn get newCount => integer().withDefault(const Constant(0))();
  IntColumn get reviewCount => integer().withDefault(const Constant(0))();
  RealColumn get correctRate => real().withDefault(const Constant(0))();
  IntColumn get durationSec => integer().withDefault(const Constant(0))();

  @override
  Set<Column> get primaryKey => {id};
}

/// 一次拼写 / 听写测验（完成一轮才写入）。
class QuizSessions extends Table with BaseColumns {
  /// 为空表示跨词库抽题（当前版本总是具体词库）。
  TextColumn get wordbookId => text().nullable()();
  TextColumn get mode => text()();
  IntColumn get total => integer().withDefault(const Constant(0))();
  IntColumn get correct => integer().withDefault(const Constant(0))();
  IntColumn get durationSec => integer().withDefault(const Constant(0))();

  @override
  Set<Column> get primaryKey => {id};
}

/// 测验中的每一道题，便于后续做错题本。
class QuizAnswers extends Table with BaseColumns {
  TextColumn get sessionId => text()();
  TextColumn get wordId => text()();
  TextColumn get answer => text()();
  BoolColumn get correct => boolean().withDefault(const Constant(false))();
  DateTimeColumn get answeredAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

// ---------------------------------------------------------------- AI

class ChatSessions extends Table with BaseColumns {
  TextColumn get title => text()();
  TextColumn get model => text()();

  @override
  Set<Column> get primaryKey => {id};
}

class ChatMessages extends Table with BaseColumns {
  TextColumn get sessionId => text()();
  TextColumn get role => text()();
  TextColumn get content => text()();
  TextColumn get toolCallsJson => text().nullable()();
  IntColumn get tokens => integer().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

class AiToolCalls extends Table with BaseColumns {
  TextColumn get messageId => text()();
  TextColumn get toolName => text()();
  TextColumn get argumentsJson => text().nullable()();
  TextColumn get resultJson => text().nullable()();
  TextColumn get status => text()();

  @override
  Set<Column> get primaryKey => {id};
}

/// 离线队列：无外网时把 AI 请求与截图排队，联网后重放。
class AiPendingTasks extends Table with BaseColumns {
  TextColumn get taskType => text()();
  TextColumn get payloadJson => text().nullable()();
  TextColumn get imagePath => text().nullable()();
  TextColumn get status => text().withDefault(const Constant('pending'))();
  IntColumn get retryCount => integer().withDefault(const Constant(0))();

  /// 最近一次重放失败的原因，供界面展示。
  TextColumn get lastError => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

// ---------------------------------------------------------------- 应用

class AppSettings extends Table {
  TextColumn get key => text()();
  TextColumn get value => text()();

  @override
  Set<Column> get primaryKey => {key};
}
