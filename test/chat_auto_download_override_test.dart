import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:komet/core/config/komet_settings.dart';
import 'package:komet/core/storage/chat_auto_download_store.dart';
import 'package:komet/frontend/screens/chats/chat_auto_download_settings_screen.dart';
import 'package:komet/l10n/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  // #***! стор и скоупы — глобальное состояние, чистим между тестами
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await ChatAutoDownloadStore.instance.clearAll();
    for (final scope in KometSettings.autoDownloadScopes.values) {
      scope.master.value = true;
      scope.photo.value = true;
      scope.video.value = true;
      scope.voice.value = true;
      scope.videoNote.value = true;
    }
  });

  group('ChatAutoDownloadOverride', () {
    test('withValue replaces exactly one flag', () {
      const override = ChatAutoDownloadOverride(photo: true, voice: false);
      final changed = override.withValue(AutoDownloadMedia.video, true);
      expect(changed.photo, isTrue);
      expect(changed.video, isTrue);
      expect(changed.voice, isFalse);
      expect(changed.videoNote, isNull);
    });

    test('withValue null unsets the flag and empties the override', () {
      const override = ChatAutoDownloadOverride(photo: true);
      final emptied = override.withValue(AutoDownloadMedia.photo, null);
      expect(emptied.photo, isNull);
      expect(emptied.isEmpty, isTrue);
      expect(const ChatAutoDownloadOverride().isEmpty, isTrue);
      expect(const ChatAutoDownloadOverride(photo: false).isEmpty, isFalse);
    });
  });

  group('ChatAutoDownloadStore', () {
    test('keeps overrides per chat and persists them as one entry', () async {
      final store = ChatAutoDownloadStore.instance;
      await store.set(
        1,
        7,
        const ChatAutoDownloadOverride(photo: false, video: true),
      );
      await store.set(1, 9, const ChatAutoDownloadOverride(voice: true));

      expect(store.get(1, 7)?.photo, isFalse);
      expect(store.get(1, 7)?.video, isTrue);
      expect(store.get(1, 9)?.voice, isTrue);
      expect(store.get(1, 9)?.photo, isNull);

      await store.flush();
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('chat_auto_download_overrides');
      expect(raw, isNotNull);
      final decoded = jsonDecode(raw!) as Map<String, dynamic>;
      expect(decoded.keys, containsAll(['1/7', '1/9']));
      expect((decoded['1/7'] as Map)['photo'], isFalse);
      expect((decoded['1/9'] as Map)['voice'], isTrue);
    });

    test('drops the entry once every value is unset', () async {
      final store = ChatAutoDownloadStore.instance;
      await store.set(1, 7, const ChatAutoDownloadOverride(photo: true));
      expect(store.get(1, 7), isNotNull);

      await store.set(
        1,
        7,
        const ChatAutoDownloadOverride().withValue(
          AutoDownloadMedia.photo,
          null,
        ),
      );
      expect(store.get(1, 7), isNull);
    });

    test('clearForChat removes only that chat', () async {
      final store = ChatAutoDownloadStore.instance;
      await store.set(1, 7, const ChatAutoDownloadOverride(photo: false));
      await store.set(1, 8, const ChatAutoDownloadOverride(video: false));

      await store.clearForChat(1, 7);
      expect(store.get(1, 7), isNull);
      expect(store.get(1, 8)?.video, isFalse);
    });

    test('a foreign account sees no overrides', () async {
      final store = ChatAutoDownloadStore.instance;
      await store.set(1, 7, const ChatAutoDownloadOverride(photo: false));
      expect(store.get(2, 7), isNull);
      expect(store.get(0, 7), isNull);
    });
  });

  group('AutoDownloadRule', () {
    test('an override off beats the enabled kind setting', () async {
      await ChatAutoDownloadStore.instance.set(
        1,
        7,
        const ChatAutoDownloadOverride(photo: false),
      );
      final rule = AutoDownloadRule.photo(
        accountId: 1,
        chatId: 7,
        chatType: 'CHANNEL',
      );
      expect(rule.value, isFalse);
    });

    test('an override on beats the disabled kind setting', () async {
      addTearDown(
        () => KometSettings.autoDownloadOf('CHANNEL').video.value = true,
      );
      KometSettings.autoDownloadOf('CHANNEL').video.value = false;
      await ChatAutoDownloadStore.instance.set(
        1,
        7,
        const ChatAutoDownloadOverride(video: true),
      );
      final rule = AutoDownloadRule.video(
        accountId: 1,
        chatId: 7,
        chatType: 'CHANNEL',
      );
      expect(rule.value, isTrue);
      // у соседнего чата исключения нет — там действует выключенный флаг
      expect(
        AutoDownloadRule.video(
          accountId: 1,
          chatId: 8,
          chatType: 'CHANNEL',
        ).value,
        isFalse,
      );
    });

    test('without an override the kind setting applies', () async {
      addTearDown(
        () => KometSettings.autoDownloadOf('CHAT').voice.value = true,
      );
      KometSettings.autoDownloadOf('CHAT').voice.value = false;
      expect(
        AutoDownloadRule.voice(accountId: 1, chatId: 7, chatType: 'CHAT').value,
        isFalse,
      );
    });

    test(
      'a null chat id or a zero account falls back to the kind setting',
      () async {
        await ChatAutoDownloadStore.instance.set(
          1,
          7,
          const ChatAutoDownloadOverride(videoNote: false),
        );
        expect(
          AutoDownloadRule.videoNote(
            accountId: 1,
            chatId: null,
            chatType: 'DIALOG',
          ).value,
          isTrue,
        );
        expect(
          AutoDownloadRule.videoNote(
            accountId: 0,
            chatId: 7,
            chatType: 'DIALOG',
          ).value,
          isTrue,
        );
      },
    );

    test('listenable reacts to the store and to the kind flag', () async {
      var calls = 0;
      void onChanged() => calls++;
      final rule = AutoDownloadRule.voice(
        accountId: 1,
        chatId: 9,
        chatType: 'CHAT',
      );
      rule.listenable.addListener(onChanged);

      await ChatAutoDownloadStore.instance.set(
        1,
        9,
        const ChatAutoDownloadOverride(voice: false),
      );
      final afterStore = calls;
      KometSettings.autoDownloadOf('CHAT').voice.value = false;
      final afterFlag = calls;
      KometSettings.autoDownloadOf('CHAT').voice.value = true;

      rule.listenable.removeListener(onChanged);
      expect(afterStore, greaterThan(0));
      expect(afterFlag, greaterThan(afterStore));
    });

    test('rules compare by account, chat, kind and media', () {
      final a = AutoDownloadRule.photo(
        accountId: 1,
        chatId: 2,
        chatType: 'DIALOG',
      );
      final b = AutoDownloadRule.photo(
        accountId: 1,
        chatId: 2,
        chatType: 'DIALOG',
      );
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(
        a,
        isNot(
          AutoDownloadRule.video(accountId: 1, chatId: 2, chatType: 'DIALOG'),
        ),
      );
      expect(
        a,
        isNot(
          AutoDownloadRule.photo(accountId: 3, chatId: 2, chatType: 'DIALOG'),
        ),
      );
    });
  });

  group('ChatAutoDownloadSettingsScreen', () {
    Widget wrap() => MaterialApp(
      locale: const Locale('ru'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: const ChatAutoDownloadSettingsScreen(
        accountId: 1,
        chatId: 7,
        chatType: 'DIALOG',
      ),
    );

    testWidgets('starts unset with the global hints visible', (tester) async {
      await tester.pumpWidget(wrap());
      await tester.pumpAndSettle();

      expect(find.text('Не задано'), findsNWidgets(4));
      expect(find.text('Общая настройка: включена'), findsNWidgets(4));
      expect(
        find.text(
          'Исключения для этого чата перекрывают общие настройки '
          'автозагрузки. «Не задано» — использовать общие настройки.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('choosing states writes and clears the override', (
      tester,
    ) async {
      await tester.pumpWidget(wrap());
      await tester.pumpAndSettle();

      // фото → выключено, видео → включено
      await tester.tap(find.text('Выключено').first);
      await tester.pump();
      await tester.tap(find.text('Включено').at(1));
      await tester.pump();

      final store = ChatAutoDownloadStore.instance;
      expect(store.get(1, 7)?.photo, isFalse);
      expect(store.get(1, 7)?.video, isTrue);
      expect(store.get(1, 7)?.voice, isNull);

      // фото → не задано: исключение снимается, видео остаётся
      await tester.tap(find.text('Не задано').first);
      await tester.pump();
      expect(store.get(1, 7)?.photo, isNull);
      expect(store.get(1, 7)?.video, isTrue);

      // видео → не задано: исключений не осталось, запись удалена
      await tester.tap(find.text('Не задано').at(1));
      await tester.pump();
      expect(store.get(1, 7), isNull);

      await store.flush();
    });

    testWidgets('the global hint follows the chat kind setting', (
      tester,
    ) async {
      addTearDown(
        () => KometSettings.autoDownloadOf('DIALOG').photo.value = true,
      );
      await tester.pumpWidget(wrap());
      await tester.pumpAndSettle();
      expect(find.text('Общая настройка: включена'), findsNWidgets(4));

      KometSettings.autoDownloadOf('DIALOG').photo.value = false;
      await tester.pump();
      expect(find.text('Общая настройка: выключена'), findsOneWidget);
      expect(find.text('Общая настройка: включена'), findsNWidgets(3));
    });
  });
}
