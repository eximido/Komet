import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';

import '../../../../core/utils/logger.dart';
import '../../../../core/utils/media_cache.dart';
// #***! сетевое фото баббла качается сразу в постоянный кэш медиа —
// как видео и голосовые. раньше оно жило только во временном кэше
// картинок и после перезапуска пропадало: загруженное вручную фото
// снова показывалось кнопкой загрузки. пока качается — размытая
// превьюшка, при сбое те же повторы что были раньше
class NetworkPhoto extends StatefulWidget {
  const NetworkPhoto({
    super.key,
    required this.url,
    required this.cacheName,
    required this.width,
    required this.height,
    required this.memWidth,
    required this.memHeight,
    required this.fallback,
    this.logId,
  });

  static const List<Duration> retryDelays = [
    Duration(seconds: 2),
    Duration(seconds: 6),
    Duration(seconds: 20),
  ];

  final String url;

  // #***! детерминированное имя в постоянном кэше, по урлу
  final String cacheName;
  final double width;
  final double height;
  final int memWidth;
  final int memHeight;
  final WidgetBuilder fallback;
  final Object? logId;

  // #***! тесты подменяют загрузку, чтобы не ходить в сеть и на диск
  @visibleForTesting
  static Future<File?> Function(String cacheName, String url) fetch =
      _fetchPersistent;

  @visibleForTesting
  static void resetForTesting() {
    fetch = _fetchPersistent;
  }

  static Future<File?> _fetchPersistent(String cacheName, String url) async {
    // #***! во временном кэше картинок файл мог оказаться раньше нас
    // (например, миниатюрой списка чатов) — берём оттуда и в фоне
    // переносим в постоянный, без второй загрузки по сети
    try {
      final cached = await DefaultCacheManager().getFileFromCache(url);
      if (cached != null) {
        unawaited(MediaCache.import(cacheName, cached.file));
        return cached.file;
      }
    } catch (_) {}
    return MediaCache.getOrDownload(cacheName, url);
  }

  @override
  State<NetworkPhoto> createState() => _NetworkPhotoState();
}

class _NetworkPhotoState extends State<NetworkPhoto> {
  int _attempt = 0;
  Timer? _retry;
  File? _file;

  @override
  void initState() {
    super.initState();
    _start();
  }

  @override
  void didUpdateWidget(NetworkPhoto oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url == widget.url &&
        oldWidget.cacheName == widget.cacheName) {
      return;
    }
    _retry?.cancel();
    _retry = null;
    _attempt = 0;
    _file = null;
    _start();
  }

  @override
  void dispose() {
    _retry?.cancel();
    super.dispose();
  }

  void _start() => unawaited(_load());

  Future<void> _load() async {
    // #***! снимаем значения до await: ответ пришедший после смены урла
    // не должен показать файл чужой картинки
    final url = widget.url;
    final cacheName = widget.cacheName;
    File? file;
    try {
      file = await NetworkPhoto.fetch(cacheName, url);
    } catch (e) {
      logger.w('Фото ${widget.logId ?? '?'} не загрузилось: $e');
      file = null;
    }
    if (!mounted || widget.url != url || widget.cacheName != cacheName) {
      return;
    }
    if (file != null) {
      setState(() => _file = file);
      return;
    }
    _scheduleRetry();
  }

  // #***! те же паузы повторов что были у сетевой версии
  void _scheduleRetry() {
    if (_retry != null) return;
    final delays = NetworkPhoto.retryDelays;
    if (_attempt == 0 || _attempt == delays.length) {
      logger.w(
        'Фото ${widget.logId ?? '?'} не загрузилось '
        '(попытка ${_attempt + 1})',
      );
    }
    if (_attempt >= delays.length) return;
    _retry = Timer(delays[_attempt], () {
      if (!mounted) return;
      setState(() {
        _retry = null;
        _attempt++;
      });
      _start();
    });
  }

  @override
  Widget build(BuildContext context) {
    final file = _file;
    if (file == null) {
      return widget.fallback(context);
    }
    return Image.file(
      file,
      width: widget.width,
      height: widget.height,
      fit: BoxFit.cover,
      cacheWidth: widget.memWidth > 0 ? widget.memWidth : null,
      cacheHeight: widget.memHeight > 0 ? widget.memHeight : null,
      gaplessPlayback: true,
      errorBuilder: (_, _, _) => widget.fallback(context),
    );
  }
}
