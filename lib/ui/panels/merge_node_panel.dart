// --- File: lib/ui/panels/merge_node_panel.dart ---
import 'package:flutter/material.dart';

class MergeNodePanel extends StatelessWidget {
  final String nodeId;
  const MergeNodePanel({super.key, required this.nodeId});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF1A1A1A), padding: const EdgeInsets.all(20),
      child: const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text("MERGE CONTEXT", style: TextStyle(color: Colors.yellowAccent, fontWeight: FontWeight.bold, letterSpacing: 1.5)),
        SizedBox(height: 20),
        Text("Combines multiple parallel branches into a single linear flow.", style: TextStyle(color: Colors.white70, fontSize: 13, height: 1.4)),
        SizedBox(height: 10),
        Text("This allows you to research different topics in separate vertical columns, and merge all their context together before feeding it to a final Agent or Output node.", style: TextStyle(color: Colors.grey, fontSize: 12, height: 1.4))
      ])
    );
  }
}