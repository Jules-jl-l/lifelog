/// 底部导航外壳：财务 / 健康 / 学习 / AI / 我的。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/providers.dart';
import '../ai/ai_page.dart';
import '../finance/finance_page.dart';
import '../health/health_page.dart';
import '../settings/data_spaces_page.dart';
import '../settings/settings_page.dart';
import '../study/study_page.dart';

class HomeShell extends ConsumerStatefulWidget {
  const HomeShell({super.key});

  @override
  ConsumerState<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends ConsumerState<HomeShell> {
  int _index = 0;

  static const _pages = <Widget>[
    FinancePage(),
    HealthPage(),
    StudyPage(),
    AiPage(),
    SettingsPage(),
  ];

  @override
  Widget build(BuildContext context) {
    final current = ref.watch(
      spaceControllerProvider.select((state) => state.current),
    );

    return Scaffold(
      body: IndexedStack(index: _index, children: _pages),
      bottomNavigationBar: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 非默认空间时常驻提示，避免把测试数据当成真实数据
          if (!current.isDefault) _SpaceBanner(name: current.name),
          NavigationBar(
            selectedIndex: _index,
            onDestinationSelected: (value) => setState(() => _index = value),
            destinations: const [
              NavigationDestination(
                icon: Icon(Icons.account_balance_wallet_outlined),
                selectedIcon: Icon(Icons.account_balance_wallet),
                label: '财务',
              ),
              NavigationDestination(
                icon: Icon(Icons.monitor_heart_outlined),
                selectedIcon: Icon(Icons.monitor_heart),
                label: '健康',
              ),
              NavigationDestination(
                icon: Icon(Icons.translate_outlined),
                selectedIcon: Icon(Icons.translate),
                label: '学习',
              ),
              NavigationDestination(
                icon: Icon(Icons.auto_awesome_outlined),
                selectedIcon: Icon(Icons.auto_awesome),
                label: 'AI',
              ),
              NavigationDestination(
                icon: Icon(Icons.person_outline),
                selectedIcon: Icon(Icons.person),
                label: '我的',
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SpaceBanner extends StatelessWidget {
  const _SpaceBanner({required this.name});

  final String name;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Material(
      color: scheme.tertiaryContainer,
      child: InkWell(
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (_) => const DataSpacesPage()),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          child: Row(
            children: [
              Icon(
                Icons.folder_special_outlined,
                size: 16,
                color: scheme.onTertiaryContainer,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '当前数据空间：$name · 点击切换',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: scheme.onTertiaryContainer,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Icon(
                Icons.chevron_right,
                size: 16,
                color: scheme.onTertiaryContainer,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
