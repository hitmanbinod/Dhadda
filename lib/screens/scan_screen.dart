import 'package:flutter/material.dart';
import 'package:flutter_zxing/flutter_zxing.dart';

import '../sync/permissions.dart';
import '../sync/relay_client.dart';
import '../sync/wifi_client.dart';

/// Camera QR scanner for sync codes (ZXing: fully open-source,
/// F-Droid compatible). Shows feedback for ANY detected code so a
/// mis-aim is visible instead of mysterious.
class ScanScreen extends StatefulWidget {
  const ScanScreen({super.key});

  @override
  State<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends State<ScanScreen> {
  final _manual = TextEditingController();
  bool _done = false;
  bool _cameraOk = false;
  String? _lastOther;

  @override
  void initState() {
    super.initState();
    _initCamera();
  }

  Future<void> _initCamera() async {
    final ok = await Permissions.ensureCamera();
    if (mounted) setState(() => _cameraOk = ok);
  }

  @override
  void dispose() {
    _manual.dispose();
    super.dispose();
  }

  void _got(String? raw) {
    if (_done || raw == null || raw.isEmpty) return;
    if (WifiClient.parseQrPayload(raw) != null ||
        QrV2.parse(raw) != null) {
      _done = true;
      if (mounted) Navigator.of(context).pop(raw);
      return;
    }
    final short =
        raw.length > 90 ? '${raw.substring(0, 90)}...' : raw;
    if (short != _lastOther && mounted) {
      setState(() => _lastOther = short);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Scan sync code')),
      body: Column(
        children: [
          Expanded(
            flex: 3,
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (_cameraOk)
                  ReaderWidget(
                    codeFormat: Format.qrCode,
                    showScannerOverlay: true,
                    showFlashlight: true,
                    showGallery: false,
                    showToggleCamera: false,
                    scanDelay:
                        const Duration(milliseconds: 300),
                    onScan: (code) => _got(code.text),
                  )
                else
                  const Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CircularProgressIndicator(
                            color: Colors.white),
                        SizedBox(height: 8),
                        Text('Starting camera…',
                            style:
                                TextStyle(color: Colors.white)),
                      ],
                    ),
                  ),
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 12,
                  child: Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.black54,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        _lastOther == null
                            ? 'Hold the QR inside the frame'
                            : 'Not a sync code:\n$_lastOther',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                            color: Colors.white, fontSize: 12),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            flex: 2,
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  const Text(
                      'Camera not finding it? Paste the code text shown under the QR instead:'),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _manual,
                    decoration: const InputDecoration(
                      labelText: 'EXPENSESYNC2::http://...::...::...',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 8),
                  FilledButton(
                    onPressed: () {
                      final t = _manual.text.trim();
                      if (WifiClient.parseQrPayload(t) == null &&
                          QrV2.parse(t) == null) {
                        ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                                content: Text(
                                    'That does not look like a sync code.')));
                        return;
                      }
                      _done = true;
                      Navigator.of(context).pop(t);
                    },
                    child: const Text('Use this code'),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}