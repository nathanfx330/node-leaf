// --- File: lib/agents/media_evidence.dart ---
//
// MEDIA EVIDENCE PACKS: how transcripts enter adversarial loops.
//
// The Wiki Council and Wiki Writer are iterative/adversarial - upstream
// context is re-injected into EVERY expert turn. A raw 40k-token SRT would
// be copied into ten debate prompts (and silently truncated by every one of
// them). So raw transcripts never enter those loops. Instead, this agent
// distills a transcript ONCE into a compact, machine-verified Evidence Pack:
//
//   * KEY FACTS - summarized per segment, deduplicated.
//   * VERIFIED QUOTES - the model proposes quotes WITHOUT timestamps; this
//     code locates each one in the actual cue index and stamps it with its
//     TRUE timecodes. Quotes that appear nowhere in the footage are dropped.
//     The model cannot fabricate a citation it was never asked to produce.
//
// Packs are cached per (doc, brief, pills, model) for the app session, so
// re-running a Council after Chairman feedback costs nothing.

import 'dart:convert';

import '../models/node_models.dart';
import '../state/network_state.dart';
import '../services/ollama_service.dart';

class _EvCue {
  final String startRaw;
  final String endRaw;
  final String normDialogue;
  _EvCue(this.startRaw, this.endRaw, this.normDialogue);
}

class MediaEvidenceAgent {
  // Context budget for distillation calls - deliberately modest (VRAM-kind).
  static const int kPackCtx = 12288;
  static const int kMinPackCtx = 6144;
  static const double kCpt = 2.8; // chars/token, conservative for SRT
  static const int kPromptOverhead = 1200;
  static const int kGenReserve = 1500;
  // Longest quote span, in cues, when locating.
  static const int kMaxSpanCues = 12;
  // Pack size caps.
  static const int kMaxFacts = 30;
  static const int kMaxQuotes = 20;

  static final Map<String, String> _packCache = {};

