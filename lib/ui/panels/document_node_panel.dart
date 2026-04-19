// --- File: lib/ui/panels/document_node_panel.dart ---
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../constants.dart';
import '../../state/graph_state.dart';
import '../../state/network_state.dart';
import '../side_panel.dart'; // Needed for EntitySearchDialog

class DocumentNodePanel extends StatefulWidget {
  final String nodeId;
  const DocumentNodePanel({super.key, required this.nodeId});

  @override
  State<DocumentNodePanel> createState() => _DocumentNodePanelState();
}

class _DocumentNodePanelState extends State<DocumentNodePanel> {
  late TextEditingController _ctrl;
  late TextEditingController _briefCtrl;
  List<dynamic> _comments = [];
  bool _isLoading = false;
  bool _hasFetched = false;

  @override
  void initState() {
    super.initState();
    final graphState = context.read<GraphState>();
    final node = graphState.nodes[widget.nodeId];
    _ctrl = TextEditingController(text: node?.content ?? "");
    _briefCtrl = TextEditingController(text: node?.ollamaPrompt ?? "");
    if (_ctrl.text.isNotEmpty) _fetchComments();
  }

  @override
  void didUpdateWidget(covariant DocumentNodePanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.nodeId != widget.nodeId) {
      final graphState = context.read<GraphState>();
      final node = graphState.nodes[widget.nodeId];
      _ctrl.text = node?.content ?? "";
      _briefCtrl.text = node?.ollamaPrompt ?? "";
      _comments.clear();
      _hasFetched = false;
      if (_ctrl.text.isNotEmpty) _fetchComments();
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _briefCtrl.dispose();
    super.dispose();
  }

  void _fetchComments() async {
    final docIdStr = _ctrl.text.trim();
    if (docIdStr.isEmpty) return;

    setState(() { _isLoading = true; _hasFetched = true; });
    
    final networkState = context.read<NetworkState>();

    try {
      // Use the authenticated service method instead of a raw HTTP call
      final comments = await networkState.redleafService.fetchCommentsForDocument(docIdStr);
      
      if (mounted) {
        setState(() { 
          _comments = comments; 
        });
      }
    } catch (e) {
      debugPrint("Failed to fetch comments: $e");
    } finally {
      if (mounted) setState(() { _isLoading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final graphState = context.watch<GraphState>();
    final networkState = context.watch<NetworkState>();
    final node = graphState.nodes[widget.nodeId];
    if (node == null) return const SizedBox.shrink();

    return Container(
      color: const Color(0xFF1A1A1A), 
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text("REDLEAF DOCUMENT READER", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, letterSpacing: 1.5)),
          const SizedBox(height: 20),
          
          TextField(
            controller: _ctrl, 
            decoration: InputDecoration(
              filled: true, 
              fillColor: const Color(0xFF222222), 
              hintText: "Enter Doc ID (e.g. 12)",
              suffixIcon: IconButton(
                icon: const Icon(Icons.download, color: Colors.white), 
                onPressed: _fetchComments,
                tooltip: "Fetch Comments",
              )
            ),
            onChanged: (v) => graphState.updateNodeContent(widget.nodeId, v),
            onSubmitted: (_) => _fetchComments(),
          ),
          
          const SizedBox(height: 20),
          const Text("Document Brief (Context for AI):", style: TextStyle(color: Colors.white70, fontWeight: FontWeight.bold)),
          const SizedBox(height: 5),
          TextField(
            controller: _briefCtrl,
            maxLines: 3,
            decoration: const InputDecoration(
              filled: true,
              fillColor: Color(0xFF222222),
              hintText: "e.g., Read this testimony paying special attention to financial contradictions.",
              border: OutlineInputBorder(borderSide: BorderSide.none)
            ),
            onChanged: (v) => graphState.updateOllamaPrompt(widget.nodeId, v),
          ),

          const SizedBox(height: 20),
          const Text("Entities to Track:", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white70)),
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
          Row(
            children: [
              const Text("Document Curation & Comments", style: TextStyle(color: Colors.white70, fontWeight: FontWeight.bold)),
              const Spacer(),
              if (_isLoading) const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
            ],
          ),
          const SizedBox(height: 10),

          Expanded(
            child: _hasFetched && _comments.isEmpty && !_isLoading
              ? const Center(child: Text("No comments found for this document.", style: TextStyle(color: Colors.white54, fontSize: 12)))
              : ListView.separated(
                  itemCount: _comments.length,
                  separatorBuilder: (ctx, i) => const SizedBox(height: 8),
                  itemBuilder: (ctx, index) {
                    final comment = _comments[index];
                    final isPinned = node.pinnedComments.any((p) => p['id'] == comment['id']);
                    final pinnedData = isPinned ? node.pinnedComments.firstWhere((p) => p['id'] == comment['id']) : null;
                    
                    return Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: isPinned ? const Color(0xFF332D15) : const Color(0xFF252525),
                        border: Border.all(color: isPinned ? Colors.amber : Colors.white24),
                        borderRadius: BorderRadius.circular(8)
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(comment['username'] ?? "User", style: const TextStyle(color: Colors.amber, fontWeight: FontWeight.bold, fontSize: 12)),
                                    const SizedBox(height: 4),
                                    SelectableText(comment['comment_text'] ?? "", style: const TextStyle(color: Colors.white70, fontSize: 12, height: 1.4)),
                                  ],
                                ),
                              ),
                              IconButton(
                                icon: Icon(isPinned ? Icons.push_pin : Icons.push_pin_outlined, color: isPinned ? Colors.amber : Colors.white54, size: 20),
                                onPressed: () => graphState.togglePinnedComment(widget.nodeId, comment),
                              )
                            ],
                          ),
                          
                          // --- THE NEW CONTEXT CHECKBOXES ---
                          if (isPinned) ...[
                            const SizedBox(height: 10),
                            const Divider(color: Colors.white24, height: 1),
                            const SizedBox(height: 5),
                            const Text("How should the AI interpret this?", style: TextStyle(color: Colors.white54, fontSize: 11)),
                            Theme(
                              data: ThemeData(unselectedWidgetColor: Colors.grey),
                              child: Column(
                                children: [
                                  _buildCheckbox("Direct quote pulled from document", pinnedData!['is_quote'] ?? false, (val) => graphState.updatePinnedCommentContext(widget.nodeId, comment['id'], 'is_quote', val!)),
                                  _buildCheckbox("Research commentary", pinnedData!['is_commentary'] ?? false, (val) => graphState.updatePinnedCommentContext(widget.nodeId, comment['id'], 'is_commentary', val!)),
                                  _buildCheckbox("Refers directly to document", pinnedData!['refers_to_doc'] ?? false, (val) => graphState.updatePinnedCommentContext(widget.nodeId, comment['id'], 'refers_to_doc', val!)),
                                ],
                              ),
                            )
                          ]
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

  Widget _buildCheckbox(String label, bool value, void Function(bool?) onChanged) {
    return SizedBox(
      height: 28,
      child: CheckboxListTile(
        title: Text(label, style: const TextStyle(fontSize: 11, color: Colors.white70)),
        contentPadding: EdgeInsets.zero,
        controlAffinity: ListTileControlAffinity.leading,
        activeColor: Colors.amber,
        checkColor: Colors.black,
        value: value,
        onChanged: onChanged,
        dense: true,
      ),
    );
  }
}