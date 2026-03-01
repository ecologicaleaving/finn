package com.ecologicaleaving.fin

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.os.Bundle
import androidx.work.*
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import com.ecologicaleaving.fin.widget.WidgetUpdateWorker
import java.util.concurrent.TimeUnit

class MainActivity: FlutterActivity() {
    private val WIDGET_CHANNEL = "com.ecologicaleaving.fin/widget"
    private var widgetChannel: MethodChannel? = null
    private var widgetEnabledReceiver: BroadcastReceiver? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // Setup widget method channel
        widgetChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, WIDGET_CHANNEL)
        widgetChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "registerBackgroundRefresh" -> {
                    registerBackgroundRefresh()
                    result.success(null)
                }
                "cancelBackgroundRefresh" -> {
                    cancelBackgroundRefresh()
                    result.success(null)
                }
                "updateWidget" -> {
                    updateWidget()
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }

        // Setup broadcast receiver for widget lifecycle events
        widgetEnabledReceiver = object : BroadcastReceiver() {
            override fun onReceive(context: Context?, intent: Intent?) {
                if (intent?.action == "com.ecologicaleaving.fin.WIDGET_ENABLED") {
                    println("MainActivity: Widget enabled broadcast received")
                    widgetChannel?.invokeMethod("onWidgetEnabled", null)
                }
            }
        }

        val filter = IntentFilter("com.ecologicaleaving.fin.WIDGET_ENABLED")
        registerReceiver(widgetEnabledReceiver, filter, Context.RECEIVER_NOT_EXPORTED)
    }

    override fun onDestroy() {
        widgetEnabledReceiver?.let {
            try {
                unregisterReceiver(it)
            } catch (e: Exception) {
                println("MainActivity: Error unregistering receiver: ${e.message}")
            }
        }
        widgetChannel?.setMethodCallHandler(null)
        super.onDestroy()
    }

    private fun registerBackgroundRefresh() {
        println("MainActivity: Registering background widget refresh")

        val workRequest = PeriodicWorkRequestBuilder<WidgetUpdateWorker>(
            30, TimeUnit.MINUTES
        )
            .setConstraints(
                Constraints.Builder()
                    .setRequiredNetworkType(NetworkType.CONNECTED)
                    .build()
            )
            .addTag("widget_refresh")
            .build()

        WorkManager.getInstance(this).enqueueUniquePeriodicWork(
            "widget_background_refresh",
            ExistingPeriodicWorkPolicy.REPLACE,
            workRequest
        )

        println("MainActivity: Background refresh scheduled successfully")
    }

    private fun cancelBackgroundRefresh() {
        println("MainActivity: Cancelling background widget refresh")
        WorkManager.getInstance(this).cancelUniqueWork("widget_background_refresh")
    }

    private fun updateWidget() {
        println("MainActivity: Sending widget update broadcast")
        val intent = Intent(this, com.ecologicaleaving.fin.widget.BudgetWidgetProvider::class.java)
        intent.action = android.appwidget.AppWidgetManager.ACTION_APPWIDGET_UPDATE

        val appWidgetManager = android.appwidget.AppWidgetManager.getInstance(this)
        val widgetComponent = android.content.ComponentName(this, com.ecologicaleaving.fin.widget.BudgetWidgetProvider::class.java)
        val widgetIds = appWidgetManager.getAppWidgetIds(widgetComponent)

        intent.putExtra(android.appwidget.AppWidgetManager.EXTRA_APPWIDGET_IDS, widgetIds)
        sendBroadcast(intent)

        println("MainActivity: Widget update broadcast sent for ${widgetIds.size} widgets")
    }
}
