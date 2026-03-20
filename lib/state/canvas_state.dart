// --- File: lib/state/canvas_state.dart ---
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../constants.dart';
import '../models/node_models.dart';
import 'graph_state.dart';

class CanvasState extends ChangeNotifier {
  final TransformationController canvasController = TransformationController();
  final GlobalKey canvasKey = GlobalKey(); 

  // --- LASSO SELECTION ---
  Rect? _lassoRect;
  Offset? _lassoStart;

  // --- WIRE DRAGGING & HOVERING ---
  String? _draggingWireSourceId;
  Offset? _draggingWireHead;
  String? _hoveredTargetId;
  String? _hoveredSwapTargetId;
  
  // For inserting a node into an existing wire
  String? _hoveredWireSourceId;
  int _hoveredWireIndex = -1;
  
  bool _isInvalidCycle = false;

  CanvasState() {
    resetCanvas();
  }

  // Getters
  Rect? get lassoRect => _lassoRect;
  String? get draggingWireSourceId => _draggingWireSourceId;
  Offset? get draggingWireHead => _draggingWireHead;
  String? get hoveredTargetId => _hoveredTargetId;
  String? get hoveredSwapTargetId => _hoveredSwapTargetId;
  String? get hoveredWireSourceId => _hoveredWireSourceId;
  int get hoveredWireIndex => _hoveredWireIndex;
  bool get isInvalidCycle => _isInvalidCycle;

  // --- VIEWPORT MANAGEMENT ---

  void resetCanvas() {
    canvasController.value = Matrix4.identity()..translate(-kWorldSize / 2 + 600, -kWorldSize / 2 + 350);
    notifyListeners();
  }

  void panCanvas(Offset delta) { 
    canvasController.value = canvasController.value.clone()..translate(delta.dx, delta.dy); 
    // We don't necessarily need to notifyListeners here because InteractiveViewer handles its own redraws,
    // but if you have custom overlays attached to the canvas controller, you might need it.
  }

  Offset screenToCanvas(Offset screenPos) { 
    final matrix = canvasController.value; 
    final scale = matrix.getMaxScaleOnAxis(); 
    final translation = matrix.getTranslation(); 
    return Offset((screenPos.dx - translation.x) / scale, (screenPos.dy - translation.y) / scale); 
  }

  void jumpToNode(String id, GraphState graphState) {
    if (!graphState.nodes.containsKey(id)) return;
    
    graphState.selectNode(id); 
    graphState.setPreviewNode(null);
    
    final nodePos = graphState.nodes[id]!.position;
    final currentScale = canvasController.value.getMaxScaleOnAxis();
    
    double viewWidth = 800.0, viewHeight = 600.0;
    if (canvasKey.currentContext != null) { 
      final renderBox = canvasKey.currentContext!.findRenderObject() as RenderBox; 
      viewWidth = renderBox.size.width; 
      viewHeight = renderBox.size.height; 
    }
    
    final targetX = (viewWidth / 2 / currentScale) - (nodePos.dx + (kNodeWidth / 2));
    final targetY = (viewHeight / 2 / currentScale) - (nodePos.dy + (kNodeHeight / 2));
    
    canvasController.value = Matrix4.identity()..scale(currentScale)..translate(targetX, targetY);
    notifyListeners();
  }

  // --- LASSO LOGIC ---

  void startLasso(Offset screenPos, GraphState graphState) { 
    _lassoStart = screenToCanvas(screenPos); 
    _lassoRect = Rect.fromPoints(_lassoStart!, _lassoStart!); 
    graphState.clearSelection(); 
    notifyListeners(); 
  }
  
  void updateLasso(Offset screenPos, GraphState graphState) { 
    if (_lassoStart == null) return; 
    _lassoRect = Rect.fromPoints(_lassoStart!, screenToCanvas(screenPos)); 
    graphState.selectNodesInRect(_lassoRect!);
    notifyListeners(); 
  }
  
  void endLasso() { 
    _lassoRect = null; 
    _lassoStart = null; 
    notifyListeners(); 
  }

  // --- WIRE DRAGGING & CONNECTION LOGIC ---

  void startWireDrag(String sourceId, GraphState graphState) { 
    graphState.recordUndo(); 
    _draggingWireSourceId = sourceId; 
    _draggingWireHead = graphState.nodes[sourceId]!.outputPortGlobal; 
    notifyListeners(); 
  }

