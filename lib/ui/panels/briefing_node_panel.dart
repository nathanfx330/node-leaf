// --- File: lib/ui/panels/briefing_node_panel.dart ---
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../state/graph_state.dart';
import '../../state/network_state.dart';

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