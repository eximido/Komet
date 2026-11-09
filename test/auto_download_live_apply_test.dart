import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:komet/backend/modules/messages.dart';
import 'package:komet/core/config/komet_settings.dart';
import 'package:komet/core/media/auto_download_gate.dart';
import 'package:komet/core/storage/chat_auto_download_store.dart';
import 'package:komet/core/utils/download_progress.dart';
import 'package:komet/frontend/screens/chats/chat/view/chat_preview_line.dart';
import 'package:komet/frontend/widgets/message_bubble.dart';
import 'package:komet/l10n/app_localizations.dart';
import 'package:komet/models/attachment.dart';
import 'package:komet/models/chat_preview_media.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';

const String _me = '1';
const int _myId = 1;
const int _chatId = 2;
const String _chatType = 'DIALOG';

const String _photoUrl = 'https://cdn.invalid/last-photo.jpg';
const String _videoUrl = 'https://cdn.invalid/last-video.jpg';

const TextStyle _style = TextStyle(fontSize: 14, height: 1.2);

class _SyntheticPathProvider extends PathProviderPlatform
    with MockPlatformInterfaceMixin {
  final String directory;

  _SyntheticPathProvider(this.directory);

  @override
  Future<String?> getApplicationSupportPath() async => directory;

  @override
  Future<String?> getTemporaryPath() async => directory;
}

AutoDownloadRule? Function(bool video) _ruleOf(
  int accountId,
  int chatId,
  String chatType,
) => (video) => video
    ? AutoDownloadRule.video(
        accountId: accountId,
        chatId: chatId,
        chatType: chatType,
      )
    : AutoDownloadRule.photo(
        accountId: accountId,
        chatId: chatId,
        chatType: chatType,
      );

Widget _host(Widget child) => MaterialApp(
  home: Scaffold(body: Center(child: child)),
);

