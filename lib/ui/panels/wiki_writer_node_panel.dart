// --- File: lib/ui/panels/wiki_writer_node_panel.dart ---
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../constants.dart';
import '../../state/graph_state.dart';
import '../../state/network_state.dart';
import '../side_panel.dart'; // Needed for parseRichText & PreviewPanel

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