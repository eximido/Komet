import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:komet/backend/modules/messages.dart';
import 'package:komet/core/config/komet_settings.dart';
import 'package:komet/core/media/auto_download_gate.dart';
import 'package:komet/core/storage/chat_auto_download_store.dart';
import 'package:komet/core/utils/media_cache.dart';
import 'package:komet/core/utils/media_cache_names.dart';
import 'package:komet/frontend/screens/chats/chat/view/chat_preview_line.dart';
import 'package:komet/frontend/widgets/attachment/bubbles/network_photo.dart';
import 'package:komet/frontend/widgets/message_bubble.dart';
import 'package:komet/l10n/app_localizations.dart';
import 'package:komet/models/attachment.dart';
import 'package:komet/models/chat_preview_media.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';

const int _myId = 1;
const int _chatId = 2;
const String _chatType = 'DIALOG';
const String _photoUrl = 'https://cdn.invalid/manual-photo.jpg';

class _SyntheticPathProvider extends PathProviderPlatform
    with MockPlatformInterfaceMixin {
  final String directory;

  _SyntheticPathProvider(this.directory);

  @override
  Future<String?> getApplicationSupportPath() async => directory;

  @override
  Future<String?> getTemporaryPath() async => directory;
}

// #***! Image.file с cacheWidth оборачивается в ResizeImage — смотрим насквозь
bool _isFromFile(Image image) {
  final provider = image.image;
  if (provider is FileImage) return true;
  return provider is ResizeImage && provider.imageProvider is FileImage;
}

CachedMessage _photoMessage() => CachedMessage(
  id: '1',
  accountId: _myId,
  chatId: _chatId,
  senderId: 7,
  time: DateTime(2026, 1, 1, 12).millisecondsSinceEpoch,
  status: 'sent',
  attachments: const [
    PhotoAttachment(baseUrl: _photoUrl, width: 320, height: 240),
  ],
);

Widget _host(Widget child) => MaterialApp(
  locale: const Locale('ru'),
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: Scaffold(body: Align(alignment: Alignment.topLeft, child: child)),
);

Future<void> _pumpBubble(WidgetTester tester) async {
  tester.view.physicalSize = const Size(780, 2400);
  tester.view.devicePixelRatio = 2;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    _host(
      MessageBubble(
        message: _photoMessage(),
        isMe: false,
        myId: _myId,
        chatType: _chatType,
      ),
    ),
  );
  await tester.pump();
}

/// Пишет «фото» в постоянный кэш под именем урла — как будто
/// пользователь загрузил его тапом до перезапуска.
File _seedPersistedPhoto(Directory dir) {
  final cacheDir = Directory('${dir.path}/media_cache')
    ..createSync(recursive: true);
  final file = File('${cacheDir.path}/${networkPhotoCacheName(_photoUrl)}');
  file.writeAsBytesSync(_pixelBytes());
  return file;
}

