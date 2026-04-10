// --- File: lib/ui/panels/wiki_reader_node_panel.dart ---
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../state/graph_state.dart';
import '../../state/network_state.dart';

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