# Dhadda design system (short reference)

Source of truth for values: `design/tokens.json`. Generated:
`design/tokens.css`, `lib/theme/tokens.g.dart` via `python3 scripts/sync_tokens.py`.

## Tokens

| Group | Values |
|---|---|
| Dark "Ink" | bg #0B100F · surface #121A18 · surface-2 #18221F · hairline rgba(255,255,255,.06) · text #ECF3F0 · text-2 #8E9E99 · accent #7BDCC0 · on-accent #04201A · expense #F2A092 · income #8FD3A9 · warn #E9C27A · lent #A9A6F0 |
| Light "Paper" | bg #F5F3EE · surface #FFFFFF · surface-2 #EFEDE7 · hairline rgba(20,32,29,.08) · text #14201D · text-2 #5C6B67 · accent #0E8C76 · on-accent #FFFFFF · expense #B84B3C · income #23784A · warn #8A6411 · lent #5B57C9 |
| Category | sage #7BDCC0 · amber #E7BC73 · periwinkle #8EA7F2 · lilac #BE9CEB · coral #F2A092 · sky #7FCBEA · rose #EE9DB9 · moss #A8CF7F |
| Radii | tile 10 · chip 999 · card 18 · sheet 24 · tabbar 24 · input 12 · segmented 10 |
| Spacing | 4 · 8 · 12 · 16 · 24 · 32 · 48 |
| Type | large-title 34/700/-0.6 · title 22/600 · headline 17/600 · body 16 · subhead 15 · footnote 13 · caption 12 · hero 56/700/-2 · editor-amount 48/700 · amounts tabular |
| Motion | ease cubic-bezier(.2,.8,.2,1) · spring cubic-bezier(.34,1.4,.64,1) · 150/250/350 ms · hero count-up 600 ms · row highlight 1200 ms |

Elevation: dark = lighter surfaces on top; glass blur 18px only on
topbar(collapsed)/tabbar/sidebar/sheets/popovers; max two blurred layers;
shadows only on floating controls.

Font stack: system UI with Nepali fallback (`Nirmala UI`,
`Noto Sans Devanagari`).

## Layout

- Desktop ≥900 px: 224 px glass sidebar (brand + Home/History/Insights/Lent
  + footer), sticky 60 px topbar (title, search, theme, Add, avatar), centred
  content max-width 960 px; Add FAB hidden.
- Phone <900 px: bottom glass tab bar (4 tabs) + round Add FAB; sheets are
  bottom sheets with grabber; respect safe-area insets.
- Settings opens from the avatar as a full page with a back button — never a
  tab. Desktop also has an avatar in the topbar.

## Components (Flutter equivalents)

| Mock class | Flutter widget / file |
|---|---|
| `.card`, `.group` | `AppCard`, `AppCard.group` — `lib/widgets/app_card.dart` |
| `.tx-row` | entry rows in `lib/screens/history_screen.dart`, `home_screen.dart` |
| `.seg` | `SegmentedTabs` — `lib/widgets/segmented_tabs.dart` |
| `.chip` | `ChoiceChip` / filter pills in History |
| `.btn`, `.icon-btn`, `.text-btn` | theme buttons in `lib/theme/app_theme.dart` |
| `.tile`, `.avatar` | `CategoryTile`, `ProfileAvatar` |
| `.meter`, `.stackbar` | `LinearProgressIndicator`, stacked bar in Home/Insights |
| `.quiet-empty`, `.empty-hero` | `EmptyState` — `lib/widgets/empty_state.dart` |
| `.sheet`, `.pop-panel`, `.toast` | `showDialog`/`showModalBottomSheet`, SnackBars |
| `.hero-amt`, `.amt-*` | `AppType.heroAmount`, `MoneyText` — `lib/widgets/money_text.dart` |

Never hard-code a colour, radius or spacing in a component: read the theme
roles (`AppColors.of(context)`) or `Radii`/`Spacing`, both fed by tokens.json.