  static String _normalize(String s) {
    return s
        .toLowerCase()
        .replaceAll(RegExp(r"[^a-z0-9\s]"), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  static bool _isVramError(Object e) {
    final s = e.toString().toLowerCase();
    return s.contains('cuda') ||
        s.contains('resource allocation') ||
        s.contains('out of memory') ||
        s.contains('failed to allocate');
  }

  /// Locates [normQuote] in [cues]. Returns [startIdx, endIdx] of the
  /// tightest containing span, or null if the quote appears nowhere.
  static List<int>? _locate(String normQuote, List<_EvCue> cues) {
    if (normQuote.length < 10) return null;
    for (int i = 0; i < cues.length; i++) {
      final sb = StringBuffer();
      for (int k = i; k < cues.length && k < i + kMaxSpanCues; k++) {
        if (sb.isNotEmpty) sb.write(' ');
        sb.write(cues[k].normDialogue);
        if (sb.length >= normQuote.length && sb.toString().contains(normQuote)) {
          int st = i;
          while (st < k) {
            final sub = cues.sublist(st + 1, k + 1).map((c) => c.normDialogue).join(' ');
            if (sub.contains(normQuote)) { st++; } else { break; }
          }
          return [st, k];
        }
      }
    }
    return null;
  }

  /// Builds (or returns the cached) Evidence Pack for a Media Reader node.
  /// [onProgress] receives status lines for the calling agent's log.
  static Future<String> buildPack({
    required StoryNode mediaNode,
    required NetworkState networkState,
    required void Function(String) onProgress,
  }) async {
    final cacheKey = [
      mediaNode.content.trim(),
      mediaNode.ollamaPrompt.trim(),
      mediaNode.redleafPills.map((p) => p.text).join(','),
      '${networkState.ollamaUrl}|${networkState.ollamaModel}',
    ].join('||');

    final cached = _packCache[cacheKey];
    if (cached != null) {
      onProgress("  - Evidence pack for Media Reader '${mediaNode.content}' already distilled this session; reusing.\n");
      return cached;
    }

    final raw = await networkState.redleafService.fetchTranscriptContext(mediaNode);

    // ---- Parse the transcript context back into header / cues / trailer ----
    final docMatch = RegExp(r'MEDIA TRANSCRIPT \(DOC #(\d+)\)').firstMatch(raw);
    if (docMatch == null) return raw; // Error string or unexpected shape: pass through.
    final String docId = docMatch.group(1)!;

    final lines = raw.split('\n');
    final int dividerIdx = lines.indexWhere((l) => l.startsWith('-----'));
    if (dividerIdx == -1) return raw;
    int trailerIdx = lines.length;
    for (int i = dividerIdx + 1; i < lines.length; i++) {
      if (lines[i].startsWith('>>>')) { trailerIdx = i; break; }
    }

    final String headerMeta = lines
        .sublist(0, dividerIdx)
        .where((l) => l.startsWith('File:') || l.startsWith('Metadata:'))
        .join('\n');
    final String trailer = lines
        .sublist(trailerIdx)
        .where((l) => !l.contains('END TRANSCRIPT'))
        .join('\n')
        .trim();

    final cueRegex = RegExp(r'^\[(.+?)-->(.+?)\]\s*(.*)$');
    final List<_EvCue> cues = [];
    final List<String> cueLines = [];
    for (int i = dividerIdx + 1; i < trailerIdx; i++) {
      final line = lines[i].trim();
      if (line.isEmpty) continue;
      final m = cueRegex.firstMatch(line);
      if (m == null) continue;
      cues.add(_EvCue(m.group(1)!.trim(), m.group(2)!.trim(), _normalize(m.group(3) ?? '')));
      cueLines.add(line);
    }
    if (cues.isEmpty) return raw;

    // ---- Chunk cue lines to fit the distillation context ----
    final int chunkCharBudget = ((kPackCtx - kPromptOverhead - kGenReserve) * kCpt).floor();
    final List<List<String>> chunks = [];
    List<String> current = [];
    int currentChars = 0;
    for (final line in cueLines) {
      if (currentChars + line.length > chunkCharBudget && current.isNotEmpty) {
        chunks.add(current);
        current = [];
        currentChars = 0;
      }
      current.add(line);
      currentChars += line.length + 1;
    }
    if (current.isNotEmpty) chunks.add(current);

    final String focus = mediaNode.ollamaPrompt.trim().isNotEmpty
        ? "FOCUS (from the editor's brief): ${mediaNode.ollamaPrompt.trim()}"
        : "FOCUS: General - capture what matters most in this footage.";

    // ---- MAP: distill each chunk into facts + candidate quotes ----
    final List<String> facts = [];
    final Set<String> factNorms = <String>{};
    final List<String> quoteBlocks = [];
    final Set<String> quoteNorms = <String>{};
    int verified = 0, droppedQuotes = 0;
    int ctx = kPackCtx;

    for (int i = 0; i < chunks.length; i++) {
      onProgress("  - Distilling media evidence: segment ${i + 1}/${chunks.length} of Doc $docId...\n");

      final String prompt = """You are a documentary research assistant creating an evidence digest from a transcript segment.

$focus

TRANSCRIPT SEGMENT (${i + 1} of ${chunks.length}):
${chunks[i].join('\n')}

Return ONLY a JSON object with this exact shape:
{"facts": ["...", "..."], "quotes": ["...", "..."]}

RULES:
- "facts": up to 6 concise factual statements this segment establishes (names, events, causal claims, numbers). Neutral wording.
- "quotes": up to 5 of the most significant VERBATIM quotes from the segment. Copy the dialogue text EXACTLY as written, joining consecutive cues if a thought spans them. Do NOT include timestamps - they will be added automatically.
- If the segment contains nothing relevant, return {"facts": [], "quotes": []}.""";

      try {
        final int callCtx = ((prompt.length / kCpt).ceil() + kPromptOverhead + kGenReserve).clamp(4096, ctx);
        final res = await OllamaService.generateTextDetailed(
          baseUrl: networkState.ollamaUrl,
          model: networkState.ollamaModel,
          prompt: prompt,
          format: "json",
          numCtx: callCtx,
          numPredict: kGenReserve,
          think: false,
        );

        Map<String, dynamic> parsed;
        try {
          parsed = jsonDecode(res.text.replaceAll('```json', '').replaceAll('```', '').trim());
        } catch (_) {
          onProgress("  - Segment ${i + 1}: unparseable response, skipped.\n");
          continue;
        }

        if (parsed['facts'] is List) {
          for (final f in parsed['facts']) {
            final fs = f.toString().trim();
            final fn = _normalize(fs);
            if (fs.isEmpty || fn.isEmpty || factNorms.contains(fn)) continue;
            if (facts.length >= kMaxFacts) break;
            factNorms.add(fn);
            facts.add(fs);
          }
        }

        if (parsed['quotes'] is List) {
          for (final q in parsed['quotes']) {
            final qs = q.toString().trim();
            final qn = _normalize(qs);
            if (qn.isEmpty || quoteNorms.contains(qn)) continue;
            if (quoteBlocks.length >= kMaxQuotes) break;
            final span = _locate(qn, cues);
            if (span == null) {
              droppedQuotes++; // Not verbatim: the model embellished. Gone.
              continue;
            }
            quoteNorms.add(qn);
            quoteBlocks.add('[Doc $docId @ ${cues[span[0]].startRaw} --> ${cues[span[1]].endRaw}] "$qs"');
            verified++;
          }
        }
      } catch (e) {
        if (_isVramError(e) && ctx > kMinPackCtx) {
          ctx = (ctx ~/ 2).clamp(kMinPackCtx, kPackCtx);
          onProgress("  - VRAM pressure during distillation; retrying segment ${i + 1} at num_ctx=$ctx...\n");
          i--; // Retry this segment at the smaller budget.
          continue;
        }
        onProgress("  - Segment ${i + 1} failed: $e\n");
      }
    }

    if (facts.isEmpty && quoteBlocks.isEmpty) {
      return "\n>>> MEDIA EVIDENCE PACK: DOC #$docId <<<\n$headerMeta\n[Distillation produced no usable evidence - the model may be failing; see agent log.]\n>>> END EVIDENCE PACK <<<\n";
    }

    // ---- Assemble the pack ----
    final StringBuffer pack = StringBuffer();
    pack.writeln("\n>>> MEDIA EVIDENCE PACK: DOC #$docId (MACHINE-VERIFIED) <<<");
    if (headerMeta.isNotEmpty) pack.writeln(headerMeta);
    pack.writeln("This is a distilled digest of a full media transcript. Every quote below was verified VERBATIM against the source subtitles and stamped with its true timestamps by the system - treat them as ground truth. Cite facts from this pack as [Doc $docId]. When citing a quote, carry its timestamp, e.g. [Doc $docId @ 01:10:47].");
    pack.writeln("\nKEY FACTS:");
    for (final f in facts) {
      pack.writeln("- $f [Doc $docId]");
    }
    pack.writeln("\nVERIFIED QUOTES (verbatim, true timestamps):");
    for (final q in quoteBlocks) {
      pack.writeln(q);
    }
    if (trailer.isNotEmpty) {
      pack.writeln();
      pack.writeln(trailer);
    }
    pack.writeln("\n[Evidence QC: ${chunks.length} segment(s) distilled, $verified quote(s) verified verbatim${droppedQuotes > 0 ? ', $droppedQuotes non-verbatim quote(s) dropped' : ''}, ${facts.length} fact(s).]");
    pack.writeln(">>> END EVIDENCE PACK <<<\n");

    final result = pack.toString();
    _packCache[cacheKey] = result;
    return result;
  }
}