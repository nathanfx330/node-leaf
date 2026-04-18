// --- File: lib/ui/panels/wiki_writer_node_panel.dart ---
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../constants.dart';
import '../../state/graph_state.dart';
import '../../state/network_state.dart';
import '../side_panel.dart'; // Needed for EntitySearchDialog & PreviewPanel

class WikiWriterNodePanel extends StatelessWidget {
  final String nodeId;
  const WikiWriterNodePanel({super.key, required this.nodeId});

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
              Tab(icon: Icon(Icons.edit_document), text: "Wiki Editor"),
            ],
          ),
          Expanded(
            child: TabBarView(
              children: [
                PreviewPanel(targetNodeId: nodeId), 
                _WikiWriterInterface(nodeId: nodeId),
              ],
            ),
          )
        ],
      ),
    );
  }
}

class _WikiWriterInterface extends StatefulWidget {
  final String nodeId;
  const _WikiWriterInterface({required this.nodeId});
  @override
  State<_WikiWriterInterface> createState() => _WikiWriterInterfaceState();
}

class _WikiWriterInterfaceState extends State<_WikiWriterInterface> {
  // --- Persistent height cache across node selections ---
  static final Map<String, double> _savedHeights = {};

  late TextEditingController _titleCtrl;
  
  // --- Chat Controllers ---
  final TextEditingController _msgCtrl = TextEditingController();
  final ScrollController _scrollCtrl = ScrollController();
  
  List<String> _availablePages = [];
  bool _isLoadingPages = true;

  // --- State for history tracking ---
  List<String> _historyFiles = [];
  bool _isLoadingHistory = false;

  // --- State for the resizable output panel ---
  double? _outputPanelHeight;

  @override
  void initState() {
    super.initState();
    final graphState = context.read<GraphState>();
    final node = graphState.nodes[widget.nodeId];
    _titleCtrl = TextEditingController(text: node?.wikiTitle ?? "");
    _outputPanelHeight = _savedHeights[widget.nodeId] ?? 350.0;
    _fetchPages();
    if (_titleCtrl.text.isNotEmpty) _fetchHistory();
  }

