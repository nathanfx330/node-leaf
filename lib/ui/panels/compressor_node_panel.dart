// --- File: lib/ui/panels/compressor_node_panel.dart ---
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../services/media_player_service.dart';
import '../../services/redleaf_service.dart';
import '../../state/graph_state.dart';
import '../../state/network_state.dart';
import '../side_panel.dart'; // For PreviewPanel and parseRichText

// --- NEW: A single parsed cut from the paper edit ---
class ParsedCut {
  final String docId;
  final String startRaw;
  final String endRaw;
  final double startSeconds;
  final double endSeconds;
  final String quoteSnippet;
  ParsedCut(this.docId, this.startRaw, this.endRaw, this.startSeconds, this.endSeconds, this.quoteSnippet);

  String get playKey => "$docId|$startRaw";
  String get shortLabel {
    // Trim ",mmm" for the chip label; keep full precision for playback.
    final s = startRaw.split(',').first.split('.').first;
    return "Doc $docId · $s";
  }
}

// --- NEW: Extracts **[Doc X]** [START --> END] cuts (+ the quote below each) ---
List<ParsedCut> parseCutlist(String text) {
  final List<ParsedCut> cuts = [];
  final cutRegex = RegExp(r'\*\*\[Doc\s*(\d+)\]\*\*\s*\[([\d:.,]+)\s*-->\s*([\d:.,]+)\]');
  for (final m in cutRegex.allMatches(text)) {
    final start = RedleafService.parseTimestampToSeconds(m.group(2)!);
    final end = RedleafService.parseTimestampToSeconds(m.group(3)!);
    if (start == null || end == null) continue;

    // Grab the "> quoted dialogue" line that follows, for the tooltip.
    String quote = "";
    final tail = text.substring(m.end, (m.end + 300).clamp(0, text.length));
    final quoteMatch = RegExp(r'>\s*"?([^"\n]+)"?').firstMatch(tail);
    if (quoteMatch != null) quote = quoteMatch.group(1)!.trim();

    cuts.add(ParsedCut(m.group(1)!, m.group(2)!, m.group(3)!, start, end, quote));
  }
  return cuts;
}

class CompressorNodePanel extends StatelessWidget {
  final String nodeId;
  const CompressorNodePanel({super.key, required this.nodeId});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Column(
        children: [
          const TabBar(
            indicatorColor: Colors.white,
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white54,
            tabs: [
              Tab(icon: Icon(Icons.movie_filter), text: "Edit Bay"),
              Tab(icon: Icon(Icons.menu_book), text: "Source Tapes"),
            ],
          ),
          Expanded(
            child: TabBarView(
              children: [
                _CompressorInterface(nodeId: nodeId),
                PreviewPanel(targetNodeId: nodeId), 
              ],
            ),
          )
        ],
      ),
    );
  }
}

class _CompressorInterface extends StatefulWidget {
  final String nodeId;
  const _CompressorInterface({required this.nodeId});
  @override
  State<_CompressorInterface> createState() => _CompressorInterfaceState();
}

class _CompressorInterfaceState extends State<_CompressorInterface> {
  late TextEditingController _promptCtrl;

  // --- NEW: Cache media_status per doc so replays don't re-hit the API ---
  final Map<String, Map<String, dynamic>?> _mediaStatusCache = {};

  @override
  void initState() {
    super.initState();
    final graphState = context.read<GraphState>();
    final initialPrompt = graphState.nodes[widget.nodeId]?.ollamaPrompt ?? "";
    _promptCtrl = TextEditingController(text: initialPrompt.isEmpty ? "Create a highlight reel focusing on the most dramatic and impactful statements." : initialPrompt);
  }

  @override
  void dispose() { _promptCtrl.dispose(); super.dispose(); }

