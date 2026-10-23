/// AI 助手：会话列表 + 对话界面 + 识图记账入口。
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/async_x.dart';
import '../../data/ai/deepseek_client.dart';
import '../../data/ai_pending_repository.dart';
import '../../data/db/database.dart';
import '../../data/providers.dart';
import 'ai_providers.dart';
import 'api_key_sheet.dart';
import 'assistant_name_dialog.dart';
import 'markdown_message.dart';
import 'speech_input.dart';
import 'vision_import.dart';

class AiPage extends ConsumerStatefulWidget {
  const AiPage({super.key});

  @override
  ConsumerState<AiPage> createState() => _AiPageState();
}

class _AiPageState extends ConsumerState<AiPage> {
  static const _suggestions = <String>[
    '午饭 30',
    '工资 8000 存进储蓄卡0137',
    '微信转 500 到支付宝',
    '我现在总资产多少',
    '这个月预算设 3000',
    '记腰围 78.5',
    '今天要复习多少单词',
    '最近状态怎么样',
  ];

  final _input = TextEditingController();
  final _scroll = ScrollController();
  String? _sessionId;

  /// 点了「新会话」但还没发第一条消息：此时不要自动回落到最近会话。
  bool _startingNew = false;
  bool _sending = false;
  bool _replaying = false;

  /// 正在流式接收的助手回复；为 null 表示当前没有进行中的回复。
  String? _draft;

  /// 按住说话：长按输入框开始录音。
  bool _holdActive = false;
  bool _recording = false;
  bool _cancelArmed = false;

  /// 每次录音的会话号；取消或发送后自增，丢弃迟到的识别回调。
  int _voiceSession = 0;

  /// 页面用过语音输入时记下实现，dispose 里用它停止拾音。
  SpeechInput? _speech;

  @override
  void initState() {
    super.initState();
    // 进页面时先试着把离线队列补做掉
    WidgetsBinding.instance.addPostFrameCallback((_) => _replayQueue());
  }

