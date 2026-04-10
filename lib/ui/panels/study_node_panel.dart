// --- File: lib/ui/panels/study_node_panel.dart ---
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../constants.dart';
import '../../state/graph_state.dart';
import '../../state/network_state.dart';
import '../side_panel.dart'; // Needed for parseRichText

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