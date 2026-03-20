// --- File: lib/ui/top_bar.dart ---
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../constants.dart';
import '../state/network_state.dart';
import '../state/graph_state.dart';

class TopBar extends StatelessWidget {
  const TopBar({super.key});

  Widget _buildStatusIndicator(AuthStatus status) {
    Color color;
    switch (status) {
      case AuthStatus.none: color = Colors.grey; break;
      case AuthStatus.testing: color = Colors.amber; break;
      case AuthStatus.success: color = Colors.greenAccent; break;
      case AuthStatus.error: color = Colors.redAccent; break;
      case AuthStatus.mismatch: color = Colors.purpleAccent; break;
    }
    return Container(
      width: 10, height: 10,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle, boxShadow: [BoxShadow(color: color, blurRadius: 4)]),
    );
  }

  String _getStatusText(AuthStatus status) {
    switch (status) {
      case AuthStatus.none: return "Not Connected";
      case AuthStatus.testing: return "Testing...";
      case AuthStatus.success: return "Connected!";
      case AuthStatus.error: return "Failed to Connect";
      case AuthStatus.mismatch: return "DB Mismatch!";
    }
  }

  @override
  Widget build(BuildContext context) {
    // Top bar needs info from both Network and Graph states
    final networkState = context.watch<NetworkState>();
    final graphState = context.watch<GraphState>();
    
    final bool isLocked = networkState.redleafInstanceId.isNotEmpty;
    
    // Create a shortened version of the UUID for display
    String displayId = isLocked 
        ? "DB: ${networkState.redleafInstanceId.substring(0, networkState.redleafInstanceId.length > 8 ? 8 : networkState.redleafInstanceId.length)}..." 
        : "No DB Linked";

    return Container(
      height: 40, color: const Color(0xFF222222), padding: const EdgeInsets.symmetric(horizontal: 10),
      child: Row(
        children:[
          const Text("NODE LEAF", style: TextStyle(color: kAccentColor, fontWeight: FontWeight.w900, letterSpacing: 2)),
          const SizedBox(width: 10),
          Text("- ${graphState.projectName}${graphState.activeFilePath == null ? '*' : ''}", style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white70)),
          const SizedBox(width: 20), const VerticalDivider(color: Colors.black, width: 20),
          
          _MenuButton(label: "New", onTap: () => graphState.newProject(networkState)),
          _MenuButton(label: "Open", onTap: () => graphState.loadProject(networkState)),
          _MenuButton(label: "Save", onTap: () => graphState.saveProject(networkState)),
          _MenuButton(label: "Save As", onTap: () => graphState.saveAsProject(networkState)),
          
          const VerticalDivider(color: Colors.black, width: 20),
          _MenuButton(label: "Undo", onTap: () => graphState.undo()),
          const VerticalDivider(color: Colors.black, width: 20),
          _MenuButton(label: "Copy", onTap: () => graphState.copySelection()),
          _MenuButton(label: "Paste", onTap: () => graphState.paste()),
          const VerticalDivider(color: Colors.black, width: 20),
          _MenuButton(label: "About", onTap: () => _showAboutDialog(context)),
          const Spacer(),
          
          _buildStatusIndicator(networkState.redleafAuthStatus),
          const SizedBox(width: 8),

          Tooltip(
            message: networkState.redleafInstanceId.isEmpty 
                ? "Connect to a Redleaf server in Settings" 
                : "Locked to DB Fingerprint:\n${networkState.redleafInstanceId}\n\nThis prevents Entity ID mixups.",
            child: Chip(
              backgroundColor: Colors.black45,
              side: BorderSide(color: networkState.redleafAuthStatus == AuthStatus.mismatch ? Colors.purpleAccent : kAccentColor),
              avatar: Icon(networkState.redleafInstanceId.isEmpty ? Icons.cloud_off : Icons.lock, size: 14, color: networkState.redleafAuthStatus == AuthStatus.mismatch ? Colors.purpleAccent : kAccentColor),
              label: Text(
                networkState.redleafAuthStatus == AuthStatus.mismatch ? "DB Mismatch!" : displayId, 
                style: const TextStyle(fontSize: 12, color: Colors.white70)
              ),
            ),
          ),
          
          const SizedBox(width: 10),
          IconButton(icon: const Icon(Icons.settings, size: 18), tooltip: "Settings", onPressed: () => _showSettingsDialog(context, networkState, graphState)),
          IconButton(icon: const Icon(Icons.delete, size: 18), onPressed: () => graphState.deleteSelected(), tooltip: "Delete Selected"),
        ],
      ),
    );
  }

  void _showAboutDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        contentPadding: const EdgeInsets.only(top: 32, bottom: 24, left: 24, right: 24),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children:[
            Image.asset(
              'assets/logo.png', 
              height: 200,
              errorBuilder: (context, error, stackTrace) => const Icon(Icons.account_tree, size: 100, color: kAccentColor),
            ), 
            const SizedBox(height: 5),
            const Text("Node Leaf 1.5", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white)),
            const SizedBox(height: 8),
            const Text("The Nodal RAG companion to Redleaf Engine 2.5", textAlign: TextAlign.center, style: TextStyle(fontSize: 13, color: Colors.white70)),
            const SizedBox(height: 16),
            const Text("by Nathaniel Westveer", style: TextStyle(fontSize: 14, color: Colors.white70)),
          ],
        ),
        actions:[TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Close", style: TextStyle(color: kAccentColor)))],
      ),
    );
  }

  void _showSettingsDialog(BuildContext context, NetworkState networkState, GraphState graphState) {
    final apiCtrl = TextEditingController(text: networkState.redleafService.apiUrl);
    final userCtrl = TextEditingController(text: networkState.redleafService.username);
    final passCtrl = TextEditingController(text: networkState.redleafService.password);
    final ollamaCtrl = TextEditingController(text: networkState.ollamaUrl);

    showDialog(
      context: context,
      builder: (ctx) {
        return MultiProvider(
          providers: [
            ChangeNotifierProvider.value(value: networkState),
            ChangeNotifierProvider.value(value: graphState),
          ],
          child: Consumer2<NetworkState, GraphState>(
            builder: (context, netState, grState, child) {
              return AlertDialog(
                title: const Text("Project Settings"),
                content: SizedBox(
                  width: 500, 
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start,
                      children:[
                        const Text("Redleaf API Connection", style: TextStyle(color: kAccentColor, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 10),
                        TextField(controller: apiCtrl, decoration: const InputDecoration(labelText: "Redleaf API URL (e.g. http://192.168.x.x:5000)", filled: true, fillColor: Colors.black26)),
                        const SizedBox(height: 10),
                        TextField(controller: userCtrl, decoration: const InputDecoration(labelText: "Redleaf Username", filled: true, fillColor: Colors.black26)),
                        const SizedBox(height: 10),
                        TextField(controller: passCtrl, obscureText: true, decoration: const InputDecoration(labelText: "Redleaf Password", filled: true, fillColor: Colors.black26)),
                        const SizedBox(height: 15),
                        Row(
                          children: [
                            ElevatedButton(
                              style: ElevatedButton.styleFrom(backgroundColor: kNodeBg),
                              onPressed: netState.redleafAuthStatus == AuthStatus.testing ? null : () {
                                netState.testAndSaveRedleafCredentials(apiCtrl.text, userCtrl.text, passCtrl.text);
                              },
                              child: Text(netState.redleafAuthStatus == AuthStatus.testing ? "Connecting..." : "Connect & Save"),
                            ),
                            const SizedBox(width: 15),
                            _buildStatusIndicator(netState.redleafAuthStatus),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                netState.redleafAuthStatus == AuthStatus.mismatch 
                                  ? "MISMATCH! This project file belongs to a different database." 
                                  : _getStatusText(netState.redleafAuthStatus), 
                                style: TextStyle(
                                  color: netState.redleafAuthStatus == AuthStatus.mismatch ? Colors.purpleAccent : Colors.white70, 
                                  fontSize: 12, 
                                  fontWeight: netState.redleafAuthStatus == AuthStatus.mismatch ? FontWeight.bold : FontWeight.normal
                                )
                              ),
                            ),
                          ],
                        ),

                        const SizedBox(height: 20), const Divider(), const SizedBox(height: 10),
                        
                        const Text("Ollama API Connection", style: TextStyle(color: kAccentColor, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 10),
                        TextField(
                          controller: ollamaCtrl, 
                          decoration: const InputDecoration(labelText: "Ollama URL (e.g. http://192.168.x.x:11434)", filled: true, fillColor: Colors.black26),
                          onChanged: (val) => netState.setOllamaUrl(val),
                        ),
                        
                        // --- NEW: Helper text for LAN connections ---
                        if (!netState.ollamaUrl.contains('localhost') && !netState.ollamaUrl.contains('127.0.0.1'))
                          const Padding(
                            padding: EdgeInsets.only(top: 8.0),
                            child: Text(
                              "Note: To connect to Ollama on a different computer, the host machine must run Ollama with the environment variable OLLAMA_HOST=0.0.0.0",
                              style: TextStyle(color: Colors.amber, fontSize: 11, fontStyle: FontStyle.italic),
                            ),
                          ),
                          
                        const SizedBox(height: 15),
                        
                        // --- NEW: Ollama Connection Button & Status ---
                        Row(
                          children: [
                            ElevatedButton(
                              style: ElevatedButton.styleFrom(backgroundColor: kNodeBg),
                              onPressed: netState.ollamaAuthStatus == AuthStatus.testing ? null : () {
                                netState.fetchOllamaModels();
                              },
                              child: Text(netState.ollamaAuthStatus == AuthStatus.testing ? "Connecting..." : "Test Connection"),
                            ),
                            const SizedBox(width: 15),
                            _buildStatusIndicator(netState.ollamaAuthStatus),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                _getStatusText(netState.ollamaAuthStatus), 
                                style: const TextStyle(color: Colors.white70, fontSize: 12)
                              ),
                            ),
                          ],
                        ),

                        const SizedBox(height: 20),
                        const Text("Ollama Model"), const SizedBox(height: 10),
                        Row(
                          children: [
                            Expanded(
                              child: DropdownButton<String>(
                                value: netState.availableModels.contains(netState.ollamaModel) ? netState.ollamaModel : (netState.availableModels.isNotEmpty ? netState.availableModels.first : null),
                                isExpanded: true,
                                hint: Text(netState.isScanningModels ? "Scanning Ollama..." : "No Models Found"),
                                items: netState.availableModels.map((m) => DropdownMenuItem(value: m, child: Text(m))).toList(),
                                onChanged: (val) { if (val != null) netState.setOllamaModel(val); },
                              ),
                            ),
                            IconButton(
                              tooltip: "Refresh Models List",
                              icon: netState.isScanningModels ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.refresh),
                              onPressed: () => netState.fetchOllamaModels(),
                            )
                          ],
                        ),
                        const SizedBox(height: 15),
                        Row(
                          children: [
                            Expanded(
                              flex: 2, 
                              child: ElevatedButton.icon(
                                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF335533), foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 12)),
                                icon: netState.isPreloadingModel ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)) : const Icon(Icons.memory, size: 18),
                                label: Text(netState.isPreloadingModel ? "LOADING..." : "PRELOAD TO VRAM"),
                                onPressed: netState.isPreloadingModel ? null : () async {
                                  final result = await netState.preloadOllamaModel();
                                  if (ctx.mounted) ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text(result == "Success" ? "${netState.ollamaModel} loaded into memory!" : "Failed: $result"), backgroundColor: result == "Success" ? Colors.green : Colors.red));
                                },
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              flex: 1, 
                              child: OutlinedButton.icon(
                                style: OutlinedButton.styleFrom(foregroundColor: Colors.redAccent, side: const BorderSide(color: Colors.redAccent), padding: const EdgeInsets.symmetric(vertical: 12)),
                                icon: const Icon(Icons.eject, size: 18), label: const Text("UNLOAD"),
                                onPressed: () async {
                                  final result = await netState.unloadOllamaModel();
                                  if (ctx.mounted) ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text(result == "Success" ? "VRAM Cleared!" : "Failed: $result"), backgroundColor: Colors.grey.shade900));
                                },
                              ),
                            ),
                          ],
                        )
                      ],
                    ),
                  ),
                ),
                actions:[TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Done", style: TextStyle(color: kAccentColor)))],
              );
            },
          ),
        );
      },
    );
  }
}

class _MenuButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const _MenuButton({required this.label, required this.onTap});
  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8), child: Text(label, style: const TextStyle(color: Colors.white))),
    );
  }
}