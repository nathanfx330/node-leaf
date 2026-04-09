// --- File: lib/ui/side_panel.dart ---
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';
import 'package:flutter/gestures.dart';
import 'package:url_launcher/url_launcher.dart';

import '../constants.dart';
import '../models/node_models.dart';
import '../state/network_state.dart';
import '../state/graph_state.dart';
import '../state/canvas_state.dart';

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

// ====================================================================
// PANELS FOR GRAPH / CATALOG / INTERSECTION / BRIEFING / PERSONA
// ====================================================================

class PersonaNodePanel extends StatefulWidget {
  final String nodeId;
  const PersonaNodePanel({super.key, required this.nodeId});

  @override
  State<PersonaNodePanel> createState() => _PersonaNodePanelState();
}

class _PersonaNodePanelState extends State<PersonaNodePanel> {
  late TextEditingController _ctrl;

  @override
  void initState() {
    super.initState();
    final graphState = context.read<GraphState>();
    _ctrl = TextEditingController(text: graphState.nodes[widget.nodeId]?.content ?? "");
  }

  @override
  void didUpdateWidget(covariant PersonaNodePanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.nodeId != widget.nodeId) {
      final graphState = context.read<GraphState>();
      _ctrl.text = graphState.nodes[widget.nodeId]?.content ?? "";
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final graphState = context.watch<GraphState>();
    final node = graphState.nodes[widget.nodeId];
    if (node == null) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.all(20.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.theater_comedy, color: Colors.blueGrey, size: 20),
              SizedBox(width: 10),
              Text("AGENT PERSONA", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white, letterSpacing: 1.5)),
            ],
          ),
          const SizedBox(height: 10),
          const Text("Define the role, tone, and perspective the AI should adopt when generating its final response.", style: TextStyle(color: Colors.white54, fontSize: 12)),
          const SizedBox(height: 20),

          const Text("Persona Description:", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white70)),
          const SizedBox(height: 5),
          Expanded(
            child: TextField(
              controller: _ctrl,
              maxLines: null, expands: true, textAlignVertical: TextAlignVertical.top,
              decoration: const InputDecoration(
                filled: true, fillColor: Color(0xFF222222), 
                border: OutlineInputBorder(borderSide: BorderSide.none), 
                hintText: "E.g., You are a skeptical forensic accountant. You look for inconsistencies in financial data and write in a dry, highly technical tone."
              ),
              onChanged: (val) => graphState.updateNodeContent(widget.nodeId, val),
            ),
          ),
        ],
      ),
    );
  }
}

class BriefingNodePanel extends StatefulWidget {
  final String nodeId;
  const BriefingNodePanel({super.key, required this.nodeId});

  @override
  State<BriefingNodePanel> createState() => _BriefingNodePanelState();
}

class _BriefingNodePanelState extends State<BriefingNodePanel> {
  String _preview = "";
  bool _isLoading = false;
  late TextEditingController _ctrl;

  @override
  void initState() {
    super.initState();
    final graphState = context.read<GraphState>();
    _ctrl = TextEditingController(text: graphState.nodes[widget.nodeId]?.content ?? "");
  }

  @override
  void didUpdateWidget(covariant BriefingNodePanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.nodeId != widget.nodeId) {
      final graphState = context.read<GraphState>();
      _ctrl.text = graphState.nodes[widget.nodeId]?.content ?? "";
      _preview = "";
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _fetchPreview() async {
    setState(() { _isLoading = true; });
    final networkState = context.read<NetworkState>();
    final text = await networkState.redleafService.fetchSystemBriefing();
    
    String combinedPreview = text;
    if (_ctrl.text.trim().isNotEmpty) {
      combinedPreview += "\n\n[USER OVERRIDE / MANUAL CONTEXT]:\n${_ctrl.text.trim()}";
    }

    if (mounted) setState(() { _preview = combinedPreview; _isLoading = false; });
  }

  @override
  Widget build(BuildContext context) {
    final graphState = context.watch<GraphState>();
    final node = graphState.nodes[widget.nodeId];
    if (node == null) return const SizedBox.shrink();

    return Container(
      color: const Color(0xFF1A1A1A), padding: const EdgeInsets.all(20),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text("REDLEAF SYSTEM BRIEFING", style: TextStyle(color: Colors.amberAccent, fontWeight: FontWeight.bold, letterSpacing: 1.5)),
        const SizedBox(height: 20),
        const Text(
          "Injects a high-level overview of the database (total documents, date ranges, prominent tags) into the AI's context.", 
          style: TextStyle(color: Colors.grey, fontSize: 13, height: 1.4)
        ),
        const SizedBox(height: 20),
        
        const Text("Manual Collection Description (Optional):", style: TextStyle(color: Colors.white70, fontSize: 12)),
        const SizedBox(height: 5),
        TextField(
          controller: _ctrl,
          maxLines: 3,
          decoration: const InputDecoration(
            filled: true, fillColor: Color(0xFF222222), 
            hintText: "e.g. This is a collection of 2016 emails regarding the energy sector.",
            border: OutlineInputBorder(borderSide: BorderSide.none)
          ),
          onChanged: (v) => graphState.updateNodeContent(widget.nodeId, v),
        ),

        const SizedBox(height: 20),
        ElevatedButton.icon(
          style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF333333), foregroundColor: Colors.white),
          icon: _isLoading ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)) : const Icon(Icons.refresh),
          label: const Text("Preview Briefing"),
          onPressed: _isLoading ? null : _fetchPreview,
        ),
        if (_preview.isNotEmpty) ...[
          const SizedBox(height: 20),
          const Text("Preview:", style: TextStyle(color: Colors.white70, fontWeight: FontWeight.bold)),
          const SizedBox(height: 10),
          Expanded(
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: const Color(0xFF222222), borderRadius: BorderRadius.circular(8)),
              child: SingleChildScrollView(
                child: Text(_preview, style: const TextStyle(color: Colors.white70, fontSize: 13, fontFamily: 'monospace')),
              ),
            ),
          )
        ]
      ])
    );
  }
}

class RelationshipNodePanel extends StatelessWidget {
  final String nodeId;
  const RelationshipNodePanel({super.key, required this.nodeId});

  @override 
  Widget build(BuildContext context) {
    final graphState = context.watch<GraphState>();
    final networkState = context.read<NetworkState>();
    final node = graphState.nodes[nodeId];
    if (node == null) return const SizedBox.shrink();

    return Container(
      color: const Color(0xFF1A1A1A), padding: const EdgeInsets.all(20),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text("REDLEAF RELATIONSHIP GRAPH", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, letterSpacing: 1.5)),
        const SizedBox(height: 20),
        const Text("Select Entity:", style: TextStyle(color: Colors.white54, fontSize: 12)),
        const SizedBox(height: 5),
        
        Wrap(
          spacing: 8, runSpacing: 8,
          children: [
            ...node.redleafPills.map((p) => Chip(
              backgroundColor: kAccentColor.withOpacity(0.2), side: const BorderSide(color: kAccentColor),
              label: Text(p.text, style: const TextStyle(color: Colors.white, fontSize: 12)),
              onDeleted: () => graphState.removePill(node.id, p.id),
            )),
            // Only allow 1 pill for the graph node
            if (node.redleafPills.isEmpty)
              ActionChip(
                backgroundColor: Colors.transparent, side: const BorderSide(color: Colors.white54, style: BorderStyle.solid),
                label: const Text("+ Add Entity"),
                onPressed: () {
                  if (!networkState.redleafService.isLoggedIn) { 
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Please configure your Redleaf credentials in Settings first."))); 
                  } else { 
                    showDialog(context: context, builder: (ctx) => EntitySearchDialog(nodeId: node.id)); 
                  }
                },
              ),
          ],
        ),
        const SizedBox(height: 20),
        const Text("Pulls structured connection data (Triplets) for this exact entity from the Redleaf Knowledge Graph.", style: TextStyle(color: Colors.grey, fontSize: 12))
      ])
    );
  }
}

