// --- File: lib/ui/side_panel.dart ---
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:flutter/gestures.dart';
import 'package:url_launcher/url_launcher.dart';

import '../constants.dart';
import '../models/node_models.dart';
import '../state/network_state.dart';
import '../state/graph_state.dart';

// --- IMPORTS FOR EXTRACTED PANELS ---
import 'panels/chat_node_panel.dart';
import 'panels/study_node_panel.dart';
import 'panels/summarize_node_panel.dart';
import 'panels/wiki_writer_node_panel.dart';
import 'panels/wiki_reader_node_panel.dart'; 
import 'panels/council_node_panel.dart';
import 'panels/output_node_panel.dart';
import 'panels/global_search_node_panel.dart';
import 'panels/catalog_node_panel.dart';
import 'panels/intersection_node_panel.dart';
import 'panels/relationship_node_panel.dart';
import 'panels/briefing_node_panel.dart';
import 'panels/persona_node_panel.dart';
import 'panels/research_party_node_panel.dart'; 
import 'panels/document_node_panel.dart'; // <-- NEW PANEL ADDED

// EXPORT common UI elements so previously extracted panels don't break
export 'dialogs/entity_search_dialog.dart';
export 'panels/preview_panel.dart';

import 'dialogs/entity_search_dialog.dart';
import 'panels/preview_panel.dart';

// --- RICH TEXT PARSER FOR THOUGHTS, CITATIONS, AND WIKI LINKS ---
TextSpan parseRichText(String text, String baseUrl, {GraphState? graphState, NetworkState? networkState, BuildContext? context, String? currentNodeId}) {
  final List<TextSpan> spans = [];
  final lines = text.split('\n');

  for (int i = 0; i < lines.length; i++) {
    final line = lines[i];
    final isLastLine = i == lines.length - 1;
    final lineText = line + (isLastLine ? '' : '\n');

    if (line.trim().startsWith('>')) {
      spans.add(TextSpan(
        text: lineText,
        style: const TextStyle(
          color: Colors.white38,
          fontStyle: FontStyle.italic,
          fontSize: 13,
        ),
      ));
    } else {
      spans.add(_parseLinksInline(lineText, baseUrl, graphState, networkState, context, currentNodeId));
    }
  }
  return TextSpan(children: spans);
}

TextSpan _parseLinksInline(String text, String baseUrl, GraphState? graphState, NetworkState? networkState, BuildContext? context, String? currentNodeId) {
  final RegExp docExp = RegExp(r'\[(?:Doc|Document)[:.]?\s*(\d+)[^\]]*\]', caseSensitive: false);
  final RegExp wikiExp = RegExp(r'\[\[(.*?)\]\]');

  final docMatches = docExp.allMatches(text).toList();
  final wikiMatches = wikiExp.allMatches(text).toList();

  final List<Map<String, dynamic>> allMatches = [];
  for (var m in docMatches) allMatches.add({'type': 'doc', 'match': m, 'start': m.start, 'end': m.end});
  for (var m in wikiMatches) allMatches.add({'type': 'wiki', 'match': m, 'start': m.start, 'end': m.end});
  
  allMatches.sort((a, b) => a['start'].compareTo(b['start']));

  if (allMatches.isEmpty) return TextSpan(text: text);

  int currentIndex = 0;
  final List<InlineSpan> spans = [];

  for (final matchData in allMatches) {
    final match = matchData['match'] as RegExpMatch;
    if (match.start < currentIndex) continue;

    if (match.start > currentIndex) {
      spans.add(TextSpan(text: text.substring(currentIndex, match.start)));
    }
    
    final String matchText = match.group(0)!;

    if (matchData['type'] == 'doc') {
      final String docIdStr = match.group(1)!;
      spans.add(
        TextSpan(
          text: matchText,
          style: const TextStyle(color: Colors.lightBlueAccent, decoration: TextDecoration.underline, fontWeight: FontWeight.bold),
          recognizer: TapGestureRecognizer()
            ..onTap = () async {
              final url = Uri.parse('$baseUrl/document/$docIdStr');
              if (await canLaunchUrl(url)) await launchUrl(url);
            },
        ),
      );
    } else if (matchData['type'] == 'wiki') {
      final String wikiTarget = match.group(1)!;
      spans.add(
        TextSpan(
          text: matchText,
          style: const TextStyle(color: Colors.amberAccent, decoration: TextDecoration.underline, fontWeight: FontWeight.bold),
          recognizer: TapGestureRecognizer()
            ..onTap = () async {
              if (graphState != null && networkState != null && context != null) {
                final content = await graphState.readWikiPage(wikiTarget, networkState);
                if (currentNodeId != null && graphState.nodes.containsKey(currentNodeId)) {
                   final node = graphState.nodes[currentNodeId]!;
                   if (node.type == NodeType.wikiWriter || node.type == NodeType.council) {
                      graphState.setNodeOllamaResult(currentNodeId, "=== PREVIEWING LINKED PAGE: $wikiTarget.md ===\n\n$content");
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Loaded [[$wikiTarget]] into preview.")));
                      return;
                   }
                }
                graphState.addNode(const Offset(kWorldSize / 2, kWorldSize / 2), NodeType.wikiReader);
                final newNodeId = graphState.selectedNodeIds.first;
                graphState.updateWikiTitle(newNodeId, wikiTarget);
                graphState.updateNodeTitle(newNodeId, "Read: $wikiTarget");
                graphState.setNodeOllamaResult(newNodeId, content);
              }
            },
        ),
      );
    }
    currentIndex = match.end;
  }

  if (currentIndex < text.length) spans.add(TextSpan(text: text.substring(currentIndex)));
  return TextSpan(children: spans);
}

