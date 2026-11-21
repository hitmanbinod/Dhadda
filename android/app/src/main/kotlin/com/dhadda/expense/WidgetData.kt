package com.dhadda.expense

import android.content.Context
import android.database.sqlite.SQLiteDatabase
import org.json.JSONObject
import java.io.File
import java.text.NumberFormat
import java.util.Calendar
import java.util.Locale

private val widgetNumberFormat: NumberFormat = NumberFormat.getNumberInstance(Locale.getDefault())

/**
 * What the home-screen widgets show. Everything is read directly from the
 * app's own private SQLite file and Flutter SharedPreferences with platform
 * APIs only — no plugin, no network, no new dependency.
 *
 * When a PIN lock is enabled the numeric values are masked. The widget never
 * unlocks anything: tapping it only opens the app, which shows the lock gate.
 */
data class WidgetData(
    val hidden: Boolean,
    val symbol: String,
    val todaySpend: Double,
    val monthSpend: Double,
    val monthIncome: Double,
    val toReceive: Double,
    val toReturn: Double,
    val monthLabel: String = "This month",
    val todayLabel: String = "Today",
) {
    /** Grouped currency, e.g. "रू 2,000". */
    fun amount(value: Double): String =
        if (hidden) "••••"
        else "$symbol ${widgetNumberFormat.format(Math.round(value))}"

    /** Net balance keeps the sign before the symbol: "-रू 2,000". */
    fun signedAmount(value: Double): String {
        if (hidden) return "••••"
        val sign = if (value < 0) "-" else ""
        return "$sign$symbol " +
            widgetNumberFormat.format(Math.round(Math.abs(value)))
    }
}

object WidgetSnapshot {
    private const val PREFS = "FlutterSharedPreferences"
    private const val PIN_KEY = "flutter.expense_pin_hash_v1"
    private const val META_KEY = "flutter.expense_meta_v1"
    private const val SNAPSHOT_KEY = "flutter.widget_calendar_snapshot_v1"

    // Mirrors ExpenseStore.currencySymbols; never hard-coded in the layouts.
    private val symbols = mapOf(
        "NPR" to "रू",
        "INR" to "₹",
        "USD" to "$",
        "EUR" to "€",
        "GBP" to "£",
        "AUD" to "A$",
        "CAD" to "C$",
        "AED" to "AED",
        "JPY" to "¥",
        "CNY" to "¥",
    )

    private fun midnight(vararg drop: Int): Long {
        val c = Calendar.getInstance()
        c.set(Calendar.HOUR_OF_DAY, 0)
        c.set(Calendar.MINUTE, 0)
        c.set(Calendar.SECOND, 0)
        c.set(Calendar.MILLISECOND, 0)
        for (field in drop) c.add(field, 1)
        return c.timeInMillis
    }

    fun load(context: Context): WidgetData {
        var hidden = false
        var symbol = "रू"
        var today = 0.0
        var spent = 0.0
        var income = 0.0
        var receive = 0.0
        var ret = 0.0
        var monthLabel = "This month"
        var todayLabel = "Today"
        var snapMonthStart = -1L
        var snapMonthEnd = -1L
        var snapDayStart = -1L
        var snapDayEnd = -1L

        try {
            val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            hidden = !prefs.getString(PIN_KEY, "").isNullOrEmpty()
            val meta = JSONObject(prefs.getString(META_KEY, "{}") ?: "{}")
            symbol = symbols[meta.optString("currency", "NPR")] ?: "रू"
            // Written by WidgetBridge.refresh() from the ACTIVE calendar.
            val snapRaw = prefs.getString(SNAPSHOT_KEY, "")
            if (!snapRaw.isNullOrEmpty()) {
                val snap = JSONObject(snapRaw)
                monthLabel = snap.optString("monthLabel", monthLabel)
                todayLabel = snap.optString("todayLabel", todayLabel)
                snapMonthStart = snap.optLong("monthStart", -1L)
                snapMonthEnd = snap.optLong("monthEnd", -1L)
                snapDayStart = snap.optLong("dayStart", -1L)
                snapDayEnd = snap.optLong("dayEnd", -1L)
            }

            val dbFile = File(context.applicationInfo.dataDir, "app_flutter/dhadda.sqlite")
            if (dbFile.exists()) {
                val db = SQLiteDatabase.openDatabase(
                    dbFile.absolutePath,
                    null,
                    SQLiteDatabase.OPEN_READONLY,
                )
                try {
                    val dayStart = midnight()
                    val dayEnd = midnight(Calendar.DAY_OF_MONTH)
                    val monthStart = Calendar.getInstance().apply {
                        set(Calendar.DAY_OF_MONTH, 1)
                        set(Calendar.HOUR_OF_DAY, 0)
                        set(Calendar.MINUTE, 0)
                        set(Calendar.SECOND, 0)
                        set(Calendar.MILLISECOND, 0)
                    }.timeInMillis
                    val monthEnd = Calendar.getInstance().apply {
                        set(Calendar.DAY_OF_MONTH, 1)
                        set(Calendar.HOUR_OF_DAY, 0)
                        set(Calendar.MINUTE, 0)
                        set(Calendar.SECOND, 0)
                        set(Calendar.MILLISECOND, 0)
                        add(Calendar.MONTH, 1)
                    }.timeInMillis

                    val fromDay = if (snapDayStart in 1..snapDayEnd - 1) snapDayStart else dayStart
                    val toDay = if (snapDayStart in 1..snapDayEnd - 1) snapDayEnd else dayEnd
                    val fromMonth = if (snapMonthStart in 1..snapMonthEnd - 1) snapMonthStart else monthStart
                    val toMonth = if (snapMonthStart in 1..snapMonthEnd - 1) snapMonthEnd else monthEnd

                    db.rawQuery(
                        "SELECT SUM(amount) FROM transactions " +
                            "WHERE type = 'expense' AND date >= ? AND date < ?",
                        arrayOf(fromDay.toString(), toDay.toString()),
                    ).use { c ->
                        if (c.moveToFirst() && !c.isNull(0)) today = c.getDouble(0)
                    }

                    db.rawQuery(
                        "SELECT type, SUM(amount) FROM transactions " +
                            "WHERE date >= ? AND date < ? GROUP BY type",
                        arrayOf(fromMonth.toString(), toMonth.toString()),
                    ).use { c ->
                        while (c.moveToNext()) {
                            val value = if (c.isNull(1)) 0.0 else c.getDouble(1)
                            when (c.getString(0)) {
                                "expense" -> spent = value
                                "income" -> income = value
                            }
                        }
                    }

                    db.rawQuery(
                        "SELECT l.kind, l.principal, " +
                            "(SELECT IFNULL(SUM(amount), 0) FROM loan_topups t " +
                            " WHERE t.loan_id = l.id) AS topups, " +
                            "(SELECT IFNULL(SUM(amount), 0) FROM loan_repayments r " +
                            " WHERE r.loan_id = l.id) AS repaid " +
                            "FROM loans l",
                        null,
                    ).use { c ->
                        while (c.moveToNext()) {
                            val pending = c.getDouble(1) + c.getDouble(2) - c.getDouble(3)
                            if (pending <= 0.005) continue
                            if (c.getString(0) == "borrowed") ret += pending else receive += pending
                        }
                    }
                } finally {
                    db.close()
                }
            }
        } catch (e: Exception) {
            // A widget must never crash the launcher or leak a stack trace.
        }

        return WidgetData(
            hidden, symbol, today, spent, income, receive, ret,
            monthLabel, todayLabel,
        )
    }
}
