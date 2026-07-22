// --- File: lib/services/media_player_service.dart ---
//
// Zero-dependency audition playback for Node Leaf.
//
// Rather than adding an audio plugin (GStreamer bindings, pubspec churn),
// this shells out to ffplay — already installed anywhere ffmpeg lives —
// with an mpv fallback. Both handle local files, Redleaf's authenticated
// Flask /serve_document stream (via the session cookie header), and remote
// web media (e.g. Archive.org links) with seek + duration clamping.
//
// Playback is strictly one-at-a-time: starting a new cut kills the old one.

import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';

class MediaPlayerService {
  MediaPlayerService._();
  static final MediaPlayerService instance = MediaPlayerService._();

  Process? _process;

  /// Identifies the currently playing cut so the UI can highlight the right
  /// button. Null when idle. Format is caller-defined (e.g. "42|00:01:23,400").
  final ValueNotifier<String?> nowPlayingKey = ValueNotifier(null);

  /// Human-readable error from the last failed attempt (e.g. "ffplay not found").
  final ValueNotifier<String?> lastError = ValueNotifier(null);

  bool get isPlaying => _process != null;

  /// Plays [url] starting at [startSeconds] for [durationSeconds].
  /// [cookie] is sent as an HTTP header for authenticated Redleaf streams
  /// (ignored for non-http sources by the players themselves).
  /// [playKey] tags this playback for UI highlighting.
  Future<void> playClip({
    required String url,
    required double startSeconds,
    required double durationSeconds,
    String cookie = "",
    String playKey = "",
  }) async {
    await stop();
    lastError.value = null;

    // Pad the tail slightly so clipped consonants at the out-point survive.
    final double dur = durationSeconds <= 0 ? 5.0 : durationSeconds + 0.25;
    final double start = startSeconds < 0 ? 0 : startSeconds;
    final bool isHttp = url.startsWith('http://') || url.startsWith('https://');

    // --- Attempt 1: ffplay ---
    final ffplayArgs = <String>[
      '-nodisp', '-autoexit', '-loglevel', 'error',
      '-ss', start.toStringAsFixed(3),
      '-t', dur.toStringAsFixed(3),
      if (isHttp && cookie.isNotEmpty) ...['-headers', 'Cookie: $cookie\r\n'],
      url,
    ];

    // --- Attempt 2: mpv ---
    final mpvArgs = <String>[
      '--no-video', '--really-quiet',
      '--start=${start.toStringAsFixed(3)}',
      '--length=${dur.toStringAsFixed(3)}',
      if (isHttp && cookie.isNotEmpty) '--http-header-fields=Cookie: $cookie',
      url,
    ];

    if (await _tryStart('ffplay', ffplayArgs, playKey)) return;
    if (await _tryStart('mpv', mpvArgs, playKey)) return;

    lastError.value =
        "No media player found. Install ffmpeg (for ffplay) or mpv to audition cuts.";
    nowPlayingKey.value = null;
  }

  Future<bool> _tryStart(String binary, List<String> args, String playKey) async {
    try {
      final proc = await Process.start(binary, args);
      _process = proc;
      nowPlayingKey.value = playKey;

      // Surface player errors (bad URL, 403 from Flask, unsupported codec).
      final errBuffer = StringBuffer();
      proc.stderr.transform(const SystemEncoding().decoder).listen(errBuffer.write);

      // Fire-and-forget cleanup when the clip finishes on its own.
      proc.exitCode.then((code) {
        if (_process == proc) {
          _process = null;
          nowPlayingKey.value = null;
          if (code != 0 && errBuffer.isNotEmpty) {
            final msg = errBuffer.toString().trim();
            lastError.value = msg.length > 200 ? msg.substring(0, 200) : msg;
            debugPrint("$binary exited ($code): $msg");
          }
        }
      });
      return true;
    } on ProcessException {
      // Binary not installed — let the caller try the next player.
      return false;
    } catch (e) {
      debugPrint("MediaPlayer start error ($binary): $e");
      return false;
    }
  }

  /// Stops playback if anything is playing. Safe to call when idle.
  Future<void> stop() async {
    final proc = _process;
    _process = null;
    nowPlayingKey.value = null;
    if (proc != null) {
      try {
        proc.kill(ProcessSignal.sigterm);
        // Give it a moment; escalate if the player hangs on a stalled stream.
        await proc.exitCode.timeout(const Duration(seconds: 2), onTimeout: () {
          proc.kill(ProcessSignal.sigkill);
          return -1;
        });
      } catch (e) {
        debugPrint("MediaPlayer stop error: $e");
      }
    }
  }
}