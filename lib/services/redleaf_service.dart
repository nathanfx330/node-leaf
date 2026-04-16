// --- File: lib/services/redleaf_service.dart ---
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:html/parser.dart' show parse;

import '../models/node_models.dart';

class RedleafService {
  String apiUrl = "http://127.0.0.1:5000";
  String username = "";
  String password = "";
  String redleafBaseDir = ""; 
  
  String _cookie = "";
  String _csrfToken = "";
  bool isLoggedIn = false;

  Future<bool> authenticate() async {
    if (username.isEmpty || password.isEmpty) return false;
    try {
      final getRes = await http.get(Uri.parse('$apiUrl/login'));
      _updateCookie(getRes);
      
      final document = parse(getRes.body);
      final csrfInput = document.querySelector('input[name="csrf_token"]');
      if (csrfInput != null) _csrfToken = csrfInput.attributes['value'] ?? "";

      final request = http.Request('POST', Uri.parse('$apiUrl/login'))
        ..followRedirects = false
        ..headers['Cookie'] = _cookie
        ..headers['Content-Type'] = 'application/x-www-form-urlencoded'
        ..bodyFields = {
          'csrf_token': _csrfToken,
          'username': username,
          'password': password,
        };

      final streamedResponse = await http.Client().send(request);
      final postRes = await http.Response.fromStream(streamedResponse);
      
      _updateCookie(postRes);
      
      if (postRes.statusCode == 302 || postRes.headers['location'] != null) {
        isLoggedIn = true;
        return true;
      }
      
      isLoggedIn = false;
      return false;
    } catch (e) {
      debugPrint("Redleaf Auth Error: $e");
      isLoggedIn = false;
      return false;
    }
  }

  void _updateCookie(http.Response response) {
    String? rawCookie = response.headers['set-cookie'];
    if (rawCookie != null) {
      List<String> parts = rawCookie.split(';');
      _cookie = parts.firstWhere((p) => p.contains('session='), orElse: () => parts[0]);
    }
  }

  Future<bool> _ensureAuth() async {
    if (isLoggedIn) return true;
    return await authenticate();
  }

  dynamic _safeJsonDecode(http.Response res) {
    if (res.body.trim().startsWith('<')) {
      throw const FormatException("Received HTML instead of JSON. Authentication likely failed or expired.");
    }
    return jsonDecode(res.body);
  }

  Future<String?> fetchInstanceId() async {
    if (!await _ensureAuth()) return null;
    try {
      final res = await http.get(
        Uri.parse('$apiUrl/api/system/info'),
        headers: {'Cookie': _cookie}
      );
      if (res.statusCode == 200) {
        final data = _safeJsonDecode(res);
        redleafBaseDir = data['base_dir'] ?? ""; 
        return data['instance_id'];
      }
    } catch (e) {
      debugPrint("Instance ID fetch error: $e");
    }
    return null;
  }
  
  Future<String> fetchSystemBriefing() async {
    if (!await _ensureAuth()) return "[Auth Error: Not connected to Redleaf]";
    try {
      final res = await http.get(
        Uri.parse('$apiUrl/api/system/briefing'),
        headers: {'Cookie': _cookie}
      );
      if (res.statusCode == 200) {
        final data = _safeJsonDecode(res);
        String text = data['briefing'] ?? '';
        return "[Redleaf System Briefing / Territory Map]:\n$text";
      }
    } catch (e) {
      debugPrint("System briefing fetch error: $e");
    }
    return "[Error fetching System Briefing]";
  }

  Future<List<Map<String, dynamic>>> searchEntities(String query) async {
    if (!await _ensureAuth()) return [];
    List<Map<String, dynamic>> results = [];
    final labelsToSearch = ['PERSON', 'ORG', 'GPE', 'LOC'];

    await Future.wait(labelsToSearch.map((label) async {
      try {
        final res = await http.get(
          Uri.parse('$apiUrl/api/discover/list/$label?q=${Uri.encodeComponent(query)}'),
          headers: {'Cookie': _cookie}
        );
        if (res.statusCode == 200) {
          final data = _safeJsonDecode(res);
          for (var item in data['items']) {
            results.add({
              'text': item['entity_text'],
              'label': label,
              'count': item['appearance_count']
            });
          }
        }
      } catch (e) { debugPrint("Entity search error for $label: $e"); }
    }));

    results.sort((a, b) => b['count'].compareTo(a['count']));
    return results;
  }

