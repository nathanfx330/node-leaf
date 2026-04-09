// --- File: lib/ui/canvas_view.dart ---
import 'package:flutter/gestures.dart'; 
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../constants.dart';
import '../state/canvas_state.dart';
import '../state/graph_state.dart';
import '../state/network_state.dart';
import '../models/node_models.dart';

class NodeCanvas extends StatefulWidget {
  const NodeCanvas({super.key});
  @override
  State<NodeCanvas> createState() => _NodeCanvasState();
}

class _NodeCanvasState extends State<NodeCanvas> {
  bool _isLassoing = false;

  @override
  Widget build(BuildContext context) {
    final canvasState = context.read<CanvasState>();
    final graphState = context.read<GraphState>();
    
    return Listener(
      key: canvasState.canvasKey, 
      behavior: HitTestBehavior.opaque,
      onPointerDown: (event) {
        final isRightClick = event.buttons == kSecondaryMouseButton;
        final isMiddleClick = event.buttons == kMiddleMouseButton;
        
        if (isMiddleClick) return;

        final canvasPos = canvasState.screenToCanvas(event.position);
        bool hitNode = graphState.nodes.values.any((n) => n.rect.inflate(40).contains(canvasPos));
        
        if (!hitNode) {
          if (isRightClick) {
            final pos = RelativeRect.fromLTRB(
              event.position.dx, event.position.dy, 
              event.position.dx, event.position.dy
            );
            showMenu<NodeType>(
              context: context,
              position: pos,
              color: kNodeBg,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              items: const [
                PopupMenuItem(value: NodeType.scene, child: Text("➕ Add Scratchpad")),
                PopupMenuItem(value: NodeType.search, child: Text("🔍 Add Global Search")),
                PopupMenuItem(value: NodeType.document, child: Text("📄 Add Document Reader")),
                PopupMenuItem(value: NodeType.relationship, child: Text("🔗 Add Graph Relationship")),
                PopupMenuItem(value: NodeType.catalog, child: Text("🗂️ Add Catalog Reader")),
                PopupMenuItem(value: NodeType.intersection, child: Text("🎯 Add Co-Mention")),
                PopupMenuItem(value: NodeType.briefing, child: Text("🗺️ Add System Briefing")),
                PopupMenuItem(value: NodeType.persona, child: Text("🎭 Add Agent Persona")),
                PopupMenuItem(value: NodeType.wikiReader, child: Text("📘 Add Wiki Reader")),
                PopupMenuItem(value: NodeType.study, child: Text("🤓 Add Deep Study (Geek Out)")),
                PopupMenuItem(value: NodeType.summarize, child: Text("📝 Add Summarizer (Simple)")),
                PopupMenuItem(value: NodeType.output, child: Text("✨ Add Ollama Output")),
                PopupMenuItem(value: NodeType.chat, child: Text("💬 Add Ollama Chat Node")),
                PopupMenuItem(value: NodeType.wikiWriter, child: Text("🖋️ Add Wiki Writer")),
                PopupMenuItem(value: NodeType.council, child: Text("🏛️ Add Wiki Council")), // <-- ADDED
              ],
            ).then((type) {
              if (type != null) graphState.addNode(canvasPos, type);
            });
          } else {
            _isLassoing = true;
            canvasState.startLasso(event.position, graphState);
          }
        }
      },
      onPointerMove: (event) {
        if (event.buttons == kMiddleMouseButton) {
          canvasState.panCanvas(event.delta);
        } else if (canvasState.draggingWireSourceId != null) {
          canvasState.updateWireDrag(event.position, graphState);
        } else if (_isLassoing && canvasState.lassoRect != null) {
          canvasState.updateLasso(event.position, graphState);
        }
      },
      onPointerUp: (event) {
        if (canvasState.draggingWireSourceId != null) canvasState.endWireDrag(graphState);
        if (_isLassoing) { canvasState.endLasso(); _isLassoing = false; }
      },
      child: InteractiveViewer(
        transformationController: canvasState.canvasController, 
        boundaryMargin: const EdgeInsets.all(kWorldSize), 
        minScale: 0.1, maxScale: 2.0, 
        constrained: false, panEnabled: false,
        child: Container(
          width: kWorldSize, height: kWorldSize, color: Colors.transparent, 
          child: Stack(
            children:[
              const RepaintBoundary(child: ConnectionsLayer()),
              Selector<GraphState, List<String>>(
                selector: (_, s) => s.nodes.keys.toList(),
                builder: (ctx, ids, _) => Stack(children: ids.map((id) => NodePositionWrapper(nodeId: id)).toList()),
              ),
              const LassoLayer(),
            ],
          ),
        ),
      ),
    );
  }
}

