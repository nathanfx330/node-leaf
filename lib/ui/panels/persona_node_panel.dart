// --- File: lib/ui/panels/persona_node_panel.dart ---
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../state/graph_state.dart';

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