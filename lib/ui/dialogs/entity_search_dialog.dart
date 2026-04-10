// --- File: lib/ui/dialogs/entity_search_dialog.dart ---
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import '../../constants.dart';
import '../../models/node_models.dart';
import '../../state/graph_state.dart';
import '../../state/network_state.dart';

class EntitySearchDialog extends StatefulWidget {
  final String nodeId;
  const EntitySearchDialog({super.key, required this.nodeId});
  @override
  State<EntitySearchDialog> createState() => _EntitySearchDialogState();
}

class _EntitySearchDialogState extends State<EntitySearchDialog> {
  final TextEditingController _ctrl = TextEditingController();
  List<Map<String, dynamic>> _results = [];
  bool _isSearching = false;

  void _search() async {
    if (_ctrl.text.isEmpty) return;
    setState(() { _isSearching = true; _results = []; });
    
    final networkState = context.read<NetworkState>();
    final data = await networkState.redleafService.searchEntities(_ctrl.text);
    
    if (mounted) setState(() { _results = data; _isSearching = false; });
  }

  @override
  Widget build(BuildContext context) {
    final networkState = context.read<NetworkState>();
    final graphState = context.read<GraphState>();

    return AlertDialog(
      backgroundColor: kNodeBg,
      title: const Text("Search Redleaf spaCy Index", style: TextStyle(color: Colors.white)),
      content: SizedBox(
        width: 400, height: 400,
        child: Column(
          children: [
            TextField(
              controller: _ctrl, autofocus: true,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: "Enter a person, place, or topic...", 
                hintStyle: const TextStyle(color: Colors.white54),
                filled: true, fillColor: Colors.black26,
                suffixIcon: IconButton(icon: const Icon(Icons.search, color: Colors.white), onPressed: _search),
              ),
              onSubmitted: (_) => _search(),
            ),
            const SizedBox(height: 10),
            if (_isSearching) const Center(child: CircularProgressIndicator(color: Colors.white))
            else if (_results.isEmpty && _ctrl.text.isNotEmpty) const Center(child: Text("No matching entities found.", style: TextStyle(color: Colors.white54)))
            else Expanded(
              child: ListView.builder(
                itemCount: _results.length,
                itemBuilder: (ctx, i) {
                  final item = _results[i];
                  return ListTile(
                    title: Text(item['text'], style: const TextStyle(color: Colors.white)),
                    subtitle: Text("${item['label']} - Mentions: ${item['count']}", style: const TextStyle(color: Colors.white54)),
                    onTap: () async {
                      final id = await networkState.redleafService.extractEntityId(item['label'], item['text']);
                      if (id != null) {
                        graphState.addPillToNode(widget.nodeId, RedleafPill(id: const Uuid().v4(), entityId: id, text: item['text'], label: item['label']));
                        if (mounted) Navigator.pop(context);
                      } else {
                        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Failed to resolve Entity ID.")));
                      }
                    },
                  );
                },
              ),
            )
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text("Cancel", style: TextStyle(color: Colors.white))),
      ]
    );
  }
}