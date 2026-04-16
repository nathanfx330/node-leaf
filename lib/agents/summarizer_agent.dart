// --- File: lib/agents/summarizer_agent.dart ---

import '../constants.dart';
import '../models/node_models.dart';
import '../state/graph_state.dart';
import '../state/network_state.dart';
import '../services/ollama_service.dart';

class SummarizerAgent {
  static Future<void> execute({
    required StoryNode node,
    required List<StoryNode> sequence,
    required GraphState graphState,
    required NetworkState networkState,
    required Function() onUpdate,
  }) async {
    node.ollamaResult = "🤖 Gathering upstream context...\n"; 
    onUpdate();

    StringBuffer upstreamContext = StringBuffer();
    String customPersona = "";
    
    // 1. Gather Context
    for (var n in sequence) {
      if (n.type == NodeType.output || n.type == NodeType.chat || n.type == NodeType.study || n.type == NodeType.summarize || n.type == NodeType.wikiWriter || n.type == NodeType.council) continue;
      
      if (n.type == NodeType.persona) {
        customPersona = n.content.trim();
        continue;
      }

      if (n.type == NodeType.wikiReader && n.wikiTitle.isNotEmpty) {
        upstreamContext.writeln("\n>>> CURRENT WIKI PAGE STATE: '${n.wikiTitle}' <<<");
        upstreamContext.writeln(await graphState.readWikiPage(n.wikiTitle, networkState));
        upstreamContext.writeln(">>> END WIKI PAGE STATE <<<\n");
        continue;
      }
      
      if (n.type == NodeType.briefing) {
        upstreamContext.writeln("\n>>> REDLEAF SYSTEM BRIEFING <<<");
        upstreamContext.writeln(await networkState.redleafService.fetchSystemBriefing());
        if (n.content.trim().isNotEmpty) upstreamContext.writeln("\n[USER OVERRIDE / MANUAL CONTEXT]:\n${n.content.trim()}");
        upstreamContext.writeln(">>> END REDLEAF BRIEFING <<<\n");
      } else if (n.type == NodeType.search && n.content.isNotEmpty) {
        upstreamContext.writeln("\n>>> REDLEAF GLOBAL SEARCH: '${n.content}' <<<");
        upstreamContext.writeln(await networkState.redleafService.fetchAdvancedFtsContext(n.content, n.searchLimit, n.pinnedSearchResults));
        upstreamContext.writeln(">>> END REDLEAF SEARCH <<<\n");
      } else if (n.type == NodeType.document && n.content.isNotEmpty) {
        // --- START FIX ---
        upstreamContext.writeln("\n>>> REDLEAF DOCUMENT <<<");
        upstreamContext.writeln(await networkState.redleafService.fetchDocumentText(n));
        upstreamContext.writeln(">>> END REDLEAF DOCUMENT <<<\n");
        // --- END FIX ---
      } else if (n.type == NodeType.catalog && n.content.isNotEmpty) {
        final catId = int.tryParse(n.content);
        if (catId != null) {
          upstreamContext.writeln("\n>>> REDLEAF CATALOG <<<");
          upstreamContext.writeln(await networkState.redleafService.fetchCatalogContext(catId, n.title));
          upstreamContext.writeln(">>> END REDLEAF CATALOG <<<\n");
        }
      } else if (n.type == NodeType.intersection && n.redleafPills.isNotEmpty) {
        upstreamContext.writeln("\n>>> REDLEAF CO-MENTIONS <<<");
        upstreamContext.writeln(await networkState.redleafService.fetchIntersectionContext(n.redleafPills.map((p) => p.text).toList()));
        upstreamContext.writeln(">>> END REDLEAF CO-MENTIONS <<<\n");
      } else if (n.type == NodeType.relationship && n.redleafPills.isNotEmpty) {
        upstreamContext.writeln("\n>>> REDLEAF GRAPH <<<");
        upstreamContext.writeln(await networkState.redleafService.fetchEntityRelationships(n.redleafPills.first.entityId, n.redleafPills.first.text));
        upstreamContext.writeln(">>> END REDLEAF GRAPH <<<\n");
      } else if (n.type == NodeType.scene) {
        upstreamContext.writeln("\n=== [USER NOTE: ${n.title}] ===\n${n.content}\n");
        for (var pill in n.redleafPills) {
          upstreamContext.writeln(await networkState.redleafService.fetchContextForPill(pill));
        }
      }
    }

    node.ollamaResult = "🤖 Generating response...\n\n"; 
    onUpdate();
    
    String userInstructions = node.ollamaPrompt.isNotEmpty 
        ? node.ollamaPrompt 
        : "Please provide a comprehensive and detailed summary of the following context material.";

    String fullPayload = "$userInstructions\n\nCONTEXT TO PROCESS:\n${upstreamContext.isEmpty ? "None" : upstreamContext.toString()}";

    final currentDate = DateTime.now().toString().split('.')[0];
    String systemInstruction = "You are a helpful and analytical AI assistant.";
    if (customPersona.isNotEmpty) {
      systemInstruction = "YOUR ACTIVE PERSONA: $customPersona\n\nYou MUST adopt this persona completely in your writing style, tone, and perspective.";
    }
    systemInstruction = "CURRENT SYSTEM TIME: $currentDate\n\n$systemInstruction";

    try {
      final stream = OllamaService.generateTextStream(
        baseUrl: networkState.ollamaUrl,
        model: networkState.ollamaModel,
        prompt: fullPayload,
        system: systemInstruction,
      );
      
      await for (final chunk in stream) {
          bool isFirstToken = node.ollamaResult.contains("🤖 Generating response...\n\n");
          if (isFirstToken) node.ollamaResult = ""; 
          node.ollamaResult += chunk; 
          onUpdate(); 
      }
    } catch (e) { 
      node.ollamaResult = "⚠️ Failed to connect to Ollama.\nError details: $e"; 
      onUpdate(); 
    }
  }
}