  Future<int?> extractEntityId(String label, String text) async {
    if (!await _ensureAuth()) return null;
    try {
      final res = await http.get(
        Uri.parse('$apiUrl/discover/entity/$label/${Uri.encodeComponent(text)}'),
        headers: {'Cookie': _cookie}
      );
      final match = RegExp(r'const ENTITY_ID\s*=\s*(\d+);').firstMatch(res.body);
      if (match != null) return int.parse(match.group(1)!);
    } catch (e) { debugPrint("Failed to extract ID: $e"); }
    return null;
  }

  Future<String> fetchContextForPill(RedleafPill pill) async {
    if (!await _ensureAuth()) return "[Auth Error: Not connected to Redleaf]";
    try {
      final res = await http.get(
        Uri.parse('$apiUrl/api/entity/${pill.entityId}/mentions?page=1'),
        headers: {'Cookie': _cookie}
      );
      if (res.statusCode == 200) {
        final data = _safeJsonDecode(res);
        final mentions = data['mentions'] as List;
        StringBuffer sb = StringBuffer();
        sb.writeln("[Redleaf DB: Entity Context for '${pill.text}' (${pill.label})]");
        int count = 0;
        for (var m in mentions) {
          if (count >= 5) break; 
          String docIdExtracted = m['doc_id']?.toString() ?? "Unknown";
          String cleanSnippet = m['snippet'].replaceAll(RegExp(r'<[^>]*>'), '');
          sb.writeln("- [Doc $docIdExtracted]: \"$cleanSnippet\"");
          count++;
        }
        return sb.toString();
      }
    } catch (e) { debugPrint("Context fetch error: $e"); }
    return "[Redleaf DB Error: Could not fetch data for '${pill.text}']";
  }

  Future<String> fetchAdvancedFtsContext(String query, int limit, List<Map<String, dynamic>> pinnedResults) async {
    if (!await _ensureAuth()) return "[Auth Error: Not connected to Redleaf]";
    try {
      StringBuffer sb = StringBuffer();
      
      if (pinnedResults.isNotEmpty) {
         sb.writeln("--- PINNED, HIGH-PRIORITY RESULTS ---");
         for (var pin in pinnedResults) {
             sb.writeln("- Snippet from [Doc ${pin['doc_id']}] ${pin['title']}: \"${pin['snippet']}\"");
         }
         sb.writeln("---------------------------------------");
      }

      if (limit > 0) {
        final res = await http.get(
          Uri.parse('$apiUrl/api/search?q=${Uri.encodeComponent(query)}&limit=$limit'), 
          headers: {'Cookie': _cookie}
        );
        
        if (res.statusCode == 200) {
          final List<dynamic> parsedData = _safeJsonDecode(res);
          for (var item in parsedData) {
            bool isAlreadyPinned = pinnedResults.any((p) => p['doc_id'] == item['doc_id'] && p['page_number'] == item['page_number']);
            if (!isAlreadyPinned) {
              sb.writeln("- Snippet from [Doc ${item['doc_id']}] ${item['title']}: \"${item['snippet']}\"");
            }
          }
        }
      }
      return sb.toString();
    } catch (e) { 
      debugPrint("Advanced FTS error: $e"); 
    }
    return "[Error fetching search results]";
  }

  Future<String> fetchFtsContext(String query) async {
    return await fetchAdvancedFtsContext(query, 5, []);
  }

  Future<List<Map<String, dynamic>>> fetchFtsResultsUI(String query) async {
    if (!await _ensureAuth()) {
      return [{"title": "AUTHENTICATION ERROR", "snippet": "Please click the Settings gear icon in the top right and click 'Connect & Save' to log into Redleaf.", "isError": true}];
    }
    
    List<Map<String, dynamic>> output = [];
    try {
      final url = Uri.parse('$apiUrl/api/search?q=${Uri.encodeComponent(query)}&mode=fts');
      final res = await http.get(url, headers: {'Cookie': _cookie});
      
      if (res.statusCode == 200) {
        final List<dynamic> parsedData = _safeJsonDecode(res);

        for (var item in parsedData) {
          output.add({
            'doc_id': item['doc_id'],
            'page_number': item['page_number'],
            'title': item['title'],
            'snippet': item['snippet'],
            'isError': false
          });
        }
      } else {
        output.add({"title": "HTTP ERROR", "snippet": "Status Code: ${res.statusCode}", "isError": true});
      }
    } catch (e) { 
      output.add({"title": "CONNECTION ERROR", "snippet": e.toString(), "isError": true});
    }
    return output;
  }

