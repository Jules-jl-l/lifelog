/// 数据空间：每个空间一份独立的 SQLite 数据库文件。
///
/// 用于把真实数据与测试数据彻底分开：切换空间后，财务 / 健康 / 学习 / AI
/// 都会读取对应空间的数据，互不影响；旧空间原样保留，可随时切回。
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../core/utils.dart';
import '../db/database.dart';

/// 默认空间沿用历史版本的文件名，老用户升级后无需迁移数据。
const defaultSpaceId = 'default';
const defaultSpaceFileName = 'lifelog.sqlite';

const _configFileName = 'data-spaces.json';

class DataSpace {
  const DataSpace({
    required this.id,
    required this.name,
    required this.fileName,
    this.createdAt,
  });

  final String id;
  final String name;
  final String fileName;

  /// 默认空间的历史数据早于本功能，没有准确的创建时间。
  final DateTime? createdAt;

  bool get isDefault => id == defaultSpaceId;

  DataSpace copyWith({String? name}) => DataSpace(
        id: id,
        name: name ?? this.name,
        fileName: fileName,
        createdAt: createdAt,
      );

  Map<String, Object?> toJson() => {
        'id': id,
        'name': name,
        'fileName': fileName,
        'createdAt': createdAt?.toIso8601String(),
      };

  static DataSpace? fromJson(Object? value) {
    if (value is! Map) return null;
    final id = value['id'];
    final name = value['name'];
    final fileName = value['fileName'];
    if (id is! String || id.isEmpty) return null;
    if (name is! String || name.trim().isEmpty) return null;
    if (fileName is! String || fileName.isEmpty) return null;
    // 只接受纯文件名，避免配置被改动后指向沙盒之外的路径
    if (p.basename(fileName) != fileName) return null;
    return DataSpace(
      id: id,
      name: name,
      fileName: fileName,
      createdAt: DateTime.tryParse('${value['createdAt']}'),
    );
  }
}

class SpaceSnapshot {
  const SpaceSnapshot({required this.spaces, required this.currentId});

  final List<DataSpace> spaces;
  final String currentId;

  DataSpace get current => spaces.firstWhere(
        (space) => space.id == currentId,
        orElse: () => spaces.first,
      );

  Map<String, Object?> toJson() => {
        'currentId': currentId,
        'spaces': [for (final space in spaces) space.toJson()],
      };

  static SpaceSnapshot? fromJson(Object? value) {
    if (value is! Map) return null;
    final rawSpaces = value['spaces'];
    if (rawSpaces is! List) return null;

    final spaces = <DataSpace>[];
    for (final item in rawSpaces) {
      final space = DataSpace.fromJson(item);
      if (space == null) continue;
      if (spaces.any((existing) => existing.id == space.id)) continue;
      if (spaces.any((existing) => existing.fileName == space.fileName)) {
        continue;
      }
      spaces.add(space);
    }
    if (spaces.isEmpty) return null;

    final id = value['currentId'];
    final currentId = id is String && spaces.any((space) => space.id == id)
        ? id
        : spaces.first.id;
    return SpaceSnapshot(spaces: List.unmodifiable(spaces), currentId: currentId);
  }
}

final defaultDataSpace = DataSpace(
  id: defaultSpaceId,
  name: '我的数据',
  fileName: defaultSpaceFileName,
);

final defaultSpaceSnapshot = SpaceSnapshot(
  spaces: List.unmodifiable([defaultDataSpace]),
  currentId: defaultSpaceId,
);

/// 空间清单的落盘与库文件操作。
class SpaceStore {
  SpaceStore({this.directory});

  /// 测试可注入临时目录；为空时使用应用文档目录。
  final Directory? directory;

  Future<Directory> _resolveDirectory() async =>
      directory ?? await getApplicationDocumentsDirectory();

  Future<File> _configFile() async {
    final dir = await _resolveDirectory();
    return File(p.join(dir.path, _configFileName));
  }

  /// 读取空间清单；配置缺失或损坏时退回默认空间，保证 App 能正常打开。
  Future<SpaceSnapshot> load() async {
    try {
      final file = await _configFile();
      if (await file.exists()) {
        final snapshot = SpaceSnapshot.fromJson(
          jsonDecode(await file.readAsString()),
        );
        if (snapshot != null) return snapshot;
      }
    } on Object {
      // 忽略损坏的配置，使用默认空间
    }
    return defaultSpaceSnapshot;
  }

  Future<void> save(SpaceSnapshot snapshot) async {
    final file = await _configFile();
    final temp = File('${file.path}.tmp');
    await temp.writeAsString(jsonEncode(snapshot.toJson()), flush: true);
    await temp.rename(file.path);
  }