class ConnectionsLayer extends StatelessWidget {
  const ConnectionsLayer({super.key});
  @override
  Widget build(BuildContext context) {
    return Consumer2<GraphState, CanvasState>(
      builder: (context, graphState, canvasState, _) => CustomPaint(
        size: Size.infinite, 
        painter: ConnectionPainter(graphState, canvasState)
      )
    );
  }
}

class NodePositionWrapper extends StatelessWidget {
  final String nodeId;
  const NodePositionWrapper({super.key, required this.nodeId});
  @override
  Widget build(BuildContext context) {
    return Selector<GraphState, Offset>(
      selector: (_, state) => state.nodes[nodeId]?.position ?? Offset.zero,
      builder: (context, pos, _) => Positioned(left: pos.dx, top: pos.dy, child: NodeVisual(nodeId: nodeId)),
    );
  }
}

class NodeVisual extends StatefulWidget {
  final String nodeId;
  const NodeVisual({super.key, required this.nodeId});
  @override
  State<NodeVisual> createState() => _NodeVisualState();
}

class _NodeVisualState extends State<NodeVisual> {
  bool _isHoveringOutput = false;

  TextSpan _getPreviewSpan(String content) {
    if (content.isEmpty) return const TextSpan(text: "// Empty", style: TextStyle(color: Colors.grey));
    return TextSpan(text: content.length > 150 ? content.substring(0, 150) : content, style: const TextStyle(color: Colors.white70, fontSize: 13, fontFamily: 'monospace', height: 1.3));
  }

