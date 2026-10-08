# Submitting Dhadda to F-Droid (step-by-step)

Everything in this file is prepared and locally verified. The steps that
remain require **your GitLab account** — I cannot fork, push, or open the
merge request for you.

Read `docs/FDROID.md` §6 first for what was verified and the known friction
points. The metadata file itself is `fdroid/com.dhadda.expense.yml`.

## Before you start

1. **Tag `v1.4.0`.** F-Droid's `UpdateCheckMode: Tags` scans your repo's tags
   to find future releases. Without a tag, automatic updates never trigger.

   ```text
   git push origin master
   git tag v1.4.0
   git push origin v1.4.0
   ```

2. **Confirm the commit hash in the metadata still points at versionCode 3.**
   `fdroid/com.dhadda.expense.yml` has `commit:` set to a full 40-character
   hash. F-Droid requires a commit hash, *not* a tag name. If you add commits
   before submitting, update that line to the commit you want built:

   ```text
   git rev-parse HEAD
   ```

## The submission

### 1. Fork and branch

- Register/log in at <https://gitlab.com>.
- Fork <https://gitlab.com/fdroid/fdroiddata>.
- Clone your fork, branch off `master`, named after the app id:

   ```text
   git clone https://gitlab.com/<you>/fdroiddata.git
   cd fdroiddata
   git checkout -b com.dhadda.expense
   ```

### 2. Add the metadata file

```text
copy C:\Users\obino\Desktop\Dhadda\fdroid\com.dhadda.expense.yml  metadata/com.dhadda.expense.yml
git add metadata/com.dhadda.expense.yml
git commit -m "Add Dhadda 1.4.0 (New App)"
git push origin com.dhadda.expense
```

### 3. Optional but recommended: test the build first

F-Droid publishes build logs at `https://f-droid.org/repo/<appid>_<vercode>.log.gz`,
but you can catch problems before submitting with `fdroidserver` locally:

```text
fdroid readmeta com.dhadda.expense     # must report no syntax errors
fdroid lint com.dhadda.expense         # must report no warnings
fdroid build -v -l com.dhadda.expense  # actually builds it
fdroid checkupdates com.dhadda.expense # fills in auto fields
fdroid rewritemeta com.dhadda.expense # normalises formatting
```

If `fdroid build` fails, the log names the exact step. The most likely
failures, in order:

- **Flutter version.** The recipe pins `flutter@stable` to tag `3.47.2`. The
  tag exists upstream; if their srclib checkout fails, that is the cause.
- **The scanner refusing committed binaries** in `assets/webapp/`. The recipe
  `scanignore`s it, but reviewers may still ask you to `rm` and rebuild it in
  `prebuild` instead.
- **Prebuild/pub-cache.** The recipe relocates `PUB_CACHE` inside the scanned
  tree so dependency licences get checked. Some environments need extra
  `flutter precache`.

### 4. Open the merge request

- Push the branch (step 2), then open an MR from your branch to
  `fdroid/fdroiddata`.
- Check the CI/CD pipeline on your fork is green.
- Fill in the MR template, mention the app is new, and note that the author
  consents to inclusion.

### 5. Wait

Packagers pick up new-app MRs from a queue. Expect questions; answer quickly.
After acceptance, the buildserver builds and publishes it — typically 24–48h.

## Afterwards

- F-Droid publishes under its own key. Your GitHub release is signed with your
  key. **A user cannot switch between the two without reinstalling.**
- When you release 1.4.1, push the tag; `fdroid checkupdates` opens an MR for
  you automatically (that is what `AutoUpdateMode: Version` +
  `UpdateCheckMode: Tags` do).