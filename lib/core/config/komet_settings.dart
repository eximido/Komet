import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../storage/chat_auto_download_store.dart';
import 'build_profile.dart';

// #***! вид чата, для которого настраивается авто-загрузка медиа
enum AutoDownloadKind { dialog, group, channel }

// #***! серверный тип чата -> вид авто-загрузки, неизвестное считаем личкой
AutoDownloadKind autoDownloadKindOf(String chatType) => switch (chatType) {
  'CHANNEL' => AutoDownloadKind.channel,
  'CHAT' || 'GROUP' => AutoDownloadKind.group,
  _ => AutoDownloadKind.dialog,
};

// #***! авто-загрузка одного вида чата: включённый мастер форсирует все
// флаги во включённом состоянии, а выключенный сбрасывает их в off и
// раскрывает меню, из которого включается только нужное
class AutoDownloadScope {
  AutoDownloadScope(this.kind);

  final AutoDownloadKind kind;
  final ValueNotifier<bool> master = ValueNotifier(true);
  final ValueNotifier<bool> photo = ValueNotifier(true);
  final ValueNotifier<bool> video = ValueNotifier(true);
  final ValueNotifier<bool> voice = ValueNotifier(true);
  final ValueNotifier<bool> videoNote = ValueNotifier(true);

  String _key(String flag) => 'komet_auto_download_${kind.name}_$flag';

  Map<ValueNotifier<bool>, String> get _flags => {
    photo: 'photo',
    video: 'video',
    voice: 'voice',
    videoNote: 'video_note',
  };

  // #***! выбраны ли все типы медиа — сводка в этом случае показывает
  // общий текст «загружаются все медиафайлы», а не перечисление
  bool get allFlagsOn =>
      photo.value && video.value && voice.value && videoNote.value;

  // #***! читаем свои ключи, а если их ещё нет — наследуем старые
  // глобальные переключатели, действовавшие на все чаты сразу
  Future<void> load(
    SharedPreferences prefs, {
    bool? legacyPhoto,
    bool? legacyVideo,
    bool? legacyVoice,
    bool? legacyVideoNote,
  }) async {
    final legacyAllOn = [
      legacyPhoto,
      legacyVideo,
      legacyVoice,
      legacyVideoNote,
    ].every((value) => value ?? true);
    master.value = prefs.getBool(_key('master')) ?? legacyAllOn;
    photo.value = prefs.getBool(_key('photo')) ?? legacyPhoto ?? true;
    video.value = prefs.getBool(_key('video')) ?? legacyVideo ?? true;
    voice.value = prefs.getBool(_key('voice')) ?? legacyVoice ?? true;
    videoNote.value =
        prefs.getBool(_key('video_note')) ?? legacyVideoNote ?? true;
    // #***! включённый мастер всегда подразумевает все флаги включёнными
    if (master.value) await _forceAll(prefs, true);
  }

  // #***! мастер выключен, но все опции включены — это то же самое, что
  // включённый мастер; при следующем заходе в настройки возвращаем мастер,
  // иначе он висит выключенным при полностью включённых опциях
  Future<void> normalize() async {
    if (master.value || !allFlagsOn) return;
    await setMaster(true);
  }

  // #***! включение мастера включает все типы сразу, выключение наоборот
  // сбрасывает всё в off: пользователь включает только нужное с нуля
  Future<void> setMaster(bool value) async {
    master.value = value;
    // память сразу — раскрытое меню показывает новые значения без прыжков
    final changed = <String>[];
    for (final entry in _flags.entries) {
      if (entry.key.value != value) {
        entry.key.value = value;
        changed.add(entry.value);
      }
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_key('master'), value);
    for (final flag in changed) {
      await prefs.setBool(_key(flag), value);
    }
  }

  Future<void> setPhoto(bool value) => _setFlag(photo, 'photo', value);

  Future<void> setVideo(bool value) => _setFlag(video, 'video', value);

  Future<void> setVoice(bool value) => _setFlag(voice, 'voice', value);

  Future<void> setVideoNote(bool value) =>
      _setFlag(videoNote, 'video_note', value);