class IntersectionNodePanel extends StatelessWidget {
  final String nodeId;
  const IntersectionNodePanel({super.key, required this.nodeId});

  @override 
  Widget build(BuildContext context) {
    final graphState = context.watch<GraphState>();
    final networkState = context.read<NetworkState>();
    final node = graphState.nodes[nodeId];
    if (node == null) return const SizedBox.shrink();

    return Container(
      color: const Color(0xFF1A1A1A), padding: const EdgeInsets.all(20),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text("REDLEAF CO-MENTION", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, letterSpacing: 1.5)),
        const SizedBox(height: 20),
        const Text("Select Entities to Intersect:", style: TextStyle(color: Colors.white54, fontSize: 12)),
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
                  showDialog(context: context, builder: (ctx) => EntitySearchDialog(nodeId: node.id)); 
                }
              },
            ),
          ],
        ),
        const SizedBox(height: 20),
        const Text("Finds specific pages across the database where ALL listed entities appear together.", style: TextStyle(color: Colors.grey, fontSize: 12))
      ])
    );
  }
}

class CatalogNodePanel extends StatefulWidget {
  final String nodeId;
  const CatalogNodePanel({super.key, required this.nodeId});
  @override 
  State<CatalogNodePanel> createState() => _CatalogNodePanelState();
}

class _CatalogNodePanelState extends State<CatalogNodePanel> {
  List<Map<String, dynamic>> _catalogs = [];
  bool _isLoading = true;

  @override 
  void initState() { 
    super.initState(); 
    _fetchCatalogs(); 
  }

  void _fetchCatalogs() async {
    final networkState = context.read<NetworkState>();
    final cats = await networkState.redleafService.fetchAllCatalogs();
    if (mounted) setState(() { _catalogs = cats; _isLoading = false; });
  }

  @override 
  Widget build(BuildContext context) {
    final graphState = context.watch<GraphState>();
    final node = graphState.nodes[widget.nodeId];
    
    return Container(
      color: const Color(0xFF1A1A1A), padding: const EdgeInsets.all(20),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text("REDLEAF CATALOG READER", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, letterSpacing: 1.5)),
        const SizedBox(height: 20),
        const Text("Select Collection:", style: TextStyle(color: Colors.white54, fontSize: 12)),
        const SizedBox(height: 5),
        if (_isLoading) const CircularProgressIndicator(color: Colors.white)
        else DropdownButton<String>(
          isExpanded: true,
          hint: const Text("Select a Catalog", style: TextStyle(color: Colors.white54)),
          value: node?.content.isEmpty == true ? null : node?.content,
          dropdownColor: const Color(0xFF333333),
          items: _catalogs.map((c) => DropdownMenuItem(value: c['id'].toString(), child: Text(c['name'], style: const TextStyle(color: Colors.white)))).toList(),
          onChanged: (v) {
            if (v != null) {
              graphState.updateNodeContent(widget.nodeId, v);
              graphState.updateNodeTitle(widget.nodeId, _catalogs.firstWhere((c) => c['id'].toString() == v)['name']);
            }
          },
        ),
        const SizedBox(height: 20),
        const Text("Extracts the context of documents in this collection for summarization tasks.", style: TextStyle(color: Colors.grey, fontSize: 12))
      ])
    );
  }
}

// ====================================================================

class GlobalSearchNodePanel extends StatefulWidget {
  final String nodeId;
  const GlobalSearchNodePanel({super.key, required this.nodeId});

  @override
  State<GlobalSearchNodePanel> createState() => _GlobalSearchNodePanelState();
}

class _GlobalSearchNodePanelState extends State<GlobalSearchNodePanel> {
  late TextEditingController _ctrl;
  late TextEditingController _limitCtrl;
  List<Map<String, dynamic>> _results = [];
  bool _isSearching = false;
  bool _hasSearched = false;

  @override
  void initState() {
    super.initState();
    final graphState = context.read<GraphState>();
    final node = graphState.nodes[widget.nodeId];
    _ctrl = TextEditingController(text: node?.content ?? "");
    _limitCtrl = TextEditingController(text: (node?.searchLimit ?? 5).toString());
    if (_ctrl.text.isNotEmpty) _performSearch();
  }

  @override
  void didUpdateWidget(covariant GlobalSearchNodePanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.nodeId != widget.nodeId) {
      final graphState = context.read<GraphState>();
      final node = graphState.nodes[widget.nodeId];
      _ctrl.text = node?.content ?? "";
      _limitCtrl.text = (node?.searchLimit ?? 5).toString();
      _results.clear();
      _hasSearched = false;
      if (_ctrl.text.isNotEmpty) _performSearch();
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _limitCtrl.dispose();
    super.dispose();
  }

