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
  // --- Persistent height cache across node selections ---
  static final Map<String, double> _savedHeights = {};

  late TextEditingController _agentCountCtrl;
  late TextEditingController _titleCtrl;
  late TextEditingController _directionCtrl; 
  late TextEditingController _feedbackCtrl;  
  
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
    _agentCountCtrl = TextEditingController(text: (node?.councilAgentCount ?? 3).toString());
    _titleCtrl = TextEditingController(text: node?.wikiTitle ?? "");
    _directionCtrl = TextEditingController(text: node?.councilDirection ?? ""); 
    _feedbackCtrl = TextEditingController(); 
    _outputPanelHeight = _savedHeights[widget.nodeId] ?? 350.0; // Generous default height
    _fetchPages();
    if (_titleCtrl.text.isNotEmpty) _fetchHistory();
  }

  @override
  void didUpdateWidget(covariant _CouncilInterface oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.nodeId != widget.nodeId) {
      final graphState = context.read<GraphState>();
      final node = graphState.nodes[widget.nodeId];
      _agentCountCtrl.text = (node?.councilAgentCount ?? 3).toString();
      _titleCtrl.text = node?.wikiTitle ?? "";
      _directionCtrl.text = node?.councilDirection ?? ""; 
      
      // Reset height to null so it pulls the correct saved height for the NEW node
      _outputPanelHeight = null; 
      
      _fetchPages();
      if (_titleCtrl.text.isNotEmpty) _fetchHistory();
    }
  }

  @override
  void dispose() {
    _agentCountCtrl.dispose();
    _titleCtrl.dispose();
    _directionCtrl.dispose(); 
    _feedbackCtrl.dispose();  
    super.dispose();
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
    final bool isAuditMode = _titleCtrl.text.trim().isNotEmpty;
    final bool isWaitingForInput = networkState.isNodeWaitingForInput(widget.nodeId);

    return LayoutBuilder(
      builder: (context, constraints) {
        // Use saved height, or default to 350px for a generous initial text area
        _outputPanelHeight ??= _savedHeights[widget.nodeId] ?? 350.0;
        
        // Ensure it doesn't overflow if the window is tiny
        if (_outputPanelHeight! > constraints.maxHeight - 20) {
          _outputPanelHeight = constraints.maxHeight - 20;
        }
        
        // If we are waiting for input, ensure the panel is tall enough to show the text box
        if (isWaitingForInput && _outputPanelHeight! < 300) {
            _outputPanelHeight = 300;
        }

        return Stack(
          children: [
            // --- BACKGROUND: SCROLLABLE SETTINGS ---
            Positioned.fill(
              child: SingleChildScrollView(
                // The bottom padding ensures the user can scroll past the overlay
                padding: EdgeInsets.fromLTRB(20, 20, 20, _outputPanelHeight! + 20),
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
                    const Text("Leave the Wiki Page blank to debate upstream research and discover new topics (Discovery Mode). Or, select a page to critique and rewrite it based on new data (Audit Mode).", style: TextStyle(color: Colors.white54, fontSize: 12)),
                    const SizedBox(height: 20),

                    // --- WIKI FILE SELECTOR ---
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text("Target Wiki Page (Optional):", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white70)),
                        if (isAuditMode)
                          const Text("Audit Mode", style: TextStyle(color: Colors.amberAccent, fontSize: 11, fontWeight: FontWeight.bold))
                        else
                          const Text("Discovery Mode", style: TextStyle(color: Colors.lightBlueAccent, fontSize: 11, fontWeight: FontWeight.bold))
                      ],
                    ),
                    const SizedBox(height: 5),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _titleCtrl,
                            decoration: InputDecoration(
                              filled: true, fillColor: const Color(0xFF222222), 
                              border: const OutlineInputBorder(borderSide: BorderSide.none), 
                              hintText: "e.g. Cold_War_Economics",
                              suffixIcon: isAuditMode ? IconButton(
                                icon: const Icon(Icons.clear, color: Colors.white54, size: 18),
                                onPressed: () {
                                  _titleCtrl.clear();
                                  graphState.updateWikiTitle(widget.nodeId, "");
                                  graphState.updateNodeTitle(widget.nodeId, "Wiki Council");
                                  _fetchHistory();
                                },
                              ) : null,
                            ),
                            onChanged: (val) {
                               graphState.updateWikiTitle(widget.nodeId, val);
                               graphState.updateNodeTitle(widget.nodeId, val.isEmpty ? "Wiki Council" : "Audit: $val");
                               _fetchHistory();
                            }
                          ),
                        ),
                        const SizedBox(width: 8),
                        ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF333333), 
                            foregroundColor: Colors.white, 
                            padding: const EdgeInsets.symmetric(vertical: 16)
                          ),
                          onPressed: _titleCtrl.text.trim().isEmpty ? null : _loadCurrentFile,
                          child: const Text("Load"),
                        )
                      ],
                    ),
                    const SizedBox(height: 10),

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
                                        graphState.updateNodeTitle(widget.nodeId, "Audit: $page");
                                        _fetchHistory();
                                        _loadCurrentFile();
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

                    const Text("Council Directive / Focus (Optional):", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white70)),
                    const SizedBox(height: 5),
                    TextField(
                      controller: _directionCtrl,
                      maxLines: 2,
                      decoration: const InputDecoration(
                        filled: true, fillColor: Color(0xFF222222), 
                        border: OutlineInputBorder(borderSide: BorderSide.none), 
                        hintText: "e.g., Focus specifically on the economic implications rather than the timeline."
                      ),
                      onChanged: (val) {
                         graphState.updateCouncilDirection(widget.nodeId, val);
                      }
                    ),
                    const SizedBox(height: 15),

                    Theme(
                      data: ThemeData(unselectedWidgetColor: Colors.grey),
                      child: CheckboxListTile(
                        title: const Text("The Chairman's Review (Interactive Debate)", style: TextStyle(fontSize: 12, color: Colors.white70, fontWeight: FontWeight.bold)),
                        subtitle: const Text("Pause the debate before the final report so you can give feedback and direct the experts.", style: TextStyle(fontSize: 10, color: Colors.white54)),
                        contentPadding: EdgeInsets.zero, controlAffinity: ListTileControlAffinity.leading, activeColor: Colors.amberAccent, checkColor: Colors.black,
                        value: node.councilInteractive, 
                        onChanged: (val) { if (val != null) graphState.toggleCouncilInteractive(widget.nodeId, val); },
                      ),
                    ),

                    if (isAuditMode) ...[
                      Theme(
                        data: ThemeData(unselectedWidgetColor: Colors.grey),
                        child: CheckboxListTile(
                          title: const Text("Audit History", style: TextStyle(fontSize: 12, color: Colors.white70, fontWeight: FontWeight.bold)),
                          subtitle: const Text("The council will compare older versions against the primary sources to recover lost facts and fix semantic drift.", style: TextStyle(fontSize: 10, color: Colors.white54)),
                          contentPadding: EdgeInsets.zero, controlAffinity: ListTileControlAffinity.leading, activeColor: Colors.amberAccent, checkColor: Colors.black,
                          value: node.councilAuditHistory, 
                          onChanged: (val) { if (val != null) graphState.toggleCouncilAuditHistory(widget.nodeId, val); },
                        ),
                      ),
                    ],

                    const SizedBox(height: 10),

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
                          side: BorderSide(color: isAuditMode ? Colors.amberAccent.withOpacity(0.5) : Colors.lightBlueAccent.withOpacity(0.5))
                        ),
                        icon: isThisGenerating && !isWaitingForInput
                          ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)) 
                          : const Icon(Icons.account_balance),
                        label: Text(isThisGenerating && !isWaitingForInput ? "CONVENING COUNCIL..." : "CONVENE COUNCIL (${networkState.ollamaModel})"),
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
                  // Removed box shadow for flat aesthetic
                  border: Border(top: BorderSide(color: Color(0xFF383842), width: 1)) // 1px subtle divider
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
                          // Leave 20px gap at the top so it doesn't clip totally out of bounds
                          if (_outputPanelHeight! > constraints.maxHeight - 20) {
                            _outputPanelHeight = constraints.maxHeight - 20;
                          }
                          // Save the new height
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
                            color: Colors.white24 // Flat, non-rounded line
                          ),
                        ),
                      ),
                    ),
                    
                    // Output Content
                    Expanded(
                      child: Padding(
                        // Reduced outer padding for maximum real estate
                        padding: const EdgeInsets.only(left: 10.0, right: 10.0, bottom: 10.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Padding(
                              padding: const EdgeInsets.only(left: 5.0, bottom: 8.0),
                              child: Text(isAuditMode ? "COUNCIL AUDIT & REWRITE" : "COUNCIL DISCOVERY REPORT", style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
                            ),
                            Expanded(
                              child: Container(
                                width: double.infinity, 
                                padding: const EdgeInsets.all(10), // Reduced inner padding
                                decoration: BoxDecoration(color: const Color(0xFF111111), borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.white12)),
                                child: SingleChildScrollView(
                                  child: SelectableText.rich(
                                    node.ollamaResult.isEmpty 
                                        ? const TextSpan(text: "Council findings will appear here...", style: TextStyle(color: Colors.grey))
                                        : parseRichText(
                                            node.ollamaResult, 
                                            networkState.redleafService.apiUrl,
                                            graphState: graphState,
                                            networkState: networkState,
                                            context: context,
                                            currentNodeId: widget.nodeId
                                          ),
                                    style: const TextStyle(color: Colors.white, height: 1.5, fontSize: 13), // Slightly smaller font for density
                                  ),
                                ),
                              ),
                            ),
                            
                            // --- DYNAMIC BOTTOM UI: Chairman Input OR Promote Button ---
                            if (isWaitingForInput) ...[
                              const SizedBox(height: 10),
                              Container(
                                  padding: const EdgeInsets.all(10),
                                  decoration: BoxDecoration(
                                      color: Colors.amberAccent.withOpacity(0.1),
                                      border: Border.all(color: Colors.amberAccent),
                                      borderRadius: BorderRadius.circular(8)
                                  ),
                                  child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                          const Text("The Chairman's Turn", style: TextStyle(color: Colors.amberAccent, fontWeight: FontWeight.bold, fontSize: 13)),
                                          const SizedBox(height: 5),
                                          const Text("The council is waiting. Enter feedback, or leave blank to proceed to the final report.", style: TextStyle(color: Colors.white70, fontSize: 11)),
                                          const SizedBox(height: 8),
                                          TextField(
                                              controller: _feedbackCtrl,
                                              maxLines: 2,
                                              style: const TextStyle(color: Colors.white, fontSize: 13),
                                              decoration: const InputDecoration(
                                                  filled: true, fillColor: Color(0xFF111111),
                                                  border: OutlineInputBorder(borderSide: BorderSide.none),
                                                  hintText: "Enter your feedback...",
                                                  contentPadding: EdgeInsets.all(8),
                                                  isDense: true,
                                              ),
                                          ),
                                          const SizedBox(height: 8),
                                          SizedBox(
                                              width: double.infinity,
                                              child: ElevatedButton(
                                                  style: ElevatedButton.styleFrom(backgroundColor: Colors.amberAccent, foregroundColor: Colors.black, padding: const EdgeInsets.symmetric(vertical: 8)),
                                                  onPressed: () {
                                                      networkState.submitUserInput(_feedbackCtrl.text);
                                                      _feedbackCtrl.clear();
                                                  },
                                                  child: const Text("Submit Feedback", style: TextStyle(fontWeight: FontWeight.bold)),
                                              ),
                                          )
                                      ],
                                  )
                              ),
                            ] else ...[
                              const SizedBox(height: 10),
                              SizedBox(
                                width: double.infinity,
                                child: OutlinedButton.icon(
                                  style: OutlinedButton.styleFrom(foregroundColor: Colors.white, side: const BorderSide(color: Colors.white54)),
                                  icon: const Icon(Icons.turn_right), label: const Text("Promote Rewrite to Scratchpad"),
                                  onPressed: node.ollamaResult.isEmpty || networkState.isGeneratingOllama ? null : () {
                                    String finalReport = node.ollamaResult;
                                    final marker = "> [System] Debate concluded. Drafting final Council Report...\n\n";
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
                            ]
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