  // #***! память сразу, диск потом
  Future<void> _setFlag(
    ValueNotifier<bool> notifier,
    String flag,
    bool value,
  ) async {
    notifier.value = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_key(flag), value);
  }

  Future<void> _forceAll(SharedPreferences prefs, bool value) async {
    for (final entry in _flags.entries) {
      if (entry.key.value != value) {
        entry.key.value = value;
        await prefs.setBool(_key(entry.value), value);
      }
    }
  }
}

// #***! правило авто-загрузки одного вида медиа в конкретном чате:
// исключение чата (если задано) перекрывает общую настройку вида чата.
// каждый баббл читает value и слушает listenable — они реагируют и на
// смену общих настроек, и на смену исключения этого чата
class AutoDownloadRule {
  AutoDownloadRule._(this.accountId, this.chatId, this.chatType, this.media);

  factory AutoDownloadRule.photo({
    required int accountId,
    int? chatId,
    required String chatType,
  }) =>
      AutoDownloadRule._(accountId, chatId, chatType, AutoDownloadMedia.photo);

  factory AutoDownloadRule.video({
    required int accountId,
    int? chatId,
    required String chatType,
  }) =>
      AutoDownloadRule._(accountId, chatId, chatType, AutoDownloadMedia.video);

  factory AutoDownloadRule.voice({
    required int accountId,
    int? chatId,
    required String chatType,
  }) =>
      AutoDownloadRule._(accountId, chatId, chatType, AutoDownloadMedia.voice);

  factory AutoDownloadRule.videoNote({
    required int accountId,
    int? chatId,
    required String chatType,
  }) => AutoDownloadRule._(
    accountId,
    chatId,
    chatType,
    AutoDownloadMedia.videoNote,
  );

  final int accountId;
  final int? chatId;
  final String chatType;
  final AutoDownloadMedia media;

  AutoDownloadScope get _scope => KometSettings.autoDownloadOf(chatType);

  ChatAutoDownloadOverride? get _override => chatId == null
      ? null
      : ChatAutoDownloadStore.instance.get(accountId, chatId!);

  bool? get _overrideValue => switch (media) {
    AutoDownloadMedia.photo => _override?.photo,
    AutoDownloadMedia.video => _override?.video,
    AutoDownloadMedia.voice => _override?.voice,
    AutoDownloadMedia.videoNote => _override?.videoNote,
  };

  ValueNotifier<bool> get _scopeFlag => switch (media) {
    AutoDownloadMedia.photo => _scope.photo,
    AutoDownloadMedia.video => _scope.video,
    AutoDownloadMedia.voice => _scope.voice,
    AutoDownloadMedia.videoNote => _scope.videoNote,
  };

  // #***! исключение чата важнее, без него действует настройка вида чата
  bool get value => _overrideValue ?? _scopeFlag.value;

  // #***! слушаем и флаг вида чата, и ревизию стора исключений
  Listenable get listenable =>
      Listenable.merge([_scopeFlag, ChatAutoDownloadStore.instance.revision]);

  @override
  bool operator ==(Object other) =>
      other is AutoDownloadRule &&
      other.accountId == accountId &&
      other.chatId == chatId &&
      other.chatType == chatType &&
      other.media == media;

  @override
  int get hashCode => Object.hash(accountId, chatId, chatType, media);
}

// #***! фирменные настройки комета которых нет в оригинале
class KometSettings {
  static const _kViewDeleted = 'komet_view_deleted';
  static const _kViewRedacted = 'komet_view_redacted';
  static const _kFullTimestamp = 'komet_full_timestamp';
  static const _kShowForward = 'komet_show_forward';
  static const _kShowTypingTime = 'komet_show_typing_time';
  static const _kGhostMode = 'komet_ghost_mode';
  static const _kAntiRead = 'komet_anti_read';
  static const _kAntiStoryView = 'komet_anti_story_view';
  static const _kSelfOnlineCheck = 'komet_self_online_check';
  static const _kHideAllChatsFolder = 'komet_hide_all_chats_folder';
  static const _kShowHiddenChats = 'komet_show_hidden_chats';
  static const _kArchiveOnPull = 'komet_archive_on_pull';
  // #***! старые глобальные ключи авто-загрузки, читаются только для миграции
  static const _kAutoDownloadPhoto = 'komet_auto_download_photo';
  static const _kAutoDownloadVideo = 'komet_auto_download_video';
  static const _kAutoDownloadVoice = 'komet_auto_download_voice';
  static const _kAutoDownloadVideoNote = 'komet_auto_download_video_note';
  static const _kAutoplayVideo = 'komet_autoplay_video';
  static const _kAutoplayGif = 'komet_autoplay_gif';
  static const _kAutoplayAnimoji = 'komet_autoplay_animoji';
  static const _kAutoplayVideoNote = 'komet_autoplay_video_note';
  static const _kRecordDebugLogs = 'komet_record_debug_logs';
  static const _kHideChannelRecommendations =
      'komet_hide_channel_recommendations';
  static const _kRecommendationsHiddenIn = 'komet_recommendations_hidden_in';

