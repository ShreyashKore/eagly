/// A screen recording in progress: made on the device by Android's
/// `screenrecord`, or on the host from an iPhone mirror's frames.
abstract interface class ScreenRecording {
  /// When recording began.
  DateTime get startedAt;

  /// How long it runs before it stops by itself; null when it has no limit.
  Duration? get timeLimit;

  /// Finishes the recording and saves the mp4 to [localPath].
  Future<void> save(String localPath);

  /// Finishes the recording and throws it away.
  Future<void> cancel();
}
