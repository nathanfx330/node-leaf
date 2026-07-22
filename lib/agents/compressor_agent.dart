// --- File: lib/agents/compressor_agent.dart ---
//
// V3: REEL-BY-REEL PROCESSING + DETERMINISTIC QC.
//
// Local models are unreliable narrators: they renumber Doc citations as if
// they were cut counters, invent timestamps, and deliver 2 cuts when asked
// for 10. But this agent fetched every cue - it KNOWS the ground truth. So:
//
//   1. BUDGET   - probe the model's context window, cap by VRAM ceiling.
//   2. MAP      - split transcripts into reels, extract candidate cuts.
//   3. REDUCE   - stream a final selection of targetCutCount cuts.
//   4. QC       - validate every cut against the real cue index:
//                   * wrong Doc citations are REWRITTEN to the true source
//                   * cuts with nonexistent timestamps are REMOVED
//                   * shortfalls are TOPPED UP from unused validated candidates
//
// The model proposes; the code disposes.

import '../constants.dart';
import '../models/node_models.dart';
import '../state/graph_state.dart';
import '../state/network_state.dart';
import '../services/ollama_service.dart';

// A transcript decomposed for chunking.
class _ReelSource {
  final String docId;
  final String header;   // ">>> REDLEAF MEDIA TRANSCRIPT..." block incl. divider
  final List<String> cueLines;
  final String trailer;  // Brief / entities / curation blocks + END marker
  _ReelSource(this.docId, this.header, this.cueLines, this.trailer);
}

// A single subtitle cue with its dialogue, position, and owner.
class _Cue {
  final String docId;
  final int indexInDoc;
  final int startMs;
  final int endMs;
  final String startRaw;
  final String endRaw;
  final String normDialogue;
  _Cue(this.docId, this.indexInDoc, this.startMs, this.endMs, this.startRaw, this.endRaw, this.normDialogue);
}

class _CueSpan {
  final _Cue start;
  final _Cue end;
  _CueSpan(this.start, this.end);
}

// Ground truth: every legal timestamp, which document owns it, and WHAT WAS
// ACTUALLY SAID there - so quotes can be verified and relocated.
class _CueIndex {
  // startMs -> cues starting there (can collide across documents)
  final Map<int, List<_Cue>> byStart = {};
  // docId -> ordered cue list
  final Map<String, List<_Cue>> cuesByDoc = {};
  // docId -> set of legal end times (ms)
  final Map<String, Set<int>> endsByDoc = {};

  // Longest span (in cues) a single cut may cover when verifying/locating.
  static const int kMaxSpanCues = 12;

  static int? toMs(String raw) {
    final s = parseTs(raw);
    return s == null ? null : (s * 1000).round();
  }

  static double? parseTs(String raw) {
    final clean = raw.trim().replaceAll(',', '.');
    final parts = clean.split(':');
    try {
      if (parts.length == 3) return int.parse(parts[0]) * 3600 + int.parse(parts[1]) * 60 + double.parse(parts[2]);
      if (parts.length == 2) return int.parse(parts[0]) * 60 + double.parse(parts[1]);
    } catch (_) {}
    return null;
  }