  void _performSearch() async {
    if (_ctrl.text.isEmpty) return;
    setState(() { _isSearching = true; _hasSearched = true; });
    
    final graphState = context.read<GraphState>();
    final networkState = context.read<NetworkState>();
    
    // Save content to the node
    graphState.updateNodeContent(widget.nodeId, _ctrl.text);
    
    final results = await networkState.redleafService.fetchFtsResultsUI(_ctrl.text);
    if (mounted) {
      setState(() { _isSearching = false; _results = results; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final graphState = context.watch<GraphState>(); // Use watch to rebuild on pins
    final networkState = context.watch<NetworkState>(); // To get API URL for links
    final node = graphState.nodes[widget.nodeId];
    if (node == null) return const SizedBox.shrink();

    // Compile display list: Pinned items first, then unpinned search results
    List<Map<String, dynamic>> displayList = [];
    for (var p in node.pinnedSearchResults) {
      displayList.add({...p, 'isPinned': true});
    }
    for (var r in _results) {
      bool isAlreadyPinned = node.pinnedSearchResults.any((p) => p['title'] == r['title'] && p['snippet'] == r['snippet']);
      if (!isAlreadyPinned) {
        displayList.add({...r, 'isPinned': false});
      }
    }

    return Container(
      color: const Color(0xFF1A1A1A), padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text("REDLEAF GLOBAL SEARCH", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, letterSpacing: 1.5)),
          const SizedBox(height: 20),
          
          TextField(
            controller: _ctrl, 
            decoration: InputDecoration(
              filled: true, fillColor: const Color(0xFF222222), 
              hintText: "e.g. Security Protocols",
              suffixIcon: IconButton(
                icon: const Icon(Icons.search, color: Colors.white),
                onPressed: _performSearch,
              )
            ),
            onChanged: (v) => graphState.updateNodeContent(widget.nodeId, v),
            onSubmitted: (_) => _performSearch(),
          ),
          const SizedBox(height: 15),
          
          Row(
            children: [
              const Icon(Icons.tune, color: Colors.white54, size: 16),
              const SizedBox(width: 8),
              const Text("Auto-feed top ", style: TextStyle(color: Colors.white70, fontSize: 13)),
              SizedBox(
                width: 45,
                child: TextField(
                  controller: _limitCtrl,
                  keyboardType: TextInputType.number,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 13, color: Colors.white, fontWeight: FontWeight.bold),
                  decoration: const InputDecoration(
                    isDense: true, contentPadding: EdgeInsets.symmetric(vertical: 4),
                    filled: true, fillColor: Color(0xFF333333), border: OutlineInputBorder(borderSide: BorderSide.none)
                  ),
                  onChanged: (val) {
                    final limit = int.tryParse(val);
                    if (limit != null && limit > 0) graphState.updateSearchLimit(widget.nodeId, limit);
                  },
                ),
              ),
              const Text(" results + pinned", style: TextStyle(color: Colors.white70, fontSize: 13)),
            ],
          ),

          const SizedBox(height: 20),
          Row(
            children: [
              const Text("Preview & Pin Results", style: TextStyle(color: Colors.white70, fontWeight: FontWeight.bold)),
              const Spacer(),
              if (_isSearching) const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
            ],
          ),
          const SizedBox(height: 10),

          Expanded(
            child: _hasSearched && displayList.isEmpty && !_isSearching
              ? const Center(child: Text("No results found in Redleaf DB.", style: TextStyle(color: Colors.white54, fontSize: 12)))
              : ListView.separated(
                  itemCount: displayList.length,
                  separatorBuilder: (ctx, i) => const SizedBox(height: 8),
                  itemBuilder: (ctx, index) {
                    final item = displayList[index];
                    final bool isError = item['isError'] == true;
                    final bool isPinned = item['isPinned'] == true;
                    
                    return Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: isError ? Colors.red.withOpacity(0.1) : (isPinned ? const Color(0xFF332D15) : const Color(0xFF252525)),
                        border: Border.all(color: isError ? Colors.red : (isPinned ? Colors.amber : Colors.white24)),
                        borderRadius: BorderRadius.circular(8)
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                MouseRegion(
                                  cursor: isError ? SystemMouseCursors.basic : SystemMouseCursors.click,
                                  child: GestureDetector(
                                    onTap: () async {
                                      if (isError) return;
                                      final docId = item['doc_id'];
                                      final pageNum = item['page_number'];
                                      final baseUrl = networkState.redleafService.apiUrl;
                                      final url = Uri.parse('$baseUrl/document/$docId#page=$pageNum');
                                      if (await canLaunchUrl(url)) {
                                        await launchUrl(url);
                                      } else {
                                        debugPrint('Could not launch $url');
                                      }
                                    },
                                    child: Text(
                                      item['title'] ?? "Unknown", 
                                      style: TextStyle(
                                        color: isError ? Colors.redAccent : (isPinned ? Colors.amber : Colors.lightBlueAccent), 
                                        fontWeight: FontWeight.bold, 
                                        fontSize: 13,
                                        decoration: isError ? TextDecoration.none : TextDecoration.underline,
                                      )
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 6),
                                SelectableText(
                                  item['snippet'] ?? "", 
                                  style: TextStyle(color: isError ? Colors.white : Colors.white70, fontSize: 12, height: 1.4)
                                ),
                              ],
                            ),
                          ),
                          if (!isError)
                            IconButton(
                              icon: Icon(isPinned ? Icons.push_pin : Icons.push_pin_outlined, color: isPinned ? Colors.amber : Colors.white54, size: 20),
                              onPressed: () {
                                final payload = {
                                  'doc_id': item['doc_id'],
                                  'page_number': item['page_number'],
                                  'title': item['title'],
                                  'snippet': item['snippet']
                                };
                                graphState.togglePinnedSearchResult(widget.nodeId, payload);
                              },
                            )
                        ],
                      ),
                    );
                  },
                ),
          ),
        ]
      )
    );
  }
}

class EntitySearchDialog extends StatefulWidget {
  final String nodeId;
  const EntitySearchDialog({super.key, required this.nodeId});
  @override
  State<EntitySearchDialog> createState() => _EntitySearchDialogState();
}

class _EntitySearchDialogState extends State<EntitySearchDialog> {
  final TextEditingController _ctrl = TextEditingController();
  List<Map<String, dynamic>> _results = [];
  bool _isSearching = false;

  void _search() async {
    if (_ctrl.text.isEmpty) return;
    setState(() { _isSearching = true; _results = []; });
    
    final networkState = context.read<NetworkState>();
    final data = await networkState.redleafService.searchEntities(_ctrl.text);
    
    if (mounted) setState(() { _results = data; _isSearching = false; });
  }

  @override
  Widget build(BuildContext context) {
    final networkState = context.read<NetworkState>();
    final graphState = context.read<GraphState>();

    return AlertDialog(
      backgroundColor: kNodeBg,
      title: const Text("Search Redleaf spaCy Index", style: TextStyle(color: Colors.white)),
      content: SizedBox(
        width: 400, height: 400,
        child: Column(
          children: [
            TextField(
              controller: _ctrl, autofocus: true,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: "Enter a person, place, or topic...", 
                hintStyle: const TextStyle(color: Colors.white54),
                filled: true, fillColor: Colors.black26,
                suffixIcon: IconButton(icon: const Icon(Icons.search, color: Colors.white), onPressed: _search),
              ),
              onSubmitted: (_) => _search(),
            ),
            const SizedBox(height: 10),
            if (_isSearching) const Center(child: CircularProgressIndicator(color: Colors.white))
            else if (_results.isEmpty && _ctrl.text.isNotEmpty) const Center(child: Text("No matching entities found.", style: TextStyle(color: Colors.white54)))
            else Expanded(
              child: ListView.builder(
                itemCount: _results.length,
                itemBuilder: (ctx, i) {
                  final item = _results[i];
                  return ListTile(
                    title: Text(item['text'], style: const TextStyle(color: Colors.white)),
                    subtitle: Text("${item['label']} - Mentions: ${item['count']}", style: const TextStyle(color: Colors.white54)),
                    onTap: () async {
                      final id = await networkState.redleafService.extractEntityId(item['label'], item['text']);
                      if (id != null) {
                        graphState.addPillToNode(widget.nodeId, RedleafPill(id: const Uuid().v4(), entityId: id, text: item['text'], label: item['label']));
                        if (mounted) Navigator.pop(context);
                      } else {
                        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Failed to resolve Entity ID.")));
                      }
                    },
                  );
                },
              ),
            )
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text("Cancel", style: TextStyle(color: Colors.white))),
      ]
    );
  }
}

class OutputNodePanel extends StatelessWidget {
  final String nodeId;
  const OutputNodePanel({super.key, required this.nodeId});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Column(
        children: [
          const TabBar(
            indicatorColor: Colors.white,
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white54,
            tabs: [
              Tab(icon: Icon(Icons.menu_book), text: "Compiled Data"),
              Tab(icon: Icon(Icons.auto_awesome), text: "Execution"),
            ],
          ),
          Expanded(
            child: TabBarView(
              children: [
                PreviewPanel(targetNodeId: nodeId),
                _OllamaInterface(nodeId: nodeId), 
              ],
            ),
          )
        ],
      ),
    );
  }
}

class _OllamaInterface extends StatefulWidget {
  final String nodeId;
  const _OllamaInterface({required this.nodeId});
  @override
  State<_OllamaInterface> createState() => _OllamaInterfaceState();
}

class _OllamaInterfaceState extends State<_OllamaInterface> {
  late TextEditingController _promptCtrl;

