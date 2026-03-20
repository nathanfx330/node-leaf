// --- File: lib/state/network_state.dart ---
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../constants.dart';
import '../models/node_models.dart';
import '../services/redleaf_service.dart';
import 'graph_state.dart'; 

class NetworkState extends ChangeNotifier {
  // Redleaf Config
  String _redleafInstanceId = ""; 
  final RedleafService redleafService = RedleafService();
  AuthStatus _redleafAuthStatus = AuthStatus.none; 

  // Ollama Config
  String _ollamaUrl = "http://localhost:11434"; 
  AuthStatus _ollamaAuthStatus = AuthStatus.none; 
  
  String? _generatingNodeId; 
  
  String _ollamaModel = "";
  List<String> _availableModels = [];
  bool _isScanningModels = false;
  bool _isPreloadingModel = false;
  
  // --- NEW: Force Answer Flag ---
  bool _isForceAnswerTriggered = false;

  NetworkState() {
    fetchOllamaModels();
  }

  // Getters
  String get redleafInstanceId => _redleafInstanceId;
  AuthStatus get redleafAuthStatus => _redleafAuthStatus; 
  
  String get ollamaUrl => _ollamaUrl;
  AuthStatus get ollamaAuthStatus => _ollamaAuthStatus; 
  
  bool get isGeneratingOllama => _generatingNodeId != null; 
  bool isNodeGenerating(String nodeId) => _generatingNodeId == nodeId; 
  
  String get ollamaModel => _ollamaModel;
  List<String> get availableModels => _availableModels;
  bool get isScanningModels => _isScanningModels;
  bool get isPreloadingModel => _isPreloadingModel;

  // --- CONFIGURATION METHODS ---

  void resetNetworkState() {
    _redleafInstanceId = ""; 
    _redleafAuthStatus = AuthStatus.none;
    _ollamaAuthStatus = AuthStatus.none; 
    redleafService.isLoggedIn = false;
    redleafService.apiUrl = "http://127.0.0.1:5000"; 
    redleafService.username = "";
    redleafService.password = "";
    notifyListeners();
  }

  void loadNetworkConfig({
    String? instanceId, String? ollamaUrl, 
    String? apiUrl, String? user, String? model
  }) {
    if (instanceId != null) _redleafInstanceId = instanceId;
    if (ollamaUrl != null) _ollamaUrl = ollamaUrl;
    if (apiUrl != null) redleafService.apiUrl = apiUrl;
    if (user != null) redleafService.username = user;
    
    _redleafAuthStatus = AuthStatus.none; 
    _ollamaAuthStatus = AuthStatus.none; 
    redleafService.isLoggedIn = false;
    
    if (model != null) { 
      _ollamaModel = model; 
      if (!_availableModels.contains(_ollamaModel)) _availableModels.add(_ollamaModel); 
    }
    
    fetchOllamaModels();
    notifyListeners();
  }

  // --- REDLEAF AUTHENTICATION ---

  Future<void> testAndSaveRedleafCredentials(String api, String user, String pass) async {
    _redleafAuthStatus = AuthStatus.testing; 
    notifyListeners();
    
    redleafService.apiUrl = api.endsWith('/') ? api.substring(0, api.length - 1) : api; 
    redleafService.username = user; 
    redleafService.password = pass;
    
    bool success = await redleafService.authenticate();
    
    if (success) {
      String? fetchedId = await redleafService.fetchInstanceId();
      if (fetchedId != null) {
        if (_redleafInstanceId.isNotEmpty && _redleafInstanceId != fetchedId) {
          _redleafAuthStatus = AuthStatus.mismatch;
          notifyListeners();
          return;
        }
        _redleafInstanceId = fetchedId;
      }
    }
    
    _redleafAuthStatus = success ? AuthStatus.success : AuthStatus.error;
    notifyListeners();
  }

  // --- OLLAMA MANAGEMENT ---

  void setOllamaUrl(String url) { 
    _ollamaUrl = url.endsWith('/') ? url.substring(0, url.length - 1) : url; 
    notifyListeners(); 
  }

  void setOllamaModel(String model) { 
    if (_ollamaModel != model) { 
      _ollamaModel = model; 
      notifyListeners(); 
    } 
  }