  Widget _buildPillContent(StoryNode node, int index, bool isGenerating) {
    IconData iconData;
    String displayTitle;
    Color iconColor = Colors.white70;

    switch (node.type) {
      case NodeType.output:
        iconData = Icons.auto_awesome;
        displayTitle = "OLLAMA OUTPUT";
        iconColor = Colors.purpleAccent;
        break;
      case NodeType.search:
        iconData = Icons.search;
        displayTitle = node.content.isEmpty ? "GLOBAL SEARCH" : "SEARCH: ${node.content}";
        iconColor = Colors.lightBlueAccent;
        break;
      case NodeType.document:
        iconData = Icons.description;
        displayTitle = node.content.isEmpty ? "DOCUMENT READER" : "DOC #${node.content}";
        iconColor = Colors.orangeAccent;
        break;
      case NodeType.catalog:
        iconData = Icons.folder_special;
        displayTitle = node.content.isEmpty ? "CATALOG READER" : "CATALOG: ${node.title}";
        iconColor = Colors.tealAccent;
        break;
      case NodeType.relationship:
        iconData = Icons.hub;
        displayTitle = node.redleafPills.isEmpty ? "GRAPH RELATIONSHIPS" : "GRAPH: ${node.redleafPills.first.text}";
        iconColor = Colors.pinkAccent;
        break;
      case NodeType.intersection:
        iconData = Icons.my_location;
        displayTitle = node.redleafPills.isEmpty ? "CO-MENTIONS" : "INTERSECT: ${node.redleafPills.length} Entities";
        iconColor = Colors.greenAccent;
        break;
      case NodeType.chat: 
        iconData = Icons.forum;
        displayTitle = "OLLAMA CHAT"; 
        iconColor = Colors.greenAccent;
        break;
      case NodeType.briefing:
        iconData = Icons.map;
        displayTitle = "SYSTEM BRIEFING";
        iconColor = Colors.amberAccent;
        break;
      case NodeType.persona: 
        iconData = Icons.theater_comedy;
        displayTitle = "AGENT PERSONA";
        iconColor = Colors.blueGrey;
        break;
      case NodeType.study: 
        iconData = Icons.school;
        displayTitle = node.content.isEmpty ? "DEEP STUDY" : "STUDY: ${node.content}";
        iconColor = Colors.deepPurpleAccent;
        break;
      case NodeType.summarize: 
        iconData = Icons.format_align_left;
        displayTitle = "SUMMARIZER";
        iconColor = Colors.orange;
        break;
      case NodeType.wikiReader: 
        iconData = Icons.menu_book;
        displayTitle = node.wikiTitle.isEmpty ? "WIKI READER" : "READ: ${node.wikiTitle}";
        iconColor = Colors.lightBlueAccent;
        break;
      case NodeType.wikiWriter: 
        iconData = Icons.edit_document;
        displayTitle = node.wikiTitle.isEmpty ? "WIKI WRITER" : "WRITE: ${node.wikiTitle}";
        iconColor = Colors.deepOrangeAccent;
        break;
      case NodeType.council: // <-- ADDED
        iconData = Icons.account_balance;
        displayTitle = "WIKI COUNCIL";
        iconColor = Colors.amberAccent;
        break;
      default:
        iconData = Icons.extension;
        displayTitle = "TOOL";
        break;
    }

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if ((node.type == NodeType.output || node.type == NodeType.chat || node.type == NodeType.study || node.type == NodeType.summarize || node.type == NodeType.wikiWriter || node.type == NodeType.council) && isGenerating) 
          const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 3))
        else 
          Icon(iconData, size: 24, color: iconColor), 
        const SizedBox(width: 12),
        Flexible(
          child: Text(
            displayTitle, 
            overflow: TextOverflow.ellipsis, 
            maxLines: 2,
            textAlign: TextAlign.left, 
            style: const TextStyle(
              fontWeight: FontWeight.w900, 
              color: Colors.white, 
              letterSpacing: 1.2,
              fontSize: 14, 
              height: 1.2
            )
          )
        ),
      ],
    );
  }

  Widget _buildScratchpadContent(StoryNode node, int index, Color headerColor, double borderRadius) {
    return Column(
      children: [
        Container(
          height: 38, width: double.infinity, alignment: Alignment.centerLeft,
          decoration: BoxDecoration(color: headerColor, borderRadius: BorderRadius.vertical(top: Radius.circular(borderRadius))),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0), 
            child: Text(
              (index > 0 ? "#$index " : "") + node.title.toUpperCase(), 
              style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 13, color: Colors.white, letterSpacing: 1.2), 
              overflow: TextOverflow.ellipsis
            )
          ),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(left: 16.0, right: 16.0, top: 12.0, bottom: 8.0), 
            child: Align(
              alignment: Alignment.topLeft, 
              child: Text.rich(_getPreviewSpan(node.content), overflow: TextOverflow.fade)
            )
          )
        ),
        if (node.redleafPills.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 12.0, left: 16.0, right: 16.0),
            child: Wrap(
              spacing: 6, runSpacing: 6,
              children: node.redleafPills.map((p) => Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(color: kAccentColor.withOpacity(0.2), border: Border.all(color: kAccentColor), borderRadius: BorderRadius.circular(16)),
                child: Text(p.text, style: const TextStyle(fontSize: 11, color: Colors.white, fontWeight: FontWeight.bold)),
              )).toList(),
            ),
          )
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final graphState = context.read<GraphState>();
    final canvasState = context.read<CanvasState>();
    
    final nodeId = widget.nodeId;
    final node = graphState.nodes[nodeId]!;
    
    final isSelected = context.select<GraphState, bool>((s) => s.selectedNodeIds.contains(nodeId));
    final isActive = context.select<GraphState, bool>((s) => s.activePathIds.contains(nodeId));
    final isPreview = context.select<GraphState, bool>((s) => s.previewNodeId == nodeId);
    final index = context.select<GraphState, int>((s) => s.getNodeIndex(nodeId));
    
    final isHoverTarget = context.select<CanvasState, bool>((s) => s.hoveredTargetId == nodeId);
    final isSwapTarget = context.select<CanvasState, bool>((s) => s.hoveredSwapTargetId == nodeId);
    final isCycleHover = context.select<CanvasState, bool>((s) => s.isInvalidCycle) && (isHoverTarget || isSwapTarget);

    final bool isGenerating = context.select<NetworkState, bool>((s) => s.isNodeGenerating(nodeId)) && 
      (node.type == NodeType.output || node.type == NodeType.chat || node.type == NodeType.study || node.type == NodeType.summarize || node.type == NodeType.wikiWriter || node.type == NodeType.council);
    
    final double height = node.currentHeight;
    final double borderRadius = node.isCompactToolNode ? (height / 2) : 12.0;

    Color borderColor = const Color(0xFF666666); 
    double borderWidth = node.isCompactToolNode ? 4.0 : 1.0; 
    List<BoxShadow> shadows = [const BoxShadow(color: Colors.black54, blurRadius: 10, offset: Offset(0, 5))];

    if (isSelected) {
      borderColor = kSelectGlowColor; 
      borderWidth = node.isCompactToolNode ? 6.0 : 2.0; 
      shadows = [
        BoxShadow(color: kSelectGlowColor.withOpacity(0.5), blurRadius: 20, spreadRadius: 3),
        const BoxShadow(color: Colors.black87, blurRadius: 15, offset: Offset(0, 8))
      ];
    } else if (isPreview) {
      borderColor = Colors.amber;
      borderWidth = node.isCompactToolNode ? 6.0 : 2.0;
      shadows = [BoxShadow(color: Colors.amber.withOpacity(0.5), blurRadius: 20, spreadRadius: 3)];
    } else if (isHoverTarget) {
      borderColor = Colors.white;
      borderWidth = node.isCompactToolNode ? 6.0 : 2.0;
    } else if (isSwapTarget) {
      borderColor = Colors.purpleAccent;
      borderWidth = node.isCompactToolNode ? 6.0 : 2.0;
    } else if (isCycleHover) {
      borderColor = Colors.redAccent;
      borderWidth = node.isCompactToolNode ? 6.0 : 2.0;
    }

    Color scratchpadHeaderColor = const Color(0xFF333333); 
    if (isActive && !node.isCompactToolNode) scratchpadHeaderColor = const Color(0xFF335533); 
    if (isPreview && !node.isCompactToolNode) scratchpadHeaderColor = Colors.amber.shade900; 

    Color pillBackgroundColor = isActive ? const Color(0xFF2E402E) : const Color(0xFF2A2A2A);

    return GestureDetector(
      onPanStart: (d) {
        graphState.requestUndoSnapshot(); 
        graphState.selectNode(nodeId, additive: HardwareKeyboard.instance.logicalKeysPressed.contains(LogicalKeyboardKey.shiftLeft));
      },
      onPanEnd: (_) => canvasState.onNodeDragEnd(nodeId, graphState),
      onPanUpdate: (d) {
        graphState.updateNodePosition(nodeId, d.delta);
        if (graphState.selectedNodeIds.length == 1) {
          canvasState.checkWireHover(nodeId, graphState);
        }
      },
      onTap: () => graphState.selectNode(nodeId, additive: HardwareKeyboard.instance.logicalKeysPressed.contains(LogicalKeyboardKey.shiftLeft)),
      onDoubleTap: () => graphState.setPreviewNode(nodeId),
      onSecondaryTapUp: (details) => _showContextMenu(context, details.globalPosition, nodeId),
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 200),
        opacity: isActive || isSelected || isPreview ? 1.0 : 0.65,
        child: SizedBox(
          width: kNodeWidth, 
          height: height,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned.fill(
                child: Container(
                  decoration: BoxDecoration(
                    color: node.isCompactToolNode ? pillBackgroundColor : kNodeBg,
                    borderRadius: BorderRadius.circular(borderRadius), 
                    border: Border.all(color: borderColor, width: borderWidth), 
                    boxShadow: shadows, 
                  ),
                  child: node.isCompactToolNode 
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 48.0, vertical: 8.0), 
                          child: _buildPillContent(node, index, isGenerating),
                        ),
                      )
                    : _buildScratchpadContent(node, index, scratchpadHeaderColor, borderRadius)
                ),
              ),

              Positioned(
                top: -9, 
                left: 0, right: 0,
                child: Center(
                  child: Container(
                    width: 18, height: 18, 
                    decoration: BoxDecoration(
                      color: (isHoverTarget && !isCycleHover) ? kSelectGlowColor : const Color(0xFF222222), 
                      shape: BoxShape.circle, 
                      border: Border.all(color: isCycleHover ? Colors.red : (isSelected ? kSelectGlowColor : Colors.white), width: 2.0)
                    ),
                  ),
                ),
              ),

              if (node.type != NodeType.output && node.type != NodeType.chat && node.type != NodeType.wikiWriter)
                Positioned(
                  bottom: -20, 
                  left: 0, right: 0, 
                  child: Center(
                    child: MouseRegion(
                      onEnter: (_) => setState(() => _isHoveringOutput = true),
                      onExit: (_) => setState(() => _isHoveringOutput = false),
                      cursor: SystemMouseCursors.click,
                      child: GestureDetector(
                        onPanStart: (_) => canvasState.startWireDrag(nodeId, graphState),
                        child: Container(
                          width: 40, height: 40, color: Colors.transparent, 
                          alignment: Alignment.center, 
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 150),
                            width: isSwapTarget ? 24 : 18, 
                            height: isSwapTarget ? 24 : 18,
                            decoration: BoxDecoration(
                              color: isSwapTarget ? Colors.purpleAccent : (_isHoveringOutput ? kSelectGlowColor : const Color(0xFF222222)),
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: isSwapTarget ? Colors.white : (_isHoveringOutput ? Colors.white : (isSelected ? kSelectGlowColor : Colors.white)), 
                                width: 2.0
                              ),
                              boxShadow: _isHoveringOutput || isSwapTarget 
                                  ? [BoxShadow(color: isSwapTarget ? Colors.purpleAccent : kSelectGlowColor, blurRadius: 10)] 
                                  : [],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                
              if (node.type != NodeType.output && node.type != NodeType.chat && node.type != NodeType.wikiWriter && node.nextNodeIds.length > 1)
                Positioned(
                  bottom: -12, right: 15,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2), 
                    decoration: BoxDecoration(
                      color: Colors.black87, 
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.white38, width: 1.5)
                    ),
                    child: Text("+${node.nextNodeIds.length - 1}", style: const TextStyle(fontSize: 10, color: Colors.white, fontWeight: FontWeight.bold)),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  void _showContextMenu(BuildContext context, Offset globalPos, String nodeId) {
    final graphState = context.read<GraphState>();
    final pos = RelativeRect.fromLTRB(globalPos.dx, globalPos.dy, globalPos.dx, globalPos.dy);
    showMenu(context: context, position: pos, items:[
      PopupMenuItem(child: const Text("Delete"), onTap: () { graphState.selectNode(nodeId); graphState.deleteSelected(); }),
      PopupMenuItem(child: const Text("Disconnect Outputs"), onTap: () => graphState.disconnectNode(nodeId)),
      if (graphState.nodes[nodeId]?.type == NodeType.scene)
        PopupMenuItem(child: const Text("Pop Out of Chain"), onTap: () => graphState.popNodeOut(nodeId)),
    ]);
  }
}

class ConnectionPainter extends CustomPainter {
  final GraphState graphState;
  final CanvasState canvasState;
  
  ConnectionPainter(this.graphState, this.canvasState);
  
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..style = PaintingStyle.stroke..strokeCap = StrokeCap.round;
    for (var node in graphState.nodes.values) {
      for (int i = 0; i < node.nextNodeIds.length; i++) {
        final target = graphState.nodes[node.nextNodeIds[i]];
        if (target == null) continue;
        bool isActive = graphState.activePathIds.contains(node.id) && graphState.activePathIds.contains(target.id);
        bool isHovered = (canvasState.hoveredWireSourceId == node.id && canvasState.hoveredWireIndex == i);
        
        paint.strokeWidth = isHovered ? 5.0 : (isActive ? 3.0 : 2.0);
        paint.color = isHovered ? Colors.cyanAccent : (isActive ? Colors.white70 : const Color(0xFF666666));
        
        if (isActive || isHovered) {
           _drawCurve(canvas, paint, node.outputPortGlobal, target.inputPortGlobal);
        } else {
           _drawDashedCurve(canvas, paint, node.outputPortGlobal, target.inputPortGlobal);
        }
      }
    }
    
    if (canvasState.draggingWireHead != null && canvasState.draggingWireSourceId != null) {
      final source = graphState.nodes[canvasState.draggingWireSourceId!]!;
      paint.color = canvasState.isInvalidCycle ? Colors.red : (canvasState.hoveredTargetId != null ? kSelectGlowColor : Colors.white54);
      if (canvasState.hoveredSwapTargetId != null) paint.color = Colors.purpleAccent;
      paint.strokeWidth = 3.0;
      
      Offset end = canvasState.draggingWireHead!;
      if (canvasState.hoveredTargetId != null) end = graphState.nodes[canvasState.hoveredTargetId!]!.inputPortGlobal;
      else if (canvasState.hoveredSwapTargetId != null) end = graphState.nodes[canvasState.hoveredSwapTargetId!]!.outputPortGlobal;
      
      _drawCurve(canvas, paint, source.outputPortGlobal, end);
    }
  }
  
  void _drawCurve(Canvas canvas, Paint paint, Offset start, Offset end) {
    final path = Path()..moveTo(start.dx, start.dy);
    double dist = (end.dy - start.dy).abs();
    double control = dist < 40 ? 20.0 : dist * 0.5;
    path.cubicTo(start.dx, start.dy + control, end.dx, end.dy - control, end.dx, end.dy);
    canvas.drawPath(path, paint);
  }
  
  void _drawDashedCurve(Canvas canvas, Paint paint, Offset start, Offset end) {
    final path = Path()..moveTo(start.dx, start.dy);
    double dist = (end.dy - start.dy).abs();
    double control = dist < 40 ? 20.0 : dist * 0.5;
    path.cubicTo(start.dx, start.dy + control, end.dx, end.dy - control, end.dx, end.dy);
    final metric = path.computeMetrics().first;
    final dashedPath = Path();
    for (double d = 0; d < metric.length; d += 20) dashedPath.addPath(metric.extractPath(d, d + 10), Offset.zero);
    canvas.drawPath(dashedPath, paint);
  }
  
  @override
  bool shouldRepaint(covariant ConnectionPainter old) => true;
}

class LassoLayer extends StatelessWidget {
  const LassoLayer({super.key});
  @override
  Widget build(BuildContext context) {
    final rect = context.select<CanvasState, Rect?>((s) => s.lassoRect);
    if (rect == null) return const SizedBox.shrink();
    return CustomPaint(painter: _LassoPainter(rect));
  }
}

class _LassoPainter extends CustomPainter {
  final Rect rect;
  _LassoPainter(this.rect);
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = kSelectGlowColor.withOpacity(0.1);
    final border = Paint()..color = kSelectGlowColor.withOpacity(0.6)..style = PaintingStyle.stroke..strokeWidth = 2.0;
    canvas.drawRect(rect, paint); 
    canvas.drawRect(rect, border);
  }
  @override
  bool shouldRepaint(covariant _LassoPainter old) => old.rect != rect;
}

class GridBackground extends StatelessWidget {
  const GridBackground({super.key});
  @override
  Widget build(BuildContext context) {
    final canvasState = context.read<CanvasState>();
    return ValueListenableBuilder<Matrix4>(
      valueListenable: canvasState.canvasController,
      builder: (context, matrix, _) {
        final scale = matrix.getMaxScaleOnAxis();
        return CustomPaint(painter: _GridPainter(matrix.getTranslation().x, matrix.getTranslation().y, scale));
      },
    );
  }
}

class _GridPainter extends CustomPainter {
  final double dx, dy, scale;
  _GridPainter(this.dx, this.dy, this.scale);
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = Colors.white.withOpacity(0.05)..strokeWidth = 1.5;
    final gridStep = 150.0 * scale; 
    double startX = (dx % gridStep) - gridStep;
    double startY = (dy % gridStep) - gridStep;
    for (double x = startX; x < size.width; x += gridStep) canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    for (double y = startY; y < size.height; y += gridStep) canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
  }
  @override
  bool shouldRepaint(covariant _GridPainter old) => old.dx != dx || old.dy != dy || old.scale != scale;
}