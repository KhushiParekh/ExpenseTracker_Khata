/// Fallback used only if neither dart:io nor dart:html is available.
/// The conditional import in `file_export.dart` means this is never the
/// implementation actually chosen on Android or Web.
Future<String> saveTextFile(String fileName, String contents, String mimeType) async {
  throw UnsupportedError('Saving files is not supported on this platform.');
}
// (keep existing saveTextFile as-is)

Future<void> shareExportedFile(String path, String mimeType) async {
  throw UnsupportedError('Sharing files is not supported on this platform.');
}