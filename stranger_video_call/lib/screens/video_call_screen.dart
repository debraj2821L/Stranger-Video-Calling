import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../config/server_config.dart';
import '../services/recording_service.dart';
import '../services/signaling_service.dart';
import '../services/webrtc_service.dart';

class VideoCallScreen extends StatefulWidget {
  final String roomId;

  const VideoCallScreen({super.key, required this.roomId});

  @override
  State<VideoCallScreen> createState() => _VideoCallScreenState();
}

class _VideoCallScreenState extends State<VideoCallScreen> {
  final SignalingService _signaling = SignalingService();
  final WebRTCService _webRTC = WebRTCService();
  final RecordingService _recordingService = RecordingService();

  bool _microphoneEnabled = true;
  bool _cameraEnabled = true;
  bool _isFrontCamera = true;
  bool _switchingCamera = false;
  bool _peerConnected = false;
  bool _starting = true;
  bool _cleanedUp = false;
  bool _recordingInProgress = false;
  bool _recordingConsentPending = false;
  bool _localRecordingConsent = false;
  bool _remoteRecordingConsent = false;

  String? _activeRecordingRequestId;
  Duration _recordingElapsed = Duration.zero;
  Timer? _recordingTimer;
  Timer? _recordingConsentTimer;

  RecordingServiceState _recordingState = RecordingServiceState.ready;
  String _statusMessage = 'Preparing your camera...';
  String _recordingMessage = 'Recording unavailable';

  final List<RTCIceCandidate> _pendingIceCandidates = [];

  bool _remoteDescriptionSet = false;
  int _remoteVideoVersion = 0;

  static const Color _background = Color(0xFF080B14);
  static const Color _surface = Color(0xFF111827);
  static const Color _cyan = Color(0xFF42E8F5);
  static const Color _purple = Color(0xFF9B7BFF);
  static const Color _success = Color(0xFF32C48D);

  @override
  void initState() {
    super.initState();
    _prepareRecordingAvailability();
    _startCall();
  }

  Future<void> _startCall() async {
    try {
      await _webRTC.initialize();
      await _webRTC.startLocalMedia();
      await _webRTC.setupPeerConnection();

      _setupSignalingCallbacks();

      if (mounted) {
        setState(() {
          _statusMessage = 'Connecting securely...';
        });
      }

      _signaling.connect(serverUrl: ServerConfig.signalingUrl);

      for (int i = 0; i < 50; i++) {
        if (_signaling.isConnected) break;

        await Future.delayed(const Duration(milliseconds: 100));
      }

      if (!_signaling.isConnected) {
        throw Exception('Could not connect to the server.');
      }

      final joined = await _signaling.joinRoom(widget.roomId);

      if (!joined) {
        throw Exception(
          'Unable to join this room. It may be full '
          'or the room ID may be invalid.',
        );
      }

      if (!mounted) return;

      setState(() {
        _starting = false;
        _statusMessage = 'Waiting for another participant';
      });

      debugPrint('[VideoCall] Joined ${widget.roomId}');
    } catch (error) {
      debugPrint('[VideoCall] Start error: $error');

      if (!mounted) return;

      setState(() {
        _starting = false;
        _statusMessage = 'Unable to start the call';
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('$error'),
          behavior: SnackBarBehavior.floating,
          backgroundColor: const Color(0xFFB93850),
        ),
      );
    }
  }

