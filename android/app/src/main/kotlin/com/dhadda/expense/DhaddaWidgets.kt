package com.dhadda.expense

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.widget.RemoteViews

const val QUICK_ACTION_EXTRA = "dhadda_quick_action"

private fun launch(context: Context, action: String?, requestCode: Int): PendingIntent {
    val intent = Intent(context, MainActivity::class.java).apply {
        flags = Intent.FLAG_ACTIVITY_NEW_TASK or
            Intent.FLAG_ACTIVITY_CLEAR_TOP or
            Intent.FLAG_ACTIVITY_SINGLE_TOP
        if (action != null) putExtra(QUICK_ACTION_EXTRA, action)
    }
    return PendingIntent.getActivity(
        context,
        requestCode,
        intent,
        PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
    )
}

private fun render(
    context: Context,
    manager: AppWidgetManager,
    ids: IntArray,
    layout: Int,
    fill: (RemoteViews, WidgetData) -> Unit,
) {
    val data = WidgetSnapshot.load(context)
    for (id in ids) {
        val views = RemoteViews(context.packageName, layout)
        views.setOnClickPendingIntent(R.id.widget_root, launch(context, null, id))
        fill(views, data)
        manager.updateAppWidget(id, views)
    }
}

class TodayWidget : AppWidgetProvider() {
    override fun onUpdate(
        context: Context,
        manager: AppWidgetManager,
        ids: IntArray,
    ) {
        render(context, manager, ids, R.layout.widget_today) { views, data ->
            views.setTextViewText(R.id.widget_today_date, data.todayLabel)
            views.setTextViewText(R.id.widget_today_amount, data.amount(data.todaySpend))
            views.setTextViewText(
                R.id.widget_today_note,
                if (data.hidden) "Amounts hidden · unlock to see"
                else "Add expense  ›",
            )
        }
    }
}

class MonthWidget : AppWidgetProvider() {
    override fun onUpdate(
        context: Context,
        manager: AppWidgetManager,
        ids: IntArray,
    ) {
        render(context, manager, ids, R.layout.widget_month) { views, data ->
            views.setTextViewText(R.id.widget_month_label, data.monthLabel)
            views.setTextViewText(R.id.widget_month_spent, data.amount(data.monthSpend))
            views.setTextViewText(R.id.widget_month_income, data.amount(data.monthIncome))
            views.setTextViewText(
                R.id.widget_month_balance,
                data.signedAmount(data.monthIncome - data.monthSpend),
            )
        }
    }
}

class LentWidget : AppWidgetProvider() {
    override fun onUpdate(
        context: Context,
        manager: AppWidgetManager,
        ids: IntArray,
    ) {
        render(context, manager, ids, R.layout.widget_lent) { views, data ->
            views.setTextViewText(
                R.id.widget_lent_receive_amount,
                data.amount(data.toReceive),
            )
            views.setTextViewText(
                R.id.widget_lent_return_amount,
                data.amount(data.toReturn),
            )
        }
    }
}

class QuickAddWidget : AppWidgetProvider() {
    override fun onUpdate(
        context: Context,
        manager: AppWidgetManager,
        ids: IntArray,
    ) {
        for (id in ids) {
            val views = RemoteViews(context.packageName, R.layout.widget_quickadd)
            views.setOnClickPendingIntent(
                R.id.widget_add_expense,
                launch(context, "expense", id * 3 + 1),
            )
            views.setOnClickPendingIntent(
                R.id.widget_add_income,
                launch(context, "income", id * 3 + 2),
            )
            views.setOnClickPendingIntent(
                R.id.widget_add_lent,
                launch(context, "lent", id * 3 + 3),
            )
            manager.updateAppWidget(id, views)
        }
    }
}

/** Called from Flutter on resume so widgets never lag behind the app. */
fun refreshWidgets(context: Context) {
    val manager = AppWidgetManager.getInstance(context)
    for (provider in arrayOf(
        TodayWidget::class.java,
        MonthWidget::class.java,
        LentWidget::class.java,
        QuickAddWidget::class.java,
    )) {
        val ids = manager.getAppWidgetIds(ComponentName(context, provider))
        if (ids.isEmpty()) continue
        val intent = Intent(context, provider).apply {
            action = AppWidgetManager.ACTION_APPWIDGET_UPDATE
            putExtra(AppWidgetManager.EXTRA_APPWIDGET_IDS, ids)
        }
        context.sendBroadcast(intent)
    }
}
