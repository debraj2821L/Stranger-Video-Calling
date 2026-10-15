import 'package:flutter/material.dart';

import 'video_call_screen.dart';

class CreateRoomScreen extends StatefulWidget {
  const CreateRoomScreen({super.key});

  @override
  State<CreateRoomScreen> createState() => _CreateRoomScreenState();
}

class _CreateRoomScreenState extends State<CreateRoomScreen> {
  String? _roomId;
  bool _isConnecting = false;
  bool _roomCreated = false;

  @override
  @override
  void dispose() {
    super.dispose();
  }

  Future<void> _createRoom() async {
    if (_isConnecting) return;

    setState(() {
      _isConnecting = true;
    });

    try {
      final roomId = _generateRoomId();

      if (!mounted) return;

      setState(() {
        _roomId = roomId;
        _roomCreated = true;
        _isConnecting = false;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _isConnecting = false;
      });

      _showError('Could not create room: $e');
    }
  }

  String _generateRoomId() {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';

    final random = DateTime.now().microsecondsSinceEpoch;

    String part(int length, int offset) {
      return List.generate(length, (index) {
        final value = (random + offset + index * 37) % chars.length;

        return chars[value];
      }).join();
    }

    return '${part(4, 17)}-${part(4, 53)}';
  }

  void _copyRoomId() {
    if (_roomId == null) return;

    // Clipboard functionality will be added next.
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Room ID ready to share')));
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red.shade700),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Create Room'), centerTitle: true),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: !_roomCreated ? _buildCreateView() : _buildRoomView(),
        ),
      ),
    );
  }

  Widget _buildCreateView() {
    return Column(
      children: [
        const Spacer(),

        Container(
          width: 110,
          height: 110,
          decoration: BoxDecoration(
            color: Colors.deepPurple.withValues(alpha: 0.15),
            shape: BoxShape.circle,
          ),
          child: const Icon(
            Icons.video_call_rounded,
            size: 60,
            color: Colors.deepPurpleAccent,
          ),
        ),

        const SizedBox(height: 30),

        const Text(
          'Create a Private Room',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
        ),

        const SizedBox(height: 12),

        Text(
          'Create a temporary room and share its ID with another person.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 15, color: Colors.grey.shade400),
        ),

        const SizedBox(height: 45),

        SizedBox(
          width: double.infinity,
          height: 58,
          child: FilledButton.icon(
            onPressed: _isConnecting ? null : _createRoom,
            icon: _isConnecting
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.add_circle_outline),
            label: Text(
              _isConnecting ? 'Creating Room...' : 'Create Room',
              style: const TextStyle(fontSize: 17),
            ),
          ),
        ),

        const Spacer(),

        Text(
          'No login • No account • Temporary room',
          style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
        ),
      ],
    );
  }

  Widget _buildRoomView() {
    return Column(
      children: [
        const Spacer(),

        const Icon(
          Icons.meeting_room_rounded,
          size: 75,
          color: Colors.deepPurpleAccent,
        ),

        const SizedBox(height: 22),

        const Text(
          'Room Created',
          style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
        ),

        const SizedBox(height: 10),

        Text(
          'Share this Room ID with the person you want to call.',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.grey.shade400, fontSize: 15),
        ),

        const SizedBox(height: 30),

        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 25),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.deepPurpleAccent, width: 1.5),
          ),
          child: Column(
            children: [
              Text(
                'ROOM ID',
                style: TextStyle(
                  fontSize: 12,
                  letterSpacing: 2,
                  color: Colors.grey.shade500,
                ),
              ),

              const SizedBox(height: 12),

              Text(
                _roomId ?? '',
                style: const TextStyle(
                  fontSize: 30,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 4,
                ),
              ),

              const SizedBox(height: 18),

              OutlinedButton.icon(
                onPressed: _copyRoomId,
                icon: const Icon(Icons.copy),
                label: const Text('Copy Room ID'),
              ),
            ],
          ),
        ),

        const SizedBox(height: 25),

        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.orange.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            children: [
              const Icon(Icons.info_outline, color: Colors.orange),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Waiting for another person to join...',
                  style: TextStyle(color: Colors.orange.shade200),
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 25),

        SizedBox(
          width: double.infinity,
          height: 55,
          child: FilledButton.icon(
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => VideoCallScreen(roomId: _roomId!),
                ),
              );
            },
            icon: const Icon(Icons.video_call),
            label: const Text(
              'Enter Video Room',
              style: TextStyle(fontSize: 17),
            ),
          ),
        ),

        const Spacer(),
      ],
    );
  }
}
