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
import 'panels/wiki_reader_node_panel.dart'; // <-- THIS WAS MISSING
import 'panels/council_node_panel.dart';
import 'panels/output_node_panel.dart';
import 'panels/global_search_node_panel.dart';
import 'panels/catalog_node_panel.dart';
import 'panels/intersection_node_panel.dart';
import 'panels/relationship_node_panel.dart';
import 'panels/briefing_node_panel.dart';
import 'panels/persona_node_panel.dart';

// EXPORT common UI elements so previously extracted panels don't break
export 'dialogs/entity_search_dialog.dart';
export 'panels/preview_panel.dart';

// We import these here so the SidePanel widget itself can still use them
import 'dialogs/entity_search_dialog.dart';
import 'panels/preview_panel.dart';

// --- RICH TEXT PARSER FOR THOUGHTS & CITATIONS ---
TextSpan parseRichText(String text, String baseUrl) {
  final List<TextSpan> spans = [];
  final lines = text.split('\n');

  for (int i = 0; i < lines.length; i++) {
    final line = lines[i];
    final isLastLine = i == lines.length - 1;
    final lineText = line + (isLastLine ? '' : '\n');

    if (line.trim().startsWith('>')) {
      // Style internal agent thoughts / actions (grey, italic, slightly smaller)
      spans.add(TextSpan(
        text: lineText,
        style: const TextStyle(
          color: Colors.white38,
          fontStyle: FontStyle.italic,
          fontSize: 13,
        ),
      ));
    } else {
      // Parse citations for normal lines
      spans.add(_parseCitationsInline(lineText, baseUrl));
    }
  }
  return TextSpan(children: spans);
}

TextSpan _parseCitationsInline(String text, String baseUrl) {
  // Matches: [Doc 12], [Document 12], [Doc: 12], [Doc. 12/p. 4], etc.
  final RegExp exp = RegExp(r'\[(?:Doc|Document)[:.]?\s*(\d+)[^\]]*\]', caseSensitive: false);
  final Iterable<RegExpMatch> matches = exp.allMatches(text);

  if (matches.isEmpty) {
    return TextSpan(text: text);
  }

  int currentIndex = 0;
  final List<InlineSpan> spans = [];

  for (final match in matches) {
    if (match.start > currentIndex) {
      spans.add(TextSpan(text: text.substring(currentIndex, match.start)));
    }
    
    final String docIdStr = match.group(1)!;
    final String matchText = match.group(0)!;

    spans.add(
      TextSpan(
        text: matchText,
        style: const TextStyle(
          color: Colors.lightBlueAccent, 
          decoration: TextDecoration.underline,
          fontWeight: FontWeight.bold,
        ),
        recognizer: TapGestureRecognizer()
          ..onTap = () async {
            final url = Uri.parse('$baseUrl/document/$docIdStr');
            if (await canLaunchUrl(url)) {
              await launchUrl(url);
            } else {
              debugPrint('Could not launch $url');
            }
          },
      ),
    );
    currentIndex = match.end;
  }

  if (currentIndex < text.length) {
    spans.add(TextSpan(text: text.substring(currentIndex)));
  }

  return TextSpan(children: spans);
}
// -------------------------------------------

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
    if (node.type == NodeType.document) return _buildDocumentPanel(context, graphState, node);
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

    // Default: Scratchpad / Prompt Node
    return Container(
      width: double.infinity, color: const Color(0xFF1A1A1A), padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children:[
          const Text("PROPERTIES", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
          const SizedBox(height: 20),
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
    );
  }

  Widget _buildDocumentPanel(BuildContext context, GraphState graphState, StoryNode node) {
    return Container(
      color: const Color(0xFF1A1A1A), padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text("REDLEAF DOCUMENT READER", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, letterSpacing: 1.5)),
          const SizedBox(height: 20),
          const Text("Enter a Document ID (e.g. 12) or specific pages (e.g. id:12 + page:1-3):", style: TextStyle(color: Colors.white54, fontSize: 12)), 
          const SizedBox(height: 5),
          TextField(
            controller: _contentCtrl, 
            decoration: const InputDecoration(filled: true, fillColor: Color(0xFF222222), hintText: "e.g. 12"),
            onChanged: (v) => graphState.updateNodeContent(node.id, v),
          ),
          const SizedBox(height: 20),
          const Text("How this works:", style: TextStyle(color: Colors.white70, fontWeight: FontWeight.bold)),
          const SizedBox(height: 5),
          const Text(
            "When the graph compiles, this node will download the raw extracted text of the specific Document ID from your Redleaf database and inject it into the LLM context window.\n\n(Note: Very large documents will be automatically truncated to fit into the AI's memory).",
            style: TextStyle(color: Colors.grey, fontSize: 12),
          ),
        ]
      )
    );
  }
  
  void _showAddPillDialog(BuildContext context, String nodeId) {
    showDialog(
      context: context,
      builder: (ctx) => EntitySearchDialog(nodeId: nodeId)
    );
  }
}