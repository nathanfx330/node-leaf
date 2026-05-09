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
      // 1. Strip markdown formatting just in case it ignored the prompt
      String clean = response.replaceAll(RegExp(r'```(?:json)?'), '').trim();
      
      // 2. Extract just the JSON block if the LLM added conversational filler before or after
      final int startIndex = clean.indexOf('{');
      final int endIndex = clean.lastIndexOf('}');
      if (startIndex != -1 && endIndex != -1 && endIndex >= startIndex) {
          clean = clean.substring(startIndex, endIndex + 1);
      }

      // 3. Fix trailing commas before closing braces/brackets (Extremely common LLM mistake)
      clean = clean.replaceAll(RegExp(r',\s*\}'), '}');
      clean = clean.replaceAll(RegExp(r',\s*\]'), ']');
      
      return jsonDecode(clean);
    } catch (e) {
      // If it still fails to parse, return an empty array so the agent uses the fallback query
      return {"searches": []};
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
    // Keep UI fun and engaging
    node.ollamaResult = "🏕️ Research Party: Packing gear and reviewing maps...\n";
    onUpdate();

    StringBuffer upstreamContext = StringBuffer();
    String directive = node.content.isNotEmpty ? node.content : "Explore the database for new insights.";

    // 1. Gather Upstream Context
    for (var n in sequence) {
      if (n.type == NodeType.output || n.type == NodeType.chat || n.type == NodeType.study || n.type == NodeType.summarize || n.type == NodeType.wikiWriter || n.type == NodeType.council || n.type == NodeType.researchParty || n.type == NodeType.merge) continue;
      
      if (n.type == NodeType.wikiReader && n.wikiTitle.isNotEmpty) {
        upstreamContext.writeln("\n>>> UNVERIFIED WIKI PAGE: '${n.wikiTitle}' <<<");
        upstreamContext.writeln(await graphState.readWikiPage(n.wikiTitle, networkState));
        upstreamContext.writeln(">>> END WIKI PAGE <<<\n");
        continue;
      }
      
      if (n.type == NodeType.briefing) {
        upstreamContext.writeln("\n>>> REDLEAF SYSTEM BRIEFING <<<\n${await networkState.redleafService.fetchSystemBriefing()}\n>>> END REDLEAF BRIEFING <<<\n");
      } else if (n.type == NodeType.search && n.content.isNotEmpty) {
        upstreamContext.writeln("\n>>> REDLEAF GLOBAL SEARCH: '${n.content}' <<<\n${await networkState.redleafService.fetchAdvancedFtsContext(n.content, n.searchLimit, n.pinnedSearchResults)}\n>>> END REDLEAF SEARCH <<<\n");
      } else if (n.type == NodeType.document && n.content.isNotEmpty) {
        upstreamContext.writeln("\n>>> REDLEAF DOCUMENT <<<\n${await networkState.redleafService.fetchDocumentText(n)}\n>>> END REDLEAF DOCUMENT <<<\n");
      }
    }

    // 2. Fetch the Wiki Knowledge Graph
    StringBuffer wikiGraphContext = StringBuffer();
    final sortedPages = graphState.wikiNodeRanks.keys.toList()
      ..sort((a, b) => graphState.wikiNodeRanks[b]!.compareTo(graphState.wikiNodeRanks[a]!));
    wikiGraphContext.writeln("EXISTING WIKI NETWORK (Topics currently documented):");
    for (int i = 0; i < sortedPages.length && i < 10; i++) {
      wikiGraphContext.writeln("- ${sortedPages[i]}");
    }

    // --- PHASE 1: THE SCOUT ---
    node.ollamaResult += "\n> [Scout] Surveying the territory based on Directive: '$directive'\n"; onUpdate();

    // LLM Prompt: Strict and sterile
    final scoutPrompt = """You are a Lead Data Strategist.
Your Directive: "$directive"

EXISTING WIKI NETWORK:
${wikiGraphContext.toString()}

UPSTREAM CONTEXT:
${upstreamContext.isEmpty ? "None" : upstreamContext.toString()}

Task: Based on the Directive and existing knowledge, identify 2 distinct search strategies to extract hard, primary-source evidence from the Redleaf Database.

CRITICAL SEARCH ENGINE RULES:
1. The search engine uses simple keyword matching. DO NOT use boolean operators (AND, OR), parentheses, or quotes.
2. Do NOT provide multi-lingual queries in the same string. Pick one language per search.
3. For entities, "mode" must be one of: "doc" (appears in document), "page" (appears on same page), or "exclude" (MUST NOT appear in the document).
4. Use "exclude" to filter out known noise or unrelated topics. 
5. You control the "limit" of documents returned (between 1 and 15). Use a higher limit (10-15) for broad overviews, and a lower limit (1-5) for targeted, highly specific facts.

File types available: ["PDF", "TXT", "HTML", "SRT" (transcripts), "EML" (emails)].
Entity labels available: PERSON, ORG, GPE (Geopolitical), LOC (Location), DATE, EVENT.

CRITICAL INSTRUCTION: Return ONLY valid, parseable JSON exactly matching this structure. Use the "exclude" mode if you need to bypass a specific topic.
{
  "searches": [
    {
      "query": "Specific keyword search",
      "required_entities": [
          {"text": "Main Topic", "label": "ORG", "mode": "doc"},
          {"text": "Irrelevant Topic", "label": "PERSON", "mode": "exclude"}
      ],
      "file_types": [],
      "limit": 8
    }
  ]
}""";

    List<Map<String, dynamic>> searchesToForage = [];
    try {
      final responseText = await OllamaService.generateText(
        baseUrl: networkState.ollamaUrl,
        model: networkState.ollamaModel,
        prompt: scoutPrompt,
        format: "json",
      );
      final scoutJson = _parseAgentJSON(responseText);
      if (scoutJson['searches'] is List) {
        searchesToForage = List<Map<String, dynamic>>.from(scoutJson['searches']);
      } else if (scoutJson['topics'] is List) {
        searchesToForage = (scoutJson['topics'] as List).map((t) => {"query": t.toString()}).toList();
      }
    } catch (e) {
      node.ollamaResult += "> [Scout Error: $e]\n"; onUpdate();
      return;
    }

    if (searchesToForage.isEmpty) {
        searchesToForage = [{"query": directive, "required_entities": [], "file_types": [], "limit": node.searchLimit}]; // Fallback
    }

    if (checkForceAnswer()) return;

    // --- PHASE 2: FORAGING (The ReAct Loop) ---
    StringBuffer foragedFacts = StringBuffer();

    for (var searchConfig in searchesToForage) {
        if (checkForceAnswer()) break;
        
        final query = searchConfig['query'] ?? '';
        final List<dynamic> rawEntities = searchConfig['required_entities'] ?? [];
        final List<dynamic> rawFileTypes = searchConfig['file_types'] ?? [];
        
        // --- NEW: Extract dynamic limit safely ---
        int dynamicLimit = node.searchLimit;
        if (searchConfig.containsKey('limit') && searchConfig['limit'] is int) {
            dynamicLimit = (searchConfig['limit'] as int).clamp(1, 15);
        }
        
        String logDesc = "Query: '${query.isEmpty ? 'None' : query}', Entities: ${rawEntities.length}, Types: ${rawFileTypes.isEmpty ? 'All' : rawFileTypes.join(', ')}, Limit: $dynamicLimit";

        node.ollamaResult += "\n> [Forager] Searching Redleaf primary sources ($logDesc)...\n"; onUpdate();
        
        final searchContext = await networkState.redleafService.fetchAdvancedAgentContext(
          networkState: networkState, 
          query: query,
          entities: rawEntities,
          fileTypes: rawFileTypes.map((e) => e.toString()).toList(),
          limit: dynamicLimit, 
        );
        
        if (searchContext.contains("[No results found")) {
          node.ollamaResult += "  - No primary source data found. Skipping.\n"; onUpdate();
          continue;
        }

        node.ollamaResult += "> [Forager] Extracting verified facts...\n"; onUpdate();
        final factPrompt = """You are a strict Data Extractor. Extract ONLY verified facts, numbers, and direct primary evidence answering this context parameter: "$logDesc".
Text to Analyze:
$searchContext

EXTRACTION TASK: 
1. Extract specific facts. 
2. You MUST preserve the [Doc X] citations. 
If nothing is relevant, return "Nothing relevant." DO NOT hallucinate facts.""";

        try {
          final extractedNotes = await OllamaService.generateText(
            baseUrl: networkState.ollamaUrl,
            model: networkState.ollamaModel,
            prompt: factPrompt,
          );
          if (!extractedNotes.contains("Nothing relevant")) {
            foragedFacts.writeln("\nVERIFIED EVIDENCE FOR ($logDesc):\n$extractedNotes");
          }
        } catch(e) {
            node.ollamaResult += "  - [Error during extraction: $e]\n"; onUpdate();
        }
    }

    if (checkForceAnswer()) return;

    // --- PHASE 3: CAMPFIRE SYNTHESIS ---
    node.ollamaResult += "\n🏕️ Campfire Synthesis: Writing grounded report...\n\n"; onUpdate();
    
    // --- FIX: Updated Synthesis Prompt to strictly enforce Wiki Council-style output ---
    final synthesisPrompt = """You are a Lead Intelligence Analyst.
Directive: "$directive"

Your team has queried the Redleaf Database and returned with the following verified data.
Your task is to write a definitive, grounded intelligence report based ONLY on the Extracted Evidence.

Write a Grounded Intelligence Report containing:
1. **Executive Summary:** A high-level overview of the findings.
2. **Detailed Findings:** The core analysis based ONLY on the extracted evidence. You MUST preserve and include the inline citations like [Doc X].
3. **Suggested Deep Studies:** A bulleted list of recommended follow-up research vectors. For each, write a 1-sentence prompt that the user can feed into a 'Deep Study' agent to kickstart it.

CRITICAL INSTRUCTIONS:
- If you mention existing Wiki Pages, wrap them in double brackets like [[Page Name]].
- Format your report using clean Markdown.
- Do NOT hallucinate data. If the evidence does not support a point, say so.

EXTRACTED EVIDENCE (VERIFIED):
${foragedFacts.isEmpty ? "No verified facts found in the database." : foragedFacts.toString()}""";

    String systemInstruction = "CURRENT SYSTEM TIME: ${DateTime.now()}\n\nYou are a strict, factual intelligence analyst. Do not use creative metaphors.";

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