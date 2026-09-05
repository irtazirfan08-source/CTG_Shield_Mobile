import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'map_screen.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  // Use http://127.0.0.1:8000 for Chrome, 10.0.2.2 for Android Emulator, or local Wi-Fi IP for phone
 static const String baseUrl = 'https://ctg-shield-backend.onrender.com';
  final FlutterSecureStorage _storage = const FlutterSecureStorage();

  bool isLogin = true;
  bool isLoading = false;

  final TextEditingController fullNameController = TextEditingController();
  final TextEditingController phoneController = TextEditingController();
  final TextEditingController emergencyContactController = TextEditingController();
  final TextEditingController passwordController = TextEditingController();

  String _extractErrorMessage(String responseBody, String defaultMessage) {
    try {
      final decoded = jsonDecode(responseBody);
      final detail = decoded['detail'];
      if (detail is String) {
        return detail;
      } else if (detail is List && detail.isNotEmpty) {
        final firstError = detail[0];
        if (firstError is Map && firstError.containsKey('msg')) {
          return firstError['msg'].toString();
        }
      }
    } catch (_) {}
    return defaultMessage;
  }

  Future<void> _submit() async {
    final phone = phoneController.text.trim();
    final password = passwordController.text.trim();

    if (phone.isEmpty || password.isEmpty) {
      _showSnackbar('Please fill in all required fields');
      return;
    }

    if (password.length < 6) {
      _showSnackbar('Password must be at least 6 characters long');
      return;
    }

    if (!isLogin && (fullNameController.text.trim().isEmpty || emergencyContactController.text.trim().isEmpty)) {
      _showSnackbar('Please provide your full name and an emergency contact');
      return;
    }

    setState(() => isLoading = true);

    try {
      if (isLogin) {
        // --- LOGIN REQUEST ---
        final response = await http.post(
          Uri.parse('$baseUrl/api/v1/auth/login'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'phone_number': phone,
            'password': password,
          }),
        );

        if (response.statusCode == 200) {
          final data = jsonDecode(response.body);
          await _saveSession(data);
          _navigateToMap();
        } else {
          final errorMessage = _extractErrorMessage(
            response.body,
            'Login failed. Check your phone number or password.',
          );
          _showSnackbar(errorMessage);
        }
      } else {
        // --- REGISTRATION REQUEST ---
        final response = await http.post(
          Uri.parse('$baseUrl/api/v1/auth/register'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'full_name': fullNameController.text.trim(),
            'phone_number': phone,
            'emergency_contact': emergencyContactController.text.trim(),
            'password': password,
          }),
        );

        if (response.statusCode == 201) {
          final data = jsonDecode(response.body);
          await _saveSession(data);
          _navigateToMap();
        } else {
          final errorMessage = _extractErrorMessage(
            response.body,
            'Registration failed. Please try again.',
          );
          _showSnackbar(errorMessage);
        }
      }
    } catch (e) {
      _showSnackbar('Unable to reach server at $baseUrl. Ensure the backend is running.');
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }

  Future<void> _saveSession(Map<String, dynamic> data) async {
    await _storage.write(key: 'access_token', value: data['access_token']);
    if (data['user'] != null) {
      await _storage.write(key: 'user_id', value: data['user']['id'].toString());
      await _storage.write(key: 'user_name', value: data['user']['full_name']);
      await _storage.write(key: 'user_phone', value: data['user']['phone_number']);
      await _storage.write(key: 'emergency_contact', value: data['user']['emergency_contact']);
    }
  }

  void _navigateToMap() {
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (context) => const CTGMapScreen()),
    );
  }

  void _showSnackbar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.redAccent,
        duration: const Duration(seconds: 4),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Icon(Icons.shield_outlined, size: 72, color: Color(0xFF3B82F6)),
                const SizedBox(height: 12),
                const Text(
                  'CTG SHIELD',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 2,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  isLogin ? 'Sign in to access verified SOS dispatch' : 'Register for the Chittagong Safety Network',
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 14, color: Colors.blueGrey),
                ),
                const SizedBox(height: 32),

                if (!isLogin) ...[
                  _buildInputField(
                    controller: fullNameController,
                    label: 'Full Name',
                    icon: Icons.person_outline,
                  ),
                  const SizedBox(height: 16),
                ],

                _buildInputField(
                  controller: phoneController,
                  label: 'Phone Number',
                  icon: Icons.phone_outlined,
                  keyboardType: TextInputType.phone,
                ),
                const SizedBox(height: 16),

                if (!isLogin) ...[
                  _buildInputField(
                    controller: emergencyContactController,
                    label: 'Emergency Guardian Contact',
                    icon: Icons.contact_phone_outlined,
                    keyboardType: TextInputType.phone,
                  ),
                  const SizedBox(height: 16),
                ],

                _buildInputField(
                  controller: passwordController,
                  label: 'Password (min. 6 characters)',
                  icon: Icons.lock_outline,
                  obscureText: true,
                ),
                const SizedBox(height: 24),

                ElevatedButton(
                  onPressed: isLoading ? null : _submit,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF3B82F6),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  child: isLoading
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : Text(
                          isLogin ? 'SIGN IN' : 'CREATE ACCOUNT',
                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                ),
                const SizedBox(height: 16),

                TextButton(
                  onPressed: () => setState(() => isLogin = !isLogin),
                  child: Text(
                    isLogin
                        ? "Don't have an account? Register"
                        : 'Already registered? Sign In',
                    style: const TextStyle(color: Color(0xFF60A5FA)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildInputField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    bool obscureText = false,
    TextInputType keyboardType = TextInputType.text,
  }) {
    return TextField(
      controller: controller,
      obscureText: obscureText,
      keyboardType: keyboardType,
      style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: Colors.blueGrey),
        prefixIcon: Icon(icon, color: const Color(0xFF3B82F6)),
        filled: true,
        fillColor: const Color(0xFF1E293B),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: Color(0xFF334155)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: Color(0xFF3B82F6), width: 1.5),
        ),
      ),
    );
  }
}