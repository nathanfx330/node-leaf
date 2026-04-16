// --- File: lib/agents/research_party_agent.dart ---
import 'dart:convert';

import '../constants.dart';
import '../models/node_models.dart';
import '../state/graph_state.dart';
import '../state/network_state.dart';
import '../services/ollama_service.dart';

class ResearchPartyAgent {
  
  static Map<String, dynamic> _parseAgentJSON(String response) {
    try {
      String clean = response.replaceAll('```json', '').replaceAll('```', '').trim();
      return jsonDecode(clean);
    } catch (e) {
      return {"topics": []};
    }
  }

  static Future<void> execute({
    required StoryNode node,
    required List<StoryNode> sequence,
    required GraphState graphState,
    required NetworkState networkState,
    required bool Function() checkForceAnswer,
    required Function() onUpdate,
  }) async {
    node.ollamaResult = "🏕️ Research Party: Packing gear and reviewing maps...\n";
    onUpdate();

    StringBuffer upstreamContext = StringBuffer();
    String directive = node.content.isNotEmpty ? node.content : "Explore the database for new insights.";

    // 1. Gather Upstream Context (Same as others)
    for (var n in sequence) {
      if (n.type == NodeType.output || n.type == NodeType.chat || n.type == NodeType.study || n.type == NodeType.summarize || n.type == NodeType.wikiWriter || n.type == NodeType.council || n.type == NodeType.researchParty) continue;
      
      if (n.type == NodeType.wikiReader && n.wikiTitle.isNotEmpty) {
        upstreamContext.writeln("\n>>> UNVERIFIED MAP (WIKI PAGE): '${n.wikiTitle}' <<<");
        upstreamContext.writeln(await graphState.readWikiPage(n.wikiTitle, networkState));
        upstreamContext.writeln(">>> END WIKI PAGE <<<\n");
        continue;
      }
      
      if (n.type == NodeType.briefing) {
        upstreamContext.writeln("\n>>> REDLEAF SYSTEM BRIEFING <<<\n${await networkState.redleafService.fetchSystemBriefing()}\n>>> END REDLEAF BRIEFING <<<\n");
      } else if (n.type == NodeType.search && n.content.isNotEmpty) {
        upstreamContext.writeln("\n>>> REDLEAF GLOBAL SEARCH: '${n.content}' <<<\n${await networkState.redleafService.fetchAdvancedFtsContext(n.content, n.searchLimit, n.pinnedSearchResults)}\n>>> END REDLEAF SEARCH <<<\n");
      } else if (n.type == NodeType.document && n.content.isNotEmpty) {
        // --- START FIX ---
        upstreamContext.writeln("\n>>> REDLEAF DOCUMENT <<<\n${await networkState.redleafService.fetchDocumentText(n)}\n>>> END REDLEAF DOCUMENT <<<\n");
        // --- END FIX ---
      }
    }

    // 2. Fetch the Wiki Knowledge Graph (to show what is known vs unknown)
    StringBuffer wikiGraphContext = StringBuffer();
    final sortedPages = graphState.wikiNodeRanks.keys.toList()
      ..sort((a, b) => graphState.wikiNodeRanks[b]!.compareTo(graphState.wikiNodeRanks[a]!));
    wikiGraphContext.writeln("KNOWN TERRITORY (Treat as unverified rumors / rough maps):");
    for (int i = 0; i < sortedPages.length && i < 10; i++) {
      wikiGraphContext.writeln("- ${sortedPages[i]}");
    }

    // --- PHASE 1: THE SCOUT ---
    node.ollamaResult += "\n> [Scout] Surveying the territory based on Directive: '$directive'\n"; onUpdate();

    final scoutPrompt = """You are the Scout for a Research Party.
Your Directive: "$directive"

KNOWN TERRITORY (Treat as unverified rumors or outdated maps):
${wikiGraphContext.toString()}

UPSTREAM CONTEXT:
${upstreamContext.isEmpty ? "None" : upstreamContext.toString()}

Task: Based on the Directive and what is currently known, identify 2 specific, distinct topics or entities to forage for in the Redleaf Database. You are looking for hard, primary-source evidence.
Return JSON ONLY:
{
  "topics": ["Specific Search Query 1", "Specific Search Query 2"]
}""";

    List<String> topicsToForage = [];
    try {
      final responseText = await OllamaService.generateText(
        baseUrl: networkState.ollamaUrl,
        model: networkState.ollamaModel,
        prompt: scoutPrompt,
        format: "json",
      );
      final scoutJson = _parseAgentJSON(responseText);
      if (scoutJson['topics'] is List) {
        topicsToForage = List<String>.from(scoutJson['topics']);
      }
    } catch (e) {
      node.ollamaResult += "> [Scout Error: $e]\n"; onUpdate();
      return;
    }

    if (topicsToForage.isEmpty) {
        topicsToForage = [directive]; // Fallback to directive
    }

    if (checkForceAnswer()) return;

    // --- PHASE 2: FORAGING (The ReAct Loop) ---
    StringBuffer foragedFacts = StringBuffer();

    for (String topic in topicsToForage) {
        if (checkForceAnswer()) break;

        node.ollamaResult += "\n> [Forager] Searching Redleaf primary sources for: '$topic'...\n"; onUpdate();
        
        final searchContext = await networkState.redleafService.fetchFtsContext(topic);
        
        if (searchContext.contains("[No results found")) {
          node.ollamaResult += "  - No primary source data found. Skipping.\n"; onUpdate();
          continue;
        }

        node.ollamaResult += "> [Forager] Extracting verified facts...\n"; onUpdate();
        final factPrompt = """You are a Forager. Extract ONLY verified facts, numbers, and direct primary evidence about "$topic".
Text to Analyze:
$searchContext

FORAGING TASK: 
1. Extract specific facts. 
2. You MUST preserve the [Doc X] citations. 
If nothing is relevant, return "Nothing relevant." """;

        try {
          final extractedNotes = await OllamaService.generateText(
            baseUrl: networkState.ollamaUrl,
            model: networkState.ollamaModel,
            prompt: factPrompt,
          );
          if (!extractedNotes.contains("Nothing relevant")) {
            foragedFacts.writeln("\nVERIFIED EVIDENCE FOR '$topic':\n$extractedNotes");
          }
        } catch(e) {
            node.ollamaResult += "  - [Error during extraction: $e]\n"; onUpdate();
        }
    }

    if (checkForceAnswer()) return;

    // --- PHASE 3: CAMPFIRE SYNTHESIS ---
    node.ollamaResult += "\n🏕️ Campfire Synthesis: Writing grounded report...\n\n"; onUpdate();
    
    final synthesisPrompt = """You are the Chronicler of the Research Party.
Directive: "$directive"

Your party has returned with hard facts verified directly from the Redleaf Database.
Your task is to write a definitive, grounded intelligence report based ONLY on the Foraged Evidence.

CRITICAL INSTRUCTIONS:
1. Treat any existing Wiki knowledge as unverified rumors or outdated maps. Overwrite any assumptions with the verified facts below.
2. You MUST include inline citations like [Doc X] when stating facts derived from the foraging.
3. Use double brackets like [[Concept Name]] to suggest links to existing or new Wiki pages.

FORAGED EVIDENCE (VERIFIED):
${foragedFacts.isEmpty ? "No verified facts found. Report that the territory is barren." : foragedFacts.toString()}""";

    String systemInstruction = "CURRENT SYSTEM TIME: ${DateTime.now()}\n\nYou are a factual, expedition reporting agent.";

    try {
      final stream = OllamaService.generateTextStream(
        baseUrl: networkState.ollamaUrl,
        model: networkState.ollamaModel,
        prompt: synthesisPrompt,
        system: systemInstruction,
      );
      
      await for (final chunk in stream) {
          bool isFirstToken = node.ollamaResult.contains("🏕️ Campfire Synthesis: Writing grounded report...\n\n");
          if (isFirstToken) node.ollamaResult = ""; 
          node.ollamaResult += chunk; 
          onUpdate(); 
      }
    } catch (e) { 
      node.ollamaResult += "\n⚠️ Failed to generate report.\nError details: $e"; 
      onUpdate(); 
    }
  }
}