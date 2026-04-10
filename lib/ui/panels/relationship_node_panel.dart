// --- File: lib/ui/panels/relationship_node_panel.dart ---
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../constants.dart';
import '../../state/graph_state.dart';
import '../../state/network_state.dart';
import '../side_panel.dart'; // Needed for EntitySearchDialog

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