  // #***! каждая настройка это ValueNotifier, юишка подписана напрямую
  static final ValueNotifier<bool> viewDeleted = ValueNotifier(false);
  static final ValueNotifier<bool> viewRedacted = ValueNotifier(false);
  static final ValueNotifier<bool> fullTimestamp = ValueNotifier(false);
  static final ValueNotifier<bool> showForward = ValueNotifier(false);
  static final ValueNotifier<bool> showTypingTime = ValueNotifier(false);
  static final ValueNotifier<bool> ghostMode = ValueNotifier(false);
  static final ValueNotifier<bool> antiRead = ValueNotifier(false);
  static final ValueNotifier<bool> antiStoryView = ValueNotifier(false);
  static final ValueNotifier<bool> selfOnlineCheck = ValueNotifier(true);
  static final ValueNotifier<bool> hideAllChatsFolder = ValueNotifier(false);
  static final ValueNotifier<bool> showHiddenChats = ValueNotifier(false);
  static final ValueNotifier<bool> archiveOnPull = ValueNotifier(false);
  // #***! авто-загрузка медиа настраивается отдельно для каждого вида чата
  static final Map<AutoDownloadKind, AutoDownloadScope> autoDownloadScopes = {
    for (final kind in AutoDownloadKind.values) kind: AutoDownloadScope(kind),
  };

  // #***! скоуп авто-загрузки по серверному типу чата
  static AutoDownloadScope autoDownloadOf(String chatType) =>
      autoDownloadScopes[autoDownloadKindOf(chatType)]!;

  static final ValueNotifier<bool> autoplayVideo = ValueNotifier(true);
  static final ValueNotifier<bool> autoplayGif = ValueNotifier(true);
  static final ValueNotifier<bool> autoplayAnimoji = ValueNotifier(true);
  static final ValueNotifier<bool> autoplayVideoNote = ValueNotifier(true);
  static final ValueNotifier<bool> recordDebugLogs = ValueNotifier(true);
  static final ValueNotifier<bool> hideChannelRecommendations = ValueNotifier(
    false,
  );
  static final ValueNotifier<Set<int>> recommendationsHiddenIn = ValueNotifier(
    const {},
  );

