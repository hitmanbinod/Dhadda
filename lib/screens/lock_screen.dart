import 'package:flutter/material.dart';

import '../security.dart';

/// 4-digit PIN gate. Auto-verifies the moment the 4th digit lands -
/// no Unlock button to hunt for.
class LockScreen extends StatefulWidget {
  final PinVault vault;
  final VoidCallback onUnlock;
  const LockScreen(
      {super.key, required this.vault, required this.onUnlock});

  @override
  State<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends State<LockScreen> {
  String _pin = '';
  String? _error;
  bool _checking = false;

  void _press(String d) {
    if (_checking || _pin.length >= 4) return;
    setState(() {
      _pin += d;
      _error = null;
    });
    if (_pin.length == 4) _tryUnlock();
  }

  void _back() {
    if (_checking || _pin.isEmpty) return;
    setState(() {
      _pin = _pin.substring(0, _pin.length - 1);
      _error = null;
    });
  }

  Future<void> _tryUnlock() async {
    setState(() => _checking = true);
    // Let the 4th dot paint before verifying.
    await Future<void>.delayed(const Duration(milliseconds: 150));
    final ok = widget.vault.verify(_pin);
    if (!mounted) return;
    if (ok) {
      widget.onUnlock();
      return;
    }
    setState(() {
      _checking = false;
      _error = 'Wrong PIN - try again';
      _pin = '';
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 300),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircleAvatar(
              radius: 34,
              backgroundColor:
                  scheme.primaryContainer.withValues(alpha: 0.5),
              child: Icon(Icons.lock,
                  size: 32, color: scheme.primary),
            ),
            const SizedBox(height: 16),
            Text('Enter your 4-digit PIN',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (var i = 0; i < 4; i++)
                  AnimatedContainer(
                    duration:
                        const Duration(milliseconds: 120),
                    margin: const EdgeInsets.symmetric(
                        horizontal: 10),
                    width: 18,
                    height: 18,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: i < _pin.length
                          ? scheme.primary
                          : scheme.surfaceContainerHighest,
                      border: Border.all(
                          color: scheme.primary, width: 1.5),
                    ),
                  ),
              ],
            ),
            SizedBox(
              height: 32,
              child: _error == null
                  ? null
                  : Center(
                      child: Text(_error!,
                          style: TextStyle(
                              color: scheme.error,
                              fontWeight: FontWeight.bold)),
                    ),
            ),
            for (final row in const [
              ['1', '2', '3'],
              ['4', '5', '6'],
              ['7', '8', '9'],
            ])
              Padding(
                padding:
                    const EdgeInsets.symmetric(vertical: 5),
                child: Row(
                  mainAxisAlignment:
                      MainAxisAlignment.spaceEvenly,
                  children: [
                    for (final d in row) _key(context, d),
                  ],
                ),
              ),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 5),
              child: Row(
                mainAxisAlignment:
                    MainAxisAlignment.spaceEvenly,
                children: [
                  const SizedBox(width: 72),
                  _key(context, '0'),
                  SizedBox(
                    width: 72,
                    child: IconButton(
                      onPressed: _back,
                      icon: const Icon(Icons.backspace_outlined),
                    ),
                  ),
                ],
              ),
            ),
            if (_checking)
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                        strokeWidth: 2)),
              ),
          ],
        ),
      ),
    );
  }

  Widget _key(BuildContext context, String d) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      width: 72,
      height: 64,
      child: OutlinedButton(
        onPressed: _checking ? null : () => _press(d),
        style: OutlinedButton.styleFrom(
          shape: const CircleBorder(),
          side: BorderSide(color: scheme.outlineVariant),
        ),
        child: Text(d,
            style: const TextStyle(
                fontSize: 24, fontWeight: FontWeight.w500)),
      ),
    );
  }
}