  Future<void> fetchOllamaModels() async {
    _isScanningModels = true; 
    _ollamaAuthStatus = AuthStatus.testing;
    notifyListeners();
    
    try {
      final response = await http.get(Uri.parse('$_ollamaUrl/api/tags'));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final List<dynamic> models = data['models'] ?? [];
        if (models.isNotEmpty) { 
          _availableModels = models.map((m) => m['name'].toString()).toList(); 
          if (!_availableModels.contains(_ollamaModel)) _ollamaModel = _availableModels.first; 
        }
        _ollamaAuthStatus = AuthStatus.success;
      } else {
        _ollamaAuthStatus = AuthStatus.error;
      }
    } catch (e) { 
      debugPrint("Failed to fetch models: $e"); 
      _ollamaAuthStatus = AuthStatus.error;
    } finally { 
      _isScanningModels = false; 
      notifyListeners(); 
    }
  }

  Future<String> preloadOllamaModel() async {
    if (_ollamaModel.isEmpty) return "No model selected";
    _isPreloadingModel = true; notifyListeners();
    try {
      await http.Client().send(http.Request('POST', Uri.parse('$_ollamaUrl/api/generate'))..headers['Content-Type'] = 'application/json'..body = jsonEncode({"model": _ollamaModel}));
      _isPreloadingModel = false; notifyListeners(); return "Success";
    } catch (e) { 
      _isPreloadingModel = false; notifyListeners(); return e.toString(); 
    }
  }

  Future<String> unloadOllamaModel() async {
    if (_ollamaModel.isEmpty) return "No model selected";
    try {
      await http.Client().send(http.Request('POST', Uri.parse('$_ollamaUrl/api/generate'))..headers['Content-Type'] = 'application/json'..body = jsonEncode({"model": _ollamaModel, "keep_alive": 0}));
      return "Success";
    } catch (e) { 
      return e.toString(); 
    }
  }

  // --- NEW: FORCE ANSWER TRIGGER ---
  void forceAnswerNow() {
    if (_generatingNodeId != null) {
      _isForceAnswerTriggered = true;
      notifyListeners();
    }
  }

  // --- LLM GENERATION PIPELINE ---

  // Helper for the Agent Loop to parse JSON safely
  Map<String, dynamic> _parseAgentJSON(String response) {
    try {
      // Ollama sometimes wraps JSON in markdown blocks
      String clean = response.replaceAll('```json', '').replaceAll('```', '').trim();
      return jsonDecode(clean);
    } catch (e) {
      return {"action": "finish", "thought": "Failed to parse JSON decision.", "query": ""};
    }
  }

  Future<void> triggerOllamaGeneration(StoryNode node, List<StoryNode> sequence) async {
    _generatingNodeId = node.id; 
    _isForceAnswerTriggered = false; // Reset flag
    node.ollamaResult = ""; 
    notifyListeners();

    StringBuffer finalPrompt = StringBuffer();
    String userInstructions = node.ollamaPrompt.isNotEmpty ? node.ollamaPrompt : "Process the following context.";
    String manualStoryContext = "";
    
    // --- ADDED: Persona Extraction ---
    String customPersona = "";

    // STEP 1: Read the Chain (Manual Context)
    for (var n in sequence) {
      if (n.type == NodeType.output || n.type == NodeType.chat || n.type == NodeType.study) continue; 

      if (n.type == NodeType.persona) {
        customPersona = n.content.trim();
        continue;
      }

      if (n.type == NodeType.briefing) {
        node.ollamaResult = "🤖 Fetching System Briefing...\n"; notifyListeners();
        final briefingContext = await redleafService.fetchSystemBriefing();
        finalPrompt.writeln("\n>>> FACTUAL CONTEXT FROM REDLEAF SYSTEM BRIEFING <<<");
        finalPrompt.writeln(briefingContext);
        if (n.content.trim().isNotEmpty) {
          finalPrompt.writeln("\n[USER OVERRIDE / MANUAL CONTEXT]:");
          finalPrompt.writeln(n.content.trim());
        }
        finalPrompt.writeln(">>> END REDLEAF BRIEFING <<<\n");
        continue;
      }
      
      if (n.type == NodeType.search && n.content.isNotEmpty) {
        node.ollamaResult = "🤖 Fetching Global Search for '${n.content}'...\n"; notifyListeners();
        
        final searchContext = await redleafService.fetchAdvancedFtsContext(n.content, n.searchLimit, n.pinnedSearchResults);

        finalPrompt.writeln("\n>>> FACTUAL CONTEXT FROM REDLEAF GLOBAL SEARCH: '${n.content}' <<<");
        finalPrompt.writeln(searchContext);
        finalPrompt.writeln(">>> END REDLEAF SEARCH <<<\n");
        continue;
      }

      if (n.type == NodeType.document && n.content.isNotEmpty) {
        node.ollamaResult = "🤖 Fetching Full Document #${n.content}...\n"; notifyListeners();
        final docContext = await redleafService.fetchDocumentText(n.content);
        finalPrompt.writeln("\n>>> FACTUAL CONTEXT FROM REDLEAF DOCUMENT <<<");
        finalPrompt.writeln(docContext);
        finalPrompt.writeln(">>> END REDLEAF DOCUMENT <<<\n");
        continue;
      }

      if (n.type == NodeType.catalog && n.content.isNotEmpty) {
        node.ollamaResult = "🤖 Fetching Context for Catalog '${n.title}'...\n"; notifyListeners();
        final catId = int.tryParse(n.content);
        if (catId != null) {
          final catContext = await redleafService.fetchCatalogContext(catId, n.title);
          finalPrompt.writeln("\n>>> FACTUAL CONTEXT FROM REDLEAF CATALOG <<<");
          finalPrompt.writeln(catContext);
          finalPrompt.writeln(">>> END REDLEAF CATALOG <<<\n");
        }
        continue;
      }

      if (n.type == NodeType.intersection && n.redleafPills.isNotEmpty) {
        final topicNames = n.redleafPills.map((p) => p.text).toList();
        node.ollamaResult = "🤖 Fetching Co-Mentions for '${topicNames.join(', ')}'...\n"; notifyListeners();
        final intContext = await redleafService.fetchIntersectionContext(topicNames);
        finalPrompt.writeln("\n>>> FACTUAL CONTEXT FROM REDLEAF CO-MENTIONS <<<");
        finalPrompt.writeln(intContext);
        finalPrompt.writeln(">>> END REDLEAF CO-MENTIONS <<<\n");
        continue;
      }

      if (n.type == NodeType.relationship && n.redleafPills.isNotEmpty) {
        final pill = n.redleafPills.first; 
        node.ollamaResult = "🤖 Fetching Graph Relationships for '${pill.text}'...\n"; notifyListeners();
        final relContext = await redleafService.fetchEntityRelationships(pill.entityId, pill.text);
        finalPrompt.writeln("\n>>> FACTUAL CONTEXT FROM REDLEAF GRAPH <<<");
        finalPrompt.writeln(relContext);
        finalPrompt.writeln(">>> END REDLEAF GRAPH <<<\n");
        continue;
      }

      manualStoryContext += "\n=== [NODE: ${n.title}] ===\n${n.content}\n";
      if (n.redleafPills.isNotEmpty) {
        finalPrompt.writeln("\n>>> FACTUAL CONTEXT FROM REDLEAF KNOWLEDGE BASE <<<");
        for (var pill in n.redleafPills) {
          node.ollamaResult = "🤖 Fetching Entity Snippets for '${pill.text}'...\n"; notifyListeners();
          final context = await redleafService.fetchContextForPill(pill);
          finalPrompt.writeln(context);
        }
        finalPrompt.writeln(">>> END REDLEAF CONTEXT <<<\n");
      }
    }

    for (var n in sequence) {
      if (n.type == NodeType.study && n.ollamaResult.isNotEmpty) {
        node.ollamaResult = "🤖 Reading Deep Study on '${n.content}'...\n"; notifyListeners();
        finalPrompt.writeln("\n>>> FACTUAL CONTEXT FROM DEEP STUDY: '${n.content}' <<<");
        finalPrompt.writeln(n.ollamaResult);
        finalPrompt.writeln(">>> END DEEP STUDY <<<\n");
      }
    }
    
    // STEP 2: Autonomous Research (ReAct Loop)
    if (node.enableAutonomousResearch && redleafService.isLoggedIn) {
      node.ollamaResult = "🤖 Agent: Initiating Autonomous Research...\n"; notifyListeners();
      
      String accumulatedNotes = "No notes yet.";
      int maxSteps = 4; 
      
      for (int step = 1; step <= maxSteps; step++) {
        // Check if user forced an answer
        if (_isForceAnswerTriggered) {
          node.ollamaResult += "\n> [User Override] Skipping remaining research steps. Moving to synthesis.\n";
          notifyListeners();
          break;
        }

        node.ollamaResult += "\n> [Step $step] Thinking...\n"; notifyListeners();
        
        final thinkPrompt = """You are an Autonomous Research Engine.
Your Goal: "$userInstructions"
Current Accumulated Notes: $accumulatedNotes

Analyze the goal and current notes. Determine the SINGLE best next step.
Return JSON ONLY:
{
  "thought": "Internal reasoning about what information is missing.",
  "action": "search" OR "finish",
  "query": "Your specific search phrase if action is search"
}""";

        try {
          final thinkRes = await http.Client().send(http.Request('POST', Uri.parse('$_ollamaUrl/api/generate'))
            ..headers['Content-Type'] = 'application/json'
            ..body = jsonEncode({
              "model": _ollamaModel, 
              "prompt": thinkPrompt,
              "stream": false, "format": "json"
            }));
            
          final thinkBody = await thinkRes.stream.bytesToString();
          final thinkData = jsonDecode(thinkBody);
          final decision = _parseAgentJSON(thinkData['response']);
          
          final action = decision['action'] ?? 'finish';
          final thought = decision['thought'] ?? 'No thought provided.';
          final query = decision['query'] ?? '';
          
          node.ollamaResult += "> Thought: $thought\n"; notifyListeners();
          
          if (action == 'finish' || query.isEmpty) {
            node.ollamaResult += "> Action: Sufficient data gathered. Moving to synthesis.\n"; notifyListeners();
            break;
          }
          
          // Check flag again before searching
          if (_isForceAnswerTriggered) break;

          // Execute Search
          node.ollamaResult += "> Action: Searching Redleaf for '$query'...\n"; notifyListeners();
          final searchContext = await redleafService.fetchFtsContext(query);
          
          if (searchContext.contains("[No results found")) {
            accumulatedNotes += "\nSearch for '$query' yielded no results.";
            continue;
          }
          
          // Check flag again before note-taking
          if (_isForceAnswerTriggered) break;

          // Take Notes
          node.ollamaResult += "> Action: Reading documents and extracting facts...\n"; notifyListeners();
          final notePrompt = """You are a Research Analyst.
Your Goal: Extract facts from the text below to answer: "$userInstructions".
Text to Analyze:
$searchContext

Task: Extract specific facts, numbers, and details. Preserve [Doc X] citations.
If nothing relevant is found, return "Nothing relevant." """;

          final noteRes = await http.Client().send(http.Request('POST', Uri.parse('$_ollamaUrl/api/generate'))
            ..headers['Content-Type'] = 'application/json'
            ..body = jsonEncode({
              "model": _ollamaModel, "prompt": notePrompt, "stream": false,
            }));
            
          final noteBody = await noteRes.stream.bytesToString();
          final noteData = jsonDecode(noteBody);
          final extractedNotes = noteData['response'] ?? '';
          
          if (!extractedNotes.contains("Nothing relevant")) {
            accumulatedNotes += "\n" + extractedNotes;
          }
          
        } catch (e) { 
          node.ollamaResult += "> [Agent Error: $e]\n"; notifyListeners(); break; 
        }
      }

      if (accumulatedNotes != "No notes yet.") {
        finalPrompt.writeln("\n>>> AUTONOMOUSLY RESEARCHED NOTES <<<");
        finalPrompt.writeln(accumulatedNotes);
        finalPrompt.writeln(">>> END AUTONOMOUS NOTES <<<\n");
      }
    }

    // STEP 3: Final Send to Ollama
    node.ollamaResult = "🤖 Agent: Writing final synthesis...\n\n"; notifyListeners();
    final fullPayload = "$userInstructions\n\nHere is the source data and prompt nodes:\n$manualStoryContext\n${finalPrompt.toString()}";
    
    // --- MODIFIED: Inject Persona ---
    String systemInstruction = node.ollamaNoBacktalk 
      ? "You are a Redleaf Synthesis Agent. Output ONLY the resulting text. Do not include any conversational filler. Start immediately with the text. YOU MUST INCLUDE INLINE CITATIONS like [Doc 12] based on the REDLEAF CONTEXT provided." 
      : "You are a helpful writing assistant.";
      
    if (customPersona.isNotEmpty) {
      systemInstruction = "YOUR ACTIVE PERSONA: $customPersona\n\n$systemInstruction\nYou MUST adopt this persona completely in your writing style, tone, and perspective.";
    }

    try {
      final response = await http.Client().send(http.Request('POST', Uri.parse('$_ollamaUrl/api/generate'))
        ..headers['Content-Type'] = 'application/json'
        ..body = jsonEncode({ "model": _ollamaModel, "prompt": fullPayload, "system": systemInstruction, "stream": true, }));
      
      response.stream.transform(utf8.decoder).transform(const LineSplitter()).listen(
        (line) { 
          if (line.isNotEmpty) { 
            try { 
              bool isFirstToken = node.ollamaResult.contains("🤖 Agent: Writing final synthesis...\n\n");
              if (isFirstToken) node.ollamaResult = ""; 
              node.ollamaResult += jsonDecode(line)['response'] ?? ''; 
              notifyListeners(); 
            } catch (e) { } 
          } 
        },
        onDone: () { _generatingNodeId = null; _isForceAnswerTriggered = false; notifyListeners(); }, 
        onError: (e) { node.ollamaResult += "\n\n[Stream Error: $e]"; _generatingNodeId = null; _isForceAnswerTriggered = false; notifyListeners(); } 
      );
    } catch (e) { 
      node.ollamaResult = "⚠️ Failed to connect to Ollama.\nError details: $e"; 
      _generatingNodeId = null; _isForceAnswerTriggered = false;
      notifyListeners(); 
    }
  }

  // --- OLLAMA CHAT PIPELINE ---
  Future<void> triggerOllamaChat(StoryNode node, List<StoryNode> sequence, String userMessage, GraphState graphState) async {
    _generatingNodeId = node.id; 
    _isForceAnswerTriggered = false; // Reset flag
    notifyListeners();

    graphState.appendChatMessage(node.id, "user", userMessage);
    graphState.appendChatMessage(node.id, "assistant", "🤖 Gathering Redleaf Context...");

    StringBuffer contextBuffer = StringBuffer();
    String systemInstructions = node.ollamaPrompt.isNotEmpty ? node.ollamaPrompt : "You are a helpful research assistant.";

    if (node.ollamaNoBacktalk) {
      systemInstructions += "\n\nYou are a strict, analytical research agent. You MUST base your answers entirely on the provided REDLEAF CONTEXT. You MUST include inline citations exactly like [Doc 12] when stating facts derived from the context. Do not use conversational filler or backtalk.";
    }
    
    // --- ADDED: Persona Extraction ---
    String customPersona = "";

    // 2. Gather Context from the upstream chain
    for (var n in sequence) {
      if (n.type == NodeType.output || n.type == NodeType.chat || n.type == NodeType.study) continue;
      
      if (n.type == NodeType.persona) {
        customPersona = n.content.trim();
        continue;
      }
      
      if (n.type == NodeType.briefing) {
        final briefingContext = await redleafService.fetchSystemBriefing();
        contextBuffer.writeln("\n>>> REDLEAF SYSTEM BRIEFING <<<\n$briefingContext");
        if (n.content.trim().isNotEmpty) {
          contextBuffer.writeln("\n[USER OVERRIDE / MANUAL CONTEXT]:\n${n.content.trim()}");
        }
        contextBuffer.writeln(">>> END REDLEAF BRIEFING <<<\n");
        continue;
      }
      
      if (n.type == NodeType.search && n.content.isNotEmpty) {
        final searchContext = await redleafService.fetchAdvancedFtsContext(n.content, n.searchLimit, n.pinnedSearchResults);
        contextBuffer.writeln("\n>>> REDLEAF GLOBAL SEARCH: '${n.content}' <<<\n$searchContext\n");
        continue;
      }

      if (n.type == NodeType.document && n.content.isNotEmpty) {
        final docContext = await redleafService.fetchDocumentText(n.content);
        contextBuffer.writeln("\n>>> REDLEAF DOCUMENT <<<\n$docContext\n");
      } else if (n.type == NodeType.catalog && n.content.isNotEmpty) {
        final catId = int.tryParse(n.content);
        if (catId != null) {
          final catContext = await redleafService.fetchCatalogContext(catId, n.title);
          contextBuffer.writeln("\n>>> REDLEAF CATALOG <<<\n$catContext\n");
        }
      } else if (n.type == NodeType.intersection && n.redleafPills.isNotEmpty) {
        final topicNames = n.redleafPills.map((p) => p.text).toList();
        final intContext = await redleafService.fetchIntersectionContext(topicNames);
        contextBuffer.writeln("\n>>> REDLEAF CO-MENTIONS <<<\n$intContext\n");
      } else if (n.type == NodeType.relationship && n.redleafPills.isNotEmpty) {
        final pill = n.redleafPills.first; 
        final relContext = await redleafService.fetchEntityRelationships(pill.entityId, pill.text);
        contextBuffer.writeln("\n>>> REDLEAF GRAPH <<<\n$relContext\n");
      } else if (n.type == NodeType.scene) {
        contextBuffer.writeln("\n=== [USER NOTE: ${n.title}] ===\n${n.content}\n");
        if (n.redleafPills.isNotEmpty) {
          for (var pill in n.redleafPills) {
            final context = await redleafService.fetchContextForPill(pill);
            contextBuffer.writeln(context);
          }
        }
      }
    }

    for (var n in sequence) {
      if (n.type == NodeType.study && n.ollamaResult.isNotEmpty) {
        contextBuffer.writeln("\n>>> FACTUAL CONTEXT FROM DEEP STUDY: '${n.content}' <<<");
        contextBuffer.writeln(n.ollamaResult);
        contextBuffer.writeln(">>> END DEEP STUDY <<<\n");
      }
    }

    // 3. Autonomous Research (ReAct Loop tailored for Chat)
    if (node.enableAutonomousResearch && redleafService.isLoggedIn) {
      node.chatHistory.last["content"] = "🤖 Agent: Analyzing your message for required research...";
      graphState.notifyListeners();
      
      String accumulatedNotes = "";
      int maxSteps = 3; 
      
      for (int step = 1; step <= maxSteps; step++) {
        // Check flag
        if (_isForceAnswerTriggered) {
          node.chatHistory.last["content"] = "🤖 Agent: Moving to synthesis...";
          graphState.notifyListeners();
          break;
        }

        final thinkPrompt = """You are a Chat Assistant's Internal Brain.
User Message: "$userMessage"
Current Context gathered so far: ${accumulatedNotes.isEmpty ? "None" : accumulatedNotes}

Do you need more factual context from the database to answer the user?
Return JSON ONLY:
{
  "thought": "Reasoning about what is missing.",
  "action": "search" OR "finish",
  "query": "Your specific search phrase if action is search"
}""";

        try {
          final thinkRes = await http.Client().send(http.Request('POST', Uri.parse('$_ollamaUrl/api/generate'))
            ..headers['Content-Type'] = 'application/json'
            ..body = jsonEncode({
              "model": _ollamaModel, "prompt": thinkPrompt, "stream": false, "format": "json"
            }));
            
          final decision = _parseAgentJSON(jsonDecode(await thinkRes.stream.bytesToString())['response']);
          
          if (decision['action'] == 'finish' || (decision['query'] ?? '').isEmpty) break;
          
          // Check flag
          if (_isForceAnswerTriggered) break;

          final query = decision['query'];
          node.chatHistory.last["content"] = "🤖 Agent: Searching Redleaf for '$query'..."; 
          graphState.notifyListeners();
          
          final searchContext = await redleafService.fetchFtsContext(query);
          
          // Check flag
          if (_isForceAnswerTriggered) break;

          node.chatHistory.last["content"] = "🤖 Agent: Reading documents and taking notes..."; 
          graphState.notifyListeners();
          
          final notePrompt = """Extract facts from the text below to answer the User Message: "$userMessage".
Text:
$searchContext

Preserve [Doc X] citations. If nothing relevant is found, return "Nothing relevant." """;

          final noteRes = await http.Client().send(http.Request('POST', Uri.parse('$_ollamaUrl/api/generate'))
            ..headers['Content-Type'] = 'application/json'
            ..body = jsonEncode({"model": _ollamaModel, "prompt": notePrompt, "stream": false}));
            
          final extractedNotes = jsonDecode(await noteRes.stream.bytesToString())['response'] ?? '';
          if (!extractedNotes.contains("Nothing relevant")) {
            accumulatedNotes += "\n" + extractedNotes;
          }
        } catch (e) { break; }
      }

      if (accumulatedNotes.isNotEmpty) {
        contextBuffer.writeln("\n>>> AUTONOMOUSLY RESEARCHED NOTES <<<\n$accumulatedNotes\n");
      }
    }

    // --- MODIFIED: Inject Persona into Chat Instructions ---
    if (customPersona.isNotEmpty) {
      systemInstructions = "YOUR ACTIVE PERSONA: $customPersona\n\n$systemInstructions\nYou MUST adopt this persona completely in your writing style, tone, and perspective.";
    }

    // 4. Structure the API Payload
    List<Map<String, String>> apiMessages = [
      {"role": "system", "content": systemInstructions}
    ];
    
    for (int i = 0; i < node.chatHistory.length - 2; i++) {
      apiMessages.add(node.chatHistory[i]);
    }

    String finalUserPayload = userMessage;
    if (contextBuffer.isNotEmpty) {
      finalUserPayload = "REDLEAF KNOWLEDGE BASE CONTEXT FOR THIS TURN:\n${contextBuffer.toString()}\n\n---\nUSER MESSAGE:\n$userMessage";
    }
    
    apiMessages.add({"role": "user", "content": finalUserPayload});

    node.chatHistory.last["content"] = "";
    graphState.notifyListeners();

    try {
      final response = await http.Client().send(http.Request('POST', Uri.parse('$_ollamaUrl/api/chat'))
        ..headers['Content-Type'] = 'application/json'
        ..body = jsonEncode({ "model": _ollamaModel, "messages": apiMessages, "stream": true }));
      
      response.stream.transform(utf8.decoder).transform(const LineSplitter()).listen(
        (line) { 
          if (line.isNotEmpty) { 
            try { 
              final chunk = jsonDecode(line)['message']['content'] ?? '';
              graphState.streamToLastChatMessage(node.id, chunk);
            } catch (e) {} 
          } 
        },
        onDone: () { _generatingNodeId = null; _isForceAnswerTriggered = false; notifyListeners(); },
        onError: (e) { 
          graphState.streamToLastChatMessage(node.id, "\n\n[Stream Error: $e]");
          _generatingNodeId = null; _isForceAnswerTriggered = false; notifyListeners(); 
        }
      );
    } catch (e) { 
      graphState.streamToLastChatMessage(node.id, "⚠️ Failed to connect to Ollama. Error details: $e");
      _generatingNodeId = null; _isForceAnswerTriggered = false; notifyListeners(); 
    }
  }

  // --- DEEP STUDY PIPELINE ("GEEK OUT" NODE) ---
  Future<void> triggerStudyLoop(StoryNode node, List<StoryNode> sequence) async {
    _generatingNodeId = node.id;
    _isForceAnswerTriggered = false; // Reset flag
    node.ollamaResult = "🤖 Agent: Gathering upstream context...\n";
    notifyListeners();

    StringBuffer upstreamContext = StringBuffer();
    String objective = node.content.isNotEmpty ? node.content : "Conduct a comprehensive study based on the provided context.";
    
    // --- ADDED: Persona Extraction ---
    String customPersona = "";

    // 1. Gather Context from the upstream chain
    for (var n in sequence) {
      if (n.type == NodeType.output || n.type == NodeType.chat || n.type == NodeType.study) continue;
      
      if (n.type == NodeType.persona) {
        customPersona = n.content.trim();
        continue;
      }
      
      if (n.type == NodeType.briefing) {
        final briefingContext = await redleafService.fetchSystemBriefing();
        upstreamContext.writeln("\n>>> REDLEAF SYSTEM BRIEFING <<<\n$briefingContext");
        if (n.content.trim().isNotEmpty) upstreamContext.writeln("\n[USER OVERRIDE]:\n${n.content.trim()}");
        upstreamContext.writeln(">>> END REDLEAF BRIEFING <<<\n");
      } else if (n.type == NodeType.search && n.content.isNotEmpty) {
        final searchContext = await redleafService.fetchAdvancedFtsContext(n.content, n.searchLimit, n.pinnedSearchResults);
        upstreamContext.writeln("\n>>> REDLEAF GLOBAL SEARCH: '${n.content}' <<<\n$searchContext\n");
      } else if (n.type == NodeType.document && n.content.isNotEmpty) {
        final docContext = await redleafService.fetchDocumentText(n.content);
        upstreamContext.writeln("\n>>> REDLEAF DOCUMENT <<<\n$docContext\n");
      } else if (n.type == NodeType.catalog && n.content.isNotEmpty) {
        final catId = int.tryParse(n.content);
        if (catId != null) {
          final catContext = await redleafService.fetchCatalogContext(catId, n.title);
          upstreamContext.writeln("\n>>> REDLEAF CATALOG <<<\n$catContext\n");
        }
      } else if (n.type == NodeType.intersection && n.redleafPills.isNotEmpty) {
        final topicNames = n.redleafPills.map((p) => p.text).toList();
        final intContext = await redleafService.fetchIntersectionContext(topicNames);
        upstreamContext.writeln("\n>>> REDLEAF CO-MENTIONS <<<\n$intContext\n");
      } else if (n.type == NodeType.relationship && n.redleafPills.isNotEmpty) {
        final pill = n.redleafPills.first; 
        final relContext = await redleafService.fetchEntityRelationships(pill.entityId, pill.text);
        upstreamContext.writeln("\n>>> REDLEAF GRAPH <<<\n$relContext\n");
      } else if (n.type == NodeType.scene) {
        upstreamContext.writeln("\n=== [USER NOTE: ${n.title}] ===\n${n.content}\n");
        for (var pill in n.redleafPills) {
          upstreamContext.writeln(await redleafService.fetchContextForPill(pill));
        }
      }
    }

    String accumulatedNotes = "";
    int maxSteps = 5; 

    // 2. Autonomous Loop
    node.ollamaResult = "🤖 Agent: Initiating Deep Study on '$objective'...\n"; notifyListeners();

    for (int step = 1; step <= maxSteps; step++) {
      // Check flag
      if (_isForceAnswerTriggered) {
        node.ollamaResult += "\n> [User Override] Skipping remaining research steps. Moving to synthesis.\n";
        notifyListeners();
        break;
      }

      node.ollamaResult += "\n> [Step $step] Analyzing gaps in knowledge...\n"; notifyListeners();
      
      final thinkPrompt = """You are an Autonomous Research Engine.
Your Goal: "$objective"

Upstream Context Provided by User:
${upstreamContext.isEmpty ? "None" : upstreamContext.toString()}

Current Accumulated Notes from your searches:
${accumulatedNotes.isEmpty ? "None" : accumulatedNotes}

Analyze the Goal, the Upstream Context, and your Notes. What information is MISSING? 
Determine the SINGLE best next step.
Return JSON ONLY:
{
  "thought": "Internal reasoning about what information is still missing.",
  "action": "search" OR "finish",
  "query": "Your specific search phrase if action is search"
}""";

      try {
        final thinkRes = await http.Client().send(http.Request('POST', Uri.parse('$_ollamaUrl/api/generate'))
          ..headers['Content-Type'] = 'application/json'
          ..body = jsonEncode({"model": _ollamaModel, "prompt": thinkPrompt, "stream": false, "format": "json"}));
          
        final decision = _parseAgentJSON(jsonDecode(await thinkRes.stream.bytesToString())['response']);
        
        final action = decision['action'] ?? 'finish';
        final thought = decision['thought'] ?? 'No thought provided.';
        final query = decision['query'] ?? '';
        
        node.ollamaResult += "> Thought: $thought\n"; notifyListeners();
        
        if (action == 'finish' || query.isEmpty) {
          node.ollamaResult += "> Action: Sufficient data gathered. Moving to synthesis.\n"; notifyListeners();
          break;
        }
        
        // Check flag
        if (_isForceAnswerTriggered) break;

        node.ollamaResult += "> Action: Searching Redleaf for '$query'...\n"; notifyListeners();
        final searchContext = await redleafService.fetchFtsContext(query);
        
        if (searchContext.contains("[No results found")) {
          accumulatedNotes += "\nSearch for '$query' yielded no results.";
          continue;
        }
        
        // Check flag
        if (_isForceAnswerTriggered) break;

        node.ollamaResult += "> Action: Extracting relevant facts...\n"; notifyListeners();
        final notePrompt = """You are a Research Analyst.
Your Goal: Extract facts from the text below to help write a report on: "$objective".
Text to Analyze:
$searchContext

Task: Extract specific facts, numbers, and details. Preserve [Doc X] citations.
If nothing relevant is found, return "Nothing relevant." """;

        final noteRes = await http.Client().send(http.Request('POST', Uri.parse('$_ollamaUrl/api/generate'))
          ..headers['Content-Type'] = 'application/json'
          ..body = jsonEncode({"model": _ollamaModel, "prompt": notePrompt, "stream": false}));
          
        final extractedNotes = jsonDecode(await noteRes.stream.bytesToString())['response'] ?? '';
        if (!extractedNotes.contains("Nothing relevant")) {
          accumulatedNotes += "\n" + extractedNotes;
        }
      } catch (e) { 
        node.ollamaResult += "> [Agent Error: $e]\n"; notifyListeners(); break; 
      }
    }

    // 3. Final Synthesis
    node.ollamaResult = "🤖 Agent: Synthesizing final intelligence report...\n\n"; notifyListeners();
    String reportPrompt = """You are a Lead Researcher writing a final intelligence report.
Topic: "$objective"

Upstream Context provided by User:
${upstreamContext.isEmpty ? "None" : upstreamContext.toString()}

Accumulated Autonomous Research:
${accumulatedNotes.isEmpty ? "None" : accumulatedNotes}

Write a comprehensive, professional report on this topic using ONLY the provided context and research. 
Include inline citations like [Doc X] when stating facts derived from the research. 
Structure with an Executive Summary, Detailed Findings, and a Conclusion.""";

    // --- MODIFIED: Inject Persona into Study Report ---
    String systemInstruction = "You are a factual reporting agent.";
    if (customPersona.isNotEmpty) {
      systemInstruction = "YOUR ACTIVE PERSONA: $customPersona\n\nYou MUST adopt this persona completely in your writing style, tone, and perspective.";
    }

    try {
      final response = await http.Client().send(http.Request('POST', Uri.parse('$_ollamaUrl/api/generate'))
        ..headers['Content-Type'] = 'application/json'
        ..body = jsonEncode({ "model": _ollamaModel, "prompt": reportPrompt, "system": systemInstruction, "stream": true }));
      
      response.stream.transform(utf8.decoder).transform(const LineSplitter()).listen(
        (line) { 
          if (line.isNotEmpty) { 
            try { 
              bool isFirstToken = node.ollamaResult.contains("🤖 Agent: Synthesizing final intelligence report...\n\n");
              if (isFirstToken) node.ollamaResult = ""; 
              node.ollamaResult += jsonDecode(line)['response'] ?? ''; 
              notifyListeners(); 
            } catch (e) {} 
          } 
        },
        onDone: () { _generatingNodeId = null; _isForceAnswerTriggered = false; notifyListeners(); }, 
        onError: (e) { node.ollamaResult += "\n\n[Stream Error: $e]"; _generatingNodeId = null; _isForceAnswerTriggered = false; notifyListeners(); } 
      );
    } catch (e) { 
      node.ollamaResult = "⚠️ Failed to generate report.\nError details: $e"; 
      _generatingNodeId = null; _isForceAnswerTriggered = false; notifyListeners(); 
    }
  }
}