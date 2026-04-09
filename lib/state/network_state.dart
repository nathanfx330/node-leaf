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
  
  // --- Force Answer Flag ---
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

  // --- FORCE ANSWER TRIGGER ---
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

  Future<void> triggerOllamaGeneration(StoryNode node, List<StoryNode> sequence, GraphState graphState) async {
    _generatingNodeId = node.id; 
    _isForceAnswerTriggered = false; 
    node.ollamaResult = ""; 
    notifyListeners();

    StringBuffer finalPrompt = StringBuffer();
    String userInstructions = node.ollamaPrompt.isNotEmpty ? node.ollamaPrompt : "Process the following context.";
    String manualStoryContext = "";
    
    String customPersona = "";

    // STEP 1: Read the Chain (Manual Context)
    for (var n in sequence) {
      if (n.type == NodeType.output || n.type == NodeType.chat || n.type == NodeType.study || n.type == NodeType.summarize || n.type == NodeType.wikiWriter || n.type == NodeType.council) continue; 

      if (n.type == NodeType.persona) {
        customPersona = n.content.trim();
        continue;
      }

      if (n.type == NodeType.wikiReader && n.wikiTitle.isNotEmpty) {
        node.ollamaResult = "🤖 Reading Wiki Page '${n.wikiTitle}'...\n"; notifyListeners();
        final wikiContext = await graphState.readWikiPage(n.wikiTitle, this);
        finalPrompt.writeln("\n>>> CURRENT WIKI PAGE STATE: '${n.wikiTitle}' <<<");
        finalPrompt.writeln(wikiContext);
        finalPrompt.writeln(">>> END WIKI PAGE STATE <<<\n");
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
          
          if (_isForceAnswerTriggered) break;

          // Execute Search
          node.ollamaResult += "> Action: Searching Redleaf for '$query'...\n"; notifyListeners();
          final searchContext = await redleafService.fetchFtsContext(query);
          
          if (searchContext.contains("[No results found")) {
            accumulatedNotes += "\nSearch for '$query' yielded no results.";
            continue;
          }
          
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
    
    final currentDate = DateTime.now().toString().split('.')[0];
    String systemInstruction = node.ollamaNoBacktalk 
      ? "You are a Redleaf Synthesis Agent. Output ONLY the resulting text. Do not include any conversational filler. Start immediately with the text. YOU MUST INCLUDE INLINE CITATIONS like [Doc 12] based on the REDLEAF CONTEXT provided." 
      : "You are a helpful writing assistant.";
      
    if (customPersona.isNotEmpty) {
      systemInstruction = "YOUR ACTIVE PERSONA: $customPersona\n\n$systemInstruction\nYou MUST adopt this persona completely in your writing style, tone, and perspective.";
    }

    systemInstruction = "CURRENT SYSTEM TIME: $currentDate\n\n$systemInstruction";

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
    _isForceAnswerTriggered = false; 
    notifyListeners();

    graphState.appendChatMessage(node.id, "user", userMessage);
    graphState.appendChatMessage(node.id, "assistant", "🤖 Gathering Redleaf Context...");

    StringBuffer contextBuffer = StringBuffer();
    String systemInstructions = node.ollamaPrompt.isNotEmpty ? node.ollamaPrompt : "You are a helpful research assistant.";

    if (node.ollamaNoBacktalk) {
      systemInstructions += "\n\nYou are a strict, analytical research agent. You MUST base your answers entirely on the provided REDLEAF CONTEXT. You MUST include inline citations exactly like [Doc 12] when stating facts derived from the context. Do not use conversational filler or backtalk.";
    }
    
    String customPersona = "";

    // 2. Gather Context from the upstream chain
    for (var n in sequence) {
      if (n.type == NodeType.output || n.type == NodeType.chat || n.type == NodeType.study || n.type == NodeType.summarize || n.type == NodeType.wikiWriter || n.type == NodeType.council) continue;
      
      if (n.type == NodeType.persona) {
        customPersona = n.content.trim();
        continue;
      }
      
      if (n.type == NodeType.wikiReader && n.wikiTitle.isNotEmpty) {
        final wikiContext = await graphState.readWikiPage(n.wikiTitle, this);
        contextBuffer.writeln("\n>>> CURRENT WIKI PAGE STATE: '${n.wikiTitle}' <<<\n$wikiContext\n>>> END WIKI PAGE STATE <<<\n");
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
          if (_isForceAnswerTriggered) break;

          final query = decision['query'];
          node.chatHistory.last["content"] = "🤖 Agent: Searching Redleaf for '$query'..."; 
          graphState.notifyListeners();
          
          final searchContext = await redleafService.fetchFtsContext(query);
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

    final currentDate = DateTime.now().toString().split('.')[0];
    if (customPersona.isNotEmpty) {
      systemInstructions = "YOUR ACTIVE PERSONA: $customPersona\n\n$systemInstructions\nYou MUST adopt this persona completely in your writing style, tone, and perspective.";
    }
    systemInstructions = "CURRENT SYSTEM TIME: $currentDate\n\n$systemInstructions";

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
  Future<void> triggerStudyLoop(StoryNode node, List<StoryNode> sequence, GraphState graphState) async {
    _generatingNodeId = node.id;
    _isForceAnswerTriggered = false; 
    node.ollamaResult = "🤖 Agent: Gathering upstream context...\n";
    notifyListeners();

    StringBuffer upstreamContext = StringBuffer();
    String objective = node.content.isNotEmpty ? node.content : "Conduct a comprehensive study based on the provided context.";
    
    String customPersona = "";

    // 1. Gather Context from the upstream chain
    for (var n in sequence) {
      if (n.type == NodeType.output || n.type == NodeType.chat || n.type == NodeType.study || n.type == NodeType.summarize || n.type == NodeType.wikiWriter || n.type == NodeType.council) continue;
      
      if (n.type == NodeType.persona) {
        customPersona = n.content.trim();
        continue;
      }

      if (n.type == NodeType.wikiReader && n.wikiTitle.isNotEmpty) {
        upstreamContext.writeln("\n>>> CURRENT WIKI PAGE STATE: '${n.wikiTitle}' <<<");
        upstreamContext.writeln(await graphState.readWikiPage(n.wikiTitle, this));
        upstreamContext.writeln(">>> END WIKI PAGE STATE <<<\n");
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
        
        if (_isForceAnswerTriggered) break;

        node.ollamaResult += "> Action: Searching Redleaf for '$query'...\n"; notifyListeners();
        final searchContext = await redleafService.fetchFtsContext(query);
        
        if (searchContext.contains("[No results found")) {
          accumulatedNotes += "\nSearch for '$query' yielded no results.";
          continue;
        }
        
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

    final currentDate = DateTime.now().toString().split('.')[0];
    String systemInstruction = "You are a factual reporting agent.";
    if (customPersona.isNotEmpty) {
      systemInstruction = "YOUR ACTIVE PERSONA: $customPersona\n\nYou MUST adopt this persona completely in your writing style, tone, and perspective.";
    }
    systemInstruction = "CURRENT SYSTEM TIME: $currentDate\n\n$systemInstruction";

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

  // --- DIRECT PROMPT / SUMMARIZER PIPELINE ---
  Future<void> triggerSummarizeGeneration(StoryNode node, List<StoryNode> sequence, GraphState graphState) async {
    _generatingNodeId = node.id; 
    node.ollamaResult = "🤖 Gathering upstream context...\n"; notifyListeners();

    StringBuffer upstreamContext = StringBuffer();
    String customPersona = "";
    
    for (var n in sequence) {
      if (n.type == NodeType.output || n.type == NodeType.chat || n.type == NodeType.study || n.type == NodeType.summarize || n.type == NodeType.wikiWriter || n.type == NodeType.council) continue;
      
      if (n.type == NodeType.persona) {
        customPersona = n.content.trim();
        continue;
      }

      if (n.type == NodeType.wikiReader && n.wikiTitle.isNotEmpty) {
        upstreamContext.writeln("\n>>> CURRENT WIKI PAGE STATE: '${n.wikiTitle}' <<<");
        upstreamContext.writeln(await graphState.readWikiPage(n.wikiTitle, this));
        upstreamContext.writeln(">>> END WIKI PAGE STATE <<<\n");
        continue;
      }
      
      if (n.type == NodeType.briefing) {
        upstreamContext.writeln("\n>>> REDLEAF SYSTEM BRIEFING <<<");
        upstreamContext.writeln(await redleafService.fetchSystemBriefing());
        if (n.content.trim().isNotEmpty) upstreamContext.writeln("\n[USER OVERRIDE / MANUAL CONTEXT]:\n${n.content.trim()}");
        upstreamContext.writeln(">>> END REDLEAF BRIEFING <<<\n");
      } else if (n.type == NodeType.search && n.content.isNotEmpty) {
        upstreamContext.writeln("\n>>> REDLEAF GLOBAL SEARCH: '${n.content}' <<<");
        upstreamContext.writeln(await redleafService.fetchAdvancedFtsContext(n.content, n.searchLimit, n.pinnedSearchResults));
        upstreamContext.writeln(">>> END REDLEAF SEARCH <<<\n");
      } else if (n.type == NodeType.document && n.content.isNotEmpty) {
        upstreamContext.writeln("\n>>> REDLEAF DOCUMENT <<<");
        upstreamContext.writeln(await redleafService.fetchDocumentText(n.content));
        upstreamContext.writeln(">>> END REDLEAF DOCUMENT <<<\n");
      } else if (n.type == NodeType.catalog && n.content.isNotEmpty) {
        final catId = int.tryParse(n.content);
        if (catId != null) {
          upstreamContext.writeln("\n>>> REDLEAF CATALOG <<<");
          upstreamContext.writeln(await redleafService.fetchCatalogContext(catId, n.title));
          upstreamContext.writeln(">>> END REDLEAF CATALOG <<<\n");
        }
      } else if (n.type == NodeType.intersection && n.redleafPills.isNotEmpty) {
        upstreamContext.writeln("\n>>> REDLEAF CO-MENTIONS <<<");
        upstreamContext.writeln(await redleafService.fetchIntersectionContext(n.redleafPills.map((p) => p.text).toList()));
        upstreamContext.writeln(">>> END REDLEAF CO-MENTIONS <<<\n");
      } else if (n.type == NodeType.relationship && n.redleafPills.isNotEmpty) {
        upstreamContext.writeln("\n>>> REDLEAF GRAPH <<<");
        upstreamContext.writeln(await redleafService.fetchEntityRelationships(n.redleafPills.first.entityId, n.redleafPills.first.text));
        upstreamContext.writeln(">>> END REDLEAF GRAPH <<<\n");
      } else if (n.type == NodeType.scene) {
        upstreamContext.writeln("\n=== [USER NOTE: ${n.title}] ===\n${n.content}\n");
        for (var pill in n.redleafPills) {
          upstreamContext.writeln(await redleafService.fetchContextForPill(pill));
        }
      }
    }

    node.ollamaResult = "🤖 Generating response...\n\n"; notifyListeners();
    
    String userInstructions = node.ollamaPrompt.isNotEmpty 
        ? node.ollamaPrompt 
        : "Please provide a comprehensive and detailed summary of the following context material.";

    String fullPayload = "$userInstructions\n\nCONTEXT TO PROCESS:\n${upstreamContext.isEmpty ? "None" : upstreamContext.toString()}";

    final currentDate = DateTime.now().toString().split('.')[0];
    String systemInstruction = "You are a helpful and analytical AI assistant.";
    if (customPersona.isNotEmpty) {
      systemInstruction = "YOUR ACTIVE PERSONA: $customPersona\n\nYou MUST adopt this persona completely in your writing style, tone, and perspective.";
    }
    systemInstruction = "CURRENT SYSTEM TIME: $currentDate\n\n$systemInstruction";

    try {
      final response = await http.Client().send(http.Request('POST', Uri.parse('$_ollamaUrl/api/generate'))
        ..headers['Content-Type'] = 'application/json'
        ..body = jsonEncode({ "model": _ollamaModel, "prompt": fullPayload, "system": systemInstruction, "stream": true }));
      
      response.stream.transform(utf8.decoder).transform(const LineSplitter()).listen(
        (line) { 
          if (line.isNotEmpty) { 
            try { 
              bool isFirstToken = node.ollamaResult.contains("🤖 Generating response...\n\n");
              if (isFirstToken) node.ollamaResult = ""; 
              node.ollamaResult += jsonDecode(line)['response'] ?? ''; 
              notifyListeners(); 
            } catch (e) {} 
          } 
        },
        onDone: () { _generatingNodeId = null; notifyListeners(); }, 
        onError: (e) { node.ollamaResult += "\n\n[Stream Error: $e]"; _generatingNodeId = null; notifyListeners(); } 
      );
    } catch (e) { 
      node.ollamaResult = "⚠️ Failed to connect to Ollama.\nError details: $e"; 
      _generatingNodeId = null; notifyListeners(); 
    }
  }

  // --- WIKI WRITER PIPELINE ---
  Future<void> triggerWikiWriterGeneration(StoryNode node, List<StoryNode> sequence, GraphState graphState) async {
    _generatingNodeId = node.id; 
    _isForceAnswerTriggered = false;
    node.ollamaResult = "🤖 Gathering upstream context and reading Wiki...\n"; 
    notifyListeners();

    StringBuffer upstreamContext = StringBuffer();
    String customPersona = "";

    // 1. Gather Context
    for (var n in sequence) {
       if (n.type == NodeType.output || n.type == NodeType.chat || n.type == NodeType.study || n.type == NodeType.summarize || n.type == NodeType.wikiWriter || n.type == NodeType.council) continue;
       
       if (n.type == NodeType.persona) {
          customPersona = n.content.trim();
          continue;
       }

       if (n.type == NodeType.wikiReader && n.wikiTitle.isNotEmpty) {
          upstreamContext.writeln("\n>>> CURRENT WIKI PAGE STATE: '${n.wikiTitle}' <<<");
          upstreamContext.writeln(await graphState.readWikiPage(n.wikiTitle, this));
          upstreamContext.writeln(">>> END WIKI PAGE STATE <<<\n");
          continue;
       }

       if (n.type == NodeType.study && n.ollamaResult.isNotEmpty) {
         upstreamContext.writeln("\n>>> FACTUAL CONTEXT FROM DEEP STUDY: '${n.content}' <<<");
         upstreamContext.writeln(n.ollamaResult);
         upstreamContext.writeln(">>> END DEEP STUDY <<<\n");
         continue;
       }
       
       if (n.type == NodeType.chat && n.chatHistory.isNotEmpty) {
         upstreamContext.writeln("\n>>> CONTEXT FROM CHAT LOG <<<");
         for (var msg in n.chatHistory) {
           upstreamContext.writeln("${(msg['role'] ?? 'unknown').toUpperCase()}: ${msg['content']}");
         }
         upstreamContext.writeln(">>> END CHAT LOG <<<\n");
         continue;
       }

       // Add standard context
       if (n.type == NodeType.briefing) {
         upstreamContext.writeln("\n>>> REDLEAF SYSTEM BRIEFING <<<\n${await redleafService.fetchSystemBriefing()}\n>>> END REDLEAF BRIEFING <<<\n");
       } else if (n.type == NodeType.search && n.content.isNotEmpty) {
         upstreamContext.writeln("\n>>> REDLEAF GLOBAL SEARCH: '${n.content}' <<<\n${await redleafService.fetchAdvancedFtsContext(n.content, n.searchLimit, n.pinnedSearchResults)}\n>>> END REDLEAF SEARCH <<<\n");
       } else if (n.type == NodeType.document && n.content.isNotEmpty) {
         upstreamContext.writeln("\n>>> REDLEAF DOCUMENT <<<\n${await redleafService.fetchDocumentText(n.content)}\n>>> END REDLEAF DOCUMENT <<<\n");
       } else if (n.type == NodeType.catalog && n.content.isNotEmpty) {
         final catId = int.tryParse(n.content);
         if (catId != null) upstreamContext.writeln("\n>>> REDLEAF CATALOG <<<\n${await redleafService.fetchCatalogContext(catId, n.title)}\n>>> END REDLEAF CATALOG <<<\n");
       } else if (n.type == NodeType.intersection && n.redleafPills.isNotEmpty) {
         upstreamContext.writeln("\n>>> REDLEAF CO-MENTIONS <<<\n${await redleafService.fetchIntersectionContext(n.redleafPills.map((p) => p.text).toList())}\n>>> END REDLEAF CO-MENTIONS <<<\n");
       } else if (n.type == NodeType.relationship && n.redleafPills.isNotEmpty) {
         upstreamContext.writeln("\n>>> REDLEAF GRAPH <<<\n${await redleafService.fetchEntityRelationships(n.redleafPills.first.entityId, n.redleafPills.first.text)}\n>>> END REDLEAF GRAPH <<<\n");
       } else if (n.type == NodeType.scene) {
         upstreamContext.writeln("\n=== [USER NOTE: ${n.title}] ===\n${n.content}\n");
         for (var pill in n.redleafPills) upstreamContext.writeln(await redleafService.fetchContextForPill(pill));
       }
    }

    node.ollamaResult = "🤖 Editing Wiki Page...\n\n"; notifyListeners();
    
    String userInstructions = node.ollamaPrompt.isNotEmpty 
        ? node.ollamaPrompt 
        : "Review the CURRENT WIKI PAGE STATE and the NEW RESEARCH. Update the wiki page.";

    String fullPayload = "$userInstructions\n\nCONTEXT TO PROCESS:\n${upstreamContext.isEmpty ? "None" : upstreamContext.toString()}";

    final currentDate = DateTime.now().toString().split('.')[0];
    
    String systemInstruction = '''You are an expert Wikipedia Editor and Fact Checker.
Your task is to rewrite, expand, and format the target wiki page to seamlessly incorporate new facts from the provided context.

RULES:
1. If the new research agrees with the current wiki, seamlessly expand the article.
2. If the new research CONTRADICTS the current wiki, you MUST preserve the controversy. Do not erase the old claim; instead, write: 'While previous documents suggested X, newly analyzed [Doc Y] indicates Z.'
3. You MUST include inline citations like [Doc X] when adding new facts based on the REDLEAF context.
4. You MUST append a bullet point to the '### Revision History' section at the bottom of the file detailing exactly what you changed today and why. (Create this section if it doesn't exist).
5. Output ONLY valid Markdown. Do NOT wrap your response in markdown code blocks (e.g., no ```markdown). Output the raw text directly.''';

    if (customPersona.isNotEmpty) {
      systemInstruction = "YOUR ACTIVE PERSONA: $customPersona\n\n$systemInstruction\nYou MUST adopt this persona completely in your writing style, tone, and perspective while adhering to the editing rules.";
    }
    systemInstruction = "CURRENT SYSTEM TIME: $currentDate\n\n$systemInstruction";

    try {
      final response = await http.Client().send(http.Request('POST', Uri.parse('$_ollamaUrl/api/generate'))
        ..headers['Content-Type'] = 'application/json'
        ..body = jsonEncode({ "model": _ollamaModel, "prompt": fullPayload, "system": systemInstruction, "stream": true }));
      
      response.stream.transform(utf8.decoder).transform(const LineSplitter()).listen(
        (line) { 
          if (line.isNotEmpty) { 
            try { 
              bool isFirstToken = node.ollamaResult.contains("🤖 Editing Wiki Page...\n\n");
              if (isFirstToken) node.ollamaResult = ""; 
              node.ollamaResult += jsonDecode(line)['response'] ?? ''; 
              notifyListeners(); 
            } catch (e) {} 
          } 
        },
        onDone: () async { 
          _generatingNodeId = null; 
          notifyListeners(); 
          
          if (node.wikiTitle.isNotEmpty && node.ollamaResult.isNotEmpty) {
              bool success = await graphState.writeWikiPage(node.wikiTitle, node.ollamaResult.trim(), this);
              if (success) {
                  node.ollamaResult += "\n\n[System: Successfully saved to Wiki/${node.wikiTitle}.md]";
              } else {
                  node.ollamaResult += "\n\n[System Error: Failed to save to Wiki/${node.wikiTitle}.md]";
              }
              notifyListeners();
          }
        }, 
        onError: (e) { node.ollamaResult += "\n\n[Stream Error: $e]"; _generatingNodeId = null; notifyListeners(); } 
      );
    } catch (e) { 
      node.ollamaResult = "⚠️ Failed to connect to Ollama.\nError details: $e"; 
      _generatingNodeId = null; notifyListeners(); 
    }
  }

  // --- NEW: WIKI COUNCIL PIPELINE (MoE Debate Loop) ---
  Future<void> triggerCouncilGeneration(StoryNode node, List<StoryNode> sequence, GraphState graphState) async {
    _generatingNodeId = node.id; 
    _isForceAnswerTriggered = false;
    node.ollamaResult = "🏛️ Convening the Wiki Council...\n"; 
    notifyListeners();

    StringBuffer upstreamContext = StringBuffer();

    // 1. Gather Upstream Context
    for (var n in sequence) {
       if (n.type == NodeType.output || n.type == NodeType.chat || n.type == NodeType.study || n.type == NodeType.summarize || n.type == NodeType.wikiWriter || n.type == NodeType.council) continue;
       
       // Note: We ignore Persona nodes for the Council, as the Council has its own strict internal personas.

       if (n.type == NodeType.wikiReader && n.wikiTitle.isNotEmpty) {
          upstreamContext.writeln("\n>>> CURRENT WIKI PAGE STATE: '${n.wikiTitle}' <<<");
          upstreamContext.writeln(await graphState.readWikiPage(n.wikiTitle, this));
          upstreamContext.writeln(">>> END WIKI PAGE STATE <<<\n");
          continue;
       }

       if (n.type == NodeType.study && n.ollamaResult.isNotEmpty) {
         upstreamContext.writeln("\n>>> FACTUAL CONTEXT FROM DEEP STUDY: '${n.content}' <<<");
         upstreamContext.writeln(n.ollamaResult);
         upstreamContext.writeln(">>> END DEEP STUDY <<<\n");
         continue;
       }
       
       if (n.type == NodeType.chat && n.chatHistory.isNotEmpty) {
         upstreamContext.writeln("\n>>> CONTEXT FROM CHAT LOG <<<");
         for (var msg in n.chatHistory) {
           upstreamContext.writeln("${(msg['role'] ?? 'unknown').toUpperCase()}: ${msg['content']}");
         }
         upstreamContext.writeln(">>> END CHAT LOG <<<\n");
         continue;
       }

       if (n.type == NodeType.briefing) {
         upstreamContext.writeln("\n>>> REDLEAF SYSTEM BRIEFING <<<\n${await redleafService.fetchSystemBriefing()}\n>>> END REDLEAF BRIEFING <<<\n");
       } else if (n.type == NodeType.search && n.content.isNotEmpty) {
         upstreamContext.writeln("\n>>> REDLEAF GLOBAL SEARCH: '${n.content}' <<<\n${await redleafService.fetchAdvancedFtsContext(n.content, n.searchLimit, n.pinnedSearchResults)}\n>>> END REDLEAF SEARCH <<<\n");
       } else if (n.type == NodeType.document && n.content.isNotEmpty) {
         upstreamContext.writeln("\n>>> REDLEAF DOCUMENT <<<\n${await redleafService.fetchDocumentText(n.content)}\n>>> END REDLEAF DOCUMENT <<<\n");
       } else if (n.type == NodeType.catalog && n.content.isNotEmpty) {
         final catId = int.tryParse(n.content);
         if (catId != null) upstreamContext.writeln("\n>>> REDLEAF CATALOG <<<\n${await redleafService.fetchCatalogContext(catId, n.title)}\n>>> END REDLEAF CATALOG <<<\n");
       } else if (n.type == NodeType.intersection && n.redleafPills.isNotEmpty) {
         upstreamContext.writeln("\n>>> REDLEAF CO-MENTIONS <<<\n${await redleafService.fetchIntersectionContext(n.redleafPills.map((p) => p.text).toList())}\n>>> END REDLEAF CO-MENTIONS <<<\n");
       } else if (n.type == NodeType.relationship && n.redleafPills.isNotEmpty) {
         upstreamContext.writeln("\n>>> REDLEAF GRAPH <<<\n${await redleafService.fetchEntityRelationships(n.redleafPills.first.entityId, n.redleafPills.first.text)}\n>>> END REDLEAF GRAPH <<<\n");
       } else if (n.type == NodeType.scene) {
         upstreamContext.writeln("\n=== [USER NOTE: ${n.title}] ===\n${n.content}\n");
         for (var pill in n.redleafPills) upstreamContext.writeln(await redleafService.fetchContextForPill(pill));
       }
    }

    if (upstreamContext.isEmpty) {
        node.ollamaResult += "\n> [Error] The Council requires upstream context (like a Wiki Reader or Deep Study node) to analyze.";
        _generatingNodeId = null;
        notifyListeners();
        return;
    }

    // --- TURN 1: Initial Context Extraction ---
    node.ollamaResult += "\n> [System] Analyzing current knowledge state...\n"; notifyListeners();

    final phase1Prompt = """Review the provided upstream context and the current Wiki page.
Identify up to 3 core conceptual entities (People, Organizations, Specific Themes) that are central to this topic.
Return ONLY a JSON object: {"core_entities": ["Entity 1", "Entity 2"]}

CONTEXT TO ANALYZE:
${upstreamContext.toString()}""";

    List<String> coreEntities = [];
    try {
      final p1Res = await http.Client().send(http.Request('POST', Uri.parse('$_ollamaUrl/api/generate'))
        ..headers['Content-Type'] = 'application/json'
        ..body = jsonEncode({"model": _ollamaModel, "prompt": phase1Prompt, "stream": false, "format": "json"}));
        
      final p1Data = jsonDecode(await p1Res.stream.bytesToString());
      final p1Json = _parseAgentJSON(p1Data['response']);
      
      if (p1Json['core_entities'] is List) {
          coreEntities = List<String>.from(p1Json['core_entities']);
      }
    } catch (e) {
      node.ollamaResult += "> [System Error in Extraction: $e]\n"; notifyListeners();
      _generatingNodeId = null; return;
    }

    if (_isForceAnswerTriggered) {
       _generatingNodeId = null; _isForceAnswerTriggered = false; notifyListeners(); return;
    }

    // --- TURN 2: Redleaf Graph Mapping ---
    node.ollamaResult += "> [System] Mapping ontological gaps in Redleaf Graph for: ${coreEntities.join(', ')}\n"; notifyListeners();
    StringBuffer graphContext = StringBuffer();
    
    for (String entityName in coreEntities.take(3)) { 
        node.ollamaResult += "  - Consulting graph for '$entityName'...\n"; notifyListeners();
        final searchRes = await redleafService.searchEntities(entityName);
        
        if (searchRes.isNotEmpty) {
            final topMatch = searchRes.first;
            final id = await redleafService.extractEntityId(topMatch['label'], topMatch['text']);
            if (id != null) {
                graphContext.writeln(await redleafService.fetchEntityRelationships(id, topMatch['text']));
            }
        }
    }

    if (_isForceAnswerTriggered) {
       _generatingNodeId = null; _isForceAnswerTriggered = false; notifyListeners(); return;
    }

    // --- TURN 3: The MoE Debate Loop ---
    node.ollamaResult += "\n> [System] The Council has convened. Debate beginning...\n\n"; notifyListeners();

    // Define the distinct personas for the experts (Expanded Master Roster of 10)
    final List<Map<String, String>> masterRoster = [
      {"name": "The Visionary", "prompt": "You are The Visionary. You look for broad, sweeping connections, paradigm shifts, and unexplored themes. You think big picture."},
      {"name": "The Skeptic", "prompt": "You are The Skeptic. You look for missing evidence, logical leaps, and contradictory data. You demand rigor and highlight what we *don't* know."},
      {"name": "The Archivist", "prompt": "You are The Archivist. You look for historical context, specific entities, and chronological continuity. You care about the details."},
      {"name": "The Pragmatist", "prompt": "You are The Pragmatist. You focus on actionable, practical implications. Why does this matter? What is the tangible impact?"},
      {"name": "The Devil's Advocate", "prompt": "You are The Devil's Advocate. Your job is to actively argue against the consensus forming in the debate. Find the weak point and attack it."},
      {"name": "The Sociologist", "prompt": "You are The Sociologist. You look at human impact, organizational behavior, group dynamics, and cultural shifts."},
      {"name": "The Lateral Thinker", "prompt": "You are The Lateral Thinker. You look for bizarre, unconventional, or indirect connections that everyone else is missing."},
      {"name": "The Economist", "prompt": "You are The Economist. You analyze the context purely through the lens of incentives, resource allocation, and financial impact."},
      {"name": "The Synthesizer", "prompt": "You are The Synthesizer. Your job is to take the disparate points made by the others so far and attempt to merge them into a single cohesive theory."},
      {"name": "The Detective", "prompt": "You are The Detective. You look for motives, hidden agendas, structural anomalies, and things that seem 'off'."}
    ];

    String debateTranscript = "";
    int requestedAgents = node.councilAgentCount;
    
    // Select the experts (Up to 10 unique, looping if more requested)
    List<Map<String, String>> activeExperts = [];
    for (int i = 0; i < requestedAgents; i++) {
        activeExperts.add(masterRoster[i % masterRoster.length]);
    }

    // --- FIX: Add strict anti-RLHF instructions to the base prompt ---
    final String baseDebateRules = """
CRITICAL INSTRUCTIONS:
1. You MUST act entirely in character as your assigned persona.
2. DO NOT break the 4th wall. DO NOT act as an AI evaluating a prompt.
3. DO NOT congratulate the other speakers or say things like "Great point" or "I agree."
4. You MUST aggressively critique the research and point out flaws, missing data, or new angles.
""";

    // Loop through the selected agents
    for (int i = 0; i < activeExperts.length; i++) {
        if (_isForceAnswerTriggered) break;

        final expert = activeExperts[i];
        
        node.ollamaResult += ">>> ${expert['name']} is speaking...\n"; notifyListeners();

        final debatePrompt = """${expert['prompt']}
You are part of the Wiki Council. Your job is to find the 'white space' in the user's research.

$baseDebateRules

1. Review the User's Current Context.
2. Review the Redleaf Graph Data.
3. Review the ongoing Debate Transcript from your peers.

Add a single, concise paragraph to the debate. Point out a specific missing connection or suggest a new angle of research that the previous experts missed or got wrong. Do not summarize, just argue your point.

USER'S CURRENT CONTEXT:
${upstreamContext.toString()}

REDLEAF GRAPH DATA:
${graphContext.isEmpty ? "No extended graph connections found." : graphContext.toString()}

DEBATE TRANSCRIPT SO FAR:
${debateTranscript.isEmpty ? "You are the first to speak. Begin the debate." : debateTranscript}
""";

        try {
          final res = await http.Client().send(http.Request('POST', Uri.parse('$_ollamaUrl/api/generate'))
            ..headers['Content-Type'] = 'application/json'
            ..body = jsonEncode({"model": _ollamaModel, "prompt": debatePrompt, "stream": false}));
            
          final data = jsonDecode(await res.stream.bytesToString());
          final responseText = data['response'] ?? '';
          
          debateTranscript += "**${expert['name']}**: $responseText\n\n";
          node.ollamaResult += "${expert['name']}: $responseText\n\n"; notifyListeners();
          
        } catch (e) {
          node.ollamaResult += "> [Agent Error during debate: $e]\n"; notifyListeners();
        }
    }

    if (_isForceAnswerTriggered) {
       _generatingNodeId = null; _isForceAnswerTriggered = false; notifyListeners(); return;
    }

    // --- TURN 4: The Director (Synthesis) ---
    node.ollamaResult += "> [System] Debate concluded. Drafting final Council Audit Report...\n\n"; notifyListeners();

    final currentDate = DateTime.now().toString().split('.')[0];
    
    final synthesisPrompt = """You are the Director of the Wiki Council. 
You must synthesize the Debate Transcript into a final, actionable report.

Write a Council Audit Report containing:
1. **Missing Connections:** A synthesized summary of the ontological gaps identified by the experts.
2. **Suggested New Pages:** A bulleted list of recommended new Wiki pages to create based on the debate. For each, write a 1-sentence prompt that the user can feed into a 'Deep Study' agent to kickstart it.

DO NOT use boilerplate placeholders like [Your Name] or make up random dates.

DEBATE TRANSCRIPT:
$debateTranscript
""";

    String systemInstruction = "CURRENT SYSTEM TIME: $currentDate\n\nYou are the Director of the Wiki Council. You must synthesize the debate without using placeholders. Sign the report as 'The Director'. DO NOT evaluate the debate, just report the facts and suggestions.";

    try {
      final response = await http.Client().send(http.Request('POST', Uri.parse('$_ollamaUrl/api/generate'))
        ..headers['Content-Type'] = 'application/json'
        ..body = jsonEncode({ "model": _ollamaModel, "prompt": synthesisPrompt, "system": systemInstruction, "stream": true }));
      
      response.stream.transform(utf8.decoder).transform(const LineSplitter()).listen(
        (line) { 
          if (line.isNotEmpty) { 
            try { 
              bool isFirstToken = node.ollamaResult.contains("> [System] Debate concluded. Drafting final Council Audit Report...\n\n");
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
      node.ollamaResult += "\n⚠️ Failed to generate Council report.\nError details: $e"; 
      _generatingNodeId = null; _isForceAnswerTriggered = false; notifyListeners(); 
    }
  }
}