  @override
  void initState() {
    super.initState();
    final graphState = context.read<GraphState>();
    final initialPrompt = graphState.nodes[widget.nodeId]?.ollamaPrompt ?? "";
    _promptCtrl = TextEditingController(text: initialPrompt.isEmpty ? "Synthesize the following context." : initialPrompt);
  }

  @override
  void dispose() { _promptCtrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final graphState = context.watch<GraphState>();
    final networkState = context.watch<NetworkState>(); 
    
    final node = graphState.nodes[widget.nodeId];
    if (node == null) return const SizedBox.shrink();

    final bool isThisGenerating = networkState.isNodeGenerating(widget.nodeId);

    return Padding(
      padding: const EdgeInsets.all(20.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text("OLLAMA SYSTEM INSTRUCTION", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
          const SizedBox(height: 10),
          TextField(
            controller: _promptCtrl, maxLines: 3,
            decoration: const InputDecoration(filled: true, fillColor: Color(0xFF222222), border: OutlineInputBorder(borderSide: BorderSide.none), hintText: "E.g., Act as a factual researcher..."),
            onChanged: (val) => graphState.updateOllamaPrompt(widget.nodeId, val),
          ),
          const SizedBox(height: 10),
          
          Theme(
            data: ThemeData(unselectedWidgetColor: Colors.grey),
            child: CheckboxListTile(
              title: const Text("Raw Output Only (No AI filler)", style: TextStyle(fontSize: 12, color: Colors.white70)),
              contentPadding: EdgeInsets.zero, controlAffinity: ListTileControlAffinity.leading, activeColor: Colors.white, checkColor: Colors.black,
              value: node.ollamaNoBacktalk, onChanged: (val) { if (val != null) graphState.toggleOllamaBacktalk(widget.nodeId, val); },
            ),
          ),
          
          Theme(
            data: ThemeData(unselectedWidgetColor: Colors.grey),
            child: CheckboxListTile(
              title: const Text("Autonomous Redleaf Research", style: TextStyle(fontSize: 12, color: Colors.white70)),
              subtitle: const Text("AI will auto-search Redleaf for terms found in your prompt before generating.", style: TextStyle(fontSize: 10, color: Colors.white54)),
              contentPadding: EdgeInsets.zero, controlAffinity: ListTileControlAffinity.leading, activeColor: Colors.white, checkColor: Colors.black,
              value: node.enableAutonomousResearch, onChanged: (val) { if (val != null) graphState.toggleAutonomousResearch(widget.nodeId, val); },
            ),
          ),

          const SizedBox(height: 15),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF333333), foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 16), side: const BorderSide(color: Colors.white54)),
              icon: isThisGenerating ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)) : const Icon(Icons.auto_awesome),
              label: Text(isThisGenerating ? "GENERATING..." : "RUN (${networkState.ollamaModel})"),
              onPressed: networkState.isGeneratingOllama ? null : () {
                final sequence = graphState.getCompiledNodes(widget.nodeId);
                networkState.triggerOllamaGeneration(node, sequence, graphState); // Pass graphState
              },
            ),
          ),
          
          if (isThisGenerating) ...[
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.redAccent, 
                  side: const BorderSide(color: Colors.redAccent),
                  padding: const EdgeInsets.symmetric(vertical: 12)
                ),
                icon: const Icon(Icons.flash_on), 
                label: const Text("ANSWER NOW (Skip Research)"),
                onPressed: () => networkState.forceAnswerNow(),
              ),
            ),
          ],
          
          const SizedBox(height: 20),
          const Text("RESULT", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
          const SizedBox(height: 10),
          Expanded(
            child: Container(
              width: double.infinity, padding: const EdgeInsets.all(15),
              decoration: BoxDecoration(color: const Color(0xFF111111), borderRadius: BorderRadius.circular(8)),
              child: SingleChildScrollView(
                child: SelectableText.rich(
                  node.ollamaResult.isEmpty 
                      ? const TextSpan(text: "Output will appear here...", style: TextStyle(color: Colors.grey))
                      : parseRichText(node.ollamaResult, networkState.redleafService.apiUrl),
                  style: const TextStyle(color: Colors.white, height: 1.5),
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(foregroundColor: Colors.white, side: const BorderSide(color: Colors.white54)),
              icon: const Icon(Icons.turn_right), label: const Text("Promote to Scratchpad"),
              onPressed: node.ollamaResult.isEmpty || networkState.isGeneratingOllama ? null : () => graphState.promoteOutputToScratchpad(node.id),
            ),
          )
        ],
      ),
    );
  }
}

class PreviewPanel extends StatelessWidget {
  final String? targetNodeId;
  const PreviewPanel({super.key, this.targetNodeId});

