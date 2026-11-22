# Vendored crypto for Dhadda LAN mode

The browser page is served over plain HTTP on a LAN address, so it is **not a
secure context** and `crypto.subtle` is unavailable. These audited, MIT-licensed
libraries are vendored instead. No CDN and no npm at runtime.

## What is here

| File | Purpose |
| --- | --- |
| `noble-1.x-min.js` | ES module exporting `x25519`, `sha256`, `hmac`, `hkdf`, `pbkdf2`, `chacha20poly1305`. Tree-shaken + minified from the official ESM builds. 48,918 bytes raw, **20,269 bytes gzip** (level 9). |
| `LICENSE-curves.txt` | MIT licence, `@noble/curves` |
| `LICENSE-hashes.txt` | MIT licence, `@noble/hashes` |
| `LICENSE-ciphers.txt` | MIT licence, `@noble/ciphers` |
| `qrcode-min.js` | MIT `qrcode-generator` 2.0.4, tree-shaken ESM build (20,887 bytes raw, 7,621 gzip). Renders the computer's pairing QR. |

Versions and upstream tarball SHA-256 (npm registry, fetched 2026-11-22):

| Package | Version | Tarball SHA-256 |
| --- | --- | --- |
| `@noble/curves` | 1.9.7 | `c4c5545645b8d58a080d2faf84982f6fe5dc3a0516e11de8dc571b38cab565e9` |
| `@noble/hashes` | 1.8.0 | `e8a765d92c04faaccba8776411c5038cb195f812ee629fce07e1d2e6aec80ea0` |
| `@noble/ciphers` | 1.3.0 | `e02e7c03c26b8dd88ab0bd5e46f2996689e33f252bacb551a1cf504bc912501f` |

Bundle SHA-256: `3e34841dd0fbd9375481796313c10f91e0b304739a20d914c83b86261690dd7d`.

`qrcode-generator` 2.0.4 tarball SHA-256:
`02e2e18a99a90b02dad940851f59b7c3c5fd1ab79cbdece8595cb06328878159`;
bundle SHA-256: `ae8ab65ebf38e38464c9b4b3287cb246c59796ab3191468772066afbdb446f25`.

## Why a bundle instead of the raw ESM files

The published ESM trees are 64.5 KB gzipped with the needed import closure and
miss the 25 KB budget; importing `@noble/curves/ed25519.js` alone drags in
Edwards, FROST and OPRF code that X25519 never uses. The file here is the same
audited source, built with the official ESM entry points and tree-shaken with
esbuild 0.25.10 (`--bundle --format=esm --minify --target=es2022`). No source
was edited by hand.

Reproduction (needs npm/esbuild only at build time, never at runtime):

```sh
npm pack @noble/curves@1.9.7 @noble/hashes@1.8.0 @noble/ciphers@1.3.0
# extract each into node_modules/@noble/{curves,hashes,ciphers}
esbuild entry.mjs --bundle --format=esm --minify --target=es2022 \
  --outfile=webapp/vendor/noble-1.x-min.js
```

where `entry.mjs` re-exports exactly the six symbols above from
`@noble/curves/ed25519.js`, `@noble/hashes/{sha256,hkdf,hmac,pbkdf2}.js` and
`@noble/ciphers/chacha.js`.

## Interop

Every primitive is also implemented with Dart's `cryptography` package in
`lib/sync/lan_crypto.dart`. `design/test-vectors/lan.json` holds shared
known-answer vectors; `test/lan_crypto_test.dart` and
`scripts/lan-vectors.mjs` both reproduce them.
