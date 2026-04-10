// --- File: lib/ui/panels/global_search_node_panel.dart ---
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../state/graph_state.dart';
import '../../state/network_state.dart';

class GlobalSearchNodePanel extends StatefulWidget {
  final String nodeId;
  const GlobalSearchNodePanel({super.key, required this.nodeId});

  @override
  State<GlobalSearchNodePanel> createState() => _GlobalSearchNodePanelState();
}

class _GlobalSearchNodePanelState extends State<GlobalSearchNodePanel> {
  late TextEditingController _ctrl;
  late TextEditingController _limitCtrl;
  List<Map<String, dynamic>> _results = [];
  bool _isSearching = false;
  bool _hasSearched = false;

  @override
  void initState() {
    super.initState();
    final graphState = context.read<GraphState>();
    final node = graphState.nodes[widget.nodeId];
    _ctrl = TextEditingController(text: node?.content ?? "");
    _limitCtrl = TextEditingController(text: (node?.searchLimit ?? 5).toString());
    if (_ctrl.text.isNotEmpty) _performSearch();
  }

  @override
  void didUpdateWidget(covariant GlobalSearchNodePanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.nodeId != widget.nodeId) {
      final graphState = context.read<GraphState>();
      final node = graphState.nodes[widget.nodeId];
      _ctrl.text = node?.content ?? "";
      _limitCtrl.text = (node?.searchLimit ?? 5).toString();
      _results.clear();
      _hasSearched = false;
      if (_ctrl.text.isNotEmpty) _performSearch();
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _limitCtrl.dispose();
    super.dispose();
  }

  void _performSearch() async {
    if (_ctrl.text.isEmpty) return;
    setState(() { _isSearching = true; _hasSearched = true; });
    
    final graphState = context.read<GraphState>();
    final networkState = context.read<NetworkState>();
    
    // Save content to the node
    graphState.updateNodeContent(widget.nodeId, _ctrl.text);
    
    final results = await networkState.redleafService.fetchFtsResultsUI(_ctrl.text);
    if (mounted) {
      setState(() { _isSearching = false; _results = results; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final graphState = context.watch<GraphState>(); // Use watch to rebuild on pins
    final networkState = context.watch<NetworkState>(); // To get API URL for links
    final node = graphState.nodes[widget.nodeId];
    if (node == null) return const SizedBox.shrink();

    // Compile display list: Pinned items first, then unpinned search results
    List<Map<String, dynamic>> displayList = [];
    for (var p in node.pinnedSearchResults) {
      displayList.add({...p, 'isPinned': true});
    }
    for (var r in _results) {
      bool isAlreadyPinned = node.pinnedSearchResults.any((p) => p['title'] == r['title'] && p['snippet'] == r['snippet']);
      if (!isAlreadyPinned) {
        displayList.add({...r, 'isPinned': false});
      }
    }

    return Container(
      color: const Color(0xFF1A1A1A), padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text("REDLEAF GLOBAL SEARCH", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, letterSpacing: 1.5)),
          const SizedBox(height: 20),
          
          TextField(
            controller: _ctrl, 
            decoration: InputDecoration(
              filled: true, fillColor: const Color(0xFF222222), 
              hintText: "e.g. Security Protocols",
              suffixIcon: IconButton(
                icon: const Icon(Icons.search, color: Colors.white),
                onPressed: _performSearch,
              )
            ),
            onChanged: (v) => graphState.updateNodeContent(widget.nodeId, v),
            onSubmitted: (_) => _performSearch(),
          ),
          const SizedBox(height: 15),
          
          Row(
            children: [
              const Icon(Icons.tune, color: Colors.white54, size: 16),
              const SizedBox(width: 8),
              const Text("Auto-feed top ", style: TextStyle(color: Colors.white70, fontSize: 13)),
              SizedBox(
                width: 45,
                child: TextField(
                  controller: _limitCtrl,
                  keyboardType: TextInputType.number,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 13, color: Colors.white, fontWeight: FontWeight.bold),
                  decoration: const InputDecoration(
                    isDense: true, contentPadding: EdgeInsets.symmetric(vertical: 4),
                    filled: true, fillColor: Color(0xFF333333), border: OutlineInputBorder(borderSide: BorderSide.none)
                  ),
                  onChanged: (val) {
                    final limit = int.tryParse(val);
                    if (limit != null && limit > 0) graphState.updateSearchLimit(widget.nodeId, limit);
                  },
                ),
              ),
              const Text(" results + pinned", style: TextStyle(color: Colors.white70, fontSize: 13)),
            ],
          ),

          const SizedBox(height: 20),
          Row(
            children: [
              const Text("Preview & Pin Results", style: TextStyle(color: Colors.white70, fontWeight: FontWeight.bold)),
              const Spacer(),
              if (_isSearching) const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
            ],
          ),
          const SizedBox(height: 10),

          Expanded(
            child: _hasSearched && displayList.isEmpty && !_isSearching
              ? const Center(child: Text("No results found in Redleaf DB.", style: TextStyle(color: Colors.white54, fontSize: 12)))
              : ListView.separated(
                  itemCount: displayList.length,
                  separatorBuilder: (ctx, i) => const SizedBox(height: 8),
                  itemBuilder: (ctx, index) {
                    final item = displayList[index];
                    final bool isError = item['isError'] == true;
                    final bool isPinned = item['isPinned'] == true;
                    
                    return Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: isError ? Colors.red.withOpacity(0.1) : (isPinned ? const Color(0xFF332D15) : const Color(0xFF252525)),
                        border: Border.all(color: isError ? Colors.red : (isPinned ? Colors.amber : Colors.white24)),
                        borderRadius: BorderRadius.circular(8)
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                MouseRegion(
                                  cursor: isError ? SystemMouseCursors.basic : SystemMouseCursors.click,
                                  child: GestureDetector(
                                    onTap: () async {
                                      if (isError) return;
                                      final docId = item['doc_id'];
                                      final pageNum = item['page_number'];
                                      final baseUrl = networkState.redleafService.apiUrl;
                                      final url = Uri.parse('$baseUrl/document/$docId#page=$pageNum');
                                      if (await canLaunchUrl(url)) {
                                        await launchUrl(url);
                                      } else {
                                        debugPrint('Could not launch $url');
                                      }
                                    },
                                    child: Text(
                                      item['title'] ?? "Unknown", 
                                      style: TextStyle(
                                        color: isError ? Colors.redAccent : (isPinned ? Colors.amber : Colors.lightBlueAccent), 
                                        fontWeight: FontWeight.bold, 
                                        fontSize: 13,
                                        decoration: isError ? TextDecoration.none : TextDecoration.underline,
                                      )
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 6),
                                SelectableText(
                                  item['snippet'] ?? "", 
                                  style: TextStyle(color: isError ? Colors.white : Colors.white70, fontSize: 12, height: 1.4)
                                ),
                              ],
                            ),
                          ),
                          if (!isError)
                            IconButton(
                              icon: Icon(isPinned ? Icons.push_pin : Icons.push_pin_outlined, color: isPinned ? Colors.amber : Colors.white54, size: 20),
                              onPressed: () {
                                final payload = {
                                  'doc_id': item['doc_id'],
                                  'page_number': item['page_number'],
                                  'title': item['title'],
                                  'snippet': item['snippet']
                                };
                                graphState.togglePinnedSearchResult(widget.nodeId, payload);
                              },
                            )
                        ],
                      ),
                    );
                  },
                ),
          ),
        ]
      )
    );
  }
}