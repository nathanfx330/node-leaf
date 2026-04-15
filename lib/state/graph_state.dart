// --- File: lib/state/graph_state.dart ---
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart'; // <-- ADDED for compute()
import 'package:uuid/uuid.dart';
import 'package:file_picker/file_picker.dart';

import '../constants.dart';
import '../models/node_models.dart';
import 'network_state.dart';

// --- NEW: TOP-LEVEL FUNCTION FOR ISOLATE ---
// This runs the heavy regex parsing and Markov Chain math on a background thread
// so the UI doesn't freeze when the user has thousands of Wiki pages.
Map<String, dynamic> _computeNodeRank(Map<String, String> pageContents) {
  List<String> pages = pageContents.keys.toList();
  final int N = pages.length;
  if (N == 0) return {'ranks': <String, double>{}, 'outLinks': <String, List<String>>{}};

  // 1. Parse Markdown for Wikilinks: [[Target Page]]
  final linkRegex = RegExp(r'\[\[(.*?)\]\]');
  Map<String, List<String>> outLinks = {};
  
  for (var page in pages) {
    final content = pageContents[page] ?? "";
    final matches = linkRegex.allMatches(content);
    
    Set<String> uniqueTargets = {};
    for (var match in matches) {
      final rawTarget = match.group(1)?.trim();
      if (rawTarget != null && rawTarget.isNotEmpty) {
        // Normalize the target string exactly how we normalize filenames
        final safeTarget = rawTarget.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_').replaceAll(' ', '_');
        
        // Only add edges to pages that actually exist in our wiki
        if (pages.contains(safeTarget)) {
          uniqueTargets.add(safeTarget);
        }
      }
    }
    outLinks[page] = uniqueTargets.toList();
  }

  // 2. NodeRank Algorithm (Markov Chain)
  Map<String, double> ranks = { for (var p in pages) p: 1.0 / N };
  const double d = 0.85; // Damping factor (probability of clicking a link vs random jumping)
  const int iterations = 25; // 25 iterations is highly accurate for graphs under 10k nodes

  for (int i = 0; i < iterations; i++) {
    // Initialize new ranks with the random jump probability
    Map<String, double> newRanks = { for (var p in pages) p: (1.0 - d) / N };
    double danglingSum = 0.0;

    // Find "Dangling Nodes" (pages with no outgoing links)
    for (var p in pages) {
      if (outLinks[p]!.isEmpty) {
        danglingSum += ranks[p]!;
      }
    }

    // Dangling nodes essentially link to EVERY page equally
    if (danglingSum > 0) {
        final share = (d * danglingSum) / N;
        for (var p in pages) {
          newRanks[p] = newRanks[p]! + share;
        }
    }

    // Distribute rank across existing edges
    for (var p in pages) {
      final targets = outLinks[p]!;
      if (targets.isNotEmpty) {
        final contribution = (ranks[p]! * d) / targets.length;
        for (var target in targets) {
          newRanks[target] = newRanks[target]! + contribution;
        }
      }
    }
    ranks = newRanks;
  }

  // 3. Normalize for the UI (Scale highest page to exactly 1.0)
  double maxRank = ranks.values.fold(0.0, (m, v) => v > m ? v : m);
  if (maxRank > 0) {
    for (var p in pages) {
      ranks[p] = ranks[p]! / maxRank; 
    }
  }

  return {
    'ranks': ranks,
    'outLinks': outLinks
  };
}

class GraphState extends ChangeNotifier {
  Map<String, StoryNode> _nodes = {};
  String _projectName = "Untitled";
  String? _activeFilePath;

  Set<String> _selectedNodeIds = {};
  String? _previewNodeId;
  String? _clipboardData;

  Map<String, int> _nodeSequence = {};
  Set<String> _activePathIds = {};

  final List<String> _undoStack = [];
  static const int _maxUndo = 20; 
  Timer? _undoDebounceTimer;

  // --- NEW: WIKI KNOWLEDGE GRAPH ---
  Map<String, double> _wikiNodeRanks = {};
  Map<String, List<String>> _wikiOutgoingLinks = {};

