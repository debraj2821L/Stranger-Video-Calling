import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import '../services/recording_service.dart';

class RecordingsScreen extends StatefulWidget {
  const RecordingsScreen({super.key});

  @override
  State<RecordingsScreen> createState() => _RecordingsScreenState();
}

class RecordingListItem {
  const RecordingListItem({
    required this.name,
    required this.sizeBytes,
    required this.modifiedAt,
  });

  final String name;
  final int sizeBytes;
  final DateTime modifiedAt;
}

class _RecordingsScreenState extends State<RecordingsScreen> {
  final RecordingService _service = RecordingService();

  bool _loading = false;
  String? _error;
  List<RecordingListItem> _items = const [];

  @override
  void initState() {
    super.initState();
    _loadRecordings();
  }

  Future<void> _loadRecordings() async {
    if (!_service.isAndroid) {
      setState(() {
        _loading = false;
        _error = 'Encrypted recordings are Android-only.';
        _items = const [];
      });
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final names = await _service.listRecordings();
      final recordings = <RecordingListItem>[];

      for (final name in names) {
        try {
          final documentsDirectory = await getApplicationDocumentsDirectory();
          final file = File('${documentsDirectory.path}/$name');
          if (!file.existsSync()) {
            continue;
          }
          recordings.add(
            RecordingListItem(
              name: name,
              sizeBytes: file.lengthSync(),
              modifiedAt: DateTime.fromMillisecondsSinceEpoch(
                file.lastModifiedSync().millisecondsSinceEpoch,
              ),
            ),
          );
        } catch (_) {
          // Ignore unreadable file entries.
        }
      }

      if (!mounted) return;
      setState(() {
        _loading = false;
        _items = recordings;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Unable to load recordings: $error';
      });
    }
  }

  Future<void> _preparePlayback(RecordingListItem item) async {
    try {
      final path = await _service.preparePlayback(item.name);
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Playback path prepared: $path'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Playback unavailable: $error'),
          behavior: SnackBarBehavior.floating,
          backgroundColor: const Color(0xFFB93850),
        ),
      );
    }
  }

  Future<void> _deleteRecording(RecordingListItem item) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete recording?'),
        content: Text(
          'Delete ${item.name}? This removes the encrypted recording from local storage.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      final ok = await _service.deleteRecording(item.name);
      if (ok) {
        if (!mounted) return;
        setState(() {
          _items.removeWhere((entry) => entry.name == item.name);
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Recording deleted.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      } else {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not delete recording.'),
            behavior: SnackBarBehavior.floating,
            backgroundColor: Color(0xFFB93850),
          ),
        );
      }
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Delete failed: $error'),
          behavior: SnackBarBehavior.floating,
          backgroundColor: const Color(0xFFB93850),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Recordings'), centerTitle: true),
      body: SafeArea(child: _buildBody()),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 12),
            Text('Loading encrypted recordings...'),
          ],
        ),
      );
    }

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(_error!, textAlign: TextAlign.center),
        ),
      );
    }

    if (_items.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'No encrypted recordings yet.\n\nRecordings are stored locally on this device and are never uploaded.',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadRecordings,
      child: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: _items.length,
        separatorBuilder: (_, _) => const SizedBox(height: 12),
        itemBuilder: (context, index) {
          final item = _items[index];
          final sizeLabel = _formatBytes(item.sizeBytes);
          final dateLabel = _formatDate(item.modifiedAt);

          return Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.03),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: Colors.white.withValues(alpha: 0.07)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.videocam_outlined),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.name,
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '$dateLabel • $sizeLabel',
                        style: const TextStyle(color: Colors.white70),
                      ),
                    ],
                  ),
                ),
                Row(
                  children: [
                    IconButton(
                      onPressed: () => _preparePlayback(item),
                      icon: const Icon(Icons.play_arrow_rounded),
                      tooltip: 'Prepare playback',
                    ),
                    IconButton(
                      onPressed: () => _deleteRecording(item),
                      icon: const Icon(Icons.delete_outline_rounded),
                      tooltip: 'Delete recording',
                    ),
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  String _formatDate(DateTime value) {
    return '${value.day.toString().padLeft(2, '0')}/${value.month.toString().padLeft(2, '0')}/${value.year}';
  }
}
