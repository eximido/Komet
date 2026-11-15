package ru.komet.app

import android.content.Context
import android.database.sqlite.SQLiteDatabase
import android.util.Log

// Пуш по Firebase может дойти, когда прямого соединения с сервером нет:
// сообщение существует только в уведомлении, и пока приложение не
// синхронизируется, кэш чата о нём не знает — пользователь открывает чат
// и не видит то, о чём ему только что сообщили. Здесь заготовка сообщения
// из пуша ложится прямо в базу: строка messages без payload (id, отправитель,
// текст, время) плюс освежение превью чата. Когда связь появится и история
// скачается, серверная версия с полным payload перезапишет заготовку —
// и у Dart (saveMessages с ConflictAlgorithm.replace по ключу id+account_id),
// и здесь (INSERT OR IGNORE) ключ один и тот же, так что дублей не возникает.
//
// Сознательно не сеем:
// - чаты с включённым e2ee (e2ee_sessions): сервер текста не знает, в пуше
//   заглушка, вставлять её в историю нельзя;
// - пуши без текста и с заглушкой «Новое сообщение» (скрытое превью,
//   вложения без текста): настоящего содержимого у нас нет — пусть чат
//   дождётся синхронизации, лучше пусто, чем неправильно;
// - чаты, которых нет в кэше: такой чат с экрана всё равно не открыть,
//   карточку ему принесёт синхронизация.
// Диапазоны message_ranges не трогаем: сообщение вне диапазона не «сшивает»
// дыру в истории, приложение само видит, что новее кэша есть непроверенное,
// и дочитывает историю при подключении.
//
// База у каждой копии своя (KOMET_INSTANCE): komet.db или komet_<имя>.db,
// имя зашито в BuildConfig той же сборкой (см. build.gradle.kts и
// MessageReadState).
object PushMessageStore {
    private const val TAG = "KometFcm"
    private const val DEFAULT_DB = "komet.db"

    // Заглушка скрытого превью: ту же строку подставляет Dart для пуша
    // (fkm_controller, _hiddenPreview) и натив в showMessage. Настоящее
    // сообщение с таким текстом потеряется из заготовки — ну и ладно,
    // синхронизация принесёт его целиком.
    private const val HIDDEN_PREVIEW = "Новое сообщение"

    // Повторяет AppInstance в Dart: пустая копия — komet.db, именованная —
    // komet_<имя>.db. Экзотические символы в имени не поддерживаем: базу не
    // угадываем, заготовка не пишется, уведомление работает как раньше.
    private val DB_NAME: String? = run {
        val instance = BuildConfig.KOMET_INSTANCE
        when {
            instance.isEmpty() -> DEFAULT_DB
            instance.matches(Regex("[A-Za-z0-9_-]{1,64}")) -> "komet_$instance.db"
            else -> null
        }
    }

    // id сообщения — серверная строка из пуша, она же первичный ключ messages;
    // время сообщения сидит в старших битах id (id ushr 16), как у самого
    // приложения (messageIdToTime), а не в ctime пуша: время должно совпасть
    // с серверным до миллисекунды, иначе заготовка встанет не на своё место
    // в истории.
    fun seed(ctx: Context, data: Map<String, String>) {
        val account = data["c"]?.toIntOrNull() ?: return
        if (account == 0) return
        val chatId = data["mc"]?.toLongOrNull() ?: return
        if (chatId == 0L) return
        val rawId = data["msgid"]?.takeIf { it.isNotEmpty() } ?: return
        val msgId = rawId.toLongOrNull() ?: return
        val text = data["msg"] ?: data["body"] ?: data["text"] ?: return
        if (text.isEmpty() || text == HIDDEN_PREVIEW) return
        var time = msgId ushr 16
        if (time <= 0L) {
            time = data["ctime"]?.toLongOrNull() ?: data["ttime"]?.toLongOrNull() ?: return
        }
        val sender = data["suid"]?.toLongOrNull() ?: 0L
        if (store(ctx, account, chatId, rawId, msgId, sender, text, time)) {
            Log.d(TAG, "push seeded into cache: chat=$chatId msg=$rawId")
        }
    }

    private fun store(
        ctx: Context,
        account: Int,
        chatId: Long,
        rawId: String,
        msgId: Long,
        sender: Long,
        text: String,
        time: Long,
    ): Boolean {
        val name = DB_NAME ?: return false
        val dbFile = ctx.getDatabasePath(name)
        if (!dbFile.isFile) return false
        var db: SQLiteDatabase? = null
        try {
            db = SQLiteDatabase.openDatabase(dbFile.path, null, SQLiteDatabase.OPEN_READWRITE)
            db.beginTransaction()
            try {
                if (e2eeActive(db, account, chatId)) return false
                if (!chatCached(db, account, chatId)) return false
                db.execSQL(
                    "INSERT OR IGNORE INTO messages " +
                        "(id, account_id, chat_id, sender_id, text, time, status, payload, deleted, e2ee) " +
                        "VALUES (?, ?, ?, ?, ?, ?, 'sent', NULL, 0, 0)",
                    arrayOf(rawId, account, chatId, sender, text, time),
                )
                // Превью чата трогаем, только если сообщение новее текущего
                // и не повторяет его: дубль пуша или опоздавший пуш не должен
                // двигать счётчик и превью (то же, что isStaleLast в Dart).
                // last_msg_id — это id сообщения, не чата. Свой счёт
                // непрочитанных не растёт: сообщение с другого своего устройства.
                db.execSQL(
                    "UPDATE chats_cache SET " +
                        "last_msg_id = ?, last_msg_time = ?, last_msg_text = ?, " +
                        "last_msg_elements = NULL, last_msg_preview = NULL, " +
                        "last_msg_sender = ?, last_msg_status = 'sent', last_event_time = ?, " +
                        "unread_count = unread_count + ? " +
                        "WHERE account_id = ? AND id = ? " +
                        "AND (last_msg_id IS NULL OR last_msg_id != ?) " +
                        "AND (last_msg_time IS NULL OR last_msg_time <= ?)",
                    arrayOf(
                        msgId, time, text, sender, time,
                        if (sender == account.toLong()) 0L else 1L,
                        account, chatId, msgId, time,
                    ),
                )
                db.setTransactionSuccessful()
                return true
            } finally {
                db.endTransaction()
            }
        } catch (e: Exception) {
            Log.w(TAG, "push seed failed: ${e.message}")
            return false
        } finally {
            db?.close()
        }
    }

    // Сквозное шифрование включено: сервер прислал заглушку, заготовку
    // не пишем (Dart расшифрует настоящее сообщение по соединению).
    private fun e2eeActive(db: SQLiteDatabase, account: Int, chatId: Long): Boolean =
        db.rawQuery(
            "SELECT 1 FROM e2ee_sessions WHERE account_id = ? AND chat_id = ? AND phase <> 'none' LIMIT 1",
            arrayOf(account.toString(), chatId.toString()),
        ).use { it.moveToFirst() }

    // Чата нет в кэше — заготовке некуда лечь, историю откроют после
    // синхронизации, когда чат появится целиком.
    private fun chatCached(db: SQLiteDatabase, account: Int, chatId: Long): Boolean =
        db.rawQuery(
            "SELECT 1 FROM chats_cache WHERE account_id = ? AND id = ? LIMIT 1",
            arrayOf(account.toString(), chatId.toString()),
        ).use { it.moveToFirst() }
}
