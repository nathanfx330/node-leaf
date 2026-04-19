// --- File: lib/agents/chat_agent.dart ---
import 'dart:convert';

import '../constants.dart';
import '../models/node_models.dart';
import '../state/graph_state.dart';
import '../state/network_state.dart';
import '../services/ollama_service.dart';

class ChatAgent {
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
    required String userMessage,
    required GraphState graphState,
    required NetworkState networkState,
    required bool Function() checkForceAnswer,
    required Function() onUpdate,
  }) async {
    graphState.appendChatMessage(node.id, "user", userMessage);
    graphState.appendChatMessage(node.id, "assistant", "🤖 Gathering Context...");

    StringBuffer contextBuffer = StringBuffer();
    
    String systemInstructions = node.ollamaPrompt.isNotEmpty ? node.ollamaPrompt : "You are a helpful research assistant.";

    // --- FIX: Extremely strict constraints on the Chat Agent to prevent the "20 Questions" bug ---
    if (node.type == NodeType.wikiWriter) {
      systemInstructions = """You are an Editorial Planner helping the user prepare to rewrite a Wiki page.
Discuss the plan, answer questions using the provided context, and confirm the changes to be made. 

CRITICAL WIKI RULES YOU MUST ENFORCE AND DISCUSS:
1. All links to other pages MUST use double brackets: [[Page Name]]. NEVER use standard markdown links [text](url) or bolding **text** to indicate a link.
2. If the user asks to link something or emphasize an entity, confirm you will use the [[ ]] syntax.
3. Citations must be preserved exactly as [Doc X].

BEHAVIORAL CONSTRAINTS:
1. DO NOT output the rewritten markdown document yourself. Keep your responses conversational and concise. 
2. DO NOT output long lists of questions for the user. If you need clarification, ask ONE concise follow-up question.
3. If the plan is clear, simply acknowledge the instructions and remind the user to click the 'EXECUTE WRITE' button to generate the draft.""";
    } else if (node.ollamaNoBacktalk) {
      systemInstructions += "\n\nYou are a strict, analytical research agent. You MUST base your answers entirely on the provided REDLEAF CONTEXT. You MUST include inline citations exactly like [Doc 12] when stating facts derived from the context. Do not use conversational filler or backtalk.";
    }
    // --- END FIX ---

    String customPersona = "";

    // 1. Gather Context from the upstream chain
    for (var n in sequence) {
      if (n.type == NodeType.output || n.type == NodeType.chat || n.type == NodeType.study || n.type == NodeType.summarize || n.type == NodeType.wikiWriter || n.type == NodeType.council || n.type == NodeType.researchParty || n.type == NodeType.merge) continue;
      
      if (n.type == NodeType.persona) {
        customPersona = n.content.trim();
        continue;
      }
      
      if (n.type == NodeType.wikiReader && n.wikiTitle.isNotEmpty) {
        final wikiContext = await graphState.readWikiPage(n.wikiTitle, networkState);
        contextBuffer.writeln("\n>>> CURRENT WIKI PAGE STATE: '${n.wikiTitle}' <<<\n$wikiContext\n>>> END WIKI PAGE STATE <<<\n");
        continue;
      }

      if (n.type == NodeType.briefing) {
        final briefingContext = await networkState.redleafService.fetchSystemBriefing();
        contextBuffer.writeln("\n>>> REDLEAF SYSTEM BRIEFING <<<\n$briefingContext");
        if (n.content.trim().isNotEmpty) {
          contextBuffer.writeln("\n[USER OVERRIDE / MANUAL CONTEXT]:\n${n.content.trim()}");
        }
        contextBuffer.writeln(">>> END REDLEAF BRIEFING <<<\n");
        continue;
      }
      
      if (n.type == NodeType.search && n.content.isNotEmpty) {
        final searchContext = await networkState.redleafService.fetchAdvancedFtsContext(n.content, n.searchLimit, n.pinnedSearchResults);
        contextBuffer.writeln("\n>>> REDLEAF GLOBAL SEARCH: '${n.content}' <<<\n$searchContext\n");
        continue;
      }

      if (n.type == NodeType.document && n.content.isNotEmpty) {
        final docContext = await networkState.redleafService.fetchDocumentText(n);
        contextBuffer.writeln("\n>>> REDLEAF DOCUMENT <<<\n$docContext\n");
      } else if (n.type == NodeType.catalog && n.content.isNotEmpty) {
        final catId = int.tryParse(n.content);
        if (catId != null) {
          final catContext = await networkState.redleafService.fetchCatalogContext(catId, n.title);
          contextBuffer.writeln("\n>>> REDLEAF CATALOG <<<\n$catContext\n");
        }
      } else if (n.type == NodeType.intersection && n.redleafPills.isNotEmpty) {
        final topicNames = n.redleafPills.map((p) => p.text).toList();
        final intContext = await networkState.redleafService.fetchIntersectionContext(topicNames);
        contextBuffer.writeln("\n>>> REDLEAF CO-MENTIONS <<<\n$intContext\n");
      } else if (n.type == NodeType.relationship && n.redleafPills.isNotEmpty) {
        final pill = n.redleafPills.first; 
        final relContext = await networkState.redleafService.fetchEntityRelationships(pill.entityId, pill.text);
        contextBuffer.writeln("\n>>> REDLEAF GRAPH <<<\n$relContext\n");
      } else if (n.type == NodeType.scene) {
        contextBuffer.writeln("\n=== [USER NOTE: ${n.title}] ===\n${n.content}\n");
        if (n.redleafPills.isNotEmpty) {
          for (var pill in n.redleafPills) {
            final context = await networkState.redleafService.fetchContextForPill(pill);
            contextBuffer.writeln(context);
          }
        }
      }
    }

    for (var n in sequence) {
      if (n.type == NodeType.study && n.ollamaResult.isNotEmpty) {
        contextBuffer.writeln("\n>>> FACTUAL CONTEXT FROM DEEP STUDY: '${n.content}' <<<");
        contextBuffer.writeln(n.ollamaResult);
        contextBuffer.writeln(">>> END DEEP STUDY <<<\n");
      }
    }

    // --- Inject Current Node Data if it's a WikiWriter ---
    if (node.type == NodeType.wikiWriter) {
      if (node.wikiTitle.isNotEmpty) {
        final wikiContext = await graphState.readWikiPage(node.wikiTitle, networkState);
        contextBuffer.writeln("\n>>> TARGET WIKI PAGE FOR REWRITE: '${node.wikiTitle}' <<<\n$wikiContext\n>>> END TARGET WIKI PAGE <<<\n");
      }
      if (node.redleafPills.isNotEmpty) {
        contextBuffer.writeln("\n>>> FACTUAL CONTEXT FROM ATTACHED ENTITIES <<<");
        for (var pill in node.redleafPills) {
          contextBuffer.writeln(await networkState.redleafService.fetchContextForPill(pill));
        }
        contextBuffer.writeln(">>> END ATTACHED ENTITIES <<<\n");
      }
    }
    // --- END NEW ---

    // 2. Autonomous Research (ReAct Loop tailored for Chat)
    if (node.enableAutonomousResearch && networkState.redleafService.isLoggedIn) {
      node.chatHistory.last["content"] = "🤖 Agent: Analyzing your message for required research...";
      onUpdate();
      
      String accumulatedNotes = "";
      int maxSteps = 3; 
      
      for (int step = 1; step <= maxSteps; step++) {
        if (checkForceAnswer()) {
          node.chatHistory.last["content"] = "🤖 Agent: Moving to synthesis...";
          onUpdate();
          break;
        }

        final thinkPrompt = """You are a Chat Assistant's Internal Brain.
User Message: "$userMessage"
Current Context gathered so far: ${accumulatedNotes.isEmpty ? "None" : accumulatedNotes}

Do you need more factual context from the database to answer the user?
Return JSON ONLY:
{
  "thought": "Reasoning about what is missing.",
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
          
          if (decision['action'] == 'finish' || (decision['query'] ?? '').isEmpty) break;
          if (checkForceAnswer()) break;

          final query = decision['query'];
          node.chatHistory.last["content"] = "🤖 Agent: Searching Redleaf for '$query'..."; 
          onUpdate();
          
          final searchContext = await networkState.redleafService.fetchFtsContext(query);
          if (checkForceAnswer()) break;

          node.chatHistory.last["content"] = "🤖 Agent: Reading documents and taking notes..."; 
          onUpdate();
          
          final notePrompt = """Extract facts from the text below to answer the User Message: "$userMessage".
Text:
$searchContext

Preserve [Doc X] citations. If nothing relevant is found, return "Nothing relevant." """;

          final extractedNotes = await OllamaService.generateText(
            baseUrl: networkState.ollamaUrl,
            model: networkState.ollamaModel,
            prompt: notePrompt,
          );
          
          if (!extractedNotes.contains("Nothing relevant")) {
            accumulatedNotes += "\n" + extractedNotes;
          }
        } catch (e) { break; }
      }

      if (accumulatedNotes.isNotEmpty) {
        contextBuffer.writeln("\n>>> AUTONOMOUSLY RESEARCHED NOTES <<<\n$accumulatedNotes\n");
      }
    }

    final currentDate = DateTime.now().toString().split('.')[0];
    if (customPersona.isNotEmpty) {
      systemInstructions = "YOUR ACTIVE PERSONA: $customPersona\n\n$systemInstructions\nYou MUST adopt this persona completely in your writing style, tone, and perspective.";
    }
    systemInstructions = "CURRENT SYSTEM TIME: $currentDate\n\n$systemInstructions";

    // 3. Structure the API Payload
    List<Map<String, String>> apiMessages = [
      {"role": "system", "content": systemInstructions}
    ];
    
    for (int i = 0; i < node.chatHistory.length - 2; i++) {
      apiMessages.add(node.chatHistory[i]);
    }

    String finalUserPayload = userMessage;
    if (contextBuffer.isNotEmpty) {
      finalUserPayload = "REDLEAF KNOWLEDGE BASE CONTEXT FOR THIS TURN:\n${contextBuffer.toString()}\n\n---\nUSER MESSAGE:\n$userMessage";
    }
    
    apiMessages.add({"role": "user", "content": finalUserPayload});

    node.chatHistory.last["content"] = "";
    onUpdate();

    try {
      final stream = OllamaService.generateChatStream(
        baseUrl: networkState.ollamaUrl,
        model: networkState.ollamaModel,
        messages: apiMessages,
      );
      
      await for (final chunk in stream) {
        graphState.streamToLastChatMessage(node.id, chunk);
      }
    } catch (e) { 
      graphState.streamToLastChatMessage(node.id, "⚠️ Failed to connect to Ollama. Error details: $e");
    }
  }
}