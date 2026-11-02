/// 健康记录编辑器：体重 / 围度 / 运动三种底部弹层。
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils.dart';
import '../../data/health_stats.dart';
import '../../data/providers.dart';

// ------------------------------------------------------------ 入口

Future<void> openWeightEditor(BuildContext context, {WeightEntry? existing}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => _WeightEditor(existing: existing),
  );
}

Future<void> openMeasureEditor(
  BuildContext context, {
  MeasureEntry? existing,
  List<String> knownParts = const [],
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => _MeasureEditor(existing: existing, knownParts: knownParts),
  );
}

Future<void> openWorkoutEditor(BuildContext context, {WorkoutEntry? existing}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => _WorkoutEditor(existing: existing),
  );
}

// ------------------------------------------------------------ 体重

class _WeightEditor extends ConsumerStatefulWidget {
  const _WeightEditor({this.existing});

  final WeightEntry? existing;

  @override
  ConsumerState<_WeightEditor> createState() => _WeightEditorState();
}

class _WeightEditorState extends ConsumerState<_WeightEditor> {
  late final TextEditingController _weight;
  late final TextEditingController _bodyFat;
  late final TextEditingController _note;
  late DateTime _at;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    _weight = TextEditingController(
      text: existing == null ? '' : formatKg(existing.grams),
    );
    _bodyFat = TextEditingController();
    _note = TextEditingController();
    _at = existing?.at ?? DateTime.now();
  }

  @override
  void dispose() {
    _weight.dispose();
    _bodyFat.dispose();
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _SheetBody(
      title: widget.existing == null ? '记录体重' : '编辑体重',
      onDelete: widget.existing == null
          ? null
          : () => _handle(
                () => ref
                    .read(healthRepositoryProvider)
                    .deleteWeight(widget.existing!.id),
              ),
      saving: _saving,
      onSave: _save,
      children: [
        _NumberField(
          controller: _weight,
          label: '体重',
          suffixText: 'kg',
        ),
        const SizedBox(height: 12),
        _NumberField(controller: _bodyFat, label: '体脂率（%，可选）'),
        _DateTimeTile(
          value: _at,
          onChanged: (value) => setState(() => _at = value),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _note,
          decoration: const InputDecoration(labelText: '备注'),
        ),
      ],
    );
  }

  Future<void> _save() async {
    final grams = parseKgToGrams(_weight.text);
    if (grams <= 0) {
      _notify('请填写有效的体重');
      return;
    }
    await _handle(
      () => ref.read(healthRepositoryProvider).saveWeight(
            id: widget.existing?.id,
            recordedAt: _at,
            grams: grams,
            bodyFatPct: double.tryParse(_bodyFat.text.trim()),
            note: _note.text.trim().isEmpty ? null : _note.text.trim(),
          ),
    );
  }

  Future<void> _handle(Future<void> Function() action) async {
    setState(() => _saving = true);
    try {
      await action();
      if (mounted) Navigator.of(context).pop();
    } catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      _notify('操作失败：$error');
    }
  }

  void _notify(String message) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
}

// ------------------------------------------------------------ 围度

class _MeasureEditor extends ConsumerStatefulWidget {
  const _MeasureEditor({this.existing, this.knownParts = const []});

  final MeasureEntry? existing;
  final List<String> knownParts;

  @override
  ConsumerState<_MeasureEditor> createState() => _MeasureEditorState();
}

class _MeasureEditorState extends ConsumerState<_MeasureEditor> {
  late final Map<String, TextEditingController> _values;
  late final TextEditingController _value;
  late final TextEditingController _note;
  late String _part;
  late DateTime _at;
  bool _saving = false;

  bool get _creating => widget.existing == null;

