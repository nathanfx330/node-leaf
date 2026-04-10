// --- File: lib/ui/panels/catalog_node_panel.dart ---
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../state/graph_state.dart';
import '../../state/network_state.dart';

class CatalogNodePanel extends StatefulWidget {
  final String nodeId;
  const CatalogNodePanel({super.key, required this.nodeId});
  @override 
  State<CatalogNodePanel> createState() => _CatalogNodePanelState();
}

class _CatalogNodePanelState extends State<CatalogNodePanel> {
  List<Map<String, dynamic>> _catalogs = [];
  bool _isLoading = true;

  @override 
  void initState() { 
    super.initState(); 
    _fetchCatalogs(); 
  }

  void _fetchCatalogs() async {
    final networkState = context.read<NetworkState>();
    final cats = await networkState.redleafService.fetchAllCatalogs();
    if (mounted) setState(() { _catalogs = cats; _isLoading = false; });
  }

  @override 
  Widget build(BuildContext context) {
    final graphState = context.watch<GraphState>();
    final node = graphState.nodes[widget.nodeId];
    
    return Container(
      color: const Color(0xFF1A1A1A), padding: const EdgeInsets.all(20),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text("REDLEAF CATALOG READER", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, letterSpacing: 1.5)),
        const SizedBox(height: 20),
        const Text("Select Collection:", style: TextStyle(color: Colors.white54, fontSize: 12)),
        const SizedBox(height: 5),
        if (_isLoading) const CircularProgressIndicator(color: Colors.white)
        else DropdownButton<String>(
          isExpanded: true,
          hint: const Text("Select a Catalog", style: TextStyle(color: Colors.white54)),
          value: node?.content.isEmpty == true ? null : node?.content,
          dropdownColor: const Color(0xFF333333),
          items: _catalogs.map((c) => DropdownMenuItem(value: c['id'].toString(), child: Text(c['name'], style: const TextStyle(color: Colors.white)))).toList(),
          onChanged: (v) {
            if (v != null) {
              graphState.updateNodeContent(widget.nodeId, v);
              graphState.updateNodeTitle(widget.nodeId, _catalogs.firstWhere((c) => c['id'].toString() == v)['name']);
            }
          },
        ),
        const SizedBox(height: 20),
        const Text("Extracts the context of documents in this collection for summarization tasks.", style: TextStyle(color: Colors.grey, fontSize: 12))
      ])
    );
  }
}