  @override
  Widget build(BuildContext context) {
    final graphState = context.watch<GraphState>();
    final canvasState = context.read<CanvasState>();
    final nodes = graphState.getCompiledNodes(targetNodeId);

    if (nodes.length <= 1) { 
      return Column(
        children: [
          Container(
            padding: const EdgeInsets.all(15), color: const Color(0xFF222222), width: double.infinity,
            child: const Text("COMPILED DATA", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
          const Expanded(
            child: Center(
              child: Text("No upstream data connected.", style: TextStyle(color: Colors.white54))
            )
          )
        ]
      );
    }

    return Column(
      children:[
        Container(
          padding: const EdgeInsets.all(15), color: const Color(0xFF222222), width: double.infinity,
          child: Row(
            children:[
              const Text("COMPILED DATA", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.copy, size: 20, color: Colors.white70), tooltip: "Copy Text",
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: graphState.getCompiledRawText(nodes)));
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Copied to clipboard!"), duration: Duration(seconds: 2)));
                },
              ),
              if (graphState.previewNodeId != null) 
                IconButton(icon: const Icon(Icons.close, color: Colors.white70), onPressed: () => graphState.setPreviewNode(null))
            ]
          ),
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.all(30), itemCount: nodes.length,
            itemBuilder: (ctx, i) {
              final node = nodes[i];
              if (node.type == NodeType.output || node.type == NodeType.chat || node.type == NodeType.wikiWriter) return const SizedBox(height: 50, child: Divider(color: Colors.white24));
              
              final baseStyle = const TextStyle(fontSize: 16, height: 1.6, color: Colors.white70);
              final nodeIndex = graphState.getNodeIndex(node.id);
              final indexPrefix = nodeIndex > 0 ? "#$nodeIndex " : "";

              String displayText = node.content;
              if (node.type == NodeType.wikiReader) {
                displayText = "File: ${node.wikiTitle}.md";
              } else if (node.type == NodeType.study || node.type == NodeType.summarize) {
                displayText = "Task: ${node.content}\n\n[Generated Result]:\n${node.ollamaResult.isEmpty ? 'Not run yet.' : node.ollamaResult}";
              }

              return MouseRegion(
                cursor: SystemMouseCursors.click,
                child: GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onTap: () => canvasState.jumpToNode(node.id, graphState),
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 20.0),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children:[
                      Text((indexPrefix + node.title).toUpperCase(), style: const TextStyle(color: Colors.white, fontSize: 10, letterSpacing: 1.5, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 8),
                      SelectableText(displayText, style: baseStyle),
                      if (node.redleafPills.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Text("Attached Context: ${node.redleafPills.map((p) => p.text).join(', ')}", style: const TextStyle(color: Colors.white54, fontSize: 12, fontStyle: FontStyle.italic)),
                      ]
                    ]),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

// ====================================================================
// CHAT NODE PANEL
// ====================================================================

class ChatNodePanel extends StatefulWidget {
  final String nodeId;
  const ChatNodePanel({super.key, required this.nodeId});

  @override
  State<ChatNodePanel> createState() => _ChatNodePanelState();
}

class _ChatNodePanelState extends State<ChatNodePanel> {
  final TextEditingController _msgCtrl = TextEditingController();
  final ScrollController _scrollCtrl = ScrollController();

  void _sendMessage() {
    final text = _msgCtrl.text.trim();
    if (text.isEmpty) return;

    final networkState = context.read<NetworkState>();
    final graphState = context.read<GraphState>();
    
    if (networkState.isGeneratingOllama) return;
    
    final node = graphState.nodes[widget.nodeId]!;
    final sequence = graphState.getCompiledNodes(widget.nodeId);

    _msgCtrl.clear();
    networkState.triggerOllamaChat(node, sequence, text, graphState);

    Future.delayed(const Duration(milliseconds: 100), _scrollToBottom);
  }

  void _scrollToBottom() {
    if (_scrollCtrl.hasClients) {
      _scrollCtrl.animateTo(_scrollCtrl.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
    }
  }

  @override
  Widget build(BuildContext context) {
    final graphState = context.watch<GraphState>();
    final networkState = context.watch<NetworkState>();
    final node = graphState.nodes[widget.nodeId];
    
    if (node == null) return const SizedBox.shrink();

    final bool isThisGenerating = networkState.isNodeGenerating(widget.nodeId);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients && _scrollCtrl.offset >= _scrollCtrl.position.maxScrollExtent - 50) {
        _scrollToBottom();
      }
    });

    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(15),
          decoration: const BoxDecoration(
            color: Color(0xFF222222),
            border: Border(bottom: BorderSide(color: Color(0xFF383842)))
          ),
          child: Row(
            children: [
              const Icon(Icons.forum, color: Colors.greenAccent, size: 20),
              const SizedBox(width: 10),
              const Text("OLLAMA CHAT", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, letterSpacing: 1.5)),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.delete_sweep, color: Colors.white54, size: 20),
                tooltip: "Clear Chat History",
                onPressed: () => graphState.clearChatHistory(widget.nodeId),
              )
            ],
          ),
        ),

        Container(
          color: const Color(0xFF1A1A1A),
          child: ExpansionTile(
            title: const Text("Chat Settings & Toggles", style: TextStyle(color: Colors.white70, fontSize: 12)),
            collapsedIconColor: Colors.white54,
            iconColor: Colors.white,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 15.0, vertical: 5.0),
                child: TextField(
                  maxLines: 2,
                  style: const TextStyle(fontSize: 12, color: Colors.white70),
                  decoration: const InputDecoration(
                    labelText: "System Instructions",
                    labelStyle: TextStyle(color: Colors.white54),
                    filled: true, fillColor: Color(0xFF2A2A32),
                    border: OutlineInputBorder(borderSide: BorderSide.none),
                  ),
                  controller: TextEditingController(text: node.ollamaPrompt)..selection = TextSelection.collapsed(offset: node.ollamaPrompt.length),
                  onChanged: (val) => graphState.updateOllamaPrompt(widget.nodeId, val),
                ),
              ),
              Theme(
                data: ThemeData(unselectedWidgetColor: Colors.grey),
                child: CheckboxListTile(
                  title: const Text("Strict Analytical Mode", style: TextStyle(fontSize: 12, color: Colors.white70)),
                  subtitle: const Text("Forces AI to prioritize facts and use inline citations [Doc X].", style: TextStyle(fontSize: 10, color: Colors.white54)),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 15.0), controlAffinity: ListTileControlAffinity.leading, activeColor: Colors.white, checkColor: Colors.black,
                  value: node.ollamaNoBacktalk, onChanged: (val) { if (val != null) graphState.toggleOllamaBacktalk(widget.nodeId, val); },
                ),
              ),
              Theme(
                data: ThemeData(unselectedWidgetColor: Colors.grey),
                child: CheckboxListTile(
                  title: const Text("Autonomous Redleaf Research", style: TextStyle(fontSize: 12, color: Colors.white70)),
                  subtitle: const Text("AI will auto-search Redleaf for topics found in your new messages.", style: TextStyle(fontSize: 10, color: Colors.white54)),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 15.0), controlAffinity: ListTileControlAffinity.leading, activeColor: Colors.white, checkColor: Colors.black,
                  value: node.enableAutonomousResearch, onChanged: (val) { if (val != null) graphState.toggleAutonomousResearch(widget.nodeId, val); },
                ),
              ),
              const SizedBox(height: 10),
            ],
          ),
        ),

        Expanded(
          child: ListView.builder(
            controller: _scrollCtrl,
            padding: const EdgeInsets.all(15),
            itemCount: node.chatHistory.length,
            itemBuilder: (ctx, i) {
              final msg = node.chatHistory[i];
              final isUser = msg['role'] == 'user';
              
              return Align(
                alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
                child: Container(
                  margin: const EdgeInsets.only(bottom: 15),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  constraints: const BoxConstraints(maxWidth: 320),
                  decoration: BoxDecoration(
                    color: isUser ? kAccentColor.withOpacity(0.8) : const Color(0xFF333333),
                    borderRadius: BorderRadius.circular(12).copyWith(
                      bottomRight: isUser ? const Radius.circular(0) : const Radius.circular(12),
                      bottomLeft: !isUser ? const Radius.circular(0) : const Radius.circular(12),
                    ),
                  ),
                  child: SelectableText.rich(
                    parseRichText(msg['content'] ?? "", networkState.redleafService.apiUrl),
                    style: const TextStyle(color: Colors.white, fontSize: 14, height: 1.4),
                  ),
                ),
              );
            },
          ),
        ),

        Container(
          padding: const EdgeInsets.all(15),
          decoration: const BoxDecoration(
            color: Color(0xFF222222),
            border: Border(top: BorderSide(color: Color(0xFF383842)))
          ),
          child: Column(
            children: [
              if (isThisGenerating)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10.0),
                  child: SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.redAccent, 
                        side: const BorderSide(color: Colors.redAccent),
                        padding: const EdgeInsets.symmetric(vertical: 8)
                      ),
                      icon: const Icon(Icons.flash_on, size: 16), 
                      label: const Text("ANSWER NOW (Skip Research)", style: TextStyle(fontSize: 12)),
                      onPressed: () => networkState.forceAnswerNow(),
                    ),
                  ),
                ),
              Row(
                children: [
                  Expanded(
                    child: Focus(
                      onKeyEvent: (nodeFocus, event) {
                        if (event is KeyDownEvent && event.logicalKey == LogicalKeyboardKey.enter) {
                          final isShiftPressed = HardwareKeyboard.instance.logicalKeysPressed.contains(LogicalKeyboardKey.shiftLeft) || 
                                                 HardwareKeyboard.instance.logicalKeysPressed.contains(LogicalKeyboardKey.shiftRight);
                          if (isShiftPressed) {
                            if (!networkState.isGeneratingOllama) {
                              _sendMessage();
                            }
                            return KeyEventResult.handled;
                          }
                        }
                        return KeyEventResult.ignored;
                      },
                      child: TextField(
                        controller: _msgCtrl,
                        maxLines: 4, minLines: 1,
                        textInputAction: TextInputAction.newline,
                        style: const TextStyle(color: Colors.white),
                        decoration: const InputDecoration(
                          hintText: "Message... (Shift+Enter to send)",
                          hintStyle: TextStyle(color: Colors.white54),
                          filled: true, fillColor: Color(0xFF1A1A1A),
                          border: OutlineInputBorder(borderSide: BorderSide.none, borderRadius: BorderRadius.all(Radius.circular(8))),
                          contentPadding: EdgeInsets.symmetric(horizontal: 15, vertical: 10)
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Container(
                    decoration: const BoxDecoration(color: Colors.greenAccent, shape: BoxShape.circle),
                    child: IconButton(
                      icon: isThisGenerating 
                        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: Colors.black, strokeWidth: 2))
                        : const Icon(Icons.send, color: Colors.black),
                      onPressed: networkState.isGeneratingOllama ? null : _sendMessage,
                    ),
                  )
                ],
              ),
            ],
          ),
        )
      ],
    );
  }
}

