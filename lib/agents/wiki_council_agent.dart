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
    final bool isAuditMode = node.wikiTitle.trim().isNotEmpty;
    
    node.ollamaResult = isAuditMode 
        ? "🏛️ Convening the Wiki Council [AUDIT MODE]...\n"
        : "🏛️ Convening the Wiki Council [DISCOVERY MODE]...\n"; 
    onUpdate();

    String targetWikiText = "";
    if (isAuditMode) {
        node.ollamaResult += "> [System] Reading target page: ${node.wikiTitle}.md...\n"; onUpdate();
        targetWikiText = await graphState.readWikiPage(node.wikiTitle, networkState);
    }

    // --- NEW: Gather History Context for Anti-Drift (Goal 1) ---
    StringBuffer historyContext = StringBuffer();
    if (isAuditMode && node.councilAuditHistory) {
      node.ollamaResult += "> [System] Fetching Wiki page history for drift analysis...\n"; onUpdate();
      final historyFiles = await graphState.getWikiHistory(node.wikiTitle, networkState);
      
      // Grab the 2 most recent backups to combat drift
      int backupsToRead = historyFiles.length > 2 ? 2 : historyFiles.length; 
      for(int i=0; i<backupsToRead; i++) {
        final backupContent = await graphState.readWikiBackup(historyFiles[i], networkState);
        if (backupContent != null) {
          historyContext.writeln("\n>>> HISTORICAL VERSION ${i+1} (${historyFiles[i]}): <<<\n$backupContent\n");
        }
      }
    }

    // --- NEW: Gather Wiki Knowledge Graph Context ---
    StringBuffer wikiGraphContext = StringBuffer();
    if (isAuditMode) {
      final nodeRank = graphState.wikiNodeRanks[node.wikiTitle];
      final outLinks = graphState.wikiOutgoingLinks[node.wikiTitle];
      if (nodeRank != null) {
        wikiGraphContext.writeln("TARGET PAGE NODERANK SCORE: ${nodeRank.toStringAsFixed(3)} (0.0 to 1.0)");
        wikiGraphContext.writeln("TARGET PAGE OUTGOING WIKI LINKS: ${outLinks?.isEmpty ?? true ? 'None (This page is a dead-end!)' : outLinks!.join(', ')}");
      } else {
        wikiGraphContext.writeln("TARGET PAGE NODERANK SCORE: Not yet ranked (New Page)");
      }
    } else {
      final sortedPages = graphState.wikiNodeRanks.keys.toList()
        ..sort((a, b) => graphState.wikiNodeRanks[b]!.compareTo(graphState.wikiNodeRanks[a]!));
      wikiGraphContext.writeln("TOP 5 WIKI HUBS (By NodeRank):");
      for (int i = 0; i < sortedPages.length && i < 5; i++) {
        final p = sortedPages[i];
        wikiGraphContext.writeln("- $p (Score: ${graphState.wikiNodeRanks[p]!.toStringAsFixed(3)}) -> Links to: ${graphState.wikiOutgoingLinks[p]?.join(', ') ?? 'Nothing'}");
      }
    }

    // 1. Gather Upstream Context
    StringBuffer upstreamContext = StringBuffer();
    for (var n in sequence) {
       // --- FIX: Added merge to the ignore list ---
       if (n.type == NodeType.output || n.type == NodeType.chat || n.type == NodeType.study || n.type == NodeType.summarize || n.type == NodeType.wikiWriter || n.type == NodeType.council || n.type == NodeType.researchParty || n.type == NodeType.merge) continue;
       
       if (n.type == NodeType.wikiReader && n.wikiTitle.isNotEmpty && n.wikiTitle != node.wikiTitle) {
          upstreamContext.writeln("\n>>> UPSTREAM WIKI PAGE STATE: '${n.wikiTitle}' <<<");
          upstreamContext.writeln(await graphState.readWikiPage(n.wikiTitle, networkState));
          upstreamContext.writeln(">>> END UPSTREAM WIKI PAGE <<<\n");
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
         upstreamContext.writeln("\n>>> REDLEAF DOCUMENT <<<\n${await networkState.redleafService.fetchDocumentText(n)}\n>>> END REDLEAF DOCUMENT <<<\n");
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

    if (upstreamContext.isEmpty && !isAuditMode) {
        node.ollamaResult += "\n> [Error] The Council requires upstream context (like a Deep Study or Global Search) to analyze.";
        onUpdate();
        return;
    }

    // --- NEW: Council Directive Context ---
    String directiveContext = node.councilDirection.trim().isNotEmpty 
        ? "\nCOUNCIL DIRECTIVE / FOCUS:\n${node.councilDirection.trim()}\nYou MUST tailor your analysis and debate specifically around this directive.\n" 
        : "";

    // --- TURN 1: Initial Context Extraction ---
    node.ollamaResult += "\n> [System] Analyzing current knowledge state...\n"; onUpdate();

    final phase1Prompt = isAuditMode 
    ? """Review the Target Wiki Page, its Historical Versions (if any), and the Upstream Context.
Identify up to 3 core conceptual entities (People, Organizations, Specific Themes) that are missing, suffering from semantic drift, or controversial.
Return ONLY a JSON object: {"core_entities": ["Entity 1", "Entity 2"]}

$directiveContext

TARGET WIKI PAGE (${node.wikiTitle}):
$targetWikiText

${historyContext.isNotEmpty ? historyContext.toString() : ""}
UPSTREAM CONTEXT (REDLEAF GROUND TRUTH):
${upstreamContext.toString()}"""
    : """Review the provided upstream context.
Identify up to 3 core conceptual entities (People, Organizations, Specific Themes) that are central to this topic.
Return ONLY a JSON object: {"core_entities": ["Entity 1", "Entity 2"]}

$directiveContext

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
    StringBuffer redleafGraphContext = StringBuffer();
    
    for (String entityName in coreEntities.take(3)) { 
        node.ollamaResult += "  - Consulting graph for '$entityName'...\n"; onUpdate();
        final searchRes = await networkState.redleafService.searchEntities(entityName);
        
        if (searchRes.isNotEmpty) {
            final topMatch = searchRes.first;
            final id = await networkState.redleafService.extractEntityId(topMatch['label'], topMatch['text']);
            if (id != null) {
                redleafGraphContext.writeln(await networkState.redleafService.fetchEntityRelationships(id, topMatch['text']));
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

    final String baseDebateRules = isAuditMode 
    ? """CRITICAL INSTRUCTIONS:
1. Act entirely in character as your assigned persona.
2. DO NOT break the 4th wall.
3. You MUST aggressively critique the TARGET WIKI PAGE based on the new UPSTREAM CONTEXT. Point out what the Wiki page gets wrong or is missing.
4. ANTI-DRIFT DIRECTIVE: If historical versions are provided, identify if accurate ground-truth facts were lost or distorted over time (Semantic Drift). Aggressively argue to restore them using Redleaf context as the ultimate authority.
5. ANALYZE THE WIKI KNOWLEDGE GRAPH DATA. If the page is a dead-end, suggest what it should link to.
$directiveContext"""
    : """CRITICAL INSTRUCTIONS:
1. Act entirely in character as your assigned persona.
2. DO NOT break the 4th wall.
3. You MUST aggressively critique the research and point out flaws, missing data, or new angles. Find the 'white space' in the user's research.
4. ANALYZE THE WIKI KNOWLEDGE GRAPH DATA. Suggest how this new research should connect to existing Wiki Hubs.
$directiveContext""";

    for (int i = 0; i < activeExperts.length; i++) {
        if (checkForceAnswer()) return;

        final expert = activeExperts[i];
        
        node.ollamaResult += ">>> ${expert['name']} is speaking...\n"; onUpdate();

        final debatePrompt = isAuditMode 
        ? """${expert['prompt']}
You are part of the Wiki Council. Your job is to audit the Target Wiki Page.

$baseDebateRules

1. Review the Target Wiki Page.
2. Review the Upstream Context & Redleaf Graph Data.
3. Review the Wiki Knowledge Graph Data (NodeRanks and Links).
4. Review the ongoing Debate Transcript.

Add a single, concise paragraph to the debate. Argue exactly how the Target Wiki Page should be rewritten or expanded to incorporate the new data and improve its connections within the Wiki.

TARGET WIKI PAGE:
$targetWikiText

UPSTREAM CONTEXT & REDLEAF GRAPH:
${upstreamContext.toString()}
${redleafGraphContext.toString()}

WIKI KNOWLEDGE GRAPH DATA:
${wikiGraphContext.toString()}

DEBATE TRANSCRIPT SO FAR:
${debateTranscript.isEmpty ? "You are the first to speak. Begin the debate." : debateTranscript}"""
        : """${expert['prompt']}
You are part of the Wiki Council. Your job is to find the 'white space' in the user's research.

$baseDebateRules

1. Review the User's Current Context.
2. Review the Redleaf Graph Data.
3. Review the Wiki Knowledge Graph Data (NodeRanks and Links).
4. Review the ongoing Debate Transcript from your peers.

Add a single, concise paragraph to the debate. Point out a specific missing connection or suggest a new angle of research that the previous experts missed or got wrong.

USER'S CURRENT CONTEXT:
${upstreamContext.toString()}

REDLEAF GRAPH DATA:
${redleafGraphContext.isEmpty ? "No extended graph connections found." : redleafGraphContext.toString()}

WIKI KNOWLEDGE GRAPH DATA:
${wikiGraphContext.toString()}

DEBATE TRANSCRIPT SO FAR:
${debateTranscript.isEmpty ? "You are the first to speak. Begin the debate." : debateTranscript}""";

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

    // --- NEW: INTERACTIVE DEBATE ("THE CHAIRMAN'S REVIEW") ---
    if (node.councilInteractive) {
        node.ollamaResult += "\n> [System] Pausing debate. Awaiting The Chairman's (User) input...\n\n";
        onUpdate();
        
        String userFeedback = await networkState.waitForUserInput(node.id);
        
        if (checkForceAnswer()) return; // Abort if user clicked Stop/Force Answer
        
        if (userFeedback.trim().isNotEmpty) {
            debateTranscript += "**The Chairman (User)**: $userFeedback\n\n";
            node.ollamaResult += "**The Chairman**: $userFeedback\n\n"; 
            onUpdate();
            
            node.ollamaResult += "> [System] The Council deliberates on The Chairman's feedback...\n\n";
            onUpdate();
            
            // Have 2 agents respond to the Chairman's feedback
            int agentsToRespond = activeExperts.length >= 2 ? 2 : activeExperts.length;
            for (int i = 0; i < agentsToRespond; i++) {
                if (checkForceAnswer()) return;
                
                // Pick agents starting from the end of the roster so it doesn't sound repetitive
                final expert = activeExperts[activeExperts.length - 1 - i]; 
                
                node.ollamaResult += ">>> ${expert['name']} is responding to The Chairman...\n"; onUpdate();
                
                final responsePrompt = """${expert['prompt']}
You are part of the Wiki Council. The Chairman (the user) has just provided feedback or a new direction for the debate.
Respond directly to The Chairman's feedback in character, incorporating it into the overall debate. Keep it to one concise paragraph.

DEBATE TRANSCRIPT SO FAR (Including The Chairman's input at the end):
$debateTranscript""";

                try {
                  final responseText = await OllamaService.generateText(
                    baseUrl: networkState.ollamaUrl,
                    model: networkState.ollamaModel,
                    prompt: responsePrompt,
                  );
                  
                  debateTranscript += "**${expert['name']}**: $responseText\n\n";
                  node.ollamaResult += "${expert['name']}: $responseText\n\n"; onUpdate();
                } catch (e) {
                  node.ollamaResult += "> [Agent Error during response: $e]\n"; onUpdate();
                }
            }
        } else {
            node.ollamaResult += "> [System] The Chairman passed. Proceeding to Director...\n\n";
            onUpdate();
        }
    }

    // --- TURN 4: The Director (Synthesis) ---
    node.ollamaResult += "> [System] Debate concluded. Drafting final Council Report...\n\n"; onUpdate();

    final currentDate = DateTime.now().toString().split('.')[0];
    
    final synthesisPrompt = isAuditMode 
    ? """You are the Director of the Wiki Council. 
You have overseen a debate about the Target Wiki Page.

Your task is twofold:
1. Write a brief "Director's Summary" outlining the flaws found in the original document based on the debate and its position in the Wiki Graph.
2. Provide a **complete, proposed rewrite** of the Target Wiki Page that incorporates the best suggestions from the debate and the upstream context. 

CRITICAL: You MUST use double brackets like [[Page Name]] to link concepts to other pages, especially if the debate suggested adding links.
Include inline citations like [Doc X] if you use facts from the context.
$directiveContext

TARGET WIKI PAGE (ORIGINAL):
$targetWikiText

WIKI KNOWLEDGE GRAPH DATA:
${wikiGraphContext.toString()}

COUNCIL DEBATE TRANSCRIPT:
$debateTranscript"""
    : """You are the Director of the Wiki Council. 
You must synthesize the Debate Transcript into a final, actionable report.

Write a Council Audit Report containing:
1. **Missing Connections:** A synthesized summary of the ontological gaps identified by the experts.
2. **Suggested New Pages:** A bulleted list of recommended new Wiki pages to create based on the debate. For each, write a 1-sentence prompt that the user can feed into a 'Deep Study' agent to kickstart it. 

CRITICAL: Use double brackets like [[Page Name]] when referencing existing Wiki Hubs or proposing new ones.
$directiveContext

WIKI KNOWLEDGE GRAPH DATA:
${wikiGraphContext.toString()}

DEBATE TRANSCRIPT:
$debateTranscript""";

    String systemInstruction = isAuditMode 
    ? "CURRENT SYSTEM TIME: $currentDate\n\nYou are the Director of the Wiki Council. First summarize the debate, then output a full Markdown rewrite of the page under the heading '### Proposed Rewrite'. DO NOT use special tags, control tokens, or signatures. Output only the requested text."
    : "CURRENT SYSTEM TIME: $currentDate\n\nYou are the Director of the Wiki Council. You must synthesize the debate. DO NOT use special tags, control tokens, or signatures. Output only the requested text.";

    try {
      final stream = OllamaService.generateTextStream(
        baseUrl: networkState.ollamaUrl,
        model: networkState.ollamaModel,
        prompt: synthesisPrompt,
        system: systemInstruction,
      );
      
      await for (final chunk in stream) {
          bool isFirstToken = node.ollamaResult.contains("> [System] Debate concluded. Drafting final Council Report...\n\n");
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