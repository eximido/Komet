import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:path/path.dart' as p;

import '../../core/security/app_lock.dart';
import '../../core/storage/call_ringtone_store.dart';
import '../../l10n/app_localizations.dart';
import 'custom_notification.dart';
import 'sheet_helpers.dart';

class CallRingtonePick {
  final CallRingtone? ringtone;

  const CallRingtonePick._(this.ringtone);

  factory CallRingtonePick.defaultOption() => const CallRingtonePick._(null);

  factory CallRingtonePick.file(CallRingtone ringtone) =>
      CallRingtonePick._(ringtone);

  bool get isDefault => ringtone == null;
}

Future<CallRingtonePick?> showCallRingtoneSheet(
  BuildContext context, {
  required String title,
  required String defaultHint,
  String? hint,
  CallRingtone? current,
}) {
  return showModalBottomSheet<CallRingtonePick>(
    context: context,
    backgroundColor: Theme.of(context).colorScheme.surfaceContainerHigh,
    shape: kSheetShape,
    builder: (sheetContext) {
      final cs = Theme.of(sheetContext).colorScheme;
      final l10n = AppLocalizations.of(sheetContext)!;
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 16, 8, 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: cs.onSurface,
                  ),
                ),
              ),
              if (hint != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: Text(
                    hint,
                    style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant),
                  ),
                ),
              ListTile(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                leading: Icon(
                  Symbols.music_note,
                  size: 24,
                  color: cs.onSurfaceVariant,
                ),
                title: Text(l10n.callRingtoneDefault),
                subtitle: Text(defaultHint),
                trailing: current == null
                    ? Icon(Symbols.check, color: cs.primary)
                    : null,
                onTap: () =>
                    Navigator.pop(sheetContext, CallRingtonePick.defaultOption()),
              ),
              if (current != null)
                ListTile(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  leading: Icon(
                    Symbols.audio_file,
                    size: 24,
                    color: cs.onSurfaceVariant,
                  ),
                  title: Text(
                    current.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: Icon(Symbols.check, color: cs.primary),
                  onTap: () =>
                      Navigator.pop(sheetContext, CallRingtonePick.file(current)),
                ),
              ListTile(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                leading: Icon(
                  Symbols.upload_file,
                  size: 24,
                  color: cs.onSurfaceVariant,
                ),
                title: Text(l10n.callRingtoneSheetChooseFile),
                onTap: () => _chooseRingtoneFile(sheetContext),
              ),
            ],
          ),
        ),
      );
    },
  );
}

Future<void> _chooseRingtoneFile(BuildContext sheetContext) async {
  final l10n = AppLocalizations.of(sheetContext)!;
  final result = await AppLock.instance.external(
    () => FilePicker.platform.pickFiles(type: FileType.audio),
  );
  final file = result?.files.firstOrNull;
  final path = file?.path;
  if (file == null || path == null) return;
  if (await File(path).length() > kMaxRingtoneBytes) {
    if (sheetContext.mounted) {
      showCustomNotification(sheetContext, l10n.callRingtoneTooLarge);
    }
    return;
  }
  final rawName = file.name.isNotEmpty ? file.name : p.basename(path);
  final pick = CallRingtonePick.file(
    CallRingtone(path: path, name: p.basenameWithoutExtension(rawName)),
  );
  if (sheetContext.mounted) Navigator.pop(sheetContext, pick);
}
