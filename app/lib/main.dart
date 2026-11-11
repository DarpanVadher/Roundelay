import 'package:flutter/material.dart';
import 'engine/engine.dart';
import 'engine/ffi_engine.dart';
import 'engine/mock_engine.dart';
import 'engine/native_core.dart';
import 'engine/platform_info.dart';
import 'screens/home_screen.dart';

/// Factories so the real FFI engine can replace the mocks without touching any screen.
typedef HostFactory = HostEngine Function();
typedef GuestFactory = GuestEngine Function();

void main() {
  final core = NativeCore.tryLoad();
  core?.enableTraceIfRequested();
  runApp(core == null
      // The Rust core is missing: run the UI against fake data and say so, rather than pretending to share audio.
      ? MultiPhonePlayerApp(hostFactory: MockHostEngine.new, guestFactory: MockGuestEngine.new, demoMode: true, demoReason: NativeCore.loadError)
      : MultiPhonePlayerApp(
          hostFactory: () => FfiHostEngine(core, dataDir: appDataDir()),
          guestFactory: () => FfiGuestEngine(core),
        ));
}

class MultiPhonePlayerApp extends StatelessWidget {
  const MultiPhonePlayerApp({super.key, required this.hostFactory, required this.guestFactory, this.demoMode = false, this.demoReason, this.lanIp, this.scanQr});
  final HostFactory hostFactory;
  final GuestFactory guestFactory;
  final bool demoMode;
  final String? demoReason;
  final Future<String?> Function()? lanIp; // tests inject a fixed address
  final Future<String?> Function(BuildContext context)? scanQr; // tests inject a fake camera scanner

  @override
  Widget build(BuildContext context) {
    ThemeData theme(Brightness b) => ThemeData(useMaterial3: true, colorSchemeSeed: const Color(0xFF3B5BDB), brightness: b);
    return MaterialApp(
      title: 'Roundelay',
      theme: theme(Brightness.light),
      darkTheme: theme(Brightness.dark),
      home: HomeScreen(hostFactory: hostFactory, guestFactory: guestFactory, demoMode: demoMode, demoReason: demoReason, lanIp: lanIp, scanQr: scanQr),
    );
  }
}
