import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:komet/core/config/komet_settings.dart';
import 'package:komet/frontend/screens/profile/auto_download_settings_section.dart';
import 'package:komet/l10n/app_localizations.dart';
import 'package:komet/l10n/app_localizations_ru.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  // #***! скоупы это глобальное состояние, возвращаем их к дефолту между тестами
  setUp(() {
    for (final scope in KometSettings.autoDownloadScopes.values) {
      scope.master.value = true;
      scope.photo.value = true;
      scope.video.value = true;
      scope.voice.value = true;
      scope.videoNote.value = true;
    }
  });

  group('autoDownloadKindOf', () {
    test('maps server chat types onto the three kinds', () {
      expect(autoDownloadKindOf('DIALOG'), AutoDownloadKind.dialog);
      expect(autoDownloadKindOf('CHAT'), AutoDownloadKind.group);
      expect(autoDownloadKindOf('GROUP'), AutoDownloadKind.group);
      expect(autoDownloadKindOf('CHANNEL'), AutoDownloadKind.channel);
      // #***! неизвестный тип считаем личкой, чтобы настройки не терялись
      expect(autoDownloadKindOf('SOMETHING_NEW'), AutoDownloadKind.dialog);
      expect(autoDownloadKindOf(''), AutoDownloadKind.dialog);
    });

    test('autoDownloadOf resolves one scope per chat type', () {
      expect(
        KometSettings.autoDownloadOf('CHANNEL'),
        same(KometSettings.autoDownloadScopes[AutoDownloadKind.channel]),
      );
      expect(
        KometSettings.autoDownloadOf('CHAT'),
        same(KometSettings.autoDownloadScopes[AutoDownloadKind.group]),
      );
      expect(
        KometSettings.autoDownloadOf('DIALOG'),
        same(KometSettings.autoDownloadScopes[AutoDownloadKind.dialog]),
      );
    });
  });

  group('AutoDownloadScope', () {
    test('turning the master off resets every flag and persists it', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final scope = KometSettings.autoDownloadScopes[AutoDownloadKind.channel]!;

      await scope.setMaster(false);

      // #***! выключение мастера сбрасывает всё в off: включается только
      // нужное, поэтому сброс обязан дойти и до диска
      expect(scope.master.value, isFalse);
      expect(scope.photo.value, isFalse);
      expect(scope.video.value, isFalse);
      expect(scope.voice.value, isFalse);
      expect(scope.videoNote.value, isFalse);
      expect(prefs.getBool('komet_auto_download_channel_master'), isFalse);
      expect(prefs.getBool('komet_auto_download_channel_photo'), isFalse);
      expect(prefs.getBool('komet_auto_download_channel_video_note'), isFalse);
    });

    test(
      'turning the master on forces every flag on and persists it',
      () async {
        SharedPreferences.setMockInitialValues({});
        final prefs = await SharedPreferences.getInstance();
        final scope =
            KometSettings.autoDownloadScopes[AutoDownloadKind.channel]!;

        await scope.setMaster(false);
        await scope.setPhoto(true);
        expect(scope.photo.value, isTrue);
        expect(scope.video.value, isFalse);

        await scope.setMaster(true);
        expect(scope.photo.value, isTrue);
        expect(scope.video.value, isTrue);
        expect(scope.voice.value, isTrue);
        expect(scope.videoNote.value, isTrue);
        expect(prefs.getBool('komet_auto_download_channel_master'), isTrue);
        expect(prefs.getBool('komet_auto_download_channel_photo'), isTrue);
        expect(prefs.getBool('komet_auto_download_channel_video'), isTrue);
        expect(prefs.getBool('komet_auto_download_channel_voice'), isTrue);
      },
    );

    test('flags persist per media type under a disabled master', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final scope = KometSettings.autoDownloadScopes[AutoDownloadKind.group]!;

      await scope.setMaster(false);
      await scope.setPhoto(true);
      await scope.setVoice(true);

      expect(prefs.getBool('komet_auto_download_group_master'), isFalse);
      expect(prefs.getBool('komet_auto_download_group_photo'), isTrue);
      expect(prefs.getBool('komet_auto_download_group_voice'), isTrue);
      // #***! сброс мастера записал выключенные флаги на диск, поэтому
      // после перезапуска ничего лишнего не включится само
      expect(prefs.getBool('komet_auto_download_group_video'), isFalse);
      expect(prefs.getBool('komet_auto_download_group_video_note'), isFalse);
      expect(scope.video.value, isFalse);
    });

    test('scopes do not leak flags into each other', () async {
      SharedPreferences.setMockInitialValues({});
      final dialog = KometSettings.autoDownloadScopes[AutoDownloadKind.dialog]!;
      final channel =
          KometSettings.autoDownloadScopes[AutoDownloadKind.channel]!;

      await dialog.setMaster(false);
      await dialog.setPhoto(true);

      expect(dialog.photo.value, isTrue);
      expect(dialog.master.value, isFalse);
      expect(channel.photo.value, isTrue);
      expect(channel.master.value, isTrue);
      expect(channel.video.value, isTrue);
    });

    test(
      'all re-enabled flags bring the master back on the next visit',
      () async {
        SharedPreferences.setMockInitialValues({});
        final prefs = await SharedPreferences.getInstance();
        final scope = KometSettings.autoDownloadScopes[AutoDownloadKind.group]!;

        // #***! пользователь выключил мастер и включил все опции по одному
        await scope.setMaster(false);
        await scope.setPhoto(true);
        await scope.setVideo(true);
        await scope.setVoice(true);
        await scope.setVideoNote(true);
        expect(scope.master.value, isFalse);

        // сразу мастер не включается — только при следующем заходе
        await scope.normalize();
        expect(scope.master.value, isTrue);
        expect(prefs.getBool('komet_auto_download_group_master'), isTrue);
      },
    );

    test('partially enabled flags keep the master off', () async {
      SharedPreferences.setMockInitialValues({});
      final scope = KometSettings.autoDownloadScopes[AutoDownloadKind.dialog]!;

      await scope.setMaster(false);
      await scope.setPhoto(true);
      await scope.setVoice(true);

      await scope.normalize();
      expect(scope.master.value, isFalse);
    });
  });

  group('migration', () {
    test('a fresh install keeps every master on', () async {
      SharedPreferences.setMockInitialValues({});
      await KometSettings.load();

      for (final scope in KometSettings.autoDownloadScopes.values) {
        expect(scope.master.value, isTrue);
        expect(scope.photo.value, isTrue);
        expect(scope.video.value, isTrue);
        expect(scope.voice.value, isTrue);
        expect(scope.videoNote.value, isTrue);
      }
    });

    test('legacy global switches apply to every chat kind', () async {
      SharedPreferences.setMockInitialValues({
        'komet_auto_download_photo': true,
        'komet_auto_download_video': false,
        'komet_auto_download_voice': true,
        'komet_auto_download_video_note': false,
      });
      await KometSettings.load();

      for (final scope in KometSettings.autoDownloadScopes.values) {
        expect(scope.master.value, isFalse, reason: scope.kind.name);
        expect(scope.photo.value, isTrue, reason: scope.kind.name);
        expect(scope.video.value, isFalse, reason: scope.kind.name);
        expect(scope.voice.value, isTrue, reason: scope.kind.name);
        expect(scope.videoNote.value, isFalse, reason: scope.kind.name);
      }
    });

    test('legacy everything-on keeps masters on', () async {
      SharedPreferences.setMockInitialValues({
        'komet_auto_download_photo': true,
        'komet_auto_download_video': true,
        'komet_auto_download_voice': true,
        'komet_auto_download_video_note': true,
      });
      await KometSettings.load();

      for (final scope in KometSettings.autoDownloadScopes.values) {
        expect(scope.master.value, isTrue);
      }
    });

    test('new per-kind values win over the legacy ones', () async {
      SharedPreferences.setMockInitialValues({
        'komet_auto_download_video': false,
        'komet_auto_download_channel_master': false,
        'komet_auto_download_channel_video': true,
      });
      await KometSettings.load();

      final channel =
          KometSettings.autoDownloadScopes[AutoDownloadKind.channel]!;
      final dialog = KometSettings.autoDownloadScopes[AutoDownloadKind.dialog]!;
      expect(channel.master.value, isFalse);
      expect(channel.video.value, isTrue);
      expect(dialog.master.value, isFalse);
      expect(dialog.video.value, isFalse);
    });
  });

  group('autoDownloadSummaryOf', () {
    test('lists what stays enabled under a disabled master', () {
      final l10n = AppLocalizationsRu();
      final scope = KometSettings.autoDownloadScopes[AutoDownloadKind.dialog]!;
      scope.master.value = false;
      scope.photo.value = false;
      scope.video.value = false;
      scope.voice.value = false;
      scope.videoNote.value = false;

      // #***! подпись перечисляет конкретные типы в порядке строки настроек
      expect(autoDownloadSummaryOf(l10n, scope), 'Ничего не загружается');

      scope.photo.value = true;
      expect(autoDownloadSummaryOf(l10n, scope), 'Загружаются только фото');

      scope.voice.value = true;
      expect(
        autoDownloadSummaryOf(l10n, scope),
        'Загружаются фото и голосовые',
      );

      scope.videoNote.value = true;
      expect(
        autoDownloadSummaryOf(l10n, scope),
        'Загружаются фото, голосовые и кружки',
      );

      scope.video.value = true;
      // #***! выбрано всё — сводка показывает общий текст, а не перечисление
      expect(autoDownloadSummaryOf(l10n, scope), 'Загружаются все медиафайлы');
    });

    test('the universal list works in any non-full combination', () {
      final l10n = AppLocalizationsRu();
      final scope = KometSettings.autoDownloadScopes[AutoDownloadKind.group]!;
      scope.master.value = false;
      scope.photo.value = false;
      scope.video.value = false;
      scope.voice.value = false;
      scope.videoNote.value = false;

      // #***! выбранное кроме последнего склеивается через запятую,
      // последнее добавляется союзом «и» из локализации
      scope.video.value = true;
      scope.videoNote.value = true;
      expect(autoDownloadSummaryOf(l10n, scope), 'Загружаются видео и кружки');

      scope.photo.value = true;
      expect(
        autoDownloadSummaryOf(l10n, scope),
        'Загружаются фото, видео и кружки',
      );

      scope.voice.value = true;
      expect(autoDownloadSummaryOf(l10n, scope), 'Загружаются все медиафайлы');

      scope.photo.value = false;
      scope.voice.value = false;
      expect(autoDownloadSummaryOf(l10n, scope), 'Загружаются видео и кружки');
    });
  });

  group('AutoDownloadSettingsSection', () {
    Widget wrap() => MaterialApp(
      locale: const Locale('ru'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: const Scaffold(body: AutoDownloadSettingsSection()),
    );

    testWidgets('turning the master off expands an all-off menu', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({});
      final dialog = KometSettings.autoDownloadScopes[AutoDownloadKind.dialog]!;

      await tester.pumpWidget(wrap());

      // #***! при включённом мастере меню скрыто, видна только подпись
      expect(find.text('Загружаются все медиафайлы'), findsNWidgets(3));
      expect(find.text('Фото'), findsNothing);
      expect(find.text('Кружки'), findsNothing);

      // выключаем мастер личных чатов первым переключателем
      await tester.tap(find.byType(Switch).first);
      await tester.pumpAndSettle();
      expect(dialog.master.value, isFalse);

      // меню раскрылось само, и все опции в нём выключены
      expect(find.text('Фото'), findsOneWidget);
      expect(find.text('Видео'), findsOneWidget);
      expect(find.text('Голосовые'), findsOneWidget);
      expect(find.text('Кружки'), findsOneWidget);
      expect(dialog.photo.value, isFalse);
      expect(dialog.video.value, isFalse);
      expect(dialog.voice.value, isFalse);
      expect(dialog.videoNote.value, isFalse);

      // включаем только нужное, остальное остаётся выключенным
      await tester.tap(find.text('Фото'));
      await tester.pumpAndSettle();
      expect(dialog.photo.value, isTrue);
      expect(dialog.video.value, isFalse);

      // возвращаем мастер — всё снова включено и меню скрыто
      await tester.tap(find.byType(Switch).first);
      await tester.pumpAndSettle();
      expect(dialog.photo.value, isTrue);
      expect(dialog.video.value, isTrue);
      expect(find.text('Фото'), findsNothing);
      expect(find.text('Загружаются все медиафайлы'), findsNWidgets(3));
    });

    testWidgets('the menu collapses back and the hint lists the enabled', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({});
      final dialog = KometSettings.autoDownloadScopes[AutoDownloadKind.dialog]!;

      await tester.pumpWidget(wrap());
      await tester.tap(find.byType(Switch).first);
      await tester.pumpAndSettle();

      // #***! тап по строке вида чата сворачивает меню обратно
      await tester.tap(find.text('Личные чаты'));
      await tester.pumpAndSettle();
      expect(find.text('Фото'), findsNothing);
      expect(find.text('Ничего не загружается'), findsOneWidget);

      // раскрываем обратно, включаем фото и голосовые
      await tester.tap(find.text('Личные чаты'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Фото'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Голосовые'));
      await tester.pumpAndSettle();
      expect(dialog.photo.value, isTrue);
      expect(dialog.voice.value, isTrue);

      // в свёрнутом виде подпись перечисляет включённое
      await tester.tap(find.text('Личные чаты'));
      await tester.pumpAndSettle();
      expect(find.text('Фото'), findsNothing);
      expect(find.text('Загружаются фото и голосовые'), findsOneWidget);
    });

    testWidgets(
      'all re-enabled flags switch the master back on the next visit',
      (tester) async {
        SharedPreferences.setMockInitialValues({});
        final channel =
            KometSettings.autoDownloadScopes[AutoDownloadKind.channel]!;

        // #***! пользователь ушёл из настроек с выключенным мастером
        // и полностью включёнными индивидуальными опциями
        await channel.setMaster(false);
        await channel.setPhoto(true);
        await channel.setVideo(true);
        await channel.setVoice(true);
        await channel.setVideoNote(true);

        // следующий заход в настройки возвращает мастер сам
        await tester.pumpWidget(wrap());
        await tester.pumpAndSettle();
        expect(channel.master.value, isTrue);
        expect(find.text('Загружаются все медиафайлы'), findsNWidgets(3));
        expect(find.text('Фото'), findsNothing);
      },
    );

    testWidgets(
      'a collapsed menu with everything selected shows the all-media hint',
      (tester) async {
        SharedPreferences.setMockInitialValues({});
        final dialog =
            KometSettings.autoDownloadScopes[AutoDownloadKind.dialog]!;

        await tester.pumpWidget(wrap());
        await tester.tap(find.byType(Switch).first);
        await tester.pumpAndSettle();

        // #***! включаем все опции по одной, не выходя из настроек
        await tester.tap(find.text('Фото'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Видео'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Голосовые'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Кружки'));
        await tester.pumpAndSettle();

        // сворачиваем меню — подпись показывает общий текст
        await tester.tap(find.text('Личные чаты'));
        await tester.pumpAndSettle();
        expect(find.text('Фото'), findsNothing);
        expect(find.text('Загружаются все медиафайлы'), findsNWidgets(3));

        // #***! мастер не включается сам до следующего захода в настройки
        expect(dialog.master.value, isFalse);
        expect(dialog.allFlagsOn, isTrue);
      },
    );
  });
}