  Future<String> pathFor(DataSpace space) async {
    final dir = await _resolveDirectory();
    return p.join(dir.path, space.fileName);
  }

  Future<int> fileSize(DataSpace space) async {
    try {
      final file = File(await pathFor(space));
      return await file.exists() ? await file.length() : 0;
    } on Object {
      return 0;
    }
  }

  /// 用 [source] 当前的数据生成一份一致的副本，作为新空间的库文件。
  Future<void> copyDatabase({
    required AppDatabase source,
    required DataSpace target,
  }) async {
    final path = await pathFor(target);
    final file = File(path);
    if (await file.exists()) await file.delete();
    // VACUUM INTO 由 SQLite 生成一致性快照，比直接复制文件安全（含 WAL 时）。
    final escaped = path.replaceAll("'", "''");
    await source.customStatement("VACUUM INTO '$escaped'");
    if (!await File(path).exists()) {
      throw const FileSystemException('复制数据空间失败');
    }
  }

  Future<void> deleteDatabase(DataSpace space) async {
    final path = await pathFor(space);
    for (final suffix in const ['', '-wal', '-shm']) {
      final file = File('$path$suffix');
      if (await file.exists()) await file.delete();
    }
  }
}

class SpaceState {
  const SpaceState({required this.spaces, required this.currentId});

  final List<DataSpace> spaces;
  final String currentId;

  DataSpace get current => spaces.firstWhere(
        (space) => space.id == currentId,
        orElse: () => spaces.first,
      );

  SpaceSnapshot toSnapshot() =>
      SpaceSnapshot(spaces: spaces, currentId: currentId);
}

/// 启动时注入的空间清单；测试里不覆盖则使用默认的单个空间。
final initialSpaceSnapshotProvider = Provider<SpaceSnapshot>(
  (ref) => defaultSpaceSnapshot,
);

final spaceStoreProvider = Provider<SpaceStore>((ref) => SpaceStore());

class SpaceController extends Notifier<SpaceState> {
  @override
  SpaceState build() {
    final initial = ref.watch(initialSpaceSnapshotProvider);
    return SpaceState(spaces: initial.spaces, currentId: initial.currentId);
  }

  SpaceStore get _store => ref.read(spaceStoreProvider);

  Future<void> switchTo(String id) async {
    if (id == state.currentId) return;
    if (!state.spaces.any((space) => space.id == id)) return;
    final next = SpaceState(spaces: state.spaces, currentId: id);
    await _store.save(next.toSnapshot());
    state = next;
  }

  /// 新建空间并立即切换过去。
  ///
  /// [copyFrom] 不为空时，以该数据库的当前数据为副本；为空则新建空空间。
  Future<DataSpace> create({
    required String name,
    AppDatabase? copyFrom,
  }) async {
    final id = newId();
    final space = DataSpace(
      id: id,
      name: _normalizeName(name),
      fileName: 'lifelog-$id.sqlite',
      createdAt: DateTime.now(),
    );

    if (copyFrom != null) {
      try {
        await _store.copyDatabase(source: copyFrom, target: space);
      } on Object {
        // 复制失败时清掉可能残留的半成品文件，避免下次新建撞名
        await _store.deleteDatabase(space);
        rethrow;
      }
    }

    final next = SpaceState(
      spaces: [...state.spaces, space],
      currentId: space.id,
    );
    await _store.save(next.toSnapshot());
    state = next;
    return space;
  }

  Future<void> rename(String id, String name) async {
    final index = state.spaces.indexWhere((space) => space.id == id);
    if (index < 0) return;
    final spaces = [...state.spaces];
    spaces[index] = spaces[index].copyWith(name: _normalizeName(name));
    final next = SpaceState(spaces: spaces, currentId: state.currentId);
    await _store.save(next.toSnapshot());
    state = next;
  }

  Future<void> delete(String id) async {
    if (id == state.currentId) {
      throw StateError('不能删除当前正在使用的数据空间');
    }
    if (state.spaces.length <= 1) {
      throw StateError('至少保留一个数据空间');
    }
    final space = state.spaces.where((space) => space.id == id).firstOrNull;
    if (space == null) return;

    await _store.deleteDatabase(space);
    final next = SpaceState(
      spaces: [
        for (final item in state.spaces)
          if (item.id != id) item,
      ],
      currentId: state.currentId,
    );
    await _store.save(next.toSnapshot());
    state = next;
  }

  String _normalizeName(String name) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return '未命名空间';
    return trimmed.length <= 24 ? trimmed : trimmed.substring(0, 24);
  }
}

final spaceControllerProvider =
    NotifierProvider<SpaceController, SpaceState>(SpaceController.new);
