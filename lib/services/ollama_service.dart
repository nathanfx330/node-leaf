// --- File: lib/services/ollama_service.dart ---
import 'dart:convert';
import 'package:http/http.dart' as http;

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
  }) async {
    final Map<String, dynamic> body = {
      "model": model,
      "prompt": prompt,
      "stream": false,
    };
    if (system != null && system.isNotEmpty) body["system"] = system;
    if (format != null && format.isNotEmpty) body["format"] = format;

    final response = await http.post(
      Uri.parse('$baseUrl/api/generate'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(body),
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      return data['response'] ?? '';
    }
    throw Exception('Ollama generation failed: ${response.body}');
  }

  /// Streaming generation (Used for final output nodes)
  static Stream<String> generateTextStream({
    required String baseUrl,
    required String model,
    required String prompt,
    String? system,
  }) async* {
    final Map<String, dynamic> body = {
      "model": model,
      "prompt": prompt,
      "stream": true,
    };
    if (system != null && system.isNotEmpty) body["system"] = system;

    final request = http.Request('POST', Uri.parse('$baseUrl/api/generate'))
      ..headers['Content-Type'] = 'application/json'
      ..body = jsonEncode(body);

    final response = await http.Client().send(request);

    await for (final line in response.stream.transform(utf8.decoder).transform(const LineSplitter())) {
      if (line.isNotEmpty) {
        try {
          final data = jsonDecode(line);
          if (data['response'] != null) {
            yield data['response'];
          }
        } catch (_) {
          // Ignore malformed JSON chunks
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

    await for (final line in response.stream.transform(utf8.decoder).transform(const LineSplitter())) {
      if (line.isNotEmpty) {
        try {
          final data = jsonDecode(line);
          if (data['message'] != null && data['message']['content'] != null) {
            yield data['message']['content'];
          }
        } catch (_) {
          // Ignore malformed JSON chunks
        }
      }
    }
  }
}