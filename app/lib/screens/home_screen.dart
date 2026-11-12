import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../main.dart';
import 'guest_screen.dart';
import 'host_screen.dart';
import 'legal_screen.dart';
import 'scan_screen.dart';
import '../widgets/glass.dart';
import '../widgets/roundelay_art.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({
    super.key,
    required this.hostFactory,
    required this.guestFactory,
    this.demoMode = false,
    this.demoReason,
    this.lanIp,
    this.scanQr,
  });
  final HostFactory hostFactory;
  final GuestFactory guestFactory;
  final bool demoMode;
  final String? demoReason; // why the real engine could not be loaded
  /// Overrides the camera scanner (tests). By default phones get the real one and desktops get none.
  final Future<String?> Function(BuildContext context)? scanQr;

  static bool get _hasCamera =>
      defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.iOS;
  final Future<String?> Function()? lanIp;

  @override
  Widget build(BuildContext context) {
    void open(Widget w) =>
        Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => w));
    return GlassBackdrop(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          title: const Text('Roundelay'),
          backgroundColor: Colors.transparent,
          scrolledUnderElevation: 0,
        ),
        body: SafeArea(
          child: Center(
            child: ListView(
              padding: centeredPadding(
                context,
                480,
                const EdgeInsets.fromLTRB(16, 16, 16, 16),
              ),
              shrinkWrap: true,
              children: [
                if (demoMode)
                  Card(
                    key: const Key('demo-banner'),
                    color: Theme.of(context).colorScheme.tertiaryContainer,
                    child: ListTile(
                      leading: const Icon(Icons.science_outlined),
                      title: const Text('Demo mode'),
                      subtitle: Text(
                        'The audio engine could not be loaded, so nothing here is real and no audio is shared.'
                        '${demoReason == null ? '' : '\n\n$demoReason'}',
                      ),
                    ),
                  ),
                // The illustration is decoration: drop it in short windows so both choices stay on screen.
                if (MediaQuery.sizeOf(context).height >= 700) ...[
                  const Center(child: RoundelayArt(size: 104)),
                  const SizedBox(height: 8),
                ],
                Text(
                  "Play one device's audio on every device nearby, in sync.",
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 24),
                Reveal(
                  delay: const Duration(milliseconds: 120),
                  child: _Choice(
                    key: const Key('choose-host'),
                    icon: Icons.cast,
                    title: "Share this device's audio",
                    subtitle: 'Show a QR code. Anything playing here is sent to the devices you approve.',
                    onTap: () => open(
                      lanIp == null
                          ? HostScreen(engine: hostFactory())
                          : HostScreen(engine: hostFactory(), lanIp: lanIp!),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Reveal(
                  delay: const Duration(milliseconds: 240),
                  child: _Choice(
                    key: const Key('choose-guest'),
                    icon: Icons.speaker_group,
                    title: 'Play audio from another device',
                    subtitle: "Join with the host's QR code or link.",
                    onTap: () => open(
                      GuestScreen(
                        engine: guestFactory(),
                        scanQr: scanQr ?? (_hasCamera ? scanPairingQr : null),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Center(
                  child: TextButton.icon(
                    key: const Key('open-legal'),
                    icon: const Icon(Icons.policy_outlined, size: 18),
                    label: const Text('Privacy & legal'),
                    onPressed: () => open(const LegalScreen()),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Choice extends StatelessWidget {
  const _Choice({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });
  final IconData icon;
  final String title, subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => GlassCard(
    onTap: onTap,
    child: ListTile(
      contentPadding: const EdgeInsets.all(16),
      leading: Icon(
        icon,
        size: 32,
        color: Theme.of(context).colorScheme.primary,
      ),
      title: Text(title),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Text(subtitle),
      ),
    ),
  );
}