  // --- MODIFIED: fetchDocumentText now accepts a StoryNode ---
  Future<String> fetchDocumentText(StoryNode node) async {
    if (!await _ensureAuth()) return "[Auth Error: Not connected to Redleaf]";
    try {
      final inputStr = node.content; // Use node content for parsing
      int? docId;
      int? startPage;
      int? endPage;

      // Parse syntax: "12" or "id:12 + page:1-3" or "id:12 + page:4"
      final match = RegExp(r'(?:id:\s*)?(\d+)(?:\s*\+\s*page:\s*(\d+)(?:-(\d+))?)?', caseSensitive: false).firstMatch(inputStr.trim());
      
      if (match != null) {
        docId = int.tryParse(match.group(1) ?? '');
        if (match.group(2) != null) {
          startPage = int.tryParse(match.group(2)!);
          if (match.group(3) != null) {
            endPage = int.tryParse(match.group(3)!);
          } else {
            endPage = startPage;
          }
        }
      } else {
        docId = int.tryParse(inputStr.trim());
      }

      if (docId == null) return "[Invalid Document Syntax: $inputStr]";

      String url = '$apiUrl/api/document/$docId/text';
      List<String> queryParams = [];
      if (startPage != null) queryParams.add('start_page=$startPage');
      if (endPage != null) queryParams.add('end_page=$endPage');
      if (queryParams.isNotEmpty) url += '?${queryParams.join('&')}';

      final res = await http.get(Uri.parse(url), headers: {'Cookie': _cookie});
      if (res.statusCode == 200) {
        final data = _safeJsonDecode(res);
        if (data['success'] == true) {
          String text = data['text'] ?? '';
          if (text.length > 4000) text = "${text.substring(0, 4000)}\n\n... [Document Truncated for AI Context] ...";
          
          // --- NEW: INJECT CURATION DATA ---
          StringBuffer finalOutput = StringBuffer();
          finalOutput.writeln("[Redleaf Raw Text for Document #$docId${startPage != null ? ' (Pages $startPage-$endPage)' : ''}]:\n$text");

          if (node.pinnedComments.isNotEmpty) {
            finalOutput.writeln("\n\n>>> HUMAN CURATION FOR DOCUMENT #$docId <<<");
            for (var comment in node.pinnedComments) {
              finalOutput.writeln("---");
              if (comment['is_quote'] == true) finalOutput.writeln("TYPE: Direct Quote from Document");
              if (comment['is_commentary'] == true) finalOutput.writeln("TYPE: Research Commentary");
              if (comment['refers_to_doc'] == true) finalOutput.writeln("CONTEXT: This refers directly to the document above.");
              finalOutput.writeln("ANNOTATION BY ${comment['username']}: \"${comment['comment_text']}\"");
            }
            finalOutput.writeln(">>> END HUMAN CURATION <<<");
          }

          return finalOutput.toString();
        }
      }
    } catch (e) { debugPrint("Doc fetch error: $e"); }
    return "[Error fetching Document data for input: ${node.content}]";
  }

  // --- NEW: Fetch Comments directly for the UI Panel ---
  Future<List<dynamic>> fetchCommentsForDocument(String docIdStr) async {
    if (!await _ensureAuth()) return [];
    
    // Clean up the input string to just get the ID (same logic as fetchDocumentText)
    final match = RegExp(r'(?:id:\s*)?(\d+)').firstMatch(docIdStr.trim());
    final docId = match != null ? match.group(1) : docIdStr.trim();
    if (docId == null || docId.isEmpty) return [];

    try {
      final url = Uri.parse('$apiUrl/api/document/$docId/curation');
      // Pass the cookie so Flask knows we are authenticated
      final res = await http.get(url, headers: {'Cookie': _cookie}); 
      
      if (res.statusCode == 200) {
        final data = _safeJsonDecode(res);
        return data['comments'] ?? []; 
      }
    } catch (e) {
      debugPrint("Failed to fetch comments for Doc $docId: $e");
    }
    return [];
  }

  Future<List<Map<String, dynamic>>> fetchAllCatalogs() async {
    if (!await _ensureAuth()) return [];
    try {
      final res = await http.get(Uri.parse('$apiUrl/api/catalogs/all'), headers: {'Cookie': _cookie});
      if (res.statusCode == 200) {
        return List<Map<String, dynamic>>.from(_safeJsonDecode(res));
      }
    } catch (e) { debugPrint("Fetch catalogs error: $e"); }
    return [];
  }

