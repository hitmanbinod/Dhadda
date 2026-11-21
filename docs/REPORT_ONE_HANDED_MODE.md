# Report — One-handed mode implementation (Dhadda)

Prepared 2026-11-21 for external review. Source of truth: the code on branch
`round2`, HEAD `484ee77`. Everything below is traceable to a file/line or a
named commit. Tests were run locally; on-device behaviour was **not** verified
(the phone was offline for most of this work).

> **Update (2026-11-21, `web-parity`):** this is a historical snapshot of the
> original `round2` implementation. Current behaviour differs in three ways:
> one-handed mode is **off by default** (an explicit `one_handed_choice_v1`
> value is still honoured), `oneHandedBottomPadding` adds only a small gap
> because the Scaffold body already ends at the bottom nav, and the AI-ish
> title subtitles were removed. See `docs/DESIGN_STATUS.md` §4.

---

## 1. What was asked

Across several messages the maintainer asked for, in essence:

1. A one-handed mode that moves the top UI slightly down by default, "similar
   to One UI on Samsung", for single-hand reach.
2. The different tab bars (segmented controls) moved all the way to the
   bottom, just above the bottom navigation bar.
3. The Home profile/avatar/username row lowered slightly, with a subtle
   blurred bar appearing on scroll.
4. Related gesture polish: remove swipe-to-change-tab, keep date swiping but
   make it smooth, stop the receipt camera button from launching the camera
   (later clarified: the button must stay, it was just not working).

This report covers only the one-handed-mode/layout work. The camera fix, web
bundle rebuild and Round 3.1 features are separate.

---

## 2. Commit history (relevant)

| Commit | What it did |
|---|---|
| `2ed8d92` | Introduced `one_handed_mode` (off by default), moved History/Insights/Lent toggles to the bottom, added root-shell tab swiping, animated Home month paging, lowered Add account picker. |
| `18bbf99` | Made one-handed mode on by default with a one-time migration; removed tab swiping; improved month animation; moved bottom bars to use the real nav-bar height; Home magnitude-only balance colours; Home Events on by default. |
| `c8616a8` | Lowered the Home profile row; added the blurred sticky bar on scroll; avatar styles; night greeting. |
| `484ee77` | Fixed a Lent summary-row overflow that only appeared at narrow (web) widths. |

---

## 3. Current design / implementation

### 3.1 State and persistence

`lib/store.dart`:

- `bool oneHanded = true;` (line 89) — on by default.
- `bool _oneHandedChosen = false;` (line 92) — private migration guard.
- `load()` (lines 572–576) reads `one_handed_choice_v1` from
  `expense_meta_v1`. When the explicit-choice key is absent, `oneHanded` is
  forced to `true` regardless of the legacy `one_handed_mode` value. This is a
  one-time migration of old installs that had the feature off by default.
- `_saveAll()` (lines 700–701) persists both `one_handed_mode` and
  `one_handed_choice_v1`.
- `setOneHanded(bool)` (lines ~866–871) sets `_oneHandedChosen = true`, stores
  the value, saves and notifies listeners.

The pref is per-device and additive — it never enters any Snapshot/sync
payload.

### 3.2 Settings entry

`lib/screens/menu_screen.dart:287–294` — `settings-one-handed` switch,
icon `Icons.front_hand_outlined`, title "One-handed mode", subtitle "Moves the
top tabs and toggles to the bottom."

### 3.3 Shared geometry helper

`lib/widgets/page.dart`:

- `kNavBarHeight = 80`, `kAddPillHeight = 50` (lines 11–12).
- `tabScrollBottomPadding(context)` (17–21): scroll tail that clears the
  NavigationBar + system bottom inset + the floating Add pill. Used by Home
  and by the scrolling bodies of the other tabs.
- `oneHandedBottomPadding(context)` (26–30): bottom inset for controls pinned
  above the NavigationBar: `kNavBarHeight + MediaQuery.paddingOf(context).bottom
  + Spacing.xs` on phones; only `Spacing.sm` on wide layouts (rail mode has no
  bottom bar).

### 3.4 Per-screen placement

