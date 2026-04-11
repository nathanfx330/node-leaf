// --- File: lib/ui/panels/preview_panel.dart ---
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../constants.dart';
import '../../state/graph_state.dart';
import '../../state/canvas_state.dart';
import '../../state/network_state.dart'; // <-- Needed for apiUrl
import '../side_panel.dart'; // <-- Needed for parseRichText

class PreviewPanel extends StatelessWidget {
  final String? targetNodeId;
  const PreviewPanel({super.key, this.targetNodeId});

  @override
  Widget build(BuildContext context) {
    final graphState = context.watch<GraphState>();
    final canvasState = context.read<CanvasState>();
    final networkState = context.watch<NetworkState>(); // <-- Added
    final nodes = graphState.getCompiledNodes(targetNodeId);

    if (nodes.length <= 1) { 
      return Column(
        children: [
          Container(
            padding: const EdgeInsets.all(15), color: const Color(0xFF222222), width: double.infinity,
            child: const Text("COMPILED DATA", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
          const Expanded(
            child: Center(
              child: Text("No upstream data connected.", style: TextStyle(color: Colors.white54))
            )
          )
        ]
      );
    }

    return Column(
      children:[
        Container(
          padding: const EdgeInsets.all(15), color: const Color(0xFF222222), width: double.infinity,
          child: Row(
            children:[
              const Text("COMPILED DATA", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.copy, size: 20, color: Colors.white70), tooltip: "Copy Text",
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: graphState.getCompiledRawText(nodes)));
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Copied to clipboard!"), duration: Duration(seconds: 2)));
                },
              ),
              if (graphState.previewNodeId != null) 
                IconButton(icon: const Icon(Icons.close, color: Colors.white70), onPressed: () => graphState.setPreviewNode(null))
            ]
          ),
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.all(30), itemCount: nodes.length,
            itemBuilder: (ctx, i) {
              final node = nodes[i];
              if (node.type == NodeType.output || node.type == NodeType.chat || node.type == NodeType.wikiWriter || node.type == NodeType.council) return const SizedBox(height: 50, child: Divider(color: Colors.white24));
              
              final baseStyle = const TextStyle(fontSize: 16, height: 1.6, color: Colors.white70);
              final nodeIndex = graphState.getNodeIndex(node.id);
              final indexPrefix = nodeIndex > 0 ? "#$nodeIndex " : "";

              String displayText = node.content;
              if (node.type == NodeType.wikiReader) {
                displayText = "File: ${node.wikiTitle}.md";
              } else if (node.type == NodeType.study || node.type == NodeType.summarize) {
                displayText = "Task: ${node.content}\n\n[Generated Result]:\n${node.ollamaResult.isEmpty ? 'Not run yet.' : node.ollamaResult}";
              }

              return MouseRegion(
                cursor: SystemMouseCursors.click,
                child: GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onTap: () => canvasState.jumpToNode(node.id, graphState),
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 20.0),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children:[
                      Text((indexPrefix + node.title).toUpperCase(), style: const TextStyle(color: Colors.white, fontSize: 10, letterSpacing: 1.5, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 8),
                      // --- THIS IS THE FIX FOR THE PREVIEW PANEL ---
                      SelectableText.rich(
                        parseRichText(
                          displayText, 
                          networkState.redleafService.apiUrl,
                          graphState: graphState,
                          networkState: networkState,
                          context: context,
                          currentNodeId: node.id
                        ), 
                        style: baseStyle
                      ),
                      if (node.redleafPills.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Text("Attached Context: ${node.redleafPills.map((p) => p.text).join(', ')}", style: const TextStyle(color: Colors.white54, fontSize: 12, fontStyle: FontStyle.italic)),
                      ]
                    ]),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}