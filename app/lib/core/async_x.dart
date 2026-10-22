/// Riverpod 的 `AsyncValue` 辅助扩展。
///
/// Riverpod 3 移除了 `valueOrNull`，统一用 [AsyncDataOrNull.dataOrNull]
/// 安全地取当前值（加载中与错误状态下返回 null）。
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

extension AsyncDataOrNull<T> on AsyncValue<T> {
  T? get dataOrNull => asData?.value;
}
