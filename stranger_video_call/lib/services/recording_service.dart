import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:path_provider/path_provider.dart';

enum RecordingServiceState {
  unsupported,
  ready,
  awaitingConsent,
  recording,
  stopping,
  failed,
}

extension RecordingServiceStateLabel on RecordingServiceState {
  String get label => switch (this) {
    RecordingServiceState.unsupported => 'Unsupported device',
    RecordingServiceState.ready => 'Ready',
    RecordingServiceState.awaitingConsent => 'Awaiting consent',
    RecordingServiceState.recording => 'Recording',
    RecordingServiceState.stopping => 'Stopping',
    RecordingServiceState.failed => 'Failed',
  };
}

class RecordingService {
  static const MethodChannel _channel = MethodChannel(
    'stranger_video_call/recording',
  );

  final ValueNotifier<RecordingServiceState> stateNotifier =
      ValueNotifier<RecordingServiceState>(RecordingServiceState.ready);

  MediaRecorder? _mediaRecorder;
  String? _recordingFilePath;
  bool _isRecording = false;

  RecordingServiceState get state => stateNotifier.value;
  bool get isRecording => _isRecording;

  bool get isAndroid =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  void setState(RecordingServiceState nextState) {
    stateNotifier.value = nextState;
  }

  Future<bool> initializeEncryption() async {
    _requireAndroid();

    return await _channel.invokeMethod<bool>('initializeEncryption') ?? false;
  }

  Future<bool> checkSupport() async {
    if (!isAndroid) {
      setState(RecordingServiceState.unsupported);
      return false;
    }

    try {
      final supported =
          await _channel.invokeMethod<bool>('isSupported') ?? false;
      setState(
        supported
            ? RecordingServiceState.ready
            : RecordingServiceState.unsupported,
      );
      return supported;
    } on PlatformException {
      setState(RecordingServiceState.unsupported);
      return false;
    }
  }

  Future<List<String>> listRecordings() async {
    _requireAndroid();

    final result = await _channel.invokeListMethod<String>('listRecordings');

    return result ?? <String>[];
  }

  Future<bool> deleteRecording(String fileName) async {
    _requireAndroid();

    return await _channel.invokeMethod<bool>('deleteRecording', {
          'fileName': fileName,
        }) ??
        false;
  }

  /// Returns a temporary decrypted file path for the in-app player.
  /// Always call finishPlayback() when playback ends.
  Future<String> preparePlayback(String fileName) async {
    _requireAndroid();

    final path = await _channel.invokeMethod<String>('preparePlayback', {
      'fileName': fileName,
    });

    if (path == null || path.isEmpty) {
      throw StateError('Could not prepare recording for playback.');
    }

    return path;
  }

  Future<void> finishPlayback() async {
    _requireAndroid();
    await _channel.invokeMethod<void>('finishPlayback');
  }

  Future<Map<String, dynamic>> debugRoundTrip() async {
    _requireAndroid();

    final result = await _channel.invokeMapMethod<String, dynamic>(
      'debugRoundTrip',
    );

    return result ?? <String, dynamic>{};
  }

  Future<void> startRecording({
    MediaStream? localStream,
    MediaStream? remoteStream,
  }) async {
    _requireAndroid();

    if (_isRecording) {
      throw StateError('A recording is already in progress.');
    }

    final localVideoTrack = localStream?.getVideoTracks().isNotEmpty == true
        ? localStream!.getVideoTracks().first
        : null;
    final remoteVideoTrack = remoteStream?.getVideoTracks().isNotEmpty == true
        ? remoteStream!.getVideoTracks().first
        : null;

    if (localVideoTrack == null && remoteVideoTrack == null) {
      throw StateError('No active video tracks are available for recording.');
    }

    final tempDir = await getTemporaryDirectory();
    final recordingPath =
        '${tempDir.path}/stranger-video-${DateTime.now().millisecondsSinceEpoch}.mp4';
    final recordingFile = File(recordingPath);
    if (await recordingFile.exists()) {
      await recordingFile.delete();
    }

    await _channel.invokeMethod<void>('startRecording', {
      'filePath': recordingPath,
    });

    final recorder = MediaRecorder(albumName: 'StrangerVideoCall');
    _mediaRecorder = recorder;
    _recordingFilePath = recordingPath;
    _isRecording = true;
    setState(RecordingServiceState.recording);

    try {
      await recorder.start(
        recordingPath,
        videoTrack: localVideoTrack,
        secondVideoTrack: remoteVideoTrack,
        audioChannel: RecorderAudioChannel.INPUT,
      );
    } catch (error) {
      _isRecording = false;
      _mediaRecorder = null;
      _recordingFilePath = null;
      setState(RecordingServiceState.failed);
      if (await recordingFile.exists()) {
        await recordingFile.delete();
      }
      rethrow;
    }
  }

  Future<String?> stopRecording() async {
    _requireAndroid();

    final recorder = _mediaRecorder;
    final recordingPath = _recordingFilePath;
    if (recorder == null || recordingPath == null || !_isRecording) {
      setState(RecordingServiceState.ready);
      return null;
    }

    setState(RecordingServiceState.stopping);

    try {
      await recorder.stop();
      final encryptedFileName = await _channel.invokeMethod<String?>(
        'stopRecording',
        {'filePath': recordingPath},
      );
      return encryptedFileName;
    } catch (error) {
      final tempFile = File(recordingPath);
      if (await tempFile.exists()) {
        await tempFile.delete();
      }
      setState(RecordingServiceState.failed);
      rethrow;
    } finally {
      _mediaRecorder = null;
      _recordingFilePath = null;
      _isRecording = false;
      setState(RecordingServiceState.ready);
    }
  }

  void _requireAndroid() {
    if (!isAndroid) {
      throw UnsupportedError(
        'Encrypted call recording is available only on Android.',
      );
    }
  }
}
