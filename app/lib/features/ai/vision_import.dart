/// 截图识别：上传一张图，自动判断是支付账单、体重还是围度记录，
/// 给出对应草稿，确认后写入财务或健康模块。
///
/// 与文本记账不同，识图准确率依赖截图版式，因此一律先给草稿让用户确认。
/// 离线时会自动把截图存进队列，联网后重放识别。
library;

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/async_x.dart';
import '../../core/utils.dart';
import '../../data/ai/deepseek_client.dart';
import '../../data/ai/image_draft.dart';
import '../../data/ai/receipt_draft.dart';
import '../../data/ai_pending_repository.dart';
import '../../data/db/database.dart';
import '../../data/health_stats.dart';
import '../../data/providers.dart';
import '../finance/finance_providers.dart';
import 'ai_providers.dart';
import 'api_key_sheet.dart';

/// 入口：选图 → 自动识别并给出确认表单。
Future<void> openReceiptImport(BuildContext context, WidgetRef ref) async {
  final key = await ref.read(securityStoreProvider).readApiKey();
  if (key == null || key.isEmpty) {
    if (!context.mounted) return;
    await openApiKeyDialog(context, currentKey: key);
    return;
  }

  final file = await ImagePicker().pickImage(
    source: ImageSource.gallery,
    maxWidth: 1800,
    imageQuality: 85,
  );
  if (file == null || !context.mounted) return;

  final bytes = await file.readAsBytes();
  final mimeType = file.mimeType ??
      (file.name.toLowerCase().endsWith('.png') ? 'image/png' : 'image/jpeg');
  if (!context.mounted) return;

  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => _ImageSheet(
      apiKey: key,
      imageBytes: bytes,
      mimeType: mimeType,
    ),
  );
}

/// 入口：处理离线队列里已识别完成、等待确认的截图。
Future<void> openPendingReceipt(
  BuildContext context,
  WidgetRef ref,
  PendingTask task,
) async {
  final payload = task.payload;
  ImageDraft? draft;

  final imageJson = payload['imageDraft'];
  if (imageJson is Map<String, dynamic>) {
    draft = ImageDraft.fromJson(imageJson);
  }
  // 兼容旧队列里只存了支付草稿的任务
  if (draft == null) {
    final legacy = payload['draft'];
    if (legacy is Map<String, dynamic>) {
      final receipt = ReceiptDraft.fromJson(legacy);
      if (receipt != null) {
        draft = ImageDraft(
          type: ImageDraftType.transaction,
          confidence: receipt.confidence,
          receipt: receipt,
        );
      }
    }
  }

  if (draft == null || !draft.isUsable) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('这条任务还没有可用的识图结果')),
    );
    return;
  }

  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => _PendingImageSheet(task: task, draft: draft!),
  );
}

// ------------------------------------------------------------ 在线识图

class _ImageSheet extends ConsumerStatefulWidget {
  const _ImageSheet({
    required this.apiKey,
    required this.imageBytes,
    required this.mimeType,
  });

  final String apiKey;
  final List<int> imageBytes;
  final String mimeType;

  @override
  ConsumerState<_ImageSheet> createState() => _ImageSheetState();
}

class _ImageSheetState extends ConsumerState<_ImageSheet> {
  ImageDraft? _draft;
  String? _error;
  bool _loading = true;
  bool _canQueue = false;

  @override
  void initState() {
    super.initState();
    _extract();
  }

