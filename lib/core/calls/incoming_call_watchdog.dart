import 'dart:async';

import '../utils/logger.dart';
import 'ws2_signaling.dart';

// #***! слушаем отмену входящего, пока он звонит
/// Пассивный слушатель сигналинга ws2 входящего звонка.
///
/// Пока входящий звонок звонит, к сигналке никто не подключён: приложение
/// соединяется с ней только при принятии или отклонении. Из-за этого отмена
/// звонящим до ответа никак не узнавалась — экран звонка и рингер продолжали
/// жить, пока пользователь не нажмёт кнопку. FCM-пуш `CallFinished` закрывает
/// это только в google-флейворе, флейвор с FKM и десктоп не видят ничего.
///
/// Слушатель подключается к каналу звонка, не отправляя `accept-call` — так
/// же подключается отклонение, — и завершает входящий при явных сигналах
/// конца: ошибке сервера (например `conversation-ended`) или уведомлении
/// `hungup`. Разрыв сокета концом не считается: сеть могла моргнуть,
/// переподключаемся. Если сервер так ничего и не сказал, страховочный таймаут
/// закрывает входящий сам — нативный рингер к этому моменту уже остановлен
/// своим 45-секундным таймаутом.
class IncomingCallWatchdog {
  IncomingCallWatchdog({
    required this.config,
    required this.onCanceled,
    Ws2Signaling Function(Ws2Config config)? signalingFactory,
  }) : _makeSignaling = signalingFactory ?? _defaultSignaling;

  /// Конфиг того же канала, к которому подключится принятие звонка.
  final Ws2Config config;

  /// Вызывается один раз, когда звонок закончен без нашего участия.
  final void Function() onCanceled;

  final Ws2Signaling Function(Ws2Config config) _makeSignaling;

  static Ws2Signaling _defaultSignaling(Ws2Config config) =>
      Ws2Signaling(config);

  static const _maxAttempts = 5;
  static const _reconnectDelay = Duration(seconds: 3);
  static const _giveUpAfter = Duration(seconds: 60);

  Ws2Signaling? _signaling;
  StreamSubscription<Map<String, dynamic>>? _sub;
  Timer? _reconnect;
  Timer? _cap;
  int _attempts = 0;
  bool _stopped = false;

  void start() {
    if (_stopped) return;
    _cap = Timer(_giveUpAfter, _cancel);
    _connect();
  }

  /// Остановить навсегда: звонок приняли, отклонили или закрыли руками.
  void dispose() {
    _stopped = true;
    _release();
  }

  Future<void> _connect() async {
    if (_stopped) return;
    final signaling = _makeSignaling(config);
    _signaling = signaling;
    try {
      await signaling.connect();
    } catch (e) {
      if (_stopped) return;
      logger.w('[call] cancel watchdog: подключение не удалось: $e');
      if (identical(_signaling, signaling)) _signaling = null;
      _scheduleReconnect();
      return;
    }
    if (_stopped) {
      unawaited(signaling.close());
      return;
    }
    _sub = signaling.notifications.listen(_onMessage);
    unawaited(
      signaling.done.then(
        (_) => _onSocketClosed(signaling),
        onError: (_) => _onSocketClosed(signaling),
      ),
    );
  }

  // #***! конец это только явные сигналы, прочие нотификации игнорируем
  void _onMessage(Map<String, dynamic> msg) {
    final ended = msg['type'] == 'error' || msg['notification'] == 'hungup';
    if (ended) _cancel();
  }

  void _onSocketClosed(Ws2Signaling signaling) {
    if (_stopped || !identical(_signaling, signaling)) return;
    _sub?.cancel();
    _sub = null;
    _signaling = null;
    _scheduleReconnect();
  }

  void _scheduleReconnect() {
    if (_stopped || _reconnect != null) return;
    if (++_attempts >= _maxAttempts) return;
    _reconnect = Timer(_reconnectDelay, () {
      _reconnect = null;
      _connect();
    });
  }

  void _cancel() {
    if (_stopped) return;
    dispose();
    onCanceled();
  }

  void _release() {
    _cap?.cancel();
    _cap = null;
    _reconnect?.cancel();
    _reconnect = null;
    _sub?.cancel();
    _sub = null;
    final signaling = _signaling;
    _signaling = null;
    unawaited(signaling?.close());
  }
}