// ====================================================================
// DEEP STUDY NODE PANEL (THE "GEEK OUT" NODE)
// ====================================================================

class StudyNodePanel extends StatefulWidget {
  final String nodeId;
  const StudyNodePanel({super.key, required this.nodeId});

  @override
  State<StudyNodePanel> createState() => _StudyNodePanelState();
}

class _StudyNodePanelState extends State<StudyNodePanel> {
  late TextEditingController _topicCtrl;

  @override
  void initState() {
    super.initState();
    final graphState = context.read<GraphState>();
    _topicCtrl = TextEditingController(text: graphState.nodes[widget.nodeId]?.content ?? "");
  }

  @override
  void didUpdateWidget(covariant StudyNodePanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.nodeId != widget.nodeId) {
      final graphState = context.read<GraphState>();
      _topicCtrl.text = graphState.nodes[widget.nodeId]?.content ?? "";
    }
  }

  @override
  void dispose() {
    _topicCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final graphState = context.watch<GraphState>();
    final networkState = context.watch<NetworkState>(); 
    
    final node = graphState.nodes[widget.nodeId];
    if (node == null) return const SizedBox.shrink();

    final bool isThisGenerating = networkState.isNodeGenerating(widget.nodeId);

    return Padding(
      padding: const EdgeInsets.all(20.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.school, color: Colors.deepPurpleAccent, size: 20),
              SizedBox(width: 10),
              Text("DEEP STUDY (GEEK OUT)", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white, letterSpacing: 1.5)),
            ],
          ),
          const SizedBox(height: 10),
          const Text("Enter a topic. The agent will autonomously scour the Redleaf database, read documents, take notes, and compile a master report.", style: TextStyle(color: Colors.white54, fontSize: 12)),
          const SizedBox(height: 20),

          const Text("Research Topic:", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white70)),
          const SizedBox(height: 5),
          TextField(
            controller: _topicCtrl,
            decoration: const InputDecoration(filled: true, fillColor: Color(0xFF222222), border: OutlineInputBorder(borderSide: BorderSide.none), hintText: "E.g., Soft power campaigns in East Germany"),
            onChanged: (val) => graphState.updateNodeContent(widget.nodeId, val),
          ),
          const SizedBox(height: 15),

          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.deepPurple.shade800, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 16)),
              icon: isThisGenerating ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)) : const Icon(Icons.travel_explore),
              label: Text(isThisGenerating ? "RESEARCHING..." : "START AUTONOMOUS STUDY"),
              onPressed: networkState.isGeneratingOllama || _topicCtrl.text.isEmpty ? null : () {
                final sequence = graphState.getCompiledNodes(widget.nodeId);
                networkState.triggerStudyLoop(node, sequence, graphState); 
              },
            ),
          ),
          
          if (isThisGenerating) ...[
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.redAccent, 
                  side: const BorderSide(color: Colors.redAccent),
                  padding: const EdgeInsets.symmetric(vertical: 12)
                ),
                icon: const Icon(Icons.flash_on), 
                label: const Text("ANSWER NOW (Skip Research)"),
                onPressed: () => networkState.forceAnswerNow(),
              ),
            ),
          ],
          
          const SizedBox(height: 20),
          const Text("STUDY REPORT", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
          const SizedBox(height: 10),
          Expanded(
            child: Container(
              width: double.infinity, padding: const EdgeInsets.all(15),
              decoration: BoxDecoration(color: const Color(0xFF111111), borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.white12)),
              child: SingleChildScrollView(
                child: SelectableText.rich(
                  node.ollamaResult.isEmpty 
                      ? const TextSpan(text: "Agent logs and final report will appear here...", style: TextStyle(color: Colors.grey))
                      : parseRichText(node.ollamaResult, networkState.redleafService.apiUrl),
                  style: const TextStyle(color: Colors.white, height: 1.5),
                ),
              ),
            ),
          ),
          
          if (node.ollamaResult.isNotEmpty && !isThisGenerating) ...[
            const SizedBox(height: 10),
            const Text("💡 Wire this node into an Output or Chat node to use this report as context!", style: TextStyle(color: Colors.greenAccent, fontSize: 12, fontStyle: FontStyle.italic))
          ]
        ],
      ),
    );
  }
}

// ====================================================================
// SUMMARIZE NODE PANEL
// ====================================================================

class SummarizeNodePanel extends StatelessWidget {
  final String nodeId;
  const SummarizeNodePanel({super.key, required this.nodeId});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Column(
        children: [
          const TabBar(
            indicatorColor: Colors.white,
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white54,
            tabs: [
              Tab(icon: Icon(Icons.menu_book), text: "Compiled Data"),
              Tab(icon: Icon(Icons.bolt), text: "Execution"),
            ],
          ),
          Expanded(
            child: TabBarView(
              children: [
                PreviewPanel(targetNodeId: nodeId), 
                _SummarizeInterface(nodeId: nodeId),
              ],
            ),
          )
        ],
      ),
    );
  }
}

class _SummarizeInterface extends StatefulWidget {
  final String nodeId;
  const _SummarizeInterface({required this.nodeId});
  @override
  State<_SummarizeInterface> createState() => _SummarizeInterfaceState();
}

class _SummarizeInterfaceState extends State<_SummarizeInterface> {
  late TextEditingController _promptCtrl;

  @override
  void initState() {
    super.initState();
    final graphState = context.read<GraphState>();
    final initialPrompt = graphState.nodes[widget.nodeId]?.ollamaPrompt ?? "";
    _promptCtrl = TextEditingController(text: initialPrompt.isEmpty ? "Please provide a comprehensive and detailed summary of the following context material." : initialPrompt);
  }

