# FEATURE_MATRIX.md — Dhadda web-v2 parity inventory

Generated in Phase 0 of the `web-v2` task by reading the Android/Flutter
sources (`lib/screens/*`, `lib/widgets/*`, `lib/store.dart`, `lib/models.dart`,
`lib/theme/*`). Android leads; this matrix is the checklist for what the web
must show. Decisions: ✅ include, 🚫 device-only (hide on web), ➖ later.

Counts are summarised at the bottom.

## Shell & navigation

| Android screen | Element / setting | Web decision | Web location |
|---|---|---|---|
| `lib/main.dart` | 4 tabs Home / History / Insights / Lent | ✅ | Sidebar ≥900 px, bottom tab bar <900 px |
| `lib/main.dart` | Settings pushed from avatar | ✅ | Content area with back link; avatar only in sidebar footer |
| `lib/main.dart` | Month paging (`[` `]`, swipe) | ✅ | Arrows beside month title, keyboard `[` `]` |
| `lib/main.dart` | Global search | ✅ | Command palette Ctrl/Cmd+K or `/` |
| `lib/main.dart` | PIN lock gate / re-lock on background | 🚫 | N/A (device-only) |
| `lib/main.dart` | Auto-SMS import on resume | 🚫 | N/A (device-only) |
| `lib/main.dart` | Resume sync / reminders refresh | ➖ | Sync is a later task |
| `lib/main.dart` | Keyboard shortcuts 1-4 / N | ✅ | Global key handler |

## Home (`lib/screens/home_screen.dart`, `lib/home_layout.dart`)

| Android screen | Element / setting | Web decision | Web location |
|---|---|---|---|
| Home | Time-aware greeting + profile name | ✅ | Greeting line; name from store |
| Home | Avatar (opens Settings) | ✅ | Sidebar footer only (desktop); Home header on phone |
| Home | Edit Home (section manager) | ✅ | Quiet icon button → right-hand drawer |
| Home | Sync button | ➖ | Shown as "Not connected" status until sync phase |
| Home | Month / year title + calendar jump | ✅ | Title row with arrows; picker opens date dialog |
| Home | Balance hero + hide/show eye | ✅ | 2-col row 3, eye adjacent to amount |
| Home | Spent / Income / Lent out stat strip | ✅ | 2-col row 3 |
| Home | By category: proportional segment bar | ✅ | Left column card; selection synced to rows |
| Home | By category: row list (icon, %, amount) | ✅ | Same card |
| Home | Events (event branches, expandable) | ✅ | Left column card |
| Home | Recent (5 rows) + See all | ✅ | Right column card, link to History |
| Home | Budgets (per-category progress) | ✅ | Optional section in drawer |
| Home | Today ring | ✅ | Optional section in drawer |
| Home | Daily rhythm | ✅ | Optional section in drawer |
| Home | Forecast | ✅ | Optional section in drawer |
| Home | Pull to refresh | 🚫 | Replaced by browser reload / later sync phase |
| Home | Floating Add pill | ✅ | Sidebar primary button + phone round Add |
| Home | Tap entry → edit sheet | ✅ | Entry modal |
| Home | Swipe to delete | 🚫 | Hover action + Undo toast on web |
| Home | One-handed bottom bars / reach zone | 🚫 | Phone-only ergonomics |
| Home | Home section order + visibility pref | ✅ | Drawer writes the same `home_layout_v1` preference |

## History (`lib/screens/history_screen.dart`)

| Android screen | Element / setting | Web decision | Web location |
|---|---|---|---|
| History | Inline search (note/category/mode) | ✅ | Inline field |
| History | Filter chips All / Expense / Income / Category | ✅ | Filter row |
| History | Day filter + calendar jump | ✅ | Filter row + date picker |
| History | Day groups with day net | ✅ | Sticky group headers |
| History | Entries / Categories / Events views | ✅ | Segmented view switch |
| History | Category manager (name, icon, colour, budget, reorder, delete) | ✅ | Categories view + manager dialog |
| History | Events list with per-event totals | ✅ | Events view |
| History | Edit / duplicate / delete entry, Undo | ✅ | Hover actions + toast |
| History | CSV export | ✅ | Export button (download blob) |
| History | Bulk select | ✅ | Selection bar |
| History | Swipe-to-delete | 🚫 | Hover action instead |
| History | 60-row paging / `content-visibility` | ✅ | Web performance requirement |