  // #***! читаем всё разом на старте
  static Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    // #***! просмотр удалённого только вне store сборки
    viewDeleted.value =
        BuildProfile.hiddenContentViewers &&
        (prefs.getBool(_kViewDeleted) ?? false);
    viewRedacted.value =
        BuildProfile.hiddenContentViewers &&
        (prefs.getBool(_kViewRedacted) ?? false);
    fullTimestamp.value = prefs.getBool(_kFullTimestamp) ?? false;
    showForward.value = prefs.getBool(_kShowForward) ?? false;
    showTypingTime.value = prefs.getBool(_kShowTypingTime) ?? false;
    ghostMode.value =
        BuildProfile.stealthPresence && (prefs.getBool(_kGhostMode) ?? false);
    antiRead.value =
        BuildProfile.stealthPresence && (prefs.getBool(_kAntiRead) ?? false);
    antiStoryView.value =
        BuildProfile.stealthPresence &&
        (prefs.getBool(_kAntiStoryView) ?? false);
    selfOnlineCheck.value = prefs.getBool(_kSelfOnlineCheck) ?? true;
    hideAllChatsFolder.value = prefs.getBool(_kHideAllChatsFolder) ?? false;
    showHiddenChats.value = prefs.getBool(_kShowHiddenChats) ?? false;
    archiveOnPull.value = prefs.getBool(_kArchiveOnPull) ?? false;
    // #***! авто-загрузка: старые глобальные флаги раздаём всем видам чатов
    for (final scope in autoDownloadScopes.values) {
      await scope.load(
        prefs,
        legacyPhoto: prefs.getBool(_kAutoDownloadPhoto),
        legacyVideo: prefs.getBool(_kAutoDownloadVideo),
        legacyVoice: prefs.getBool(_kAutoDownloadVoice),
        legacyVideoNote: prefs.getBool(_kAutoDownloadVideoNote),
      );
    }
    autoplayVideo.value = prefs.getBool(_kAutoplayVideo) ?? true;
    autoplayGif.value = prefs.getBool(_kAutoplayGif) ?? true;
    autoplayAnimoji.value = prefs.getBool(_kAutoplayAnimoji) ?? true;
    autoplayVideoNote.value = prefs.getBool(_kAutoplayVideoNote) ?? true;
    recordDebugLogs.value = prefs.getBool(_kRecordDebugLogs) ?? true;
    hideChannelRecommendations.value =
        prefs.getBool(_kHideChannelRecommendations) ?? false;
    recommendationsHiddenIn.value = {
      for (final raw
          in prefs.getStringList(_kRecommendationsHiddenIn) ?? const [])
        ?int.tryParse(raw),
    };
  }

  // #***! дальше по сеттеру на настройку, память потом диск
  static Future<void> setViewDeleted(bool value) async {
    viewDeleted.value = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kViewDeleted, value);
  }

  static Future<void> setViewRedacted(bool value) async {
    viewRedacted.value = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kViewRedacted, value);
  }

  static Future<void> setFullTimestamp(bool value) async {
    fullTimestamp.value = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kFullTimestamp, value);
  }

  static Future<void> setShowForward(bool value) async {
    showForward.value = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kShowForward, value);
  }

  static Future<void> setShowTypingTime(bool value) async {
    showTypingTime.value = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kShowTypingTime, value);
  }

  // #***! невидимка влияет на пинг, с interactive false сервер не считает нас онлайн
  static Future<void> setGhostMode(bool value) async {
    ghostMode.value = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kGhostMode, value);
  }

  static Future<void> setAntiRead(bool value) async {
    antiRead.value = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kAntiRead, value);
  }

  static Future<void> setAntiStoryView(bool value) async {
    antiStoryView.value = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kAntiStoryView, value);
  }

  static Future<void> setSelfOnlineCheck(bool value) async {
    selfOnlineCheck.value = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kSelfOnlineCheck, value);
  }

  static Future<void> setHideAllChatsFolder(bool value) async {
    hideAllChatsFolder.value = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kHideAllChatsFolder, value);
  }

  static Future<void> setAutoplayVideo(bool value) =>
      _setFlag(autoplayVideo, _kAutoplayVideo, value);

  static Future<void> setAutoplayGif(bool value) =>
      _setFlag(autoplayGif, _kAutoplayGif, value);

  static Future<void> setAutoplayAnimoji(bool value) =>
      _setFlag(autoplayAnimoji, _kAutoplayAnimoji, value);

  static Future<void> setAutoplayVideoNote(bool value) =>
      _setFlag(autoplayVideoNote, _kAutoplayVideoNote, value);

  static Future<void> _setFlag(
    ValueNotifier<bool> notifier,
    String key,
    bool value,
  ) async {
    notifier.value = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(key, value);
  }

  static Future<void> setArchiveOnPull(bool value) async {
    archiveOnPull.value = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kArchiveOnPull, value);
  }

  static Future<void> setShowHiddenChats(bool value) async {
    showHiddenChats.value = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kShowHiddenChats, value);
  }

  static Future<void> setRecordDebugLogs(bool value) async {
    recordDebugLogs.value = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kRecordDebugLogs, value);
  }

  static Future<void> setHideChannelRecommendations(bool value) =>
      _setFlag(hideChannelRecommendations, _kHideChannelRecommendations, value);

  static Future<void> hideRecommendationsIn(int chatId) async {
    final hidden = recommendationsHiddenIn.value;
    if (hidden.contains(chatId)) return;
    final next = {...hidden, chatId};
    recommendationsHiddenIn.value = next;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_kRecommendationsHiddenIn, [
      for (final id in next) '$id',
    ]);
  }
}