  void _setupSignalingCallbacks() {
    _webRTC.onRemoteStreamChanged = () {
      if (!mounted) return;

      setState(() {
        _remoteVideoVersion++;
        _statusMessage = 'Remote video stream received';
      });

      debugPrint(
        '[VideoCall] Rebuilding remote video view: '
        '$_remoteVideoVersion',
      );
    };

    _signaling.onRecordingConsentRequest = _handleRecordingConsentRequest;
    _signaling.onRecordingConsentResponse = _handleRecordingConsentResponse;
    _signaling.onRecordingConsentCancelled = _handleRecordingConsentCancelled;

    _signaling.onPeerJoined = () async {
      debugPrint('[VideoCall] Peer joined');

      if (mounted) {
        setState(() {
          _peerConnected = true;
          _statusMessage = 'Establishing video connection...';
        });
      }

      await _createAndSendOffer();
    };

    _signaling.onPeerLeft = () async {
      debugPrint('[VideoCall] Peer left');

      _remoteDescriptionSet = false;
      _pendingIceCandidates.clear();

      if (mounted) {
        setState(() {
          _peerConnected = false;
          _statusMessage = 'Participant left the room';
        });
      }

      try {
        await _webRTC.resetPeerConnection();
      } catch (error) {
        debugPrint('[VideoCall] Reset error: $error');
      }
    };

    _signaling.onOffer = (data) async {
      await _handleOffer(data);
    };

    _signaling.onAnswer = (data) async {
      await _handleAnswer(data);
    };

    _signaling.onIceCandidate = (data) async {
      await _handleIceCandidate(data);
    };

    _webRTC.onIceCandidate = (candidate) {
      _signaling.sendIceCandidate({
        'candidate': candidate.candidate,
        'sdpMid': candidate.sdpMid,
        'sdpMLineIndex': candidate.sdpMLineIndex,
      });
    };
  }

  Future<void> _createAndSendOffer() async {
    try {
      final offer = await _webRTC.createOffer();

      _signaling.sendOffer({'type': offer.type, 'sdp': offer.sdp});

      debugPrint('[VideoCall] Offer sent');
    } catch (error) {
      debugPrint('[VideoCall] Offer error: $error');
    }
  }

  Future<void> _inspectVideoAfterDelay() async {
    await Future<void>.delayed(const Duration(seconds: 5));

    if (!mounted || _cleanedUp) return;

    await _webRTC.logVideoStats();
  }

  Future<void> _handleOffer(dynamic data) async {
    try {
      if (data is! Map) return;

      final description = RTCSessionDescription(
        data['sdp'] as String?,
        data['type'] as String?,
      );

      await _webRTC.setRemoteDescription(description);
      _remoteDescriptionSet = true;
      await _flushPendingIceCandidates();

      final answer = await _webRTC.createAnswer();

      _signaling.sendAnswer({'type': answer.type, 'sdp': answer.sdp});

      if (mounted) {
        setState(() {
          _peerConnected = true;
          _statusMessage = 'Negotiating video and audio...';
        });
      }

      debugPrint('[VideoCall] Answer sent');
    } catch (error) {
      debugPrint('[VideoCall] Offer handling error: $error');
    }
    unawaited(_inspectVideoAfterDelay());
  }

  Future<void> _handleAnswer(dynamic data) async {
    try {
      if (data is! Map) return;

      final description = RTCSessionDescription(
        data['sdp'] as String?,
        data['type'] as String?,
      );

      await _webRTC.setRemoteDescription(description);
      _remoteDescriptionSet = true;
      await _flushPendingIceCandidates();

      if (mounted) {
        setState(() {
          _peerConnected = true;
          _statusMessage = 'Connecting media...';
        });
      }

      debugPrint('[VideoCall] Answer received');
    } catch (error) {
      debugPrint('[VideoCall] Answer handling error: $error');
    }
    unawaited(_inspectVideoAfterDelay());
  }

  Future<void> _handleIceCandidate(dynamic data) async {
    try {
      if (data is! Map) return;

      final candidate = RTCIceCandidate(
        data['candidate'] as String?,
        data['sdpMid'] as String?,
        data['sdpMLineIndex'] as int?,
      );

      _pendingIceCandidates.add(candidate);
      await _flushPendingIceCandidates();
    } catch (error) {
      debugPrint('[VideoCall] ICE error: $error');
    }
  }

  Future<void> _flushPendingIceCandidates() async {
    if (!_remoteDescriptionSet || _pendingIceCandidates.isEmpty) {
      return;
    }

    final candidates = List<RTCIceCandidate>.from(_pendingIceCandidates);

    _pendingIceCandidates.clear();

    for (final candidate in candidates) {
      try {
        await _webRTC.addIceCandidate(candidate);
      } catch (error) {
        debugPrint('[VideoCall] Candidate error: $error');

        // Retain candidates that failed so they can be retried.
        _pendingIceCandidates.add(candidate);
      }
    }
  }

