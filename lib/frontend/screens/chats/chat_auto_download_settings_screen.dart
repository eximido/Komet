import 'dart:async';

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../core/config/app_fonts.dart';
import '../../../core/config/komet_settings.dart';
import '../../../core/storage/chat_auto_download_store.dart';
import '../../../core/utils/haptics.dart';
import '../../../l10n/app_localizations.dart';
import '../../widgets/settings_card.dart';

// #***! состояние одного вида медиа в исключении чата
enum _OverrideTri { on, off, unset }

// #***! экран исключений авто-загрузки для конкретного чата: открывается
// из меню чата (три точки) рядом с обоями и уведомлениями. каждый вид
// медиа выбирается из трёх вариантов — включено, выключено и не задано,
// то есть действовать по общим настройкам
class ChatAutoDownloadSettingsScreen extends StatefulWidget {
  final int accountId;
  final int chatId;
  final String chatType;

  const ChatAutoDownloadSettingsScreen({
    super.key,
    required this.accountId,
    required this.chatId,
    required this.chatType,
  });

  @override
  State<ChatAutoDownloadSettingsScreen> createState() =>
      _ChatAutoDownloadSettingsScreenState();
}

class _ChatAutoDownloadSettingsScreenState
    extends State<ChatAutoDownloadSettingsScreen> {
  @override
  void initState() {
    super.initState();
    // #***! стор грузится на старте приложения, тут только подстраховка
    unawaited(
      ChatAutoDownloadStore.instance.load().then((_) {
        if (mounted) setState(() {});
      }),
    );
    // #***! исключение могли поменять снаружи, например удалить чат
    ChatAutoDownloadStore.instance.revision.addListener(_refresh);
  }

  @override
  void dispose() {
    ChatAutoDownloadStore.instance.revision.removeListener(_refresh);
    super.dispose();
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  ChatAutoDownloadOverride? get _override => widget.accountId == 0
      ? null
      : ChatAutoDownloadStore.instance.get(widget.accountId, widget.chatId);

  bool? _valueOf(ChatAutoDownloadOverride? override, AutoDownloadMedia media) =>
      switch (media) {
        AutoDownloadMedia.photo => override?.photo,
        AutoDownloadMedia.video => override?.video,
        AutoDownloadMedia.voice => override?.voice,
        AutoDownloadMedia.videoNote => override?.videoNote,
      };

  Future<void> _setValue(AutoDownloadMedia media, bool? value) async {
    if (widget.accountId == 0) return;
    Haptics.selection();
    final current = _override ?? const ChatAutoDownloadOverride();
    await ChatAutoDownloadStore.instance.set(
      widget.accountId,
      widget.chatId,
      current.withValue(media, value),
    );
    // стор пишет с задержкой, перерисовку делаем сами
    _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context)!;
    final scope = KometSettings.autoDownloadOf(widget.chatType);
    final override = _override;

    return Scaffold(
      backgroundColor: cs.surface,
      appBar: AppBar(
        backgroundColor: cs.surface,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Symbols.arrow_back, color: cs.onSurface, weight: 400),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          l10n.chatSettingsAutoDownloadTitle,
          style: TextStyle(
            color: cs.onSurface,
            fontSize: 20,
            fontWeight: FontWeight.w700,
            fontFamily: displayFontOf(context),
          ),
        ),
      ),
      body: SafeArea(
        top: false,
        child: ListView(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 120),
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Text(
                l10n.chatAutoDownloadExceptionsDescription,
                style: TextStyle(
                  color: cs.onSurfaceVariant,
                  fontSize: 13,
                  height: 1.4,
                ),
              ),
            ),
            const SizedBox(height: 12),
            SettingsCard(
              children: [
                _OverrideTile(
                  icon: Symbols.image,
                  label: l10n.chatSettingsAutoDownloadPhoto,
                  media: AutoDownloadMedia.photo,
                  value: _valueOf(override, AutoDownloadMedia.photo),
                  globalFlag: scope.photo,
                  onChanged: _setValue,
                ),
                _OverrideTile(
                  icon: Symbols.videocam,
                  label: l10n.chatSettingsAutoDownloadVideo,
                  media: AutoDownloadMedia.video,
                  value: _valueOf(override, AutoDownloadMedia.video),
                  globalFlag: scope.video,
                  onChanged: _setValue,
                ),
                _OverrideTile(
                  icon: Symbols.mic,
                  label: l10n.chatSettingsAutoDownloadVoice,
                  media: AutoDownloadMedia.voice,
                  value: _valueOf(override, AutoDownloadMedia.voice),
                  globalFlag: scope.voice,
                  onChanged: _setValue,
                ),
                _OverrideTile(
                  icon: Symbols.radio_button_checked,
                  label: l10n.chatSettingsAutoDownloadVideoNote,
                  media: AutoDownloadMedia.videoNote,
                  value: _valueOf(override, AutoDownloadMedia.videoNote),
                  globalFlag: scope.videoNote,
                  onChanged: _setValue,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _OverrideTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final AutoDownloadMedia media;
  final bool? value;
  final ValueNotifier<bool> globalFlag;
  final Future<void> Function(AutoDownloadMedia media, bool? value) onChanged;

  const _OverrideTile({
    required this.icon,
    required this.label,
    required this.media,
    required this.value,
    required this.globalFlag,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context)!;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(icon, color: cs.onSurfaceVariant, size: 22, weight: 400),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: TextStyle(
                        color: cs.onSurface,
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 2),
                    // #***! подсказка, что сейчас делает общая настройка —
                    // это и есть действие варианта «не задано»
                    ValueListenableBuilder<bool>(
                      valueListenable: globalFlag,
                      builder: (context, global, _) => Text(
                        global
                            ? l10n.chatAutoDownloadGlobalOn
                            : l10n.chatAutoDownloadGlobalOff,
                        style: TextStyle(
                          color: cs.onSurfaceVariant,
                          fontSize: 13,
                          height: 1.3,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SegmentedButton<_OverrideTri>(
            showSelectedIcon: false,
            segments: [
              ButtonSegment(
                value: _OverrideTri.on,
                label: Text(l10n.chatAutoDownloadStateOn),
              ),
              ButtonSegment(
                value: _OverrideTri.off,
                label: Text(l10n.chatAutoDownloadStateOff),
              ),
              // #***! не задано — снимаем исключение, действуют общие
              ButtonSegment(
                value: _OverrideTri.unset,
                label: Text(l10n.chatAutoDownloadStateUnset),
              ),
            ],
            selected: {
              switch (value) {
                true => _OverrideTri.on,
                false => _OverrideTri.off,
                null => _OverrideTri.unset,
              },
            },
            onSelectionChanged: (selection) =>
                onChanged(media, switch (selection.first) {
                  _OverrideTri.on => true,
                  _OverrideTri.off => false,
                  _OverrideTri.unset => null,
                }),
          ),
        ],
      ),
    );
  }
}