## Insights (`lib/screens/insights_screen.dart`, `lib/analytics.dart`)

| Android screen | Element / setting | Web decision | Web location |
|---|---|---|---|
| Insights | Period control Month / 3 / 6 / Year / Fiscal | ✅ | Equal-width segmented control, max 460 px |
| Insights | Summary (spend, comparison, income, net, daily avg) | ✅ | Card |
| Insights | Month-end forecast | ✅ | Card |
| Insights | Where it went (ring + legend) | ✅ | SVG ring + legend |
| Insights | How you pay (bar + legend) | ✅ | CSS bar + legend |
| Insights | Monthly rhythm (trend bars) | ✅ | Inline SVG/CSS bars |
| Insights | Money on loan (To receive / To return, "Now") | ✅ | Two-row card |
| Insights | Largest expenses | ✅ | List card |
| Insights | Fiscal-year label when applicable | ✅ | Caption under period control |

## Lent (`lib/screens/lent_screen.dart`)

| Android screen | Element / setting | Web decision | Web location |
|---|---|---|---|
| Lent | Lent out / Borrowed toggle | ✅ | Segmented control |
| Lent | Pending / Settled / All chips | ✅ | Status chips |
| Lent | To receive / To return totals | ✅ | Totals card |
| Lent | Person cards (initials, progress, timeline) | ✅ | One card per person |
| Lent | Top-up / repayment / settle / delete | ✅ | Card actions + dialogs |
| Lent | Due date | ✅ | Shown on card (read/write) |
| Lent | One-time OS reminder scheduling | 🚫 | Device-only; show disclosure line only |
| Lent | Person-name autocomplete | ✅ | Dialog field |

## Settings (`lib/screens/menu_screen.dart`, `lib/screens/settings_screen.dart`)

| Android screen | Element / setting | Web decision | Web location |
|---|---|---|---|
| Settings | Theme System / Light / Dark | ✅ | Grouped card row |
| Settings | Accent colour picker (12 presets + custom) | ✅ | Swatch row + dialog |
| Settings | Material You (wallpaper colour) | 🚫 | Device-only |
| Settings | Calendar AD / BS + conversion | ✅ | Two-segment toggle; port conversion |
| Settings | BS estimate note (BS only) | ✅ | Conditional helper text |
| Settings | Hide balance on launch | ✅ | Switch row |
| Settings | One-handed mode | 🚫 | Phone-only ergonomics |
| Settings | Edit Home | ✅ | Link to drawer |
| Settings | Display currency | ✅ | Picker row |
| Settings | Accounts manager | ✅ | Grouped card + dialogs |
| Settings | Auto-category rules | ✅ | Grouped card + dialog |
| Settings | PIN / biometrics | 🚫 | Device-only |
| Settings | Receipts storage + clear | ✅ | Usage row + clear action |
| Settings | Receipt camera/gallery capture | 🚫 | Web has no platform bridge (not verified); disclosure |
| Settings | Backup export / import / encrypted | ➖ | Later (data layer is out of scope) |
| Settings | Sync / pairing | ➖ | Later task |
| Settings | SMS import + sender allowlist | 🚫 | Device-only |
| Settings | Notifications / reminders permission | 🚫 | Device-only; due dates still shown |
| Settings | About / version / signing | 🚫 | Device-only |
| Settings | Erase all data | ✅ | Destructive row with double confirm (demo store only) |
| Settings | Profile name + avatar style | ✅ | Account & avatar sheet |

## Dialogs / shared flows

| Android screen | Element / setting | Web decision | Web location |
|---|---|---|---|
| `add_screen.dart` | Add expense / income form | ✅ | Centred 480 px modal |
| `entry_actions.dart` | Edit entry + receipt viewer | ✅ | Same modal + viewer |
| `delete.dart` | Delete with Undo | ✅ | Toast with Undo |
| `receipt_field.dart` | Gallery / Camera buttons | 🚫 on web | Disclosure line; stored receipts viewable |
| `menu_screen.dart` | New category / new event dialogs | ✅ | Reused from History/Settings |
| `app_dates.dart` | AD/BS conversion | ✅ | Ported pure logic, no library |
| `format.dart` | Money / date / greeting formatters | ✅ | Ported exactly |
| `home_layout.dart` | Section ids and order | ✅ | Drawer uses same ids/order |

## Summary

- ✅ Include: 68
- 🚫 Device-only / hidden: 15
- ➖ Later: 4
- Total rows: 87
