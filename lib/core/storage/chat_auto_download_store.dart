import 'package:flutter/foundation.dart';

import 'per_chat_json_store.dart';

// #***! вид медиа, для которого спрашивается правило авто-загрузки
enum AutoDownloadMedia { photo, video, voice, videoNote }

// #***! исключение авто-загрузки для одного чата: null значит «не задано»,
// то есть действовать по общим настройкам вида чата
@immutable
class ChatAutoDownloadOverride {
  final bool? photo;
  final bool? video;
  final bool? voice;
  final bool? videoNote;

  const ChatAutoDownloadOverride({
    this.photo,
    this.video,
    this.voice,
    this.videoNote,
  });

  // #***! все значения не заданы — исключения нет, запись можно удалить
  bool get isEmpty =>
      photo == null && video == null && voice == null && videoNote == null;

  ChatAutoDownloadOverride copyWith({
    bool? photo,
    bool? video,
    bool? voice,
    bool? videoNote,
  }) => ChatAutoDownloadOverride(
    photo: photo ?? this.photo,
    video: video ?? this.video,
    voice: voice ?? this.voice,
    videoNote: videoNote ?? this.videoNote,
  );

  // #***! заменяем ровно одно значение, null снимает исключение
  ChatAutoDownloadOverride withValue(AutoDownloadMedia media, bool? value) =>
      switch (media) {
        AutoDownloadMedia.photo => ChatAutoDownloadOverride(
          photo: value,
          video: video,
          voice: voice,
          videoNote: videoNote,
        ),
        AutoDownloadMedia.video => ChatAutoDownloadOverride(
          photo: photo,
          video: value,
          voice: voice,
          videoNote: videoNote,
        ),
        AutoDownloadMedia.voice => ChatAutoDownloadOverride(
          photo: photo,
          video: video,
          voice: value,
          videoNote: videoNote,
        ),
        AutoDownloadMedia.videoNote => ChatAutoDownloadOverride(
          photo: photo,
          video: video,
          voice: voice,
          videoNote: value,
        ),
      };

  Map<String, dynamic> _toJson() => {
    if (photo != null) 'photo': photo,
    if (video != null) 'video': video,
    if (voice != null) 'voice': voice,
    if (videoNote != null) 'video_note': videoNote,
  };

  static ChatAutoDownloadOverride? _fromJson(Object? raw) {
    if (raw is! Map) return null;
    final override = ChatAutoDownloadOverride(
      photo: raw['photo'] is bool ? raw['photo'] as bool : null,
      video: raw['video'] is bool ? raw['video'] as bool : null,
      voice: raw['voice'] is bool ? raw['voice'] as bool : null,
      videoNote: raw['video_note'] is bool ? raw['video_note'] as bool : null,
    );
    return override.isEmpty ? null : override;
  }
}

// #***! исключения авто-загрузки по чатам, хранятся как обои — одним
// джейсоном в prefs с ключом «accountId/chatId»
class ChatAutoDownloadStore extends PerChatJsonStore<ChatAutoDownloadOverride> {
  ChatAutoDownloadStore._()
    : super(
        prefsKey: 'chat_auto_download_overrides',
        fromJson: ChatAutoDownloadOverride._fromJson,
        toJson: (value) => value._toJson(),
      );

  static final ChatAutoDownloadStore instance = ChatAutoDownloadStore._();

  ChatAutoDownloadOverride? get(int accountId, int chatId) =>
      read(accountId, chatId);

  // #***! пустое исключение не храним — запись удаляется целиком
  Future<void> set(
    int accountId,
    int chatId,
    ChatAutoDownloadOverride? value,
  ) => write(accountId, chatId, value?.isEmpty == true ? null : value);

  // #***! чат удалён — его исключения больше не нужны
  Future<void> clearForChat(int accountId, int chatId) =>
      write(accountId, chatId, null);
}
