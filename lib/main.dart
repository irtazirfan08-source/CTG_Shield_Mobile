import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'map_screen.dart';
import 'auth_screen.dart';

void main() {
  runApp(const CTGShieldApp());
}

class CTGShieldApp extends StatelessWidget {
  const CTGShieldApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'CTG Shield',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF0F172A),
        primaryColor: const Color(0xFF3B82F6),
      ),
      home: const SessionCheckScreen(),
    );
  }
}

class SessionCheckScreen extends StatefulWidget {
  const SessionCheckScreen({super.key});

  @override
  State<SessionCheckScreen> createState() => _SessionCheckScreenState();
}

class _SessionCheckScreenState extends State<SessionCheckScreen> {
  final FlutterSecureStorage _storage = const FlutterSecureStorage();

  @override
  void initState() {
    super.initState();
    _checkExistingSession();
  }

  Future<void> _checkExistingSession() async {
    final token = await _storage.read(key: 'access_token');
    if (!mounted) return;

    if (token != null && token.isNotEmpty) {
      // User already logged in -> open Radar screen immediately
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => const CTGMapScreen()),
      );
    } else {
      // No active token -> prompt login/registration
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => const AuthScreen()),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: Color(0xFF0F172A),
      body: Center(
        child: CircularProgressIndicator(color: Color(0xFF3B82F6)),
      ),
    );
  }
}