  // --- NEW: Audition a cut using linked media from Redleaf ---
  Future<void> _auditionCut(ParsedCut cut) async {
    final player = MediaPlayerService.instance;

    // Tapping the playing cut again = stop.
    if (player.nowPlayingKey.value == cut.playKey) {
      await player.stop();
      return;
    }

    final networkState = context.read<NetworkState>();
    final service = networkState.redleafService;

    // Resolve linked media (cached per doc).
    if (!_mediaStatusCache.containsKey(cut.docId)) {
      _mediaStatusCache[cut.docId] = await service.fetchMediaStatus(cut.docId);
    }
    final status = _mediaStatusCache[cut.docId];

    if (!mounted) return;
    if (status == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Could not reach Redleaf to check for linked media.")));
      return;
    }
    if (status['linked'] != true) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Doc ${cut.docId} has no linked media in Redleaf. Link an audio/video file in the SRT viewer first.")));
      return;
    }

    // Cue time + Redleaf's stored sync offset = actual media position.
    final double offset = status['offset'] ?? 0.0;
    final double start = (cut.startSeconds + offset).clamp(0.0, double.infinity);
    final double duration = cut.endSeconds - cut.startSeconds;

    await player.playClip(
      url: status['url'],
      startSeconds: start,
      durationSeconds: duration,
      cookie: status['source'] == 'local' ? service.sessionCookie : "",
      playKey: cut.playKey,
    );

