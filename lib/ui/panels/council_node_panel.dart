// --- File: lib/ui/panels/council_node_panel.dart ---
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../constants.dart';
import '../../state/graph_state.dart';
import '../../state/network_state.dart';
import '../side_panel.dart'; // Needed for parseRichText & PreviewPanel

class CouncilNodePanel extends StatelessWidget {
  final String nodeId;
  const CouncilNodePanel({super.key, required this.nodeId});

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
              Tab(icon: Icon(Icons.account_balance), text: "Council"),
            ],
          ),
          Expanded(
            child: TabBarView(
              children: [
                PreviewPanel(targetNodeId: nodeId), 
                _CouncilInterface(nodeId: nodeId),
              ],
            ),
          )
        ],
      ),
    );
  }
}

class _CouncilInterface extends StatefulWidget {
  final String nodeId;
  const _CouncilInterface({required this.nodeId});
  @override
  State<_CouncilInterface> createState() => _CouncilInterfaceState();
}

class _CouncilInterfaceState extends State<_CouncilInterface> {
  late TextEditingController _agentCountCtrl;

  @override
  void initState() {
    super.initState();
    final graphState = context.read<GraphState>();
    final node = graphState.nodes[widget.nodeId];
    _agentCountCtrl = TextEditingController(text: (node?.councilAgentCount ?? 3).toString());
  }

  @override
  void didUpdateWidget(covariant _CouncilInterface oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.nodeId != widget.nodeId) {
      final graphState = context.read<GraphState>();
      final node = graphState.nodes[widget.nodeId];
      _agentCountCtrl.text = (node?.councilAgentCount ?? 3).toString();
    }
  }

  @override
  void dispose() {
    _agentCountCtrl.dispose();
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
              Icon(Icons.account_balance, color: Colors.amberAccent, size: 20),
              SizedBox(width: 10),
              Text("WIKI COUNCIL", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white, letterSpacing: 1.5)),
            ],
          ),
          const SizedBox(height: 10),
          const Text("Analyzes a finished Wiki page against the broader Redleaf Knowledge Graph to identify missing conceptual links, unexplored entities, and unwritten Wiki pages. It maps the completeness of the knowledge graph.", style: TextStyle(color: Colors.white54, fontSize: 12)),
          const SizedBox(height: 20),

          Row(
            children: [
              const Text("Number of Experts:", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white70)),
              const SizedBox(width: 10),
              SizedBox(
                width: 60,
                child: TextField(
                  controller: _agentCountCtrl,
                  keyboardType: TextInputType.number,
                  textAlign: TextAlign.center,
                  decoration: const InputDecoration(
                    filled: true, fillColor: Color(0xFF222222),
                    border: OutlineInputBorder(borderSide: BorderSide.none),
                    isDense: true,
                  ),
                  onChanged: (val) {
                    final count = int.tryParse(val);
                    if (count != null && count > 0) {
                      graphState.updateCouncilAgentCount(widget.nodeId, count);
                    }
                  },
                ),
              ),
            ],
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
                : const Icon(Icons.account_balance),
              label: Text(isThisGenerating ? "CONVENING COUNCIL..." : "CONVENE COUNCIL (${networkState.ollamaModel})"),
              onPressed: networkState.isGeneratingOllama ? null : () {
                final sequence = graphState.getCompiledNodes(widget.nodeId);
                networkState.triggerCouncilGeneration(node, sequence, graphState);
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
                label: const Text("STOP COUNCIL"),
                onPressed: () => networkState.forceAnswerNow(),
              ),
            ),
          ],
          
          const SizedBox(height: 20),
          const Text("COUNCIL AUDIT REPORT", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
          const SizedBox(height: 10),
          Expanded(
            child: Container(
              width: double.infinity, padding: const EdgeInsets.all(15),
              decoration: BoxDecoration(color: const Color(0xFF111111), borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.white12)),
              child: SingleChildScrollView(
                child: SelectableText.rich(
                  node.ollamaResult.isEmpty 
                      ? const TextSpan(text: "Council findings and suggestions will appear here...", style: TextStyle(color: Colors.grey))
                      : parseRichText(node.ollamaResult, networkState.redleafService.apiUrl),
                  style: const TextStyle(color: Colors.white, height: 1.5),
                ),
              ),
            ),
          ),
          
          if (node.ollamaResult.isNotEmpty && !isThisGenerating) ...[
            const SizedBox(height: 10),
            const Text("💡 Use these suggestions to kickstart a new Deep Study node!", style: TextStyle(color: Colors.amberAccent, fontSize: 12, fontStyle: FontStyle.italic))
          ]
        ],
      ),
    );
  }
}