  @override
  void didUpdateWidget(covariant _WikiWriterInterface oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.nodeId != widget.nodeId) {
      final graphState = context.read<GraphState>();
      final node = graphState.nodes[widget.nodeId];
      _titleCtrl.text = node?.wikiTitle ?? "";
      
      // Reset height so it pulls the correct saved height for the NEW node
      _outputPanelHeight = null;
      
      _fetchPages();
      if (_titleCtrl.text.isNotEmpty) _fetchHistory();
    }
  }

  @override
  void dispose() { 
    _titleCtrl.dispose();
    _msgCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose(); 
  }

  void _scrollToBottom() {
    if (_scrollCtrl.hasClients) {
      _scrollCtrl.animateTo(_scrollCtrl.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
    }
  }

  void _sendMessage() {
    final text = _msgCtrl.text.trim();
    if (text.isEmpty) return;

    final networkState = context.read<NetworkState>();
    final graphState = context.read<GraphState>();
    
    if (networkState.isGeneratingOllama) return;
    
    final node = graphState.nodes[widget.nodeId]!;
    final sequence = graphState.getCompiledNodes(widget.nodeId);

    _msgCtrl.clear();
    // Re-use the ChatAgent logic to handle the conversation!
    networkState.triggerOllamaChat(node, sequence, text, graphState);

    Future.delayed(const Duration(milliseconds: 100), _scrollToBottom);
  }

  void _fetchPages() async {
    final graphState = context.read<GraphState>();
    final networkState = context.read<NetworkState>();
    final pages = await graphState.listWikiPages(networkState);
    if (mounted) setState(() { _availablePages = pages; _isLoadingPages = false; });
  }

  void _fetchHistory() async {
    setState(() { _isLoadingHistory = true; });
    final graphState = context.read<GraphState>();
    final networkState = context.read<NetworkState>();
    final history = await graphState.getWikiHistory(_titleCtrl.text, networkState);
    if (mounted) setState(() { _historyFiles = history; _isLoadingHistory = false; });
  }

  void _loadCurrentFile() async {
    final title = _titleCtrl.text.trim();
    if (title.isEmpty) return;
    
    final graphState = context.read<GraphState>();
    final networkState = context.read<NetworkState>();
    
    final content = await graphState.readWikiPage(title, networkState);
    graphState.setNodeOllamaResult(widget.nodeId, "=== CURRENT FILE: $title.md ===\n\n$content");
  }

  void _previewBackup(String backupFilename) async {
    final graphState = context.read<GraphState>();
    final networkState = context.read<NetworkState>();
    
    final content = await graphState.readWikiBackup(backupFilename, networkState);
    if (content != null) {
      graphState.setNodeOllamaResult(widget.nodeId, "=== PREVIEWING BACKUP: $backupFilename ===\n\n$content");
    } else {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Failed to load backup preview.")));
    }
  }

  void _showNewPageDialog() {
    final ctrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF333333),
        title: const Text("Create New Wiki Page", style: TextStyle(color: Colors.white)),
        content: TextField(
          controller: ctrl,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(
            hintText: "e.g., Space_Race_Timeline",
            hintStyle: TextStyle(color: Colors.white54),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx), 
            child: const Text("Cancel", style: TextStyle(color: Colors.white54))
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: kAccentColor, foregroundColor: Colors.white),
            onPressed: () {
              // Sanitize input: Replace spaces and special chars with underscores
              String val = ctrl.text.trim().replaceAll(RegExp(r'[\\/:*?"<>| ]'), '_');
              if (val.isNotEmpty) {
                _titleCtrl.text = val;
                final graphState = context.read<GraphState>();
                graphState.updateWikiTitle(widget.nodeId, val);
                graphState.updateNodeTitle(widget.nodeId, "Write: $val");
                _fetchHistory();
                _loadCurrentFile();
              }
              Navigator.pop(ctx);
            },
            child: const Text("Create")
          )
        ]
      )
    );
  }

  Future<bool> _showConfirmDialog(String message) async {
    return await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF333333),
        title: const Text("Confirm Restore", style: TextStyle(color: Colors.amberAccent)),
        content: Text(message, style: const TextStyle(color: Colors.white70)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text("Cancel", style: TextStyle(color: Colors.white54)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.amberAccent, foregroundColor: Colors.black),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text("RESTORE"),
          ),
        ],
      ),
    ) ?? false;
  }

  void _restoreBackup(String backupFilename) async {
    final title = _titleCtrl.text.trim();
    if (title.isEmpty) return;

    final shouldRestore = await _showConfirmDialog('Are you sure you want to overwrite the current Wiki page with this older version?\n\n(The current state will be backed up automatically before the restore).');
    if (!shouldRestore) return;

    final graphState = context.read<GraphState>();
    final networkState = context.read<NetworkState>();

    final backupContent = await graphState.readWikiBackup(backupFilename, networkState);
    
    if (backupContent != null) {
      final success = await graphState.writeWikiPage(title, backupContent, networkState);
      
      if (success && mounted) {
        graphState.setNodeOllamaResult(widget.nodeId, "=== RESTORED SUCCESSFULLY ===\n\n$backupContent");
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Restored previous version successfully.")));
        _fetchHistory(); 
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Failed to restore version.")));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final graphState = context.watch<GraphState>();
    final networkState = context.watch<NetworkState>(); 
    final node = graphState.nodes[widget.nodeId];
    if (node == null) return const SizedBox.shrink();

    final bool isThisGenerating = networkState.isNodeGenerating(widget.nodeId);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients && _scrollCtrl.offset >= _scrollCtrl.position.maxScrollExtent - 50) {
        _scrollToBottom();
      }
    });

    return LayoutBuilder(
      builder: (context, constraints) {
        // Use saved height, or default to 350px
        _outputPanelHeight ??= _savedHeights[widget.nodeId] ?? 350.0;
        
        // Ensure it doesn't overflow if the window is tiny
        if (_outputPanelHeight! > constraints.maxHeight - 20) {
          _outputPanelHeight = constraints.maxHeight - 20;
        }

        return Stack(
          children: [
            // --- BACKGROUND: SCROLLABLE SETTINGS & CHAT ---
            Positioned.fill(
              child: SingleChildScrollView(
                // The bottom padding ensures the user can scroll past the overlay
                padding: EdgeInsets.fromLTRB(20, 20, 20, _outputPanelHeight! + 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.edit_document, color: Colors.deepOrangeAccent, size: 20),
                        SizedBox(width: 10),
                        Text("WIKI WRITER", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white, letterSpacing: 1.5)),
                      ],
                    ),
                    const SizedBox(height: 10),
                    const Text("Discuss changes with the editor below. When you are ready, execute the rewrite to permanently update the markdown file.", style: TextStyle(color: Colors.white54, fontSize: 12)),
                    const SizedBox(height: 20),

                    // --- REQ 1: Target File Name (Read-Only + New Button) ---
                    const Text("Target File Name:", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white70)),
                    const SizedBox(height: 5),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _titleCtrl,
                            readOnly: true, // Prevents spelling mistakes
                            decoration: const InputDecoration(
                              filled: true, fillColor: Color(0xFF222222), 
                              border: OutlineInputBorder(borderSide: BorderSide.none), 
                              hintText: "Select below or create new..."
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF333333), 
                            foregroundColor: Colors.white, 
                            padding: const EdgeInsets.symmetric(vertical: 16)
                          ),
                          onPressed: _showNewPageDialog,
                          child: const Text("➕ New Page"),
                        )
                      ],
                    ),
                    const SizedBox(height: 10),

                    // --- DIRECTORY BROWSER ---
                    Theme(
                      data: ThemeData(unselectedWidgetColor: Colors.grey, dividerColor: Colors.transparent),
                      child: ExpansionTile(
                        tilePadding: EdgeInsets.zero,
                        title: Text("Browse Directory (${_availablePages.length} files)", style: const TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.bold)),
                        children: [
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(color: const Color(0xFF222222), borderRadius: BorderRadius.circular(8)),
                            child: _isLoadingPages 
                              ? const Text("Scanning folder...", style: TextStyle(color: Colors.white54, fontSize: 12))
                              : _availablePages.isEmpty 
                                ? const Text("No wiki pages found.", style: TextStyle(color: Colors.white54, fontSize: 12))
                                : Wrap(
                                    spacing: 8, runSpacing: 8,
                                    children: _availablePages.map((page) => ActionChip(
                                      backgroundColor: const Color(0xFF333333),
                                      side: BorderSide.none,
                                      label: Text(page, style: const TextStyle(color: Colors.white70, fontSize: 12)),
                                      onPressed: () {
                                        _titleCtrl.text = page;
                                        graphState.updateWikiTitle(widget.nodeId, page);
                                        graphState.updateNodeTitle(widget.nodeId, "Write: $page");
                                        _fetchHistory();
                                        _loadCurrentFile(); // Auto-load content to preview
                                      },
                                    )).toList(),
                                  ),
                          )
                        ],
                      ),
                    ),
                    
                    // --- VERSION HISTORY ACCORDION ---
                    if (_titleCtrl.text.isNotEmpty)
                      Theme(
                        data: ThemeData(unselectedWidgetColor: Colors.grey, dividerColor: Colors.transparent),
                        child: ExpansionTile(
                          tilePadding: EdgeInsets.zero,
                          title: Text("Version History (${_historyFiles.length} backups)", style: const TextStyle(color: Colors.amberAccent, fontSize: 12, fontWeight: FontWeight.bold)),
                          children: [
                            Container(
                              width: double.infinity,
                              constraints: const BoxConstraints(maxHeight: 150),
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(color: const Color(0xFF222222), borderRadius: BorderRadius.circular(8)),
                              child: _isLoadingHistory 
                                ? const Text("Scanning history...", style: TextStyle(color: Colors.white54, fontSize: 12))
                                : _historyFiles.isEmpty 
                                  ? const Text("No previous versions found for this file.", style: TextStyle(color: Colors.white54, fontSize: 12))
                                  : ListView.builder(
                                      shrinkWrap: true,
                                      itemCount: _historyFiles.length,
                                      itemBuilder: (ctx, i) {
                                        final filename = _historyFiles[i];
                                        final parts = filename.split('_');
                                        final timeStr = parts.length > 2 ? parts.last.replaceAll('.md', '') : 'Unknown Time';
                                        
                                        return Padding(
                                          padding: const EdgeInsets.only(bottom: 8.0),
                                          child: Row(
                                            children: [
                                              Expanded(child: Text("Backup: $timeStr", style: const TextStyle(color: Colors.white70, fontSize: 12, fontFamily: 'monospace'))),
                                              SizedBox(
                                                height: 24,
                                                child: OutlinedButton(
                                                  style: OutlinedButton.styleFrom(
                                                    padding: const EdgeInsets.symmetric(horizontal: 8),
                                                    side: const BorderSide(color: Colors.lightBlueAccent)
                                                  ),
                                                  onPressed: () => _previewBackup(filename),
                                                  child: const Text("PREVIEW", style: TextStyle(color: Colors.lightBlueAccent, fontSize: 10)),
                                                ),
                                              ),
                                              const SizedBox(width: 8),
                                              SizedBox(
                                                height: 24,
                                                child: OutlinedButton(
                                                  style: OutlinedButton.styleFrom(
                                                    padding: const EdgeInsets.symmetric(horizontal: 8),
                                                    side: const BorderSide(color: Colors.amberAccent)
                                                  ),
                                                  onPressed: () => _restoreBackup(filename),
                                                  child: const Text("RESTORE", style: TextStyle(color: Colors.amberAccent, fontSize: 10)),
                                                ),
                                              )
                                            ],
                                          ),
                                        );
                                      },
                                    ),
                            )
                          ],
                        ),
                      ),

                    const SizedBox(height: 15),
                    
                    // --- REQ 3: Redleaf Entity Pills ---
                    const Text("Attached Entities (Context):", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white70)),
                    const SizedBox(height: 5),
                    Wrap(
                      spacing: 8, runSpacing: 8,
                      children: [
                        ...node.redleafPills.map((p) => Chip(
                          backgroundColor: kAccentColor.withOpacity(0.2), side: const BorderSide(color: kAccentColor),
                          label: Text(p.text, style: const TextStyle(color: Colors.white, fontSize: 12)),
                          onDeleted: () => graphState.removePill(node.id, p.id),
                        )),
                        ActionChip(
                          backgroundColor: Colors.transparent, side: const BorderSide(color: Colors.white54, style: BorderStyle.solid),
                          label: const Text("+ Add Entity"),
                          onPressed: () {
                            if (!networkState.redleafService.isLoggedIn) { 
                              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Please configure your Redleaf credentials in Settings first."))); 
                            } else { 
                              showDialog(context: context, builder: (ctx) => EntitySearchDialog(nodeId: node.id)); 
                            }
                          },
                        ),
                      ],
                    ),

                    const SizedBox(height: 15),

                    // --- Editor Chat ---
                    Row(
                      children: [
                        const Text("Editor Chat", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white70)),
                        const Spacer(),
                        IconButton(
                          icon: const Icon(Icons.delete_sweep, color: Colors.white54, size: 16),
                          tooltip: "Clear Instructions",
                          onPressed: () => graphState.clearChatHistory(widget.nodeId),
                        )
                      ],
                    ),
                    
                    Container(
                      height: 250, // Fixed height for chat area
                      decoration: BoxDecoration(
                        color: const Color(0xFF111111),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: const Color(0xFF383842))
                      ),
                      child: Column(
                        children: [
                          Expanded(
                            child: ListView.builder(
                              controller: _scrollCtrl,
                              padding: const EdgeInsets.all(10),
                              itemCount: node.chatHistory.length,
                              itemBuilder: (ctx, i) {
                                final msg = node.chatHistory[i];
                                final isUser = msg['role'] == 'user';
                                return Align(
                                  alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
                                  child: Container(
                                    margin: const EdgeInsets.only(bottom: 8),
                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                    constraints: const BoxConstraints(maxWidth: 280),
                                    decoration: BoxDecoration(
                                      color: isUser ? kAccentColor.withOpacity(0.8) : const Color(0xFF333333),
                                      borderRadius: BorderRadius.circular(8).copyWith(
                                        bottomRight: isUser ? const Radius.circular(0) : const Radius.circular(8),
                                        bottomLeft: !isUser ? const Radius.circular(0) : const Radius.circular(8),
                                      ),
                                    ),
                                    child: SelectableText(msg['content'] ?? "", style: const TextStyle(color: Colors.white, fontSize: 13)),
                                  ),
                                );
                              },
                            ),
                          ),
                          Container(
                             padding: const EdgeInsets.all(8),
                             color: const Color(0xFF222222),
                             child: Row(
                               children: [
                                 Expanded(
                                   child: Focus(
                                     onKeyEvent: (nodeFocus, event) {
                                        if (event is KeyDownEvent && event.logicalKey == LogicalKeyboardKey.enter) {
                                          final isShiftPressed = HardwareKeyboard.instance.logicalKeysPressed.contains(LogicalKeyboardKey.shiftLeft) || 
                                                                 HardwareKeyboard.instance.logicalKeysPressed.contains(LogicalKeyboardKey.shiftRight);
                                          if (isShiftPressed) {
                                            if (!networkState.isGeneratingOllama) {
                                              _sendMessage();
                                            }
                                            return KeyEventResult.handled;
                                          }
                                        }
                                        return KeyEventResult.ignored;
                                     },
                                     child: TextField(
                                       controller: _msgCtrl,
                                       style: const TextStyle(color: Colors.white, fontSize: 13),
                                       textInputAction: TextInputAction.newline,
                                       maxLines: 3, minLines: 1,
                                       decoration: const InputDecoration(
                                         hintText: "Discuss edits... (Shift+Enter to send)",
                                         hintStyle: TextStyle(color: Colors.white54),
                                         isDense: true,
                                         contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                         border: OutlineInputBorder(borderSide: BorderSide.none)
                                       ),
                                     ),
                                   ),
                                 ),
                                 IconButton(
                                   icon: isThisGenerating 
                                     ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(color: Colors.greenAccent, strokeWidth: 2))
                                     : const Icon(Icons.send, color: Colors.greenAccent, size: 20),
                                   onPressed: networkState.isGeneratingOllama ? null : _sendMessage,
                                 )
                               ]
                             )
                          )
                        ]
                      )
                    ),
                  ],
                ),
              ),
            ),

            // --- FOREGROUND: SLIDING OUTPUT PANEL ---
            Positioned(
              left: 0, right: 0, bottom: 0,
              height: _outputPanelHeight!,
              child: Container(
                decoration: const BoxDecoration(
                  color: Color(0xFF1A1A1A), // Matches the background panel
                  border: Border(top: BorderSide(color: Color(0xFF383842), width: 1)) 
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Resizer Handle (Flat style)
                    GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onVerticalDragUpdate: (details) {
                        setState(() {
                          _outputPanelHeight = _outputPanelHeight! - details.delta.dy;
                          if (_outputPanelHeight! < 150) _outputPanelHeight = 150;
                          if (_outputPanelHeight! > constraints.maxHeight - 20) {
                            _outputPanelHeight = constraints.maxHeight - 20;
                          }
                          _savedHeights[widget.nodeId] = _outputPanelHeight!;
                        });
                      },
                      child: MouseRegion(
                        cursor: SystemMouseCursors.resizeRow,
                        child: Container(
                          height: 16,
                          width: double.infinity,
                          alignment: Alignment.center,
                          child: Container(
                            width: 50, height: 2, 
                            color: Colors.white24 
                          ),
                        ),
                      ),
                    ),
                    
                    // Output Content
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.only(left: 10.0, right: 10.0, bottom: 10.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Execute Button
                            SizedBox(
                              width: double.infinity,
                              child: ElevatedButton.icon(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.deepOrange.shade800, 
                                  foregroundColor: Colors.white, 
                                  padding: const EdgeInsets.symmetric(vertical: 12), 
                                ),
                                icon: isThisGenerating 
                                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)) 
                                  : const Icon(Icons.edit_document),
                                label: Text(isThisGenerating ? "EDITING WIKI..." : "EXECUTE WRITE (${networkState.ollamaModel})"),
                                onPressed: networkState.isGeneratingOllama || _titleCtrl.text.trim().isEmpty ? null : () {
                                  final sequence = graphState.getCompiledNodes(widget.nodeId);
                                  networkState.triggerWikiWriterGeneration(node, sequence, graphState);
                                  
                                  Future.delayed(const Duration(seconds: 10), _fetchHistory);
                                },
                              ),
                            ),
                            
                            const SizedBox(height: 10),
                            const Padding(
                              padding: EdgeInsets.only(left: 5.0, bottom: 8.0),
                              child: Text("LIVE DRAFT", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
                            ),
                            
                            Expanded(
                              child: Container(
                                width: double.infinity, padding: const EdgeInsets.all(10), // Reduced inner padding
                                decoration: BoxDecoration(color: const Color(0xFF111111), borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.white12)),
                                child: SingleChildScrollView(
                                  child: SelectableText.rich(
                                    node.ollamaResult.isEmpty 
                                        ? const TextSpan(text: "Output will appear here and then be written to disk...", style: TextStyle(color: Colors.grey))
                                        : parseRichText(
                                            node.ollamaResult, 
                                            networkState.redleafService.apiUrl,
                                            graphState: graphState,
                                            networkState: networkState,
                                            context: context,
                                            currentNodeId: widget.nodeId
                                          ),
                                    style: const TextStyle(color: Colors.white, height: 1.5, fontFamily: 'monospace', fontSize: 13), 
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    )
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}