  Future<void> _extract() async {
    try {
      final raw = await ref.read(deepSeekClientProvider).extractFromImage(
            apiKey: widget.apiKey,
            imageBytes: widget.imageBytes,
            mimeType: widget.mimeType,
            instruction: imageExtractionInstruction,
          );
      final draft = ImageDraft.fromModelOutput(raw);
      if (!mounted) return;

      if (draft == null || !draft.isUsable) {
        setState(() {
          _loading = false;
          _error = '没能从截图里识别出账单、体重或围度信息。\n'
              '可以换一张更清晰、包含金额或数值的截图，或手动记录。';
        });
        return;
      }
      setState(() {
        _draft = draft;
        _loading = false;
      });
    } on DeepSeekException catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = error.message;
        // 网络类失败可以排队等联网重放
        _canQueue = true;
      });
    }
  }

  Future<void> _queueForLater() async {
    final path = await persistPendingScreenshot(
      Uint8List.fromList(widget.imageBytes),
      mimeType: widget.mimeType,
    );
    await ref.read(aiPendingRepositoryProvider).enqueue(
          type: PendingTaskType.vision,
          payloadJson: jsonEncode({'mimeType': widget.mimeType, 'mode': 'auto'}),
          imagePath: path,
        );
    if (!mounted) return;
    Navigator.of(context).pop();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('截图已存入离线队列，联网后自动识别')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('识别截图', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 16),
            if (_loading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 32),
                child: Column(
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(height: 12),
                    Text('正在识别截图…'),
                  ],
                ),
              )
            else if (_draft != null)
              ImageDraftContent(draft: _draft!)
            else ...[
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Text(_error ?? '识别失败', textAlign: TextAlign.center),
              ),
              if (_canQueue)
                FilledButton.icon(
                  onPressed: _queueForLater,
                  icon: const Icon(Icons.schedule),
                  label: const Text('存入离线队列，联网后自动识别'),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

// ------------------------------------------------------------ 离线待确认

class _PendingImageSheet extends ConsumerWidget {
  const _PendingImageSheet({required this.task, required this.draft});

  final PendingTask task;
  final ImageDraft draft;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Text('确认离线截图', style: theme.textTheme.titleLarge),
                const Spacer(),
                TextButton.icon(
                  onPressed: () async {
                    await ref
                        .read(aiPendingRepositoryProvider)
                        .remove(task.id);
                    if (context.mounted) Navigator.of(context).pop();
                  },
                  icon: const Icon(Icons.delete_outline, size: 18),
                  label: const Text('放弃'),
                  style: TextButton.styleFrom(
                    foregroundColor: theme.colorScheme.error,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              '排队于 ${formatDateTime(task.createdAt)}，识别已完成，确认后即可保存。',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.outline),
            ),
            const SizedBox(height: 16),
            ImageDraftContent(
              draft: draft,
              onSaved: () =>
                  ref.read(aiPendingRepositoryProvider).remove(task.id),
            ),
          ],
        ),
      ),
    );
  }
}

// ------------------------------------------------------------ 草稿分发

/// 按识别类型分发到记账 / 体重 / 围度表单。
class ImageDraftContent extends StatelessWidget {
  const ImageDraftContent({super.key, required this.draft, this.onSaved});

  final ImageDraft draft;
  final Future<void> Function()? onSaved;

  @override
  Widget build(BuildContext context) {
    return switch (draft.type) {
      ImageDraftType.transaction => ReceiptDraftForm(
          draft: draft.receipt!,
          onSaved: onSaved,
        ),
      ImageDraftType.weight => _WeightDraftForm(
          draft: draft,
          onSaved: onSaved,
        ),
      ImageDraftType.measure => _MeasureDraftForm(
          draft: draft,
          onSaved: onSaved,
        ),
      ImageDraftType.unknown => const Padding(
          padding: EdgeInsets.symmetric(vertical: 24),
          child: Text('没能识别出可用信息', textAlign: TextAlign.center),
        ),
    };
  }
}

// ------------------------------------------------------------ 体重草稿

class _WeightDraftForm extends ConsumerStatefulWidget {
  const _WeightDraftForm({required this.draft, this.onSaved});

  final ImageDraft draft;
  final Future<void> Function()? onSaved;

  @override
  ConsumerState<_WeightDraftForm> createState() => _WeightDraftFormState();
}

class _WeightDraftFormState extends ConsumerState<_WeightDraftForm> {
  late final TextEditingController _weight;
  late final TextEditingController _fat;
  bool _saving = false;

  DateTime get _at => widget.draft.measuredAt ?? DateTime.now();

  @override
  void initState() {
    super.initState();
    _weight = TextEditingController(
      text: widget.draft.weightGrams == null
          ? ''
          : formatKg(widget.draft.weightGrams!),
    );
    _fat = TextEditingController(
      text: widget.draft.bodyFatPct?.toString() ?? '',
    );
  }