  /// Lowercase, strip punctuation, collapse whitespace - for text matching.
  static String normalize(String s) {
    return s
        .toLowerCase()
        .replaceAll(RegExp(r"[^a-z0-9\s]"), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  void addSource(_ReelSource src) {
    final cueRegex = RegExp(r'^\[(.+?)-->(.+?)\]\s*(.*)$');
    final list = cuesByDoc.putIfAbsent(src.docId, () => []);
    for (final line in src.cueLines) {
      final m = cueRegex.firstMatch(line.trim());
      if (m == null) continue;
      final startRaw = m.group(1)!.trim();
      final endRaw = m.group(2)!.trim();
      final startMs = toMs(startRaw);
      final endMs = toMs(endRaw);
      if (startMs == null || endMs == null) continue;
      final cue = _Cue(src.docId, list.length, startMs, endMs, startRaw, endRaw, normalize(m.group(3) ?? ''));
      list.add(cue);
      byStart.putIfAbsent(startMs, () => []).add(cue);
      endsByDoc.putIfAbsent(src.docId, () => <int>{}).add(endMs);
    }
  }

  /// Finds the cue starting at [startMs], preferring [preferDocId] on collision.
  _Cue? cueAtStart(int startMs, String preferDocId) {
    final list = byStart[startMs];
    if (list == null || list.isEmpty) return null;
    for (final c in list) {
      if (c.docId == preferDocId) return c;
    }
    return list.first;
  }

  /// Concatenated normalized dialogue from [start] through the cue whose end
  /// is [endMs] (bounded by kMaxSpanCues). Null if endMs closes no cue in range.
  String? spanText(_Cue start, int endMs) {
    final cues = cuesByDoc[start.docId]!;
    final sb = StringBuffer();
    for (int k = start.indexInDoc; k < cues.length && k < start.indexInDoc + kMaxSpanCues; k++) {
      if (sb.isNotEmpty) sb.write(' ');
      sb.write(cues[k].normDialogue);
      if (cues[k].endMs == endMs) return sb.toString();
    }
    return null;
  }

  /// The cue whose end time is [endMs], within span range of [start].
  _Cue? endCueOf(_Cue start, int endMs) {
    final cues = cuesByDoc[start.docId]!;
    for (int k = start.indexInDoc; k < cues.length && k < start.indexInDoc + kMaxSpanCues; k++) {
      if (cues[k].endMs == endMs) return cues[k];
    }
    return null;
  }

  /// Searches ALL documents for where [normQuote] is actually spoken.
  /// Returns the tightest cue span containing it, or null if it appears
  /// nowhere (i.e. the model paraphrased).
  _CueSpan? locateQuote(String normQuote) {
    if (normQuote.length < 10) return null; // Too short to match reliably.
    for (final cues in cuesByDoc.values) {
      for (int i = 0; i < cues.length; i++) {
        final sb = StringBuffer();
        for (int k = i; k < cues.length && k < i + kMaxSpanCues; k++) {
          if (sb.isNotEmpty) sb.write(' ');
          sb.write(cues[k].normDialogue);
          if (sb.length >= normQuote.length && sb.toString().contains(normQuote)) {
            // Shrink leading cues that aren't needed.
            int st = i;
            while (st < k) {
              final sub = cues.sublist(st + 1, k + 1).map((c) => c.normDialogue).join(' ');
              if (sub.contains(normQuote)) { st++; } else { break; }
            }
            return _CueSpan(cues[st], cues[k]);
          }
        }
      }
    }
    return null;
  }
}

// One parsed cut block from model output.
class _CutBlock {
  final String claimedDocId;
  final String startRaw;
  final String endRaw;
  String block; // Full markdown block, mutable so citations can be repaired.
  _CutBlock(this.claimedDocId, this.startRaw, this.endRaw, this.block);
}

// Accumulating QC: validates cuts against ground truth across multiple
// ingestion rounds (final pass, candidate top-up, continuation requests).
class _QcSession {
  final _CueIndex index;
  final Set<int> _usedStarts = <int>{};
  final Set<String> _usedQuotes = <String>{};
  final List<_CutBlock> accepted = [];
  int corrected = 0, removed = 0, endFixed = 0, toppedUp = 0, rounds = 0;
  int relocated = 0, paraphrased = 0;

  _QcSession(this.index);

  int get count => accepted.length;

  /// Comma-separated start timestamps already used - for "do not repeat"
  /// lists. Reads from the (possibly relocated/repaired) block text, not the
  /// original parse.
  String get usedStartsRaw => accepted
      .map((c) => RegExp(r'\[([\d:.,]+)\s*-->').firstMatch(c.block)?.group(1) ?? c.startRaw)
      .join(', ');

  /// Extracts the quoted dialogue line from a cut block, normalized.
  /// Anchored to line start: the first bare '>' in a block is inside the
  /// timestamp's '-->', which must never be mistaken for the quote line.
  static String _extractNormQuote(String block) {
    final m = RegExp(r'^\s*>\s*"?(.+?)"?\s*$', multiLine: true).firstMatch(block);
    if (m == null) return '';
    final norm = _CueIndex.normalize(m.group(1)!);
    // Guard: a real quote contains words, not timestamp debris.
    if (!RegExp(r'[a-z]').hasMatch(norm)) return '';
    return norm;
  }

  /// Validates and absorbs cuts from [text]. Returns how many were accepted.
  /// Every cut must be VERBATIM dialogue at its claimed span; quotes found
  /// elsewhere in the footage are relocated to their true timestamps; quotes
  /// found nowhere are dropped as paraphrases.
  int ingest(String text, {bool asTopUp = false, int? capAt}) {
    int added = 0;
    for (final cut in CompressorAgent._parseCutBlocks(text)) {
      if (capAt != null && accepted.length >= capAt) break;

      final String normQuote = _extractNormQuote(cut.block);
      final int? claimedStartMs = _CueIndex.toMs(cut.startRaw);
      final int? claimedEndMs = _CueIndex.toMs(cut.endRaw);

      _Cue? startCue = (claimedStartMs != null)
          ? index.cueAtStart(claimedStartMs, cut.claimedDocId)
          : null;
      _Cue? endCue = (startCue != null && claimedEndMs != null)
          ? index.endCueOf(startCue, claimedEndMs)
          : null;

      // --- Verbatim check: does the quote actually live at the claimed span?
      bool verbatimOk = false;
      if (normQuote.isNotEmpty && startCue != null) {
        final String span = (endCue != null)
            ? (index.spanText(startCue, claimedEndMs!) ?? startCue.normDialogue)
            : startCue.normDialogue;
        verbatimOk = span.contains(normQuote);
      }

      // --- Relocation: quote is real but the timestamps are wrong (the
      // "reuse the quote, shift the timecode" cheat). Find the truth.
      if (!verbatimOk && normQuote.isNotEmpty) {
        final located = index.locateQuote(normQuote);
        if (located != null) {
          startCue = located.start;
          endCue = located.end;
          cut.block = cut.block.replaceFirst(
            RegExp(r'\*\*\[Doc\s*\d+\]\*\*\s*\[[\d:.,]+\s*-->\s*[\d:.,]+\]'),
            '**[Doc ${startCue.docId}]** [${startCue.startRaw} --> ${endCue.endRaw}]',
          );
          relocated++;
          verbatimOk = true;
        } else {
          // Quote appears nowhere in the footage: paraphrased. Drop.
          paraphrased++;
          continue;
        }
      }

      if (startCue == null) {
        removed++;
        continue; // No quote to verify and timestamp exists nowhere.
      }

      // --- Duplicate suppression by BOTH position and content.
      if (_usedStarts.contains(startCue.startMs)) continue;
      if (normQuote.isNotEmpty && _usedQuotes.contains(normQuote)) continue;

      // --- Citation repair (the "cut counter" failure mode).
      if (cut.claimedDocId != startCue.docId) {
        cut.block = cut.block.replaceFirst(
          RegExp(r'\*\*\[Doc\s*\d+\]\*\*'), '**[Doc ${startCue.docId}]**');
        corrected++;
      }

      // --- End time must close a real cue at/after the start (no zero-length
      // or backwards spans). Otherwise snap to the start cue's own end.
      final int? endMs = _CueIndex.toMs(
          RegExp(r'-->\s*([\d:.,]+)\]').firstMatch(cut.block)?.group(1) ?? cut.endRaw);
      final bool endOk = endMs != null &&
          endMs > startCue.startMs &&
          index.endCueOf(startCue, endMs) != null;
      if (!endOk) {
        cut.block = cut.block.replaceFirst(
          RegExp(r'-->\s*[\d:.,]+\]'), '--> ${startCue.endRaw}]');
        endFixed++;
      }

      _usedStarts.add(startCue.startMs);
      if (normQuote.isNotEmpty) _usedQuotes.add(normQuote);
      accepted.add(cut);
      if (asTopUp) toppedUp++;
      added++;
    }
    return added;
  }

  String format(int targetCount) {
    final StringBuffer out = StringBuffer();
    for (final cut in accepted) {
      out.writeln(cut.block);
      if (!cut.block.trimRight().endsWith('---')) out.writeln('---');
      out.writeln();
    }

    out.writeln();
    out.write('*System QC: ${accepted.length}/$targetCount cuts delivered.');
    if (rounds > 0) out.write(' $rounds continuation round(s) used.');
    if (corrected > 0) out.write(' $corrected citation(s) corrected.');
    if (endFixed > 0) out.write(' $endFixed end time(s) snapped to real cues.');
    if (relocated > 0) out.write(' $relocated quote(s) relocated to their true timestamps.');
    if (paraphrased > 0) out.write(' $paraphrased paraphrased (non-verbatim) cut(s) dropped.');
    if (removed > 0) out.write(' $removed hallucinated cut(s) removed.');
    if (toppedUp > 0) out.write(' $toppedUp topped up from reel candidates.');
    out.write(' All timestamps verified against source cues.');
    if (accepted.length < targetCount) {
      out.write(' Shortfall: the model could not surface more distinct valid '
          'cuts for this directive — consider broadening the directive or '
          'raising candidates per reel.');
    }
    out.writeln('*');
    return out.toString();
  }
}

// Thrown when Ollama reports a GPU memory failure - triggers a retry of the
// whole pass at a smaller context budget.
class _VramPressure implements Exception {
  final String detail;
  _VramPressure(this.detail);
}

// Thrown when a prompt filled the entire context window (no room left to
// generate) - triggers a re-pack with the measured chars/token ratio at the
// SAME budget. VRAM was fine; the token estimate was wrong.
class _CtxOverflow implements Exception {
  final String detail;
  _CtxOverflow(this.detail);
}

class CompressorAgent {
  // Hard ceiling regardless of what the model claims - protects VRAM.
  static const int kVramCtxCap = 32768;
  // Below this, chunking overhead exceeds the value - abort instead.
  static const int kMinCtxBudget = 6144;
  // Assumed when /api/show can't tell us the model's context length.
  static const int kFallbackModelCtx = 8192;
  // Default chars-per-token for timestamped SRT text. Digit-dense timestamps
  // tokenize badly (~2.5-3 chars/token), so this errs conservative. It is
  // replaced by a MEASURED ratio (from Ollama's prompt_eval_count) after the
  // first real call for each model.
  static const double kCharsPerToken = 2.8;
  // Tokens reserved for prompt scaffolding (system prompt, directive, format).
  static const int kOverheadTokens = 1500;
  // Tokens explicitly reserved for the model's ANSWER. Packing must leave this
  // much air below num_ctx, or the model hits the ceiling and emits nothing.
  static const int kGenReserveTokens = 2500;

  // --- NEW: Measured chars/token per model - ground truth from
  // prompt_eval_count, stored with a 5% safety discount.
  static final Map<String, double> _measuredCpt = {};

  // --- NEW: Once a budget survives a full run on this hardware, start there
  // next time instead of re-discovering the ceiling by crashing CUDA.
  static final Map<String, int> _knownGoodBudget = {};

  // --- NEW: Recognizes GPU memory failures in Ollama error strings.
  static bool _isVramError(Object e) {
    final s = e.toString().toLowerCase();
    return s.contains('cuda') ||
        s.contains('resource allocation') ||
        s.contains('out of memory') ||
        s.contains('vram') ||
        s.contains('failed to allocate');
  }

  static int _estimateTokens(int chars) => (chars / kCharsPerToken).ceil();

  /// Splits a fetchTranscriptContext() string back into header / cues / trailer.
  static _ReelSource? _parseTranscriptContext(String context) {
    final lines = context.split('\n');
    final docMatch = RegExp(r'MEDIA TRANSCRIPT \(DOC #(\d+)\)').firstMatch(context);
    if (docMatch == null) return null;
    final docId = docMatch.group(1)!;

    int dividerIdx = lines.indexWhere((l) => l.startsWith('-----'));
    if (dividerIdx == -1) return null;

    int trailerIdx = lines.length;
    for (int i = dividerIdx + 1; i < lines.length; i++) {
      if (lines[i].startsWith('>>>')) { trailerIdx = i; break; }
    }

    final header = lines.sublist(0, dividerIdx + 1).join('\n');
    final cues = lines
        .sublist(dividerIdx + 1, trailerIdx)
        .where((l) => l.trim().isNotEmpty)
        .toList();
    final trailer = trailerIdx < lines.length ? lines.sublist(trailerIdx).join('\n') : '';
    return _ReelSource(docId, header, cues, trailer);
  }

  /// Packs cue lines into reels no larger than [charBudget].
  static List<List<String>> _packReels(List<String> cueLines, int charBudget) {
    final List<List<String>> reels = [];
    List<String> current = [];
    int currentChars = 0;
    for (final line in cueLines) {
      if (currentChars + line.length > charBudget && current.isNotEmpty) {
        reels.add(current);
        current = [];
        currentChars = 0;
      }
      current.add(line);
      currentChars += line.length + 1;
    }
    if (current.isNotEmpty) reels.add(current);
    return reels;
  }

  /// Parses **[Doc X]** [A --> B] cut blocks out of model output.
  static List<_CutBlock> _parseCutBlocks(String text) {
    final List<_CutBlock> cuts = [];
    final cutRegex = RegExp(r'\*\*\[Doc\s*(\d+)\]\*\*\s*\[([\d:.,]+)\s*-->\s*([\d:.,]+)\]');
    final matches = cutRegex.allMatches(text).toList();
    for (int i = 0; i < matches.length; i++) {
      final m = matches[i];
      final blockEnd = (i + 1 < matches.length) ? matches[i + 1].start : text.length;
      cuts.add(_CutBlock(
        m.group(1)!,
        m.group(2)!.trim(),
        m.group(3)!.trim(),
        text.substring(m.start, blockEnd).trim(),
      ));
    }
    return cuts;
  }

  // (QC logic lives in _QcSession below — it accumulates cuts across the
  // initial pass, candidate top-up, and continuation rounds.)

  static Future<void> execute({
    required StoryNode node,
    required List<StoryNode> sequence,
    required GraphState graphState,
    required NetworkState networkState,
    bool Function()? checkForceAnswer,
    required Function() onUpdate,
  }) async {
    bool forced() => checkForceAnswer?.call() ?? false;

    node.ollamaResult = "🎬 Gathering media transcripts and context...\n";
    onUpdate();

    // ------------------------------------------------------------------
    // 1. GATHER
    // ------------------------------------------------------------------
    final List<_ReelSource> reelSources = [];
    StringBuffer otherContext = StringBuffer();
    String customPersona = "";

    for (var n in sequence) {
      if (n.type == NodeType.output || n.type == NodeType.chat || n.type == NodeType.study || n.type == NodeType.summarize || n.type == NodeType.wikiWriter || n.type == NodeType.council || n.type == NodeType.researchParty || n.type == NodeType.merge || n.type == NodeType.compressor) continue;

      if (n.type == NodeType.persona) {
        customPersona = n.content.trim();
        continue;
      }

      if (n.type == NodeType.briefing) {
        otherContext.writeln(await networkState.redleafService.fetchSystemBriefing());
      } else if (n.type == NodeType.search && n.content.isNotEmpty) {
        otherContext.writeln(await networkState.redleafService.fetchAdvancedFtsContext(n.content, n.searchLimit, n.pinnedSearchResults));
      } else if (n.type == NodeType.document && n.content.isNotEmpty) {
        otherContext.writeln(await networkState.redleafService.fetchDocumentText(n));
      } else if (n.type == NodeType.mediaReader && n.content.isNotEmpty) {
        final raw = await networkState.redleafService.fetchTranscriptContext(n);
        final parsed = _parseTranscriptContext(raw);
        if (parsed != null) {
          reelSources.add(parsed);
        } else {
          otherContext.writeln(raw);
        }
      } else if (n.type == NodeType.scene) {
        otherContext.writeln("\n=== [USER NOTE: ${n.title}] ===\n${n.content}\n");
      }
    }

    if (reelSources.isEmpty) {
      node.ollamaResult = "⚠️ No media transcripts found. Wire a Media/SRT Reader (with a valid Doc ID) into this node.";
      onUpdate();
      return;
    }

    // Ground-truth cue index for the QC pass.
    final _CueIndex cueIndex = _CueIndex();
    for (final src in reelSources) {
      cueIndex.addSource(src);
    }
    final String validDocIds = reelSources.map((r) => r.docId).toSet().join(", ");

    String userInstructions = node.ollamaPrompt.isNotEmpty
        ? node.ollamaPrompt
        : "Create a highlight reel focusing on the most dramatic and impactful statements.";

    String systemInstruction = """You are a strict, robotic Video Editing Assistant. 
Your ONLY purpose is to extract verbatim quotes and their exact timestamps from a transcript to create an Edit Decision List (EDL) / Cutlist.
Do NOT act like a chatbot. Do NOT write summaries. Do NOT write introductory paragraphs.""";

    if (customPersona.isNotEmpty) {
      systemInstruction += "\n\nYOUR ACTIVE PERSONA: $customPersona\nYou MUST adopt this persona completely in your selection rationale and tone.";
    }

    final String cutFormat = """You MUST use this EXACT markdown format for every single cut:

**[Doc X]** [START_TIME --> END_TIME]
> "Verbatim dialogue copied exactly from the transcript."
*Editor's Note: One short sentence explaining why this cut was selected.*
---

IMPORTANT: "Doc X" identifies the SOURCE DOCUMENT the quote came from. It is NOT a cut counter - do NOT number cuts sequentially. The ONLY valid Doc ID(s) in this footage: $validDocIds.

SPAN RULE: Subtitle cues are only a sentence long. A good sound bite usually spans SEVERAL CONSECUTIVE cues (roughly 8-25 seconds) to capture a complete thought. To make a spanning cut: use the START time of the FIRST cue and the END time of the LAST cue in the passage, and quote the ENTIRE passage verbatim, joining the cue texts in order. Prefer complete thoughts over single-sentence fragments.""";

    // ------------------------------------------------------------------
    // 2. BUDGET
    // ------------------------------------------------------------------
    node.ollamaResult += "> [System] Probing model context limit...\n";
    onUpdate();
    final int? modelLimit = await OllamaService.fetchModelContextLimit(networkState.ollamaUrl, networkState.ollamaModel);

    // Start from the last budget that survived a full run on this model, if any.
    final String budgetKey = '${networkState.ollamaUrl}|${networkState.ollamaModel}';
    int ctxBudget = (_knownGoodBudget[budgetKey] ?? modelLimit ?? kFallbackModelCtx).clamp(4096, kVramCtxCap);

    final int totalTranscriptChars = reelSources.fold(0, (sum, r) => sum + r.header.length + r.trailer.length + r.cueLines.fold(0, (s, l) => s + l.length + 1));

    // Chars/token: measured ground truth if we have it, conservative default if not.
    double cpt = _measuredCpt[budgetKey] ?? kCharsPerToken;
    int totalTokens = ((totalTranscriptChars + otherContext.length) / cpt).ceil() + kOverheadTokens + kGenReserveTokens;

    node.ollamaResult += "> [System] Model window: ${modelLimit ?? 'unknown (assuming $kFallbackModelCtx)'} tokens. Budget: $ctxBudget${_knownGoodBudget.containsKey(budgetKey) ? ' (known-good for this card)' : ''}. Material: ~${totalTokens - kOverheadTokens} tokens (${cpt.toStringAsFixed(2)} chars/tok${_measuredCpt.containsKey(budgetKey) ? ', measured' : ', estimated'}). Sources: Doc $validDocIds.\n";
    onUpdate();

    String candidatesForTopUp = "";
    String retrySourceMaterial = ""; // What continuation rounds re-present.
    String? finalRaw;
    int overflowRepacks = 0;

    // ------------------------------------------------------------------
    // ADAPTIVE VRAM LOOP: if CUDA chokes at this budget, halve it, re-pack
    // the reels, and run the whole pass again. If a prompt merely OVERFLOWED
    // the window (empty response, prompt_eval_count ~ num_ctx), re-pack with
    // the measured chars/token ratio at the SAME budget. The card and the
    // tokenizer calibrate the system between them.
    // ------------------------------------------------------------------
    bool passSucceeded = false;
    while (!passSucceeded) {
      candidatesForTopUp = "";
      retrySourceMaterial = "";
      finalRaw = null;
      cpt = _measuredCpt[budgetKey] ?? kCharsPerToken;
      totalTokens = ((totalTranscriptChars + otherContext.length) / cpt).ceil() + kOverheadTokens + kGenReserveTokens;
      try {

    if (totalTokens + (totalTokens ~/ 10) <= ctxBudget) {
      // ----------------------------------------------------------------
      // SINGLE PASS - everything fits.
      // ----------------------------------------------------------------
      StringBuffer allMaterial = StringBuffer(otherContext.toString());
      for (final r in reelSources) {
        allMaterial.writeln(r.header);
        r.cueLines.forEach(allMaterial.writeln);
        allMaterial.writeln(r.trailer);
      }

      retrySourceMaterial = allMaterial.toString();

      node.ollamaResult += "> [System] Fits in one pass. Cutting...\n\n";
      onUpdate();

      final String payload = """DIRECTIVE:
$userInstructions

RAW TRANSCRIPTS TO PROCESS:
${allMaterial.toString()}

=========================================
FINAL EXECUTION INSTRUCTIONS:
Review the transcripts above. Select the best moments that match the DIRECTIVE.

CRITICAL RULES:
1. EXTRACT EXACTLY ${node.targetCutCount} CUTS. You must not stop until you have provided exactly ${node.targetCutCount} separate cuts.
2. NO SUMMARIES. You must copy and paste the EXACT, VERBATIM dialogue from the transcript.
3. TIMESTAMPS ARE MANDATORY. You must copy the exact start and end timestamps.
4. CITE THE SOURCE. Replace 'X' with the ACTUAL Document ID from the transcript header. Valid IDs: $validDocIds.
5. OUTPUT FORMAT ONLY. Output NOTHING but the formatted cuts. 

$cutFormat

BEGIN CUTLIST NOW:
""";
      finalRaw = await _streamFinal(node, networkState, payload, systemInstruction, ctxBudget, onUpdate);
    } else {
      // ----------------------------------------------------------------
      // 3. MAP - reel-by-reel candidate extraction.
      // ----------------------------------------------------------------
      final int reelCharBudget = ((ctxBudget - kOverheadTokens - kGenReserveTokens) * cpt).floor();

      final List<MapEntry<_ReelSource, List<String>>> allReels = [];
      for (final src in reelSources) {
        final int fixedChars = src.header.length + src.trailer.length;
        final reels = _packReels(src.cueLines, (reelCharBudget - fixedChars).clamp(2000, reelCharBudget));
        for (final reel in reels) {
          allReels.add(MapEntry(src, reel));
        }
      }

      final int totalReels = allReels.length;
      final int candidatesPerReel = ((node.targetCutCount * 2) / totalReels).ceil().clamp(2, 8);

      node.ollamaResult += "> [System] Material exceeds window. Splitting into $totalReels reels, pulling up to $candidatesPerReel candidates per reel.\n\n";
      onUpdate();

      StringBuffer candidates = StringBuffer();
      int reelsScanned = 0;

      for (int i = 0; i < allReels.length; i++) {
        if (forced()) {
          node.ollamaResult += "> [System] ⚡ Early finish requested - skipping remaining ${totalReels - i} reel(s).\n";
          onUpdate();
          break;
        }

        final src = allReels[i].key;
        final reelLines = allReels[i].value;

        node.ollamaResult += "> [Reel ${i + 1}/$totalReels] Scanning Doc ${src.docId} (${reelLines.length} cues)...\n";
        onUpdate();

        final String mapPayload = """DIRECTIVE:
$userInstructions

SOURCE MATERIAL - REEL ${i + 1} OF $totalReels (this is a PARTIAL segment of Doc ${src.docId}):
${src.header}
${reelLines.join('\n')}
${src.trailer}

=========================================
INSTRUCTIONS:
Extract the $candidatesPerReel best candidate cuts from THIS REEL ONLY that match the DIRECTIVE. If this reel contains nothing relevant, output the single word: PASS

CRITICAL RULES:
1. VERBATIM dialogue only, copied exactly.
2. Exact timestamps copied from the cue lines.
3. Every cut in this reel MUST be cited as **[Doc ${src.docId}]** - this is the source document ID, not a cut number.
4. Output NOTHING but formatted cuts (or PASS).

$cutFormat

BEGIN:
""";

        try {
          final int reelCtx = ((mapPayload.length / cpt).ceil() + kOverheadTokens + kGenReserveTokens).clamp(4096, ctxBudget);
          final res = await OllamaService.generateTextDetailed(
            baseUrl: networkState.ollamaUrl,
            model: networkState.ollamaModel,
            prompt: mapPayload,
            system: systemInstruction,
            numCtx: reelCtx,
            numPredict: kGenReserveTokens,
            think: false, // EDL extraction gains nothing from deliberation
          );
          reelsScanned++;

          // --- NEW: Calibrate chars/token from ground truth (with 5% safety
          // discount) so packing gets exact from here on.
          if (res.promptEvalCount > 50) {
            final double measured = mapPayload.length / res.promptEvalCount;
            _measuredCpt[budgetKey] = measured * 0.95;
          }

          final trimmed = res.text.trim();
          if (trimmed.isEmpty) {
            // --- NEW: A thinking model that burned its whole allowance on
            // chain-of-thought is NOT a context problem - don't escalate.
            // (Should not occur once think:false lands; this covers models
            // where the toggle is unsupported.)
            if (res.thinking.trim().isNotEmpty) {
              node.ollamaResult += "> [Reel ${i + 1}/$totalReels] ⚠️ Model spent all ${res.evalCount} output tokens on internal reasoning and produced no cutlist. (Thinking could not be disabled for this model.)\n";
              onUpdate();
            } else
            // Empty + prompt filling the window = context overflow.
            // The token estimate was wrong, not the VRAM. Re-pack, same budget.
            if (res.promptEvalCount >= reelCtx - 1000 || res.doneReason == 'length') {
              throw _CtxOverflow(
                  "prompt consumed ${res.promptEvalCount} of $reelCtx tokens (done_reason: '${res.doneReason}') - insufficient room to generate");
            }
            node.ollamaResult += "> [Reel ${i + 1}/$totalReels] ⚠️ Model returned nothing (done_reason: '${res.doneReason}', prompt ${res.promptEvalCount}/$reelCtx tokens).\n";
            onUpdate();
          } else if (trimmed.toUpperCase().startsWith("PASS")) {
            node.ollamaResult += "> [Reel ${i + 1}/$totalReels] Passed (nothing relevant).\n";
            onUpdate();
          } else {
            candidates.writeln(trimmed);
            candidates.writeln();
            node.ollamaResult += "> [Reel ${i + 1}/$totalReels] Done.\n";
            onUpdate();
          }
        } catch (e) {
          // --- FIX: Sentinels must reach the adaptive loop, not die here.
          if (e is _CtxOverflow || e is _VramPressure) rethrow;
          // GPU memory failures abort this pass so the adaptive loop can
          // retry everything at a smaller budget. Other errors skip the reel.
          if (_isVramError(e)) throw _VramPressure(e.toString());
          node.ollamaResult += "> [Reel ${i + 1}/$totalReels] ⚠️ Failed: $e\n";
          onUpdate();
        }
      }

      if (candidates.isEmpty) {
        node.ollamaResult += "\n⚠️ No candidate cuts were extracted from any reel. Check that the DIRECTIVE matches the footage, or that the model is responding correctly (see reel errors above).";
        onUpdate();
        return;
      }

      candidatesForTopUp = candidates.toString();
      retrySourceMaterial = candidatesForTopUp;

      // ----------------------------------------------------------------
      // 4. REDUCE
      // ----------------------------------------------------------------
      node.ollamaResult += "\n> [System] Assembling final cut from $reelsScanned scanned reel(s)...\n\n";
      onUpdate();

      final String reducePayload = """DIRECTIVE:
$userInstructions

${otherContext.isNotEmpty ? "ADDITIONAL PRODUCTION CONTEXT:\n${otherContext.toString()}\n" : ""}
CANDIDATE CUTS (pre-extracted verbatim from the full footage by your assistant editors):
$candidatesForTopUp

=========================================
FINAL EXECUTION INSTRUCTIONS:
From the CANDIDATE CUTS above, select the ${node.targetCutCount} best cuts that together fulfill the DIRECTIVE. Order them for maximum narrative impact.

CRITICAL RULES:
1. OUTPUT EXACTLY ${node.targetCutCount} CUTS.
2. DO NOT ALTER quotes, timestamps, or Doc citations - copy the selected candidates verbatim. Valid Doc ID(s): $validDocIds.
3. You may rewrite the Editor's Note for each selected cut.
4. OUTPUT FORMAT ONLY. Output NOTHING but the formatted cuts.

$cutFormat

BEGIN FINAL CUTLIST NOW:
""";
      finalRaw = await _streamFinal(node, networkState, reducePayload, systemInstruction, ctxBudget, onUpdate);
      }

        passSucceeded = true;
      } on _CtxOverflow catch (co) {
        overflowRepacks++;
        if (overflowRepacks > 2) {
          // Estimation keeps failing - fall back to brute force: smaller budget.
          node.ollamaResult += "> [System] 🔻 Repeated context overflow (${co.detail}). Escalating to smaller budget...\n";
          onUpdate();
          if (ctxBudget <= kMinCtxBudget) {
            node.ollamaResult += "\n⚠️ Could not fit reels into the context window even at num_ctx=$ctxBudget.";
            onUpdate();
            return;
          }
          ctxBudget = (ctxBudget ~/ 2).clamp(4096, kVramCtxCap);
        } else {
          final double newCpt = _measuredCpt[budgetKey] ?? kCharsPerToken;
          node.ollamaResult += "> [System] 📐 Context overflow (${co.detail}). Token ratio recalibrated to ${newCpt.toStringAsFixed(2)} chars/tok - re-packing reels at the same budget ($ctxBudget)...\n";
          onUpdate();
        }
      } on _VramPressure catch (vp) {
        if (ctxBudget <= kMinCtxBudget) {
          node.ollamaResult += "\n⚠️ GPU memory exhausted even at num_ctx=$ctxBudget. "
              "This model is too large for reliable use on this card at any useful "
              "context size. Try a smaller model (e.g. a 12B) or a tighter "
              "quantization for Compressor work.\nLast error: ${vp.detail}";
          onUpdate();
          return;
        }
        ctxBudget = (ctxBudget ~/ 2).clamp(4096, kVramCtxCap);
        node.ollamaResult += "> [System] 🔻 VRAM pressure detected. Halving context and re-packing reels: retrying entire pass at num_ctx=$ctxBudget...\n";
        onUpdate();
      }
    } // end adaptive VRAM loop

    // This budget survived a complete pass - start here next run.
    _knownGoodBudget[budgetKey] = ctxBudget;

    // ------------------------------------------------------------------
    // 5. QC + CONTINUATION - the model proposes; the code disposes.
    //    Small models love to deliver one beautiful cut and declare
    //    victory. If we're short, we go back for more - up to 2 rounds.
    // ------------------------------------------------------------------
    if (finalRaw == null) return;

    final qc = _QcSession(cueIndex);
    qc.ingest(finalRaw);

    // Free refill first: unused validated map-phase candidates.
    if (qc.count < node.targetCutCount && candidatesForTopUp.isNotEmpty) {
      qc.ingest(candidatesForTopUp, asTopUp: true, capAt: node.targetCutCount);
    }

    const int kMaxContinuationRounds = 2;
    while (qc.count < node.targetCutCount &&
        qc.rounds < kMaxContinuationRounds &&
        !forced()) {
      qc.rounds++;
      final int missing = node.targetCutCount - qc.count;

      node.ollamaResult =
          "🎬 QC: only ${qc.count}/${node.targetCutCount} valid cuts so far. "
          "Requesting $missing more (continuation round ${qc.rounds}/$kMaxContinuationRounds)...\n\n";
      onUpdate();

      final String contPayload = """DIRECTIVE:
$userInstructions

SOURCE MATERIAL:
$retrySourceMaterial

=========================================
CONTINUATION INSTRUCTIONS:
You have ALREADY selected cuts starting at these timestamps - DO NOT repeat any of them:
${qc.usedStartsRaw}

Now select $missing ADDITIONAL, DIFFERENT cuts from the source material that also serve the DIRECTIVE. Broaden your selection - strong secondary moments count.

CRITICAL RULES:
1. OUTPUT EXACTLY $missing CUTS. Do not stop early.
2. VERBATIM dialogue and EXACT timestamps copied from the source material.
3. Valid Doc ID(s): $validDocIds. Doc numbers are source IDs, not cut numbers.
4. OUTPUT FORMAT ONLY. Output NOTHING but the formatted cuts.

$cutFormat

BEGIN ADDITIONAL CUTS NOW:
""";

      String? more;
      try {
        more = await _streamFinal(node, networkState, contPayload, systemInstruction, ctxBudget, onUpdate);
      } on _VramPressure {
        // Don't re-run the whole pass over a continuation - keep what we have.
        node.ollamaResult += "\n> [System] 🔻 VRAM pressure during continuation - salvaging current cuts.\n";
        onUpdate();
        break;
      }
      if (more == null) break; // Error already shown; salvage what we have.
      final added = qc.ingest(more, capAt: node.targetCutCount);
      if (added == 0) break; // Model has nothing new to give - stop asking.
    }

    node.ollamaResult = qc.format(node.targetCutCount);
    onUpdate();
  }

  /// Streams a final generation pass into the node. Returns the raw text for
  /// the QC pass, or null on failure (error already written to the node).
  static Future<String?> _streamFinal(
    StoryNode node,
    NetworkState networkState,
    String payload,
    String systemInstruction,
    int ctxBudget,
    Function() onUpdate,
  ) async {
    try {
      final int numCtx = (_estimateTokens(payload.length) + kOverheadTokens + kGenReserveTokens).clamp(4096, ctxBudget);

      final stream = OllamaService.generateTextStream(
        baseUrl: networkState.ollamaUrl,
        model: networkState.ollamaModel,
        prompt: payload,
        system: systemInstruction,
        numCtx: numCtx,
        think: false, // EDL selection gains nothing from deliberation
      );

      bool receivedAnyTokens = false;
      await for (final chunk in stream) {
        if (!receivedAnyTokens) { node.ollamaResult = ""; receivedAnyTokens = true; }
        node.ollamaResult += chunk;
        onUpdate();
      }

      if (!receivedAnyTokens) {
        node.ollamaResult = "⚠️ The model returned an empty response on the final pass "
            "(payload ${payload.length} chars, num_ctx=$numCtx).\n"
            "Likely causes: the model is still loading into VRAM (try again), or "
            "num_ctx exceeds what your VRAM can hold for this model.";
        onUpdate();
        return null;
      }
      return node.ollamaResult;
    } catch (e) {
      // GPU memory failures bubble up to the adaptive budget loop.
      if (CompressorAgent._isVramError(e)) throw _VramPressure(e.toString());
      node.ollamaResult = "⚠️ Ollama request failed on the final pass.\n\nError details: $e";
      onUpdate();
      return null;
    }
  }
}