/// DeepSeek API 客户端（OpenAI 兼容协议）。
///
/// 只负责两件事：文本对话（含 Function Calling）与多模态识图。
/// API Key 由调用方从本地安全存储读出后传入，代码里不硬编码任何密钥。
library;

import 'dart:convert';

import 'package:dio/dio.dart';

/// 面向用户的错误信息（已翻译成可读提示）。
class DeepSeekException implements Exception {
  DeepSeekException(this.message);

  final String message;

  @override
  String toString() => message;
}

class ToolCall {
  const ToolCall({
    required this.id,
    required this.name,
    required this.argumentsJson,
  });

  final String id;
  final String name;
  final String argumentsJson;

  Map<String, dynamic> get arguments {
    try {
      final decoded = jsonDecode(argumentsJson);
      return decoded is Map<String, dynamic> ? decoded : <String, dynamic>{};
    } on FormatException {
      return <String, dynamic>{};
    }
  }
}

class CompletionResult {
  const CompletionResult({this.content, this.toolCalls = const []});

  final String? content;
  final List<ToolCall> toolCalls;

  bool get hasToolCalls => toolCalls.isNotEmpty;
}

/// 流式对话的一帧：正文增量与「本轮结束时的工具调用」二选一或同时出现。
class ChatStreamChunk {
  const ChatStreamChunk({this.content, this.toolCalls});

  /// 正文增量；没有正文（例如纯工具调用轮）时为 null。
  final String? content;

  /// 仅在本轮流结束时、模型确实发起了工具调用时才非空。
  final List<ToolCall>? toolCalls;
}

class DeepSeekClient {
  DeepSeekClient({Dio? dio, this.baseUrl = 'https://api.deepseek.com'})
      : _dio = dio ??
            Dio(
              BaseOptions(
                connectTimeout: const Duration(seconds: 20),
                receiveTimeout: const Duration(seconds: 120),
                sendTimeout: const Duration(seconds: 60),
              ),
            );

  final Dio _dio;
  final String baseUrl;

  /// 文本模型。
  static const textModel = 'deepseek-chat';

  /// 多模态模型（识别截图中的文字与信息）。
  static const visionModel = 'deepseek-flash';

  Map<String, String> _headers(String apiKey) => {
        'Authorization': 'Bearer $apiKey',
        'Content-Type': 'application/json',
      };

  /// 非流式对话；传入 [tools] 时模型可能返回工具调用而正文为空。
  Future<CompletionResult> complete({
    required String apiKey,
    required List<Map<String, dynamic>> messages,
    List<Map<String, dynamic>>? tools,
    String model = textModel,
    double temperature = 0.3,
  }) async {
    try {
      final response = await _dio.post<Map<String, dynamic>>(
        '$baseUrl/chat/completions',
        data: {
          'model': model,
          'messages': messages,
          'temperature': temperature,
          if (tools != null && tools.isNotEmpty) 'tools': tools,
        },
        options: Options(headers: _headers(apiKey)),
      );
      return _parseCompletion(response.data);
    } on DioException catch (error) {
      throw DeepSeekException(_describe(error));
    }
  }

  /// 流式对话：逐段吐正文增量，并在本轮结束时汇总工具调用。
  ///
  /// 工具调用在 SSE 里是按 `index` 分片下发的（先 id/name，再分段 arguments），
  /// 这里按 index 累积，最后一帧统一交给调用方执行。
  Stream<ChatStreamChunk> streamChat({
    required String apiKey,
    required List<Map<String, dynamic>> messages,
    List<Map<String, dynamic>>? tools,
    String model = textModel,
    double temperature = 0.3,
  }) async* {
    Response<ResponseBody> response;
    try {
      response = await _dio.post<ResponseBody>(
        '$baseUrl/chat/completions',
        data: {
          'model': model,
          'messages': messages,
          'temperature': temperature,
          'stream': true,
          if (tools != null && tools.isNotEmpty) 'tools': tools,
        },
        options: Options(
          headers: _headers(apiKey),
          responseType: ResponseType.stream,
        ),
      );
    } on DioException catch (error) {
      throw DeepSeekException(_describe(error));
    }

    final body = response.data;
    if (body == null) return;

    final lines = body.stream
        .cast<List<int>>()
        .transform(utf8.decoder)
        .transform(const LineSplitter());

    final pending = <int, _ToolCallBuilder>{};

    await for (final line in lines) {
      final trimmed = line.trim();
      if (trimmed.isEmpty || !trimmed.startsWith('data:')) continue;

      final payload = trimmed.substring(5).trim();
      if (payload == '[DONE]') break;

      final Map<String, dynamic> json;
      try {
        final decoded = jsonDecode(payload);
        if (decoded is! Map<String, dynamic>) continue;
        json = decoded;
      } on FormatException {
        // 单行解析失败不影响整体，跳过
        continue;
      }

      final choices = json['choices'];
      if (choices is! List || choices.isEmpty) continue;
      final delta = (choices.first as Map<String, dynamic>)['delta'];
      if (delta is! Map<String, dynamic>) continue;

      final content = delta['content'];
      if (content is String && content.isNotEmpty) {
        yield ChatStreamChunk(content: content);
      }

      final rawCalls = delta['tool_calls'];
      if (rawCalls is List) {
        for (final raw in rawCalls) {
          if (raw is! Map<String, dynamic>) continue;
          final index = raw['index'] is int ? raw['index'] as int : 0;
          final builder = pending.putIfAbsent(index, _ToolCallBuilder.new);
          final id = raw['id'];
          if (id is String && id.isNotEmpty) builder.id = id;
          final function = raw['function'];
          if (function is Map<String, dynamic>) {
            final name = function['name'];
            if (name is String && name.isNotEmpty) builder.name = name;
            final arguments = function['arguments'];
            if (arguments is String) builder.arguments.write(arguments);
          }
        }
      }
    }

    if (pending.isNotEmpty) {
      final indexes = pending.keys.toList()..sort();
      yield ChatStreamChunk(
        toolCalls: [
          for (final index in indexes) pending[index]!.toToolCall(),
        ],
      );
    }
  }

