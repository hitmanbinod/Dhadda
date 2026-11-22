// Cross-language simulation entry point.
// Phase 1: the web client's real crypto module is checked against the shared
// Dart-generated vectors. Phase 2 extends this to drive the Dart test server
// with the same module (pairing, snapshot, push, events, replay rejection).
// Run: node scripts/lan-simulate.mjs
import './lan-vectors.mjs';
console.log('lan-simulate: Phase 2 will add the Dart test-server transport.');
