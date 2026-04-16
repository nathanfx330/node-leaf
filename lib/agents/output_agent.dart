// --- File: lib/agents/output_agent.dart ---
import 'dart:convert';

import '../constants.dart';
import '../models/node_models.dart';
import '../state/graph_state.dart';
import '../state/network_state.dart';
import '../services/ollama_service.dart';

class OutputAgent {
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
    node.ollamaResult = "🤖 Gathering upstream context...\n"; 
    onUpdate();

    StringBuffer finalPrompt = StringBuffer();
    String userInstructions = node.ollamaPrompt.isNotEmpty ? node.ollamaPrompt : "Process the following context.";
    String manualStoryContext = "";
    
    String customPersona = "";

    // 1. Gather Context
    for (var n in sequence) {
      if (n.type == NodeType.output || n.type == NodeType.chat || n.type == NodeType.study || n.type == NodeType.summarize || n.type == NodeType.wikiWriter || n.type == NodeType.council) continue; 

      if (n.type == NodeType.persona) {
        customPersona = n.content.trim();
        continue;
      }

      if (n.type == NodeType.wikiReader && n.wikiTitle.isNotEmpty) {
        node.ollamaResult = "🤖 Reading Wiki Page '${n.wikiTitle}'...\n"; onUpdate();
        final wikiContext = await graphState.readWikiPage(n.wikiTitle, networkState);
        finalPrompt.writeln("\n>>> CURRENT WIKI PAGE STATE: '${n.wikiTitle}' <<<");
        finalPrompt.writeln(wikiContext);
        finalPrompt.writeln(">>> END WIKI PAGE STATE <<<\n");
        continue;
      }

      if (n.type == NodeType.briefing) {
        node.ollamaResult = "🤖 Fetching System Briefing...\n"; onUpdate();
        final briefingContext = await networkState.redleafService.fetchSystemBriefing();
        finalPrompt.writeln("\n>>> FACTUAL CONTEXT FROM REDLEAF SYSTEM BRIEFING <<<");
        finalPrompt.writeln(briefingContext);
        if (n.content.trim().isNotEmpty) {
          finalPrompt.writeln("\n[USER OVERRIDE / MANUAL CONTEXT]:");
          finalPrompt.writeln(n.content.trim());
        }
        finalPrompt.writeln(">>> END REDLEAF BRIEFING <<<\n");
        continue;
      }
      
      if (n.type == NodeType.search && n.content.isNotEmpty) {
        node.ollamaResult = "🤖 Fetching Global Search for '${n.content}'...\n"; onUpdate();
        final searchContext = await networkState.redleafService.fetchAdvancedFtsContext(n.content, n.searchLimit, n.pinnedSearchResults);
        finalPrompt.writeln("\n>>> FACTUAL CONTEXT FROM REDLEAF GLOBAL SEARCH: '${n.content}' <<<");
        finalPrompt.writeln(searchContext);
        finalPrompt.writeln(">>> END REDLEAF SEARCH <<<\n");
        continue;
      }

      if (n.type == NodeType.document && n.content.isNotEmpty) {
        node.ollamaResult = "🤖 Fetching Full Document #${n.content}...\n"; onUpdate();
        // --- START FIX ---
        final docContext = await networkState.redleafService.fetchDocumentText(n);
        // --- END FIX ---
        finalPrompt.writeln("\n>>> FACTUAL CONTEXT FROM REDLEAF DOCUMENT <<<");
        finalPrompt.writeln(docContext);
        finalPrompt.writeln(">>> END REDLEAF DOCUMENT <<<\n");
        continue;
      }

      if (n.type == NodeType.catalog && n.content.isNotEmpty) {
        node.ollamaResult = "🤖 Fetching Context for Catalog '${n.title}'...\n"; onUpdate();
        final catId = int.tryParse(n.content);
        if (catId != null) {
          final catContext = await networkState.redleafService.fetchCatalogContext(catId, n.title);
          finalPrompt.writeln("\n>>> FACTUAL CONTEXT FROM REDLEAF CATALOG <<<");
          finalPrompt.writeln(catContext);
          finalPrompt.writeln(">>> END REDLEAF CATALOG <<<\n");
        }
        continue;
      }

      if (n.type == NodeType.intersection && n.redleafPills.isNotEmpty) {
        final topicNames = n.redleafPills.map((p) => p.text).toList();
        node.ollamaResult = "🤖 Fetching Co-Mentions for '${topicNames.join(', ')}'...\n"; onUpdate();
        final intContext = await networkState.redleafService.fetchIntersectionContext(topicNames);
        finalPrompt.writeln("\n>>> FACTUAL CONTEXT FROM REDLEAF CO-MENTIONS <<<");
        finalPrompt.writeln(intContext);
        finalPrompt.writeln(">>> END REDLEAF CO-MENTIONS <<<\n");
        continue;
      }

      if (n.type == NodeType.relationship && n.redleafPills.isNotEmpty) {
        final pill = n.redleafPills.first; 
        node.ollamaResult = "🤖 Fetching Graph Relationships for '${pill.text}'...\n"; onUpdate();
        final relContext = await networkState.redleafService.fetchEntityRelationships(pill.entityId, pill.text);
        finalPrompt.writeln("\n>>> FACTUAL CONTEXT FROM REDLEAF GRAPH <<<");
        finalPrompt.writeln(relContext);
        finalPrompt.writeln(">>> END REDLEAF GRAPH <<<\n");
        continue;
      }

      manualStoryContext += "\n=== [NODE: ${n.title}] ===\n${n.content}\n";
      if (n.redleafPills.isNotEmpty) {
        finalPrompt.writeln("\n>>> FACTUAL CONTEXT FROM REDLEAF KNOWLEDGE BASE <<<");
        for (var pill in n.redleafPills) {
          node.ollamaResult = "🤖 Fetching Entity Snippets for '${pill.text}'...\n"; onUpdate();
          final context = await networkState.redleafService.fetchContextForPill(pill);
          finalPrompt.writeln(context);
        }
        finalPrompt.writeln(">>> END REDLEAF CONTEXT <<<\n");
      }
    }