  /// 把支付截图交给多模态模型，要求其按 [instruction] 返回结构化结果。
  Future<String> extractFromImage({
    required String apiKey,
    required List<int> imageBytes,
    required String instruction,
    String mimeType = 'image/jpeg',
  }) async {
    final dataUrl = 'data:$mimeType;base64,${base64Encode(imageBytes)}';
    try {
      final response = await _dio.post<Map<String, dynamic>>(
        '$baseUrl/chat/completions',
        data: {
          'model': visionModel,
          'temperature': 0,
          'messages': [
            {
              'role': 'user',
              'content': [
                {'type': 'text', 'text': instruction},
                {
                  'type': 'image_url',
                  'image_url': {'url': dataUrl},
                },
              ],
            },
          ],
        },
        options: Options(headers: _headers(apiKey)),
      );
      final result = _parseCompletion(response.data);
      return result.content ?? '';
    } on DioException catch (error) {
      throw DeepSeekException(_describe(error));
    }
  }

  CompletionResult _parseCompletion(Map<String, dynamic>? data) {
    if (data == null) throw DeepSeekException('模型没有返回内容');

    final choices = data['choices'];
    if (choices is! List || choices.isEmpty) {
      throw DeepSeekException('模型没有返回内容');
    }

    final message = (choices.first as Map<String, dynamic>)['message'];
    if (message is! Map<String, dynamic>) {
      throw DeepSeekException('模型返回格式异常');
    }

    final rawCalls = message['tool_calls'];
    return CompletionResult(
      content: message['content'] as String?,
      toolCalls: [
        for (final call in rawCalls is List ? rawCalls : const <dynamic>[])
          if (call is Map<String, dynamic>)
            ToolCall(
              id: (call['id'] as String?) ?? '',
              name: _functionField(call, 'name'),
              argumentsJson: _functionField(call, 'arguments', fallback: '{}'),
            ),
      ],
    );
  }

  String _functionField(
    Map<String, dynamic> call,
    String field, {
    String fallback = '',
  }) {
    final function = call['function'];
    if (function is! Map<String, dynamic>) return fallback;
    final value = function[field];
    return value is String ? value : fallback;
  }

  /// 把网络/协议错误翻译成用户能看懂的提示。
  String _describe(DioException error) {
    final status = error.response?.statusCode;
    if (status == 401) return 'API Key 无效或已过期，请在「我的 → AI 助手」重新配置';
    if (status == 402) return 'DeepSeek 账户余额不足，请充值后再试';
    if (status == 429) return '请求过于频繁或额度已用完，请稍后再试';
    if (status != null && status >= 500) {
      return 'DeepSeek 服务暂时不可用（$status），请稍后再试';
    }

    return switch (error.type) {
      DioExceptionType.connectionTimeout ||
      DioExceptionType.receiveTimeout ||
      DioExceptionType.sendTimeout =>
        '连接 DeepSeek 超时，请检查网络',
      DioExceptionType.connectionError ||
      DioExceptionType.unknown =>
        '无法连接 DeepSeek，请检查网络（离线时可用本地规则记账）',
      _ => 'AI 请求失败：${error.message ?? '未知错误'}',
    };
  }
}

/// 按 index 拼接流式下发的工具调用分片。
class _ToolCallBuilder {
  String id = '';
  String name = '';
  final StringBuffer arguments = StringBuffer();

  ToolCall toToolCall() => ToolCall(
        id: id,
        name: name,
        argumentsJson: arguments.isEmpty ? '{}' : arguments.toString(),
      );
}
