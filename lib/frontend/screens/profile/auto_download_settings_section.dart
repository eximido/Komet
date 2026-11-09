import 'dart:async';

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../core/config/komet_settings.dart';
import '../../../l10n/app_localizations.dart';
import '../../widgets/settings_card.dart';

// #***! секция авто-загрузки: по кнопке на каждый вид чата, мастер-переключатель
// прямо на кнопке. включённый мастер качает всё и прячет меню опций,
// выключенный — раскрывает список типов медиа со всеми выключенными, из
// которого включается только нужное; в свёрнутом виде подпись строки
// перечисляет, что конкретно осталось включённым
class AutoDownloadSettingsSection extends StatelessWidget {
  const AutoDownloadSettingsSection({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return SettingsCard(
      children: [
        _AutoDownloadKindTile(
          icon: Symbols.person,
          label: l10n.chatSettingsAutoDownloadPrivateChats,
          scope: KometSettings.autoDownloadScopes[AutoDownloadKind.dialog]!,
        ),
        _AutoDownloadKindTile(
          icon: Symbols.group,
          label: l10n.chatSettingsAutoDownloadGroupChats,
          scope: KometSettings.autoDownloadScopes[AutoDownloadKind.group]!,
        ),
        _AutoDownloadKindTile(
          icon: Symbols.campaign,
          label: l10n.chatSettingsAutoDownloadChannels,
          scope: KometSettings.autoDownloadScopes[AutoDownloadKind.channel]!,
        ),
      ],
    );
  }
}

// #***! подпись под видом чата при выключенном мастере: перечисляем, что
// конкретно осталось включённым — «загружаются фото и голосовые»,
// «загружаются только фото», «ничего не загружается» и так далее.
// список строится универсально: выбранное кроме последнего склеивается
// через запятую, последнее добавляется союзом из локализации — так новая
// категория медиа не потребует отдельных строк под каждое число
String autoDownloadSummaryOf(AppLocalizations l10n, AutoDownloadScope scope) {
  final labels = [
    if (scope.photo.value) l10n.chatSettingsAutoDownloadPhoto,
    if (scope.video.value) l10n.chatSettingsAutoDownloadVideo,
    if (scope.voice.value) l10n.chatSettingsAutoDownloadVoice,
    if (scope.videoNote.value) l10n.chatSettingsAutoDownloadVideoNote,
  ].map(_lowerFirst).toList();
  if (labels.isEmpty) return l10n.chatSettingsAutoDownloadNothingHint;
  if (labels.length == 1) {
    return l10n.chatSettingsAutoDownloadOnlyHint(labels.single);
  }
  // #***! выбрано всё — общий текст информативнее перечисления
  if (scope.allFlagsOn) return l10n.chatSettingsAutoDownloadAllMediaHint;
  return l10n.chatSettingsAutoDownloadListHint(
    labels.sublist(0, labels.length - 1).join(', '),
    labels.last,
  );
}

// #***! названия типов в подписи идут со строчной буквы
String _lowerFirst(String label) =>
    label.isEmpty ? label : '${label[0].toLowerCase()}${label.substring(1)}';

class _AutoDownloadKindTile extends StatefulWidget {
  final IconData icon;
  final String label;
  final AutoDownloadScope scope;

  const _AutoDownloadKindTile({
    required this.icon,
    required this.label,
    required this.scope,
  });

  @override
  State<_AutoDownloadKindTile> createState() => _AutoDownloadKindTileState();
}

class _AutoDownloadKindTileState extends State<_AutoDownloadKindTile> {
  static const Duration _expandDuration = Duration(milliseconds: 200);

  bool _expanded = false;

  AutoDownloadScope get _scope => widget.scope;

  @override
  void initState() {
    super.initState();
    _scope.master.addListener(_onMasterChanged);
    // #***! пользователь ушёл с выключенным мастером и всеми включёнными
    // опциями — возвращаем мастер, чтобы не висело глупое состояние
    unawaited(_scope.normalize());
  }

  @override
  void dispose() {
    _scope.master.removeListener(_onMasterChanged);
    super.dispose();
  }

