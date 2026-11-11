import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../main.dart';
import 'guest_screen.dart';
import 'host_screen.dart';
import 'scan_screen.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key, required this.hostFactory, required this.guestFactory, this.demoMode = false, this.demoReason, this.lanIp, this.scanQr});
  final HostFactory hostFactory;
  final GuestFactory guestFactory;
  final bool demoMode;
  final String? demoReason; // why the real engine could not be loaded
  /// Overrides the camera scanner (tests). By default phones get the real one and desktops get none.
  final Future<String?> Function(BuildContext context)? scanQr;

  static bool get _hasCamera => defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS;
  final Future<String?> Function()? lanIp;

  @override
  Widget build(BuildContext context) {
    void open(Widget w) => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => w));
    return Scaffold(
      appBar: AppBar(title: const Text('Roundelay')),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: ListView(
              padding: const EdgeInsets.all(16),
              shrinkWrap: true,
              children: [
                if (demoMode)
                  Card(
                    key: const Key('demo-banner'),
                    color: Theme.of(context).colorScheme.tertiaryContainer,
                    child: ListTile(
                      leading: const Icon(Icons.science_outlined),
                      title: const Text('Demo mode'),
                      subtitle: Text('The audio engine could not be loaded, so nothing here is real and no audio is shared.'
                          '${demoReason == null ? '' : '\n\n$demoReason'}'),
                    ),
                  ),
                Text("Play one device's audio on every device nearby, in sync.", style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 24),
                _Choice(
                  key: const Key('choose-host'),
                  icon: Icons.cast,
                  title: "Share this device's audio",
                  subtitle: 'Show a QR code. Anything playing here is sent to the devices you approve.',
                  onTap: () => open(lanIp == null ? HostScreen(engine: hostFactory()) : HostScreen(engine: hostFactory(), lanIp: lanIp!)),
                ),
                const SizedBox(height: 12),
                _Choice(
                  key: const Key('choose-guest'),
                  icon: Icons.speaker_group,
                  title: 'Play audio from another device',
                  subtitle: "Join with the host's QR code or link.",
                  onTap: () => open(GuestScreen(engine: guestFactory(), scanQr: scanQr ?? (_hasCamera ? scanPairingQr : null))),
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
  const _Choice({super.key, required this.icon, required this.title, required this.subtitle, required this.onTap});
  final IconData icon;
  final String title, subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Card(
        clipBehavior: Clip.antiAlias,
        child: ListTile(
          contentPadding: const EdgeInsets.all(16),
          leading: Icon(icon, size: 32),
          title: Text(title),
          subtitle: Padding(padding: const EdgeInsets.only(top: 4), child: Text(subtitle)),
          onTap: onTap,
        ),
      );
}
