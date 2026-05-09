// --- File: lib/agents/deep_study_agent.dart ---
import 'dart:convert';

import '../constants.dart';
import '../models/node_models.dart';
import '../state/graph_state.dart';
import '../state/network_state.dart';
import '../services/ollama_service.dart';

class DeepStudyAgent {
  
  static Map<String, dynamic> _parseAgentJSON(String response) {
    try {
      String clean = response.replaceAll(RegExp(r'```(?:json)?'), '').trim();
      clean = clean.replaceAll(RegExp(r',\s*\}'), '}');
      clean = clean.replaceAll(RegExp(r',\s*\]'), ']');
      return jsonDecode(clean);
    } catch (e) {
      return {"action": "finish", "thought": "Failed to parse JSON decision.", "query": ""};
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
    node.ollamaResult = "🤖 Agent: Gathering upstream context...\n";
    onUpdate();

    StringBuffer upstreamContext = StringBuffer();
    String objective = node.content.isNotEmpty ? node.content : "Conduct a comprehensive study based on the provided context.";
    
    String customPersona = "";

    // 1. Gather Context from the upstream chain
    for (var n in sequence) {
      if (n.type == NodeType.output || n.type == NodeType.chat || n.type == NodeType.study || n.type == NodeType.summarize || n.type == NodeType.wikiWriter || n.type == NodeType.council || n.type == NodeType.researchParty || n.type == NodeType.merge) continue;
      
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
        final briefingContext = await networkState.redleafService.fetchSystemBriefing();
        upstreamContext.writeln("\n>>> REDLEAF SYSTEM BRIEFING <<<\n$briefingContext");
        if (n.content.trim().isNotEmpty) upstreamContext.writeln("\n[USER OVERRIDE]:\n${n.content.trim()}");
        upstreamContext.writeln(">>> END REDLEAF BRIEFING <<<\n");
      } else if (n.type == NodeType.search && n.content.isNotEmpty) {
        final searchContext = await networkState.redleafService.fetchAdvancedFtsContext(n.content, n.searchLimit, n.pinnedSearchResults);
        upstreamContext.writeln("\n>>> REDLEAF GLOBAL SEARCH: '${n.content}' <<<\n$searchContext\n");
      } else if (n.type == NodeType.document && n.content.isNotEmpty) {
        final docContext = await networkState.redleafService.fetchDocumentText(n);
        upstreamContext.writeln("\n>>> REDLEAF DOCUMENT <<<\n$docContext\n");
      } else if (n.type == NodeType.catalog && n.content.isNotEmpty) {
        final catId = int.tryParse(n.content);
        if (catId != null) {
          final catContext = await networkState.redleafService.fetchCatalogContext(catId, n.title);
          upstreamContext.writeln("\n>>> REDLEAF CATALOG <<<\n$catContext\n");
        }
      } else if (n.type == NodeType.intersection && n.redleafPills.isNotEmpty) {
        final topicNames = n.redleafPills.map((p) => p.text).toList();
        final intContext = await networkState.redleafService.fetchIntersectionContext(topicNames);
        upstreamContext.writeln("\n>>> REDLEAF CO-MENTIONS <<<\n$intContext\n");
      } else if (n.type == NodeType.relationship && n.redleafPills.isNotEmpty) {
        final pill = n.redleafPills.first; 
        final relContext = await networkState.redleafService.fetchEntityRelationships(pill.entityId, pill.text);
        upstreamContext.writeln("\n>>> REDLEAF GRAPH <<<\n$relContext\n");
      } else if (n.type == NodeType.scene) {
        upstreamContext.writeln("\n=== [USER NOTE: ${n.title}] ===\n${n.content}\n");
        for (var pill in n.redleafPills) {
          upstreamContext.writeln(await networkState.redleafService.fetchContextForPill(pill));
        }
      }
    }

    String accumulatedNotes = "";
    int maxSteps = 5; 

    // 2. Autonomous Loop
    node.ollamaResult += "🤖 Agent: Initiating Deep Study on '$objective'...\n"; onUpdate();

    for (int step = 1; step <= maxSteps; step++) {
      if (checkForceAnswer()) {
        node.ollamaResult += "\n> [User Override] Skipping remaining research steps. Moving to synthesis.\n";
        onUpdate();
        break;
      }

      node.ollamaResult += "\n> [Step $step] Analyzing gaps in knowledge...\n"; onUpdate();
      
      final thinkPrompt = """You are an Autonomous Research Engine.
Your Goal: "$objective"

Upstream Context Provided by User:
${upstreamContext.isEmpty ? "None" : upstreamContext.toString()}

Current Accumulated Notes from your searches:
${accumulatedNotes.isEmpty ? "None" : accumulatedNotes}

Analyze the Goal, the Upstream Context, and your Notes. What information is MISSING? 
Determine the SINGLE best next step.

CRITICAL SEARCH ENGINE RULES:
1. The search engine uses simple keyword matching. DO NOT use boolean operators (AND, OR), parentheses, or quotes.
2. Do NOT provide multi-lingual queries in the same string. Pick one language per search.
3. For entities, "mode" must be one of: "doc" (appears in document), "page" (appears on same page), or "exclude" (MUST NOT appear in the document).
4. Use "exclude" to filter out known noise or unrelated topics.
5. You control the "limit" of documents returned (between 1 and 15). Use a higher limit (10-15) for broad overviews, and a lower limit (1-5) for targeted, highly specific facts.

File types available: ["PDF", "TXT", "HTML", "SRT" (transcripts), "EML" (emails)].
Entity labels available: PERSON, ORG, GPE (Geopolitical), LOC (Location), DATE, EVENT.

Return JSON ONLY (Do not use Markdown blocks):
{
  "thought": "Internal reasoning about what information is still missing.",
  "action": "search" OR "finish",
  "query": "Specific, natural language keyword search",
  "required_entities": [
      {"text": "Main Topic", "label": "ORG", "mode": "doc"},
      {"text": "Irrelevant Topic", "label": "PERSON", "mode": "exclude"}
  ],
  "file_types": [],
  "limit": 8
}""";

      try {
        final responseText = await OllamaService.generateText(
          baseUrl: networkState.ollamaUrl,
          model: networkState.ollamaModel,
          prompt: thinkPrompt,
          format: "json",
        );
          
        final decision = _parseAgentJSON(responseText);
        
        final action = decision['action'] ?? 'finish';
        final thought = decision['thought'] ?? 'No thought provided.';
        final query = decision['query'] ?? '';
        final List<dynamic> rawEntities = decision['required_entities'] ?? [];
        final List<dynamic> rawFileTypes = decision['file_types'] ?? [];
        
        // --- NEW: Extract dynamic limit safely ---
        int dynamicLimit = node.searchLimit;
        if (decision.containsKey('limit') && decision['limit'] is int) {
            dynamicLimit = (decision['limit'] as int).clamp(1, 15);
        }
        
        node.ollamaResult += "> Thought: $thought\n"; onUpdate();
        
        if (action == 'finish' || (query.isEmpty && rawEntities.isEmpty)) {
          node.ollamaResult += "> Action: Sufficient data gathered. Moving to synthesis.\n"; onUpdate();
          break;
        }
        
        if (checkForceAnswer()) break;

        String logDesc = "Query: '${query.isEmpty ? 'None' : query}', Entities: ${rawEntities.length}, Types: ${rawFileTypes.isEmpty ? 'All' : rawFileTypes.join(', ')}, Limit: $dynamicLimit";
        node.ollamaResult += "> Action: Searching Redleaf ($logDesc)...\n"; onUpdate();
        
        final searchContext = await networkState.redleafService.fetchAdvancedAgentContext(
          networkState: networkState,
          query: query,
          entities: rawEntities,
          fileTypes: rawFileTypes.map((e) => e.toString()).toList(),
          limit: dynamicLimit, 
        );
        
        if (searchContext.contains("[No results found")) {
          accumulatedNotes += "\nSearch yielded no results for this specific combination.";
          continue;
        }
        
        if (checkForceAnswer()) break;

        node.ollamaResult += "> Action: Extracting relevant facts...\n"; onUpdate();
        final notePrompt = """You are a Research Analyst.
Your Goal: Extract facts from the text below to help write a report on: "$objective".
Text to Analyze:
$searchContext

Task: Extract specific facts, numbers, and details. Preserve [Doc X] citations.
If nothing relevant is found, return "Nothing relevant." """;

        final extractedNotes = await OllamaService.generateText(
          baseUrl: networkState.ollamaUrl,
          model: networkState.ollamaModel,
          prompt: notePrompt,
        );
          
        if (!extractedNotes.contains("Nothing relevant")) {
          accumulatedNotes += "\n" + extractedNotes;
        }
      } catch (e) { 
        node.ollamaResult += "> [Agent Error: $e]\n"; onUpdate(); break; 
      }
    }

    // 3. Final Synthesis
    node.ollamaResult += "🤖 Agent: Synthesizing final intelligence report...\n\n"; onUpdate();
    String reportPrompt = """You are a Lead Researcher writing a final intelligence report.
Topic: "$objective"

Upstream Context provided by User:
${upstreamContext.isEmpty ? "None" : upstreamContext.toString()}

Accumulated Autonomous Research:
${accumulatedNotes.isEmpty ? "None" : accumulatedNotes}

Write a comprehensive, professional report on this topic using ONLY the provided context and research. 
Include inline citations like [Doc X] when stating facts derived from the research. 
Structure with an Executive Summary, Detailed Findings, and a Conclusion.""";

    final currentDate = DateTime.now().toString().split('.')[0];
    String systemInstruction = "You are a factual reporting agent.";
    if (customPersona.isNotEmpty) {
      systemInstruction = "YOUR ACTIVE PERSONA: $customPersona\n\nYou MUST adopt this persona completely in your writing style, tone, and perspective.";
    }
    systemInstruction = "CURRENT SYSTEM TIME: $currentDate\n\n$systemInstruction";

    try {
      final stream = OllamaService.generateTextStream(
        baseUrl: networkState.ollamaUrl,
        model: networkState.ollamaModel,
        prompt: reportPrompt,
        system: systemInstruction,
      );
      
      await for (final chunk in stream) {
          bool isFirstToken = node.ollamaResult.contains("🤖 Agent: Synthesizing final intelligence report...\n\n");
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