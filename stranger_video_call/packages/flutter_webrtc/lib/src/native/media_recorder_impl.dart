import 'dart:async';
import 'dart:math';

import 'package:webrtc_interface/webrtc_interface.dart';

import 'media_stream_track_impl.dart';
import 'utils.dart';

class MediaRecorderNative extends MediaRecorder {
  MediaRecorderNative({
    String? albumName = 'FlutterWebRTC',
  }) : _albumName = albumName;

  static final _random = Random();

  final int _recorderId = _random.nextInt(0x7FFFFFFF);
  final String? _albumName;

  bool _isStarted = false;

  @override
  Future<void> start(
    String path, {
    MediaStreamTrack? videoTrack,
    MediaStreamTrack? secondVideoTrack,
    RecorderAudioChannel? audioChannel,
  }) async {
    if (audioChannel == null &&
        videoTrack == null &&
        secondVideoTrack == null) {
      throw ArgumentError(
        'At least one video track or an audio channel is required.',
      );
    }

    if (_isStarted) {
      throw StateError('This media recorder is already running.');
    }

    final String? peerConnectionId;

    if (videoTrack is MediaStreamTrackNative) {
      peerConnectionId = videoTrack.peerConnectionId;
    } else if (secondVideoTrack is MediaStreamTrackNative) {
      peerConnectionId = secondVideoTrack.peerConnectionId;
    } else {
      peerConnectionId = null;
    }

    await WebRTC.invokeMethod('startRecordToFile', {
      'path': path,
      if (audioChannel != null) 'audioChannel': audioChannel.index,
      if (videoTrack != null) 'videoTrackId': videoTrack.id,
      if (secondVideoTrack != null) 'secondVideoTrackId': secondVideoTrack.id,
      'recorderId': _recorderId,
      'peerConnectionId': peerConnectionId,
    });

    _isStarted = true;
  }

  @override
  void startWeb(
    MediaStream stream, {
    Function(dynamic blob, bool isLastOne)? onDataChunk,
    String? mimeType,
    int timeSlice = 1000,
  }) {
    throw UnsupportedError('This method is for Flutter Web only.');
  }

  @override
  Future<dynamic> stop() async {
    if (!_isStarted) {
      throw StateError('Media recorder not started.');
    }

    await WebRTC.invokeMethod('stopRecordToFile', {
      'recorderId': _recorderId,
      'albumName': _albumName,
    });

    _isStarted = false;
  }
}
