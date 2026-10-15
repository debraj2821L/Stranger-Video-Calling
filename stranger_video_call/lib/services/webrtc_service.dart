import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

class WebRTCService {
  RTCPeerConnection? _peerConnection;
  MediaStream? _localStream;
  MediaStream? _remoteStream;

  final RTCVideoRenderer localRenderer = RTCVideoRenderer();
  final RTCVideoRenderer remoteRenderer = RTCVideoRenderer();

  Function(RTCIceCandidate candidate)? onIceCandidate;
  VoidCallback? onRemoteStreamChanged;

  MediaStream? get localStream => _localStream;
  MediaStream? get remoteStream => _remoteStream;

  bool _initialized = false;

  Future<void> initialize() async {
    if (_initialized) return;

    await localRenderer.initialize();
    await remoteRenderer.initialize();

    _initialized = true;
    debugPrint('[WebRTC] Renderers initialized');
  }

  Future<void> logVideoStats() async {
    final peer = _peerConnection;

    if (peer == null) {
      debugPrint('[VideoStats] Peer connection is null');
      return;
    }

    try {
      final reports = await peer.getStats();

      for (final report in reports) {
        if (report.type != 'inbound-rtp' && report.type != 'outbound-rtp') {
          continue;
        }

        final values = report.values;
        final kind = values['kind'] ?? values['mediaType'];

        if (kind != 'video') continue;

        debugPrint(
          '[VideoStats] ${report.type}: '
          'bytes=${values['bytesReceived'] ?? values['bytesSent']}, '
          'packets=${values['packetsReceived'] ?? values['packetsSent']}, '
          'framesReceived=${values['framesReceived']}, '
          'framesDecoded=${values['framesDecoded']}, '
          'framesSent=${values['framesSent']}, '
          'width=${values['frameWidth']}, '
          'height=${values['frameHeight']}',
        );
      }
    } catch (error) {
      debugPrint('[VideoStats] Failed to get stats: $error');
    }
  }

  Future<void> startLocalMedia() async {
    if (!_initialized) {
      await initialize();
    }

    if (_localStream != null) return;

    final constraints = <String, dynamic>{
      'audio': true,
      'video': {
        'facingMode': 'user',
        'width': {'ideal': 1280},
        'height': {'ideal': 720},
        'frameRate': {'ideal': 30},
      },
    };

    _localStream = await navigator.mediaDevices.getUserMedia(constraints);

    localRenderer.srcObject = _localStream;

    debugPrint(
      '[WebRTC] Local audio tracks: '
      '${_localStream!.getAudioTracks().length}',
    );
    debugPrint(
      '[WebRTC] Local video tracks: '
      '${_localStream!.getVideoTracks().length}',
    );

    for (final track in _localStream!.getTracks()) {
      debugPrint(
        '[WebRTC] Local track: ${track.kind}, '
        'enabled=${track.enabled}, muted=${track.muted}',
      );
    }
  }

  Future<void> resetPeerConnection() async {
    final oldPeer = _peerConnection;
    _peerConnection = null;

    if (oldPeer != null) {
      oldPeer.onTrack = null;
      oldPeer.onIceCandidate = null;

      await oldPeer.close();
      await oldPeer.dispose();
    }

    _remoteStream = null;
    remoteRenderer.srcObject = null;

    // Keep the local camera and microphone running.
    await setupPeerConnection();

    debugPrint('[WebRTC] Peer connection reset');
  }