Widget _thumbLine({bool video = false}) => ChatPreviewLine(
  text: video ? 'Видео' : 'Изображение',
  style: _style,
  media: ChatPreviewMedia(
    kind: video ? ChatPreviewKind.video : ChatPreviewKind.photo,
    thumbs: [ChatPreviewThumb(source: video ? _videoUrl : _photoUrl, video: video)],
    label: video ? 'Видео' : 'Изображение',
  ),
  networkThumbRule: _ruleOf(_myId, _chatId, _chatType),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final dialogScope = KometSettings.autoDownloadOf(_chatType);

  setUp(() async {
    SharedPreferences.setMockInitialValues(const {});
    await ChatAutoDownloadStore.instance.clearAll();
    AutoDownloadGate.reset();
    AutoDownloadGate.isCached = (_) async => false;
    dialogScope.photo.value = true;
    dialogScope.video.value = true;
    dialogScope.voice.value = true;
    dialogScope.videoNote.value = true;
  });

  // #***! дебаунс записи стора — 400 мс таймер — тесты гасят его сами
  // через flush() перед концом тела

  group('миниатюра списка чатов', () {
    testWidgets('при выключенном правиле фото не качается', (tester) async {
      dialogScope.photo.value = false;

      await tester.pumpWidget(_host(_thumbLine()));
      await tester.pump(const Duration(milliseconds: 30));

      expect(find.byType(Image), findsNothing,
          reason: 'сетевую миниатюру нельзя рендерить без разрешения');
      expect(find.byIcon(Symbols.image), findsOneWidget);
    });

    testWidgets('при включённом правиле миниатюра рендерится', (tester) async {
      await tester.pumpWidget(_host(_thumbLine()));
      await tester.pump(const Duration(milliseconds: 30));

      expect(find.byType(Image), findsOneWidget);
    });

    testWidgets('видео-миниатюра живёт по правилу видео', (tester) async {
      dialogScope.photo.value = true;
      dialogScope.video.value = false;

      await tester.pumpWidget(_host(_thumbLine(video: true)));
      await tester.pump(const Duration(milliseconds: 30));

      expect(find.byType(Image), findsNothing);
      expect(find.byIcon(Symbols.movie), findsOneWidget);
    });

    testWidgets('уже скачанная миниатюра показывается и без правила',
        (tester) async {
      dialogScope.photo.value = false;
      AutoDownloadGate.isCached =
          (key) async => key == _photoUrl;

      await tester.pumpWidget(_host(_thumbLine()));
      expect(
        find.byType(Image),
        findsNothing,
        reason: 'до ответа пробы кэша показываем иконку',
      );
      await tester.pump(const Duration(milliseconds: 30));

      expect(find.byType(Image), findsOneWidget);
      expect(find.byIcon(Symbols.image), findsNothing);
    });

    testWidgets('включение правила на лету догружает миниатюру',
        (tester) async {
      dialogScope.photo.value = false;
      await tester.pumpWidget(_host(_thumbLine()));
      await tester.pump(const Duration(milliseconds: 30));
      expect(find.byType(Image), findsNothing);

      dialogScope.photo.value = true;
      await tester.pump();

      expect(find.byType(Image), findsOneWidget);
    });

    testWidgets('исключение чата перекрывает общую настройку', (tester) async {
      await ChatAutoDownloadStore.instance.set(
        _myId,
        _chatId,
        const ChatAutoDownloadOverride(photo: false),
      );

      await tester.pumpWidget(_host(_thumbLine()));
      await tester.pump(const Duration(milliseconds: 30));

      expect(find.byType(Image), findsNothing,
          reason: 'исключение запрещает качать миниатюру');

      await ChatAutoDownloadStore.instance.set(
        _myId,
        _chatId,
        const ChatAutoDownloadOverride(photo: true),
      );
      dialogScope.photo.value = false;
      await tester.pump(const Duration(milliseconds: 30));

      expect(find.byType(Image), findsOneWidget,
          reason: 'исключение разрешает, хотя вид чата выключен');

      // #***! гасим дебаунс записи, иначе останется висящий таймер
      await ChatAutoDownloadStore.instance.flush();
    });
  });

  group('голосовые догружаются на лету', () {
    late Directory directory;
    late PathProviderPlatform previousProvider;

    setUp(() {
      directory = Directory.systemTemp.createTempSync(
        'auto_download_live_apply_test',
      );
      previousProvider = PathProviderPlatform.instance;
      PathProviderPlatform.instance = _SyntheticPathProvider(directory.path);
    });

    tearDown(() async {
      PathProviderPlatform.instance = previousProvider;
      if (directory.existsSync()) {
        directory.deleteSync(recursive: true);
      }
    });

    Future<void> pumpVoice(WidgetTester tester) async {
      tester.view.physicalSize = const Size(780, 2400);
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('ru'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: Align(
              alignment: Alignment.topLeft,
              child: MessageBubble(
                message: CachedMessage(
                  id: _me,
                  accountId: _myId,
                  chatId: _chatId,
                  senderId: 7,
                  time: DateTime(2026, 1, 1, 12).millisecondsSinceEpoch,
                  status: 'sent',
                  attachments: const [
                    AudioAttachment(
                      audioId: 33,
                      duration: 4200,
                      baseUrl: 'https://cdn.invalid/voice.ogg',
                    ),
                  ],
                ),
                isMe: false,
                myId: _myId,
                chatType: _chatType,
              ),
            ),
          ),
        ),
      );
      await tester.pump();
    }

    testWidgets('выключенное правило не трогает сеть', (tester) async {
      dialogScope.voice.value = false;
      final progress = MediaDownloadProgress.notifier('33.ogg');
      final seen = <double?>[];
      progress.addListener(() => seen.add(progress.value));

      await pumpVoice(tester);
      await tester.pump(const Duration(milliseconds: 50));

      expect(
        seen.where((value) => value != null),
        isEmpty,
        reason: 'префетч не должен стартовать при выключенном правиле',
      );
    });

    testWidgets('включение правила на лету запускает префетч', (tester) async {
      dialogScope.voice.value = false;
      final progress = MediaDownloadProgress.notifier('33.ogg');
      final seen = <double?>[];
      progress.addListener(() => seen.add(progress.value));

      await pumpVoice(tester);
      await tester.pump(const Duration(milliseconds: 50));
      expect(seen.where((value) => value != null), isEmpty);

      // #***! и переключение флага, и файловый ввод-вывод кэша должны идти
      // в реальной зоне — из FakeAsync настоящий IO не прокачивается
      await tester.runAsync(() async {
        dialogScope.voice.value = true;
        await Future<void>.delayed(const Duration(milliseconds: 400));
      });
      await tester.pump();

      expect(seen, contains(0.0),
          reason: 'правило включили — голосовое начало скачиваться');

      // #***! неудавшийся префетч показывает уведомление с таймером
      // автоскрытия — прокачиваем, чтобы таймер отработал
      await tester.pump(const Duration(milliseconds: 2400));
    });
  });
}