  @override
  void dispose() { _promptCtrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final graphState = context.watch<GraphState>();
    final networkState = context.watch<NetworkState>(); 
    final node = graphState.nodes[widget.nodeId];
    if (node == null) return const SizedBox.shrink();

    final bool isThisGenerating = networkState.isNodeGenerating(widget.nodeId);

    return Padding(
      padding: const EdgeInsets.all(20.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.bolt, color: Colors.white70, size: 20),
              SizedBox(width: 10),
              Text("DIRECT PROMPT (NO AGENT)", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white, letterSpacing: 1.5)),
            ],
          ),
          const SizedBox(height: 10),
          const Text("Gathers all upstream context and feeds it directly into Ollama with your instructions. Bypasses the autonomous ReAct agent loop entirely for speed.", style: TextStyle(color: Colors.white54, fontSize: 12)),
          const SizedBox(height: 20),

          const Text("LLM INSTRUCTION", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
          const SizedBox(height: 10),
          TextField(
            controller: _promptCtrl, maxLines: 3,
            decoration: const InputDecoration(filled: true, fillColor: Color(0xFF222222), border: OutlineInputBorder(borderSide: BorderSide.none), hintText: "E.g., Write a 5-paragraph essay comparing these documents..."),
            onChanged: (val) => graphState.updateOllamaPrompt(widget.nodeId, val),
          ),
          const SizedBox(height: 15),

          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF333333), 
                foregroundColor: Colors.white, 
                padding: const EdgeInsets.symmetric(vertical: 16),
                side: const BorderSide(color: Colors.white54)
              ),
              icon: isThisGenerating 
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)) 
                : const Icon(Icons.bolt),
              label: Text(isThisGenerating ? "GENERATING..." : "RUN PROMPT (${networkState.ollamaModel})"),
              onPressed: networkState.isGeneratingOllama ? null : () {
                final sequence = graphState.getCompiledNodes(widget.nodeId);
                networkState.triggerSummarizeGeneration(node, sequence, graphState); 
              },
            ),
          ),
          
          const SizedBox(height: 20),
          const Text("RESULT", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
          const SizedBox(height: 10),
          Expanded(
            child: Container(
              width: double.infinity, padding: const EdgeInsets.all(15),
              decoration: BoxDecoration(color: const Color(0xFF111111), borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.white12)),
              child: SingleChildScrollView(
                child: SelectableText.rich(
                  node.ollamaResult.isEmpty 
                      ? const TextSpan(text: "Output will appear here...", style: TextStyle(color: Colors.grey))
                      : parseRichText(node.ollamaResult, networkState.redleafService.apiUrl),
                  style: const TextStyle(color: Colors.white, height: 1.5),
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(foregroundColor: Colors.white, side: const BorderSide(color: Colors.white54)),
              icon: const Icon(Icons.turn_right), label: const Text("Promote to Scratchpad"),
              onPressed: node.ollamaResult.isEmpty || networkState.isGeneratingOllama ? null : () => graphState.promoteOutputToScratchpad(node.id),
            ),
          )
        ],
      ),
    );
  }
}

// ====================================================================
// NEW: WIKI READER NODE PANEL
// ====================================================================

class WikiReaderNodePanel extends StatefulWidget {
  final String nodeId;
  const WikiReaderNodePanel({super.key, required this.nodeId});

  @override
  State<WikiReaderNodePanel> createState() => _WikiReaderNodePanelState();
}

class _WikiReaderNodePanelState extends State<WikiReaderNodePanel> {
  late TextEditingController _titleCtrl;
  String _preview = "";
  bool _isLoadingPreview = false;
  
  List<String> _availablePages = [];
  bool _isLoadingPages = true;

  @override
  void initState() {
    super.initState();
    final graphState = context.read<GraphState>();
    _titleCtrl = TextEditingController(text: graphState.nodes[widget.nodeId]?.wikiTitle ?? "");
    _fetchPages();
  }

  @override
  void didUpdateWidget(covariant WikiReaderNodePanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.nodeId != widget.nodeId) {
      final graphState = context.read<GraphState>();
      _titleCtrl.text = graphState.nodes[widget.nodeId]?.wikiTitle ?? "";
      _preview = "";
      _fetchPages();
    }
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    super.dispose();
  }

  void _fetchPages() async {
    final graphState = context.read<GraphState>();
    final networkState = context.read<NetworkState>();
    final pages = await graphState.listWikiPages(networkState);
    if (mounted) setState(() { _availablePages = pages; _isLoadingPages = false; });
  }

  void _fetchPreview() async {
    if (_titleCtrl.text.trim().isEmpty) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Please enter a Wiki page title first.")));
      return;
    }
    
    setState(() => _isLoadingPreview = true);
    final graphState = context.read<GraphState>();
    final networkState = context.read<NetworkState>();
    
    final text = await graphState.readWikiPage(_titleCtrl.text, networkState);
    if (mounted) setState((){ _preview = text; _isLoadingPreview = false; });
  }

  @override
  Widget build(BuildContext context) {
    final graphState = context.watch<GraphState>();
    final node = graphState.nodes[widget.nodeId];
    if (node == null) return const SizedBox.shrink();

    return Container(
      color: const Color(0xFF1A1A1A), padding: const EdgeInsets.all(20),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Row(
          children: [
            Icon(Icons.menu_book, color: Colors.lightBlueAccent, size: 20),
            SizedBox(width: 10),
            Text("WIKI READER", style: TextStyle(color: Colors.lightBlueAccent, fontWeight: FontWeight.bold, letterSpacing: 1.5)),
          ],
        ),
        const SizedBox(height: 20),
        const Text(
          "Loads a Markdown (.md) file from your local Wiki folder into the LLM context. Ideal for feeding existing knowledge to an Agent.", 
          style: TextStyle(color: Colors.grey, fontSize: 13, height: 1.4)
        ),
        const SizedBox(height: 20),
        
        const Text("Wiki Page Title:", style: TextStyle(color: Colors.white70, fontSize: 12)),
        const SizedBox(height: 5),
        TextField(
          controller: _titleCtrl,
          decoration: const InputDecoration(
            filled: true, fillColor: Color(0xFF222222), 
            hintText: "e.g. Cold_War_Economics",
            border: OutlineInputBorder(borderSide: BorderSide.none)
          ),
          onChanged: (v) {
             graphState.updateWikiTitle(widget.nodeId, v);
             graphState.updateNodeTitle(widget.nodeId, "Read: $v");
          }
        ),
        const SizedBox(height: 10),

        // --- NEW: Browse Directory UI ---
        Theme(
          data: ThemeData(unselectedWidgetColor: Colors.grey, dividerColor: Colors.transparent),
          child: ExpansionTile(
            tilePadding: EdgeInsets.zero,
            title: Text("Browse Directory (${_availablePages.length} files)", style: const TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.bold)),
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: const Color(0xFF222222), borderRadius: BorderRadius.circular(8)),
                child: _isLoadingPages 
                  ? const Text("Scanning folder...", style: TextStyle(color: Colors.white54, fontSize: 12))
                  : _availablePages.isEmpty 
                    ? const Text("No wiki pages found.", style: TextStyle(color: Colors.white54, fontSize: 12))
                    : Wrap(
                        spacing: 8, runSpacing: 8,
                        children: _availablePages.map((page) => ActionChip(
                          backgroundColor: const Color(0xFF333333),
                          side: BorderSide.none,
                          label: Text(page, style: const TextStyle(color: Colors.white70, fontSize: 12)),
                          onPressed: () {
                            _titleCtrl.text = page;
                            graphState.updateWikiTitle(widget.nodeId, page);
                            graphState.updateNodeTitle(widget.nodeId, "Read: $page");
                            _fetchPreview();
                          },
                        )).toList(),
                      ),
              )
            ],
          ),
        ),

        const SizedBox(height: 20),
        ElevatedButton.icon(
          style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF333333), foregroundColor: Colors.white),
          icon: _isLoadingPreview ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)) : const Icon(Icons.preview),
          label: const Text("Preview Local File"),
          onPressed: _isLoadingPreview ? null : _fetchPreview,
        ),
        if (_preview.isNotEmpty) ...[
          const SizedBox(height: 20),
          const Text("File Contents:", style: TextStyle(color: Colors.white70, fontWeight: FontWeight.bold)),
          const SizedBox(height: 10),
          Expanded(
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: const Color(0xFF222222), borderRadius: BorderRadius.circular(8)),
              child: SingleChildScrollView(
                child: SelectableText(_preview, style: const TextStyle(color: Colors.white70, fontSize: 13, fontFamily: 'monospace')),
              ),
            ),
          )
        ]
      ])
    );
  }
}

