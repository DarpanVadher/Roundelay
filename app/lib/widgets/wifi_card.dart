import 'package:flutter/material.dart';

import '../engine/platform_info.dart';
import '../engine/wifi_share.dart';
import 'glass.dart';

/// Runs [start] (which brings the hotspot up) and returns the address the hotspot added, or null if none appeared.
typedef HotspotIpFinder = Future<String?> Function(
  Future<void> Function() start,
);

Future<String?> defaultHotspotIp(Future<void> Function() start) async {
  final before = await allIpv4();
  await start();
  return findNewLanIp(before);
}

/// Host-side control for "put the hotspot's Wi-Fi in the QR": a switch, name and password fields (remembered on this
/// device) and, on Android, a button that starts an app-owned hotspot and fills them in.
class HostWifiCard extends StatefulWidget {
  const HostWifiCard({
    super.key,
    required this.bridge,
    required this.store,
    required this.onChanged,
    this.findHotspotIp = defaultHotspotIp,
  });
  final WifiBridge bridge;
  final WifiStore store;
  final HotspotIpFinder findHotspotIp;

  /// Called with the Wi-Fi to put in the QR (null when off or empty) and the address guests should dial when it is
  /// a hotspot on another interface (null to keep the engine's own address).
  final void Function(WifiCredentials? wifi, String? hostIp) onChanged;

  @override
  State<HostWifiCard> createState() => _HostWifiCardState();
}

class _HostWifiCardState extends State<HostWifiCard> {
  final _ssid = TextEditingController();
  final _pass = TextEditingController();
  bool _include = false, _hidePass = true, _busy = false, _local = false;
  String? _error, _hostIp;

  @override
  void initState() {
    super.initState();
    widget.store.load().then((v) {
      if (!mounted || _local) return;
      setState(() {
        _include = v.include;
        _ssid.text = v.wifi?.ssid ?? '';
        _pass.text = v.wifi?.password ?? '';
      });
      _notify(save: false);
    });
  }

  @override
  void dispose() {
    if (_local) widget.bridge.stopHotspot();
    _ssid.dispose();
    _pass.dispose();
    super.dispose();
  }

  WifiCredentials? get _current => _include && _ssid.text.trim().isNotEmpty
      ? WifiCredentials(
          ssid: _ssid.text.trim(),
          password: _pass.text,
          local: _local,
        )
      : null;

  void _notify({bool save = true}) {
    widget.onChanged(_current, _local ? _hostIp : null);
    // Names and passwords of a hotspot we started ourselves change every time, so only typed ones are remembered.
    if (save && !_local) {
      widget.store.save(
        wifi: _ssid.text.trim().isEmpty
            ? null
            : WifiCredentials(ssid: _ssid.text.trim(), password: _pass.text),
        include: _include,
      );
    }
  }

  Future<void> _toggleHotspot() async {
    if (_local) {
      await widget.bridge.stopHotspot();
      setState(() {
        _local = false;
        _hostIp = null;
        _ssid.clear();
        _pass.clear();
      });
      final v = await widget.store.load();
      if (!mounted) return;
      setState(() {
        _ssid.text = v.wifi?.ssid ?? '';
        _pass.text = v.wifi?.password ?? '';
      });
      _notify(save: false);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      late WifiCredentials c;
      final ip = await widget.findHotspotIp(
        () async => c = await widget.bridge.startHotspot(),
      );
      if (!mounted) return;
      setState(() {
        _local = true;
        _include = true;
        _hostIp = ip;
        _ssid.text = c.ssid;
        _pass.text = c.password;
        if (ip == null) _error = 'The hotspot started but its address could not be found. Guests may not be able to connect.';
      });
      _notify(save: false);
    } on WifiBridgeException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    return GlassCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.wifi_tethering, color: scheme.primary),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Include hotspot Wi-Fi in the QR',
                  style: text.titleSmall,
                ),
              ),
              Switch(
                key: const Key('wifi-switch'),
                value: _include,
                onChanged: (v) {
                  setState(() => _include = v);
                  _notify();
                },
              ),
            ],
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            alignment: Alignment.topCenter,
            child: !_include
                ? Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      'Guests scan once to join your hotspot and pair.',
                      style: text.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 12),
                      TextField(
                        key: const Key('wifi-ssid'),
                        controller: _ssid,
                        enabled: !_local,
                        decoration: const InputDecoration(
                          labelText: 'Wi-Fi name',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                        onChanged: (_) {
                          setState(() {});
                          _notify();
                        },
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        key: const Key('wifi-password'),
                        controller: _pass,
                        enabled: !_local,
                        obscureText: _hidePass,
                        decoration: InputDecoration(
                          labelText: 'Password (empty for an open network)',
                          border: const OutlineInputBorder(),
                          isDense: true,
                          suffixIcon: IconButton(
                            tooltip: _hidePass
                                ? 'Show password'
                                : 'Hide password',
                            icon: Icon(
                              _hidePass
                                  ? Icons.visibility
                                  : Icons.visibility_off,
                            ),
                            onPressed: () =>
                                setState(() => _hidePass = !_hidePass),
                          ),
                        ),
                        onChanged: (_) {
                          setState(() {});
                          _notify();
                        },
                      ),
                      if (widget.bridge.canStartHotspot) ...[
                        const SizedBox(height: 10),
                        OutlinedButton.icon(
                          key: const Key('start-hotspot'),
                          icon: _busy
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : Icon(
                                  _local
                                      ? Icons.stop_circle_outlined
                                      : Icons.wifi_tethering,
                                ),
                          label: Text(
                            _local
                                ? 'Stop app hotspot'
                                : 'Create a hotspot for me',
                          ),
                          onPressed: _busy ? null : _toggleHotspot,
                        ),
                      ],
                      const SizedBox(height: 8),
                      Text(
                        _local
                            ? 'This hotspot lives only while this screen is open. Guests have no internet through it.'
                            : 'Type the name and password of the hotspot you turned on. They are saved on this device only.',
                        style: text.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Anyone who can see this QR can read the Wi-Fi password in it.',
                        key: const Key('wifi-warning'),
                        style: text.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                _error!,
                style: text.bodySmall?.copyWith(color: scheme.error),
              ),
            ),
        ],
      ),
    );
  }
}
