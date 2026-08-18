import 'package:flutter/material.dart';
import 'map_screen.dart';

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
      home: const CTGMapScreen(),
    );
  }
}