  @override
  void dispose() {
    _weight.dispose();
    _fat.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final grams = parseKgToGrams(_weight.text);
    if (grams <= 0) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('请填写有效的体重')));
      return;
    }

    setState(() => _saving = true);
    try {
      await ref.read(healthRepositoryProvider).saveWeight(
            recordedAt: _at,
            grams: grams,
            bodyFatPct: double.tryParse(_fat.text.trim()),
          );
      await widget.onSaved?.call();
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已记录体重 ${formatKg(grams)} kg')),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('保存失败：$error')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          '置信度 ${(widget.draft.confidence * 100).toStringAsFixed(0)}%'
          ' · 体重记录 · ${formatDateTime(_at)}',
          style: theme.textTheme.bodySmall
              ?.copyWith(color: theme.colorScheme.outline),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _weight,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
          ],
          style: theme.textTheme.headlineSmall,
          decoration: const InputDecoration(
            labelText: '体重（kg）',
            prefixText: '',
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _fat,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
          ],
          decoration: const InputDecoration(labelText: '体脂率（%，可选）'),
        ),
        const SizedBox(height: 24),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: Text(_saving ? '保存中…' : '确认记录'),
        ),
      ],
    );
  }
}

// ------------------------------------------------------------ 围度草稿

class _MeasureDraftForm extends ConsumerStatefulWidget {
  const _MeasureDraftForm({required this.draft, this.onSaved});

  final ImageDraft draft;
  final Future<void> Function()? onSaved;

  @override
  ConsumerState<_MeasureDraftForm> createState() => _MeasureDraftFormState();
}

class _MeasureDraftFormState extends ConsumerState<_MeasureDraftForm> {
  late final List<(String, TextEditingController)> _items;
  bool _saving = false;

  DateTime get _at => widget.draft.measuredAt ?? DateTime.now();

  @override
  void initState() {
    super.initState();
    _items = [
      for (final point in widget.draft.measures)
        (point.part, TextEditingController(text: formatCm(point.mm))),
    ];
  }

  @override
  void dispose() {
    for (final item in _items) {
      item.$2.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    final repository = ref.read(healthRepositoryProvider);
    setState(() => _saving = true);
    try {
      var saved = 0;
      for (final item in _items) {
        final mm = parseCmToMm(item.$2.text);
        if (mm <= 0) continue;
        await repository.saveMeasure(
          measuredAt: _at,
          part: item.$1,
          mm: mm,
        );
        saved++;
      }
      if (saved == 0) {
        if (!mounted) return;
        setState(() => _saving = false);
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('请填写有效的围度数值')));
        return;
      }
      await widget.onSaved?.call();
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已记录 $saved 项围度')),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('保存失败：$error')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          '置信度 ${(widget.draft.confidence * 100).toStringAsFixed(0)}%'
          ' · 围度记录 · ${formatDateTime(_at)}',
          style: theme.textTheme.bodySmall
              ?.copyWith(color: theme.colorScheme.outline),
        ),
        const SizedBox(height: 12),
        for (final item in _items)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Row(
              children: [
                SizedBox(width: 96, child: Text(item.$1)),
                Expanded(
                  child: TextField(
                    controller: item.$2,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                    ],
                    decoration: const InputDecoration(
                      labelText: '数值（cm）',
                      isDense: true,
                    ),
                  ),
                ),
              ],
            ),
          ),
        const SizedBox(height: 12),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: Text(_saving ? '保存中…' : '确认记录'),
        ),
      ],
    );
  }
}

// ------------------------------------------------------------ 记账表单

/// 识图草稿的确认表单：在线识图与离线待确认共用。
class ReceiptDraftForm extends ConsumerStatefulWidget {
  const ReceiptDraftForm({super.key, required this.draft, this.onSaved});

  final ReceiptDraft draft;
  final Future<void> Function()? onSaved;

  @override
  ConsumerState<ReceiptDraftForm> createState() => _ReceiptDraftFormState();
}

