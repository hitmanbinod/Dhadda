# DHADDA WIDGET RULES
Read this whole file before any widget task. Obey it exactly.

## PROJECT OVERRIDES (these win over anything below)
- Providers are TodayWidget, MonthWidget, LentWidget, QuickAddWidget in DhaddaWidgets.kt (package com.dhadda.expense). Do not rename or split them.
- Data comes from WidgetSnapshot.load(context) in WidgetData.kt. Do NOT use HomeWidgetPreferences or wg_* keys. Section D and the golden Kotlin show style only.
- Layout files are widget_today, widget_month, widget_lent, widget_quickadd. Naming rule 13 does not apply.
- Sections A, B and C, and the golden layout, still apply.

Dhadda is a Flutter app. Widgets are native Android: Kotlin providers plus XML layouts shown through RemoteViews. The LAUNCHER draws them, not the app. Normal Android UI rules do not apply.

## A. Hard rules (break one and you get "Can't load widget")
1. Allowed layout tags ONLY: FrameLayout, LinearLayout, RelativeLayout, TextView, ImageView, ImageButton, Button, ProgressBar.
2. FORBIDDEN: View, Space, ConstraintLayout, CardView, MaterialCardView, ScrollView, ViewStub, merge, any androidx.* or com.google.* tag, any custom view.
3. Dots, dividers, circles, bars: use an ImageView with a shape drawable, or a FrameLayout with a background. NEVER <View>. NEVER <Space> (use an empty FrameLayout).
4. NEVER use: ?attr/..., ?android:attr/..., app:..., @font/..., tools:..., custom styles or themes. Colors only as @color/wg_*. Fonts only android:fontFamily="sans-serif" or "sans-serif-medium". (The one platform ProgressBar style named in a spec is allowed.)
5. Sample text goes in android:text with real values, for example "रू 2,000". The widget picker preview shows it.
6. Kotlin may only call: setTextViewText and setTextColor on a TextView id; setImageViewResource and setImageViewBitmap on an ImageView id; setProgressBar on a ProgressBar id; setViewVisibility and setOnClickPendingIntent on any id. Before each call, check that id's tag in the layout.
7. Providers contain ZERO business logic. They read ready-to-show strings from prefs and set them. Formatting happens in Dart. Only allowed logic: choose one of two colors from a "1"/"0" flag, and hide a row when its text is empty.
8. Every onUpdate body is inside try/catch, logs with tag "DhaddaWidget", and never throws.
9. Icons are vector drawables used with ImageView android:src, tinted with android:tint="@color/...".
10. Every TextView has maxLines="1" and ellipsize="end".
11. Click targets use PendingIntent.FLAG_IMMUTABLE or'd with FLAG_UPDATE_CURRENT. Reuse the launch mechanism the working Quick widget already uses.
12. Do not add dependencies. Do not edit files unrelated to widgets, except the one Dart sync file.
13. Naming: layouts widget_<name>.xml, info xml widget_<name>_info.xml, providers <Name>WidgetProvider.kt. Never rename a provider class without updating AndroidManifest.xml in the same step.

## B. Colors
Create res/values/wg_colors.xml (light, porcelain) and res/values-night/wg_colors.xml (dark, graphite). Same names in both. Format is #AARRGGBB.

| name | light | dark |
|---|---|---|
| wg_surface | #F5F7F5F0 | #F2161B19 |
| wg_stroke | #FFE3DFD5 | #FF2A3230 |
| wg_tile | #FFFFFFFF | #FF1F2624 |
| wg_tile_stroke | #FFE8E4DB | #FF2E3633 |
| wg_pill | #FFEFECE4 | #FF262E2C |
| wg_text | #FF1B1B1A | #FFF4F6F5 |
| wg_text2 | #FF7A766E | #FF8E9A95 |
| wg_expense | #FFC8321F | #FFF28B78 |
| wg_income | #FF1C8A52 | #FF4FD1A5 |
| wg_lent | #FF3B4A8F | #FFA9B4F2 |
| wg_expense_bg | #FFFDECEA | #FF2D1F1E |
| wg_income_bg | #FFE6F3EA | #FF1B2B25 |
| wg_lent_bg | #FFEAEDFB | #FF1E2238 |
| wg_expense_line | #40C8321F | #55F28B78 |
| wg_income_line | #401C8A52 | #554FD1A5 |
| wg_lent_line | #403B4A8F | #55A9B4F2 |
| wg_brand | #FFD4202B | #FFD4202B |