| Screen | Normal mode | One-handed mode | File |
|---|---|---|---|
| History | `_segmented()` directly under the title (line 187) | pinned at the bottom of the Column with `EdgeInsets.only(top: Spacing.sm, bottom: oneHandedBottomPadding(context))` (lines 201–208) | `lib/screens/history_screen.dart` |
| Insights | `_periodTabs(colors)` in the header sliver (line 85) | last sliver, `SliverPadding(... bottom: oneHandedBottomPadding(context))` (lines 180–189) | `lib/screens/insights_screen.dart` |
| Lent | `_toggles(colors, hPad)` under the summary card (line 116) | pinned at the bottom of the Column with `EdgeInsets.fromLTRB(hPad, Spacing.sm, hPad, oneHandedBottomPadding(context))` (lines 144–153) | `lib/screens/lent_screen.dart` |

The floating Add pill remains only on Home, which is why the pinned bars use
the smaller inset and can sit just above the navigation bar.

### 3.5 Home top area

`lib/screens/home_screen.dart`:

- The header `SliverPadding` uses top `Spacing.lg` (24 dp) instead of
  `Spacing.sm` (8 dp) — "slightly lower by default".
- A `NotificationListener<ScrollNotification>` sets `_showTopBar` when
  `pixels > 120`.
- A compact profile bar (`_stickyTopBar`, avatar + name + sync icon) is
  mounted only while `_showTopBar` is true via an `AnimatedSwitcher`, using
  `BackdropFilter(ImageFilter.blur(14,14))` over `colors.card` at alpha 0.78 —
  the subtle blurred bar on scroll.
- Because it is mounted only while needed, its name/sync button never
  duplicate the full header's widgets (this was a bug fixed after first
  implementation, see tests below).

### 3.6 Gesture changes tied to this work

- Root-shell horizontal tab swiping was **removed** in `18bbf99`
  (`lib/main.dart`): the `GestureDetector` wrapper around `IndexedStack` and
  its drag handlers were deleted. Tab switching is via `NavigationBar` /
  `NavigationRail` only.
- Home month paging uses a direction-aware `AnimatedSwitcher` (slide +
  scale + fade, 300 ms, eased in/out, reduced-motion aware). Only the date
  text opens the calendar picker.

---

## 4. Tests

`test/one_handed_test.dart` (6 tests):

- default-on and explicit-choice persistence;
- one-time migration of a legacy stored `false`;
- History tabs Y > 500 in one-handed vs < 200 in normal at 420×1200;
- Insights period bar Y > title Y;
- Lent toggles Y > title Y and no layout exception.

`test/home_redesign_test.dart`, `test/home_customize_test.dart`,
`test/step5_restyle_test.dart` cover the sticky bar, avatar styles and narrow
Lent layout. `test/navigation_redesign_test.dart` covers the 4-tab shell.

Baseline after all changes: `flutter analyze --no-fatal-infos` clean,
`flutter test` **356/356 passing**.

---

## 5. Known issues / things to review

1. **Pinned bars and scroll clearance are independent.** `oneHandedBottomPadding`
   is used for the pinned controls while `tabScrollBottomPadding` is used for
   the scrollable list tail. They share `kNavBarHeight + system inset` but not
   the Add-pill term. That is intentional (only Home has the pill), but it is
   a coupling point worth checking if the pill ever moves.
2. **Wide layout (>900 dp)** uses a NavigationRail, so one-handed mode still
   moves the toggles to the bottom but with only `Spacing.sm` inset — there is
   no bottom navigation bar to clear. Review whether the bottom placement is
   actually desirable on desktop.
3. **`_showTopBar` threshold is a hard-coded 120 px.** With different text
   scales the full header height changes; the blur bar may appear slightly
   early or late.
4. **One-time migration guard** relies on the presence of `one_handed_choice_v1`.
   A user who toggles the switch off, then clears app data except that key,
   could see surprising state; low risk but worth noting.
5. **Not verified on device:** actual thumb reach, blur rendering/performance,
   gesture-conflict behaviour with `Slidable` rows, and system gesture inset
   on the physical phone. All of those are automated-widget-test or code
   evidence only.
6. The narrow-web Lent overflow fixed in `484ee77` was caused by this work's
   button-constraining change; the regression test uses 320 dp, but the
   original failure appeared in a real Edge window whose exact width was not
   recorded.

---

## 6. Summary

One-handed mode is a persisted, per-device boolean that is now on by default,
moves the History/Insights/Lent segmented controls from the header to just
above the bottom navigation bar, and lowers the Home header with a blurred
compact bar on scroll. The change set is additive: no schema, sync, snapshot,
security or signing surfaces were touched. Automated coverage is good;
physical-device ergonomics remain unverified.
