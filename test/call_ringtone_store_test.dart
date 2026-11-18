import 'package:flutter_test/flutter_test.dart';
import 'package:komet/core/storage/call_ringtone_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('CallVibration', () {
    test('id совпадают со строками нативного рингера', () {
      expect(CallVibration.phoneDefault.id, 'default');
      expect(CallVibration.disabled.id, 'disabled');
      expect(CallVibration.short.id, 'short');
      expect(CallVibration.long.id, 'long');
      expect(CallVibration.onlySilent.id, 'only_silent');
    });

    test('fromId разбирает известные пресеты', () {
      expect(CallVibration.fromId('default'), CallVibration.phoneDefault);
      expect(CallVibration.fromId('disabled'), CallVibration.disabled);
      expect(CallVibration.fromId('short'), CallVibration.short);
      expect(CallVibration.fromId('long'), CallVibration.long);
      expect(CallVibration.fromId('only_silent'), CallVibration.onlySilent);
    });

    test('неизвестное и пустое значение дают пресет по умолчанию', () {
      expect(CallVibration.fromId(null), CallVibration.phoneDefault);
      expect(CallVibration.fromId(''), CallVibration.phoneDefault);
      expect(CallVibration.fromId('bzzz'), CallVibration.phoneDefault);
    });
  });

  test('вибрация читается из prefs и сохраняется', () async {
    SharedPreferences.setMockInitialValues({
      'call_ringtone_vibration': 'long',
    });
    final store = CallRingtoneStore.instance;
    await store.load();

    expect(store.vibration.value, CallVibration.long);

    await store.setVibration(CallVibration.onlySilent);
    expect(store.vibration.value, CallVibration.onlySilent);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('call_ringtone_vibration'), 'only_silent');
  });
}
