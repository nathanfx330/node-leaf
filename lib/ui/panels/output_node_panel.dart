// --- File: lib/ui/panels/output_node_panel.dart ---
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../state/graph_state.dart';
import '../../state/network_state.dart';
import '../side_panel.dart'; // Needed for parseRichText & PreviewPanel

class OutputNodePanel extends StatelessWidget {
  final String nodeId;
  const OutputNodePanel({super.key, required this.nodeId});

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
              Tab(icon: Icon(Icons.auto_awesome), text: "Execution"),
            ],
          ),
          Expanded(
            child: TabBarView(
              children: [
                PreviewPanel(targetNodeId: nodeId),
                _OllamaInterface(nodeId: nodeId), 
              ],
            ),
          )
        ],
      ),
    );
  }
}

class _OllamaInterface extends StatefulWidget {
  final String nodeId;
  const _OllamaInterface({required this.nodeId});
  @override
  State<_OllamaInterface> createState() => _OllamaInterfaceState();
}

class _OllamaInterfaceState extends State<_OllamaInterface> {
  late TextEditingController _promptCtrl;

  @override
  void initState() {
    super.initState();
    final graphState = context.read<GraphState>();
    final initialPrompt = graphState.nodes[widget.nodeId]?.ollamaPrompt ?? "";
    _promptCtrl = TextEditingController(text: initialPrompt.isEmpty ? "Synthesize the following context." : initialPrompt);
  }

  @override
  void dispose() { _promptCtrl.dispose(); super.dispose(); }

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
          const Text("OLLAMA SYSTEM INSTRUCTION", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
          const SizedBox(height: 10),
          TextField(
            controller: _promptCtrl, maxLines: 3,
            decoration: const InputDecoration(filled: true, fillColor: Color(0xFF222222), border: OutlineInputBorder(borderSide: BorderSide.none), hintText: "E.g., Act as a factual researcher..."),
            onChanged: (val) => graphState.updateOllamaPrompt(widget.nodeId, val),
          ),
          const SizedBox(height: 10),
          
          Theme(
            data: ThemeData(unselectedWidgetColor: Colors.grey),
            child: CheckboxListTile(
              title: const Text("Raw Output Only (No AI filler)", style: TextStyle(fontSize: 12, color: Colors.white70)),
              contentPadding: EdgeInsets.zero, controlAffinity: ListTileControlAffinity.leading, activeColor: Colors.white, checkColor: Colors.black,
              value: node.ollamaNoBacktalk, onChanged: (val) { if (val != null) graphState.toggleOllamaBacktalk(widget.nodeId, val); },
            ),
          ),
          
          Theme(
            data: ThemeData(unselectedWidgetColor: Colors.grey),
            child: CheckboxListTile(
              title: const Text("Autonomous Redleaf Research", style: TextStyle(fontSize: 12, color: Colors.white70)),
              subtitle: const Text("AI will auto-search Redleaf for terms found in your prompt before generating.", style: TextStyle(fontSize: 10, color: Colors.white54)),
              contentPadding: EdgeInsets.zero, controlAffinity: ListTileControlAffinity.leading, activeColor: Colors.white, checkColor: Colors.black,
              value: node.enableAutonomousResearch, onChanged: (val) { if (val != null) graphState.toggleAutonomousResearch(widget.nodeId, val); },
            ),
          ),

          const SizedBox(height: 15),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF333333), foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 16), side: const BorderSide(color: Colors.white54)),
              icon: isThisGenerating ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)) : const Icon(Icons.auto_awesome),
              label: Text(isThisGenerating ? "GENERATING..." : "RUN (${networkState.ollamaModel})"),
              onPressed: networkState.isGeneratingOllama ? null : () {
                final sequence = graphState.getCompiledNodes(widget.nodeId);
                networkState.triggerOllamaGeneration(node, sequence, graphState); 
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
          const Text("RESULT", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
          const SizedBox(height: 10),
          Expanded(
            child: Container(
              width: double.infinity, padding: const EdgeInsets.all(15),
              decoration: BoxDecoration(color: const Color(0xFF111111), borderRadius: BorderRadius.circular(8)),
              child: SingleChildScrollView(
                child: SelectableText.rich(
                  node.ollamaResult.isEmpty 
                      ? const TextSpan(text: "Output will appear here...", style: TextStyle(color: Colors.grey))
                      : parseRichText(node.ollamaResult, networkState.redleafService.apiUrl),
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
              icon: const Icon(Icons.turn_right), label: const Text("Promote to Scratchpad"),
              onPressed: node.ollamaResult.isEmpty || networkState.isGeneratingOllama ? null : () => graphState.promoteOutputToScratchpad(node.id),
            ),
          )
        ],
      ),
    );
  }
}