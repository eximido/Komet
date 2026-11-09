import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../core/config/komet_settings.dart';
import '../../core/crypto/encrypted_photo_cache.dart';
import '../../core/crypto/e2ee_service.dart';
import '../../core/storage/chat_encryption_store.dart';

class DecryptedPhoto extends StatefulWidget {
  final int accountId;
  final int chatId;
  final String cacheName;
  final int size;
  final EncryptedPhotoUrlLoader urlLoader;
  final Uint8List? sealedTicket;
  final Widget Function(EncryptedPhotoView? view) builder;

  /// Правило авто-загрузки фото этого чата: когда выключено — зашифрованный
  /// файл не качается заранее, но уже скачанный всё равно расшифровывается.
  /// null — без ограничения (прочие вызывающие места).
  final AutoDownloadRule? autoDownload;

  const DecryptedPhoto({
    super.key,
    required this.accountId,
    required this.chatId,
    required this.cacheName,
    required this.size,
    required this.urlLoader,
    required this.builder,
    this.sealedTicket,
    this.autoDownload,
  });

  @override
  State<DecryptedPhoto> createState() => _DecryptedPhotoState();
}

class _DecryptedPhotoState extends State<DecryptedPhoto> {
  Listenable? _ruleListenable;

  @override
  void initState() {
    super.initState();
    _ruleListenable = widget.autoDownload?.listenable;
    _ruleListenable?.addListener(_onRuleChanged);
    _request();
    ChatEncryptionStore.instance.revision.addListener(_onEncryptionChanged);
    E2eeService.instance.revision.addListener(_onEncryptionChanged);
  }

  @override
  void dispose() {
    _ruleListenable?.removeListener(_onRuleChanged);
    ChatEncryptionStore.instance.revision.removeListener(_onEncryptionChanged);
    E2eeService.instance.revision.removeListener(_onEncryptionChanged);
    super.dispose();
  }

  @override
  void didUpdateWidget(DecryptedPhoto old) {
    super.didUpdateWidget(old);
    if (old.accountId != widget.accountId ||
        old.chatId != widget.chatId ||
        old.cacheName != widget.cacheName ||
        old.sealedTicket != widget.sealedTicket) {
      _request();
    }
  }

  void _onEncryptionChanged() => scheduleMicrotask(_request);

  // #***! правило включили на лету — файл догрузится без перезахода в чат
  void _onRuleChanged() => _request();

  void _request() {
    if (!mounted) return;
    EncryptedPhotoCache.instance.request(
      accountId: widget.accountId,
      chatId: widget.chatId,
      cacheName: widget.cacheName,
      urlLoader: widget.urlLoader,
      size: widget.size,
      sealedTicket: widget.sealedTicket,
      allowDownload: widget.autoDownload?.value ?? true,
    );
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<EncryptedPhotoView?>(
      valueListenable: EncryptedPhotoCache.instance.listenableFor(
        widget.cacheName,
        accountId: widget.accountId,
        chatId: widget.chatId,
        sealedTicket: widget.sealedTicket,
      ),
      builder: (context, view, _) => widget.builder(view),
    );
  }
}
