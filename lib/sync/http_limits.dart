// Shared HTTP request limits for Dhadda's LAN servers (Phase 5).
//
// Shelf buffers request bodies unboundedly by default, so every endpoint
// that reads a body goes through [readCappedBody]: anything beyond the cap
// is rejected with HTTP 413 BEFORE the full payload sits in memory.
// The cap (8 MiB) is evidence-based, not arbitrary: bulk-300 snapshots are
// ~67 KiB and ~1.5 MiB at 5k v2 records, so legitimate histories (and large
// future growth) fit with ~5x headroom. The Node relay enforces its own
// equivalent 6 MiB cap server-side.
import 'dart:convert';

import 'package:shelf/shelf.dart';

/// 8 MiB per request body on Dart shelf servers.
const maxSyncBodyBytes = 8 << 20;

class BodyTooBig implements Exception {
  const BodyTooBig();
}

/// Reads the body up to [maxBytes]. Throws [BodyTooBig] (caller: 413) or
/// [FormatException] (caller: 400, non-UTF8 bytes).
Future<String> readCappedBody(Request req,
    {int maxBytes = maxSyncBodyBytes}) async {
  var n = 0;
  final chunks = <List<int>>[];
  await for (final c in req.read()) {
    n += c.length;
    if (n > maxBytes) throw const BodyTooBig();
    chunks.add(c);
  }
  try {
    return utf8.decode(chunks.expand((e) => e).toList());
  } catch (_) {
    throw const FormatException('bad encoding');
  }
}
