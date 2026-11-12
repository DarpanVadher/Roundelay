import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import '../widgets/glass.dart';
import '../widgets/roundelay_art.dart';

import 'package:flutter/services.dart';

import '../engine/engine.dart';
import '../engine/wifi_share.dart';

class GuestScreen extends StatefulWidget {
  const GuestScreen({
    super.key,
    required this.engine,
    this.scanQr,
    this.wifiBridge,
  });
  final GuestEngine engine;

  /// Joins the hotspot named in a scanned QR (Android); tests inject a fake.
  final WifiBridge? wifiBridge;

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
  late final WifiBridge _bridge = widget.wifiBridge ?? PlatformWifiBridge();
  String? _wifiJoining, _wifiError;

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
    _bridge.leaveWifi();
    super.dispose();
  }

  bool get _busy =>
      _wifiJoining != null ||
      const {
        GuestPhase.pairing,
        GuestPhase.awaitingApproval,
        GuestPhase.connected,
      }.contains(_s.phase);

  /// Scan, then join straight away: scanning the host's code is the whole setup.
  Future<void> _scan() async {
    final link = await widget.scanQr!(context);
    if (link == null || !mounted) return;
    setState(() => _link.text = link);
    await _joinLink(link);
  }

  /// Joins the hotspot named in the link first (automatically on Android, by showing the details elsewhere), then pairs.
  Future<void> _joinLink(String link) async {
    final wifi = wifiFromLink(link);
    setState(() => _wifiError = null);
    if (wifi != null) {
      if (_bridge.canJoinWifi) {
        setState(() => _wifiJoining = wifi.ssid);
        try {
          await _bridge.joinWifi(wifi);
        } on WifiBridgeException catch (e) {
          if (mounted) {
            setState(() {
              _wifiJoining = null;
              _wifiError = e.message;
            });
          }
          return;
        }
        if (!mounted) return;
        setState(() => _wifiJoining = null);
      } else {
        final ok = await _askToJoinWifi(wifi);
        if (ok != true || !mounted) return;
      }
    }
    await widget.engine.join(stripWifi(link), delayMs: _latencyMs.round());
  }

  Future<bool?> _askToJoinWifi(WifiCredentials wifi) => showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      key: const Key('wifi-dialog'),
      title: const Text("Join the host's Wi-Fi first"),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Connect this device to the hotspot below, then continue.',
          ),
          const SizedBox(height: 12),
          _copyRow(ctx, 'Name', wifi.ssid),
          if (!wifi.isOpen) _copyRow(ctx, 'Password', wifi.password),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const Key('wifi-continue'),
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text("I'm connected"),
        ),
      ],
    ),
  );

  Widget _copyRow(BuildContext ctx, String label, String value) => Padding(
    padding: const EdgeInsets.only(bottom: 4),
    child: Row(
      children: [
        Expanded(
          child: SelectableText.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: '$label: ',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                TextSpan(text: value),
              ],
            ),
          ),
        ),
        IconButton(
          tooltip: 'Copy $label',
          icon: const Icon(Icons.copy, size: 18),
          onPressed: () => Clipboard.setData(ClipboardData(text: value)),
        ),
      ],
    ),
  );

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
          child: ListView(
            padding: centeredPadding(
              context,
              520,
              const EdgeInsets.fromLTRB(16, 16, 16, 16),
            ),
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
                      onPressed: () {
                        widget.engine.leave();
                        _bridge.leaveWifi();
                      },
                      child: const Text('Disconnect'),
                    )
                  : FilledButton(
                      key: const Key('join'),
                      onPressed: valid
                          ? () => _joinLink(_link.text.trim())
                          : null,
                      child: const Text('Join'),
                    ),
              const SizedBox(height: 24),
              if (_wifiJoining != null)
                Card(
                  key: const Key('wifi-joining'),
                  child: ListTile(
                    leading: const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    title: Text('Joining Wi-Fi "$_wifiJoining"…'),
                    subtitle: const Text('Android will ask you to confirm.'),
                  ),
                ),
              if (_wifiError != null)
                Card(
                  key: const Key('wifi-error'),
                  color: Theme.of(context).colorScheme.errorContainer,
                  child: ListTile(
                    leading: const Icon(Icons.wifi_off),
                    title: Text(_wifiError!),
                  ),
                ),
              _mixerWarning(context),
              _statusCard(context),
            ],
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