## C. Shapes, sizes, type
Shape drawables in res/drawable (each is a <shape> with <solid>, <corners>, optional <stroke android:width="1dp">):
- wg_bg_surface: solid wg_surface, radius 24dp, stroke wg_stroke
- wg_bg_tile: solid wg_tile, radius 16dp, stroke wg_tile_stroke
- wg_bg_pill: solid wg_pill, radius 14dp
- wg_bg_expense, wg_bg_income, wg_bg_lent: solid wg_*_bg, radius 14dp, stroke wg_*_line
- wg_bg_brand: solid wg_brand, radius 8dp
- wg_circle_expense, wg_circle_income, wg_circle_lent: oval, solid wg_*_bg
- wg_dot: oval, solid #FFFFFFFF, <size> 6dp by 6dp (tinted in the layout)

Vector icons (24dp, viewport 24, ONE path each, fillColor #FFFFFFFF): wg_ic_plus, wg_ic_minus, wg_ic_swap, wg_ic_chevron. Path data:
- plus: M19,13h-6v6h-2v-6H5v-2h6V5h2v6h6v2z
- minus: M19,13H5v-2h14v2z
- swap: M6.99,11L3,15l3.99,4v-3H14v-2H6.99v-3zM21,9l-3.99,-4v3H10v2h7.01v3L21,9z
- chevron: M10,6L8.59,7.41 13.17,12l-4.58,4.59L10,18l6,-6z

Sizes: 2x2 = 110dp x 110dp. 4x2 = 250dp x 110dp. 4x1 = 250dp x 40dp. Design for about 146dp of height on 2x2 and 4x2.
Spacing: outer padding 12dp (4x1: 6dp). Gap between tiles 8dp.
Type: title 13sp sans-serif-medium. Label 11sp wg_text2. Big amount 24sp bold. Tile amount 17sp bold. Pill text 11sp or 12sp sans-serif-medium.

## D. Data keys (Dart writes, Kotlin reads; every value is a String)
If hide-balance is on, Dart writes "रू ••••" into every amount key.

| Key | Example | Used by |
|---|---|---|
| wg_today_date | Sat, 5 Mangsir | Today |
| wg_today_spent | रू 2,000 | Today |
| wg_month_title | Mangsir 2083 | Month |
| wg_month_spent | रू 2,000 | Month |
| wg_month_income | रू 0 | Month |
| wg_month_balance | -रू 2,000 | Month |
| wg_month_balance_neg | 1 or 0 | Month (red when 1) |
| wg_loan_receive | रू 0 | Lent |
| wg_loan_return | रू 1,000 | Lent |

Prefs file name: HomeWidgetPreferences. Provider names: TodayWidgetProvider, MonthWidgetProvider, LentWidgetProvider, QuickWidgetProvider.

## E. Golden example (Today, 2x2). Copy this structure for every widget.

res/xml/widget_today_info.xml
```xml
<?xml version="1.0" encoding="utf-8"?>
<appwidget-provider xmlns:android="http://schemas.android.com/apk/res/android"
    android:minWidth="110dp" android:minHeight="110dp"
    android:targetCellWidth="2" android:targetCellHeight="2"
    android:updatePeriodMillis="0" android:resizeMode="none"
    android:initialLayout="@layout/widget_today"
    android:previewLayout="@layout/widget_today"
    android:widgetCategory="home_screen"
    android:description="@string/widget_today_desc" />
```

res/layout/widget_today.xml
```xml
<?xml version="1.0" encoding="utf-8"?>
<LinearLayout xmlns:android="http://schemas.android.com/apk/res/android"
    android:id="@+id/w_root" android:layout_width="match_parent" android:layout_height="match_parent"
    android:background="@drawable/wg_bg_surface" android:orientation="vertical" android:padding="12dp">

    <LinearLayout android:layout_width="match_parent" android:layout_height="wrap_content"
        android:gravity="center_vertical" android:orientation="horizontal">

        <LinearLayout android:layout_width="0dp" android:layout_height="wrap_content"
            android:layout_weight="1" android:orientation="vertical">
            <TextView android:layout_width="wrap_content" android:layout_height="wrap_content"
                android:ellipsize="end" android:fontFamily="sans-serif-medium" android:maxLines="1"
                android:text="Today" android:textColor="@color/wg_text" android:textSize="13sp" />
            <TextView android:id="@+id/w_date" android:layout_width="wrap_content" android:layout_height="wrap_content"
                android:ellipsize="end" android:maxLines="1" android:text="Sat, 5 Mangsir"
                android:textColor="@color/wg_text2" android:textSize="11sp" />
        </LinearLayout>

        <FrameLayout android:id="@+id/w_add" android:layout_width="28dp" android:layout_height="28dp"
            android:background="@drawable/wg_circle_expense">
            <ImageView android:layout_width="14dp" android:layout_height="14dp" android:layout_gravity="center"
                android:contentDescription="Add expense" android:src="@drawable/wg_ic_plus"
                android:tint="@color/wg_expense" />
        </FrameLayout>
    </LinearLayout>

    <FrameLayout android:layout_width="match_parent" android:layout_height="0dp" android:layout_weight="1" />

    <TextView android:layout_width="wrap_content" android:layout_height="wrap_content"
        android:ellipsize="end" android:maxLines="1" android:text="Spent today"
        android:textColor="@color/wg_text2" android:textSize="11sp" />
    <TextView android:id="@+id/w_amount" android:layout_width="match_parent" android:layout_height="wrap_content"
        android:ellipsize="end" android:fontFamily="sans-serif-medium" android:maxLines="1" android:text="रू 2,000"
        android:textColor="@color/wg_text" android:textSize="24sp" android:textStyle="bold" />

    <LinearLayout android:id="@+id/w_pill" android:layout_width="match_parent" android:layout_height="28dp"
        android:layout_marginTop="8dp" android:background="@drawable/wg_bg_pill" android:gravity="center_vertical"
        android:orientation="horizontal" android:paddingStart="10dp" android:paddingEnd="8dp">
        <ImageView android:layout_width="6dp" android:layout_height="6dp"
            android:src="@drawable/wg_dot" android:tint="@color/wg_expense" />
        <TextView android:layout_width="0dp" android:layout_height="wrap_content" android:layout_weight="1"
            android:layout_marginStart="6dp" android:ellipsize="end" android:maxLines="1" android:text="Add expense"
            android:textColor="@color/wg_text" android:textSize="11sp" />
        <ImageView android:layout_width="12dp" android:layout_height="12dp"
            android:src="@drawable/wg_ic_chevron" android:tint="@color/wg_text2" />
    </LinearLayout>
</LinearLayout>
```

TodayWidgetProvider.kt (use the project's real package; R comes from that package)
```kotlin
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context
import android.util.Log
import android.widget.RemoteViews

class TodayWidgetProvider : AppWidgetProvider() {
    override fun onUpdate(context: Context, manager: AppWidgetManager, ids: IntArray) {
        for (id in ids) {
            try {
                val p = context.getSharedPreferences("HomeWidgetPreferences", Context.MODE_PRIVATE)
                val v = RemoteViews(context.packageName, R.layout.widget_today)
                v.setTextViewText(R.id.w_date, p.getString("wg_today_date", "") ?: "")
                v.setTextViewText(R.id.w_amount, p.getString("wg_today_spent", "रू 0") ?: "रू 0")
                v.setOnClickPendingIntent(R.id.w_root, WidgetIntents.open(context, "home", 10))
                v.setOnClickPendingIntent(R.id.w_add, WidgetIntents.open(context, "add_expense", 11))
                v.setOnClickPendingIntent(R.id.w_pill, WidgetIntents.open(context, "add_expense", 12))
                manager.updateAppWidget(id, v)
            } catch (e: Exception) {
                Log.e("DhaddaWidget", "Today update failed", e)
            }
        }
    }
}
```
WidgetIntents.open(context, route, requestCode) returns a PendingIntent. Build it from the launch code the Quick widget already uses.

## F. Gates and workflow
1. After every widget task run: `dart run tool/check_widgets.dart widget_<name>` and then `flutter build apk --debug`. Both must pass.
2. Never say "done" until both gates pass. Paste the last lines of each gate in your report.
3. Old widget instances on the home screen keep the old layout. Always end your report with: "Remove the old widget and add it again."
4. Only do the steps you were given. If you see something else to improve, list it at the end. Do not do it.
