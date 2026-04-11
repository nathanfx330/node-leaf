// --- File: lib/ui/panels/research_party_node_panel.dart ---
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../constants.dart';
import '../../state/graph_state.dart';
import '../../state/network_state.dart';
import '../side_panel.dart'; 

class ResearchPartyNodePanel extends StatefulWidget {
  final String nodeId;
  const ResearchPartyNodePanel({super.key, required this.nodeId});

  @override
  State<ResearchPartyNodePanel> createState() => _ResearchPartyNodePanelState();
}

class _ResearchPartyNodePanelState extends State<ResearchPartyNodePanel> {
  late TextEditingController _directiveCtrl;

  @override
  void initState() {
    super.initState();
    final graphState = context.read<GraphState>();
    _directiveCtrl = TextEditingController(text: graphState.nodes[widget.nodeId]?.content ?? "");
  }

  @override
  void didUpdateWidget(covariant ResearchPartyNodePanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.nodeId != widget.nodeId) {
      final graphState = context.read<GraphState>();
      _directiveCtrl.text = graphState.nodes[widget.nodeId]?.content ?? "";
    }
  }

  @override
  void dispose() {
    _directiveCtrl.dispose();
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
              Icon(Icons.explore, color: Colors.tealAccent, size: 20),
              SizedBox(width: 10),
              Text("RESEARCH PARTY", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white, letterSpacing: 1.5)),
            ],
          ),
          const SizedBox(height: 10),
          const Text("Deploys an exploratory party of agents. They read your current Wiki to map the landscape, but treat it as unverified rumor. They will independently select paths, forage the Redleaf Database for hard primary-source evidence, and return to camp with a fully grounded intelligence report.", style: TextStyle(color: Colors.white54, fontSize: 12)),
          const SizedBox(height: 20),

          const Text("Expedition Directive (Optional Domain):", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white70)),
          const SizedBox(height: 5),
          TextField(
            controller: _directiveCtrl,
            decoration: const InputDecoration(filled: true, fillColor: Color(0xFF222222), border: OutlineInputBorder(borderSide: BorderSide.none), hintText: "E.g., Explore the 1980s Tech Boom"),
            onChanged: (val) => graphState.updateNodeContent(widget.nodeId, val),
          ),
          const SizedBox(height: 15),

          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.teal.shade800, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 16)),
              icon: isThisGenerating ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)) : const Icon(Icons.hiking),
              label: Text(isThisGenerating ? "EXPEDITION IN PROGRESS..." : "SEND OUT PARTY"),
              onPressed: networkState.isGeneratingOllama ? null : () {
                final sequence = graphState.getCompiledNodes(widget.nodeId);
                networkState.triggerResearchPartyLoop(node, sequence, graphState); 
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
                label: const Text("RECALL PARTY NOW"),
                onPressed: () => networkState.forceAnswerNow(),
              ),
            ),
          ],
          
          const SizedBox(height: 20),
          const Text("CAMPFIRE REPORT", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
          const SizedBox(height: 10),
          Expanded(
            child: Container(
              width: double.infinity, padding: const EdgeInsets.all(15),
              decoration: BoxDecoration(color: const Color(0xFF111111), borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.white12)),
              child: SingleChildScrollView(
                child: SelectableText.rich(
                  node.ollamaResult.isEmpty 
                      ? const TextSpan(text: "Agent logs and final report will appear here...", style: TextStyle(color: Colors.grey))
                      : parseRichText(
                          node.ollamaResult, 
                          networkState.redleafService.apiUrl,
                          graphState: graphState,
                          networkState: networkState,
                          context: context,
                          currentNodeId: widget.nodeId
                        ),
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
              icon: const Icon(Icons.turn_right), label: const Text("Promote Report to Scratchpad"),
              onPressed: node.ollamaResult.isEmpty || networkState.isGeneratingOllama ? null : () {
                String finalReport = node.ollamaResult;
                final marker = "🏕️ Campfire Synthesis: Writing grounded report...\n\n";
                if (finalReport.contains(marker)) {
                  finalReport = finalReport.split(marker).last;
                }
                final originalResult = node.ollamaResult;
                graphState.setNodeOllamaResult(node.id, finalReport.trim());
                graphState.promoteOutputToScratchpad(node.id);
                graphState.setNodeOllamaResult(node.id, originalResult);
              },
            ),
          )
        ],
      ),
    );
  }
}