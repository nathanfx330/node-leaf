// --- File: lib/agents/wiki_council_agent.dart ---
import 'dart:convert';

import '../constants.dart';
import '../models/node_models.dart';
import '../state/graph_state.dart';
import '../state/network_state.dart';
import '../services/ollama_service.dart';

class WikiCouncilAgent {
  
  // Helper to parse the JSON safely
  static Map<String, dynamic> _parseAgentJSON(String response) {
    try {
      String clean = response.replaceAll('```json', '').replaceAll('```', '').trim();
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
    node.ollamaResult = "🏛️ Convening the Wiki Council...\n"; 
    onUpdate();

    StringBuffer upstreamContext = StringBuffer();

    // 1. Gather Upstream Context
    for (var n in sequence) {
       if (n.type == NodeType.output || n.type == NodeType.chat || n.type == NodeType.study || n.type == NodeType.summarize || n.type == NodeType.wikiWriter || n.type == NodeType.council) continue;
       
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

    if (upstreamContext.isEmpty) {
        node.ollamaResult += "\n> [Error] The Council requires upstream context (like a Wiki Reader or Deep Study node) to analyze.";
        onUpdate();
        return;
    }

    // --- TURN 1: Initial Context Extraction ---
    node.ollamaResult += "\n> [System] Analyzing current knowledge state...\n"; onUpdate();

    final phase1Prompt = """Review the provided upstream context and the current Wiki page.
Identify up to 3 core conceptual entities (People, Organizations, Specific Themes) that are central to this topic.
Return ONLY a JSON object: {"core_entities": ["Entity 1", "Entity 2"]}

CONTEXT TO ANALYZE:
${upstreamContext.toString()}""";

    List<String> coreEntities = [];
    try {
      final responseText = await OllamaService.generateText(
        baseUrl: networkState.ollamaUrl,
        model: networkState.ollamaModel,
        prompt: phase1Prompt,
        format: "json",
      );
        
      final p1Json = _parseAgentJSON(responseText);
      
      if (p1Json['core_entities'] is List) {
          coreEntities = List<String>.from(p1Json['core_entities']);
      }
    } catch (e) {
      node.ollamaResult += "> [System Error in Extraction: $e]\n"; onUpdate();
      return;
    }

    if (checkForceAnswer()) return;

    // --- TURN 2: Redleaf Graph Mapping ---
    node.ollamaResult += "> [System] Mapping ontological gaps in Redleaf Graph for: ${coreEntities.join(', ')}\n"; onUpdate();
    StringBuffer graphContext = StringBuffer();
    
    for (String entityName in coreEntities.take(3)) { 
        node.ollamaResult += "  - Consulting graph for '$entityName'...\n"; onUpdate();
        final searchRes = await networkState.redleafService.searchEntities(entityName);
        
        if (searchRes.isNotEmpty) {
            final topMatch = searchRes.first;
            final id = await networkState.redleafService.extractEntityId(topMatch['label'], topMatch['text']);
            if (id != null) {
                graphContext.writeln(await networkState.redleafService.fetchEntityRelationships(id, topMatch['text']));
            }
        }
    }

    if (checkForceAnswer()) return;

    // --- TURN 3: The MoE Debate Loop ---
    node.ollamaResult += "\n> [System] The Council has convened. Debate beginning...\n\n"; onUpdate();

    final List<Map<String, String>> masterRoster = [
      {"name": "The Visionary", "prompt": "You are The Visionary. You look for broad, sweeping connections, paradigm shifts, and unexplored themes. You think big picture."},
      {"name": "The Skeptic", "prompt": "You are The Skeptic. You look for missing evidence, logical leaps, and contradictory data. You demand rigor and highlight what we *don't* know."},
      {"name": "The Archivist", "prompt": "You are The Archivist. You look for historical context, specific entities, and chronological continuity. You care about the details."},
      {"name": "The Pragmatist", "prompt": "You are The Pragmatist. You focus on actionable, practical implications. Why does this matter? What is the tangible impact?"},
      {"name": "The Devil's Advocate", "prompt": "You are The Devil's Advocate. Your job is to actively argue against the consensus forming in the debate. Find the weak point and attack it."},
      {"name": "The Sociologist", "prompt": "You are The Sociologist. You look at human impact, organizational behavior, group dynamics, and cultural shifts."},
      {"name": "The Lateral Thinker", "prompt": "You are The Lateral Thinker. You look for bizarre, unconventional, or indirect connections that everyone else is missing."},
      {"name": "The Economist", "prompt": "You are The Economist. You analyze the context purely through the lens of incentives, resource allocation, and financial impact."},
      {"name": "The Synthesizer", "prompt": "You are The Synthesizer. Your job is to take the disparate points made by the others so far and attempt to merge them into a single cohesive theory."},
      {"name": "The Detective", "prompt": "You are The Detective. You look for motives, hidden agendas, structural anomalies, and things that seem 'off'."}
    ];

    String debateTranscript = "";
    int requestedAgents = node.councilAgentCount;
    
    List<Map<String, String>> activeExperts = [];
    for (int i = 0; i < requestedAgents; i++) {
        activeExperts.add(masterRoster[i % masterRoster.length]);
    }

    final String baseDebateRules = """
CRITICAL INSTRUCTIONS:
1. You MUST act entirely in character as your assigned persona.
2. DO NOT break the 4th wall. DO NOT act as an AI evaluating a prompt.
3. DO NOT congratulate the other speakers or say things like "Great point" or "I agree."
4. You MUST aggressively critique the research and point out flaws, missing data, or new angles.
""";

    for (int i = 0; i < activeExperts.length; i++) {
        if (checkForceAnswer()) return;

        final expert = activeExperts[i];
        
        node.ollamaResult += ">>> ${expert['name']} is speaking...\n"; onUpdate();

        final debatePrompt = """${expert['prompt']}
You are part of the Wiki Council. Your job is to find the 'white space' in the user's research.

$baseDebateRules

1. Review the User's Current Context.
2. Review the Redleaf Graph Data.
3. Review the ongoing Debate Transcript from your peers.

Add a single, concise paragraph to the debate. Point out a specific missing connection or suggest a new angle of research that the previous experts missed or got wrong. Do not summarize, just argue your point.

USER'S CURRENT CONTEXT:
${upstreamContext.toString()}

REDLEAF GRAPH DATA:
${graphContext.isEmpty ? "No extended graph connections found." : graphContext.toString()}

DEBATE TRANSCRIPT SO FAR:
${debateTranscript.isEmpty ? "You are the first to speak. Begin the debate." : debateTranscript}
""";

        try {
          final responseText = await OllamaService.generateText(
            baseUrl: networkState.ollamaUrl,
            model: networkState.ollamaModel,
            prompt: debatePrompt,
          );
          
          debateTranscript += "**${expert['name']}**: $responseText\n\n";
          node.ollamaResult += "${expert['name']}: $responseText\n\n"; onUpdate();
          
        } catch (e) {
          node.ollamaResult += "> [Agent Error during debate: $e]\n"; onUpdate();
        }
    }

    if (checkForceAnswer()) return;

    // --- TURN 4: The Director (Synthesis) ---
    node.ollamaResult += "> [System] Debate concluded. Drafting final Council Audit Report...\n\n"; onUpdate();

    final currentDate = DateTime.now().toString().split('.')[0];
    
    final synthesisPrompt = """You are the Director of the Wiki Council. 
You must synthesize the Debate Transcript into a final, actionable report.

Write a Council Audit Report containing:
1. **Missing Connections:** A synthesized summary of the ontological gaps identified by the experts.
2. **Suggested New Pages:** A bulleted list of recommended new Wiki pages to create based on the debate. For each, write a 1-sentence prompt that the user can feed into a 'Deep Study' agent to kickstart it.

DO NOT use boilerplate placeholders like [Your Name] or make up random dates.

DEBATE TRANSCRIPT:
$debateTranscript
""";

    String systemInstruction = "CURRENT SYSTEM TIME: $currentDate\n\nYou are the Director of the Wiki Council. You must synthesize the debate without using placeholders. Sign the report as 'The Director'. DO NOT evaluate the debate, just report the facts and suggestions.";

    try {
      final stream = OllamaService.generateTextStream(
        baseUrl: networkState.ollamaUrl,
        model: networkState.ollamaModel,
        prompt: synthesisPrompt,
        system: systemInstruction,
      );
      
      await for (final chunk in stream) {
          bool isFirstToken = node.ollamaResult.contains("> [System] Debate concluded. Drafting final Council Audit Report...\n\n");
          if (isFirstToken) node.ollamaResult = ""; 
          node.ollamaResult += chunk; 
          onUpdate(); 
      }
    } catch (e) { 
      node.ollamaResult += "\n⚠️ Failed to generate Council report.\nError details: $e"; 
      onUpdate(); 
    }
  }
}