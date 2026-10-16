import 'package:flutter/material.dart';

import 'screens/create_room_screen.dart';
import 'screens/join_room_screen.dart';
import 'package:flutter/foundation.dart';
import 'package:url_launcher/url_launcher.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  FlutterError.onError = (FlutterErrorDetails details) {
    FlutterError.presentError(details);
    debugPrint('Flutter error: ${details.exception}');
  };

  runApp(const StrangerVideoCallApp());
}

class StrangerVideoCallApp extends StatelessWidget {
  const StrangerVideoCallApp({super.key});

  static const Color background = Color(0xFF080B14);
  static const Color surface = Color(0xFF111827);
  static const Color cyan = Color(0xFF42E8F5);
  static const Color purple = Color(0xFF9B7BFF);

  @override
  Widget build(BuildContext context) {
    final scheme = ColorScheme.fromSeed(
      seedColor: purple,
      brightness: Brightness.dark,
      surface: surface,
    );

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Stranger Video Call',
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorScheme: scheme,
        scaffoldBackgroundColor: background,
        appBarTheme: const AppBarTheme(
          backgroundColor: background,
          foregroundColor: Colors.white,
          centerTitle: false,
        ),
        snackBarTheme: const SnackBarThemeData(
          behavior: SnackBarBehavior.floating,
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            backgroundColor: cyan,
            foregroundColor: const Color(0xFF071016),
            minimumSize: const Size(0, 58),
            textStyle: const TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 16,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(17),
            ),
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            foregroundColor: Colors.white,
            minimumSize: const Size(0, 58),
            side: BorderSide(color: purple.withValues(alpha: 0.65)),
            textStyle: const TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 16,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(17),
            ),
          ),
        ),
      ),
      home: const HomeScreen(),
    );
  }
}

Future<void> downloadAndroidApk(BuildContext context) async {
  final uri = Uri.parse(
    'https://github.com/debraj2821L/'
    'Stranger-Video-Calling/releases/latest/download/'
    'stranger-video-call.apk',
  );

  try {
    final launched = await launchUrl(uri, mode: LaunchMode.platformDefault);

    if (!launched && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Could not open the APK download link. Please try again.',
          ),
        ),
      );
    }
  } catch (error) {
    debugPrint('APK download link error: $error');
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Unable to open the download link. Please try again.'),
        ),
      );
    }
  }
}

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  static const Color cyan = StrangerVideoCallApp.cyan;
  static const Color purple = StrangerVideoCallApp.purple;

  void _openScreen(BuildContext context, Widget screen) {
    Navigator.of(context)
        .push(MaterialPageRoute<void>(builder: (_) => screen))
        .catchError((Object error, StackTrace stackTrace) {
          debugPrint('Navigation error: $error');
        });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF121B30), Color(0xFF080B14), Color(0xFF160D26)],
          ),
        ),
        child: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              return Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 28,
                  ),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 440),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _buildLogo(),
                        const SizedBox(height: 30),

                        const Text(
                          'Stranger Video Call',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 30,
                            height: 1.2,
                            fontWeight: FontWeight.w900,
                            letterSpacing: -0.8,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 13),

                        Text(
                          'Meet someone new. Start a conversation.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.68),
                            fontSize: 15,
                            height: 1.6,
                          ),
                        ),
                        const SizedBox(height: 34),

                        _buildFeatureStrip(),
                        const SizedBox(height: 30),

                        _buildCreateButton(context),
                        const SizedBox(height: 14),

                        _buildJoinButton(context),
                        if (kIsWeb) ...[
                          const SizedBox(height: 14),
                          _buildInstallButton(context),
                        ],
                        const SizedBox(height: 26),

                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.035),
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.08),
                            ),
                          ),
                          child: const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.shield_outlined,
                                color: cyan,
                                size: 19,
                              ),
                              SizedBox(width: 9),
                              Flexible(
                                child: Text(
                                  'No account required • Private rooms',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    color: Colors.white70,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 24),

                        Text(
                          'MEET  ·  TALK  ·  CONNECT',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: purple.withValues(alpha: 0.9),
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 2.4,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildLogo() {
    return Container(
      width: 112,
      height: 112,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(34),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [cyan, purple],
        ),
        boxShadow: [
          BoxShadow(
            color: cyan.withValues(alpha: 0.16),
            blurRadius: 35,
            spreadRadius: 1,
          ),
        ],
      ),
      child: const Icon(
        Icons.video_call_rounded,
        color: Color(0xFF080B14),
        size: 67,
      ),
    );
  }

  Widget _buildFeatureStrip() {
    return Row(
      children: [
        Expanded(child: _feature(Icons.flash_on_rounded, 'Instant')),
        const SizedBox(width: 10),
        Expanded(child: _feature(Icons.lock_outline_rounded, 'Private room')),
        const SizedBox(width: 10),
        Expanded(child: _feature(Icons.videocam_outlined, 'Live video')),
      ],
    );
  }

  Widget _feature(IconData icon, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 15),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.045),
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: Colors.white.withValues(alpha: 0.07)),
      ),
      child: Column(
        children: [
          Icon(icon, color: cyan, size: 22),
          const SizedBox(height: 9),
          Text(
            label,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 10,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCreateButton(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: FilledButton.icon(
        onPressed: () {
          _openScreen(context, const CreateRoomScreen());
        },
        icon: const Icon(Icons.add_rounded, size: 23),
        label: const Text('Create a room'),
      ),
    );
  }

  Widget _buildJoinButton(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: () {
          _openScreen(context, const JoinRoomScreen());
        },
        icon: const Icon(Icons.login_rounded, size: 21),
        label: const Text('Join with Room ID'),
      ),
    );
  }

  Widget _buildInstallButton(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: FilledButton.icon(
        onPressed: () => downloadAndroidApk(context),
        icon: const Icon(Icons.android_rounded, size: 25),
        label: const Text('Install on Phone'),
        style: FilledButton.styleFrom(
          backgroundColor: const Color(0xFFB8F36B),
          foregroundColor: const Color(0xFF10170A),
          minimumSize: const Size(0, 58),
          textStyle: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(17),
          ),
        ),
      ),
    );
  }
}