  // #***! включение мастера сворачивает меню, выключение — наоборот
  // раскрывает опции заново, все в выключенном состоянии
  void _onMasterChanged() {
    if (_scope.master.value) {
      if (_expanded) setState(() => _expanded = false);
    } else if (!_expanded) {
      setState(() => _expanded = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context)!;
    return ValueListenableBuilder<bool>(
      valueListenable: _scope.master,
      builder: (context, master, _) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Material(
            color: Colors.transparent,
            child: InkWell(
              // #***! тап по строке с включённым мастером выключает его,
              // с выключенным — раскрывает и сворачивает опции
              onTap: master
                  ? () => _scope.setMaster(false)
                  : () => setState(() => _expanded = !_expanded),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 14,
                ),
                child: Row(
                  children: [
                    Icon(
                      widget.icon,
                      color: cs.onSurfaceVariant,
                      size: 22,
                      weight: 400,
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.label,
                            style: TextStyle(
                              color: cs.onSurface,
                              fontSize: 16,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          if (master || !_expanded) ...[
                            const SizedBox(height: 2),
                            _hint(l10n, master, cs),
                          ],
                        ],
                      ),
                    ),
                    _expandArrow(cs, master),
                    const SizedBox(width: 12),
                    Switch(value: master, onChanged: _scope.setMaster),
                  ],
                ),
              ),
            ),
          ),
          AnimatedSize(
            duration: _expandDuration,
            curve: Curves.easeInOutCubic,
            alignment: Alignment.topCenter,
            // #***! опции видны только при выключенном мастере и
            // развёрнутом меню, сворачивание реально прячет строки
            child: (master || !_expanded)
                ? const SizedBox(width: double.infinity)
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: _mediaToggles(l10n),
                  ),
          ),
        ],
      ),
    );
  }

  // #***! шеврон раскрытия виден только при выключенном мастере,
  // место под ним держим, чтобы переключатель не прыгал
  Widget _expandArrow(ColorScheme cs, bool master) {
    if (master) return const SizedBox(width: 24, height: 24);
    return AnimatedRotation(
      turns: _expanded ? 0.5 : 0,
      duration: _expandDuration,
      child: Icon(
        Symbols.expand_more,
        color: cs.outline,
        size: 24,
        weight: 400,
      ),
    );
  }

  // #***! подпись строки: мастер включён — качается всё; выключен и меню
  // свёрнуто — перечисляем, что конкретно осталось включённым
  Widget _hint(AppLocalizations l10n, bool master, ColorScheme cs) {
    final style = TextStyle(
      color: cs.onSurfaceVariant,
      fontSize: 13,
      height: 1.3,
    );
    if (master) {
      return Text(l10n.chatSettingsAutoDownloadAllMediaHint, style: style);
    }
    return ListenableBuilder(
      listenable: Listenable.merge([
        _scope.photo,
        _scope.video,
        _scope.voice,
        _scope.videoNote,
      ]),
      builder: (context, _) =>
          Text(autoDownloadSummaryOf(l10n, _scope), style: style),
    );
  }

  List<Widget> _mediaToggles(AppLocalizations l10n) {
    return [
      _mediaToggle(
        icon: Symbols.image,
        label: l10n.chatSettingsAutoDownloadPhoto,
        notifier: _scope.photo,
        onChanged: _scope.setPhoto,
      ),
      _mediaDivider(),
      _mediaToggle(
        icon: Symbols.videocam,
        label: l10n.chatSettingsAutoDownloadVideo,
        notifier: _scope.video,
        onChanged: _scope.setVideo,
      ),
      _mediaDivider(),
      _mediaToggle(
        icon: Symbols.mic,
        label: l10n.chatSettingsAutoDownloadVoice,
        notifier: _scope.voice,
        onChanged: _scope.setVoice,
      ),
      _mediaDivider(),
      _mediaToggle(
        icon: Symbols.radio_button_checked,
        label: l10n.chatSettingsAutoDownloadVideoNote,
        notifier: _scope.videoNote,
        onChanged: _scope.setVideoNote,
      ),
    ];
  }

  Widget _mediaDivider() => Builder(
    builder: (context) {
      final cs = Theme.of(context).colorScheme;
      return Padding(
        padding: const EdgeInsets.only(left: 92),
        child: Divider(
          height: 1,
          thickness: 1,
          color: cs.outlineVariant.withValues(alpha: 0.35),
        ),
      );
    },
  );

  Widget _mediaToggle({
    required IconData icon,
    required String label,
    required ValueNotifier<bool> notifier,
    required ValueChanged<bool> onChanged,
  }) {
    return ValueListenableBuilder<bool>(
      valueListenable: notifier,
      builder: (context, value, _) {
        final cs = Theme.of(context).colorScheme;
        return Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () => onChanged(!value),
            child: Padding(
              padding: const EdgeInsets.only(
                left: 58,
                right: 20,
                top: 11,
                bottom: 11,
              ),
              child: Row(
                children: [
                  Icon(icon, color: cs.onSurfaceVariant, size: 20, weight: 400),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Text(
                      label,
                      style: TextStyle(
                        color: cs.onSurface,
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Switch(value: value, onChanged: onChanged),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
