// ignore_for_file: deprecated_member_use
import 'dart:convert';
import 'dart:html' as html;

/// Triggers a normal browser download. Building the object URL from a Blob
/// and clicking a detached anchor is the standard way to hand a generated
/// file to the user without a server round-trip.
Future<String> saveTextFile(String fileName, String contents, String mimeType) async {
  final bytes = utf8.encode(contents);
  final blob = html.Blob(<dynamic>[bytes], mimeType);
  final url = html.Url.createObjectUrlFromBlob(blob);

  html.AnchorElement(href: url)
    ..setAttribute('download', fileName)
    ..click();

  // Revoke on the next tick so the click has definitely been handled;
  // skipping this leaks the object URL for the life of the page.
  Future<void>.delayed(const Duration(seconds: 1), () => html.Url.revokeObjectUrl(url));

  return 'Downloads/$fileName';
}