List<int> _pixelBytes() => const [
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D,
  0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
  0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4, 0x89, 0x00, 0x00, 0x00,
  0x0D, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00,
  0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00, 0x00, 0x00, 0x00, 0x49,
  0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82,
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final dialogScope = KometSettings.autoDownloadOf(_chatType);
  late Directory directory;
  late PathProviderPlatform previousProvider;

  setUp(() async {
    SharedPreferences.setMockInitialValues(const {});
    await ChatAutoDownloadStore.instance.clearAll();
    AutoDownloadGate.reset();
    MediaCache.resetForTesting();
    directory = Directory.systemTemp.createTempSync(
      'photo_persistent_cache_test',
    );
    previousProvider = PathProviderPlatform.instance;
    PathProviderPlatform.instance = _SyntheticPathProvider(directory.path);
    dialogScope.photo.value = true;
    dialogScope.video.value = true;
    // #***! по умолчанию загрузка отдает готовый файл без диска и сети:
    // каждый тест знает, что проверяет, и подменяет при необходимости
    NetworkPhoto.resetForTesting();
    NetworkPhoto.fetch = (cacheName, _) async =>
        File('${directory.path}/media_cache/$cacheName');
  });

  tearDown(() async {
    PathProviderPlatform.instance = previousProvider;
    if (directory.existsSync()) directory.deleteSync(recursive: true);
  });

  group('имя в постоянном кэше', () {
    test('детерминировано и с фото-префиксом', () {
      final name = networkPhotoCacheName(_photoUrl);
      expect(name, networkPhotoCacheName(_photoUrl));
      expect(name.startsWith('img_'), isTrue);
      expect(name.endsWith('.jpg'), isTrue);
    });

    test('не пересекается с именем по photoId', () {
      final photo = PhotoAttachment(photoId: 7, baseUrl: _photoUrl);
      expect(
        networkPhotoCacheName(_photoUrl),
        isNot(photoCacheName(photo, _photoUrl)),
      );
    });

    test('считается фото в хранилище', () {
      expect(
        mediaCacheKindOf(networkPhotoCacheName(_photoUrl)),
        MediaCacheKind.photo,
      );
    });
  });

  group('перенос из временного хранилища', () {
    test('import копирует файл в постоянный кэш', () async {
      final source = File('${directory.path}/tmp_source.jpg')
        ..writeAsBytesSync(_pixelBytes());

      final imported = await MediaCache.import(
        networkPhotoCacheName(_photoUrl),
        source,
      );

      expect(imported, isNotNull);
      expect(imported!.path, endsWith(networkPhotoCacheName(_photoUrl)));
      expect(
        await File(
          '${directory.path}/media_cache/${networkPhotoCacheName(_photoUrl)}',
        ).exists(),
        isTrue,
      );
      // повторный import не создаёт вторую копию
      final again = await MediaCache.import(
        networkPhotoCacheName(_photoUrl),
        source,
      );
      expect(again!.path, imported.path);
    });
  });

  group('гейт находит фото в постоянном кэше', () {
    test('файл на месте — загрузка разрешена без тапа', () async {
      _seedPersistedPhoto(directory);

      expect(AutoDownloadGate.allows(false, _photoUrl), isFalse);
      await Future<void>.delayed(const Duration(milliseconds: 300));

      expect(AutoDownloadGate.allows(false, _photoUrl), isTrue);
      expect(AutoDownloadGate.awaitsTap(false, _photoUrl), isFalse);
    });

    test('файла нет — ждём тапа', () async {
      // #***! без файла проверяем только постоянный кэш: обращение
      // к временному в тестах ни к чему, там нет платформенных каналов
      AutoDownloadGate.isCached =
          (key) async => await MediaCache.existing(networkPhotoCacheName(key)) != null;

      AutoDownloadGate.allows(false, _photoUrl);
      await Future<void>.delayed(const Duration(milliseconds: 300));

      expect(AutoDownloadGate.awaitsTap(false, _photoUrl), isTrue);
    });
  });

  group('NetworkPhoto', () {
    testWidgets('файл в кэше показывается сразу', (tester) async {
      final file = _seedPersistedPhoto(directory);

      await tester.pumpWidget(
        _host(
          NetworkPhoto(
            url: _photoUrl,
            cacheName: networkPhotoCacheName(_photoUrl),
            width: 100,
            height: 100,
            memWidth: 200,
            memHeight: 200,
            fallback: (_) => const Text('fallback'),
          ),
        ),
      );
      await tester.pump();

      final image = tester.widget<Image>(find.byType(Image));
      // #***! Image.file с cacheWidth оборачивается в ResizeImage
      final provider = image.image is ResizeImage
          ? (image.image as ResizeImage).imageProvider
          : image.image;
      expect(provider, isA<FileImage>());
      expect((provider as FileImage).file.path, file.path);
    });

    testWidgets('пока качается — превью, после — файл', (tester) async {
      final pending = Completer<File?>();
      NetworkPhoto.fetch = (_, _) => pending.future;

      await tester.pumpWidget(
        _host(
          NetworkPhoto(
            url: _photoUrl,
            cacheName: networkPhotoCacheName(_photoUrl),
            width: 100,
            height: 100,
            memWidth: 200,
            memHeight: 200,
            fallback: (_) => const Text('fallback'),
          ),
        ),
      );
      expect(find.text('fallback'), findsOneWidget);

      final file = _seedPersistedPhoto(directory);
      pending.complete(file);
      await tester.pump();

      expect(find.byType(Image), findsOneWidget);
      expect(find.text('fallback'), findsNothing);
    });

    testWidgets('сбой повторяет загрузку', (tester) async {
      var calls = 0;
      NetworkPhoto.fetch = (_, _) async {
        calls++;
        return calls == 1 ? null : _seedPersistedPhoto(directory);
      };

      await tester.pumpWidget(
        _host(
          NetworkPhoto(
            url: _photoUrl,
            cacheName: networkPhotoCacheName(_photoUrl),
            width: 100,
            height: 100,
            memWidth: 200,
            memHeight: 200,
            fallback: (_) => const Text('fallback'),
          ),
        ),
      );
      await tester.pump();
      expect(calls, 1);
      expect(find.text('fallback'), findsOneWidget);

      await tester.pump(const Duration(seconds: 2));
      expect(calls, 2);
      await tester.pump();
      expect(find.byType(Image), findsOneWidget);
    });
  });

  group('пузырь после перезапуска', () {
    testWidgets(
      'руками загруженное до перезапуска фото показывается сразу, без кнопки',
      (tester) async {
        dialogScope.photo.value = false;
        _seedPersistedPhoto(directory);
        // #***! прогреваем гейт в реальной зоне: файловый ввод-вывод
        // не прокачивается из FakeAsync виджет-теста
        await tester.runAsync(() async {
          AutoDownloadGate.allows(false, _photoUrl);
          await Future<void>.delayed(const Duration(milliseconds: 300));
        });

        await _pumpBubble(tester);

        // ручная загрузка это тот же файл в постоянном кэше — гейт
        // находит его и не показывает кнопку загрузки
        expect(find.byIcon(Symbols.download), findsNothing);
        final images = tester.widgetList<Image>(find.byType(Image));
        expect(
          images.any(_isFromFile),
          isTrue,
          reason: 'фото должно рисоваться из постоянного кэша',
        );
      },
    );

    testWidgets('файла в кэше нет — кнопка загрузки на месте', (
      tester,
    ) async {
      dialogScope.photo.value = false;
      AutoDownloadGate.isCached = (_) async => false;

      await _pumpBubble(tester);
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.byIcon(Symbols.download), findsOneWidget);
    });

    testWidgets('тап по кнопке качает фото в постоянный кэш', (
      tester,
    ) async {
      dialogScope.photo.value = false;
      AutoDownloadGate.isCached = (_) async => false;
      var fetched = '';
      NetworkPhoto.fetch = (cacheName, _) async {
        fetched = cacheName;
        return _seedPersistedPhoto(directory);
      };

      await _pumpBubble(tester);
      await tester.pump(const Duration(milliseconds: 300));

      await tester.tap(find.byIcon(Symbols.download));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(fetched, networkPhotoCacheName(_photoUrl));
      final images = tester.widgetList<Image>(find.byType(Image));
      expect(images.any(_isFromFile), isTrue);
      await tester.runAsync(() async {
        expect(
          await MediaCache.existing(networkPhotoCacheName(_photoUrl)),
          isNotNull,
        );
      });
    });
  });

  group('миниатюра списка чатов', () {
    testWidgets('берётся из постоянного кэша без скачивания', (tester) async {
      dialogScope.photo.value = false;
      _seedPersistedPhoto(directory);
      await tester.runAsync(() async {
        AutoDownloadGate.allows(false, _photoUrl);
        await Future<void>.delayed(const Duration(milliseconds: 300));
      });

      await tester.pumpWidget(
        _host(
          ChatPreviewLine(
            text: 'Изображение',
            style: const TextStyle(fontSize: 14),
            media: const ChatPreviewMedia(
              kind: ChatPreviewKind.photo,
              thumbs: [ChatPreviewThumb(source: _photoUrl)],
              label: 'Изображение',
            ),
            networkThumbRule: (video) => AutoDownloadRule.photo(
              accountId: _myId,
              chatId: _chatId,
              chatType: _chatType,
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));

      final image = tester.widget<Image>(find.byType(Image));
      expect(image.image, isA<ResizeImage>());
      final provider = image.image as ResizeImage;
      expect(provider.imageProvider, isA<FileImage>());
    });
  });
}