  List<String> get _partOptions {
    final options = <String>[
      ...defaultMeasureParts,
      for (final part in widget.knownParts)
        if (!defaultMeasureParts.contains(part) &&
            !removedMeasureParts.contains(part))
          part,
    ];
    final current = widget.existing?.part;
    if (current != null && !options.contains(current)) options.add(current);
    return options;
  }

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    _value = TextEditingController(
      text: existing == null ? '' : formatCm(existing.mm),
    );
    _values = {
      for (final part in coreMeasureParts)
        part: TextEditingController(),
    };
    _note = TextEditingController();
    _part = existing?.part ?? coreMeasureParts.first;
    _at = existing?.at ?? DateTime.now();
  }

  @override
  void dispose() {
    _value.dispose();
    for (final controller in _values.values) {
      controller.dispose();
    }
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return _SheetBody(
      title: _creating ? '记录围度' : '编辑围度',
      onDelete: widget.existing == null
          ? null
          : () => _handle(
                () => ref
                    .read(healthRepositoryProvider)
                    .deleteMeasure(widget.existing!.id),
              ),
      saving: _saving,
      onSave: _save,
      children: [
        if (!_creating) ...[
          Align(
            alignment: Alignment.centerLeft,
            child: Text('部位', style: theme.textTheme.labelLarge),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final option in _partOptions)
                ChoiceChip(
                  label: Text(option),
                  selected: _part == option,
                  onSelected: (_) => setState(() => _part = option),
                ),
            ],
          ),
          const SizedBox(height: 16),
          _NumberField(
            controller: _value,
            label: '数值',
            suffixText: 'cm',
          ),
        ] else ...[
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              '六项围度（cm，可只填有数据的项）',
              style: theme.textTheme.labelLarge,
            ),
          ),
          const SizedBox(height: 10),
          for (var row = 0; row < 2; row++) ...[
            Row(
              children: [
                for (var column = 0; column < 3; column++) ...[
                  if (column > 0) const SizedBox(width: 8),
                  Expanded(
                    child: _NumberField(
                      controller:
                          _values[coreMeasureParts[row * 3 + column]]!,
                      label: coreMeasureParts[row * 3 + column],
                      suffixText: 'cm',
                    ),
                  ),
                ],
              ],
            ),
            if (row == 0) const SizedBox(height: 12),
          ],
        ],
        _DateTimeTile(
          value: _at,
          onChanged: (value) => setState(() => _at = value),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _note,
          decoration: const InputDecoration(labelText: '备注', hintText: '选填'),
        ),
      ],
    );
  }

  Future<void> _save() async {
    if (_creating) {
      final values = <String, int>{};
      for (final entry in _values.entries) {
        final text = entry.value.text.trim();
        if (text.isEmpty) continue;
        final mm = parseCmToMm(text);
        if (mm <= 0) {
          _notify('「${entry.key}」请填写有效数值');
          return;
        }
        values[entry.key] = mm;
      }
      if (values.isEmpty) {
        _notify('请至少填写一项围度');
        return;
      }
      await _handle(
        () => ref.read(healthRepositoryProvider).saveMeasures(
              measuredAt: _at,
              values: values,
              note: _note.text.trim().isEmpty ? null : _note.text.trim(),
            ),
      );
      return;
    }

    final mm = parseCmToMm(_value.text);
    if (mm <= 0) {
      _notify('请填写有效的数值');
      return;
    }
    await _handle(
      () => ref.read(healthRepositoryProvider).saveMeasure(
            id: widget.existing?.id,
            measuredAt: _at,
            part: _part,
            mm: mm,
            note: _note.text.trim().isEmpty ? null : _note.text.trim(),
          ),
    );
  }

  Future<void> _handle(Future<void> Function() action) async {
    setState(() => _saving = true);
    try {
      await action();
      if (mounted) Navigator.of(context).pop();
    } catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      _notify('操作失败：$error');
    }
  }

  void _notify(String message) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
}

// ------------------------------------------------------------ 运动

class _WorkoutEditor extends ConsumerStatefulWidget {
  const _WorkoutEditor({this.existing});

  final WorkoutEntry? existing;

  @override
  ConsumerState<_WorkoutEditor> createState() => _WorkoutEditorState();
}

