import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// Writes the export to the most user-reachable directory available and
/// returns the path so the UI can tell the person where it landed.
///
/// On Android `getExternalStorageDirectory()` gives an app-scoped folder
/// under /Android/data/... which is browsable with any file manager and
/// needs no runtime permission. If that is unavailable for any reason we
/// fall back to the app documents directory, which always exists.
Future<String> saveTextFile(String fileName, String contents, String mimeType) async {
  Directory? dir;

  if (Platform.isAndroid) {
    try {
      dir = await getExternalStorageDirectory();
    } catch (_) {
      dir = null;
    }
  }

  dir ??= await getApplicationDocumentsDirectory();

  final exportsDir = Directory('${dir.path}/exports');
  if (!await exportsDir.exists()) {
    await exportsDir.create(recursive: true);
  }

  final file = File('${exportsDir.path}/$fileName');
  await file.writeAsString(contents);
  return file.path;
}
