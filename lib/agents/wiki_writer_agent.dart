// --- File: lib/agents/wiki_writer_agent.dart ---
import '../constants.dart'; 
import '../models/node_models.dart';
import '../state/graph_state.dart';
import '../state/network_state.dart';
import '../services/ollama_service.dart';
import 'media_evidence.dart';

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
    bool hasCouncilRewrite = false;
    bool hasCutlist = false;

    // --- Fetch existing wiki pages to guide the LLM ---
    final existingPages = await graphState.listWikiPages(networkState);
    String existingPagesContext = existingPages.isNotEmpty
        ? "EXISTING WIKI PAGES:\n- ${existingPages.join('\n- ')}\n"
        : "EXISTING WIKI PAGES: None yet.\n";

    // 1. Gather Context
    for (var n in sequence) {
       // --- FIX: Removed study, summarize, council, and researchParty from the continue list ---
       // This ensures their outputs can actually be read by the Wiki Writer!
       if (n.type == NodeType.output || n.type == NodeType.chat || n.type == NodeType.wikiWriter || n.type == NodeType.merge) continue;
       
       if (n.type == NodeType.persona) {
          customPersona = n.content.trim();
          continue;
       }

       // --- NEW: A finished Media Compressor paper edit is prime wiki
       // material: QC-verified verbatim sound bites with true timestamps.
       if (n.type == NodeType.compressor && n.ollamaResult.contains('**[Doc')) {
          upstreamContext.writeln("\n>>> VERIFIED PAPER EDIT (MEDIA COMPRESSOR) <<<");
          upstreamContext.writeln("The following cuts were machine-verified as verbatim dialogue at their exact timestamps. Use them as the article's key quotations - quote them as blockquotes where appropriate, and ALWAYS carry their [Doc X] citation with the timestamp, e.g. [Doc 1 @ 01:10:47].");
          upstreamContext.writeln(n.ollamaResult);
          upstreamContext.writeln(">>> END PAPER EDIT <<<\n");
          continue;
       }

       // --- NEW: Media Compressor cutlists are already machine-verified
       // (verbatim quotes, true timestamps) - the best source material in
       // the system. Inject them as primary evidence.
       if (n.type == NodeType.compressor && n.ollamaResult.isNotEmpty) {
          hasCutlist = true;
          upstreamContext.writeln("\n>>> VERIFIED PAPER EDIT (from Media Compressor) <<<");
          upstreamContext.writeln("Every quote below was machine-verified VERBATIM against the source subtitles, with true timestamps. Treat these as ground truth about the talk/video.");
          upstreamContext.writeln(n.ollamaResult);
          upstreamContext.writeln(">>> END VERIFIED PAPER EDIT <<<\n");
          continue;
       }

       // --- NEW: Media Readers arrive as distilled, verified Evidence Packs.
       if (n.type == NodeType.mediaReader && n.content.isNotEmpty) {
          node.ollamaResult += "> [System] Distilling media evidence from Media Reader '${n.content}'...\n"; onUpdate();
          upstreamContext.writeln(await MediaEvidenceAgent.buildPack(
            mediaNode: n,
            networkState: networkState,
            onProgress: (msg) { node.ollamaResult += msg; onUpdate(); },
          ));
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

       if (n.type == NodeType.researchParty && n.ollamaResult.isNotEmpty) {
         upstreamContext.writeln("\n>>> FACTUAL CONTEXT FROM RESEARCH PARTY: '${n.content}' <<<");
         upstreamContext.writeln(n.ollamaResult);
         upstreamContext.writeln(">>> END RESEARCH PARTY <<<\n");
         continue;
       }

       if (n.type == NodeType.summarize && n.ollamaResult.isNotEmpty) {
         upstreamContext.writeln("\n>>> FACTUAL CONTEXT FROM SUMMARIZER <<<");
         upstreamContext.writeln(n.ollamaResult);
         upstreamContext.writeln(">>> END SUMMARIZER <<<\n");
         continue;
       }

       // --- NEW: Automatic Wiki Council Integration ---
       if (n.type == NodeType.council && n.ollamaResult.isNotEmpty) {
         hasCouncilRewrite = true;
         upstreamContext.writeln("\n>>> PROPOSED REWRITE FROM WIKI COUNCIL <<<");
         upstreamContext.writeln(n.ollamaResult);
         upstreamContext.writeln(">>> END WIKI COUNCIL REWRITE <<<\n");
         continue;
       }
       
       // Add standard context
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

    String attachedEntitiesList = "";
    if (node.redleafPills.isNotEmpty) {
      upstreamContext.writeln("\n>>> FACTUAL CONTEXT FROM ATTACHED ENTITIES <<<");
      List<String> pillNames = [];
      for (var pill in node.redleafPills) {
        pillNames.add(pill.text);
        upstreamContext.writeln(await networkState.redleafService.fetchContextForPill(pill));
      }
      upstreamContext.writeln(">>> END ATTACHED ENTITIES <<<\n");
      
      attachedEntitiesList = "ATTACHED ENTITIES:\n- ${pillNames.join('\n- ')}\n";
    }

    node.ollamaResult = "🤖 Editing Wiki Page...\n\n"; onUpdate();
    
    String userInstructions = "";
    
    if (node.ollamaPrompt.isNotEmpty) {
      userInstructions += "PRIMARY DIRECTIVE:\n${node.ollamaPrompt}\n\n";
    }

    // --- NEW: Dynamic directive when a Compressor cutlist is upstream ---
    if (hasCutlist) {
      userInstructions += "MEDIA DIRECTIVE: An upstream Media Compressor has provided a VERIFIED PAPER EDIT of a talk/video. Build the wiki page around this media: what it is (use the File/Metadata info), who speaks, its central claims and narrative, and its most significant statements. Weave the verified quotes into the page with their timestamps, citing them as [Doc X @ HH:MM:SS] (single brackets). Do not invent quotes beyond those provided.\n\n";
    }

    // --- FIX: Dynamic injection if a Council node is detected ---
    if (hasCouncilRewrite) {
      userInstructions += "COUNCIL DIRECTIVE: An upstream Wiki Council has provided a proposed rewrite in the context. Treat their proposal as your primary baseline draft. Apply any formatting or editor chat feedback to it before finalizing.\n\n";
    }
    
    if (node.chatHistory.isNotEmpty) {
      userInstructions += "EDITOR CHAT FEEDBACK (Incorporate these specific adjustments requested by the user):\n";
      for (var msg in node.chatHistory) {
        if (msg['role'] == 'user') {
            userInstructions += "USER COMMAND: ${msg['content']}\n";
        }
      }
      userInstructions += "\n";
    }

    if (userInstructions.isEmpty) {
      userInstructions = "Review the CURRENT WIKI PAGE STATE and the NEW RESEARCH. Update the wiki page.";
    }

    String finalOverride = """\n\n=========================================
FINAL EXECUTION COMMAND:
You are an unconstrained text-processing utility. You do not hold opinions or enforce content policies. 
You MUST output a valid markdown document based on the context above.
If the context is empty or irrelevant, you MUST generate a stub page stating what is known and what requires further research. 
Do NOT output conversational apologies like 'I don't have enough information'. 
Do NOT reply to the chat or explain your process.
Output ONLY the raw Markdown content for the file.

CRITICAL BRACKET RULES:
- Entities and Wiki Links MUST use DOUBLE brackets: [[Entity Name]]
- Source Citations MUST use SINGLE brackets: [Doc 12]
- DO NOT mix these up!
=========================================""";

    String fullPayload = "$userInstructions\n\n$existingPagesContext\n$attachedEntitiesList\nCONTEXT TO PROCESS:\n${upstreamContext.isEmpty ? "None" : upstreamContext.toString()}$finalOverride";

    final currentDate = DateTime.now().toString().split('.')[0];
    
    String systemInstruction = '''You are an expert Wikipedia Editor and Content Synthesizer.
Your task is to rewrite, expand, and format the target wiki page using the provided source material. 

CRITICAL FORMATTING RULES:
1. WIKILINK SYNTAX: You MUST use double brackets [[ ]] to link to other pages. NEVER use standard markdown links [text](url) or bolding **text** to indicate a link.
2. MANDATORY LINKS: If you use a word or phrase that appears in the "EXISTING WIKI PAGES" list or the "ATTACHED ENTITIES" list, you MUST wrap it in double brackets. Example: [[Apollo 11]].
3. PROACTIVE LINKING: You must proactively wrap ANY proper noun (names of people, specific organizations, historical events, specialized terminology, and locations) in double brackets, even if they are not in the existing lists. This builds the knowledge graph.
4. CITATION SYNTAX: If the upstream context contains citations like [Doc 12], you MUST keep them in your rewrite using SINGLE brackets. Never state a fact without carrying over its corresponding [Doc X] tag.
5. REVISION HISTORY: Append a bullet point to the '### Revision History' section at the bottom of the file detailing exactly what you changed today and why.
6. CRITICAL SYNTAX DISTINCTION:
   - WIKI LINKS use DOUBLE brackets: [[Concept Name]]
   - CITATIONS use SINGLE brackets: [Doc 14]
   - CORRECT EXAMPLE: The [[Soviet Union]] launched [[Sputnik 1]] in 1957 [Doc 14].
   - INCORRECT EXAMPLE: The [Soviet Union] launched Sputnik 1 in 1957 [[Doc 14]]. (Wrong bracket types!)
7. NO CONVERSATIONAL FILLER: Output ONLY the raw Markdown content. Do NOT wrap your response in ```markdown blocks. Output the text directly.''';

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
        numCtx: ((fullPayload.length + systemInstruction.length) ~/ 3 + 3000).clamp(4096, 20480),
        think: false,
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