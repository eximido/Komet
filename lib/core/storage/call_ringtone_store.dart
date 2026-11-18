import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../utils/logger.dart';

@immutable
class CallRingtone {
  final String path;
  final String name;

  const CallRingtone({required this.path, required this.name});

  Map<String, dynamic> toJson() => {'path': path, 'name': name};

  static CallRingtone? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final path = raw['path'];
    final name = raw['name'];
    if (path is! String || path.isEmpty || name is! String) return null;
    return CallRingtone(path: path, name: name);
  }
}

const int kMaxRingtoneBytes = 16 * 1024 * 1024;
const String _dirName = 'call_ringtones';

Future<String?> copyRingtoneFile(String sourcePath, String prefix) async {
  try {
    final root = await getApplicationDocumentsDirectory();
    final dir = Directory('${root.path}/$_dirName');
    await dir.create(recursive: true);
    final stamp = DateTime.now().millisecondsSinceEpoch;
    final ext = p.extension(sourcePath);
    final file = File('${dir.path}/${prefix}_$stamp$ext');
    await file.writeAsBytes(await File(sourcePath).readAsBytes(), flush: true);
    return file.path;
  } catch (e) {
    logger.w('ringtone copy failed: $e');
    return null;
  }
}

Future<void> deleteRingtoneFile(String? path) async {
  if (path == null) return;
  try {
    final file = File(path);
    if (await file.exists()) await file.delete();
  } catch (e) {
    logger.w('ringtone file delete failed: $e');
  }
}

class CallRingtoneStore {
  CallRingtoneStore._();

  static final CallRingtoneStore instance = CallRingtoneStore._();

  static const _prefsKey = 'call_ringtone';

  final ValueNotifier<CallRingtone?> current = ValueNotifier(null);
  bool _loaded = false;

  Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKey);
    if (raw == null) return;
    final Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } on FormatException {
      return;
    }
    final ringtone = CallRingtone.fromJson(decoded);
    if (ringtone == null || !await File(ringtone.path).exists()) return;
    current.value = ringtone;
  }

  Future<bool> setFromPickedPath(String sourcePath, String displayName) async {
    final path = await copyRingtoneFile(sourcePath, 'global');
    if (path == null) return false;
    final previous = current.value;
    current.value = CallRingtone(path: path, name: displayName);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, jsonEncode(current.value!.toJson()));
    await deleteRingtoneFile(previous?.path);
    return true;
  }

  Future<void> clear() async {
    final previous = current.value;
    if (previous == null) return;
    current.value = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefsKey);
    await deleteRingtoneFile(previous.path);
  }
}
