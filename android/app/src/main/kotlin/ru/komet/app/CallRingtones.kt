package ru.komet.app

import android.content.Context
import org.json.JSONObject
import java.io.File

object CallRingtones {
    private const val FLUTTER_PREFS = "FlutterSharedPreferences"
    private const val GLOBAL_KEY = "flutter.call_ringtone"
    private const val OVERRIDES_KEY = "flutter.call_ringtone_overrides"
    private const val VIBRATION_KEY = "flutter.call_ringtone_vibration"

    const val VIBRATION_DEFAULT = "default"
    const val VIBRATION_DISABLED = "disabled"
    const val VIBRATION_SHORT = "short"
    const val VIBRATION_LONG = "long"
    const val VIBRATION_ONLY_SILENT = "only_silent"

    fun pick(ctx: Context, account: String, callerId: String): String? {
        if (account.isNotEmpty() && callerId.isNotEmpty()) {
            contactPath(ctx, account, callerId)?.let { return it }
        }
        return globalPath(ctx)
    }

    // #***! пресет вибрации звонка: default/disabled/short/long/only_silent
    fun vibration(ctx: Context): String = try {
        ctx.getSharedPreferences(FLUTTER_PREFS, Context.MODE_PRIVATE)
            .getString(VIBRATION_KEY, VIBRATION_DEFAULT) ?: VIBRATION_DEFAULT
    } catch (_: Exception) {
        VIBRATION_DEFAULT
    }

    private fun contactPath(ctx: Context, account: String, callerId: String): String? {
        return try {
            val prefs = ctx.getSharedPreferences(FLUTTER_PREFS, Context.MODE_PRIVATE)
            val raw = prefs.getString(OVERRIDES_KEY, null) ?: return null
            val entry = JSONObject(raw).optJSONObject("$account/$callerId") ?: return null
            val path = entry.optString("path", "")
            if (path.isNotEmpty() && File(path).isFile) path else null
        } catch (e: Exception) {
            null
        }
    }

    fun globalPath(ctx: Context): String? {
        return try {
            val prefs = ctx.getSharedPreferences(FLUTTER_PREFS, Context.MODE_PRIVATE)
            val raw = prefs.getString(GLOBAL_KEY, null) ?: return null
            val path = JSONObject(raw).optString("path", "")
            if (path.isNotEmpty() && File(path).isFile) path else null
        } catch (e: Exception) {
            null
        }
    }
}
