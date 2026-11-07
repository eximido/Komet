package ru.komet.app

import android.content.Context
import android.database.sqlite.SQLiteDatabase
import android.util.Log
import org.json.JSONObject
import java.io.File

// Серверный id сообщения несёт его время в старших битах (младшие 16 — счётчик
// внутри миллисекунды), а chats_cache.participants хранит для каждого аккаунта
// время последнего прочитанного сообщения — тем же способом «прочитано до»
// пользуется сам экран чата. Пуш по Firebase может опоздать: сообщение уже
// пришло по прямому соединению и прочитано, и тогда уведомление не нужно.
// Если прямого соединения не было, отметка остаётся старой и уведомление
// покажется как обычно, так что «чат прочитан целиком» ничего не подавляет.
//
// База у каждой копии приложения своя (KOMET_INSTANCE): komet.db или
// komet_<имя>.db. Имя копии зашивается в BuildConfig той же сборкой из того же
// --dart-define, что компилируется и в Dart (см. build.gradle.kts), поэтому
// здесь открывается один точный файл без сканирования каталога и без канала к
// Dart — имя известно с самой первой доставки пуша, ещё до запуска Dart.
object MessageReadState {
    private const val DEFAULT_DB = "komet.db"

    // Повторяет AppInstance в Dart: пустая копия — komet.db, именованная —
    // komet_<имя>.db. Экзотические символы в имени не поддерживаем: базу не
    // угадываем, в таком случае все сообщения в принятых пушах будут считаться
    // безусловно новыми.
    private val DB_NAME: String? = run {
        val instance = BuildConfig.KOMET_INSTANCE
        when {
            instance.isEmpty() -> DEFAULT_DB
            instance.matches(Regex("[A-Za-z0-9_-]{1,64}")) -> "komet_$instance.db"
            else -> null
        }
    }

    fun isRead(ctx: Context, account: Int, chatId: Long, messageId: String): Boolean {
        if (account == 0 || chatId == 0L) return false
        val id = messageId.toLongOrNull() ?: return false
        val messageTime = id ushr 16
        if (messageTime <= 0L) return false
        val db = database(ctx) ?: return false
        return isReadIn(db, account, chatId, messageTime)
    }

    // Файла нет — считаем непрочитанным (покажем уведомление).
    private fun database(ctx: Context): File? {
        val name = DB_NAME ?: return null
        val file = ctx.getDatabasePath(name)
        return if (file.isFile) file else null
    }

    private fun isReadIn(db: File, account: Int, chatId: Long, messageTime: Long): Boolean {
        var opened: SQLiteDatabase? = null
        try {
            opened = open(db) ?: return false
            opened.rawQuery(
                "SELECT participants FROM chats_cache WHERE id = ? AND account_id = ?",
                arrayOf(chatId.toString(), account.toString()),
            ).use { cursor ->
                while (cursor.moveToNext()) {
                    if (ownReadMark(cursor.getString(0), account) >= messageTime) return true
                }
            }
        } catch (e: Exception) {
            Log.w("KometFcm", "read mark lookup failed: ${e.message}")
        } finally {
            opened?.close()
        }
        return false
    }

    // participants — json вида {"<userId>": <время последнего прочитанного>}.
    private fun ownReadMark(raw: String?, account: Int): Long {
        if (raw.isNullOrEmpty()) return 0L
        return try {
            JSONObject(raw).optLong(account.toString(), 0L)
        } catch (e: Exception) {
            0L
        }
    }

    private fun open(db: File): SQLiteDatabase? = try {
        SQLiteDatabase.openDatabase(db.path, null, SQLiteDatabase.OPEN_READONLY)
    } catch (e: Exception) {
        // wal-база без живого держателя восстанавливает -shm только записью.
        try {
            SQLiteDatabase.openDatabase(db.path, null, SQLiteDatabase.OPEN_READWRITE)
        } catch (e2: Exception) {
            null
        }
    }
}