class _ReceiptDraftFormState extends ConsumerState<ReceiptDraftForm> {
  late final TextEditingController _amount;
  late final TextEditingController _payee;
  String? _categoryId;
  String? _accountId;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _amount = TextEditingController(
      text: (widget.draft.amount / 100).toStringAsFixed(2),
    );
    _payee = TextEditingController(text: widget.draft.payee ?? '');
    final accounts = ref.read(accountsProvider).dataOrNull ?? const <Account>[];
    _accountId = accounts.isEmpty ? null : accounts.first.id;
  }

  @override
  void dispose() {
    _amount.dispose();
    _payee.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final draft = widget.draft;
    final categories =
        ref.watch(categoriesProvider).dataOrNull ?? const <Category>[];
    final accounts =
        ref.watch(accountsProvider).dataOrNull ?? const <Account>[];

    Category? matched;
    for (final item in categories) {
      if (item.kind == draft.kind && item.name == draft.categoryName) {
        matched = item;
        break;
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          '置信度 ${(draft.confidence * 100).toStringAsFixed(0)}%'
          '${draft.channel == null ? '' : ' · ${draft.channel}'}'
          '${draft.occurredAt == null ? '' : ' · ${formatDateTime(draft.occurredAt!)}'}',
          style: theme.textTheme.bodySmall
              ?.copyWith(color: theme.colorScheme.outline),
        ),
        const SizedBox(height: 12),
        SegmentedButton<TxnKind>(
          segments: const [
            ButtonSegment(value: TxnKind.expense, label: Text('支出')),
            ButtonSegment(value: TxnKind.income, label: Text('收入')),
          ],
          selected: {draft.kind},
          showSelectedIcon: false,
          onSelectionChanged: (values) => setState(() {
            draft.kind = values.first;
            _categoryId = null;
          }),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _amount,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
          ],
          style: theme.textTheme.headlineSmall,
          decoration: const InputDecoration(labelText: '金额', prefixText: '¥ '),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _payee,
          decoration: const InputDecoration(labelText: '商户 / 对方'),
        ),
        if (categories.isNotEmpty) ...[
          const SizedBox(height: 16),
          Text('分类', style: theme.textTheme.labelLarge),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final item in categories.where((c) => c.kind == draft.kind))
                ChoiceChip(
                  label: Text(item.name),
                  selected: _categoryId == item.id ||
                      (_categoryId == null && matched?.id == item.id),
                  onSelected: (_) => setState(() => _categoryId = item.id),
                ),
            ],
          ),
        ],
        if (accounts.isNotEmpty) ...[
          const SizedBox(height: 16),
          Text('账户', style: theme.textTheme.labelLarge),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final item in accounts)
                ChoiceChip(
                  label: Text(item.name),
                  selected: _accountId == item.id,
                  onSelected: (_) => setState(() => _accountId = item.id),
                ),
            ],
          ),
        ],
        const SizedBox(height: 24),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: Text(_saving ? '入账中…' : '确认入账'),
        ),
      ],
    );
  }

  Future<void> _save() async {
    final draft = widget.draft;
    final amount = parseYuanToCents(_amount.text);
    if (amount <= 0) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('请输入大于 0 的金额')));
      return;
    }

    final fingerprint = draft.fingerprint;
    setState(() => _saving = true);

    final finance = ref.read(financeRepositoryProvider);
    try {
      if (fingerprint != null &&
          await finance.existsByFingerprint(fingerprint)) {
        if (!mounted) return;
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('这张截图对应的账目已经记过了，未重复入账')),
        );
        return;
      }

      await finance.saveTransaction(
        kind: draft.kind,
        amount: amount,
        occurredAt: draft.occurredAt ?? DateTime.now(),
        categoryId: _categoryId ?? _matchedCategoryId(draft),
        accountId: _accountId,
        payee: _payee.text.trim().isEmpty ? null : _payee.text.trim(),
        source: TxnSource.ocr,
        confidence: draft.confidence,
        fingerprint: fingerprint,
        tradeNo: draft.tradeNo,
      );

      await widget.onSaved?.call();
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已入账 ¥${formatCents(amount)}')),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('入账失败：$error')));
    }
  }

  String? _matchedCategoryId(ReceiptDraft draft) {
    if (draft.categoryName == null) return null;
    final categories =
        ref.read(categoriesProvider).dataOrNull ?? const <Category>[];
    for (final item in categories) {
      if (item.kind == draft.kind && item.name == draft.categoryName) {
        return item.id;
      }
    }
    return null;
  }
}
