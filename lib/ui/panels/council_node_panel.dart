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
  late TextEditingController _titleCtrl;
  
  List<String> _availablePages = [];
  bool _isLoadingPages = true;

  // --- State for history tracking ---
  List<String> _historyFiles = [];
  bool _isLoadingHistory = false;

  @override
  void initState() {
    super.initState();
    final graphState = context.read<GraphState>();
    final node = graphState.nodes[widget.nodeId];
    _agentCountCtrl = TextEditingController(text: (node?.councilAgentCount ?? 3).toString());
    _titleCtrl = TextEditingController(text: node?.wikiTitle ?? "");
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
      _fetchPages();
      if (_titleCtrl.text.isNotEmpty) _fetchHistory();
    }
  }

  @override
  void dispose() {
    _agentCountCtrl.dispose();
    _titleCtrl.dispose();
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

          if (isAuditMode) ...[
            Theme(
              data: ThemeData(unselectedWidgetColor: Colors.grey),
              child: CheckboxListTile(
                title: const Text("Audit History", style: TextStyle(fontSize: 12, color: Colors.white70, fontWeight: FontWeight.bold)),
                subtitle: const Text("The council will compare older versions of this page against the primary sources to recover lost facts and fix semantic drift.", style: TextStyle(fontSize: 10, color: Colors.white54)),
                contentPadding: EdgeInsets.zero, controlAffinity: ListTileControlAffinity.leading, activeColor: Colors.amberAccent, checkColor: Colors.black,
                value: node.councilAuditHistory, 
                onChanged: (val) { if (val != null) graphState.toggleCouncilAuditHistory(widget.nodeId, val); },
              ),
            ),
            const SizedBox(height: 10),
          ],

          // --- AGENT COUNT ---
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
          Text(isAuditMode ? "COUNCIL AUDIT & REWRITE" : "COUNCIL DISCOVERY REPORT", style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
          const SizedBox(height: 10),
          Expanded(
            child: Container(
              width: double.infinity, padding: const EdgeInsets.all(15),
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
                  style: const TextStyle(color: Colors.white, height: 1.5),
                ),
              ),
            ),
          ),
          
          // --- NEW: Promote to Scratchpad Button ---
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
        ],
      ),
    );
  }
}