import 'package:flutter/material.dart';

import 'video_call_screen.dart';

class JoinRoomScreen extends StatefulWidget {
  const JoinRoomScreen({super.key});

  @override
  State<JoinRoomScreen> createState() => _JoinRoomScreenState();
}

class _JoinRoomScreenState extends State<JoinRoomScreen> {
  final TextEditingController _roomController = TextEditingController();

  bool _isJoining = false;
  bool _joined = false;

  @override
  void dispose() {
    super.dispose();
  }

  Future<void> _joinRoom() async {
    if (_isJoining) return;

    final roomId = _roomController.text.trim().toUpperCase();

    if (roomId.isEmpty) {
      _showError('Please enter a Room ID.');
      return;
    }

    if (!_isValidRoomId(roomId)) {
      _showError('Invalid Room ID format.');
      return;
    }

    setState(() {
      _isJoining = true;
    });

    // The actual server join happens in VideoCallScreen.
    await Future<void>.delayed(Duration.zero);

    if (!mounted) return;

    setState(() {
      _isJoining = false;
      _joined = true;
    });
  }

  bool _isValidRoomId(String roomId) {
    final pattern = RegExp(r'^[A-Z2-9]{4}-[A-Z2-9]{4}$');

    return pattern.hasMatch(roomId);
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red.shade700),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Join Room'), centerTitle: true),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: _joined ? _buildJoinedView() : _buildJoinView(),
        ),
      ),
    );
  }

  Widget _buildJoinView() {
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
            Icons.login_rounded,
            size: 60,
            color: Colors.deepPurpleAccent,
          ),
        ),

        const SizedBox(height: 30),

        const Text(
          'Join a Private Room',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
        ),

        const SizedBox(height: 12),

        Text(
          'Enter the Room ID shared by the other person.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 15, color: Colors.grey.shade400),
        ),

        const SizedBox(height: 40),

        TextField(
          controller: _roomController,
          enabled: !_isJoining,
          textCapitalization: TextCapitalization.characters,
          textAlign: TextAlign.center,
          maxLength: 9,
          style: const TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
            letterSpacing: 3,
          ),
          decoration: InputDecoration(
            counterText: '',
            hintText: 'XXXX-XXXX',
            prefixIcon: const Icon(Icons.key_rounded),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
          ),
          onSubmitted: (_) => _joinRoom(),
        ),

        const SizedBox(height: 25),

        SizedBox(
          width: double.infinity,
          height: 58,
          child: FilledButton.icon(
            onPressed: _isJoining ? null : _joinRoom,
            icon: _isJoining
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.video_call),
            label: Text(
              _isJoining ? 'Joining Room...' : 'Join Video Call',
              style: const TextStyle(fontSize: 17),
            ),
          ),
        ),

        const Spacer(),

        Text(
          'No login • No account • Anonymous',
          style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
        ),
      ],
    );
  }

  Widget _buildJoinedView() {
    return Column(
      children: [
        const Spacer(),

        const Icon(Icons.check_circle_rounded, size: 90, color: Colors.green),

        const SizedBox(height: 25),

        const Text(
          'Room Joined',
          style: TextStyle(fontSize: 30, fontWeight: FontWeight.bold),
        ),

        const SizedBox(height: 12),

        Text(
          _roomController.text.trim().toUpperCase(),
          style: const TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
            letterSpacing: 3,
          ),
        ),

        const SizedBox(height: 25),

        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.green.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(14),
          ),
          child: const Row(
            children: [
              Icon(Icons.check_circle_outline, color: Colors.green),
              SizedBox(width: 12),
              Expanded(child: Text('Successfully connected to the room.')),
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
                  builder: (_) => VideoCallScreen(
                    roomId: _roomController.text.trim().toUpperCase(),
                  ),
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