    if (mounted && player.lastError.value != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(player.lastError.value!)));
    }
  }

  // --- NEW: The audition strip rendered above the paper edit ---
  Widget _buildAuditionStrip(List<ParsedCut> cuts) {
    return ValueListenableBuilder<String?>(
      valueListenable: MediaPlayerService.instance.nowPlayingKey,
      builder: (context, playingKey, _) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.headphones, color: Colors.cyanAccent, size: 16),
                const SizedBox(width: 8),
                const Text("AUDITION CUTS", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 12, letterSpacing: 1.2)),
                const Spacer(),
                if (playingKey != null)
                  TextButton.icon(
                    style: TextButton.styleFrom(foregroundColor: Colors.redAccent, padding: EdgeInsets.zero),
                    icon: const Icon(Icons.stop, size: 16),
                    label: const Text("STOP", style: TextStyle(fontSize: 11)),
                    onPressed: () => MediaPlayerService.instance.stop(),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6, runSpacing: 6,
              children: cuts.map((cut) {
                final bool isPlaying = playingKey == cut.playKey;
                return Tooltip(
                  message: cut.quoteSnippet.isEmpty ? "${cut.startRaw} --> ${cut.endRaw}" : "\"${cut.quoteSnippet}\"",
                  waitDuration: const Duration(milliseconds: 400),
                  child: ActionChip(
                    avatar: Icon(
                      isPlaying ? Icons.graphic_eq : Icons.play_arrow,
                      size: 16,
                      color: isPlaying ? Colors.black : Colors.cyanAccent,
                    ),
                    backgroundColor: isPlaying ? Colors.cyanAccent : const Color(0xFF0E2A2A),
                    side: BorderSide(color: isPlaying ? Colors.white : Colors.cyanAccent.withValues(alpha: 0.5)),
                    label: Text(
                      cut.shortLabel,
                      style: TextStyle(fontSize: 11, fontFamily: 'monospace', color: isPlaying ? Colors.black : Colors.white),
                    ),
                    onPressed: () => _auditionCut(cut),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 12),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final graphState = context.watch<GraphState>();
    final networkState = context.watch<NetworkState>(); 
    final node = graphState.nodes[widget.nodeId];
    if (node == null) return const SizedBox.shrink();

    final bool isThisGenerating = networkState.isNodeGenerating(widget.nodeId);

    return Padding(
      padding: const EdgeInsets.all(20.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.movie_filter, color: Colors.redAccent, size: 20),
              SizedBox(width: 10),
              Text("MEDIA COMPRESSOR", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white, letterSpacing: 1.5)),
            ],
          ),
          const SizedBox(height: 10),
          const Text("Acts as a Documentary Story Producer. Reads upstream transcripts and cuts them down into a timestamped paper edit based on your narrative goals.", style: TextStyle(color: Colors.white54, fontSize: 12)),
          const SizedBox(height: 20),

          const Text("NARRATIVE GOAL / EDITING INSTRUCTIONS", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
          const SizedBox(height: 5),
          TextField(
            controller: _promptCtrl, maxLines: 3,
            decoration: const InputDecoration(filled: true, fillColor: Color(0xFF222222), border: OutlineInputBorder(borderSide: BorderSide.none), hintText: "E.g., Make a 2-minute sizzle reel highlighting AI dangers..."),
            onChanged: (val) => graphState.updateOllamaPrompt(widget.nodeId, val),
          ),
          const SizedBox(height: 15),

          // --- NEW: Target Cut Count Slider ---
          Row(
            children: [
              const Text("Target Number of Cuts: ", style: TextStyle(color: Colors.white70, fontWeight: FontWeight.bold, fontSize: 12)),
              Text("${node.targetCutCount}", style: const TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold, fontSize: 14)),
            ],
          ),
          Slider(
            value: node.targetCutCount.toDouble(),
            min: 1,
            max: 30,
            divisions: 29,
            activeColor: Colors.redAccent,
            inactiveColor: Colors.white24,
            onChanged: (val) {
              graphState.updateTargetCutCount(widget.nodeId, val.toInt());
            },
          ),
          const SizedBox(height: 15),

          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF331111), 
                foregroundColor: Colors.white, 
                padding: const EdgeInsets.symmetric(vertical: 16),
                side: const BorderSide(color: Colors.redAccent)
              ),
              icon: isThisGenerating 
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)) 
                : const Icon(Icons.content_cut),
              label: Text(isThisGenerating ? "CUTTING FOOTAGE..." : "GENERATE CUTLIST (${networkState.ollamaModel})"),
              onPressed: networkState.isGeneratingOllama ? null : () {
                final sequence = graphState.getCompiledNodes(widget.nodeId);
                networkState.triggerCompressorGeneration(node, sequence, graphState); 
              },
            ),
          ),
          
          if (isThisGenerating) ...[
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.redAccent, 
                  side: const BorderSide(color: Colors.redAccent),
                  padding: const EdgeInsets.symmetric(vertical: 12)
                ),
                icon: const Icon(Icons.flash_on), 
                label: const Text("FINISH CUT EARLY (Skip remaining)"),
                onPressed: () => networkState.forceAnswerNow(),
              ),
            ),
          ],
          
          const SizedBox(height: 20),
          const Text("PAPER EDIT", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
          const SizedBox(height: 10),
          
          // --- NEW: Audition strip (only when the cutlist has parseable timestamped cuts) ---
          Builder(builder: (context) {
            if (isThisGenerating || node.ollamaResult.isEmpty) return const SizedBox.shrink();
            final cuts = parseCutlist(node.ollamaResult);
            if (cuts.isEmpty) return const SizedBox.shrink();
            return _buildAuditionStrip(cuts);
          }),
          
          Expanded(
            child: Container(
              width: double.infinity, padding: const EdgeInsets.all(15),
              decoration: BoxDecoration(color: const Color(0xFF111111), borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.white12)),
              child: SingleChildScrollView(
                child: SelectableText.rich(
                  node.ollamaResult.isEmpty 
                      ? const TextSpan(text: "Cutlist will appear here...", style: TextStyle(color: Colors.grey))
                      : parseRichText(node.ollamaResult, networkState.redleafService.apiUrl),
                  style: const TextStyle(color: Colors.white, height: 1.5, fontFamily: 'monospace'),
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(foregroundColor: Colors.white, side: const BorderSide(color: Colors.white54)),
              icon: const Icon(Icons.turn_right), label: const Text("Promote to Scratchpad"),
              onPressed: node.ollamaResult.isEmpty || networkState.isGeneratingOllama ? null : () => graphState.promoteOutputToScratchpad(node.id),
            ),
          )
        ],
      ),
    );
  }
}