  Future<void> _toggleMicrophone() async {
    final nextValue = !_microphoneEnabled;

    try {
      await _webRTC.toggleMicrophone(nextValue);

      if (mounted) {
        setState(() {
          _microphoneEnabled = nextValue;
        });
      }
    } catch (error) {
      debugPrint('[VideoCall] Microphone error: $error');
    }
  }

  Future<void> _toggleCamera() async {
    final nextValue = !_cameraEnabled;

    try {
      await _webRTC.toggleCamera(nextValue);

      if (mounted) {
        setState(() {
          _cameraEnabled = nextValue;
        });
      }
    } catch (error) {
      debugPrint('[VideoCall] Camera error: $error');
    }
  }

  Future<void> _flipCamera() async {
    if (_switchingCamera || !_cameraEnabled) return;

    setState(() => _switchingCamera = true);
    try {
      await _webRTC.switchCamera();
      if (!mounted) return;
      setState(() {
        _isFrontCamera = !_isFrontCamera;
        _remoteVideoVersion++;
      });
      debugPrint(
        '[VideoCall] Switched to ${_isFrontCamera ? 'front' : 'rear'} camera',
      );
    } catch (error) {
      debugPrint('[VideoCall] Camera flip unavailable: $error');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Camera switching is not supported by this device/browser.',
            ),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _switchingCamera = false);
    }
  }

  void _clearRecordingConsentTimer() {
    _recordingConsentTimer?.cancel();
    _recordingConsentTimer = null;
  }

  void _scheduleRecordingConsentTimeout() {
    _clearRecordingConsentTimer();
    final activeRequestId = _activeRecordingRequestId;
    if (activeRequestId == null || activeRequestId.isEmpty) return;

    _recordingConsentTimer = Timer(const Duration(seconds: 30), () {
      if (!mounted) return;
      if (_recordingState != RecordingServiceState.awaitingConsent) return;
      if (_activeRecordingRequestId != activeRequestId) return;

      _showRecordingMessage(
        'No response arrived from the other participant. Recording cancelled.',
        backgroundColor: const Color(0xFFB93850),
      );

      _signaling.sendRecordingConsentCancelled({
        'requestId': activeRequestId,
        'roomId': widget.roomId,
        'cancelled': true,
        'reason': 'timeout',
      });

      setState(() {
        _recordingConsentPending = false;
        _localRecordingConsent = false;
        _remoteRecordingConsent = false;
        _activeRecordingRequestId = null;
        _recordingState = RecordingServiceState.ready;
        _recordingMessage = 'Recording cancelled';
      });
    });
  }

  Future<void> _prepareRecordingAvailability() async {
    if (!_recordingService.isAndroid) {
      if (!mounted) return;
      setState(() {
        _recordingState = RecordingServiceState.unsupported;
        _recordingMessage = 'Recording is Android-only';
      });
      return;
    }

    final supported = await _recordingService.checkSupport();
    if (!mounted) return;

    setState(() {
      _recordingState = supported
          ? RecordingServiceState.ready
          : RecordingServiceState.unsupported;
      _recordingMessage = supported
          ? 'Ready to record'
          : 'Recording setup incomplete';
    });
  }

  Future<void> _copyRoomId() async {
    await Clipboard.setData(ClipboardData(text: widget.roomId));

    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Room ID copied'),
        behavior: SnackBarBehavior.floating,
        duration: Duration(seconds: 2),
      ),
    );
  }

  Future<void> _requestRecordingConsent() async {
    if (!_peerConnected) {
      _showRecordingMessage(
        'Recording is only available during an active call.',
      );
      return;
    }

    if (!_recordingService.isAndroid) {
      _showRecordingMessage('Recording is only available on Android.');
      return;
    }

    if (_recordingState == RecordingServiceState.recording ||
        _recordingState == RecordingServiceState.awaitingConsent) {
      _showRecordingMessage(
        'A recording is already in progress or pending consent.',
      );
      return;
    }

    final supported = await _recordingService.checkSupport();
    if (!supported) {
      _showRecordingMessage('Recording setup incomplete on this device.');
      setState(() {
        _recordingState = RecordingServiceState.unsupported;
        _recordingMessage = 'Recording setup incomplete';
      });
      return;
    }

    final requestId = DateTime.now().millisecondsSinceEpoch.toString();
    if (!mounted) return;
    // ignore: use_build_context_synchronously
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('Record this call?'),
        content: const Text(
          'Both participants must explicitly consent before recording begins. This app records the local microphone and the active call video stream; mixed two-person audio is not verified yet. The file is encrypted locally on this device only.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('I consent'),
          ),
        ],
      ),
    );

    if (confirmed != true) {
      _showRecordingMessage('Recording cancelled.');
      return;
    }

    setState(() {
      _recordingState = RecordingServiceState.awaitingConsent;
      _recordingMessage = 'Waiting for the other participant to consent...';
      _recordingConsentPending = true;
      _localRecordingConsent = true;
      _remoteRecordingConsent = false;
      _activeRecordingRequestId = requestId;
    });
    _scheduleRecordingConsentTimeout();

    _signaling.sendRecordingConsentRequest({
      'requestId': requestId,
      'roomId': widget.roomId,
      'initiator': 'local',
      'accepted': true,
    });
  }

  Future<void> _handleRecordingConsentRequest(Map<String, dynamic> data) async {
    final requestId = data['requestId']?.toString();
    if (requestId == null || requestId.isEmpty) {
      return;
    }

    if (_recordingState == RecordingServiceState.recording ||
        _recordingConsentPending) {
      _signaling.sendRecordingConsentResponse({
        'requestId': requestId,
        'accepted': false,
        'reason': 'busy',
        'roomId': widget.roomId,
      });
      return;
    }

    if (_activeRecordingRequestId != null &&
        _activeRecordingRequestId != requestId) {
      _signaling.sendRecordingConsentResponse({
        'requestId': requestId,
        'accepted': false,
        'reason': 'busy',
        'roomId': widget.roomId,
      });
      return;
    }

    _recordingConsentPending = true;
    _activeRecordingRequestId = requestId;
    _localRecordingConsent = false;
    _remoteRecordingConsent = false;
    setState(() {
      _recordingState = RecordingServiceState.awaitingConsent;
      _recordingMessage = 'Other participant wants to record this call';
    });
    _scheduleRecordingConsentTimeout();

    final accepted = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('Recording consent request'),
        content: const Text(
          'The other participant wants to record both video and audio from this call. This recording will be encrypted locally on the initiating device. Do you consent?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Decline'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Accept'),
          ),
        ],
      ),
    );

    if (accepted != true) {
      _clearRecordingConsentTimer();
      _recordingConsentPending = false;
      _activeRecordingRequestId = null;
      setState(() {
        _recordingState = RecordingServiceState.ready;
        _recordingMessage = 'Recording declined';
      });
      _signaling.sendRecordingConsentResponse({
        'requestId': requestId,
        'accepted': false,
        'reason': 'declined',
        'roomId': widget.roomId,
      });
      return;
    }

    _clearRecordingConsentTimer();
    _remoteRecordingConsent = true;
    _signaling.sendRecordingConsentResponse({
      'requestId': requestId,
      'accepted': true,
      'roomId': widget.roomId,
    });

    if (_localRecordingConsent) {
      _beginRecording();
    } else {
      setState(() {
        _recordingState = RecordingServiceState.awaitingConsent;
        _recordingMessage = 'Waiting for your local consent to finish';
      });
    }
  }

  Future<void> _handleRecordingConsentResponse(
    Map<String, dynamic> data,
  ) async {
    final requestId = data['requestId']?.toString();
    if (requestId == null ||
        requestId.isEmpty ||
        _activeRecordingRequestId != requestId) {
      return;
    }

    final accepted = data['accepted'] == true;
    if (!accepted) {
      _clearRecordingConsentTimer();
      _recordingConsentPending = false;
      _activeRecordingRequestId = null;
      setState(() {
        _recordingState = RecordingServiceState.ready;
        _recordingMessage = 'Remote participant declined recording';
      });
      _showRecordingMessage('The other participant declined recording.');
      return;
    }

    _clearRecordingConsentTimer();
    _remoteRecordingConsent = true;
    if (_localRecordingConsent) {
      _beginRecording();
    }
  }

  Future<void> _handleRecordingConsentCancelled(
    Map<String, dynamic> data,
  ) async {
    final requestId = data['requestId']?.toString();
    if (requestId == null ||
        requestId.isEmpty ||
        _activeRecordingRequestId != requestId) {
      return;
    }

    _clearRecordingConsentTimer();
    _recordingConsentPending = false;
    _activeRecordingRequestId = null;
    _localRecordingConsent = false;
    _remoteRecordingConsent = false;
    setState(() {
      _recordingState = RecordingServiceState.ready;
      _recordingMessage = 'Recording cancelled';
    });
    _showRecordingMessage('Recording cancelled by the other participant.');
  }

  Future<void> _beginRecording() async {
    if (_recordingState == RecordingServiceState.recording) {
      return;
    }

    if (!_localRecordingConsent || !_remoteRecordingConsent) {
      _showRecordingMessage(
        'Both participants must explicitly consent before recording.',
      );
      return;
    }

    try {
      await _recordingService.startRecording(
        localStream: _webRTC.localStream,
        remoteStream: _webRTC.remoteStream,
      );
      _recordingInProgress = true;
      _recordingConsentPending = false;
      _recordingState = RecordingServiceState.recording;
      _recordingMessage = 'Recording active';
      _recordingElapsed = Duration.zero;
      _recordingTimer?.cancel();
      _recordingTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (!mounted || !_recordingInProgress) return;
        setState(() => _recordingElapsed += const Duration(seconds: 1));
      });
      _showRecordingMessage(
        'Recording started. Local microphone capture and active call video are being recorded.',
        backgroundColor: _success,
      );
    } on PlatformException catch (error) {
      _recordingState = RecordingServiceState.failed;
      _recordingMessage = 'Recording setup incomplete';
      _recordingInProgress = false;
      _recordingConsentPending = false;
      _showRecordingMessage(
        'Recording setup incomplete: ${error.message ?? 'Native pipeline unavailable'}',
      );
    } catch (error) {
      _recordingState = RecordingServiceState.failed;
      _recordingMessage = 'Recording setup incomplete';
      _recordingInProgress = false;
      _recordingConsentPending = false;
      _showRecordingMessage('Recording setup incomplete.');
    }
  }

  Future<void> _toggleRecording() async {
    if (_recordingState == RecordingServiceState.recording) {
      await _stopRecording('User stopped recording.');
      return;
    }

    await _requestRecordingConsent();
  }

  Future<void> _stopRecording([String reason = 'Recording stopped']) async {
    if (!_recordingInProgress &&
        _recordingState != RecordingServiceState.awaitingConsent) {
      return;
    }

    try {
      final result = await _recordingService.stopRecording();
      _recordingTimer?.cancel();
      _recordingTimer = null;
      _recordingInProgress = false;
      _recordingConsentPending = false;
      _localRecordingConsent = false;
      _remoteRecordingConsent = false;
      _activeRecordingRequestId = null;
      _recordingState = RecordingServiceState.ready;
      _recordingElapsed = Duration.zero;
      _recordingMessage = 'Ready to record';
      _showRecordingMessage(
        result != null ? 'Recording saved: $result' : reason,
        backgroundColor: _success,
      );
    } catch (error) {
      _recordingState = RecordingServiceState.failed;
      _recordingMessage = 'Recording setup incomplete';
      _showRecordingMessage('Recording could not stop cleanly.');
    }
  }

  void _showRecordingMessage(
    String message, {
    Color backgroundColor = const Color(0xFFB93850),
    Duration duration = const Duration(seconds: 3),
  }) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        backgroundColor: backgroundColor,
        duration: duration,
      ),
    );
  }

  Future<void> _endCall() async {
    await _cleanup();

    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  Future<void> _cleanup() async {
    if (_cleanedUp) return;
    _cleanedUp = true;

    if (_recordingState == RecordingServiceState.awaitingConsent ||
        _recordingState == RecordingServiceState.recording) {
      final requestId =
          _activeRecordingRequestId ??
          DateTime.now().millisecondsSinceEpoch.toString();
      _signaling.sendRecordingConsentCancelled({
        'requestId': requestId,
        'roomId': widget.roomId,
        'cancelled': true,
      });
      if (_recordingInProgress) {
        try {
          await _recordingService.stopRecording();
        } catch (_) {}
      }
    }

    _recordingTimer?.cancel();
    _recordingTimer = null;
    _recordingInProgress = false;
    _recordingConsentPending = false;
    _localRecordingConsent = false;
    _remoteRecordingConsent = false;
    _activeRecordingRequestId = null;
    _recordingState = RecordingServiceState.ready;
    _recordingElapsed = Duration.zero;

    _signaling.leaveRoom();
    _signaling.disconnect();

    await _webRTC.dispose();
  }

  @override
  void dispose() {
    unawaited(_cleanup());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _background,
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF10182B), Color(0xFF080B14), Color(0xFF160D26)],
          ),
        ),
        child: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final isWide = constraints.maxWidth >= 760;

              return Column(
                children: [
                  _buildHeader(isWide),
                  Expanded(
                    child: Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal: isWide ? 32 : 14,
                        vertical: 12,
                      ),
                      child: _buildVideoStage(isWide),
                    ),
                  ),
                  _buildBottomPanel(isWide),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(bool isWide) {
    return Padding(
      padding: EdgeInsets.fromLTRB(isWide ? 32 : 18, 18, isWide ? 32 : 18, 8),
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(15),
              gradient: const LinearGradient(colors: [_cyan, _purple]),
              boxShadow: [
                BoxShadow(color: _cyan.withValues(alpha: 0.15), blurRadius: 22),
              ],
            ),
            child: const Icon(
              Icons.videocam_rounded,
              color: Colors.black,
              size: 27,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'STRANGER',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 2.2,
                    fontSize: 17,
                  ),
                ),
                Text(
                  'VIDEO CALL',
                  style: TextStyle(
                    color: _cyan.withValues(alpha: 0.85),
                    fontWeight: FontWeight.w600,
                    letterSpacing: 2.5,
                    fontSize: 9,
                  ),
                ),
              ],
            ),
          ),
          _buildStatusChip(),
        ],
      ),
    );
  }

  Widget _buildStatusChip() {
    final statusColor = _starting
        ? Colors.orangeAccent
        : _peerConnected
        ? _cyan
        : Colors.white54;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.055),
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(
              color: statusColor,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: statusColor.withValues(alpha: 0.5),
                  blurRadius: 8,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            _starting
                ? 'Connecting'
                : _peerConnected
                ? 'In room'
                : 'Waiting',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVideoStage(bool isWide) {
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: const Color(0xFF05070D),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: _cyan.withValues(alpha: 0.18)),
        boxShadow: [
          BoxShadow(
            color: _purple.withValues(alpha: 0.08),
            blurRadius: 35,
            spreadRadius: 1,
          ),
        ],
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          RTCVideoView(
            _webRTC.remoteRenderer,
            key: ValueKey('remote-video-$_remoteVideoVersion'),
            mirror: false,
            objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitContain,
          ),

          IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withValues(alpha: 0.40),
                    Colors.transparent,
                    Colors.transparent,
                    Colors.black.withValues(alpha: 0.55),
                  ],
                  stops: const [0, 0.23, 0.62, 1],
                ),
              ),
            ),
          ),

          if (!_peerConnected && !_starting) _buildWaitingOverlay(),

          if (_starting)
            Container(
              color: _background.withValues(alpha: 0.86),
              child: const Center(
                child: CircularProgressIndicator(
                  color: _cyan,
                  strokeWidth: 2.5,
                ),
              ),
            ),

          Positioned(
            top: 18,
            left: 18,
            child: _glassLabel(
              icon: Icons.people_alt_rounded,
              label: 'PRIVATE ROOM',
            ),
          ),

          Positioned(top: 16, right: 16, child: _buildLocalPreview(isWide)),

          Positioned(
            left: 18,
            right: 18,
            bottom: 18,
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _peerConnected
                            ? 'Your conversation'
                            : 'Your space to connect',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        _statusMessage,
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                _roomBadge(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWaitingOverlay() {
    return Container(
      color: _background.withValues(alpha: 0.94),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 330),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 94,
                  height: 94,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      colors: [
                        _cyan.withValues(alpha: 0.20),
                        _purple.withValues(alpha: 0.20),
                      ],
                    ),
                    border: Border.all(color: _cyan.withValues(alpha: 0.30)),
                  ),
                  child: const Icon(
                    Icons.person_search_rounded,
                    size: 43,
                    color: _cyan,
                  ),
                ),
                const SizedBox(height: 24),
                const Text(
                  'Your next connection awaits',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 21,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 10),
                const Text(
                  'Share your room ID with someone to start '
                  'a private video conversation.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white60,
                    height: 1.6,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 22),
                OutlinedButton.icon(
                  onPressed: _copyRoomId,
                  icon: const Icon(Icons.copy_rounded, size: 17),
                  label: const Text('Copy room ID'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: _cyan,
                    side: BorderSide(color: _cyan.withValues(alpha: 0.55)),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 14,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(15),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLocalPreview(bool isWide) {
    final width = isWide ? 190.0 : 116.0;
    final height = isWide ? 240.0 : 164.0;

    return Container(
      width: width,
      height: height,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: const Color(0xFF20283A),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _cyan.withValues(alpha: 0.75), width: 1.5),
        boxShadow: [
          BoxShadow(color: _cyan.withValues(alpha: 0.10), blurRadius: 20),
        ],
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (_cameraEnabled)
            RTCVideoView(
              _webRTC.localRenderer,
              mirror: true,
              objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
            )
          else
            const Center(
              child: Icon(
                Icons.videocam_off_rounded,
                size: 32,
                color: Colors.white70,
              ),
            ),
          Positioned(
            left: 7,
            right: 7,
            bottom: 7,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.65),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.person_rounded, color: _cyan, size: 13),
                  SizedBox(width: 5),
                  Flexible(
                    child: Text(
                      'You',
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _roomBadge() {
    return Material(
      color: Colors.white.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: _copyRoomId,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.key_rounded, color: _cyan, size: 16),
              const SizedBox(width: 7),
              Text(
                widget.roomId,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.6,
                ),
              ),
              const SizedBox(width: 7),
              const Icon(Icons.copy_rounded, color: Colors.white60, size: 14),
            ],
          ),
        ),
      ),
    );
  }

  Widget _glassLabel({required IconData icon, required String label}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.50),
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: _cyan, size: 15),
          const SizedBox(width: 7),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.1,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomPanel(bool isWide) {
    return Padding(
      padding: EdgeInsets.fromLTRB(isWide ? 32 : 18, 4, isWide ? 32 : 18, 22),
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: isWide ? 28 : 15,
          vertical: 17,
        ),
        decoration: BoxDecoration(
          color: _surface.withValues(alpha: 0.92),
          borderRadius: BorderRadius.circular(25),
          border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
        ),
        child: Row(
          children: [
            Expanded(
              child: _buildControl(
                icon: _microphoneEnabled
                    ? Icons.mic_rounded
                    : Icons.mic_off_rounded,
                label: _microphoneEnabled ? 'Mute' : 'Unmute',
                active: _microphoneEnabled,
                onTap: _toggleMicrophone,
              ),
            ),
            Expanded(
              child: _buildControl(
                icon: _cameraEnabled
                    ? Icons.videocam_rounded
                    : Icons.videocam_off_rounded,
                label: _cameraEnabled ? 'Camera' : 'Camera off',
                active: _cameraEnabled,
                onTap: _toggleCamera,
              ),
            ),
            Expanded(
              child: _buildControl(
                icon: _switchingCamera
                    ? Icons.hourglass_top_rounded
                    : Icons.flip_camera_android_rounded,
                label: _switchingCamera
                    ? 'Switching'
                    : (_isFrontCamera ? 'Rear camera' : 'Selfie camera'),
                active: true,
                onTap: _flipCamera,
              ),
            ),
            Expanded(child: _buildRecordControl()),
            Expanded(
              child: _buildControl(
                icon: Icons.copy_rounded,
                label: 'Room ID',
                active: true,
                onTap: _copyRoomId,
              ),
            ),
            Expanded(
              child: _buildControl(
                icon: Icons.phone_disabled_rounded,
                label: 'End call',
                active: false,
                destructive: true,
                onTap: _endCall,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRecordControl() {
    final isDisabled =
        !_recordingService.isAndroid ||
        !_peerConnected ||
        _starting ||
        _cleanedUp;
    final isRecording = _recordingState == RecordingServiceState.recording;
    final label = isRecording ? 'Stop' : 'Record';
    final icon = isRecording
        ? Icons.stop_circle_rounded
        : Icons.fiber_manual_record;

    return Semantics(
      button: true,
      label: label,
      child: Tooltip(
        message: _recordingMessage,
        child: InkWell(
          onTap: isDisabled ? null : _toggleRecording,
          borderRadius: BorderRadius.circular(18),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 4),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  width: 54,
                  height: 54,
                  decoration: BoxDecoration(
                    color: isRecording
                        ? const Color(0xFF552529)
                        : const Color(0xFF42E8F5).withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: isRecording
                          ? const Color(0xFFFF667A).withValues(alpha: 0.45)
                          : Colors.white.withValues(alpha: 0.10),
                    ),
                  ),
                  child: Icon(
                    icon,
                    color: isRecording
                        ? const Color(0xFFFF667A)
                        : const Color(0xFF42E8F5),
                    size: 22,
                  ),
                ),
                const SizedBox(height: 7),
                Text(
                  label,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: isDisabled ? Colors.white54 : Colors.white70,
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (isRecording ||
                    _recordingState == RecordingServiceState.awaitingConsent)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 7,
                          height: 7,
                          decoration: const BoxDecoration(
                            color: Colors.red,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 5),
                        Text(
                          isRecording
                              ? _formatElapsedTime(_recordingElapsed)
                              : 'Waiting',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 9,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _formatElapsedTime(Duration elapsed) {
    final seconds = elapsed.inSeconds;
    final minutes = seconds ~/ 60;
    final remainingSeconds = seconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${remainingSeconds.toString().padLeft(2, '0')}';
  }

  Widget _buildControl({
    required IconData icon,
    required String label,
    required bool active,
    required VoidCallback onTap,
    bool destructive = false,
  }) {
    final backgroundColor = destructive
        ? const Color(0xFF351820)
        : active
        ? const Color(0xFF42E8F5).withValues(alpha: 0.18)
        : Colors.white.withValues(alpha: 0.08);

    final foregroundColor = destructive
        ? const Color(0xFFFF667A)
        : active
        ? const Color(0xFF42E8F5)
        : Colors.white70;

    final borderColor = destructive
        ? const Color(0xFFFF667A).withValues(alpha: 0.45)
        : Colors.white.withValues(alpha: 0.10);

    return Semantics(
      button: true,
      label: label,
      child: Tooltip(
        message: label,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(18),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 4),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  width: 54,
                  height: 54,
                  decoration: BoxDecoration(
                    color: backgroundColor,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: borderColor),
                  ),
                  child: Icon(icon, color: foregroundColor, size: 23),
                ),
                const SizedBox(height: 9),
                Text(
                  label,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: destructive
                        ? const Color(0xFFFF8097)
                        : Colors.white70,
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
