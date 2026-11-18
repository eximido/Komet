import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:komet/core/calls/incoming_call_watchdog.dart';
import 'package:komet/core/calls/ws2_signaling.dart';

// #***! фейковая сигналка, управляемая из теста
class _FakeSignaling extends Ws2Signaling {
  _FakeSignaling(super.config);

  final _notifications = StreamController<Map<String, dynamic>>.broadcast();
  final _done = Completer<Object?>();
  int connectCalls = 0;
  bool closed = false;
  Object? connectError;

  @override
  Stream<Map<String, dynamic>> get notifications => _notifications.stream;

  @override
  Future<Object?> get done => _done.future;

  @override
  Future<void> connect() async {
    connectCalls++;
    final error = connectError;
    if (error != null) throw error;
  }

  @override
  Future<void> close() async {
    closed = true;
    if (!_done.isCompleted) _done.complete(null);
  }

  void serverError() =>
      _notifications.add({'type': 'error', 'error': 'conversation-ended'});

  void serverHungup() =>
      _notifications.add({'notification': 'hungup', 'participantId': 42});

  void serverAlive() =>
      _notifications.add({'notification': 'connection', 'type': 'notification'});

  void socketDies() {
    if (!_done.isCompleted) _done.complete(null);
  }
}

const _reconnectDelay = Duration(seconds: 3);
const _giveUpAfter = Duration(seconds: 60);

Ws2Config _config() =>
    Ws2Config(uri: Uri.parse('wss://call.invalid/ws2'), userId: 1);

void main() {
  test('уведомление hungup завершает входящий', () {
    fakeAsync((async) {
      var canceled = 0;
      final fake = _FakeSignaling(_config());
      final watchdog = IncomingCallWatchdog(
        config: _config(),
        onCanceled: () => canceled++,
        signalingFactory: (_) => fake,
      );
      watchdog.start();
      async.flushMicrotasks();

      fake.serverHungup();
      async.flushMicrotasks();

      expect(canceled, 1);
      expect(fake.closed, isTrue);
    });
  });

  test('ошибка сервера завершает входящий', () {
    fakeAsync((async) {
      var canceled = 0;
      final fake = _FakeSignaling(_config());
      final watchdog = IncomingCallWatchdog(
        config: _config(),
        onCanceled: () => canceled++,
        signalingFactory: (_) => fake,
      );
      watchdog.start();
      async.flushMicrotasks();

      fake.serverError();
      async.flushMicrotasks();

      expect(canceled, 1);
      expect(fake.closed, isTrue);
    });
  });

  test('прочие нотификации не завершают входящий', () {
    fakeAsync((async) {
      var canceled = 0;
      final fake = _FakeSignaling(_config());
      final watchdog = IncomingCallWatchdog(
        config: _config(),
        onCanceled: () => canceled++,
        signalingFactory: (_) => fake,
      );
      watchdog.start();
      async.flushMicrotasks();

      fake.serverAlive();
      async.flushMicrotasks();
      async.elapse(const Duration(seconds: 10));

      expect(canceled, 0);
      expect(fake.closed, isFalse);
    });
  });

  test('разрыв сокета переподключается без отмены', () {
    fakeAsync((async) {
      var canceled = 0;
      final fake = _FakeSignaling(_config());
      final watchdog = IncomingCallWatchdog(
        config: _config(),
        onCanceled: () => canceled++,
        signalingFactory: (_) => fake,
      );
      watchdog.start();
      async.flushMicrotasks();
      expect(fake.connectCalls, 1);

      fake.socketDies();
      async.flushMicrotasks();
      async.elapse(_reconnectDelay);
      async.flushMicrotasks();

      expect(fake.connectCalls, 2);
      expect(canceled, 0);
    });
  });

  test('неудачное подключение переподключается ограниченно', () {
    fakeAsync((async) {
      var canceled = 0;
      final fake = _FakeSignaling(_config())
        ..connectError = Exception('сеть недоступна');
      final watchdog = IncomingCallWatchdog(
        config: _config(),
        onCanceled: () => canceled++,
        signalingFactory: (_) => fake,
      );
      watchdog.start();
      async.flushMicrotasks();

      // Первое подключение и четыре повтора, дальше попытки кончились.
      for (var i = 0; i < 4; i++) {
        async.elapse(_reconnectDelay);
        async.flushMicrotasks();
      }
      expect(fake.connectCalls, 5);

      async.elapse(_reconnectDelay * 4);
      async.flushMicrotasks();
      expect(fake.connectCalls, 5);
      expect(canceled, 0);
    });
  });

  test('страховочный таймаут закрывает входящий', () {
    fakeAsync((async) {
      var canceled = 0;
      final fake = _FakeSignaling(_config());
      final watchdog = IncomingCallWatchdog(
        config: _config(),
        onCanceled: () => canceled++,
        signalingFactory: (_) => fake,
      );
      watchdog.start();
      async.flushMicrotasks();

      async.elapse(_giveUpAfter + const Duration(seconds: 1));

      expect(canceled, 1);
      expect(fake.closed, isTrue);
    });
  });

  test('dispose гасит слушателя, поздние события игнорируются', () {
    fakeAsync((async) {
      var canceled = 0;
      final fake = _FakeSignaling(_config());
      final watchdog = IncomingCallWatchdog(
        config: _config(),
        onCanceled: () => canceled++,
        signalingFactory: (_) => fake,
      );
      watchdog.start();
      async.flushMicrotasks();

      watchdog.dispose();
      fake.serverHungup();
      async.flushMicrotasks();
      async.elapse(_giveUpAfter + const Duration(seconds: 1));

      expect(canceled, 0);
      expect(fake.closed, isTrue);
    });
  });

  test('повторный сигнал конца не дёргает колбэк дважды', () {
    fakeAsync((async) {
      var canceled = 0;
      final fake = _FakeSignaling(_config());
      final watchdog = IncomingCallWatchdog(
        config: _config(),
        onCanceled: () => canceled++,
        signalingFactory: (_) => fake,
      );
      watchdog.start();
      async.flushMicrotasks();

      fake.serverHungup();
      async.flushMicrotasks();
      fake.serverHungup();
      async.flushMicrotasks();

      expect(canceled, 1);
    });
  });
}
