// Web  → database_stub.dart (memória, sem SQLite)
// Mobile/Desktop → database_io.dart (SQLite)
export 'database_stub.dart' if (dart.library.io) 'database_io.dart';
