# On-device checklist — cloud sync (Prompt 2)

Do these in order on your own phone. Nothing here clears app data.

1. **Back up first.** In Dhadda: Settings → Data → Backup/Export (or the Sync
   screen export) and save the JSON somewhere safe.
2. Install the new APK **over** the existing app (no uninstall, no `pm clear`).
3. Open Dhadda and confirm all entries, loans, events and categories are intact.
   Check the balance and a few recent notes.
4. Go to Settings → Data → **Web access → Create link**. The app saves a local
   pre-sync snapshot automatically before creating the vault.
5. Copy the pairing link. Treat it like a password — anyone with it can read
   your data. It is also the recovery key.
6. On the PC, open the link in a browser. Confirm the fragment disappears from
   the address bar and the app opens straight to Home.
7. Add an expense on the **phone**. It is queued immediately and pushed about
   5 s later; within about 30 s it should appear on the web (History/Recent).
   Verify the amount and category. No "Sync now" tap is needed — the app also
   pushes/pulls on resume and pulls every 60 s while in the foreground.
8. Add an expense on the **web**. Within about 5 s it should appear on the
   phone. Verify the amount and category.
9. Delete one entry on the web. Confirm it disappears on the phone after the
   next sync (tombstone propagation).
10. Put the phone in airplane mode, add an entry, then reconnect. The queued
    change stays in the outbox; on reconnect (resume) it pushes and pulls.
    Confirm the status changes to "Synced just now" and the entry appears on
    the web. Leaving the app to the background stops the 60 s timer, which
    then restarts on resume.
11. In Web access, tap **Disconnect web**. The old browser link must stop
    syncing; create a new link and reconnect to continue.
12. Tap **Delete cloud copy**. Confirm both devices keep all local data, then
    create a fresh link if you want to continue syncing.

If anything looks wrong, stop and keep the backup from step 1. Do not reinstall
without exporting first.
