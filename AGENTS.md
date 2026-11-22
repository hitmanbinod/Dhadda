# Dhadda — agent rules

> **Current branch `sync`:** Prompt 2 adds an end-to-end encrypted cloud sync
> contract. The phone is the source of a random 256-bit vault key; the key and
> bearer token travel only in the pairing-link fragment, never in requests.
> The Cloudflare Worker/D1 stores `{t,id,ua,d,iv,ct,seq}` ciphertext rows only.
> LWW is by `ua`, ties by larger `device_id`; server keeps tombstones 180 days.
> Sync code: `lib/sync/cloud_sync.dart`, `webapp/sync.js`, `sync-server/`.
> Never log tokens/keys or touch app data on a device. See `design/SYNC_PROTOCOL.md`.

> **Current branch `web-v2`:** an experimental separate lightweight web app
> lives in `web-v2/` (plain JS/CSS, generated `tokens.css`). It is a
> presentation-only prototype: do not change Android, sync/packaging or the
> real store from it. See `design/WEB_V2_REPORT.md` and `design/FEATURE_MATRIX.md`.

## Android <-> Web design parity (standing rules)

- Android leads, web follows. `design/PARITY.md` is the contract;
  `design/tokens.json` feeds the web tokens via `scripts/sync_tokens.py`.
- Any task that changes Android UI (layout, colours, text, spacing, a new
  screen, section or setting) must, in the SAME task, update the web UI,
  tokens.json (then run `python3 scripts/sync_tokens.py`) and
  `design/PARITY.md`. If the web part cannot be done now, set the row to
  "web pending" in PARITY.md with the reason.
- Never hard-code colours, radii or spacing in web components; use the CSS
  variables from `design/tokens.css` or the Flutter theme roles fed by
  `lib/theme/tokens.g.dart` (both generated from tokens.json).
- Do not add a feature to only one platform unless it is listed under
  "Intentional differences" in `design/PARITY.md`.
- Web changes are presentation only. Never touch storage keys, schema, sync
  or import/export format.
- When the user says "sync web" (or "sync web with Android"): read "Last synced
  Android commit" in PARITY.md; run
  `git log --oneline <hash>..HEAD -- <Android UI paths>` and
  `git diff <hash>..HEAD -- <Android UI paths>`; apply every UI change to the
  web; update tokens and PARITY.md; set the new "Last synced" hash; summarise
  in 10 lines or fewer.

See `design/DESIGN_SYSTEM.md` for the token/layout/component reference and
`design/reference/dhadda-mock.html` for the approved mock (read in slices).