    for (var n in sequence) {
      if (n.type == NodeType.study && n.ollamaResult.isNotEmpty) {
        node.ollamaResult = "🤖 Reading Deep Study on '${n.content}'...\n"; onUpdate();
        finalPrompt.writeln("\n>>> FACTUAL CONTEXT FROM DEEP STUDY: '${n.content}' <<<");
        finalPrompt.writeln(n.ollamaResult);
        finalPrompt.writeln(">>> END DEEP STUDY <<<\n");
      }
    }
    
    // 2. Autonomous Research (ReAct Loop)
    if (node.enableAutonomousResearch && networkState.redleafService.isLoggedIn) {
      node.ollamaResult = "🤖 Agent: Initiating Autonomous Research...\n"; onUpdate();
      
      String accumulatedNotes = "No notes yet.";
      int maxSteps = 4; 
      
      for (int step = 1; step <= maxSteps; step++) {
        if (checkForceAnswer()) {
          node.ollamaResult += "\n> [User Override] Skipping remaining research steps. Moving to synthesis.\n";
          onUpdate();
          break;
        }

        node.ollamaResult += "\n> [Step $step] Thinking...\n"; onUpdate();
        
        final thinkPrompt = """You are an Autonomous Research Engine.
Your Goal: "$userInstructions"
Current Accumulated Notes: $accumulatedNotes

Analyze the goal and current notes. Determine the SINGLE best next step.
Return JSON ONLY:
{
  "thought": "Internal reasoning about what information is missing.",
  "action": "search" OR "finish",
  "query": "Your specific search phrase if action is search"
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
          
          node.ollamaResult += "> Thought: $thought\n"; onUpdate();
          
          if (action == 'finish' || query.isEmpty) {
            node.ollamaResult += "> Action: Sufficient data gathered. Moving to synthesis.\n"; onUpdate();
            break;
          }
          
          if (checkForceAnswer()) break;

          node.ollamaResult += "> Action: Searching Redleaf for '$query'...\n"; onUpdate();
          final searchContext = await networkState.redleafService.fetchFtsContext(query);
          
          if (searchContext.contains("[No results found")) {
            accumulatedNotes += "\nSearch for '$query' yielded no results.";
            continue;
          }
          
          if (checkForceAnswer()) break;

          node.ollamaResult += "> Action: Reading documents and extracting facts...\n"; onUpdate();
          final notePrompt = """You are a Research Analyst.
Your Goal: Extract facts from the text below to answer: "$userInstructions".
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

      if (accumulatedNotes != "No notes yet.") {
        finalPrompt.writeln("\n>>> AUTONOMOUSLY RESEARCHED NOTES <<<");
        finalPrompt.writeln(accumulatedNotes);
        finalPrompt.writeln(">>> END AUTONOMOUS NOTES <<<\n");
      }
    }

    // 3. Final Send to Ollama
    node.ollamaResult = "🤖 Agent: Writing final synthesis...\n\n"; onUpdate();
    final fullPayload = "$userInstructions\n\nHere is the source data and prompt nodes:\n$manualStoryContext\n${finalPrompt.toString()}";
    
    final currentDate = DateTime.now().toString().split('.')[0];
    String systemInstruction = node.ollamaNoBacktalk 
      ? "You are a Redleaf Synthesis Agent. Output ONLY the resulting text. Do not include any conversational filler. Start immediately with the text. YOU MUST INCLUDE INLINE CITATIONS like [Doc 12] based on the REDLEAF CONTEXT provided." 
      : "You are a helpful writing assistant.";
      
    if (customPersona.isNotEmpty) {
      systemInstruction = "YOUR ACTIVE PERSONA: $customPersona\n\n$systemInstruction\nYou MUST adopt this persona completely in your writing style, tone, and perspective.";
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
          bool isFirstToken = node.ollamaResult.contains("🤖 Agent: Writing final synthesis...\n\n");
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