  // Getters
  Map<String, StoryNode> get nodes => _nodes;
  String get projectName => _projectName;
  String? get activeFilePath => _activeFilePath;
  Set<String> get selectedNodeIds => _selectedNodeIds;
  String? get previewNodeId => _previewNodeId;
  Set<String> get activePathIds => _activePathIds;
  int getNodeIndex(String id) => _nodeSequence[id] ?? -1;

  Map<String, double> get wikiNodeRanks => _wikiNodeRanks;
  Map<String, List<String>> get wikiOutgoingLinks => _wikiOutgoingLinks;

  // --- PROJECT MANAGEMENT (SAVE / LOAD) ---

  void newProject(NetworkState networkState) {
    _nodes.clear(); 
    _undoStack.clear(); 
    _projectName = "Untitled"; 
    _activeFilePath = null;
    _selectedNodeIds.clear(); 
    _clipboardData = null; 
    
    networkState.resetNetworkState();

    final sceneId = const Uuid().v4();
    final outputId = const Uuid().v4();

    _nodes[sceneId] = StoryNode(id: sceneId, position: const Offset(kWorldSize / 2, kWorldSize / 2), title: "Start Here", content: "Write instructions...");
    _nodes[outputId] = StoryNode(id: outputId, type: NodeType.output, position: const Offset(kWorldSize / 2, kWorldSize / 2 + 250), title: "FINAL OUTPUT", ollamaPrompt: "Synthesize findings strictly based on the provided REDLEAF KNOWLEDGE BASE context.");

    _selectedNodeIds = {sceneId};
    recalculateSequence(); 
    calculateWikiGraph(networkState); // Trigger graph calculation
    notifyListeners();
  }

  Future<void> saveProject(NetworkState networkState) async {
    if (_activeFilePath == null) { await saveAsProject(networkState); return; }
    await _writeToDisk(_activeFilePath!, networkState);
  }

  Future<void> saveAsProject(NetworkState networkState) async {
    String? initialDir;
    if (networkState.redleafService.redleafBaseDir.isNotEmpty) {
      final dir = Directory("${networkState.redleafService.redleafBaseDir}${Platform.pathSeparator}Node-leaf-saves");
      if (!await dir.exists()) {
        try { 
          await dir.create(recursive: true); 
        } catch (e) {
          debugPrint("Could not create save directory: $e");
        }
      }
      initialDir = dir.path;
    }

    String? outputFile = await FilePicker.platform.saveFile(
      dialogTitle: 'Save Node Leaf Project', 
      initialDirectory: initialDir, 
      fileName: '$_projectName.nlf', 
      type: FileType.custom, 
      allowedExtensions: ['nlf'],
    );
    if (outputFile == null) return;
    if (!outputFile.endsWith('.nlf')) outputFile = '$outputFile.nlf';
    _activeFilePath = outputFile;
    _projectName = outputFile.split(Platform.pathSeparator).last.replaceAll('.nlf', '');
    await _writeToDisk(_activeFilePath!, networkState); 
    notifyListeners();
  }

  Future<void> _writeToDisk(String path, NetworkState networkState) async {
    final Map<String, dynamic> projectData = {
      'version': 28, // Incremented version for Wiki features
      'name': _projectName, 
      'ollama_url': networkState.ollamaUrl, 
      'ollama_model': networkState.ollamaModel, 
      'redleaf_instance_id': networkState.redleafInstanceId,
      'redleaf_api': networkState.redleafService.apiUrl, 
      'redleaf_user': networkState.redleafService.username,
      'nodes': _nodes.values.map((n) => n.toJson()).toList(),
    };
    try { 
      await File(path).writeAsString(jsonEncode(projectData)); 
      debugPrint("Saved to $path"); 
    } catch (e) { 
      debugPrint("Error saving project: $e"); 
    }
  }

