// Browser download of a text file. The web build uses the real
// implementation; the VM (widget tests) gets a stub so the page still compiles.
export 'csv_download_stub.dart' if (dart.library.js_interop) 'csv_download_web.dart';
