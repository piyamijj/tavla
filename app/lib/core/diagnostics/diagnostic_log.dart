/// A tiny app-lifetime diagnostic log.
///
/// Purpose: on a real device with no PC/adb access, an exception that gets
/// thrown outside the places this app already listens for errors (for
/// example inside a third-party package's own internal async machinery,
/// in a `Timer` callback, or anywhere else that isn't wrapped in a local
/// try/catch) would otherwise vanish silently in a release build — no
/// crash, no log, no visible cause. This captures those via
/// `runZonedGuarded`'s error handler and `FlutterError.onError` (both
/// wired in `main.dart`) into a small in-memory list, so the app itself
/// can show "here is the last uncaught error seen since launch" directly
/// on screen, without needing `adb logcat` or any other tooling.
///
/// Deliberately dependency-free (no Flutter import here) so it can be
/// imported from anywhere, including plain Dart files, without pulling
/// in `package:flutter`. The call sites in `main.dart` pass in already
///-stringified error/stack text.
class DiagnosticLog {
  DiagnosticLog._();

  /// Keep only the most recent entries — this is meant for a short,
  /// human-readable on-screen banner, not a full log viewer.
  static const int _maxEntries = 5;

  static final List<String> _entries = <String>[];

  /// Records one captured error. [context] is a short label for where it
  /// came from (e.g. `'zone'`, `'flutter'`), [error] is the error's own
  /// `toString()`, and [stackTop] is optionally the first line or two of
  /// the stack trace — enough to point at a source location without
  /// ballooning the log.
  static void record(String context, String error, [String? stackTop]) {
    final entry = stackTop == null || stackTop.isEmpty
        ? '[$context] $error'
        : '[$context] $error\n$stackTop';

    _entries.add(entry);
    if (_entries.length > _maxEntries) {
      _entries.removeAt(0);
    }
  }

  /// True once at least one uncaught error has been captured since launch.
  static bool get hasEntries => _entries.isNotEmpty;

  /// The most recently captured entry, or `null` if none yet — this is
  /// the one most likely to be relevant to whatever the user is looking
  /// at right now (e.g. a connection attempt that just failed).
  static String? get latest => _entries.isEmpty ? null : _entries.last;

  /// All captured entries, oldest first, joined for display.
  static String get allAsText => _entries.join('\n---\n');

  /// Clears the log. Not currently called anywhere — kept for
  /// completeness / future use (e.g. clearing after a successful
  /// connection so old, unrelated errors don't linger in the display).
  static void clear() => _entries.clear();
}