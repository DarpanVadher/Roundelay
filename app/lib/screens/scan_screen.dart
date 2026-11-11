import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../engine/engine.dart';

/// Opens the camera and returns the first valid pairing link it sees, or null if the user backs out.
/// Passed to [GuestScreen] as a function so tests (and desktop, which has no scanner) can substitute it.
Future<String?> scanPairingQr(BuildContext context) =>
    Navigator.of(context).push<String>(MaterialPageRoute(builder: (_) => const ScanScreen()));

class ScanScreen extends StatefulWidget {
  const ScanScreen({super.key});

  @override
  State<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends State<ScanScreen> {
  final _controller = MobileScannerController(formats: const [BarcodeFormat.qrCode], detectionSpeed: DetectionSpeed.noDuplicates);
  bool _done = false;
  bool _wrongCode = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_done) return;
    for (final b in capture.barcodes) {
      final v = b.rawValue;
      if (v != null && looksLikePairingLink(v)) {
        _done = true; // one result only; the camera keeps delivering frames until the route is gone
        Navigator.of(context).pop(v.trim());
        return;
      }
    }
    if (!_wrongCode) setState(() => _wrongCode = true); // a QR code, but not one of ours
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Scan the host\'s QR code'),
        actions: [
          IconButton(tooltip: 'Torch', icon: const Icon(Icons.flashlight_on_outlined), onPressed: _controller.toggleTorch),
        ],
      ),
      body: Stack(fit: StackFit.expand, children: [
        MobileScanner(
          key: const Key('scanner'),
          controller: _controller,
          onDetect: _onDetect,
          errorBuilder: (context, error) => _CameraProblem(error: error),
        ),
        Align(
          alignment: Alignment.bottomCenter,
          child: Container(
            width: double.infinity,
            color: Colors.black54,
            padding: const EdgeInsets.all(16),
            child: SafeArea(
              top: false,
              child: Text(
                _wrongCode ? "That QR code isn't from this app. Scan the code shown on the host." : 'Point the camera at the QR code on the host device.',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white),
              ),
            ),
          ),
        ),
      ]),
    );
  }
}

class _CameraProblem extends StatelessWidget {
  const _CameraProblem({required this.error});
  final MobileScannerException error;

  @override
  Widget build(BuildContext context) {
    final denied = error.errorCode == MobileScannerErrorCode.permissionDenied;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.no_photography_outlined, size: 48),
          const SizedBox(height: 12),
          Text(
            denied ? 'Camera access is needed to scan the code. Allow it in Settings, or go back and paste the link instead.' : 'The camera could not start. Go back and paste the link instead.',
            textAlign: TextAlign.center,
          ),
        ]),
      ),
    );
  }
}