  void updateWireDrag(Offset screenPos, GraphState graphState) {
    _draggingWireHead = screenToCanvas(screenPos);
    _hoveredTargetId = null; 
    _hoveredSwapTargetId = null; 
    _isInvalidCycle = false;

    for (var node in graphState.nodes.values) {
      if (node.id == _draggingWireSourceId) continue;
      
      // Check input port proximity (Connecting)
      if ((_draggingWireHead! - node.inputPortGlobal).distance < 60) {
        _hoveredTargetId = node.id;
        if (_detectCycle(_draggingWireSourceId!, node.id, graphState.nodes)) {
          _isInvalidCycle = true; 
        }
        break;
      }
      
      // Check output port proximity (Swapping/Stealing connections)
      if (node.type != NodeType.output && (_draggingWireHead! - node.outputPortGlobal).distance < 60) { 
        _hoveredSwapTargetId = node.id; 
        break; 
      }
    }
    notifyListeners();
  }

  void endWireDrag(GraphState graphState) {
    if (_draggingWireSourceId != null && !_isInvalidCycle) {
      if (_hoveredTargetId != null) { 
        graphState.connectNode(_draggingWireSourceId!, _hoveredTargetId!); 
      } else if (_hoveredSwapTargetId != null) {
        graphState.swapNodeConnections(_draggingWireSourceId!, _hoveredSwapTargetId!);
      }
    }
    
    // Reset state
    _draggingWireSourceId = null; 
    _draggingWireHead = null; 
    _hoveredTargetId = null; 
    _hoveredSwapTargetId = null; 
    _isInvalidCycle = false; 
    
    notifyListeners();
  }

  // --- WIRE HOVERING (For Inserting Nodes) ---

  void checkWireHover(String draggingNodeId, GraphState graphState) {
    final keys = HardwareKeyboard.instance.logicalKeysPressed;
    final isShift = keys.contains(LogicalKeyboardKey.shiftLeft) || keys.contains(LogicalKeyboardKey.shiftRight);
    
    _hoveredWireSourceId = null; 
    _hoveredWireIndex = -1;

    if (isShift && graphState.nodes.containsKey(draggingNodeId)) {
      final nodeCenter = graphState.nodes[draggingNodeId]!.rect.center;
      
      for (var source in graphState.nodes.values) {
        if (source.id == draggingNodeId) continue;
        
        for (int i = 0; i < source.nextNodeIds.length; i++) {
          final targetId = source.nextNodeIds[i];
          if (targetId == draggingNodeId || !graphState.nodes.containsKey(targetId)) continue;
          
          final target = graphState.nodes[targetId]!;
          if (_distanceToLineSegment(nodeCenter, source.outputPortGlobal, target.inputPortGlobal) < 50) { 
            _hoveredWireSourceId = source.id; 
            _hoveredWireIndex = i; 
            return; 
          }
        }
      }
    }
  }

  void onNodeDragEnd(String droppedNodeId, GraphState graphState) {
    if (_hoveredWireSourceId != null && _hoveredWireIndex != -1) {
      graphState.insertNodeIntoWire(_hoveredWireSourceId!, _hoveredWireIndex, droppedNodeId);
      
      _hoveredWireSourceId = null; 
      _hoveredWireIndex = -1; 
      notifyListeners();
    }
  }

  // --- MATH UTILS ---

  double _distanceToLineSegment(Offset p, Offset a, Offset b) { 
    final double l2 = (a - b).distanceSquared; 
    if (l2 == 0) return (p - a).distance; 
    double t = ((p.dx - a.dx) * (b.dx - a.dx) + (p.dy - a.dy) * (b.dy - a.dy)) / l2; 
    t = math.max(0, math.min(1, t)); 
    return (p - (a + (b - a) * t)).distance; 
  }

  bool _detectCycle(String sourceId, String targetId, Map<String, StoryNode> nodes) { 
    if (sourceId == targetId) return true; 
    Set<String> visited = {}; 
    List<String> stack = [targetId]; 
    while (stack.isNotEmpty) { 
      final curr = stack.removeLast(); 
      if (curr == sourceId) return true; 
      if (!visited.add(curr)) continue; 
      if (nodes.containsKey(curr)) stack.addAll(nodes[curr]!.nextNodeIds); 
    } 
    return false; 
  }
}