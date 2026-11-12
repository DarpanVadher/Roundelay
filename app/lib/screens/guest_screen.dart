import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import '../widgets/glass.dart';
import '../widgets/roundelay_art.dart';
import '../engine/engine.dart';

class GuestScreen extends StatefulWidget {
  const GuestScreen({super.key, required this.engine, this.scanQr});
  final GuestEngine engine;

  /// Camera QR scanner; null where there is none (desktop), which hides the scan button.
  final Future<String?> Function(BuildContext context)? scanQr;

  @override
  State<GuestScreen> createState() => _GuestScreenState();
}

class _GuestScreenState extends State<GuestScreen> {
  final _link = TextEditingController();
  StreamSubscription<GuestStatus>? _sub;
  GuestStatus _s = const GuestStatus();
  double _latencyMs = defaultLatencyMs.toDouble();

  @override
  void initState() {
    super.initState();
    _sub = widget.engine.status.listen((s) {
      if (mounted) setState(() => _s = s);
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    _link.dispose();
    widget.engine.leave();
    super.dispose();
  }

  bool get _busy => const {
    GuestPhase.pairing,
    GuestPhase.awaitingApproval,
    GuestPhase.connected,
  }.contains(_s.phase);

  /// Scan, then join straight away: scanning the host's code is the whole setup.
  Future<void> _scan() async {
    final link = await widget.scanQr!(context);
    if (link == null || !mounted) return;
    setState(() => _link.text = link);
    await widget.engine.join(link, delayMs: _latencyMs.round());
  }

  @override
  Widget build(BuildContext context) {
    final valid = looksLikePairingLink(_link.text);
    return GlassBackdrop(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          title: const Text('Join a device'),
          backgroundColor: Colors.transparent,
          scrolledUnderElevation: 0,
        ),
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
                children: [
                  if (MediaQuery.sizeOf(context).height >= 700) ...[
                    Center(child: RoundelayArt(size: 96, animate: _busy)),
                    const SizedBox(height: 12),
                  ],
                  if (widget.scanQr != null && !_busy) ...[
                    FilledButton.icon(
                      key: const Key('scan'),
                      icon: const Icon(Icons.qr_code_scanner),
                      label: const Text('Scan QR code'),
                      onPressed: _scan,
                    ),
                    const SizedBox(height: 16),
                    const Center(child: Text('or paste the link')),
                    const SizedBox(height: 12),
                  ],
                  TextField(
                    key: const Key('link-field'),
                    controller: _link,
                    enabled: !_busy,
                    onChanged: (_) => setState(() {}),
                    decoration: InputDecoration(
                      labelText: 'Pairing link from the host',
                      hintText: 'mpsp://pair?...',
                      border: const OutlineInputBorder(),
                      errorText: _link.text.isNotEmpty && !valid
                          ? "That doesn't look like a pairing link"
                          : null,
                    ),
                    minLines: 1,
                    maxLines: 3,
                  ),
                  if (!_busy) ...[
                    const SizedBox(height: 8),
                    Text(
                      'Latency: ${_latencyMs.round()} ms',
                      style: Theme.of(context).textTheme.labelLarge,
                    ),
                    Slider(
                      key: const Key('latency'),
                      value: _latencyMs,
                      min: 60,
                      max: 400,
                      divisions: 34,
                      label: '${_latencyMs.round()} ms',
                      onChanged: (v) => setState(() => _latencyMs = v),
                    ),
                    Text(
                      'Lower is more live but can glitch on weak Wi-Fi. Raise it if you hear dropouts.',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                  const SizedBox(height: 12),
                  _busy
                      ? OutlinedButton(
                          key: const Key('leave'),
                          onPressed: widget.engine.leave,
                          child: const Text('Disconnect'),
                        )
                      : FilledButton(
                          key: const Key('join'),
                          onPressed: valid
                              ? () => widget.engine.join(
                                  _link.text.trim(),
                                  delayMs: _latencyMs.round(),
                                )
                              : null,
                          child: const Text('Join'),
                        ),
                  const SizedBox(height: 24),
                  _mixerWarning(context),
                  _statusCard(context),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// "Playing in sync" over silence is the worst kind of failure, so when the OS mixer keeps this app from being
  /// heard, say so plainly and offer the way out. Nothing is changed for the person.
  Widget _mixerWarning(BuildContext context) {
    if (_s.phase != GuestPhase.connected || !_s.mixerSilencesApp) {
      return const SizedBox.shrink();
    }
    final muted = _s.appMuted == true;
    return Card(
      key: const Key('mixer-warning'),
      color: Theme.of(context).colorScheme.errorContainer,
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.volume_off),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    muted
                        ? 'You will hear nothing: this app is muted in Windows.'
                        : 'You will hear almost nothing: this app is turned down to ${((_s.appVolume ?? 0) * 100).round()}% in Windows.',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            const Text(
              'The audio is arriving fine. Unmute or raise this app in the Windows Volume Mixer.',
            ),
            if (Platform.isWindows) ...[
              const SizedBox(height: 12),
              FilledButton.tonal(
                key: const Key('open-mixer'),
                onPressed: _openVolumeMixer,
                child: const Text('Open volume mixer'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _openVolumeMixer() async {
    try {
      await Process.start('explorer.exe', ['ms-settings:apps-volume']);
    } on Object {
      // Settings could not be opened; the text above already says where to look.
    }
  }

  Widget _statusCard(BuildContext context) {
    if (_s.phase == GuestPhase.idle) return const SizedBox.shrink();
    final isErr = _s.phase == GuestPhase.error;
    final waiting =
        _s.phase == GuestPhase.pairing ||
        _s.phase == GuestPhase.awaitingApproval;
    final content = Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (waiting)
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else
                Icon(
                  isErr ? Icons.error_outline : Icons.check_circle_outline,
                  size: 18,
                ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _s.message,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ),
            ],
          ),
          if (_s.phase == GuestPhase.connected) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                const Icon(Icons.graphic_eq, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: LinearProgressIndicator(
                    key: const Key('level'),
                    value: _s.peak.clamp(0.0, 1.0),
                    minHeight: 8,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  _s.peak < 0.005 ? 'silent' : '${(_s.peak * 100).round()}%',
                ),
              ],
            ),
            if (_s.outputDevice != null) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  const Icon(Icons.speaker, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Playing on ${_s.outputDevice}',
                      key: const Key('output-device'),
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 8),
            Text(
              'Round trip ${((_s.rttUs ?? 0) / 1000).toStringAsFixed(1)} ms  -  buffer ${((_s.fillFrames ?? 0) / 48).round()} ms  -  '
              'clock drift ${(_s.driftPpm ?? 0).round()} ppm  -  dropouts ${_s.underruns}\n'
              'late packets ${_s.latePackets}  -  lost ${_s.lostPackets}  -  worst lateness ${_s.maxLateMs.toStringAsFixed(0)} ms',
            ),
          ],
        ],
      ),
    );
    return AnimatedSize(
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOutCubic,
      alignment: Alignment.topCenter,
      child: isErr
          ? Card(
              key: const Key('status'),
              color: Theme.of(context).colorScheme.errorContainer,
              child: content,
            )
          : GlassCard(key: const Key('status'), child: content),
    );
  }
}
