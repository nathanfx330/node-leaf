// --- File: lib/models/node_models.dart ---
import 'package:flutter/material.dart';
import '../constants.dart';

class RedleafPill {
  final String id;
  final int entityId;
  final String text;
  final String label;
  
  RedleafPill({required this.id, required this.entityId, required this.text, required this.label});
  
  Map<String, dynamic> toJson() => {'id': id, 'entityId': entityId, 'text': text, 'label': label};
  factory RedleafPill.fromJson(Map<String, dynamic> json) => RedleafPill(
    id: json['id'], entityId: json['entityId'], text: json['text'], label: json['label']
  );
}

class StoryNode {
  final String id;
  final NodeType type;
  String title;
  String content;
  Offset position;
  List<String> nextNodeIds;
  TextAlign textAlign;
  String fontFamily;
  
  List<RedleafPill> redleafPills; 
  
  String ollamaPrompt;
  String ollamaResult;
  bool ollamaNoBacktalk; 
  bool enableAutonomousResearch; 
  List<Map<String, String>> chatHistory; 
  
  // --- Global Search Configurations ---
  int searchLimit;
  List<Map<String, dynamic>> pinnedSearchResults;

  // --- NEW: Agentic Wiki Configuration ---
  String wikiTitle;
  
  // --- NEW: Council Configuration ---
  int councilAgentCount;
  bool councilAuditHistory; // <-- ADDED

  StoryNode({
    required this.id, required this.position, this.type = NodeType.scene,
    this.title = "Untitled", this.content = "", this.textAlign = TextAlign.left,
    this.fontFamily = "Modern", List<String>? nextNodeIds,
    List<RedleafPill>? redleafPills,
    this.ollamaPrompt = "", this.ollamaResult = "", this.ollamaNoBacktalk = true,
    this.enableAutonomousResearch = true,
    List<Map<String, String>>? chatHistory, 
    this.searchLimit = 5, 
    List<Map<String, dynamic>>? pinnedSearchResults, 
    this.wikiTitle = "", 
    this.councilAgentCount = 3, 
    this.councilAuditHistory = false, // <-- ADDED
  }) : nextNodeIds = nextNodeIds ?? [],
       redleafPills = redleafPills ?? [],
       chatHistory = chatHistory ?? [],
       pinnedSearchResults = pinnedSearchResults ?? []; 

  // True for tools/actions, False for Scratchpad (which shows text preview)
  bool get isCompactToolNode => type != NodeType.scene;

  // Dynamically calculate height based on node type
  double get currentHeight => isCompactToolNode ? kPillHeight : kNodeHeight;

  Offset get inputPortLocal => const Offset(kNodeWidth / 2, 0);
  Offset get outputPortLocal => Offset(kNodeWidth / 2, currentHeight);
  Offset get inputPortGlobal => position + inputPortLocal;
  Offset get outputPortGlobal => position + outputPortLocal;
  Rect get rect => position & Size(kNodeWidth, currentHeight);

  Map<String, dynamic> toJson() => {
    'id': id, 'type': type.toString(), 'title': title, 'content': content,
    'align': textAlign.toString(), 'font': fontFamily,
    'dx': position.dx, 'dy': position.dy, 'next_ids': nextNodeIds,
    'pills': redleafPills.map((p) => p.toJson()).toList(), 
    'ollamaPrompt': ollamaPrompt, 'ollamaResult': ollamaResult,
    'ollamaNoBacktalk': ollamaNoBacktalk,
    'enableAutonomousResearch': enableAutonomousResearch,
    'chatHistory': chatHistory, 
    'searchLimit': searchLimit, 
    'pinnedSearchResults': pinnedSearchResults, 
    'wikiTitle': wikiTitle, 
    'councilAgentCount': councilAgentCount,
    'councilAuditHistory': councilAuditHistory, // <-- ADDED
  };

  factory StoryNode.fromJson(Map<String, dynamic> json) {
    NodeType parsedType = NodeType.scene;
    if (json['type'] == 'NodeType.output') parsedType = NodeType.output;
    if (json['type'] == 'NodeType.search') parsedType = NodeType.search;
    if (json['type'] == 'NodeType.document') parsedType = NodeType.document;
    if (json['type'] == 'NodeType.relationship') parsedType = NodeType.relationship;
    if (json['type'] == 'NodeType.catalog') parsedType = NodeType.catalog;
    if (json['type'] == 'NodeType.intersection') parsedType = NodeType.intersection;
    if (json['type'] == 'NodeType.chat') parsedType = NodeType.chat; 
    if (json['type'] == 'NodeType.briefing') parsedType = NodeType.briefing; 
    if (json['type'] == 'NodeType.study') parsedType = NodeType.study;
    if (json['type'] == 'NodeType.persona') parsedType = NodeType.persona;
    if (json['type'] == 'NodeType.summarize') parsedType = NodeType.summarize; 
    if (json['type'] == 'NodeType.wikiReader') parsedType = NodeType.wikiReader; 
    if (json['type'] == 'NodeType.wikiWriter') parsedType = NodeType.wikiWriter; 
    if (json['type'] == 'NodeType.council') parsedType = NodeType.council; 
    if (json['type'] == 'NodeType.researchParty') parsedType = NodeType.researchParty; // <-- ADDED

    return StoryNode(
      id: json['id'],
      type: parsedType,
      title: json['title'], content: json['content'],
      textAlign: _stringToTextAlign(json['align']),
      fontFamily: json['font'] ?? "Modern", position: Offset(json['dx'], json['dy']),
      nextNodeIds: List<String>.from(json['next_ids'] ?? []),
      redleafPills: (json['pills'] as List?)?.map((p) => RedleafPill.fromJson(p)).toList() ?? [], 
      ollamaPrompt: json['ollamaPrompt'] ?? "",
      ollamaResult: json['ollamaResult'] ?? "",
      ollamaNoBacktalk: json['ollamaNoBacktalk'] ?? true, 
      enableAutonomousResearch: json['enableAutonomousResearch'] ?? true,
      chatHistory: (json['chatHistory'] as List?)
          ?.map((e) => Map<String, String>.from(e as Map))
          .toList() ?? [], 
      searchLimit: json['searchLimit'] ?? 5, 
      pinnedSearchResults: (json['pinnedSearchResults'] as List?)
          ?.map((e) => Map<String, dynamic>.from(e as Map))
          .toList() ?? [], 
      wikiTitle: json['wikiTitle'] ?? "", 
      councilAgentCount: json['councilAgentCount'] ?? 3,
      councilAuditHistory: json['councilAuditHistory'] ?? false, // <-- ADDED
    );
  }

  static TextAlign _stringToTextAlign(String? str) {
    if (str == 'TextAlign.center') return TextAlign.center;
    if (str == 'TextAlign.right') return TextAlign.right;
    if (str == 'TextAlign.justify') return TextAlign.justify;
    return TextAlign.left;
  }
}