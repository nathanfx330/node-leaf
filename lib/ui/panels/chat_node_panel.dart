// --- File: lib/ui/panels/chat_node_panel.dart ---
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../constants.dart';
import '../../state/graph_state.dart';
import '../../state/network_state.dart';
import '../side_panel.dart'; // Needed for parseRichText

class ChatNodePanel extends StatefulWidget {
  final String nodeId;
  const ChatNodePanel({super.key, required this.nodeId});

  @override
  State<ChatNodePanel> createState() => _ChatNodePanelState();
}

class _ChatNodePanelState extends State<ChatNodePanel> {
  final TextEditingController _msgCtrl = TextEditingController();
  final ScrollController _scrollCtrl = ScrollController();

  void _sendMessage() {
    final text = _msgCtrl.text.trim();
    if (text.isEmpty) return;

    final networkState = context.read<NetworkState>();
    final graphState = context.read<GraphState>();
    
    if (networkState.isGeneratingOllama) return;
    
    final node = graphState.nodes[widget.nodeId]!;
    final sequence = graphState.getCompiledNodes(widget.nodeId);

    _msgCtrl.clear();
    networkState.triggerOllamaChat(node, sequence, text, graphState);

    Future.delayed(const Duration(milliseconds: 100), _scrollToBottom);
  }

  void _scrollToBottom() {
    if (_scrollCtrl.hasClients) {
      _scrollCtrl.animateTo(_scrollCtrl.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
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

    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(15),
          decoration: const BoxDecoration(
            color: Color(0xFF222222),
            border: Border(bottom: BorderSide(color: Color(0xFF383842)))
          ),
          child: Row(
            children: [
              const Icon(Icons.forum, color: Colors.greenAccent, size: 20),
              const SizedBox(width: 10),
              const Text("OLLAMA CHAT", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, letterSpacing: 1.5)),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.delete_sweep, color: Colors.white54, size: 20),
                tooltip: "Clear Chat History",
                onPressed: () => graphState.clearChatHistory(widget.nodeId),
              )
            ],
          ),
        ),

        Container(
          color: const Color(0xFF1A1A1A),
          child: ExpansionTile(
            title: const Text("Chat Settings & Toggles", style: TextStyle(color: Colors.white70, fontSize: 12)),
            collapsedIconColor: Colors.white54,
            iconColor: Colors.white,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 15.0, vertical: 5.0),
                child: TextField(
                  maxLines: 2,
                  style: const TextStyle(fontSize: 12, color: Colors.white70),
                  decoration: const InputDecoration(
                    labelText: "System Instructions",
                    labelStyle: TextStyle(color: Colors.white54),
                    filled: true, fillColor: Color(0xFF2A2A32),
                    border: OutlineInputBorder(borderSide: BorderSide.none),
                  ),
                  controller: TextEditingController(text: node.ollamaPrompt)..selection = TextSelection.collapsed(offset: node.ollamaPrompt.length),
                  onChanged: (val) => graphState.updateOllamaPrompt(widget.nodeId, val),
                ),
              ),
              Theme(
                data: ThemeData(unselectedWidgetColor: Colors.grey),
                child: CheckboxListTile(
                  title: const Text("Strict Analytical Mode", style: TextStyle(fontSize: 12, color: Colors.white70)),
                  subtitle: const Text("Forces AI to prioritize facts and use inline citations [Doc X].", style: TextStyle(fontSize: 10, color: Colors.white54)),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 15.0), controlAffinity: ListTileControlAffinity.leading, activeColor: Colors.white, checkColor: Colors.black,
                  value: node.ollamaNoBacktalk, onChanged: (val) { if (val != null) graphState.toggleOllamaBacktalk(widget.nodeId, val); },
                ),
              ),
              Theme(
                data: ThemeData(unselectedWidgetColor: Colors.grey),
                child: CheckboxListTile(
                  title: const Text("Autonomous Redleaf Research", style: TextStyle(fontSize: 12, color: Colors.white70)),
                  subtitle: const Text("AI will auto-search Redleaf for topics found in your new messages.", style: TextStyle(fontSize: 10, color: Colors.white54)),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 15.0), controlAffinity: ListTileControlAffinity.leading, activeColor: Colors.white, checkColor: Colors.black,
                  value: node.enableAutonomousResearch, onChanged: (val) { if (val != null) graphState.toggleAutonomousResearch(widget.nodeId, val); },
                ),
              ),
              const SizedBox(height: 10),
            ],
          ),
        ),

        Expanded(
          child: ListView.builder(
            controller: _scrollCtrl,
            padding: const EdgeInsets.all(15),
            itemCount: node.chatHistory.length,
            itemBuilder: (ctx, i) {
              final msg = node.chatHistory[i];
              final isUser = msg['role'] == 'user';
              
              return Align(
                alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
                child: Container(
                  margin: const EdgeInsets.only(bottom: 15),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  constraints: const BoxConstraints(maxWidth: 320),
                  decoration: BoxDecoration(
                    color: isUser ? kAccentColor.withOpacity(0.8) : const Color(0xFF333333),
                    borderRadius: BorderRadius.circular(12).copyWith(
                      bottomRight: isUser ? const Radius.circular(0) : const Radius.circular(12),
                      bottomLeft: !isUser ? const Radius.circular(0) : const Radius.circular(12),
                    ),
                  ),
                  child: SelectableText.rich(
                    parseRichText(msg['content'] ?? "", networkState.redleafService.apiUrl),
                    style: const TextStyle(color: Colors.white, fontSize: 14, height: 1.4),
                  ),
                ),
              );
            },
          ),
        ),

        Container(
          padding: const EdgeInsets.all(15),
          decoration: const BoxDecoration(
            color: Color(0xFF222222),
            border: Border(top: BorderSide(color: Color(0xFF383842)))
          ),
          child: Column(
            children: [
              if (isThisGenerating)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10.0),
                  child: SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.redAccent, 
                        side: const BorderSide(color: Colors.redAccent),
                        padding: const EdgeInsets.symmetric(vertical: 8)
                      ),
                      icon: const Icon(Icons.flash_on, size: 16), 
                      label: const Text("ANSWER NOW (Skip Research)", style: TextStyle(fontSize: 12)),
                      onPressed: () => networkState.forceAnswerNow(),
                    ),
                  ),
                ),
              Row(
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
                        maxLines: 4, minLines: 1,
                        textInputAction: TextInputAction.newline,
                        style: const TextStyle(color: Colors.white),
                        decoration: const InputDecoration(
                          hintText: "Message... (Shift+Enter to send)",
                          hintStyle: TextStyle(color: Colors.white54),
                          filled: true, fillColor: Color(0xFF1A1A1A),
                          border: OutlineInputBorder(borderSide: BorderSide.none, borderRadius: BorderRadius.all(Radius.circular(8))),
                          contentPadding: EdgeInsets.symmetric(horizontal: 15, vertical: 10)
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Container(
                    decoration: const BoxDecoration(color: Colors.greenAccent, shape: BoxShape.circle),
                    child: IconButton(
                      icon: isThisGenerating 
                        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: Colors.black, strokeWidth: 2))
                        : const Icon(Icons.send, color: Colors.black),
                      onPressed: networkState.isGeneratingOllama ? null : _sendMessage,
                    ),
                  )
                ],
              ),
            ],
          ),
        )
      ],
    );
  }
}