// --- File: lib/agents/wiki_writer_agent.dart ---
import 'dart:convert';

import '../constants.dart'; // <-- THIS WAS MISSING!
import '../models/node_models.dart';
import '../state/graph_state.dart';
import '../state/network_state.dart';
import '../services/ollama_service.dart';

class WikiWriterAgent {
  static Future<void> execute({
    required StoryNode node,
    required List<StoryNode> sequence,
    required GraphState graphState,
    required NetworkState networkState,
    required Function() onUpdate,
  }) async {
    node.ollamaResult = "🤖 Gathering upstream context and reading Wiki...\n"; 
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

       if (n.type == NodeType.study && n.ollamaResult.isNotEmpty) {
         upstreamContext.writeln("\n>>> FACTUAL CONTEXT FROM DEEP STUDY: '${n.content}' <<<");
         upstreamContext.writeln(n.ollamaResult);
         upstreamContext.writeln(">>> END DEEP STUDY <<<\n");
         continue;
       }
       
       if (n.type == NodeType.chat && n.chatHistory.isNotEmpty) {
         upstreamContext.writeln("\n>>> CONTEXT FROM CHAT LOG <<<");
         for (var msg in n.chatHistory) {
           upstreamContext.writeln("${(msg['role'] ?? 'unknown').toUpperCase()}: ${msg['content']}");
         }
         upstreamContext.writeln(">>> END CHAT LOG <<<\n");
         continue;
       }

       // Add standard context
       if (n.type == NodeType.briefing) {
         upstreamContext.writeln("\n>>> REDLEAF SYSTEM BRIEFING <<<\n${await networkState.redleafService.fetchSystemBriefing()}\n>>> END REDLEAF BRIEFING <<<\n");
       } else if (n.type == NodeType.search && n.content.isNotEmpty) {
         upstreamContext.writeln("\n>>> REDLEAF GLOBAL SEARCH: '${n.content}' <<<\n${await networkState.redleafService.fetchAdvancedFtsContext(n.content, n.searchLimit, n.pinnedSearchResults)}\n>>> END REDLEAF SEARCH <<<\n");
       } else if (n.type == NodeType.document && n.content.isNotEmpty) {
         upstreamContext.writeln("\n>>> REDLEAF DOCUMENT <<<\n${await networkState.redleafService.fetchDocumentText(n.content)}\n>>> END REDLEAF DOCUMENT <<<\n");
       } else if (n.type == NodeType.catalog && n.content.isNotEmpty) {
         final catId = int.tryParse(n.content);
         if (catId != null) upstreamContext.writeln("\n>>> REDLEAF CATALOG <<<\n${await networkState.redleafService.fetchCatalogContext(catId, n.title)}\n>>> END REDLEAF CATALOG <<<\n");
       } else if (n.type == NodeType.intersection && n.redleafPills.isNotEmpty) {
         upstreamContext.writeln("\n>>> REDLEAF CO-MENTIONS <<<\n${await networkState.redleafService.fetchIntersectionContext(n.redleafPills.map((p) => p.text).toList())}\n>>> END REDLEAF CO-MENTIONS <<<\n");
       } else if (n.type == NodeType.relationship && n.redleafPills.isNotEmpty) {
         upstreamContext.writeln("\n>>> REDLEAF GRAPH <<<\n${await networkState.redleafService.fetchEntityRelationships(n.redleafPills.first.entityId, n.redleafPills.first.text)}\n>>> END REDLEAF GRAPH <<<\n");
       } else if (n.type == NodeType.scene) {
         upstreamContext.writeln("\n=== [USER NOTE: ${n.title}] ===\n${n.content}\n");
         for (var pill in n.redleafPills) upstreamContext.writeln(await networkState.redleafService.fetchContextForPill(pill));
       }
    }

    node.ollamaResult = "🤖 Editing Wiki Page...\n\n"; onUpdate();
    
    String userInstructions = node.ollamaPrompt.isNotEmpty 
        ? node.ollamaPrompt 
        : "Review the CURRENT WIKI PAGE STATE and the NEW RESEARCH. Update the wiki page.";

    String fullPayload = "$userInstructions\n\nCONTEXT TO PROCESS:\n${upstreamContext.isEmpty ? "None" : upstreamContext.toString()}";

    final currentDate = DateTime.now().toString().split('.')[0];
    
    String systemInstruction = '''You are an expert Wikipedia Editor and Fact Checker.
Your task is to rewrite, expand, and format the target wiki page to seamlessly incorporate new facts from the provided context.

RULES:
1. If the new research agrees with the current wiki, seamlessly expand the article.
2. If the new research CONTRADICTS the current wiki, you MUST preserve the controversy. Do not erase the old claim; instead, write: 'While previous documents suggested X, newly analyzed [Doc Y] indicates Z.'
3. You MUST include inline citations like [Doc X] when adding new facts based on the REDLEAF context.
4. You MUST append a bullet point to the '### Revision History' section at the bottom of the file detailing exactly what you changed today and why. (Create this section if it doesn't exist).
5. Output ONLY valid Markdown. Do NOT wrap your response in markdown code blocks (e.g., no ```markdown). Output the raw text directly.''';

    if (customPersona.isNotEmpty) {
      systemInstruction = "YOUR ACTIVE PERSONA: $customPersona\n\n$systemInstruction\nYou MUST adopt this persona completely in your writing style, tone, and perspective while adhering to the editing rules.";
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
          bool isFirstToken = node.ollamaResult.contains("🤖 Editing Wiki Page...\n\n");
          if (isFirstToken) node.ollamaResult = ""; 
          node.ollamaResult += chunk; 
          onUpdate(); 
      }
      
      // Post-generation task: Write to disk
      if (node.wikiTitle.isNotEmpty && node.ollamaResult.isNotEmpty) {
          bool success = await graphState.writeWikiPage(node.wikiTitle, node.ollamaResult.trim(), networkState);
          if (success) {
              node.ollamaResult += "\n\n[System: Successfully saved to Wiki/${node.wikiTitle}.md]";
          } else {
              node.ollamaResult += "\n\n[System Error: Failed to save to Wiki/${node.wikiTitle}.md]";
          }
          onUpdate();
      }
    } catch (e) { 
      node.ollamaResult = "⚠️ Failed to connect to Ollama.\nError details: $e"; 
      onUpdate(); 
    }
  }
}