// ====================================================================
// NEW: WIKI WRITER NODE PANEL
// ====================================================================

class WikiWriterNodePanel extends StatelessWidget {
  final String nodeId;
  const WikiWriterNodePanel({super.key, required this.nodeId});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Column(
        children: [
          const TabBar(
            indicatorColor: Colors.white,
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white54,
            tabs: [
              Tab(icon: Icon(Icons.menu_book), text: "Compiled Data"),
              Tab(icon: Icon(Icons.edit_document), text: "Wiki Editor"),
            ],
          ),
          Expanded(
            child: TabBarView(
              children: [
                PreviewPanel(targetNodeId: nodeId), 
                _WikiWriterInterface(nodeId: nodeId),
              ],
            ),
          )
        ],
      ),
    );
  }
}

class _WikiWriterInterface extends StatefulWidget {
  final String nodeId;
  const _WikiWriterInterface({required this.nodeId});
  @override
  State<_WikiWriterInterface> createState() => _WikiWriterInterfaceState();
}

class _WikiWriterInterfaceState extends State<_WikiWriterInterface> {
  late TextEditingController _titleCtrl;
  late TextEditingController _promptCtrl;
  
  List<String> _availablePages = [];
  bool _isLoadingPages = true;

  @override
  void initState() {
    super.initState();
    final graphState = context.read<GraphState>();
    final node = graphState.nodes[widget.nodeId];
    _titleCtrl = TextEditingController(text: node?.wikiTitle ?? "");
    _promptCtrl = TextEditingController(text: node?.ollamaPrompt ?? "Review the CURRENT WIKI PAGE STATE and the NEW RESEARCH. Rewrite, expand, and format the wiki page to seamlessly incorporate the new facts.");
    _fetchPages();
  }

  @override
  void didUpdateWidget(covariant _WikiWriterInterface oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.nodeId != widget.nodeId) {
      final graphState = context.read<GraphState>();
      final node = graphState.nodes[widget.nodeId];
      _titleCtrl.text = node?.wikiTitle ?? "";
      _promptCtrl.text = node?.ollamaPrompt ?? "Review the CURRENT WIKI PAGE STATE and the NEW RESEARCH. Rewrite, expand, and format the wiki page to seamlessly incorporate the new facts.";
      _fetchPages();
    }
  }

  @override
  void dispose() { 
    _titleCtrl.dispose();
    _promptCtrl.dispose(); 
    super.dispose(); 
  }

  void _fetchPages() async {
    final graphState = context.read<GraphState>();
    final networkState = context.read<NetworkState>();
    final pages = await graphState.listWikiPages(networkState);
    if (mounted) setState(() { _availablePages = pages; _isLoadingPages = false; });
  }

  @override
  Widget build(BuildContext context) {
    final graphState = context.watch<GraphState>();
    final networkState = context.watch<NetworkState>(); 
    final node = graphState.nodes[widget.nodeId];
    if (node == null) return const SizedBox.shrink();

    final bool isThisGenerating = networkState.isNodeGenerating(widget.nodeId);

    return Padding(
      padding: const EdgeInsets.all(20.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.edit_document, color: Colors.deepOrangeAccent, size: 20),
              SizedBox(width: 10),
              Text("WIKI WRITER (TERMINAL)", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white, letterSpacing: 1.5)),
            ],
          ),
          const SizedBox(height: 10),
          const Text("Instructs Ollama to act as a Wikipedia Editor. It will consume all upstream context and automatically save the output as a Markdown (.md) file to your local Wiki directory. Old versions are backed up automatically.", style: TextStyle(color: Colors.white54, fontSize: 12)),
          const SizedBox(height: 20),

          const Text("Target File Name:", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white70)),
          const SizedBox(height: 5),
          TextField(
            controller: _titleCtrl,
            decoration: const InputDecoration(
              filled: true, fillColor: Color(0xFF222222), 
              border: OutlineInputBorder(borderSide: BorderSide.none), 
              hintText: "e.g. Cold_War_Economics"
            ),
            onChanged: (val) {
               graphState.updateWikiTitle(widget.nodeId, val);
               graphState.updateNodeTitle(widget.nodeId, "Write: $val");
            }
          ),
          const SizedBox(height: 10),

          // --- NEW: Browse Directory UI ---
          Theme(
            data: ThemeData(unselectedWidgetColor: Colors.grey, dividerColor: Colors.transparent),
            child: ExpansionTile(
              tilePadding: EdgeInsets.zero,
              title: Text("Browse Directory (${_availablePages.length} files)", style: const TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.bold)),
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(color: const Color(0xFF222222), borderRadius: BorderRadius.circular(8)),
                  child: _isLoadingPages 
                    ? const Text("Scanning folder...", style: TextStyle(color: Colors.white54, fontSize: 12))
                    : _availablePages.isEmpty 
                      ? const Text("No wiki pages found.", style: TextStyle(color: Colors.white54, fontSize: 12))
                      : Wrap(
                          spacing: 8, runSpacing: 8,
                          children: _availablePages.map((page) => ActionChip(
                            backgroundColor: const Color(0xFF333333),
                            side: BorderSide.none,
                            label: Text(page, style: const TextStyle(color: Colors.white70, fontSize: 12)),
                            onPressed: () {
                              _titleCtrl.text = page;
                              graphState.updateWikiTitle(widget.nodeId, page);
                              graphState.updateNodeTitle(widget.nodeId, "Write: $page");
                            },
                          )).toList(),
                        ),
                )
              ],
            ),
          ),

          const SizedBox(height: 15),

          const Text("Editor Instructions:", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white70)),
          const SizedBox(height: 5),
          TextField(
            controller: _promptCtrl, maxLines: 3,
            decoration: const InputDecoration(filled: true, fillColor: Color(0xFF222222), border: OutlineInputBorder(borderSide: BorderSide.none), hintText: "Focus on adding the financial timeline..."),
            onChanged: (val) => graphState.updateOllamaPrompt(widget.nodeId, val),
          ),
          const SizedBox(height: 15),

          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.deepOrange.shade800, 
                foregroundColor: Colors.white, 
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
              icon: isThisGenerating 
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)) 
                : const Icon(Icons.edit_document),
              label: Text(isThisGenerating ? "EDITING WIKI..." : "START WIKI EDIT (${networkState.ollamaModel})"),
              onPressed: networkState.isGeneratingOllama || _titleCtrl.text.trim().isEmpty ? null : () {
                final sequence = graphState.getCompiledNodes(widget.nodeId);
                networkState.triggerWikiWriterGeneration(node, sequence, graphState);
              },
            ),
          ),
          
          const SizedBox(height: 20),
          const Text("LIVE DRAFT", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
          const SizedBox(height: 10),
          Expanded(
            child: Container(
              width: double.infinity, padding: const EdgeInsets.all(15),
              decoration: BoxDecoration(color: const Color(0xFF111111), borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.white12)),
              child: SingleChildScrollView(
                child: SelectableText(
                  node.ollamaResult.isEmpty 
                      ? "Output will appear here and then be written to disk..."
                      : node.ollamaResult,
                  style: const TextStyle(color: Colors.white, height: 1.5, fontFamily: 'monospace', fontSize: 13),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}