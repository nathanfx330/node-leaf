// --- File: lib/ui/dialogs/node_search_dialog.dart ---
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../constants.dart';

class NodeDef {
  final NodeType type;
  final String name;
  final IconData icon;
  final Color color;

  const NodeDef(this.type, this.name, this.icon, this.color);
}

// Centralized list matching the display titles and icons used in the canvas
const List<NodeDef> kAllNodes = [
  NodeDef(NodeType.scene, "Scratchpad", Icons.note_add, Colors.white),
  NodeDef(NodeType.search, "Global Search", Icons.search, Colors.lightBlueAccent),
  NodeDef(NodeType.document, "Document Reader", Icons.description, Colors.orangeAccent),
  NodeDef(NodeType.relationship, "Graph Relationship", Icons.hub, Colors.pinkAccent),
  NodeDef(NodeType.catalog, "Catalog Reader", Icons.folder_special, Colors.tealAccent),
  NodeDef(NodeType.intersection, "Co-Mentions", Icons.my_location, Colors.greenAccent),
  NodeDef(NodeType.briefing, "System Briefing", Icons.map, Colors.amberAccent),
  NodeDef(NodeType.persona, "Agent Persona", Icons.theater_comedy, Colors.blueGrey),
  NodeDef(NodeType.wikiReader, "Wiki Reader", Icons.menu_book, Colors.lightBlueAccent),
  NodeDef(NodeType.study, "Deep Study (Geek Out)", Icons.school, Colors.deepPurpleAccent),
  NodeDef(NodeType.summarize, "Summarizer (Simple)", Icons.format_align_left, Colors.orange),
  NodeDef(NodeType.output, "Ollama Output", Icons.auto_awesome, Colors.purpleAccent),
  NodeDef(NodeType.chat, "Ollama Chat", Icons.forum, Colors.greenAccent),
  NodeDef(NodeType.wikiWriter, "Wiki Writer", Icons.edit_document, Colors.deepOrangeAccent),
  NodeDef(NodeType.council, "Wiki Council", Icons.account_balance, Colors.amberAccent),
  NodeDef(NodeType.researchParty, "Research Party", Icons.explore, Colors.tealAccent),
  NodeDef(NodeType.merge, "Merge Context", Icons.mediation, Colors.yellowAccent),
];

class NodeSearchDialog extends StatefulWidget {
  const NodeSearchDialog({super.key});

  @override
  State<NodeSearchDialog> createState() => _NodeSearchDialogState();
}

class _NodeSearchDialogState extends State<NodeSearchDialog> {
  final TextEditingController _ctrl = TextEditingController();
  final ScrollController _scrollCtrl = ScrollController();
  final FocusNode _focusNode = FocusNode();
  
  List<NodeDef> _filtered = kAllNodes;
  int _selectedIndex = 0;

  @override
  void initState() {
    super.initState();
    _focusNode.requestFocus();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _scrollCtrl.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _filter(String q) {
    setState(() {
      if (q.isEmpty) {
        _filtered = kAllNodes;
      } else {
        _filtered = kAllNodes
            .where((n) => n.name.toLowerCase().contains(q.toLowerCase()))
            .toList();
      }
      _selectedIndex = 0;
    });
    if (_scrollCtrl.hasClients) _scrollCtrl.jumpTo(0);
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is KeyDownEvent) {
      if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
        setState(() {
          _selectedIndex = (_selectedIndex + 1).clamp(0, _filtered.length - 1);
        });
        _scrollToSelected();
        return KeyEventResult.handled;
      } else if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
        setState(() {
          _selectedIndex = (_selectedIndex - 1).clamp(0, _filtered.length - 1);
        });
        _scrollToSelected();
        return KeyEventResult.handled;
      } else if (event.logicalKey == LogicalKeyboardKey.enter) {
        if (_filtered.isNotEmpty) {
          Navigator.pop(context, _filtered[_selectedIndex].type);
        }
        return KeyEventResult.handled;
      }
    }
    return KeyEventResult.ignored;
  }

  void _scrollToSelected() {
    if (!_scrollCtrl.hasClients) return;
    const double itemHeight = 50.0; 
    final double offset = _selectedIndex * itemHeight;
    final double currentScroll = _scrollCtrl.offset;
    final double viewportHeight = _scrollCtrl.position.viewportDimension;

    if (offset < currentScroll) {
      _scrollCtrl.jumpTo(offset);
    } else if (offset + itemHeight > currentScroll + viewportHeight) {
      _scrollCtrl.jumpTo(offset + itemHeight - viewportHeight);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      alignment: Alignment.center,
      child: Container(
        width: 320,
        decoration: BoxDecoration(
          color: kNodeBg,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white24, width: 1),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.6), 
              blurRadius: 20, 
              offset: const Offset(0, 10)
            )
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
              child: Focus(
                onKeyEvent: _handleKeyEvent,
                child: TextField(
                  controller: _ctrl,
                  focusNode: _focusNode,
                  style: const TextStyle(color: Colors.white, fontSize: 16),
                  decoration: const InputDecoration(
                    hintText: "Search nodes...",
                    hintStyle: TextStyle(color: Colors.white54),
                    border: InputBorder.none,
                    icon: Icon(Icons.search, color: Colors.white54),
                  ),
                  onChanged: _filter,
                ),
              ),
            ),
            const Divider(height: 1, color: Colors.white24),
            Container(
              constraints: const BoxConstraints(maxHeight: 300),
              child: _filtered.isEmpty
                  ? const Padding(
                      padding: EdgeInsets.all(16.0),
                      child: Text("No nodes found.", style: TextStyle(color: Colors.white54)),
                    )
                  : ListView.builder(
                      controller: _scrollCtrl,
                      shrinkWrap: true,
                      itemCount: _filtered.length,
                      itemExtent: 50.0, // Fixed height for exact scrolling math
                      itemBuilder: (ctx, i) {
                        final nodeDef = _filtered[i];
                        final isSelected = i == _selectedIndex;
                        return MouseRegion(
                          onEnter: (_) => setState(() => _selectedIndex = i),
                          child: GestureDetector(
                            onTap: () => Navigator.pop(context, nodeDef.type),
                            child: Container(
                              color: isSelected ? kAccentColor.withOpacity(0.8) : Colors.transparent,
                              padding: const EdgeInsets.symmetric(horizontal: 16.0),
                              alignment: Alignment.centerLeft,
                              child: Row(
                                children: [
                                  Icon(nodeDef.icon, color: nodeDef.color, size: 20),
                                  const SizedBox(width: 12),
                                  Text(
                                    nodeDef.name,
                                    style: TextStyle(
                                      color: isSelected ? Colors.white : Colors.white70,
                                      fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}