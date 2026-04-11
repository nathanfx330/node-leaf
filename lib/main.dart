// --- File: lib/main.dart ---
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'constants.dart';
import 'state/network_state.dart';
import 'state/graph_state.dart';
import 'state/canvas_state.dart';
import 'ui/top_bar.dart';
import 'ui/canvas_view.dart';
import 'ui/side_panel.dart';

void main() {
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => NetworkState()),
        ChangeNotifierProvider(create: (_) => CanvasState()),
        // GraphState needs NetworkState initialized first to pass into newProject
        ChangeNotifierProvider(create: (context) {
          final networkState = context.read<NetworkState>();
          final graphState = GraphState();
          
          // --- FIXED: Defer the initialization to prevent "setState during build" crash ---
          WidgetsBinding.instance.addPostFrameCallback((_) {
            graphState.newProject(networkState);
          });
          
          return graphState;
        }),
      ],
      child: const NodeLeafApp(),
    ),
  );
}

class NodeLeafApp extends StatelessWidget {
  const NodeLeafApp({super.key});
  
  @override
  Widget build(BuildContext context) {
    // We listen to GraphState for the project name and shortcuts
    final graphState = context.watch<GraphState>();
    // We only need to read NetworkState to pass it into the save/load functions
    final networkState = context.read<NetworkState>();

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.delete): () => graphState.deleteSelected(),
        const SingleActivator(LogicalKeyboardKey.backspace): () => graphState.deleteSelected(),
        const SingleActivator(LogicalKeyboardKey.keyZ, control: true): () => graphState.undo(),
        const SingleActivator(LogicalKeyboardKey.keyC, control: true): () => graphState.copySelection(),
        const SingleActivator(LogicalKeyboardKey.keyV, control: true): () => graphState.paste(),
        const SingleActivator(LogicalKeyboardKey.keyS, control: true): () => graphState.saveProject(networkState),
        const SingleActivator(LogicalKeyboardKey.keyS, control: true, shift: true): () => graphState.saveAsProject(networkState),
        const SingleActivator(LogicalKeyboardKey.keyO, control: true): () => graphState.loadProject(networkState),
      },
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        title: "${graphState.projectName} - Node Leaf",
        theme: ThemeData.dark().copyWith(
          scaffoldBackgroundColor: kCanvasBg, 
          cardColor: const Color(0xFF222222),
          colorScheme: const ColorScheme.dark(primary: kAccentColor),
        ),
        home: const MainLayout(),
      ),
    );
  }
}

class MainLayout extends StatefulWidget {
  const MainLayout({super.key});
  @override
  State<MainLayout> createState() => _MainLayoutState();
}

class _MainLayoutState extends State<MainLayout> {
  double _sidePanelWidth = 400.0;
  
  @override
  Widget build(BuildContext context) {
    final canvasState = context.watch<CanvasState>();
    final graphState = context.read<GraphState>();

    return Scaffold(
      body: Row(
        children: [
          Expanded(
            child: Column(
              children:[
                const TopBar(),
                Expanded(
                  child: ClipRect(
                    child: Stack(
                      children:[
                        const Positioned.fill(child: GridBackground()),
                        const NodeCanvas(),
                        Positioned(
                          left: 20, top: 20,
                          child: PopupMenuButton<NodeType>(
                            offset: const Offset(0, 60),
                            onSelected: (type) {
                              final size = MediaQuery.of(context).size;
                              final matrix = canvasState.canvasController.value;
                              final scale = matrix.getMaxScaleOnAxis();
                              final translation = matrix.getTranslation();
                              final center = Offset((size.width / 2 - translation.x) / scale, (size.height / 2 - translation.y) / scale);
                              
                              graphState.addNode(center, type);
                            },
                            itemBuilder: (ctx) => const [
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
                              PopupMenuItem(value: NodeType.chat, child: Text("💬 Add Ollama Chat")), 
                              PopupMenuItem(value: NodeType.wikiWriter, child: Text("🖋️ Add Wiki Writer")),
                              PopupMenuItem(value: NodeType.council, child: Text("🏛️ Add Wiki Council")), 
                              PopupMenuItem(value: NodeType.researchParty, child: Text("🏕️ Add Research Party")), 
                            ],
                            child: FloatingActionButton.extended(
                              backgroundColor: kNodeBg, foregroundColor: Colors.white,
                              onPressed: null, 
                              icon: const Icon(Icons.add),
                              label: const Text("ADD NODE", style: TextStyle(fontWeight: FontWeight.bold)),
                            ),
                          )
                        )
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          MouseRegion(
            cursor: SystemMouseCursors.resizeColumn,
            child: GestureDetector(
              onPanUpdate: (details) {
                setState(() {
                  _sidePanelWidth -= details.delta.dx;
                  if (_sidePanelWidth < 250) _sidePanelWidth = 250;
                  if (_sidePanelWidth > 800) _sidePanelWidth = 800;
                });
              },
              child: Container(width: 5, color: kCanvasBg, child: Center(child: Container(width: 1, color: Colors.white.withOpacity(0.1)))),
            ),
          ),
          SizedBox(width: _sidePanelWidth, child: const SidePanel()),
        ],
      ),
    );
  }
}