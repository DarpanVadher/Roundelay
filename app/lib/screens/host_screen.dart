import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../engine/engine.dart';
import '../engine/platform_info.dart';

class HostScreen extends StatefulWidget {
  const HostScreen({super.key, required this.engine, this.lanIp = findLanIp});
  final HostEngine engine;
  /// Address other devices use to reach this one; null means there is no usable network.
  final Future<String?> Function() lanIp;

  @override
  State<HostScreen> createState() => _HostScreenState();
}

class _HostScreenState extends State<HostScreen> {
  StreamSubscription<HostEvent>? _sub;
  String? _link, _error;
  JoinRequest? _pending;
  List<ConnectedGuest> _guests = const [];

  @override
  void initState() {
    super.initState();
    _sub = widget.engine.events.listen((e) {
      if (!mounted) return;
      setState(() {
        switch (e) {
          case PairingLinkReady(:final link):
            _link = link;
          case JoinRequested(:final request):
            _pending = request;
          case GuestsChanged(:final guests):
            _guests = guests;
          case HostError(:final message):
            _error = message;
        }
      });
    });
    _startEngine();
  }

  Future<void> _startEngine() async {
    try {
      final ip = await widget.lanIp();
      if (!mounted) return;
      if (ip == null) {
        setState(() => _error = 'Not connected to a network. Join Wi-Fi or turn on a hotspot, then try again.');
        return;
      }
      await widget.engine.start(lanIp: ip);
    } on Object catch (e) {
      if (mounted) setState(() => _error = '${e is Exception ? e.toString().replaceFirst('Exception: ', '') : e}');
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    widget.engine.stop();
    super.dispose();
  }

  void _answer(bool allow) {
    final r = _pending!;
    // The old QR is single-use; the engine issues a new one right after this answer.
    setState(() {
      _pending = null;
      _link = null;
    });
    widget.engine.respond(r.id, allow: allow);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Sharing audio')),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: ListView(padding: const EdgeInsets.all(16), children: [
              if (_error != null)
                Card(color: scheme.errorContainer, child: ListTile(leading: const Icon(Icons.error_outline), title: Text(_error!))),
              if (_pending != null) _joinRequestCard(context),
              Text('Add a device', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 12),
              Center(
                child: _link == null
                    ? const SizedBox(height: 220, child: Center(child: CircularProgressIndicator()))
                    : Container(
                        padding: const EdgeInsets.all(12),
                        color: Colors.white, // QR needs a light quiet zone in dark mode
                        child: QrImageView(key: const Key('pairing-qr'), data: _link!, size: 220),
                      ),
              ),
              const SizedBox(height: 8),
              if (_link != null)
                TextButton.icon(
                  key: const Key('copy-link'),
                  icon: const Icon(Icons.copy, size: 18),
                  label: const Text('Copy link instead'),
                  onPressed: () => Clipboard.setData(ClipboardData(text: _link!)),
                ),
              if (defaultTargetPlatform == TargetPlatform.android)
                const Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: Text(
                    'Start music in any app. Apps that block audio capture (some streaming services) cannot be shared.',
                    textAlign: TextAlign.center,
                  ),
                ),
              const Divider(height: 32),
              Text('Connected devices (${_guests.length})', style: Theme.of(context).textTheme.titleMedium),
              if (_guests.isEmpty)
                const Padding(padding: EdgeInsets.symmetric(vertical: 12), child: Text('None yet. Scan the code on another device.')),
              for (final g in _guests)
                ListTile(
                  key: Key('guest-${g.id}'),
                  leading: const Icon(Icons.speaker),
                  title: Text(g.name),
                  subtitle: Text(g.rttUs == null ? 'Connected' : 'In sync - ${(g.rttUs! / 1000).toStringAsFixed(1)} ms round trip'),
                  trailing: IconButton(tooltip: 'Disconnect', icon: const Icon(Icons.close), onPressed: () => widget.engine.kick(g.id)),
                ),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _joinRequestCard(BuildContext context) => Card(
        key: const Key('join-request'),
        color: Theme.of(context).colorScheme.primaryContainer,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('"${_pending!.name}" wants to join', style: Theme.of(context).textTheme.titleMedium),
            Text(_pending!.address),
            const SizedBox(height: 12),
            Row(children: [
              FilledButton(key: const Key('allow'), onPressed: () => _answer(true), child: const Text('Allow')),
              const SizedBox(width: 8),
              OutlinedButton(key: const Key('deny'), onPressed: () => _answer(false), child: const Text('Deny')),
            ]),
          ]),
        ),
      );
}
