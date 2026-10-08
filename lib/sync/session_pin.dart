// 6-digit pairing PIN generator.
//
// Lives in its own platform-neutral module because both the dart:io server
// (wifi_host_io.dart) and the web stub (wifi_host_stub.dart) export it: the
// pairing screens need a PIN on every platform, and a web build must not lose
// the symbol just because it cannot host a socket.
import 'dart:math';

/// 6-digit numeric PIN shown next to the QR code.
///
/// CSPRNG, not a clock. The PIN is the only thing guarding a live LAN pairing
/// session (and, for a relay box, the mailbox), so a time-seeded variant was
/// predictable to anyone who knew roughly when the session started -- roughly
/// 900,000 candidates, and the clock narrows that to a small window.
String newPin() => '${100000 + Random.secure().nextInt(900000)}';