// --- File: lib/services/ollama_service.dart ---
import 'dart:convert';
import 'package:http/http.dart' as http;

/// Stats-bearing result from a non-streaming generation.
class OllamaGenResult {
  final String text;
  final int promptEvalCount; // Actual tokens the prompt consumed
  final int evalCount;       // Tokens generated
  final String doneReason;   // e.g. "stop", "length", "load"
  final String thinking;     // Reasoning-model chain-of-thought (if any)
  OllamaGenResult(this.text, this.promptEvalCount, this.evalCount, this.doneReason, this.thinking);
}

class OllamaService {
  /// Fetches available models from the Ollama instance.
  static Future<List<String>> fetchModels(String baseUrl) async {
    final response = await http.get(Uri.parse('$baseUrl/api/tags'));
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      final List<dynamic> models = data['models'] ?? [];
      return models.map((m) => m['name'].toString()).toList();
    }
    throw Exception('Failed to load models: ${response.statusCode}');
  }

  /// Preloads a model into VRAM.
  static Future<void> preloadModel(String baseUrl, String model) async {
    final response = await http.post(
      Uri.parse('$baseUrl/api/generate'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({"model": model}),
    );
    if (response.statusCode != 200) {
      throw Exception('Failed to preload model.');
    }
  }

  /// Unloads a model from VRAM.
  static Future<void> unloadModel(String baseUrl, String model) async {
    final response = await http.post(
      Uri.parse('$baseUrl/api/generate'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({"model": model, "keep_alive": 0}),
    );
    if (response.statusCode != 200) {
      throw Exception('Failed to unload model.');
    }
  }

  /// Non-streaming generation (Used for Agent internal thoughts and note-taking)
  static Future<String> generateText({
    required String baseUrl,
    required String model,
    required String prompt,
    String? system,
    String? format,
    int? numCtx,
    int? numPredict,
    bool? think,
  }) async {
    final res = await generateTextDetailed(
      baseUrl: baseUrl, model: model, prompt: prompt,
      system: system, format: format, numCtx: numCtx,
      numPredict: numPredict, think: think,
    );
    return res.text;
  }

  /// --- NEW: Non-streaming generation that also returns Ollama's token stats.
  /// prompt_eval_count is ground truth for how many tokens a prompt actually
  /// consumed — agents use it to calibrate chunk sizing and detect context
  /// overflow (prompt fills num_ctx, leaving no room to generate).
  // Models that rejected the "think" parameter - don't send it to them again.
  static final Set<String> _thinkParamUnsupported = {};

  static bool _isThinkParamError(String body) {
    final b = body.toLowerCase();
    return b.contains('think');
  }

  static Future<OllamaGenResult> generateTextDetailed({
    required String baseUrl,
    required String model,
    required String prompt,
    String? system,
    String? format,
    int? numCtx,
    int? numPredict,
    bool? think,
  }) async {
    Future<http.Response> send(bool includeThink) {
      final Map<String, dynamic> body = {
        "model": model,
        "prompt": prompt,
        "stream": false,
      };
      if (system != null && system.isNotEmpty) body["system"] = system;
      if (format != null && format.isNotEmpty) body["format"] = format;
      if (includeThink && think != null) body["think"] = think;
      final Map<String, dynamic> options = {};
      if (numCtx != null) options["num_ctx"] = numCtx;
      if (numPredict != null) options["num_predict"] = numPredict;
      if (options.isNotEmpty) body["options"] = options;
      return http.post(
        Uri.parse('$baseUrl/api/generate'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(body),
      );
    }

    final String modelKey = '$baseUrl|$model';
    bool includeThink = think != null && !_thinkParamUnsupported.contains(modelKey);

    var response = await send(includeThink);

    // --- NEW: Some models reject the think toggle - retry once without it
    // and remember, so future calls skip the wasted round-trip.
    if (response.statusCode != 200 && includeThink && _isThinkParamError(response.body)) {
      _thinkParamUnsupported.add(modelKey);
      response = await send(false);
    }

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      if (data['error'] != null) throw Exception("Ollama error: ${data['error']}");
      return OllamaGenResult(
        data['response'] ?? '',
        (data['prompt_eval_count'] is num) ? (data['prompt_eval_count'] as num).toInt() : 0,
        (data['eval_count'] is num) ? (data['eval_count'] as num).toInt() : 0,
        (data['done_reason'] ?? '').toString(),
        (data['thinking'] ?? '').toString(),
      );
    }
    throw Exception('Ollama generation failed: ${response.body}');
  }

  /// --- NEW: Asks Ollama what the model's usable context window is, so agents
  /// can budget chunking instead of guessing. Priority order:
  ///   1. An explicit "PARAMETER num_ctx" in the model's Modelfile — this is a
  ///      deliberate user setting (usually VRAM-motivated) and wins.
  ///   2. The architecture's trained context_length from model_info.
  /// Returns null if neither is available (older Ollama versions).
  /// Results are cached per (baseUrl, model) — switching models re-probes.
  static final Map<String, int?> _ctxLimitCache = {};

  static Future<int?> fetchModelContextLimit(String baseUrl, String model) async {
    final cacheKey = '$baseUrl|$model';
    if (_ctxLimitCache.containsKey(cacheKey)) return _ctxLimitCache[cacheKey];

    int? limit;
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/api/show'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({"model": model}),
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);

        // 1. Modelfile override: "parameters" is a plain-text block of
        //    "num_ctx  16384"-style lines.
        final String params = (data['parameters'] ?? '').toString();
        final numCtxMatch = RegExp(r'num_ctx\s+(\d+)').firstMatch(params);
        if (numCtxMatch != null) {
          limit = int.tryParse(numCtxMatch.group(1)!);
        }

        // 2. Trained architecture limit, e.g. "llama.context_length",
        //    "qwen2.context_length" — match by suffix.
        if (limit == null) {
          final Map<String, dynamic>? info = data['model_info'];
          if (info != null) {
            for (final entry in info.entries) {
              if (entry.key.endsWith('.context_length') && entry.value is num) {
                limit = (entry.value as num).toInt();
                break;
              }
            }
          }
        }
      }
    } catch (_) {}

    _ctxLimitCache[cacheKey] = limit;
    return limit;
  }

  /// Streaming generation (Used for final output nodes)
  ///
  /// [numCtx] optionally overrides Ollama's default context window (often only
  /// 2048-4096 tokens). Agents with large payloads (e.g. full SRT transcripts)
  /// MUST pass this, or Ollama silently truncates the prompt.
  static Stream<String> generateTextStream({
    required String baseUrl,
    required String model,
    required String prompt,
    String? system,
    int? numCtx,
    bool? think,
  }) async* {
    final String modelKey = '$baseUrl|$model';

    http.Request buildRequest(bool includeThink) {
      final Map<String, dynamic> body = {
        "model": model,
        "prompt": prompt,
        "stream": true,
      };
      if (system != null && system.isNotEmpty) body["system"] = system;
      if (includeThink && think != null) body["think"] = think;
      if (numCtx != null) body["options"] = {"num_ctx": numCtx};
      return http.Request('POST', Uri.parse('$baseUrl/api/generate'))
        ..headers['Content-Type'] = 'application/json'
        ..body = jsonEncode(body);
    }

    bool includeThink = think != null && !_thinkParamUnsupported.contains(modelKey);
    var response = await http.Client().send(buildRequest(includeThink));

    // --- NEW: Fallback for models that reject the think toggle.
    if (response.statusCode != 200 && includeThink) {
      final errBody = await response.stream.transform(utf8.decoder).join();
      if (_isThinkParamError(errBody)) {
        _thinkParamUnsupported.add(modelKey);
        response = await http.Client().send(buildRequest(false));
      } else {
        String message = errBody;
        try {
          final parsed = jsonDecode(errBody);
          if (parsed['error'] != null) message = parsed['error'];
        } catch (_) {}
        throw Exception("Ollama HTTP ${response.statusCode}: $message");
      }
    }

    // --- FIX: Ollama errors (model not found, OOM, bad request) come back as
    // an {"error": "..."} body. Previously these were silently swallowed and
    // the stream completed with zero chunks — the "returns nothing" bug. ---
    if (response.statusCode != 200) {
      final errBody = await response.stream.transform(utf8.decoder).join();
      String message = errBody;
      try {
        final parsed = jsonDecode(errBody);
        if (parsed['error'] != null) message = parsed['error'];
      } catch (_) {}
      throw Exception("Ollama HTTP ${response.statusCode}: $message");
    }

    await for (final line in response.stream.transform(utf8.decoder).transform(const LineSplitter())) {
      if (line.isNotEmpty) {
        try {
          final data = jsonDecode(line);
          // --- FIX: Mid-stream errors must surface, not vanish ---
          if (data['error'] != null) {
            throw Exception("Ollama stream error: ${data['error']}");
          }
          if (data['response'] != null) {
            yield data['response'];
          }
        } on FormatException {
          // Ignore genuinely malformed JSON chunks (partial lines)
        }
      }
    }
  }

  /// Streaming chat generation (Used for the Chat Node)
  static Stream<String> generateChatStream({
    required String baseUrl,
    required String model,
    required List<Map<String, String>> messages,
  }) async* {
    final request = http.Request('POST', Uri.parse('$baseUrl/api/chat'))
      ..headers['Content-Type'] = 'application/json'
      ..body = jsonEncode({
        "model": model,
        "messages": messages,
        "stream": true,
      });

    final response = await http.Client().send(request);

    // --- FIX: Same error surfacing as generateTextStream ---
    if (response.statusCode != 200) {
      final errBody = await response.stream.transform(utf8.decoder).join();
      String message = errBody;
      try {
        final parsed = jsonDecode(errBody);
        if (parsed['error'] != null) message = parsed['error'];
      } catch (_) {}
      throw Exception("Ollama HTTP ${response.statusCode}: $message");
    }

    await for (final line in response.stream.transform(utf8.decoder).transform(const LineSplitter())) {
      if (line.isNotEmpty) {
        try {
          final data = jsonDecode(line);
          if (data['error'] != null) {
            throw Exception("Ollama stream error: ${data['error']}");
          }
          if (data['message'] != null && data['message']['content'] != null) {
            yield data['message']['content'];
          }
        } on FormatException {
          // Ignore genuinely malformed JSON chunks (partial lines)
        }
      }
    }
  }
}