class _WorkoutEditorState extends ConsumerState<_WorkoutEditor> {
  late final TextEditingController _hours;
  late final TextEditingController _minutes;
  late final TextEditingController _distance;
  late final TextEditingController _calories;
  late final TextEditingController _avgHr;
  late final TextEditingController _note;
  late String _type;
  late DateTime _at;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    final totalMinutes = existing?.minutes ?? 0;
    _hours = TextEditingController(
      text: totalMinutes == 0 ? '' : '${totalMinutes ~/ 60}',
    );
    _minutes = TextEditingController(
      text: totalMinutes == 0 ? '' : '${totalMinutes % 60}',
    );
    _distance = TextEditingController(
      text: existing?.meters == null ? '' : formatKm(existing!.meters!),
    );
    _calories = TextEditingController(
      text: existing?.calories?.toString() ?? '',
    );
    _avgHr = TextEditingController(text: existing?.avgHr?.toString() ?? '');
    _note = TextEditingController();
    _type = existing?.type ?? workoutTypes.first;
    _at = existing?.at ?? DateTime.now();
  }

  @override
  void dispose() {
    _hours.dispose();
    _minutes.dispose();
    _distance.dispose();
    _calories.dispose();
    _avgHr.dispose();
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _SheetBody(
      title: widget.existing == null ? '记录运动' : '编辑运动',
      onDelete: widget.existing == null
          ? null
          : () => _handle(
                () => ref
                    .read(healthRepositoryProvider)
                    .deleteWorkout(widget.existing!.id),
              ),
      saving: _saving,
      onSave: _save,
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: Text('类型', style: Theme.of(context).textTheme.labelLarge),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final option in workoutTypes)
              ChoiceChip(
                label: Text(option),
                selected: _type == option,
                onSelected: (_) => setState(() => _type = option),
              ),
          ],
        ),
        const SizedBox(height: 16),
        Align(
          alignment: Alignment.centerLeft,
          child: Text('时长', style: Theme.of(context).textTheme.labelLarge),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: _NumberField(
                controller: _hours,
                label: '小时',
                digitsOnly: true,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _NumberField(
                controller: _minutes,
                label: '分钟',
                digitsOnly: true,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        _NumberField(controller: _distance, label: '距离（km，可选）'),
        const SizedBox(height: 12),
        _NumberField(controller: _calories, label: '消耗（kcal，可选）'),
        const SizedBox(height: 12),
        _NumberField(controller: _avgHr, label: '平均心率（可选）'),
        _DateTimeTile(
          value: _at,
          onChanged: (value) => setState(() => _at = value),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _note,
          decoration: const InputDecoration(labelText: '备注', hintText: '选填'),
        ),
      ],
    );
  }

  Future<void> _save() async {
    final hours = int.tryParse(_hours.text.trim()) ?? 0;
    final minutesPart = int.tryParse(_minutes.text.trim()) ?? 0;
    if (minutesPart > 59) {
      _notify('分钟需要填写 0-59');
      return;
    }
    final minutes = hours * 60 + minutesPart;
    if (minutes <= 0) {
      _notify('请填写有效的时长');
      return;
    }
    await _handle(
      () => ref.read(healthRepositoryProvider).saveWorkout(
            id: widget.existing?.id,
            startedAt: _at,
            minutes: minutes,
            type: _type,
            meters: _distance.text.trim().isEmpty
                ? null
                : parseKmToMeters(_distance.text),
            calories: int.tryParse(_calories.text.trim()),
            avgHr: int.tryParse(_avgHr.text.trim()),
            note: _note.text.trim().isEmpty ? null : _note.text.trim(),
          ),
    );
  }

  Future<void> _handle(Future<void> Function() action) async {
    setState(() => _saving = true);
    try {
      await action();
      if (mounted) Navigator.of(context).pop();
    } catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      _notify('操作失败：$error');
    }
  }

  void _notify(String message) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
}

// ------------------------------------------------------------ 公共控件

class _SheetBody extends StatelessWidget {
  const _SheetBody({
    required this.title,
    required this.children,
    required this.onSave,
    required this.saving,
    this.onDelete,
  });

  final String title;
  final List<Widget> children;
  final VoidCallback onSave;
  final bool saving;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
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
                Expanded(
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleLarge,
                  ),
                ),
                TextButton(
                  onPressed: saving ? null : () => Navigator.of(context).pop(),
                  child: const Text('取消'),
                ),
                if (onDelete != null)
                  TextButton.icon(
                    onPressed: saving ? null : onDelete,
                    icon: const Icon(Icons.delete_outline, size: 18),
                    label: const Text('删除'),
                    style: TextButton.styleFrom(
                      foregroundColor: theme.colorScheme.error,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            ...children,
            const SizedBox(height: 24),
            FilledButton(
              onPressed: saving ? null : onSave,
              child: Text(saving ? '保存中…' : '保存'),
            ),
          ],
        ),
      ),
    );
  }
}

class _NumberField extends StatelessWidget {
  const _NumberField({
    required this.controller,
    required this.label,
    this.suffixText,
    this.digitsOnly = false,
  });

  final TextEditingController controller;
  final String label;
  final String? suffixText;
  final bool digitsOnly;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      keyboardType: digitsOnly
          ? TextInputType.number
          : const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: [
        if (digitsOnly)
          FilteringTextInputFormatter.digitsOnly
        else
          FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
      ],
      decoration: InputDecoration(
        labelText: label,
        suffixText: suffixText,
      ),
    );
  }
}

class _DateTimeTile extends StatelessWidget {
  const _DateTimeTile({required this.value, required this.onChanged});

  final DateTime value;
  final ValueChanged<DateTime> onChanged;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: const Icon(Icons.schedule),
      title: const Text('时间'),
      subtitle: Text(formatDateTime(value)),
      onTap: () async {
        final date = await showDatePicker(
          context: context,
          initialDate: value,
          firstDate: DateTime(2000),
          lastDate: DateTime(2100),
        );
        if (date == null || !context.mounted) return;

        final time = await showTimePicker(
          context: context,
          initialTime: TimeOfDay.fromDateTime(value),
        );
        if (!context.mounted) return;

        onChanged(
          DateTime(
            date.year,
            date.month,
            date.day,
            time?.hour ?? value.hour,
            time?.minute ?? value.minute,
          ),
        );
      },
    );
  }
}
