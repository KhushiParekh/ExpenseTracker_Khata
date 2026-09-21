/// Picks the right file-saving implementation at compile time:
/// a browser download on Web, a real file write on Android.
export 'file_export_stub.dart'
    if (dart.library.html) 'file_export_web.dart'
    if (dart.library.io) 'file_export_io.dart';