  Future<void> loadProject(NetworkState networkState) async {
    String? initialDir;
    if (networkState.redleafService.redleafBaseDir.isNotEmpty) {
      final dir = Directory("${networkState.redleafService.redleafBaseDir}${Platform.pathSeparator}Node-leaf-saves");
      if (await dir.exists()) {
        initialDir = dir.path;
      }
    }

    FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.custom, 
      allowedExtensions: ['nlf', 'nw'],
      initialDirectory: initialDir,
    );
    if (result != null && result.files.single.path != null) {
      final path = result.files.single.path!;
      try {
        final String jsonStr = await File(path).readAsString();
        _loadFromJson(jsonStr, networkState); 
        _activeFilePath = path; 
        notifyListeners();
      } catch (e) { 
        debugPrint("Error loading: $e"); 
      }
    }
  }

  void _loadFromJson(String jsonStr, NetworkState networkState) {
    try {
      final Map<String, dynamic> data = jsonDecode(jsonStr);
      _nodes.clear(); 
      _undoStack.clear();
      _projectName = data['name'] ?? "Untitled"; 
      
      networkState.loadNetworkConfig(
        instanceId: data['redleaf_instance_id'],
        ollamaUrl: data['ollama_url'],
        apiUrl: data['redleaf_api'],
        user: data['redleaf_user'],
        model: data['ollama_model']
      );
      
      for (var n in data['nodes']) { 
        final node = StoryNode.fromJson(n); 
        _nodes[node.id] = node; 
      }
      _selectedNodeIds.clear(); 
      _previewNodeId = null; 
      recalculateSequence();
      calculateWikiGraph(networkState); // Trigger graph calculation on load
      
    } catch (e) { 
      debugPrint("Parse Error: $e"); 
    }
  }

  // --- WIKI FILE MANAGEMENT ---

  Future<Directory?> _getWikiDirectory(NetworkState networkState) async {
    final baseDir = networkState.redleafService.redleafBaseDir;
    if (baseDir.isEmpty) return null;
    final dir = Directory("$baseDir${Platform.pathSeparator}Node-leaf-saves${Platform.pathSeparator}Wiki");
    if (!await dir.exists()) {
      try {
        await dir.create(recursive: true);
      } catch (e) {
        debugPrint("Could not create Wiki directory: $e");
        return null;
      }
    }
    return dir;
  }

  Future<String> readWikiPage(String title, NetworkState networkState) async {
    if (title.trim().isEmpty) return "Error: Wiki title is empty.";
    final dir = await _getWikiDirectory(networkState);
    if (dir == null) return "Error: Could not locate Redleaf base directory to find Wiki folder. Ensure you are connected to Redleaf.";
    
    final safeTitle = title.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_').replaceAll(' ', '_');
    final file = File("${dir.path}${Platform.pathSeparator}$safeTitle.md");
    
    if (await file.exists()) {
      try {
        return await file.readAsString();
      } catch (e) {
        return "Error reading wiki page: $e";
      }
    } else {
      return "This page is currently empty. You are writing the first draft.";
    }
  }

  Future<void> _createWikiBackup(String title, NetworkState networkState) async {
    final dir = await _getWikiDirectory(networkState);
    if (dir == null) return;
    
    final safeTitle = title.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_').replaceAll(' ', '_');
    final originalFile = File("${dir.path}${Platform.pathSeparator}$safeTitle.md");
    
    if (await originalFile.exists()) {
      try {
        final historyDir = Directory("${dir.path}${Platform.pathSeparator}.history");
        if (!await historyDir.exists()) {
          await historyDir.create(recursive: true);
        }
        
        final now = DateTime.now();
        final timestamp = "${now.year}${now.month.toString().padLeft(2,'0')}${now.day.toString().padLeft(2,'0')}_${now.hour.toString().padLeft(2,'0')}${now.minute.toString().padLeft(2,'0')}${now.second.toString().padLeft(2,'0')}";
        
        final backupFile = File("${historyDir.path}${Platform.pathSeparator}${safeTitle}_$timestamp.md");
        await originalFile.copy(backupFile.path);
        debugPrint("Wiki backup created at: ${backupFile.path}");
      } catch (e) {
        debugPrint("Failed to create wiki backup: $e");
      }
    }
  }

  Future<bool> writeWikiPage(String title, String content, NetworkState networkState) async {
    if (title.trim().isEmpty) return false;
    final dir = await _getWikiDirectory(networkState);
    if (dir == null) return false;
    
    // Backup the existing file first for Git-style history
    await _createWikiBackup(title, networkState);
    
    final safeTitle = title.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_').replaceAll(' ', '_');
    final file = File("${dir.path}${Platform.pathSeparator}$safeTitle.md");
    
    try {
      await file.writeAsString(content);
      debugPrint("Wiki page written to: ${file.path}");
      
      // Automatically recalculate the Markov Chain graph!
      calculateWikiGraph(networkState);
      
      return true;
    } catch (e) {
      debugPrint("Failed to write wiki page: $e");
      return false;
    }
  }

  void updateWikiTitle(String id, String title) {
    if (_nodes.containsKey(id) && _nodes[id]!.wikiTitle != title) {
      requestUndoSnapshot();
      _nodes[id]!.wikiTitle = title;
      notifyListeners();
    }
  }

  Future<List<String>> listWikiPages(NetworkState networkState) async {
    final dir = await _getWikiDirectory(networkState);
    if (dir == null) return [];
    
    List<String> pages = [];
    try {
      final entities = dir.listSync();
      for (var entity in entities) {
        if (entity is File && entity.path.endsWith('.md')) {
          final filename = entity.path.split(Platform.pathSeparator).last;
          final title = filename.substring(0, filename.length - 3);
          pages.add(title);
        }
      }
      pages.sort(); 
      return pages;
    } catch (e) {
      debugPrint("Error listing wiki pages: $e");
      return [];
    }
  }

  Future<List<String>> getWikiHistory(String title, NetworkState networkState) async {
    if (title.trim().isEmpty) return [];
    final dir = await _getWikiDirectory(networkState);
    if (dir == null) return [];

    final safeTitle = title.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_').replaceAll(' ', '_');
    final historyDir = Directory("${dir.path}${Platform.pathSeparator}.history");

    if (!await historyDir.exists()) return [];

    List<String> backups = [];
    try {
      final entities = historyDir.listSync();
      for (var entity in entities) {
        if (entity is File && entity.path.endsWith('.md')) {
          final filename = entity.path.split(Platform.pathSeparator).last;
          if (filename.startsWith("${safeTitle}_")) {
            backups.add(filename);
          }
        }
      }
      backups.sort((a, b) => b.compareTo(a)); // Newest first
      return backups;
    } catch (e) {
      debugPrint("Error listing history: $e");
      return [];
    }
  }

  Future<String?> readWikiBackup(String backupFilename, NetworkState networkState) async {
    final dir = await _getWikiDirectory(networkState);
    if (dir == null) return null;
    
    final file = File("${dir.path}${Platform.pathSeparator}.history${Platform.pathSeparator}$backupFilename");
    if (await file.exists()) {
      try {
        return await file.readAsString();
      } catch (e) {
        debugPrint("Error reading backup: $e");
        return null;
      }
    }
    return null;
  }

  // --- NEW: MARKOV CHAIN / NODERANK ALGORITHM ---
  
  Future<void> calculateWikiGraph(NetworkState networkState) async {
    final dir = await _getWikiDirectory(networkState);
    if (dir == null) return;

    Map<String, String> pageContents = {};

    // 1. Read all files asynchronously to prevent UI freeze
    try {
      final entities = await dir.list().toList();
      List<Future<void>> readTasks = [];

      for (var entity in entities) {
        if (entity is File && entity.path.endsWith('.md')) {
          final filename = entity.path.split(Platform.pathSeparator).last;
          final title = filename.substring(0, filename.length - 3);
          
          readTasks.add(entity.readAsString().then((content) {
            pageContents[title] = content;
          }));
        }
      }
      // Wait for all I/O to finish in parallel
      await Future.wait(readTasks);
    } catch (e) {
      debugPrint("Error reading wiki files for graph: $e");
      return;
    }

    if (pageContents.isEmpty) {
      _wikiNodeRanks.clear();
      _wikiOutgoingLinks.clear();
      notifyListeners();
      return;
    }

    // 2. Offload heavy regex parsing and math to a background Isolate
    final result = await compute(_computeNodeRank, pageContents);

    _wikiNodeRanks = Map<String, double>.from(result['ranks']);
    
    _wikiOutgoingLinks = (result['outLinks'] as Map<String, dynamic>).map(
      (key, value) => MapEntry(key, List<String>.from(value))
    );
    
    debugPrint("Wiki Graph updated. Processed ${pageContents.length} nodes.");
    notifyListeners();
  }

  // --- NODE CRUD & SELECTION ---

  void addNode(Offset centerPos, [NodeType type = NodeType.scene]) {
    recordUndo();
    final id = const Uuid().v4();
    String title = "New Node";
    if (type == NodeType.search) title = "Global Search";
    if (type == NodeType.document) title = "Read Document";
    if (type == NodeType.output) title = "Ollama Output";
    if (type == NodeType.relationship) title = "Graph Entity";
    if (type == NodeType.catalog) title = "Read Catalog";
    if (type == NodeType.intersection) title = "Co-Mentions";
    if (type == NodeType.chat) title = "Ollama Chat";
    if (type == NodeType.briefing) title = "System Briefing";
    if (type == NodeType.persona) title = "Agent Persona"; 
    if (type == NodeType.study) title = "Deep Study"; 
    if (type == NodeType.summarize) title = "Summarizer";
    if (type == NodeType.wikiReader) title = "Wiki Reader"; 
    if (type == NodeType.wikiWriter) title = "Wiki Writer"; 
    if (type == NodeType.council) title = "Wiki Council";
    if (type == NodeType.researchParty) title = "Research Party";

    _nodes[id] = StoryNode(id: id, position: centerPos - const Offset(kNodeWidth / 2, kNodeHeight / 2), title: title, type: type);
    _selectedNodeIds = {id};
    notifyListeners();
  }

  void deleteSelected() {
    if (_selectedNodeIds.isEmpty) return;
    recordUndo();
    final toDelete = _selectedNodeIds.toList();
    for (var id in toDelete) {
      _nodes.remove(id);
      for (var node in _nodes.values) node.nextNodeIds.remove(id);
    }
    _selectedNodeIds.clear(); 
    _previewNodeId = null;
    recalculateSequence();
    notifyListeners();
  }

  void updateNodePosition(String id, Offset delta) {
    requestUndoSnapshot(); 
    if (_selectedNodeIds.contains(id)) {
      for (var selId in _selectedNodeIds) { 
        if (_nodes.containsKey(selId)) _nodes[selId]!.position += delta; 
      }
    } else { 
      if (_nodes.containsKey(id)) _nodes[id]!.position += delta; 
    }
    notifyListeners();
  }

  void selectNode(String id, {bool additive = false}) {
    if (additive) { 
      if (_selectedNodeIds.contains(id)) _selectedNodeIds.remove(id); 
      else _selectedNodeIds.add(id); 
    } else { 
      if (!_selectedNodeIds.contains(id)) _selectedNodeIds = {id}; 
    }
    notifyListeners();
  }

  void clearSelection() { 
    if (_selectedNodeIds.isNotEmpty) { 
      _selectedNodeIds.clear(); 
      notifyListeners(); 
    } 
  }

  void selectNodesInRect(Rect rect) {
    _selectedNodeIds = _nodes.values.where((n) => rect.overlaps(n.rect)).map((n) => n.id).toSet();
    notifyListeners();
  }

  void setPreviewNode(String? id) { 
    _previewNodeId = id; 
    notifyListeners(); 
  }

  // --- GRAPH TOPOLOGY (WIRES) ---

  void connectNode(String sourceId, String targetId) {
    recordUndo();
    final source = _nodes[sourceId]!;
    for (var n in _nodes.values) { 
      if (n.nextNodeIds.contains(targetId)) n.nextNodeIds.remove(targetId); 
    }
    source.nextNodeIds.add(targetId); 
    recalculateSequence();
    notifyListeners();
  }

  void swapNodeConnections(String sourceId, String targetId) {
    recordUndo();
    final source = _nodes[sourceId]!;
    final target = _nodes[targetId]!;
    source.nextNodeIds = List.from(target.nextNodeIds);
    target.nextNodeIds.clear(); 
    recalculateSequence();
    notifyListeners();
  }

  void disconnectNode(String id) { 
    recordUndo(); 
    if (_nodes.containsKey(id)) { 
      _nodes[id]!.nextNodeIds.clear(); 
      recalculateSequence(); 
      notifyListeners(); 
    } 
  }

  void popNodeOut(String id) {
    if (!_nodes.containsKey(id)) return;
    recordUndo(); 
    final nodeToPop = _nodes[id]!;
    final childrenIds = List<String>.from(nodeToPop.nextNodeIds);
    for (var node in _nodes.values) {
      if (node.nextNodeIds.contains(id)) {
        node.nextNodeIds.remove(id);
        for (var childId in childrenIds) { 
          if (!node.nextNodeIds.contains(childId)) node.nextNodeIds.add(childId); 
        }
      }
    }
    nodeToPop.nextNodeIds.clear(); 
    recalculateSequence(); 
    notifyListeners();
  }

  void insertNodeIntoWire(String sourceId, int wireIndex, String newNodeId) {
    recordUndo();
    final source = _nodes[sourceId];
    if (source != null && wireIndex < source.nextNodeIds.length) {
      final targetId = source.nextNodeIds[wireIndex];
      source.nextNodeIds[wireIndex] = newNodeId;
      if (!_nodes[newNodeId]!.nextNodeIds.contains(targetId)) {
        _nodes[newNodeId]!.nextNodeIds = [targetId];
      }
    }
    recalculateSequence();
    notifyListeners();
  }

  // --- UNDO / REDO / CLIPBOARD ---

  void requestUndoSnapshot() { 
    if (_undoDebounceTimer == null || !_undoDebounceTimer!.isActive) recordUndo(); 
    _undoDebounceTimer?.cancel(); 
    _undoDebounceTimer = Timer(const Duration(seconds: 1), () {}); 
  }
  
  void recordUndo() { 
    final state = jsonEncode({'nodes': _nodes.values.map((n) => n.toJson()).toList(), 'name': _projectName}); 
    if (_undoStack.isNotEmpty && _undoStack.last == state) return; 
    _undoStack.add(state); 
    if (_undoStack.length > _maxUndo) _undoStack.removeAt(0); 
  }
  
  void undo() { 
    if (_undoStack.isEmpty) return; 
    final previousJson = _undoStack.removeLast(); 
    try { 
      final Map<String, dynamic> data = jsonDecode(previousJson); 
      _nodes.clear(); 
      _projectName = data['name']; 
      for (var n in data['nodes']) { 
        final node = StoryNode.fromJson(n); 
        _nodes[node.id] = node; 
      } 
      _selectedNodeIds.removeWhere((id) => !_nodes.containsKey(id)); 
      if (_previewNodeId != null && !_nodes.containsKey(_previewNodeId)) _previewNodeId = null; 
      recalculateSequence(); 
      notifyListeners(); 
    } catch (e) { debugPrint("Undo Error: $e"); } 
  }

  void copySelection() { 
    if (_selectedNodeIds.isEmpty) return; 
    final id = _selectedNodeIds.first; 
    if (_nodes.containsKey(id)) _clipboardData = jsonEncode(_nodes[id]!.toJson()); 
  }
  
  void paste() { 
    if (_clipboardData == null) return; 
    recordUndo(); 
    try { 
      final data = jsonDecode(_clipboardData!); 
      final newId = const Uuid().v4(); 
      final newPos = Offset(data['dx'] + kNodeWidth + 50, data['dy']); 
      List<String> nextIds = []; 
      if (data['next_ids'] != null) { 
        for (var id in List<String>.from(data['next_ids'])) { 
          if (_nodes[id]?.type != NodeType.output && _nodes[id]?.type != NodeType.wikiWriter && _nodes[id]?.type != NodeType.council && _nodes[id]?.type != NodeType.researchParty) nextIds.add(id); 
        } 
      } 
      final newNode = StoryNode.fromJson(data)..position = newPos..nextNodeIds = nextIds; 
      _nodes[newId] = newNode; 
      _selectedNodeIds = {newId}; 
      recalculateSequence(); 
      notifyListeners(); 
    } catch (e) { debugPrint("Paste Error: $e"); } 
  }

  // --- DAG (DIRECTED ACYCLIC GRAPH) LOGIC ---

  void recalculateSequence() {
    _nodeSequence.clear(); 
    _activePathIds.clear();
    List<StoryNode> targetNodes = _nodes.values.where((n) => 
      n.type == NodeType.output || 
      n.type == NodeType.chat || 
      n.type == NodeType.study || 
      n.type == NodeType.summarize ||
      n.type == NodeType.wikiWriter ||
      n.type == NodeType.council ||
      n.type == NodeType.researchParty
    ).toList();
    
    if (targetNodes.isEmpty) return;

    Map<String, String> parents = {};
    for (var node in _nodes.values) { 
      for (var childId in node.nextNodeIds) { 
        if (!parents.containsKey(childId) || node.nextNodeIds.indexOf(childId) == 0) parents[childId] = node.id; 
      } 
    }

    for (var target in targetNodes) {
      String? curr = target.id;
      List<String> path = [];
      int safe = 0;
      while (curr != null && safe < 1000) { 
        path.add(curr); 
        _activePathIds.add(curr); 
        curr = parents[curr]; 
        safe++; 
      }
      path = path.reversed.toList();
      for (int i = 0; i < path.length; i++) { 
        if (_nodes[path[i]]?.type == NodeType.scene) _nodeSequence[path[i]] = i + 1; 
      }
    }
  }

  List<StoryNode> getCompiledNodes([String? targetId]) {
    String? curr = targetId ?? _previewNodeId;
    if (curr == null) { 
      try { 
        curr = _nodes.values.firstWhere((n) => 
          n.type == NodeType.output || 
          n.type == NodeType.chat || 
          n.type == NodeType.study || 
          n.type == NodeType.summarize ||
          n.type == NodeType.wikiWriter ||
          n.type == NodeType.council ||
          n.type == NodeType.researchParty
        ).id; 
      } 
      catch (_) { return []; } 
    }
    
    Map<String, String> parents = {};
    for (var n in _nodes.values) { 
      for (var childId in n.nextNodeIds) { 
        if (!parents.containsKey(childId) || n.nextNodeIds.indexOf(childId) == 0) parents[childId] = n.id; 
      } 
    }
    
    List<StoryNode> path = [];
    int safety = 0;
    while (curr != null && safety < 1000) { 
      if (_nodes[curr] != null) path.add(_nodes[curr]!); 
      curr = parents[curr]; 
      safety++; 
    }
    return path.reversed.toList();
  }

  String getCompiledRawText(List<StoryNode> nodesToCompile) {
    StringBuffer buffer = StringBuffer();
    for (var node in nodesToCompile) {
      if (node.type != NodeType.scene) continue; 
      buffer.writeln(node.title.toUpperCase()); 
      buffer.writeln(node.content); 
      buffer.writeln("\n---\n"); 
    }
    return buffer.toString().trim();
  }

  void promoteOutputToScratchpad(String outputNodeId) {
    final outNode = _nodes[outputNodeId];
    if (outNode == null || outNode.ollamaResult.isEmpty) return;
    recordUndo();
    final newId = const Uuid().v4();
    _nodes[newId] = StoryNode(id: newId, type: NodeType.scene, position: outNode.position + const Offset(kNodeWidth + 50, 0), title: "AI Draft (${DateTime.now().hour}:${DateTime.now().minute})", content: outNode.ollamaResult);
    outNode.nextNodeIds = [newId]; 
    _selectedNodeIds = {newId}; 
    recalculateSequence(); 
    notifyListeners();
  }

  // --- NODE PROPERTY UPDATERS ---

  void updateNodeContent(String id, String content) { if (_nodes.containsKey(id) && _nodes[id]!.content != content) { requestUndoSnapshot(); _nodes[id]!.content = content; } }
  void updateNodeTitle(String id, String title) { if (_nodes.containsKey(id) && _nodes[id]!.title != title) { requestUndoSnapshot(); _nodes[id]!.title = title; notifyListeners(); } }
  void updateNodeAlignment(String id, TextAlign align) { if (_nodes.containsKey(id)) { requestUndoSnapshot(); _nodes[id]!.textAlign = align; notifyListeners(); } }
  void updateNodeFont(String id, String font) { if (_nodes.containsKey(id)) { requestUndoSnapshot(); _nodes[id]!.fontFamily = font; notifyListeners(); } }
  void updateOllamaPrompt(String id, String prompt) { if (_nodes.containsKey(id)) { requestUndoSnapshot(); _nodes[id]!.ollamaPrompt = prompt; } }
  void toggleOllamaBacktalk(String id, bool value) { if (_nodes.containsKey(id)) { requestUndoSnapshot(); _nodes[id]!.ollamaNoBacktalk = value; notifyListeners(); } }
  void toggleAutonomousResearch(String id, bool value) { if (_nodes.containsKey(id)) { requestUndoSnapshot(); _nodes[id]!.enableAutonomousResearch = value; notifyListeners(); } }
  void addPillToNode(String nodeId, RedleafPill pill) { if (_nodes.containsKey(nodeId)) { requestUndoSnapshot(); _nodes[nodeId]!.redleafPills.add(pill); notifyListeners(); } }
  void removePill(String nodeId, String pillId) { if (_nodes.containsKey(nodeId)) { requestUndoSnapshot(); _nodes[nodeId]!.redleafPills.removeWhere((p) => p.id == pillId); notifyListeners(); } }
  
  void updateSearchLimit(String id, int limit) {
    if (_nodes.containsKey(id)) {
      requestUndoSnapshot();
      _nodes[id]!.searchLimit = limit;
      notifyListeners();
    }
  }

  void togglePinnedSearchResult(String id, Map<String, dynamic> result) {
    if (_nodes.containsKey(id)) {
      requestUndoSnapshot();
      final node = _nodes[id]!;
      final existingIndex = node.pinnedSearchResults.indexWhere((r) => r['doc_id'] == result['doc_id'] && r['page_number'] == result['page_number']);
      if (existingIndex >= 0) node.pinnedSearchResults.removeAt(existingIndex);
      else node.pinnedSearchResults.add(result);
      notifyListeners();
    }
  }
  
  void clearPinnedSearchResults(String id) {
    if (_nodes.containsKey(id)) {
      requestUndoSnapshot();
      _nodes[id]!.pinnedSearchResults.clear();
      notifyListeners();
    }
  }

  void clearChatHistory(String id) {
    if (_nodes.containsKey(id)) {
      requestUndoSnapshot();
      _nodes[id]!.chatHistory.clear();
      notifyListeners();
    }
  }

  void appendChatMessage(String id, String role, String content) {
    if (_nodes.containsKey(id)) {
      requestUndoSnapshot();
      _nodes[id]!.chatHistory.add({"role": role, "content": content});
      notifyListeners();
    }
  }

  void streamToLastChatMessage(String id, String chunk) {
    if (_nodes.containsKey(id) && _nodes[id]!.chatHistory.isNotEmpty) {
      _nodes[id]!.chatHistory.last["content"] = (_nodes[id]!.chatHistory.last["content"] ?? "") + chunk;
      notifyListeners();
    }
  }
  
  void updateCouncilAgentCount(String id, int count) {
    if (_nodes.containsKey(id)) {
      requestUndoSnapshot();
      _nodes[id]!.councilAgentCount = count;
      notifyListeners();
    }
  }
  
  void toggleCouncilAuditHistory(String id, bool value) {
    if (_nodes.containsKey(id)) {
      requestUndoSnapshot();
      _nodes[id]!.councilAuditHistory = value;
      notifyListeners();
    }
  }

  // --- NEW: Interactive / Directive state updaters ---
  void updateCouncilDirection(String id, String direction) {
    if (_nodes.containsKey(id)) {
      requestUndoSnapshot();
      _nodes[id]!.councilDirection = direction;
      notifyListeners();
    }
  }

  void toggleCouncilInteractive(String id, bool value) {
    if (_nodes.containsKey(id)) {
      requestUndoSnapshot();
      _nodes[id]!.councilInteractive = value;
      notifyListeners();
    }
  }

  void setNodeOllamaResult(String id, String result) {
    if (_nodes.containsKey(id)) {
      requestUndoSnapshot();
      _nodes[id]!.ollamaResult = result;
      notifyListeners();
    }
  }
}