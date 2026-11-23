# On-device checklist — phone-hosted LAN sync (Prompt 3)

Use the `.dev` debug build only. Phone and computer must be on the same
**home/hotspot** Wi-Fi (not guest/hotel, not AP-isolated). Keep Dhadda open and
awake on the phone. The computer page must be opened at
`http://<phone-wifi-ip>:8765` — do **not** use `localhost` for the final test.

| # | Step | What to expect |
| --- | --- | --- |
| 1 | Open Home → Sync icon (or Settings → Data → Use on computer) | Title "Use on computer", one Start button, the "same Wi-Fi / hotspot" line. If there is no Wi-Fi address: "Connect to Wi-Fi first". |
| 2 | Tap **Start** | Status chip "Ready · wlan0"; a large address; three numbered cards; a code with a countdown; a Stop button. |
| 3 | On the computer open the shown `http://<phone-ip>:8765` | "Dhadda on your computer", three steps, "Enter code" / "Scan with phone" tabs, trust checkbox. |
| 4 | Tap **Copy** / **Share** on the phone; paste into the address bar | Same page loads. (Share sheet works.) |
| 5 | Tap **New code** on the phone | Code changes; countdown restarts at 120. Old code no longer works. |
| 6 | Enter the code on the computer with hyphens/lowercase, tick trust, **Connect** | Phone shows "Allow Chrome on Windows (192.168.x.x)? Trusted for 30 days" with Allow / Deny. |
| 7 | Tap **Deny** once, then pair again and tap **Allow** | Deny shows a clear refusal; Allow connects to Home with the sidebar "Live". |
| 8 | Type five wrong codes | Each shows attempts left; the sixth says too many attempts; the phone says the code is dead. Get a new code. |
| 9 | Let a code expire (>120 s), then try it | "That code expired. Ask your phone for a new one." |
| 10 | Add an expense on the phone | Appears on the computer in under a second. |
| 11 | Add / edit / delete on the computer | Appears on the phone in under a second; totals recompute. |
| 12 | Scan the computer's QR | On the computer choose "Scan with phone" → "Show pairing QR"; on the phone tap "Scan computer's QR". Pairing completes without a second Allow. |
| 13 | Close the browser tab, reopen the address | Trusted computer reconnects silently. Untyped/untrusted needs a new code. |
| 14 | Settings on the computer → **Forget this computer** | Next visit asks for a code again. |
| 15 | On the phone's connected list: Disconnect / Forget / Forget all | Live dot goes away; trust rows disappear; reconnect fails with "pair again". |
| 16 | Turn the phone screen off for 5 minutes (after Phase 7) | Foreground service notification stays; computer keeps working or reconnects within 5 s. Without Phase 7, expect a drop — this is the known limit. |
| 17 | Toggle Wi-Fi off and on | If the phone IP changes, the old address stops working; the phone shows the new address and the computer must pair again. |
| 18 | Tap **Stop** on the phone | Server stops; computer shows "Phone not reachable"; no socket/wake lock remains. |

## Verification run — 2026-11-23 (dev APK, `4750a3bc`)

PASS: Home → Sync → Start; address shown as `http://192.168.1.64:8765`;
foreground service running; page loads over the real LAN IP (not localhost).
Pairing page renders with no console errors; code + trust connected; phone
approval gate; trusted reconnect after app restart; Home renders with the
phone's data; web → phone and phone → web edits both arrive live; test entries
removed again; Stop/CSP/Host checks covered by `flutter test` (391/391) and
`node scripts/lan-simulate.mjs`.

Not re-checked: screen-off survival with the foreground service, AP-isolation,
QR pairing on the phone camera (the code path is covered by Dart/JS tests).

Record PASS/FAIL and any wording that felt unclear. Do not install or touch
`com.dhadda.expense` (the real app).
