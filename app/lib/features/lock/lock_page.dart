/// 锁屏：首次进入引导设置 PIN，之后每次冷启动校验 PIN。
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/providers.dart';
import 'lock_state.dart';

class LockPage extends ConsumerStatefulWidget {
  const LockPage({super.key});

  @override
  ConsumerState<LockPage> createState() => _LockPageState();
}

class _LockPageState extends ConsumerState<LockPage> {
  final _controller = TextEditingController();
  String? _firstEntry;
  String? _error;
  bool _busy = false;
  int _failures = 0;
  bool _biometricAvailable = false;

  @override
  void initState() {
    super.initState();
    // 首帧结束后再读取，避免在 build 期间修改 provider 状态。
    WidgetsBinding.instance.addPostFrameCallback((_) => _prepareBiometric());
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// 检测指纹/面容是否可用；已设 PIN 时自动拉起一次验证。
  Future<void> _prepareBiometric() async {
    final service = ref.read(biometricServiceProvider);
    final hasPin = await ref.read(hasPinProvider.future);
    final available = await service.isAvailable();
    if (!mounted) return;
    setState(() => _biometricAvailable = available);
    if (!hasPin || !available) return;
    await _authenticateBiometric();
  }

  Future<void> _authenticateBiometric() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final ok = await ref
        .read(biometricServiceProvider)
        .authenticate(reason: '验证指纹以解锁朝夕册');
    if (!mounted) return;
    if (ok) {
      ref.read(lockStatusProvider.notifier).unlock();
      return;
    }
    setState(() {
      _busy = false;
      _error = '指纹验证未通过，请输入 PIN 解锁';
    });
  }

  Future<void> _submit(bool hasPin) async {
    final pin = _controller.text;
    if (pin.length < 4 || pin.length > 8) {
      setState(() => _error = 'PIN 需要 4-8 位数字');
      return;
    }

    final store = ref.read(securityStoreProvider);
    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      if (!hasPin) {
        if (_firstEntry == null) {
          setState(() {
            _firstEntry = pin;
            _controller.clear();
            _busy = false;
          });
          return;
        }
        if (_firstEntry != pin) {
          setState(() {
            _firstEntry = null;
            _controller.clear();
            _error = '两次输入不一致，请重新设置';
            _busy = false;
          });
          return;
        }
        await store.setPin(pin);
        ref.invalidate(hasPinProvider);
        if (!mounted) return;
        ref.read(lockStatusProvider.notifier).unlock();
        return;
      }

      final ok = await store.verifyPin(pin);
      if (!mounted) return;
      if (ok) {
        ref.read(lockStatusProvider.notifier).unlock();
        return;
      }
      setState(() {
        _failures++;
        _controller.clear();
        _error = 'PIN 不正确';
        _busy = false;
      });
    } finally {
      if (mounted && _busy) {
        setState(() => _busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasPinAsync = ref.watch(hasPinProvider);
    final theme = Theme.of(context);

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 360),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: hasPinAsync.when(
                loading: () => const CircularProgressIndicator(),
                error: (error, _) => Text('无法读取本地安全存储：$error'),
                data: (hasPin) => Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(18),
                      child: Image.asset(
                        'assets/branding/app_icon.png',
                        width: 76,
                        height: 76,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      '朝夕册',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.headlineSmall
                          ?.copyWith(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _subtitle(hasPin),
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium
                          ?.copyWith(color: theme.colorScheme.outline),
                    ),
                    const SizedBox(height: 28),
                    TextField(
                      controller: _controller,
                      autofocus: true,
                      obscureText: true,
                      keyboardType: TextInputType.number,
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                        LengthLimitingTextInputFormatter(8),
                      ],
                      textAlign: TextAlign.center,
                      decoration: const InputDecoration(
                        labelText: 'PIN 码',
                        hintText: '4-8 位数字',
                        counterText: '',
                      ),
                      onSubmitted: (_) => _submit(hasPin),
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 12),
                      Text(
                        _error!,
                        textAlign: TextAlign.center,
                        style: TextStyle(color: theme.colorScheme.error),
                      ),
                    ],
                    if (hasPin && _failures >= 3) ...[
                      const SizedBox(height: 8),
                      Text(
                        '已连续输错 $_failures 次',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: theme.colorScheme.outline),
                      ),
                    ],
                    const SizedBox(height: 20),
                    FilledButton(
                      onPressed: _busy ? null : () => _submit(hasPin),
                      child: Text(
                        hasPin
                            ? '解锁'
                            : (_firstEntry == null ? '设置 PIN' : '确认 PIN'),
                      ),
                    ),
                    if (hasPin && _biometricAvailable) ...[
                      const SizedBox(height: 12),
                      OutlinedButton.icon(
                        onPressed: _busy ? null : _authenticateBiometric,
                        icon: const Icon(Icons.fingerprint),
                        label: const Text('指纹解锁'),
                      ),
                    ],
                    const SizedBox(height: 12),
                    Text(
                      '数据只保存在本机，PIN 用于防止他人翻看；忘记 PIN 只能清空数据重来。',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: theme.colorScheme.outline),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  String _subtitle(bool hasPin) {
    if (!hasPin) {
      return _firstEntry == null ? '首次使用，请设置解锁 PIN' : '请再次输入以确认';
    }
    return '输入 PIN 解锁';
  }
}
