// --- File: lib/state/network_state.dart ---
import 'dart:async';
import 'package:flutter/material.dart';

import '../constants.dart';
import '../models/node_models.dart';
import '../services/redleaf_service.dart';
import '../services/ollama_service.dart';
import '../agents/wiki_council_agent.dart';
import '../agents/deep_study_agent.dart';
import '../agents/chat_agent.dart';
import '../agents/wiki_writer_agent.dart';
import '../agents/summarizer_agent.dart';
import '../agents/output_agent.dart';
import '../agents/research_party_agent.dart'; 
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

  // --- Interactive Input State ---
  String? _waitingForInputNodeId;
  Completer<String>? _inputCompleter;

  // --- Agent Tuning & Debug State ---
  double _semanticThreshold = 0.80;
  final List<String> _agentDebugLogs = [];

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

  // --- Tuning Getters ---
  double get semanticThreshold => _semanticThreshold;
  List<String> get agentDebugLogs => _agentDebugLogs;

  void setSemanticThreshold(double val) {
    _semanticThreshold = val;
    notifyListeners();
  }

  void addAgentDebugLog(String message) {
    final now = DateTime.now();
    final timeStr = "${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}";
    _agentDebugLogs.add("[$timeStr] $message");
    // Keep it from getting too massive
    if (_agentDebugLogs.length > 500) {
      _agentDebugLogs.removeAt(0);
    }
    notifyListeners(); // We want the debug window to update in real-time
  }

  void clearAgentDebugLogs() {
    _agentDebugLogs.clear();
    notifyListeners();
  }

  // --- Interactive Getters/Methods ---
  bool isNodeWaitingForInput(String nodeId) => _waitingForInputNodeId == nodeId;
  
  Future<String> waitForUserInput(String nodeId) async {
    _waitingForInputNodeId = nodeId;
    _inputCompleter = Completer<String>();
    notifyListeners();
    return _inputCompleter!.future;
  }
  
  void submitUserInput(String input) {
    if (_inputCompleter != null && !_inputCompleter!.isCompleted) {
      _inputCompleter!.complete(input);
    }
    _waitingForInputNodeId = null;
    _inputCompleter = null;
    notifyListeners();
  }

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

  Future<void> testAndSaveRedleafCredentials(String api, String user, String pass, GraphState graphState) async {
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
      graphState.calculateWikiGraph(this);
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
      final models = await OllamaService.fetchModels(_ollamaUrl);
      if (models.isNotEmpty) {
        _availableModels = models;
        if (!_availableModels.contains(_ollamaModel)) _ollamaModel = _availableModels.first;
      }
      _ollamaAuthStatus = AuthStatus.success;
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
      await OllamaService.preloadModel(_ollamaUrl, _ollamaModel);
      _isPreloadingModel = false; notifyListeners(); 
      return "Success";
    } catch (e) { 
      _isPreloadingModel = false; notifyListeners(); 
      return e.toString(); 
    }
  }

  Future<String> unloadOllamaModel() async {
    if (_ollamaModel.isEmpty) return "No model selected";
    try {
      await OllamaService.unloadModel(_ollamaUrl, _ollamaModel);
      return "Success";
    } catch (e) { 
      return e.toString(); 
    }
  }

  // --- FORCE ANSWER TRIGGER ---
  void forceAnswerNow() {
    if (_generatingNodeId != null) {
      _isForceAnswerTriggered = true;
      if (_inputCompleter != null && !_inputCompleter!.isCompleted) {
        _inputCompleter!.complete("");
        _waitingForInputNodeId = null;
      }
      notifyListeners();
    }
  }

  // --- LLM GENERATION PIPELINE ---

  Future<void> triggerOllamaGeneration(StoryNode node, List<StoryNode> sequence, GraphState graphState) async {
    _generatingNodeId = node.id; 
    _isForceAnswerTriggered = false; 
    notifyListeners();

    await OutputAgent.execute(
      node: node,
      sequence: sequence,
      graphState: graphState,
      networkState: this,
      checkForceAnswer: () => _isForceAnswerTriggered,
      onUpdate: () => notifyListeners(),
    );

    _generatingNodeId = null;
    _isForceAnswerTriggered = false;
    notifyListeners();
  }

  Future<void> triggerSummarizeGeneration(StoryNode node, List<StoryNode> sequence, GraphState graphState) async {
    _generatingNodeId = node.id; 
    _isForceAnswerTriggered = false;
    notifyListeners();

    await SummarizerAgent.execute(
      node: node,
      sequence: sequence,
      graphState: graphState,
      networkState: this,
      onUpdate: () => notifyListeners(),
    );

    _generatingNodeId = null;
    _isForceAnswerTriggered = false;
    notifyListeners();
  }

  Future<void> triggerWikiWriterGeneration(StoryNode node, List<StoryNode> sequence, GraphState graphState) async {
    _generatingNodeId = node.id; 
    _isForceAnswerTriggered = false;
    notifyListeners();

    await WikiWriterAgent.execute(
      node: node,
      sequence: sequence,
      graphState: graphState,
      networkState: this,
      onUpdate: () => notifyListeners(),
    );

    _generatingNodeId = null;
    _isForceAnswerTriggered = false;
    notifyListeners();
  }

  Future<void> triggerCouncilGeneration(StoryNode node, List<StoryNode> sequence, GraphState graphState) async {
    _generatingNodeId = node.id;
    _isForceAnswerTriggered = false;
    notifyListeners();

    await WikiCouncilAgent.execute(
      node: node,
      sequence: sequence,
      graphState: graphState,
      networkState: this,
      checkForceAnswer: () => _isForceAnswerTriggered,
      onUpdate: () => notifyListeners(),
    );

    _generatingNodeId = null;
    _isForceAnswerTriggered = false;
    notifyListeners();
  }
  
  Future<void> triggerStudyLoop(StoryNode node, List<StoryNode> sequence, GraphState graphState) async {
    _generatingNodeId = node.id;
    _isForceAnswerTriggered = false;
    notifyListeners();

    await DeepStudyAgent.execute(
      node: node,
      sequence: sequence,
      graphState: graphState,
      networkState: this,
      checkForceAnswer: () => _isForceAnswerTriggered,
      onUpdate: () => notifyListeners(),
    );

    _generatingNodeId = null;
    _isForceAnswerTriggered = false;
    notifyListeners();
  }

  Future<void> triggerOllamaChat(StoryNode node, List<StoryNode> sequence, String userMessage, GraphState graphState) async {
    _generatingNodeId = node.id; 
    _isForceAnswerTriggered = false; 
    notifyListeners();

    await ChatAgent.execute(
      node: node,
      sequence: sequence,
      userMessage: userMessage,
      graphState: graphState,
      networkState: this,
      checkForceAnswer: () => _isForceAnswerTriggered,
      onUpdate: () => notifyListeners(),
    );

    _generatingNodeId = null;
    _isForceAnswerTriggered = false;
    notifyListeners();
  }

  Future<void> triggerResearchPartyLoop(StoryNode node, List<StoryNode> sequence, GraphState graphState) async {
    _generatingNodeId = node.id;
    _isForceAnswerTriggered = false;
    notifyListeners();

    await ResearchPartyAgent.execute(
      node: node,
      sequence: sequence,
      graphState: graphState,
      networkState: this,
      checkForceAnswer: () => _isForceAnswerTriggered,
      onUpdate: () => notifyListeners(),
    );

    _generatingNodeId = null;
    _isForceAnswerTriggered = false;
    notifyListeners();
  }
}