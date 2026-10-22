/// AI 会话与消息的本地存储。
library;

import 'package:drift/drift.dart';

import '../core/utils.dart';
import 'db/database.dart';

class AiRepository {
  AiRepository(this._db);

  final AppDatabase _db;

  Stream<List<ChatSession>> watchSessions() {
    final query = _db.select(_db.chatSessions)
      ..where((t) => t.deletedAt.isNull())
      ..orderBy([
        (t) => OrderingTerm(expression: t.createdAt, mode: OrderingMode.desc),
      ]);
    return query.watch();
  }

  Future<ChatSession> createSession({required String title, required String model}) async {
    final now = DateTime.now();
    final id = newId();
    await _db.into(_db.chatSessions).insert(
          ChatSessionsCompanion.insert(
            id: id,
            createdAt: now,
            updatedAt: now,
            title: title,
            model: model,
          ),
        );
    return (_db.select(_db.chatSessions)..where((t) => t.id.equals(id)))
        .getSingle();
  }

  Future<void> renameSession(String id, String title) async {
    await (_db.update(_db.chatSessions)..where((t) => t.id.equals(id))).write(
      ChatSessionsCompanion(title: Value(title), updatedAt: Value(DateTime.now())),
    );
  }

  Future<void> deleteSession(String id) async {
    final now = DateTime.now();
    await (_db.update(_db.chatSessions)..where((t) => t.id.equals(id))).write(
      ChatSessionsCompanion(deletedAt: Value(now), updatedAt: Value(now)),
    );
  }

  Stream<List<ChatMessage>> watchMessages(String sessionId) {
    final query = _db.select(_db.chatMessages)
      ..where((t) => t.deletedAt.isNull() & t.sessionId.equals(sessionId))
      ..orderBy([(t) => OrderingTerm(expression: t.createdAt)]);
    return query.watch();
  }

  Future<List<ChatMessage>> messagesOnce(String sessionId) async {
    final query = _db.select(_db.chatMessages)
      ..where((t) => t.deletedAt.isNull() & t.sessionId.equals(sessionId))
      ..orderBy([(t) => OrderingTerm(expression: t.createdAt)]);
    return query.get();
  }

  Future<ChatMessage> addMessage({
    required String sessionId,
    required String role,
    required String content,
    String? toolCallsJson,
    int? tokens,
  }) async {
    final now = DateTime.now();
    final id = newId();
    await _db.into(_db.chatMessages).insert(
          ChatMessagesCompanion.insert(
            id: id,
            createdAt: now,
            updatedAt: now,
            sessionId: sessionId,
            role: role,
            content: content,
            toolCallsJson: Value(toolCallsJson),
            tokens: Value(tokens),
          ),
        );
    await (_db.update(_db.chatSessions)..where((t) => t.id.equals(sessionId)))
        .write(ChatSessionsCompanion(updatedAt: Value(now)));

    return (_db.select(_db.chatMessages)..where((t) => t.id.equals(id)))
        .getSingle();
  }

  Future<void> clearMessages(String sessionId) async {
    final now = DateTime.now();
    await (_db.update(_db.chatMessages)
          ..where((t) => t.sessionId.equals(sessionId) & t.deletedAt.isNull()))
        .write(ChatMessagesCompanion(deletedAt: Value(now), updatedAt: Value(now)));
  }
}
