import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'home_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final TextEditingController _loginController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  bool _isLoading = false;
  String? _errorMessage;

  bool _isPhoneNumber(String input) {
    return RegExp(r'^\d{10}$').hasMatch(input);
  }

  void _login() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final login = _loginController.text.trim();
      final password = _passwordController.text;

      if (login.isEmpty || password.isEmpty) {
        setState(() {
          _errorMessage = 'Please enter both login and password.';
          _isLoading = false;
        });
        return;
      }

      QuerySnapshot query;
      if (_isPhoneNumber(login)) {
        query = await _firestore
            .collection('user')
            .where('number', isEqualTo: int.parse(login))
            .limit(1)
            .get();
      } else {
        query = await _firestore
            .collection('user')
            .where('mail', isEqualTo: login)
            .limit(1)
            .get();
      }

      if (query.docs.isEmpty) {
        setState(() {
          _errorMessage = 'No user found with this login.';
        });
      } else {
        final doc = query.docs.first;
        final data = doc.data() as Map<String, dynamic>;

        if (data['password'] == password) {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
                builder: (_) => HomeScreen(userId: doc['userId'])),
          );
        } else {
          setState(() {
            _errorMessage = 'Incorrect password.';
          });
        }
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Login error: ${e.toString()}';
      });
    } finally {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Login')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          children: [
            const SizedBox(height: 40),
            TextField(
              controller: _loginController,
              decoration: const InputDecoration(
                labelText: 'Email or Phone Number',
              ),
              keyboardType: TextInputType.text,
            ),
            const SizedBox(height: 20),
            TextField(
              controller: _passwordController,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'Password'),
            ),
            const SizedBox(height: 30),
            if (_errorMessage != null)
              Text(_errorMessage!, style: const TextStyle(color: Colors.red)),
            const SizedBox(height: 10),
            ElevatedButton(
              onPressed: _isLoading ? null : _login,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                minimumSize: const Size.fromHeight(50),
              ),
              child: _isLoading
                  ? const CircularProgressIndicator(color: Colors.white)
                  : const Text('Login'),
            ),
          ],
        ),
      ),
    );
  }
}