class SidePanel extends StatefulWidget {
  const SidePanel({super.key});
  @override
  State<SidePanel> createState() => _SidePanelState();
}

class _SidePanelState extends State<SidePanel> {
  late TextEditingController _titleCtrl;
  late TextEditingController _contentCtrl;
  String? _editingId;

  @override
  void initState() {
    super.initState();
    _titleCtrl = TextEditingController();
    _contentCtrl = TextEditingController(); 
  }

  @override
  Widget build(BuildContext context) {
    final graphState = context.watch<GraphState>();
    final networkState = context.read<NetworkState>(); 
    
    final nodeId = graphState.selectedNodeIds.isNotEmpty ? graphState.selectedNodeIds.first : null;
    final node = nodeId != null ? graphState.nodes[nodeId] : null;

    if (graphState.previewNodeId != null && graphState.previewNodeId != nodeId) {
      return Container(width: double.infinity, color: const Color(0xFF1A1A1A), child: const PreviewPanel());
    }
    
    if (node == null) return Container(width: double.infinity, color: const Color(0xFF1A1A1A), child: const Center(child: Text("Select a Node", style: TextStyle(color: Colors.grey))));
    
    if (_editingId != nodeId) {
      _editingId = nodeId;
      _titleCtrl.text = node.title; _contentCtrl.text = node.content;
    }

    // Routing for Compact Tool Nodes
    if (node.type == NodeType.output) return Container(width: double.infinity, color: const Color(0xFF1A1A1A), child: OutputNodePanel(nodeId: node.id));
    if (node.type == NodeType.search) return GlobalSearchNodePanel(nodeId: node.id);
    if (node.type == NodeType.document) return DocumentNodePanel(nodeId: node.id); // <-- NEW ROUTING
    if (node.type == NodeType.relationship) return RelationshipNodePanel(nodeId: node.id);
    if (node.type == NodeType.catalog) return CatalogNodePanel(nodeId: node.id);
    if (node.type == NodeType.intersection) return IntersectionNodePanel(nodeId: node.id);
    if (node.type == NodeType.chat) return Container(width: double.infinity, color: const Color(0xFF1A1A1A), child: ChatNodePanel(nodeId: node.id)); 
    if (node.type == NodeType.briefing) return Container(width: double.infinity, color: const Color(0xFF1A1A1A), child: BriefingNodePanel(nodeId: node.id));
    if (node.type == NodeType.study) return Container(width: double.infinity, color: const Color(0xFF1A1A1A), child: StudyNodePanel(nodeId: node.id)); 
    if (node.type == NodeType.summarize) return Container(width: double.infinity, color: const Color(0xFF1A1A1A), child: SummarizeNodePanel(nodeId: node.id)); 
    if (node.type == NodeType.persona) return Container(width: double.infinity, color: const Color(0xFF1A1A1A), child: PersonaNodePanel(nodeId: node.id)); 
    if (node.type == NodeType.wikiReader) return Container(width: double.infinity, color: const Color(0xFF1A1A1A), child: WikiReaderNodePanel(nodeId: node.id)); 
    if (node.type == NodeType.wikiWriter) return Container(width: double.infinity, color: const Color(0xFF1A1A1A), child: WikiWriterNodePanel(nodeId: node.id)); 
    if (node.type == NodeType.council) return Container(width: double.infinity, color: const Color(0xFF1A1A1A), child: CouncilNodePanel(nodeId: node.id)); 
    if (node.type == NodeType.researchParty) return Container(width: double.infinity, color: const Color(0xFF1A1A1A), child: ResearchPartyNodePanel(nodeId: node.id));

    // --- Scratchpad Node (Dual-Tab Read/Edit interface) ---
    return DefaultTabController(
      length: 2,
      child: Container(
        width: double.infinity, color: const Color(0xFF1A1A1A),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const TabBar(
              indicatorColor: Colors.white,
              labelColor: Colors.white,
              unselectedLabelColor: Colors.white54,
              tabs: [
                Tab(icon: Icon(Icons.edit, size: 18), text: "Edit Note"),
                Tab(icon: Icon(Icons.visibility, size: 18), text: "Read (Links Active)"),
              ],
            ),
            Expanded(
              child: TabBarView(
                children: [
                  // --- TAB 1: EDIT MODE ---
                  Padding(
                    padding: const EdgeInsets.all(20.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text("PROPERTIES", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
                        const SizedBox(height: 10),
                        TextField(
                          controller: _titleCtrl, 
                          decoration: const InputDecoration(labelText: "Node Title", filled: true, fillColor: Color(0xFF222222)), 
                          onChanged: (v) => graphState.updateNodeTitle(node.id, v)
                        ),
                        
                        const SizedBox(height: 20),
                        const Text("Redleaf Context Cues", style: TextStyle(color: Colors.white54, fontSize: 12)),
                        const SizedBox(height: 5),
                        Wrap(
                          spacing: 8, runSpacing: 8,
                          children: [
                            ...node.redleafPills.map((p) => Chip(
                              backgroundColor: kAccentColor.withOpacity(0.2), side: const BorderSide(color: kAccentColor),
                              label: Text(p.text, style: const TextStyle(color: Colors.white, fontSize: 12)),
                              onDeleted: () => graphState.removePill(node.id, p.id),
                            )),
                            ActionChip(
                              backgroundColor: Colors.transparent, side: const BorderSide(color: Colors.white54, style: BorderStyle.solid),
                              label: const Text("+ Add Entity"),
                              onPressed: () {
                                if (!networkState.redleafService.isLoggedIn) { 
                                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Please configure your Redleaf credentials in Settings first."))); 
                                } else { 
                                  _showAddPillDialog(context, node.id); 
                                }
                              },
                            ),
                          ],
                        ),
                        
                        const SizedBox(height: 20),
                        const Text("Prompt / Content", style: TextStyle(color: Colors.white54, fontSize: 12)),
                        const SizedBox(height: 5),
                        Expanded(
                          child: TextField(
                            controller: _contentCtrl, 
                            maxLines: null, expands: true, 
                            textAlignVertical: TextAlignVertical.top,
                            decoration: const InputDecoration(
                              filled: true, fillColor: Color(0xFF222222), 
                              border: OutlineInputBorder(borderSide: BorderSide.none), 
                              hintText: "Write prompt instructions or paste notes here..."
                            ),
                            onChanged: (v) => graphState.updateNodeContent(node.id, v),
                            style: const TextStyle(fontSize: 14, color: Colors.white, height: 1.4),
                          ),
                        ),
                      ],
                    ),
                  ),

                  // --- TAB 2: READ MODE ---
                  Padding(
                    padding: const EdgeInsets.all(20.0),
                    child: Container(
                      width: double.infinity, padding: const EdgeInsets.all(15),
                      decoration: BoxDecoration(color: const Color(0xFF111111), borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.white12)),
                      child: SingleChildScrollView(
                        child: SelectableText.rich(
                          parseRichText(
                            node.content.isEmpty ? "Nothing to read yet. Type in the Edit tab." : node.content, 
                            networkState.redleafService.apiUrl,
                            graphState: graphState,
                            networkState: networkState,
                            context: context,
                            currentNodeId: node.id
                          ),
                          style: const TextStyle(color: Colors.white, height: 1.5, fontSize: 14),
                        ),
                      ),
                    ),
                  )
                ],
              ),
            )
          ],
        ),
      ),
    );
  }

  void _showAddPillDialog(BuildContext context, String nodeId) {
    showDialog(
      context: context,
      builder: (ctx) => EntitySearchDialog(nodeId: nodeId)
    );
  }
}