package ru.komet.app

import android.content.Context
import org.json.JSONObject
import java.io.File

object CallRingtones {
    private const val FLUTTER_PREFS = "FlutterSharedPreferences"
    private const val GLOBAL_KEY = "flutter.call_ringtone"

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
