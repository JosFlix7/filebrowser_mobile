import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../../l10n/app_localizations.dart';
import '../api/filebrowser_client.dart';
import '../api/models.dart';
import 'error_display.dart';
import 'file_details_sheet.dart';
import 'item_actions.dart';

/// Streams an audio file from the server download endpoint. Quantum 2.0
/// answers `inline=true` with 403 for audio, so the URL must be the plain
/// download. Playback uses the same ExoPlayer stack as video (`video_player`);
/// auth travels in the `Authorization: Bearer` header.
class AudioPlayerScreen extends StatefulWidget {
  const AudioPlayerScreen({
    super.key,
    required this.url,
    required this.headers,
    required this.title,
    this.resource,
    this.client,
    this.actions,
    this.onChanged,
  });

  final Uri url;
  final Map<String, String> headers;
  final String title;
  final FbResource? resource;
  final FileBrowserClient? client;
  final ItemActions? actions;

  /// Invoked after a rename/delete here changed the server, so the browser
  /// underneath can refresh its listing.
  final VoidCallback? onChanged;

  @override
  State<AudioPlayerScreen> createState() => _AudioPlayerScreenState();
}

class _AudioPlayerScreenState extends State<AudioPlayerScreen> {
  VideoPlayerController? _audio;
  String? _error;
  bool _scrubbing = false;
  Duration _scrub = Duration.zero;
  int _shownSecond = -1;
  bool _playing = false;
  bool _buffering = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    try {
      final audio =
          VideoPlayerController.networkUrl(widget.url, httpHeaders: widget.headers);
      await audio.initialize();
      if (!mounted) {
        await audio.dispose();
        return;
      }
      audio.addListener(_onTick);
      setState(() => _audio = audio);
      await audio.play();
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  void _onTick() {
    final audio = _audio;
    if (!mounted || audio == null || _scrubbing) return;
    final value = audio.value;
    final second = value.position.inSeconds;
    if (second == _shownSecond &&
        value.isPlaying == _playing &&
        value.isBuffering == _buffering) {
      return;
    }
    setState(() {
      _shownSecond = second;
      _playing = value.isPlaying;
      _buffering = value.isBuffering;
    });
  }

  @override
  void dispose() {
    _audio?.removeListener(_onTick);
    _audio?.dispose();
    super.dispose();
  }

  void _closeAfterChange() {
    widget.onChanged?.call();
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _toggle() async {
    final audio = _audio;
    if (audio == null) return;
    if (audio.value.isPlaying) {
      await audio.pause();
    } else {
      final atEnd = audio.value.duration > Duration.zero &&
          audio.value.position >= audio.value.duration;
      if (atEnd) await audio.seekTo(Duration.zero);
      await audio.play();
    }
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(widget.title, overflow: TextOverflow.ellipsis),
        actions: [
          if (widget.resource != null && widget.client != null)
            IconButton(
              icon: const Icon(Icons.info_outline),
              tooltip: loc.actionDetails,
              onPressed: () => FileDetailsSheet.show(
                context,
                resource: widget.resource!,
                client: widget.client!,
              ),
            ),
          if (widget.resource != null && widget.actions != null)
            ItemActionsMenu(
              actions: widget.actions!,
              resource: widget.resource!,
              onRenamed: _closeAfterChange,
              onDeleted: _closeAfterChange,
            ),
        ],
      ),
      body: Center(
        child: _error != null
            ? _ErrorBody(message: loc.audioCouldNotPlay(_error!))
            : _audio == null
                ? const CircularProgressIndicator()
                : _Controls(
                    title: widget.title,
                    value: _audio!.value,
                    scrubbing: _scrubbing,
                    scrub: _scrub,
                    onScrubStart: () => setState(() => _scrubbing = true),
                    onScrub: (d) => setState(() => _scrub = d),
                    onScrubEnd: (d) async {
                      await _audio?.seekTo(d);
                      if (mounted) setState(() => _scrubbing = false);
                    },
                    onToggle: _toggle,
                  ),
      ),
    );
  }
}

class _ErrorBody extends StatelessWidget {
  const _ErrorBody({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white70)),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: () => copyErrorToClipboard(
              message,
              ScaffoldMessenger.of(context),
            ),
            icon: const Icon(Icons.copy, size: 18, color: Colors.white70),
            label: Text(loc.actionCopy,
                style: const TextStyle(color: Colors.white70)),
          ),
        ],
      ),
    );
  }
}

class _Controls extends StatelessWidget {
  const _Controls({
    required this.title,
    required this.value,
    required this.scrubbing,
    required this.scrub,
    required this.onScrubStart,
    required this.onScrub,
    required this.onScrubEnd,
    required this.onToggle,
  });

  final String title;
  final VideoPlayerValue value;
  final bool scrubbing;
  final Duration scrub;
  final VoidCallback onScrubStart;
  final ValueChanged<Duration> onScrub;
  final ValueChanged<Duration> onScrubEnd;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final duration = value.duration;
    final position = scrubbing ? scrub : value.position;
    final maxMs = duration.inMilliseconds <= 0 ? 1 : duration.inMilliseconds;
    final millis = position.inMilliseconds.clamp(0, maxMs);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.audiotrack, size: 96, color: Colors.white70),
          const SizedBox(height: 24),
          Text(title,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white, fontSize: 18)),
          const SizedBox(height: 28),
          Slider(
            value: millis.toDouble(),
            max: maxMs.toDouble(),
            onChangeStart: (_) => onScrubStart(),
            onChanged: (v) =>
                onScrub(Duration(milliseconds: v.round())),
            onChangeEnd: (v) =>
                onScrubEnd(Duration(milliseconds: v.round())),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(_clock(position),
                  style: const TextStyle(color: Colors.white70)),
              Text(_clock(duration),
                  style: const TextStyle(color: Colors.white70)),
            ],
          ),
          const SizedBox(height: 12),
          IconButton(
            iconSize: 64,
            color: Colors.white,
            onPressed: onToggle,
            icon: value.isBuffering && !value.isPlaying
                ? const SizedBox(
                    width: 48,
                    height: 48,
                    child: CircularProgressIndicator(strokeWidth: 3),
                  )
                : Icon(value.isPlaying ? Icons.pause_circle : Icons.play_circle),
          ),
        ],
      ),
    );
  }
}

String _clock(Duration d) {
  final negative = d < Duration.zero;
  final total = d.inSeconds.abs();
  final h = total ~/ 3600;
  final m = (total % 3600) ~/ 60;
  final s = (total % 60).toString().padLeft(2, '0');
  final body = h > 0 ? '$h:${m.toString().padLeft(2, '0')}:$s' : '$m:$s';
  return negative ? '-$body' : body;
}