  Future<void> setupPeerConnection() async {
    if (_peerConnection != null) return;

    if (!_initialized) {
      await initialize();
    }

    final configuration = <String, dynamic>{
      'iceServers': [
        {
          'urls': [
            'stun:stun.l.google.com:19302',
            'stun:stun1.l.google.com:19302',
          ],
        },
      ],
      'sdpSemantics': 'unified-plan',
    };

    _peerConnection = await createPeerConnection(configuration);

    _peerConnection!.onIceCandidate = (candidate) {
      if (candidate.candidate != null) {
        debugPrint('[WebRTC] Local ICE candidate generated');
        onIceCandidate?.call(candidate);
      }
    };

    _peerConnection!.onTrack = (event) async {
      final track = event.track;

      debugPrint(
        '[WebRTC] Remote track received: ${track.kind}, '
        'enabled=${track.enabled}, muted=${track.muted}',
      );
      debugPrint('[WebRTC] Remote stream count: ${event.streams.length}');

      if (event.streams.isNotEmpty) {
        _remoteStream = event.streams.first;
      } else {
        // Some browsers deliver tracks without a stream.
        _remoteStream ??= await createLocalMediaStream('remoteStream');

        final existingTrackIds = _remoteStream!
            .getTracks()
            .map((existing) => existing.id)
            .toSet();

        if (!existingTrackIds.contains(track.id)) {
          await _remoteStream!.addTrack(track);
        }
      }

      remoteRenderer.srcObject = _remoteStream;

      final remoteVideoTracks = _remoteStream!.getVideoTracks();

      debugPrint(
        '[WebRTC] Remote video track count: ${remoteVideoTracks.length}',
      );

      for (final track in remoteVideoTracks) {
        debugPrint(
          '[WebRTC] Remote video: '
          'enabled=${track.enabled}, muted=${track.muted}, id=${track.id}',
        );
      }

      // Notify the UI that the remote stream has changed.
      onRemoteStreamChanged?.call();

      debugPrint(
        '[WebRTC] Renderer stream ID: '
        '${remoteRenderer.srcObject?.id}',
      );

      debugPrint(
        '[WebRTC] Renderer video track count: '
        '${remoteRenderer.srcObject?.getVideoTracks().length}',
      );

      debugPrint(
        '[WebRTC] Remote video tracks: '
        '${_remoteStream!.getVideoTracks().length}',
      );
      debugPrint(
        '[WebRTC] Remote audio tracks: '
        '${_remoteStream!.getAudioTracks().length}',
      );
    };

    _peerConnection!.onConnectionState = (state) {
      debugPrint('[WebRTC] Connection state: $state');
    };

    _peerConnection!.onIceConnectionState = (state) {
      debugPrint('[WebRTC] ICE state: $state');
    };

    _peerConnection!.onSignalingState = (state) {
      debugPrint('[WebRTC] Signaling state: $state');
    };

    if (_localStream != null) {
      for (final track in _localStream!.getTracks()) {
        debugPrint('[WebRTC] Adding local track: ${track.kind}');

        await _peerConnection!.addTrack(track, _localStream!);
      }
    } else {
      debugPrint('[WebRTC] Warning: local media is not started yet');
    }
  }

  Future<RTCSessionDescription> createOffer() async {
    final peer = _peerConnection;

    if (peer == null) {
      throw StateError('Peer connection is not initialized');
    }

    final offer = await peer.createOffer({
      'offerToReceiveAudio': 1,
      'offerToReceiveVideo': 1,
    });

    await peer.setLocalDescription(offer);

    debugPrint('[WebRTC] Local offer created');
    return offer;
  }

  Future<RTCSessionDescription> createAnswer() async {
    final peer = _peerConnection;

    if (peer == null) {
      throw StateError('Peer connection is not initialized');
    }

    final answer = await peer.createAnswer({
      'offerToReceiveAudio': 1,
      'offerToReceiveVideo': 1,
    });

    await peer.setLocalDescription(answer);

    debugPrint('[WebRTC] Local answer created');
    return answer;
  }

  Future<void> setRemoteDescription(RTCSessionDescription description) async {
    final peer = _peerConnection;

    if (peer == null) {
      throw StateError('Peer connection is not initialized');
    }

    await peer.setRemoteDescription(description);

    debugPrint('[WebRTC] Remote description set: ${description.type}');
  }

  Future<void> addIceCandidate(RTCIceCandidate candidate) async {
    final peer = _peerConnection;

    if (peer == null) return;

    await peer.addCandidate(candidate);
  }

  Future<void> toggleMicrophone(bool enabled) async {
    for (final track
        in _localStream?.getAudioTracks() ?? <MediaStreamTrack>[]) {
      track.enabled = enabled;
    }
  }

  Future<void> toggleCamera(bool enabled) async {
    for (final track
        in _localStream?.getVideoTracks() ?? <MediaStreamTrack>[]) {
      track.enabled = enabled;
    }
  }

  Future<void> dispose() async {
    debugPrint('[WebRTC] Cleaning up');

    final peer = _peerConnection;
    _peerConnection = null;

    if (peer != null) {
      peer.onTrack = null;
      peer.onIceCandidate = null;
      await peer.close();
      await peer.dispose();
    }

    final local = _localStream;
    _localStream = null;

    if (local != null) {
      for (final track in local.getTracks()) {
        await track.stop();
      }
      await local.dispose();
    }

    // Do not stop remote tracks individually; they belong
    // to the remote peer's stream.
    _remoteStream = null;

    localRenderer.srcObject = null;
    remoteRenderer.srcObject = null;

    if (_initialized) {
      await localRenderer.dispose();
      await remoteRenderer.dispose();
    }

    _initialized = false;

    debugPrint('[WebRTC] Cleanup complete');
  }
}