  @override
  void dispose() {
    if (_recording) {
      unawaited(_speech?.cancel() ?? Future<void>.value());
    }
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final sessions =
        ref.watch(chatSessionsProvider).dataOrNull ?? const <ChatSession>[];
    final configured = ref.watch(apiKeyConfiguredProvider).dataOrNull ?? false;
    final assistantName =
        ref.watch(assistantNameProvider).dataOrNull ?? defaultAssistantName;
    final pending =
        ref.watch(pendingTasksProvider).dataOrNull ?? const <PendingTask>[];

    if (_sessionId == null && !_startingNew && sessions.isNotEmpty) {
      _sessionId = sessions.first.id;
    }

    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      appBar: AppBar(
        centerTitle: true,
        backgroundColor: theme.colorScheme.surface,
        surfaceTintColor: Colors.transparent,
        title: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(assistantName, style: theme.textTheme.titleMedium),
            const SizedBox(height: 1),
            Text(
              'AI 生成可能有误，注意核实',
              style: theme.textTheme.bodySmall?.copyWith(
                fontSize: 11,
                color: theme.colorScheme.outline,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: '给助手改名',
            icon: const Icon(Icons.badge_outlined),
            onPressed: () =>
                openAssistantNameDialog(context, ref, current: assistantName),
          ),
          IconButton(
            tooltip: '上传图片',
            icon: const Icon(Icons.add_photo_alternate_outlined),
            onPressed: () => openReceiptImport(context, ref),
          ),
          IconButton(
            tooltip: 'API Key',
            icon: const Icon(Icons.vpn_key_outlined),
            onPressed: () => _openKey(configured),
          ),
        ],
      ),
      drawer: Drawer(child: _buildSessionDrawer(sessions)),
      body: Column(
        children: [
          if (!configured)
            MaterialBanner(
              content: const Text('未配置 DeepSeek API Key，将用本地规则兜底记账'),
              leading: const Icon(Icons.info_outline),
              actions: [
                TextButton(
                  onPressed: () => _openKey(configured),
                  child: const Text('去配置'),
                ),
              ],
            ),
          if (pending.isNotEmpty) _buildPendingBanner(pending),
          Expanded(child: _buildMessages()),
          _buildComposer(),
        ],
      ),
    );
  }

  Widget _buildSessionDrawer(List<ChatSession> sessions) {
    return SafeArea(
      child: Column(
        children: [
          ListTile(
            leading: const Icon(Icons.add),
            title: const Text('新会话'),
            onTap: () {
              setState(() {
                _sessionId = null;
                _startingNew = true;
              });
              Navigator.of(context).pop();
            },
          ),
          const Divider(height: 1),
          Expanded(
            child: sessions.isEmpty
                ? const Center(child: Text('还没有会话'))
                : ListView.builder(
                    itemCount: sessions.length,
                    itemBuilder: (context, index) {
                      final session = sessions[index];
                      return ListTile(
                        title: Text(
                          session.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(formatShortDate(session.createdAt)),
                        selected: session.id == _sessionId,
                        trailing: IconButton(
                          icon: const Icon(Icons.delete_outline, size: 18),
                          onPressed: () async {
                            await ref
                                .read(aiRepositoryProvider)
                                .deleteSession(session.id);
                            if (_sessionId == session.id) {
                              setState(() => _sessionId = null);
                            }
                          },
                        ),
                        onTap: () {
                          setState(() {
                            _sessionId = session.id;
                            _startingNew = false;
                          });
                          Navigator.of(context).pop();
                        },
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildMessages() {
    final sessionId = _sessionId;
    final messages = sessionId == null
        ? const <ChatMessage>[]
        : (ref.watch(chatMessagesProvider(sessionId)).dataOrNull ??
              const <ChatMessage>[]);
    final draft = _draft;

    if (draft == null && messages.isEmpty) return _buildWelcome();

    return ListView.builder(
      controller: _scroll,
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 24),
      itemCount: messages.length + (draft == null ? 0 : 1),
      itemBuilder: (context, index) {
        if (index < messages.length) {
          return _bubble(messages[index], messages);
        }
        return _draftBubble(draft);
      },
    );
  }

  Widget _buildWelcome() {
    final theme = Theme.of(context);
    final name =
        ref.watch(assistantNameProvider).dataOrNull ?? defaultAssistantName;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 48, 24, 24),
      child: Column(
        children: [
          Container(
            width: 76,
            height: 76,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [theme.colorScheme.primary, theme.colorScheme.tertiary],
              ),
            ),
            child: const Icon(
              Icons.auto_awesome,
              size: 34,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 18),
          Text('你好，我是$name', style: theme.textTheme.headlineSmall),
          const SizedBox(height: 10),
          Text(
            '记账、转账、账户与预算、体重围度运动、背单词，说一声我就能直接帮你操作。\n'
            '没网或没配 Key 时会自动切到本地规则记账。',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.outline,
              height: 1.6,
            ),
          ),
          const SizedBox(height: 28),
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              '试试这样说',
              style: theme.textTheme.labelMedium?.copyWith(
                color: theme.colorScheme.outline,
              ),
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final suggestion in _suggestions)
                _SuggestionChip(
                  label: suggestion,
                  onTap: _sending ? null : () => _send(suggestion),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _bubble(ChatMessage message, List<ChatMessage> all) {
    final theme = Theme.of(context);

    // 豆包式布局：用户消息是右侧蓝色气泡，助手回复直接平铺在背景上。
    if (message.role == 'user') {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Align(
            alignment: Alignment.centerRight,
            child: GestureDetector(
              onLongPress: () => _showMessageActions(message, all),
              child: Container(
                margin: const EdgeInsets.only(bottom: 4),
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 11,
                ),
                constraints: BoxConstraints(
                  maxWidth: MediaQuery.of(context).size.width * 0.76,
                ),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary,
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(20),
                    topRight: Radius.circular(20),
                    bottomLeft: Radius.circular(20),
                    bottomRight: Radius.circular(6),
                  ),
                ),
                child: Text(
                  message.content,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onPrimary,
                    height: 1.45,
                  ),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: _MessageActionRow(onCopy: () => _copyText(message.content)),
          ),
        ],
      );
    }

    return GestureDetector(
      onLongPress: () => _showMessageActions(message, all),
      child: Container(
        margin: const EdgeInsets.only(bottom: 22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            MarkdownMessage(data: message.content),
            const SizedBox(height: 6),
            _MessageActionRow(onCopy: () => _copyText(message.content)),
          ],
        ),
      ),
    );
  }

  /// 流式接收中的助手回复：没有正文时显示「正在思考」。
  Widget _draftBubble(String? text) {
    final theme = Theme.of(context);

    return Container(
      margin: const EdgeInsets.only(bottom: 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (text == null || text.isEmpty)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                const SizedBox(width: 8),
                Text(
                  '正在思考…',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.outline,
                  ),
                ),
              ],
            )
          else
            MarkdownMessage(data: text),
        ],
      ),
    );
  }

  Future<void> _copyText(String text) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('已复制到剪贴板')));
  }

  Future<void> _showMessageActions(
    ChatMessage message,
    List<ChatMessage> all,
  ) async {
    final name =
        ref.read(assistantNameProvider).dataOrNull ?? defaultAssistantName;

    final action = await showModalBottomSheet<_MessageAction>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.copy_outlined),
              title: const Text('复制这条'),
              onTap: () =>
                  Navigator.of(sheetContext).pop(_MessageAction.single),
            ),
            ListTile(
              leading: const Icon(Icons.chat_outlined),
              title: const Text('复制整段对话'),
              onTap: () => Navigator.of(sheetContext).pop(_MessageAction.all),
            ),
          ],
        ),
      ),
    );
    if (action == null || !mounted) return;

    final text = switch (action) {
      _MessageAction.single => message.content,
      _MessageAction.all => [
        for (final item in all)
          '${item.role == 'user' ? '我' : name}：${item.content}',
      ].join('\n\n'),
    };

    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('已复制到剪贴板')));
  }

  Widget _buildComposer() {
    final theme = Theme.of(context);

    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(
          top: BorderSide(
            color: theme.colorScheme.outlineVariant.withValues(alpha: 0.35),
          ),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_recording)
              Center(child: _buildVoiceStatus())
            else
              _buildQuickPrompts(),
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 6, 10, 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  IconButton(
                    tooltip: '上传图片',
                    onPressed: _sending
                        ? null
                        : () => openReceiptImport(context, ref),
                    icon: const Icon(Icons.add_photo_alternate_outlined),
                  ),
                  Expanded(
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        Container(
                          constraints: const BoxConstraints(minHeight: 48),
                          padding: const EdgeInsets.symmetric(horizontal: 18),
                          decoration: BoxDecoration(
                            color: _recording
                                ? theme.colorScheme.primary.withValues(
                                    alpha: 0.12,
                                  )
                                : theme.colorScheme.surfaceContainerHighest
                                      .withValues(alpha: 0.65),
                            borderRadius: BorderRadius.circular(26),
                          ),
                          child: TextField(
                            controller: _input,
                            minLines: 1,
                            maxLines: 4,
                            textInputAction: TextInputAction.send,
                            style: theme.textTheme.bodyMedium,
                            decoration: InputDecoration(
                              hintText: '发消息或按住说话……',
                              hintStyle: theme.textTheme.bodyMedium?.copyWith(
                                color: theme.colorScheme.outline,
                              ),
                              border: InputBorder.none,
                              isDense: true,
                              contentPadding: const EdgeInsets.symmetric(
                                vertical: 13,
                              ),
                            ),
                            onSubmitted: (_) => _send(),
                          ),
                        ),
                        // 透明覆盖层只接管长按，不拦截点击输入。
                        Positioned.fill(
                          child: GestureDetector(
                            behavior: HitTestBehavior.translucent,
                            onLongPressStart: _onVoiceHoldStart,
                            onLongPressMoveUpdate: _onVoiceHoldMove,
                            onLongPressEnd: _onVoiceHoldEnd,
                            onLongPressCancel: _onVoiceHoldCancel,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    onPressed: _sending ? null : () => _send(),
                    style: IconButton.styleFrom(
                      minimumSize: const Size(48, 48),
                    ),
                    icon: _sending
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.send),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 输入框上方的快捷入口，点击后把示例填进输入框，方便改一改再发。
  Widget _buildQuickPrompts() {
    const prompts = <(String, String)>[
      ('记一笔', '午饭 30'),
      ('查收支', '这个月花了多少'),
      ('看健康', '我最近体重多少'),
      ('背单词', '今天要复习多少单词'),
    ];

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      child: Row(
        children: [
          for (final (label, example) in prompts)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ActionChip(
                visualDensity: VisualDensity.compact,
                label: Text(label),
                onPressed: _sending
                    ? null
                    : () {
                        _input.text = example;
                        _input.selection = TextSelection.collapsed(
                          offset: example.length,
                        );
                      },
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _send([String? preset]) async {
    final text = (preset ?? _input.text).trim();
    if (text.isEmpty || _sending) return;
    if (_recording) await _cancelVoice();

    final service = ref.read(aiServiceProvider);
    setState(() {
      _sending = true;
      _draft = '';
    });

    var usedLocalRules = false;
    try {
      var sessionId = _sessionId;
      if (sessionId == null) {
        final session = await ref
            .read(aiRepositoryProvider)
            .createSession(
              title: service.titleFrom(text),
              model: DeepSeekClient.textModel,
            );
        sessionId = session.id;
        _sessionId = sessionId;
        _startingNew = false;
      }

      _input.clear();
      // 流式接收：delta 逐段进气泡，reply 表示本轮结束且消息已落库
      await for (final chunk in service.sendStream(
        sessionId: sessionId,
        text: text,
      )) {
        final delta = chunk.delta;
        if (delta != null) {
          if (!mounted) continue;
          setState(() => _draft = '${_draft ?? ''}$delta');
          _scrollToEnd(animate: false);
        }
        final reply = chunk.reply;
        if (reply != null) usedLocalRules = reply.usedLocalRules;
      }

      if (!mounted) return;
      if (usedLocalRules) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('已使用本地规则（离线兜底）')));
      } else {
        // 能拿到模型回复说明网络已恢复，顺手把离线队列补做掉
        await _replayQueue();
      }
      _scrollToEnd();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('发送失败：$error')));
    } finally {
      if (mounted) {
        setState(() {
          _sending = false;
          _draft = null;
        });
      }
    }
  }

  // ----------------------------------------------------------- 按住说话

  void _onVoiceHoldStart(LongPressStartDetails details) {
    // 输入框有内容时保留系统选择/编辑手势，不触发说话。
    if (_sending || _recording || _input.text.isNotEmpty) return;
    _holdActive = true;
    _cancelArmed = false;
    unawaited(_beginVoiceHold());
  }

  void _onVoiceHoldMove(LongPressMoveUpdateDetails details) {
    if (!_recording) return;
    // 豆包交互：按住后上滑一定距离松手即取消。
    final armed = details.offsetFromOrigin.dy < -80;
    if (armed == _cancelArmed) return;
    // 滑入/滑出取消区时各给一次轻点反馈
    unawaited(HapticFeedback.lightImpact());
    setState(() => _cancelArmed = armed);
  }

  void _onVoiceHoldEnd(LongPressEndDetails details) {
    _holdActive = false;
    if (_recording) unawaited(_endVoiceHold());
  }

  void _onVoiceHoldCancel() {
    _holdActive = false;
    if (_recording) unawaited(_cancelVoice());
  }

  Future<void> _beginVoiceHold() async {
    if (_recording) return;
    final session = ++_voiceSession;
    final speech = ref.read(speechInputProvider);
    _speech = speech;

    final ready = await speech.ensureReady();
    if (!mounted) return;
    if (!ready) {
      _holdActive = false;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('这台设备暂时用不了语音输入，先用键盘吧')));
      return;
    }

    final started = await speech.start(
      onResult: (text, isFinal) {
        if (!mounted || session != _voiceSession) return;
        if (text.isEmpty) return;
        _input.text = text;
        _input.selection = TextSelection.collapsed(offset: text.length);
      },
    );

    if (!mounted || session != _voiceSession) return;
    if (!started) {
      _holdActive = false;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('没能启动语音识别，请检查麦克风权限')));
      return;
    }
    if (!_holdActive) {
      // 手指在初始化期间已经抬起：不保留这段录音
      await speech.cancel();
      return;
    }
    // 真正开始拾音后再给触感反馈
    unawaited(HapticFeedback.mediumImpact());
    setState(() {
      _recording = true;
      _cancelArmed = false;
    });
  }

  /// 松开手指：未上滑则结束识别并直接发送，上滑则取消。
  Future<void> _endVoiceHold() async {
    final cancel = _cancelArmed;
    _holdActive = false;
    _cancelArmed = false;
    setState(() => _recording = false);

    if (cancel) {
      unawaited(HapticFeedback.heavyImpact());
      await _cancelVoice();
      return;
    }

    // stop() 返回前会把最后一段识别结果定稿写入输入框
    await _speech?.stop();
    if (!mounted) return;

    final text = _input.text.trim();
    // 让迟到的识别回调失效，避免发送后又把旧文字写回输入框
    _voiceSession++;
    if (text.isEmpty) {
      _input.clear();
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('没听清，请再说一次')));
      return;
    }

    _input.text = text;
    _input.selection = TextSelection.collapsed(offset: text.length);
    await _send();
  }

  /// 取消本轮语音输入，丢弃已识别的文字与迟到的结果。
  Future<void> _cancelVoice() async {
    _voiceSession++;
    _holdActive = false;
    _cancelArmed = false;
    if (_recording) setState(() => _recording = false);
    _input.clear();
    await _speech?.cancel();
  }

  Widget _buildVoiceStatus() {
    final theme = Theme.of(context);
    final cancel = _cancelArmed;
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
      decoration: BoxDecoration(
        color: cancel
            ? theme.colorScheme.errorContainer
            : theme.colorScheme.primary.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(22),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            cancel ? Icons.close : Icons.mic,
            size: 16,
            color: cancel
                ? theme.colorScheme.onErrorContainer
                : theme.colorScheme.primary,
          ),
          const SizedBox(width: 6),
          Text(
            cancel ? '松开取消' : '松开发送，上滑取消',
            style: theme.textTheme.bodySmall?.copyWith(
              color: cancel
                  ? theme.colorScheme.onErrorContainer
                  : theme.colorScheme.primary,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _openKey(bool configured) async {
    final key = configured
        ? await ref.read(securityStoreProvider).readApiKey()
        : null;
    if (!mounted) return;
    await openApiKeyDialog(context, currentKey: key);
  }

  void _scrollToEnd({bool animate = true}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      final target = _scroll.position.maxScrollExtent;
      // 用户往上翻看历史时不要把他拽回底部
      final nearBottom = _scroll.position.pixels >= target - 120;
      if (!nearBottom) return;
      if (animate) {
        _scroll.animateTo(
          target,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      } else {
        _scroll.jumpTo(target);
      }
    });
  }

  // ---------------------------------------------------------- 离线队列

  Widget _buildPendingBanner(List<PendingTask> tasks) {
    final theme = Theme.of(context);
    final awaiting = tasks
        .where((task) => task.status == PendingTaskStatus.awaiting)
        .length;
    final waiting = tasks.length - awaiting;

    final parts = <String>[
      if (awaiting > 0) '$awaiting 张截图待确认',
      if (waiting > 0) '$waiting 条待联网重放',
    ];

    return Material(
      color: theme.colorScheme.secondaryContainer,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 6, 8, 6),
        child: Row(
          children: [
            Icon(
              Icons.cloud_off_outlined,
              size: 20,
              color: theme.colorScheme.onSecondaryContainer,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                '离线队列：${parts.join('，')}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSecondaryContainer,
                ),
              ),
            ),
            TextButton(onPressed: _showPendingSheet, child: const Text('查看')),
            TextButton(
              onPressed: _replaying ? null : _replayQueue,
              child: const Text('重放'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _replayQueue() async {
    if (_replaying) return;
    _replaying = true;
    try {
      final report = await ref.read(aiQueueWorkerProvider).replayAll();
      if (!mounted || report.isEmpty) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('离线队列：${report.summary}')));
    } finally {
      _replaying = false;
    }
  }

  Future<void> _showPendingSheet() {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => const _PendingTasksSheet(),
    );
  }
}

/// 离线队列清单：可重试、可放弃，待确认的截图点进去确认入账。
class _PendingTasksSheet extends ConsumerWidget {
  const _PendingTasksSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final tasks =
        ref.watch(pendingTasksProvider).dataOrNull ?? const <PendingTask>[];

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text('离线队列', style: theme.textTheme.titleLarge),
              const Spacer(),
              TextButton(
                onPressed: () async {
                  await ref.read(aiQueueWorkerProvider).replayAll();
                },
                child: const Text('全部重放'),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '没网时排队的请求会存在这里；联网后自动补做，也可以手动重放。',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.outline,
            ),
          ),
          const SizedBox(height: 12),
          if (tasks.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 32),
              child: Center(child: Text('队列是空的')),
            )
          else
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: tasks.length,
                separatorBuilder: (_, _) => const Divider(height: 1),
                itemBuilder: (context, index) =>
                    _buildRow(context, ref, tasks[index]),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildRow(BuildContext context, WidgetRef ref, PendingTask task) {
    final awaiting = task.status == PendingTaskStatus.awaiting;

    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(
        task.type == PendingTaskType.vision
            ? Icons.receipt_long_outlined
            : Icons.chat_bubble_outline,
      ),
      title: Text('${task.type.label} · ${task.status.label}'),
      subtitle: Text(
        task.lastError == null
            ? formatShortDate(task.createdAt)
            : '${formatShortDate(task.createdAt)}\n${task.lastError}',
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (awaiting)
            TextButton(
              onPressed: () async {
                Navigator.of(context).pop();
                await openPendingReceipt(context, ref, task);
              },
              child: const Text('确认'),
            )
          else
            IconButton(
              tooltip: '重试',
              icon: const Icon(Icons.refresh),
              onPressed: () async {
                await ref.read(aiQueueWorkerProvider).retry(task.id);
                await ref.read(aiQueueWorkerProvider).replayAll();
              },
            ),
          IconButton(
            tooltip: '放弃',
            icon: const Icon(Icons.delete_outline),
            onPressed: () =>
                ref.read(aiPendingRepositoryProvider).remove(task.id),
          ),
        ],
      ),
    );
  }
}