  Future<String> fetchCatalogContext(int catalogId, String catalogName) async {
    if (!await _ensureAuth()) return "[Auth Error: Not connected to Redleaf]";
    try {
      final res = await http.get(Uri.parse('$apiUrl/api/catalogs/$catalogId/context?limit=5'), headers: {'Cookie': _cookie});
      if (res.statusCode == 200) {
        final data = _safeJsonDecode(res);
        String text = data['context'] ?? '';
        return "[Redleaf Context for Catalog '$catalogName']:\n$text";
      }
    } catch (e) { debugPrint("Catalog context error: $e"); }
    return "[Error fetching context for Catalog '$catalogName']";
  }

  Future<String> fetchIntersectionContext(List<String> topics) async {
    if (!await _ensureAuth()) return "[Auth Error: Not connected to Redleaf]";
    if (topics.isEmpty) return "[No topics provided for Intersection]";
    try {
      final qs = topics.map((t) => 'topic=${Uri.encodeComponent(t)}').join('&');
      final res = await http.get(Uri.parse('$apiUrl/api/search/intersection?$qs'), headers: {'Cookie': _cookie});
      if (res.statusCode == 200) {
        final data = _safeJsonDecode(res);
        String text = data['context'] ?? '';
        return "[Redleaf Intersection Context for topics: ${topics.join(', ')}]:\n$text";
      }
    } catch (e) { debugPrint("Intersection context error: $e"); }
    return "[Error fetching intersection context for ${topics.join(', ')}]";
  }

  Future<String> fetchEntityRelationships(int entityId, String entityName) async {
    if (!await _ensureAuth()) return "[Auth Error: Not connected to Redleaf]";
    try {
      final res = await http.get(Uri.parse('$apiUrl/api/entity/$entityId/relationships'), headers: {'Cookie': _cookie});
      if (res.statusCode == 200) {
        final List<dynamic> data = _safeJsonDecode(res);
        StringBuffer sb = StringBuffer();
        sb.writeln("[Redleaf Structured Relationships for Entity: '$entityName']");
        
        if (data.isEmpty) {
          sb.writeln("No known relationships found.");
          return sb.toString();
        }
        
        for (var rel in data) {
          String role = rel['role'];
          String phrase = rel['relationship_phrase'];
          String other = rel['other_entity_text'];
          int count = rel['count'];
          
          if (role == 'subject') {
            sb.writeln("- $entityName -> $phrase -> $other (Seen $count times)");
          } else {
            sb.writeln("- $other -> $phrase -> $entityName (Seen $count times)");
          }
        }
        return sb.toString();
      }
    } catch (e) { debugPrint("Entity relationships error: $e"); }
    return "[Error fetching relationships for '$entityName']";
  }

  Future<String?> exportToSynthesis(String title, String rawText) async {
    if (!await _ensureAuth()) return null;

    try {
      final createRes = await http.post(
        Uri.parse('$apiUrl/api/synthesis/reports'),
        headers: {
          'Cookie': _cookie,
          'Content-Type': 'application/json',
          'X-CSRFToken': _csrfToken, 
        },
        body: jsonEncode({'title': title})
      );
      
      if (createRes.statusCode != 201 && createRes.statusCode != 200) {
        debugPrint("Failed to create Synthesis report: ${createRes.body}");
        return null;
      }
      
      final createData = _safeJsonDecode(createRes);
      final reportId = createData['report']['id'];

      List<Map<String, dynamic>> contentBlocks = [];
      List<String> lines = rawText.split('\n');
      for (String line in lines) {
        if (line.trim().isEmpty) continue;
        contentBlocks.add({
          "type": "paragraph",
          "content": [
            {"type": "text", "text": line.trim()}
          ]
        });
      }
      
      Map<String, dynamic> tiptapJson = {
        "type": "doc",
        "content": contentBlocks
      };

      final saveRes = await http.post(
        Uri.parse('$apiUrl/api/synthesis/$reportId/content'),
        headers: {
          'Cookie': _cookie,
          'Content-Type': 'application/json',
          'X-CSRFToken': _csrfToken,
        },
        body: jsonEncode(tiptapJson)
      );

      if (saveRes.statusCode == 200) {
        return '$apiUrl/synthesis/report/$reportId'; 
      } else {
        debugPrint("Failed to save content to Synthesis report: ${saveRes.body}");
      }

    } catch (e) {
      debugPrint("Export to Synthesis Error: $e");
    }
    return null;
  }
}