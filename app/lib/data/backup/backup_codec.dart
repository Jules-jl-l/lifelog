/// 加密备份包的编解码格式。
///
/// 文件结构（全部小端无关，纯字节序）：
/// ```
/// [0..7]     魔术字 "LIFELOG1"        (8 字节)
/// [8..23]    PBKDF2 盐                (16 字节)
/// [24..35]   AES-GCM nonce            (12 字节)
/// [36..]     密文 + 认证标签
/// ```
/// 前 36 字节的头部会作为 GCM 的附加认证数据（AAD），
/// 因此改魔术字、换盐或换 nonce 都会导致解密失败。
library;

import 'dart:convert';
import 'dart:typed_data';

import '../../core/crypto.dart';

const backupMagic = 'LIFELOG1';
const backupFormatVersion = 1;

const _saltLength = 16;
const _nonceLength = 12;
const _headerLength = 8 + _saltLength + _nonceLength;

/// 备份包里的元信息。
class BackupInfo {
  const BackupInfo({
    required this.exportedAt,
    required this.schemaVersion,
    required this.formatVersion,
    required this.tableCounts,
  });

  final DateTime exportedAt;
  final int schemaVersion;
  final int formatVersion;

  /// 表名 -> 行数
  final Map<String, int> tableCounts;

  int get totalRows =>
      tableCounts.values.fold(0, (sum, value) => sum + value);

  Map<String, dynamic> toJson() => {
        'exportedAt': exportedAt.toIso8601String(),
        'schemaVersion': schemaVersion,
        'formatVersion': formatVersion,
        'tableCounts': tableCounts,
      };

  static BackupInfo fromJson(Map<String, dynamic> json) => BackupInfo(
        exportedAt:
            DateTime.tryParse(json['exportedAt'] as String? ?? '') ??
                DateTime.fromMillisecondsSinceEpoch(0),
        schemaVersion: (json['schemaVersion'] as num?)?.toInt() ?? 0,
        formatVersion: (json['formatVersion'] as num?)?.toInt() ?? 0,
        tableCounts: {
          for (final entry
              in (json['tableCounts'] as Map<String, dynamic>? ?? {}).entries)
            if (entry.value is num) entry.key: (entry.value as num).toInt(),
        },
      );
}

/// 解密后的备份内容。
class BackupPayload {
  const BackupPayload({required this.info, required this.tables});

  final BackupInfo info;

  /// 表名 -> 行列表（每行是「列名 -> 原始值」）
  final Map<String, List<Map<String, dynamic>>> tables;

  Map<String, dynamic> toJson() => {
        'info': info.toJson(),
        'tables': tables,
      };

  static BackupPayload fromJson(Map<String, dynamic> json) {
    final infoJson = json['info'];
    final tablesJson = json['tables'];
    if (infoJson is! Map<String, dynamic> || tablesJson is! Map) {
      throw BackupException('备份内容结构不正确');
    }

    final tables = <String, List<Map<String, dynamic>>>{};
    for (final entry in (tablesJson as Map<String, dynamic>).entries) {
      final rows = entry.value;
      if (rows is! List) continue;
      tables[entry.key] = [
        for (final row in rows)
          if (row is Map<String, dynamic>) row,
      ];
    }

    return BackupPayload(
      info: BackupInfo.fromJson(infoJson),
      tables: tables,
    );
  }
}

class BackupException implements Exception {
  BackupException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// 加密一个备份包。
Future<Uint8List> encodeBackup({
  required BackupPayload payload,
  required String password,
}) async {
  if (password.length < 8) {
    throw BackupException('备份密码至少 8 位');
  }

  final salt = randomBytes(_saltLength);
  final nonce = randomBytes(_nonceLength);
  final header = <int>[
    ...utf8.encode(backupMagic),
    ...salt,
    ...nonce,
  ];

  final key = await deriveKey(
    password: password,
    salt: salt,
    iterations: backupKdfIterations,
  );
  final plaintext = Uint8List.fromList(
    utf8.encode(jsonEncode(payload.toJson())),
  );
  final sealed = await aesGcmSeal(
    key: key,
    nonce: nonce,
    plaintext: plaintext,
    aad: header,
  );

  return Uint8List.fromList([...header, ...sealed]);
}

/// 解密一个备份包；密码错误或文件损坏都会抛 [BackupException]。
Future<BackupPayload> decodeBackup({
  required Uint8List bytes,
  required String password,
}) async {
  if (bytes.length <= _headerLength) {
    throw BackupException('文件太小，不是有效的备份包');
  }

  final magic = String.fromCharCodes(bytes.sublist(0, 8));
  if (magic != backupMagic) {
    throw BackupException('文件格式不正确，请选择 .lifelog 备份包');
  }

  final header = bytes.sublist(0, _headerLength);
  final salt = Uint8List.fromList(bytes.sublist(8, 8 + _saltLength));
  final nonce = Uint8List.fromList(
    bytes.sublist(8 + _saltLength, _headerLength),
  );

  final key = await deriveKey(
    password: password,
    salt: salt,
    iterations: backupKdfIterations,
  );

  final Uint8List clear;
  try {
    clear = await aesGcmOpen(
      key: key,
      nonce: nonce,
      ciphertextWithTag: Uint8List.fromList(bytes.sublist(_headerLength)),
      aad: header,
    );
  } on CryptoException {
    throw BackupException('密码不正确，或备份文件已损坏');
  }

  final Map<String, dynamic> json;
  try {
    final decoded = jsonDecode(utf8.decode(clear));
    if (decoded is! Map<String, dynamic>) {
      throw BackupException('备份内容结构不正确');
    }
    json = decoded;
  } on FormatException {
    throw BackupException('备份内容已损坏');
  }

  final payload = BackupPayload.fromJson(json);
  if (payload.info.formatVersion > backupFormatVersion) {
    throw BackupException('备份包版本过新，请先升级 App');
  }
  return payload;
}