/// 欢迎页的示例胶囊。
class _SuggestionChip extends StatelessWidget {
  const _SuggestionChip({required this.label, required this.onTap});

  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.55),
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          child: Text(
            label,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ),
    );
  }
}

/// 消息下方的轻量操作栏（目前提供复制），用户与助手消息共用。
class _MessageActionRow extends StatelessWidget {
  const _MessageActionRow({required this.onCopy});

  final VoidCallback onCopy;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        TextButton.icon(
          onPressed: onCopy,
          icon: const Icon(Icons.copy_outlined, size: 15),
          label: const Text('复制'),
          style: TextButton.styleFrom(
            foregroundColor: theme.colorScheme.outline,
            textStyle: theme.textTheme.labelSmall,
            padding: const EdgeInsets.symmetric(horizontal: 6),
            minimumSize: const Size(0, 28),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
        ),
      ],
    );
  }
}

/// 会话列表里的简短日期。
String formatShortDate(DateTime value) =>
    '${value.month.toString().padLeft(2, '0')}-'
    '${value.day.toString().padLeft(2, '0')} '
    '${value.hour.toString().padLeft(2, '0')}:'
    '${value.minute.toString().padLeft(2, '0')}';

/// 长按消息后的复制范围。
enum _MessageAction { single, all }
