import 'package:socket_io_client/socket_io_client.dart' as io;

class SignalingService {
  io.Socket? _socket;

  String? _roomId;

  Function()? onPeerJoined;
  Function()? onPeerLeft;

  Function(dynamic data)? onOffer;
  Function(dynamic data)? onAnswer;
  Function(dynamic data)? onIceCandidate;
  Function(Map<String, dynamic> data)? onRecordingConsentRequest;
  Function(Map<String, dynamic> data)? onRecordingConsentResponse;
  Function(Map<String, dynamic> data)? onRecordingConsentCancelled;

  bool get isConnected => _socket?.connected ?? false;

  String? get roomId => _roomId;

  void connect({required String serverUrl}) {
    if (_socket != null) {
      if (!_socket!.connected) {
        _socket!.connect();
      }
      return;
    }

    _socket = io.io(
      serverUrl,
      io.OptionBuilder()
          .setTransports(['websocket'])
          .disableAutoConnect()
          .build(),
    );

    _socket!.onConnect((_) {
      _log('Connected to signaling server');
      _log('Socket ID: ${_socket!.id}');
    });

    _socket!.onDisconnect((_) {
      _log('Disconnected from signaling server');
    });

    _socket!.onConnectError((error) {
      _log('Connection error: $error');
    });

    _socket!.onError((error) {
      _log('Socket error: $error');
    });

    _socket!.on('peer-joined', (_) {
      _log('Peer joined room');
      onPeerJoined?.call();
    });

    _socket!.on('peer-left', (_) {
      _log('Peer left room');
      onPeerLeft?.call();
    });

    _socket!.on('offer', (data) {
      _log('Received WebRTC offer');
      onOffer?.call(data);
    });

    _socket!.on('answer', (data) {
      _log('Received WebRTC answer');
      onAnswer?.call(data);
    });

    _socket!.on('ice-candidate', (data) {
      _log('Received ICE candidate');
      onIceCandidate?.call(data);
    });

    _socket!.on('recording-consent-request', (data) {
      if (data is Map) {
        _log('Recording consent requested');
        onRecordingConsentRequest?.call(Map<String, dynamic>.from(data));
      }
    });

    _socket!.on('recording-consent-response', (data) {
      if (data is Map) {
        _log('Recording consent response received');
        onRecordingConsentResponse?.call(Map<String, dynamic>.from(data));
      }
    });

    _socket!.on('recording-consent-cancelled', (data) {
      if (data is Map) {
        _log('Recording consent cancelled');
        onRecordingConsentCancelled?.call(Map<String, dynamic>.from(data));
      }
    });

    _socket!.connect();
  }

  Future<bool> joinRoom(String roomId) async {
    if (_socket == null) {
      _log('Socket is not initialized');
      return false;
    }

    if (!_socket!.connected) {
      _log('Socket is not connected');
      return false;
    }

    _roomId = roomId;

    try {
      final response = await _socket!.emitWithAckAsync('join-room', roomId);

      _log('Join response: $response');

      if (response == null) {
        return false;
      }

      if (response is Map) {
        if (response['success'] == true) {
          _log('Successfully joined: $roomId');
          return true;
        }

        _log('Failed to join: ${response['message']}');

        return false;
      }

      return false;
    } catch (error) {
      _log('Join room error: $error');
      return false;
    }
  }

  void sendOffer(dynamic data) {
    if (_socket?.connected != true) {
      return;
    }

    _socket!.emit('offer', data);
    _log('WebRTC offer sent');
  }

  void sendAnswer(dynamic data) {
    if (_socket?.connected != true) {
      return;
    }

    _socket!.emit('answer', data);
    _log('WebRTC answer sent');
  }

  void sendIceCandidate(dynamic data) {
    if (_socket?.connected != true) {
      return;
    }

    _socket!.emit('ice-candidate', data);
    _log('ICE candidate sent');
  }

  void sendRecordingConsentRequest(Map<String, dynamic> data) {
    if (_socket?.connected != true) {
      return;
    }

    _socket!.emit('recording-consent-request', data);
    _log('Recording consent request sent');
  }

  void sendRecordingConsentResponse(Map<String, dynamic> data) {
    if (_socket?.connected != true) {
      return;
    }

    _socket!.emit('recording-consent-response', data);
    _log('Recording consent response sent');
  }

  void sendRecordingConsentCancelled(Map<String, dynamic> data) {
    if (_socket?.connected != true) {
      return;
    }

    _socket!.emit('recording-consent-cancelled', data);
    _log('Recording consent cancelled event sent');
  }

  void leaveRoom() {
    if (_socket?.connected == true) {
      _socket!.emit('leave-room');
    }

    _roomId = null;
    _log('Left room');
  }

  void disconnect() {
    if (_socket == null) {
      return;
    }

    _log('Disconnecting socket');

    _socket!.disconnect();
    _socket!.dispose();

    _socket = null;
    _roomId = null;
  }

  void _log(String message) {
    // Logging can be enabled during development.
    // ignore: avoid_print
    print('[Signaling] $message');
  }
}
